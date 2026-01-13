import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_constants.dart';
import '../../../services/wallet_service.dart';
import '../../../services/blockchain_service.dart';
import '../../../core/providers/market_provider.dart';

class ReceivePage extends ConsumerStatefulWidget {
  final String? initialCoin;
  
  const ReceivePage({super.key, this.initialCoin});

  @override
  ConsumerState<ReceivePage> createState() => _ReceivePageState();
}

class _ReceivePageState extends ConsumerState<ReceivePage> with SingleTickerProviderStateMixin {
  final WalletService _walletService = WalletService();
  final BlockchainService _blockchainService = BlockchainService();
  final Map<String, String?> _addresses = {};
  final Map<String, List<String>> _storedLists = {};
  final Map<String, double> _balances = {};
  bool _loading = true;
  bool _loadingBalance = false;
  bool _generatingAddress = false;
  String _selectedCoin = 'BTC';
  
  // Animation controller for loading
  late AnimationController _animationController;

  final List<Map<String, dynamic>> _supportedCoins = [
    {'symbol': 'BTC', 'name': 'Bitcoin', 'icon': Icons.currency_bitcoin, 'color': Color(0xFFF7931A)},
    {'symbol': 'ETH', 'name': 'Ethereum', 'icon': Icons.currency_exchange, 'color': Color(0xFF627EEA)},
    {'symbol': 'BNB', 'name': 'BNB (BSC)', 'icon': Icons.currency_exchange, 'color': Color(0xFFF3BA2F)},
    {'symbol': 'USDT-ERC20', 'name': 'Tether (ERC20)', 'icon': Icons.attach_money, 'color': Color(0xFF26A17B)},
    {'symbol': 'USDT-BEP20', 'name': 'Tether (BEP20)', 'icon': Icons.attach_money, 'color': Color(0xFF26A17B)},
    {'symbol': 'USDT-TRC20', 'name': 'Tether (TRC20)', 'icon': Icons.attach_money, 'color': Color(0xFF26A17B)},
  ];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
    
    // Set initial coin from parameter
    print('🔵 ReceivePage initialCoin: ${widget.initialCoin}');
    if (widget.initialCoin != null && widget.initialCoin!.isNotEmpty) {
      final coinToMatch = widget.initialCoin!.toUpperCase();
      // Match to supported coins (handle variants like ETH -> ETH, USDT -> USDT-BEP20)
      final matchingCoin = _supportedCoins.firstWhere(
        (c) {
          final sym = (c['symbol'] as String).toUpperCase();
          return sym == coinToMatch || sym.startsWith(coinToMatch);
        },
        orElse: () => _supportedCoins.first,
      );
      _selectedCoin = matchingCoin['symbol'] as String;
      print('🔵 ReceivePage matched coin: $_selectedCoin');
    }
    
    _loadAddressesAndBalance();
  }
  
  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
  
  Future<void> _loadAddressesAndBalance() async {
    print('🔵 _loadAddressesAndBalance started, selectedCoin: $_selectedCoin');
    await _loadAddresses();
    print('🔵 _loadAddresses completed, addresses: $_addresses');
    // Load balance after addresses are loaded
    await _loadBalance();
    print('🔵 _loadBalance completed');
    
    // Check if the selected coin has no address and prompt to create one
    print('🔵 Checking address for $_selectedCoin: ${_addresses[_selectedCoin]}');
    print('🔵 mounted: $mounted');
    if (_addresses[_selectedCoin] == null && mounted) {
      print('🔵 No address found, showing create dialog');
      _showCreateAddressDialog();
    } else {
      print('🔵 Address exists or not mounted, skipping dialog');
    }
  }
  
  void _showCreateAddressDialog() {
    print('🟣 _showCreateAddressDialog called for $_selectedCoin');
    final coinData = _supportedCoins.firstWhere(
      (c) => c['symbol'] == _selectedCoin,
      orElse: () => _supportedCoins.first,
    );
    final color = coinData['color'] as Color? ?? const Color(0xFF8B5CF6);
    print('🟣 Showing dialog with color: $color');
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                coinData['icon'] as IconData? ?? Icons.wallet,
                color: color,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'No $_selectedCoin Address',
                style: const TextStyle(color: Colors.white, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'You don\'t have a ${coinData['name']} wallet address yet. Would you like to create one now?',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: color, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Creating an address is free and instant',
                      style: TextStyle(color: color, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              // Switch to BTC if available
              if (_addresses['BTC'] != null) {
                setState(() => _selectedCoin = 'BTC');
                _loadBalance();
              }
            },
            child: Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _generateNewAddressWithAnimation();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Create Address'),
          ),
        ],
      ),
    );
  }
  
  Future<void> _generateNewAddressWithAnimation() async {
    print('🟡 Starting address generation for $_selectedCoin');
    setState(() => _generatingAddress = true);
    
    // Show generating dialog with animation
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _buildGeneratingDialog(),
      );
    }
    
    try {
      print('🟡 Calling walletService.generateAddressFor($_selectedCoin)');
      final response = await _walletService.generateAddressFor(_selectedCoin);
      print('🟡 Got response: $response');
      final addresses = await _walletService.getStoredAddresses(_selectedCoin);
      print('🟡 Got addresses: $addresses');
      
      if (!mounted) return;
      
      setState(() {
        _storedLists[_selectedCoin] = addresses;
        _addresses[_selectedCoin] = addresses.isNotEmpty ? addresses.first : response['address'];
        _generatingAddress = false;
      });
      
      // Close generating dialog
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      
      // Load balance for the new address
      await _loadBalance();
      
      // Show success
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Text('$_selectedCoin address created successfully!'),
              ],
            ),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      print('🔴 Error generating address: $e');
      if (mounted) {
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }
        setState(() => _generatingAddress = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create address: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  Widget _buildGeneratingDialog() {
    final coinData = _supportedCoins.firstWhere(
      (c) => c['symbol'] == _selectedCoin,
      orElse: () => _supportedCoins.first,
    );
    final color = coinData['color'] as Color? ?? const Color(0xFF8B5CF6);
    
    return Dialog(
      backgroundColor: const Color(0xFF1A1F2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Animated wallet icon
            AnimatedBuilder(
              animation: _animationController,
              builder: (context, child) {
                return Transform.rotate(
                  angle: _animationController.value * 2 * 3.14159,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [color, color.withOpacity(0.5)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: color.withOpacity(0.4),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet_rounded,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            Text(
              'Creating $_selectedCoin Address',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Generating secure wallet address...',
              style: TextStyle(color: Colors.white54, fontSize: 14),
            ),
            const SizedBox(height: 24),
            // Progress indicator
            SizedBox(
              width: 200,
              child: LinearProgressIndicator(
                backgroundColor: color.withOpacity(0.2),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            const SizedBox(height: 16),
            // Steps animation
            _buildGeneratingSteps(color),
          ],
        ),
      ),
    );
  }
  
  Widget _buildGeneratingSteps(Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepRow('Initializing wallet', true, color),
        const SizedBox(height: 8),
        _buildStepRow('Generating keys', true, color),
        const SizedBox(height: 8),
        _buildStepRow('Creating address', false, color),
      ],
    );
  }
  
  Widget _buildStepRow(String text, bool completed, Color color) {
    return Row(
      children: [
        AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            return completed
                ? Icon(Icons.check_circle, color: color, size: 16)
                : Opacity(
                    opacity: 0.5 + 0.5 * _animationController.value,
                    child: Icon(Icons.pending, color: color, size: 16),
                  );
          },
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            color: completed ? Colors.white : Colors.white54,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Future<void> _loadAddresses() async {
    final stateCtx = context;
    setState(() => _loading = true);
    try {
      // Only load stored addresses. Do NOT auto-generate new addresses on page load.
      for (final coin in _supportedCoins) {
        final symbol = coin['symbol'] as String;
        try {
          final addresses = await _walletService.getStoredAddresses(symbol);
          if (addresses.isNotEmpty) {
            setState(() {
              _storedLists[symbol] = addresses;
              _addresses[symbol] = addresses.first;
            });
          } else {
            setState(() {
              _storedLists[symbol] = [];
              _addresses[symbol] = null;
            });
          }
        } catch (_) {
          // ignore individual coin errors
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('Failed to load addresses: $e');
      if (mounted) {
        ScaffoldMessenger.of(stateCtx).showSnackBar(
          SnackBar(content: Text('Failed to load addresses: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _generateNewAddress() async {
    final stateCtx = context;
    setState(() => _loading = true);
    try {
      final response = await _walletService.generateAddressFor(_selectedCoin);
      // Refresh stored addresses for this coin and pick the newest
      final addresses = await _walletService.getStoredAddresses(_selectedCoin);
      if (!mounted) return;
      setState(() {
        _storedLists[_selectedCoin] = addresses;
        _addresses[_selectedCoin] = (addresses.isNotEmpty ? addresses.first : response['address']);
      });
      // ignore: use_build_context_synchronously
      if (mounted) {
        ScaffoldMessenger.of(stateCtx).showSnackBar(
          const SnackBar(content: Text('Generated new address successfully')),
        );
      }
    } catch (e) {
      // ignore: avoid_print
      print('Failed to generate new address: $e');
      // ignore: use_build_context_synchronously
      if (mounted) {
        ScaffoldMessenger.of(stateCtx).showSnackBar(
          SnackBar(content: Text('Failed to generate new address: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _copyToClipboard() {
    final address = _addresses[_selectedCoin];
    if (address == null) return;
    Clipboard.setData(ClipboardData(text: address));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Address copied to clipboard')),
      );
    }
  }

  void _showCoinPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return _CoinPickerSheet(
          initial: _selectedCoin,
          onSelected: (sym) {
            setState(() => _selectedCoin = sym);
            Navigator.of(context).pop();
            // Load stored addresses for the newly selected coin (do not auto-generate)
            _loadAddresses();
            _loadBalance();
          },
        );
      },
    );
  }

  Future<void> _loadBalance() async {
    final currentAddress = _addresses[_selectedCoin];
    if (currentAddress == null) return;
    
    setState(() => _loadingBalance = true);
    try {
      // Get blockchain balance
      final blockchainBalance = await _blockchainService.getBalance(_selectedCoin, currentAddress);
      
      // Get swap adjustments (pending swap amounts)
      final swapAdjustment = await _getSwapAdjustment(_selectedCoin);
      
      // Combine real balance + swap adjustments (pending swaps)
      final totalBalance = blockchainBalance + swapAdjustment;
      
      print('💰 $_selectedCoin balance on receive page:');
      print('   Blockchain: $blockchainBalance');
      print('   Swap adjustment: $swapAdjustment');
      print('   Total: $totalBalance');
      
      setState(() {
        _balances[_selectedCoin] = totalBalance > 0 ? totalBalance : 0.0;
      });
    } catch (e) {
      print('Error loading balance for $_selectedCoin: $e');
    } finally {
      setState(() => _loadingBalance = false);
    }
  }
  
  /// Get swap adjustment for a coin from SharedPreferences
  Future<double> _getSwapAdjustment(String coin) async {
    try {
      // Force reload from storage (important on web)
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload(); // Reload to get latest values
      
      // Get base coin (USDT-BEP20 -> USDT, ETH -> ETH)
      final baseCoin = coin.contains('-') ? coin.split('-')[0] : coin;
      final adjustment = prefs.getDouble('swap_adjustment_$baseCoin') ?? 0.0;
      print('📊 Receive page: swap_adjustment_$baseCoin = $adjustment');
      return adjustment;
    } catch (e) {
      print('Error getting swap adjustment: $e');
      return 0.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentAddress = _addresses[_selectedCoin];
    final currentList = _storedLists[_selectedCoin] ?? [];
    final currentBalance = _balances[_selectedCoin] ?? 0.0;
    final pricesAsync = ref.watch(marketPricesProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/dashboard'),
          tooltip: 'Back to Dashboard',
        ),
        title: const Text('Receive'),
        actions: [
          IconButton(
            icon: const Icon(Icons.camera_alt),
            onPressed: _captureQrScreenshot,
            tooltip: 'Screenshot QR Code',
          ),
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            onPressed: _showCoinPicker,
            tooltip: 'Change coin',
          ),
          IconButton(
            icon: const Icon(Icons.key),
            onPressed: () async {
              final localCtx = context;
              final addr = _addresses[_selectedCoin];
              if (addr == null) {
                  if (mounted) {
                    ScaffoldMessenger.of(localCtx).showSnackBar(const SnackBar(content: Text('No address selected')));
                  }
                  return;
                }
              await _confirmAndReveal(_selectedCoin, addr);
            },
            tooltip: 'Export / Reveal private key',
          ),
          if (!_loading)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _generateNewAddress,
              tooltip: 'Generate new address',
            ),
          IconButton(
            icon: const Icon(Icons.update),
            onPressed: _loadBalance,
            tooltip: 'Refresh balance',
          ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: EdgeInsets.only(
              left: AppConstants.defaultPadding,
              right: AppConstants.defaultPadding,
              top: AppConstants.defaultPadding,
              bottom: AppConstants.defaultPadding + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Coin Selection
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Select Coin', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 16),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SegmentedButton<String>(
                            segments: _supportedCoins
                                .map((coin) => ButtonSegment<String>(
                                      value: coin['symbol'] as String,
                                      label: Text(coin['name'] as String),
                                      icon: Icon(coin['icon'] as IconData),
                                    ))
                                .toList(),
                            selected: {_selectedCoin},
                            onSelectionChanged: (Set<String> selection) {
                              setState(() {
                                _selectedCoin = selection.first;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Balance Display
                if (currentAddress != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Current Balance',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _loadingBalance
                                        ? const SizedBox(
                                            width: 24,
                                            height: 24,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          )
                                        : Text(
                                            '${currentBalance.toStringAsFixed(8)} $_selectedCoin',
                                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Blockchain verified',
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Theme.of(context).colorScheme.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 16),

                // QR Code and Address Section
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      children: [
                        // QR Code (responsive) + price/percent inside the card
                        LayoutBuilder(builder: (context, constraints) {
                          // compute a safe size that adapts to narrow screens
                          final maxW = constraints.maxWidth.isFinite ? constraints.maxWidth : 360.0;
                          final size = (maxW * 0.6).clamp(120.0, 320.0);
                          return ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: maxW),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // price / percent row inside the card, aligned to right
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8.0),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      pricesAsync.when(
                                        data: (map) {
                                          final item = map[_selectedCoin.split('-').first] ?? {'price_usd': null};
                                          final price = item['price_usd'];
                                          final priceText = (price is num) ? '\$${price.toDouble().toStringAsFixed(2)}' : '-';
                                          // Percentage placeholder (backend currently does not provide change pct) - leave as N/A
                                          final pctText = item.containsKey('change_pct') ? '${item['change_pct']}%' : 'N/A';
                                          return Row(
                                            children: [
                                              Text(priceText, style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                                              const SizedBox(width: 8),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: Theme.of(context).colorScheme.primary.withAlpha(20),
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: Text(pctText, style: Theme.of(context).textTheme.bodySmall),
                                              ),
                                            ],
                                          );
                                        },
                                        loading: () => const SizedBox.shrink(),
                                        error: (_, __) => const SizedBox.shrink(),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  width: size,
                                  height: size,
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.grey.withAlpha((0.1 * 255).round()),
                                        spreadRadius: 2,
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: currentAddress != null
                                      ? FittedBox(
                                          fit: BoxFit.contain,
                                          child: QrImageView(
                                            data: currentAddress,
                                            version: QrVersions.auto,
                                            size: size - 40,
                                            backgroundColor: Colors.white,
                                            errorCorrectionLevel: QrErrorCorrectLevel.H,
                                          ),
                                        )
                                      : const Center(
                                          child: Text('No address available'),
                                        ),
                                ),
                              ],
                            ),
                          );
                        }),

                        const SizedBox(height: 24),

                        // Address Display
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Network Information
                              if (currentAddress != null)
                                Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.network_check,
                                        size: 16,
                                        color: Theme.of(context).colorScheme.primary,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        _getNetworkName(_selectedCoin),
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                              fontWeight: FontWeight.w600,
                                              color: Theme.of(context).colorScheme.primary,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              
                              Row(
                                children: [
                                  Flexible(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (currentList.length > 1)
                                          Container(
                                            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.6),
                                            child: DropdownButton<String>(
                                              isExpanded: true,
                                              value: currentAddress,
                                              items: currentList.map((a) => DropdownMenuItem(
                                                value: a,
                                                child: Text(
                                                  a,
                                                  overflow: TextOverflow.ellipsis,
                                                )
                                              )).toList(),
                                              onChanged: (v) {
                                                if (v != null) setState(() => _addresses[_selectedCoin] = v);
                                              },
                                            ),
                                          ),
                                        if (currentAddress != null)
                                            Container(
                                              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.6),
                                              child: SingleChildScrollView(
                                                scrollDirection: Axis.horizontal,
                                                child: SelectableText(
                                                  currentAddress,
                                                  style: Theme.of(context).textTheme.bodyLarge,
                                                ),
                                              ),
                                            )
                                        else
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Address not generated',
                                                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                                      color: Theme.of(context).colorScheme.error,
                                                    ),
                                              ),
                                              const SizedBox(height: 8),
                                              ElevatedButton.icon(
                                                onPressed: _generateNewAddress,
                                                icon: const Icon(Icons.add),
                                                label: const Text('Generate address'),
                                              ),
                                            ],
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (currentAddress != null)
                                    IconButton(
                                      icon: const Icon(Icons.copy),
                                      onPressed: _copyToClipboard,
                                      tooltip: 'Copy address',
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Security Note
                Card(
                  color: Theme.of(context).colorScheme.surface,
                  child: const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.security, size: 20),
                            SizedBox(width: 8),
                            Text('Security Tips', style: TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        SizedBox(height: 8),
                        Text(
                          '• Always verify the address before sending funds\n'
                          '• Each address should only be used once for maximum privacy\n'
                          '• Save or screenshot the QR code for reference',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                Text(
                  'Note: For maximum security, generate a new address for each transaction.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          // Loading overlay to avoid layout shifts/overflows when generating
          if (_loading)
            Positioned.fill(
              child: AbsorbPointer(
                absorbing: true,
                child: Container(
                  color: Colors.black.withAlpha((0.25 * 255).round()),
                  alignment: Alignment.center,
                  child: const SizedBox(width: 56, height: 56, child: CircularProgressIndicator()),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmAndReveal(String chain, String address) async {
    // Check if we have a private key stored locally
    final privateKey = await _walletService.getPrivateKey(chain, address);
    final mnemonic = await _walletService.getMnemonic(chain, address);

    final stateCtx = context;
    if (privateKey == null && mnemonic == null) {
      // ignore: use_build_context_synchronously
      if (mounted) {
        ScaffoldMessenger.of(stateCtx).showSnackBar(const SnackBar(content: Text('No local secrets available for this address')));
      }
      return;
    }

    // Ask user to confirm intent
    final confirm = await showDialog<bool>(
      context: stateCtx,
      builder: (context) => AlertDialog(
        title: const Text('Reveal sensitive data'),
        content: const Text('Revealing the private key or mnemonic will expose sensitive information on this device. Continue?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Continue')),
        ],
      ),
    );

    if (confirm != true) return;

    // Require a 6-digit PIN to proceed. If no PIN exists, prompt user to create one.
    // Check if PIN exists
    final hasPin = await _walletService.hasPin();
    if (!hasPin) {
      // Prompt to create PIN (enter twice)
      final created = await showDialog<bool>(
        context: stateCtx,
        builder: (context) {
          final p1 = TextEditingController();
          final p2 = TextEditingController();
          return AlertDialog(
            title: const Text('Create a 6-digit PIN'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('You need to set a 6-digit PIN to reveal private keys.'),
                const SizedBox(height: 8),
                TextField(controller: p1, keyboardType: TextInputType.number, obscureText: true, maxLength: 6, decoration: const InputDecoration(hintText: 'Enter 6-digit PIN')),
                TextField(controller: p2, keyboardType: TextInputType.number, obscureText: true, maxLength: 6, decoration: const InputDecoration(hintText: 'Confirm PIN')),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
              TextButton(
                    onPressed: () {
                    final v1 = p1.text.trim();
                    final v2 = p2.text.trim();
                    if (v1.length == 6 && v1 == v2) {
                      Navigator.of(context).pop(true);
                    } else {
                      // ignore: use_build_context_synchronously
                      if (mounted) {
                        ScaffoldMessenger.of(stateCtx).showSnackBar(const SnackBar(content: Text('PINs do not match or are not 6 digits')));
                      }
                    }
                  },
                  child: const Text('Set PIN'))
            ],
          );
        },
      );

      if (created == true) {
        // write the PIN
        // We need to retrieve the controllers again via a fresh dialog to get the value; to simplify, ask user to set PIN via a second dialog that only asks once and confirms.
        final pin = await showDialog<String?>(
          context: stateCtx,
          builder: (context) {
            final ctl = TextEditingController();
            return AlertDialog(
              title: const Text('Enter new 6-digit PIN (again)'),
              content: TextField(controller: ctl, keyboardType: TextInputType.number, obscureText: true, maxLength: 6),
              actions: [TextButton(onPressed: () => Navigator.of(context).pop(null), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.of(context).pop(ctl.text.trim()), child: const Text('Save'))],
            );
          },
        );
        if (pin == null || pin.length != 6) {
          // ignore: use_build_context_synchronously
          if (mounted) {
            ScaffoldMessenger.of(stateCtx).showSnackBar(const SnackBar(content: Text('PIN setup canceled')));
          }
          return;
        }
        await _walletService.setPin(pin);
        // ignore: use_build_context_synchronously
        if (mounted) {
          ScaffoldMessenger.of(stateCtx).showSnackBar(const SnackBar(content: Text('PIN set successfully')));
        }
      } else {
        // user canceled creation
        return;
      }
    }

    // Prompt user to enter PIN
    final entered = await showDialog<String?>(
      context: stateCtx,
      builder: (context) {
        final ctl = TextEditingController();
        return AlertDialog(
          title: const Text('Enter your 6-digit PIN'),
          content: TextField(controller: ctl, keyboardType: TextInputType.number, obscureText: true, maxLength: 6),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(null), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.of(context).pop(ctl.text.trim()), child: const Text('Unlock'))],
        );
      },
    );

    if (entered == null) return;

    final ok = await _walletService.verifyPin(entered);
    if (!ok) {
      await _walletService.recordRevealEvent(chain, address, false);
      // ignore: use_build_context_synchronously
      if (mounted) {
        ScaffoldMessenger.of(stateCtx).showSnackBar(const SnackBar(content: Text('Incorrect PIN')));
      }
      return;
    }
    // record success
    await _walletService.recordRevealEvent(chain, address, true);

    // Show the secrets in a dialog with copy buttons
    if (!mounted) return;
    await showDialog<void>(
      context: stateCtx,
      builder: (context) {
        return AlertDialog(
          title: const Text('Private Key & Mnemonic'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (privateKey != null) ...[
                  const Text('Private Key', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  SelectableText(privateKey),
                  TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: privateKey));
                      Navigator.of(context).pop();
                      // ignore: use_build_context_synchronously
                      if (mounted) ScaffoldMessenger.of(stateCtx).showSnackBar(const SnackBar(content: Text('Private key copied')));
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy private key'),
                  ),
                  const SizedBox(height: 12),
                ],
                if (mnemonic != null) ...[
                  const Text('Mnemonic', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  SelectableText(mnemonic),
                  TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: mnemonic));
                      Navigator.of(context).pop();
                      // ignore: use_build_context_synchronously
                      if (mounted) ScaffoldMessenger.of(stateCtx).showSnackBar(const SnackBar(content: Text('Mnemonic copied')));
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy mnemonic'),
                  ),
                ],
              ],
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
        );
      },
    );
  }

  void _captureQrScreenshot() async {
    final currentAddress = _addresses[_selectedCoin];
    if (currentAddress == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No address available to capture')),
      );
      return;
    }

    try {
      // Create a widget to render
      final qrWidget = Container(
        color: Colors.white,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            QrImageView(
              data: currentAddress,
              version: QrVersions.auto,
              size: 200,
              backgroundColor: Colors.white,
              errorCorrectionLevel: QrErrorCorrectLevel.H,
            ),
            const SizedBox(height: 12),
            Text(
              _getNetworkName(_selectedCoin),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              constraints: const BoxConstraints(maxWidth: 300),
              child: Text(
                currentAddress,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.black87,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );

      // For web, show dialog with instructions
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          contentPadding: const EdgeInsets.all(16),
          title: const Text('QR Code'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                qrWidget,
                const SizedBox(height: 16),
                const Text(
                  'Right-click and "Save image as..." or take a screenshot',
                  style: TextStyle(fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: currentAddress));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Address copied to clipboard')),
                );
              },
              child: const Text('Copy Address'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  String _getNetworkName(String coinSymbol) {
    switch (coinSymbol) {
      case 'BTC':
        return 'Bitcoin Mainnet';
      case 'ETH':
        return 'Ethereum Mainnet';
      case 'BNB':
        return 'Binance Smart Chain';
      case 'USDT-ERC20':
        return 'Ethereum ERC20 Network';
      case 'USDT-BEP20':
        return 'Binance Smart Chain BEP20';
      case 'USDT-TRC20':
        return 'Tron TRC20 Network';
      default:
        return 'Main Network';
    }
  }
}

class _CoinPickerSheet extends StatefulWidget {
  final String initial;
  final void Function(String) onSelected;

  const _CoinPickerSheet({required this.initial, required this.onSelected});

  @override
  State<_CoinPickerSheet> createState() => _CoinPickerSheetState();
}

class _CoinPickerSheetState extends State<_CoinPickerSheet> {
  final TextEditingController _search = TextEditingController();
  late List<Map<String, String>> _coins;

  @override
  void initState() {
    super.initState();
    _coins = [
      {'symbol': 'BTC', 'name': 'Bitcoin'},
      {'symbol': 'USDT', 'name': 'Tether'},
      {'symbol': 'ETH', 'name': 'Ethereum'},
      {'symbol': 'TRX', 'name': 'Tron'},
      {'symbol': 'XRP', 'name': 'XRP'},
      {'symbol': 'BNB', 'name': 'BNB'},
      {'symbol': 'SOL', 'name': 'Solana'},
      {'symbol': 'LTC', 'name': 'Litecoin'},
      {'symbol': 'DOGE', 'name': 'Dogecoin'},
    ];
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? _coins
        : _coins.where((c) => c['symbol']!.toLowerCase().contains(query) || c['name']!.toLowerCase().contains(query)).toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Select Asset to Receive', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                TextField(
                  controller: _search,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search...'),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 300,
            child: ListView.separated(
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final c = filtered[index];
                return ListTile(
                  leading: CircleAvatar(child: Text(c['symbol']!.substring(0, 1))),
                  title: Text(c['name']!),
                  subtitle: Text(c['symbol']!),
                  onTap: () => widget.onSelected(c['symbol']!),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}