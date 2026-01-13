import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../services/wallet_service.dart';
import '../../../services/blockchain_service.dart';

class ReceivePageV2 extends ConsumerStatefulWidget {
  const ReceivePageV2({super.key, this.initialCoin});

  final String? initialCoin;

  @override
  ConsumerState<ReceivePageV2> createState() => _ReceivePageV2State();
}

class _ReceivePageV2State extends ConsumerState<ReceivePageV2>
    with TickerProviderStateMixin {
  final WalletService _walletService = WalletService();
  final BlockchainService _blockchainService = BlockchainService();

  // Animation controllers
  late AnimationController _colorAnimationController;
  late Animation<Color?> _headerColorAnimation;

  String _selectedCoin = 'BTC';
  String? _selectedNetwork;
  String? _address;
  List<String> _allAddresses = []; // Store all addresses for dropdown
  bool _loading = true;
  bool _generatingAddress = false;
  Color _currentHeaderColor = const Color(0xFFF7931A);

  // Coins with network options
  final List<Map<String, dynamic>> _coins = [
    {
      'symbol': 'BTC',
      'name': 'Bitcoin',
      'color': Color(0xFFF7931A),
      'icon': Icons.currency_bitcoin,
      'networks': [
        {'id': 'BTC', 'name': 'Bitcoin Network', 'tag': 'BTC'},
      ],
    },
    {
      'symbol': 'ETH',
      'name': 'Ethereum',
      'color': Color(0xFF627EEA),
      'icon': Icons.diamond_outlined,
      'networks': [
        {'id': 'ETH', 'name': 'Ethereum (ERC20)', 'tag': 'ERC20'},
      ],
    },
    {
      'symbol': 'BNB',
      'name': 'BNB',
      'color': Color(0xFFF3BA2F),
      'icon': Icons.hexagon_outlined,
      'networks': [
        {'id': 'BNB', 'name': 'BNB Smart Chain (BEP20)', 'tag': 'BEP20'},
      ],
    },
    {
      'symbol': 'USDT',
      'name': 'Tether',
      'color': Color(0xFF26A17B),
      'icon': Icons.attach_money,
      'networks': [
        {'id': 'USDT-ERC20', 'name': 'Ethereum (ERC20)', 'tag': 'ERC20'},
        {'id': 'USDT-BEP20', 'name': 'BNB Smart Chain (BEP20)', 'tag': 'BEP20'},
        {'id': 'USDT-TRC20', 'name': 'TRON (TRC20)', 'tag': 'TRC20'},
      ],
    },
    {
      'symbol': 'SOL',
      'name': 'Solana',
      'color': Color(0xFF00FFA3),
      'icon': Icons.sunny,
      'networks': [
        {'id': 'SOL', 'name': 'Solana Network', 'tag': 'SOL'},
      ],
    },
    {
      'symbol': 'TRX',
      'name': 'TRON',
      'color': Color(0xFFEF0027),
      'icon': Icons.flash_on,
      'networks': [
        {'id': 'TRX', 'name': 'TRON Network', 'tag': 'TRC20'},
      ],
    },
    {
      'symbol': 'XRP',
      'name': 'XRP',
      'color': Color(0xFF00AAE4),
      'icon': Icons.water_drop_outlined,
      'networks': [
        {'id': 'XRP', 'name': 'XRP Ledger', 'tag': 'XRP'},
      ],
    },
    {
      'symbol': 'DOGE',
      'name': 'Dogecoin',
      'color': Color(0xFFC2A633),
      'icon': Icons.pets,
      'networks': [
        {'id': 'DOGE', 'name': 'Dogecoin Network', 'tag': 'DOGE'},
      ],
    },
    {
      'symbol': 'LTC',
      'name': 'Litecoin',
      'color': Color(0xFFBFBBBB),
      'icon': Icons.bolt,
      'networks': [
        {'id': 'LTC', 'name': 'Litecoin Network', 'tag': 'LTC'},
      ],
    },
  ];

  @override
  void initState() {
    super.initState();
    
    // Set initial coin from parameter
    if (widget.initialCoin != null && widget.initialCoin!.isNotEmpty) {
      final coinToMatch = widget.initialCoin!.toUpperCase();
      final matchingCoin = _coins.firstWhere(
        (c) => (c['symbol'] as String).toUpperCase() == coinToMatch ||
               (c['symbol'] as String).toUpperCase().startsWith(coinToMatch),
        orElse: () => _coins.first,
      );
      _selectedCoin = matchingCoin['symbol'] as String;
    }

    _colorAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _updateHeaderColor(_getCoinColor(_selectedCoin));
    _initializeNetwork();
  }

  void _initializeNetwork() {
    final coin = _coins.firstWhere(
      (c) => c['symbol'] == _selectedCoin,
      orElse: () => _coins.first,
    );
    final networksList = coin['networks'] as List;
    if (networksList.isNotEmpty) {
      final firstNetwork = networksList.first as Map;
      _selectedNetwork = firstNetwork['id']?.toString() ?? _selectedCoin;
    } else {
      _selectedNetwork = _selectedCoin;
    }
    _loadAddress();
  }

  @override
  void dispose() {
    _colorAnimationController.dispose();
    super.dispose();
  }

  Color _getCoinColor(String symbol) {
    return _coins.firstWhere(
      (c) => c['symbol'] == symbol,
      orElse: () => {'color': const Color(0xFF8B5CF6)},
    )['color'] as Color;
  }

  void _updateHeaderColor(Color newColor) {
    final oldColor = _currentHeaderColor;
    _headerColorAnimation = ColorTween(begin: oldColor, end: newColor).animate(
      CurvedAnimation(
          parent: _colorAnimationController, curve: Curves.easeInOut),
    );
    _colorAnimationController.forward(from: 0);
    setState(() => _currentHeaderColor = newColor);
  }

  void _selectCoin(String symbol) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedCoin = symbol;
      _address = null;
      _loading = true;
    });
    _updateHeaderColor(_getCoinColor(symbol));
    
    // Reset network to first option for new coin
    final coin = _coins.firstWhere(
      (c) => c['symbol'] == symbol,
      orElse: () => _coins.first,
    );
    final networksList = coin['networks'] as List;
    if (networksList.isNotEmpty) {
      final firstNetwork = networksList.first as Map;
      _selectedNetwork = firstNetwork['id']?.toString() ?? symbol;
    } else {
      _selectedNetwork = symbol;
    }
    _loadAddress();
  }

  void _selectNetwork(String networkId) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedNetwork = networkId;
      _address = null;
      _loading = true;
    });
    _loadAddress();
  }

  Future<void> _loadAddress() async {
    setState(() => _loading = true);
    try {
      final addresses = await _walletService.getStoredAddresses(_selectedNetwork ?? _selectedCoin);
      if (addresses.isNotEmpty) {
        setState(() {
          _allAddresses = addresses;
          _address = addresses.first;
          _loading = false;
        });
      } else {
        setState(() {
          _allAddresses = [];
          _address = null;
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _allAddresses = [];
        _address = null;
        _loading = false;
      });
    }
  }

  void _selectAddress(String address) {
    HapticFeedback.selectionClick();
    setState(() {
      _address = address;
    });
  }

  Future<void> _generateAddress() async {
    setState(() => _generatingAddress = true);
    
    // Show generating dialog
    _showGeneratingDialog();
    
    try {
      await _walletService.generateAddressFor(_selectedNetwork ?? _selectedCoin);
      final addresses = await _walletService.getStoredAddresses(_selectedNetwork ?? _selectedCoin);
      
      if (mounted) {
        Navigator.of(context).pop(); // Close dialog
        setState(() {
          _allAddresses = addresses;
          // Select the newly generated address (should be the last one or first depending on order)
          _address = addresses.isNotEmpty ? addresses.last : null;
          _generatingAddress = false;
        });
        
        if (_address != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Address created successfully!'),
                ],
              ),
              backgroundColor: _currentHeaderColor,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Close dialog
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

  void _showGeneratingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: const Color(0xFF1A1F2E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Animated wallet icon with continuous rotation
                _GeneratingAnimation(color: _currentHeaderColor),
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
                const Text(
                  'Generating secure wallet address...',
                  style: TextStyle(color: Colors.white54, fontSize: 14),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: 200,
                  child: LinearProgressIndicator(
                    backgroundColor: _currentHeaderColor.withOpacity(0.2),
                    valueColor: AlwaysStoppedAnimation<Color>(_currentHeaderColor),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _copyAddress() {
    if (_address == null) return;
    Clipboard.setData(ClipboardData(text: _address!));
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 8),
            Text('Address copied to clipboard'),
          ],
        ),
        backgroundColor: _currentHeaderColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _shareAddress() {
    if (_address == null) return;
    HapticFeedback.mediumImpact();
    // Copy address with share-friendly text
    final shareText = 'My $_selectedCoin address:\n$_address';
    Clipboard.setData(ClipboardData(text: shareText));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 8),
            Expanded(child: Text('Address copied! Ready to share')),
          ],
        ),
        backgroundColor: _currentHeaderColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1421),
      body: AnimatedBuilder(
        animation: _colorAnimationController,
        builder: (context, child) {
          final headerColor =
              _headerColorAnimation?.value ?? _currentHeaderColor;

          return NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              // Fixed app bar
              SliverAppBar(
                pinned: true,
                floating: false,
                backgroundColor: const Color(0xFF0D1421),
                elevation: 0,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded,
                      color: Colors.white),
                  onPressed: () => context.go('/dashboard'),
                ),
                title: const Text(
                  'Receive',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                centerTitle: true,
                actions: [
                  // Add new address button
                  if (_address != null)
                    IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: headerColor.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.add_rounded, color: headerColor, size: 20),
                      ),
                      onPressed: _generatingAddress ? null : _generateNewAddress,
                      tooltip: 'Generate new address',
                    ),
                  const SizedBox(width: 8),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          headerColor.withOpacity(0.3),
                          headerColor.withOpacity(0.1),
                          Colors.transparent,
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ),
              ),
            ],
            body: CustomScrollView(
              slivers: [
                // Selected coin header
                SliverToBoxAdapter(
                  child: _buildCoinHeader(headerColor),
                ),

                // Coin selection cards
                SliverToBoxAdapter(
                  child: _buildCoinSelection(),
                ),

                // Network selection (if multiple networks)
                SliverToBoxAdapter(
                  child: _buildNetworkSelection(),
                ),

                // QR Code section
                SliverToBoxAdapter(
                  child: _buildQRSection(),
                ),

                // Address section
                SliverToBoxAdapter(
                  child: _buildAddressSection(),
                ),

                // Action buttons
                SliverToBoxAdapter(
                  child: _buildActionButtons(),
                ),

                // Warning section
                SliverToBoxAdapter(
                  child: _buildWarningSection(),
                ),

                const SliverToBoxAdapter(
                  child: SizedBox(height: 40),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _generateNewAddress() async {
    // Show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.add_circle_outline, color: _currentHeaderColor),
            const SizedBox(width: 12),
            const Text('New Address', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Text(
          'Generate a new $_selectedCoin receiving address?\n\nYour current address will still work.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _currentHeaderColor,
            ),
            child: const Text('Generate', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _generateAddress();
    }
  }

  Widget _buildCoinHeader(Color headerColor) {
    final coin = _coins.firstWhere(
      (c) => c['symbol'] == _selectedCoin,
      orElse: () => _coins.first,
    );
    
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [headerColor, headerColor.withOpacity(0.7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: headerColor.withOpacity(0.4),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(
              coin['icon'] as IconData,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Receive ${coin['name']}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _selectedNetwork ?? _selectedCoin,
                  style: TextStyle(
                    color: headerColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(Color headerColor) {
    final coin = _coins.firstWhere(
      (c) => c['symbol'] == _selectedCoin,
      orElse: () => _coins.first,
    );
    
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            headerColor.withOpacity(0.3),
            headerColor.withOpacity(0.1),
            Colors.transparent,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // App bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white),
                    onPressed: () => context.go('/dashboard'),
                  ),
                  const Expanded(
                    child: Text(
                      'Receive',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),

            // Selected coin display
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [headerColor, headerColor.withOpacity(0.7)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: headerColor.withOpacity(0.4),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Icon(
                      coin['icon'] as IconData,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Receive ${coin['name']}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _selectedNetwork ?? _selectedCoin,
                        style: TextStyle(
                          color: headerColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoinSelection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Select Coin',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 90,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _coins.length,
              itemBuilder: (context, index) {
                final coin = _coins[index];
                final isSelected = _selectedCoin == coin['symbol'];
                final color = coin['color'] as Color;

                return GestureDetector(
                  onTap: () => _selectCoin(coin['symbol'] as String),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    width: 75,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      gradient: isSelected
                          ? LinearGradient(
                              colors: [
                                color.withOpacity(0.3),
                                color.withOpacity(0.1)
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null,
                      color: isSelected ? null : const Color(0xFF1A1F2E),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected ? color : Colors.transparent,
                        width: 2,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: color.withOpacity(0.3),
                                blurRadius: 12,
                                spreadRadius: 0,
                              ),
                            ]
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: isSelected ? color : color.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            coin['icon'] as IconData,
                            color: isSelected ? Colors.white : color,
                            size: 20,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          coin['symbol'] as String,
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.white60,
                            fontSize: 12,
                            fontWeight:
                                isSelected ? FontWeight.bold : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkSelection() {
    final coin = _coins.firstWhere(
      (c) => c['symbol'] == _selectedCoin,
      orElse: () => _coins.first,
    );
    final networksList = coin['networks'] as List;
    
    // Only show network selection if there are multiple networks
    if (networksList.length <= 1) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Select Network',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: networksList.map<Widget>((n) {
              final network = n as Map;
              final isSelected = _selectedNetwork == network['id'];
              return GestureDetector(
                onTap: () => _selectNetwork(network['id']?.toString() ?? ''),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: isSelected
                        ? LinearGradient(
                            colors: [
                              _currentHeaderColor.withOpacity(0.3),
                              _currentHeaderColor.withOpacity(0.1),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: isSelected ? null : const Color(0xFF1A1F2E),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? _currentHeaderColor : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? _currentHeaderColor
                              : _currentHeaderColor.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          network['tag']?.toString() ?? '',
                          style: TextStyle(
                            color: isSelected ? Colors.white : _currentHeaderColor,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        network['name']?.toString() ?? '',
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.white70,
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildQRSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1F2E),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: _currentHeaderColor.withOpacity(0.3),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: _currentHeaderColor.withOpacity(0.1),
                blurRadius: 20,
                spreadRadius: 0,
              ),
            ],
          ),
          child: Column(
            children: [
              if (_loading)
                _buildLoadingQR()
              else if (_address == null)
                _buildNoAddressQR()
              else
                _buildQRCode(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingQR() {
    return Column(
      children: [
        Container(
          width: 200,
          height: 200,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Center(
            child: CircularProgressIndicator(
              color: _currentHeaderColor,
              strokeWidth: 3,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Loading address...',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Widget _buildNoAddressQR() {
    return Column(
      children: [
        Container(
          width: 200,
          height: 200,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _currentHeaderColor.withOpacity(0.3),
              width: 2,
              style: BorderStyle.solid,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                color: _currentHeaderColor.withOpacity(0.5),
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                'No Address Yet',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Create one to receive $_selectedCoin',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: _generatingAddress ? null : _generateAddress,
          icon: Icon(_generatingAddress ? Icons.hourglass_empty : Icons.add_rounded),
          label: Text(_generatingAddress ? 'Creating...' : 'Create Address'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _currentHeaderColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQRCode() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: _currentHeaderColor.withOpacity(0.2),
                blurRadius: 20,
                spreadRadius: 0,
              ),
            ],
          ),
          child: QrImageView(
            data: _address!,
            version: QrVersions.auto,
            size: 180,
            backgroundColor: Colors.white,
            eyeStyle: QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color: const Color(0xFF1A1F2E),
            ),
            dataModuleStyle: QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: const Color(0xFF1A1F2E),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _currentHeaderColor.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle,
                color: _currentHeaderColor,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                'Scan to receive $_selectedCoin',
                style: TextStyle(
                  color: _currentHeaderColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAddressSection() {
    if (_address == null) return const SizedBox.shrink();
    
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Wallet Address',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Row(
                children: [
                  // Address count badge
                  if (_allAddresses.length > 1)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${_allAddresses.indexOf(_address!) + 1}/${_allAddresses.length}',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _currentHeaderColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _selectedNetwork ?? _selectedCoin,
                      style: TextStyle(
                        color: _currentHeaderColor,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Address dropdown if multiple addresses exist
          if (_allAddresses.length > 1) ...[
            _buildAddressDropdown(),
            const SizedBox(height: 12),
          ],
          
          GestureDetector(
            onTap: _copyAddress,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1F2E),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withOpacity(0.1),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _address!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontFamily: 'monospace',
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _currentHeaderColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.copy_rounded,
                      color: _currentHeaderColor,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _currentHeaderColor.withOpacity(0.3),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _address,
          isExpanded: true,
          dropdownColor: const Color(0xFF1A1F2E),
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: _currentHeaderColor),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontFamily: 'monospace',
          ),
          items: _allAddresses.asMap().entries.map((entry) {
            final index = entry.key;
            final addr = entry.value;
            final isSelected = addr == _address;
            final shortAddr = '${addr.substring(0, 8)}...${addr.substring(addr.length - 6)}';
            
            return DropdownMenuItem<String>(
              value: addr,
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: isSelected 
                          ? _currentHeaderColor 
                          : _currentHeaderColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: isSelected ? Colors.white : _currentHeaderColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      shortAddr,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  if (isSelected)
                    Icon(
                      Icons.check_circle,
                      color: _currentHeaderColor,
                      size: 16,
                    ),
                ],
              ),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) {
              _selectAddress(value);
            }
          },
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    if (_address == null) return const SizedBox.shrink();
    
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _copyAddress,
              icon: const Icon(Icons.copy_rounded, size: 20),
              label: const Text('Copy'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A1F2E),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: _currentHeaderColor.withOpacity(0.3),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _shareAddress,
              icon: const Icon(Icons.share_rounded, size: 20),
              label: const Text('Share'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _currentHeaderColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWarningSection() {
    final coin = _coins.firstWhere(
      (c) => c['symbol'] == _selectedCoin,
      orElse: () => _coins.first,
    );
    final networksList = coin['networks'] as List;
    
    // Find current network safely
    Map<String, dynamic>? currentNetwork;
    for (final n in networksList) {
      if (n is Map && n['id'] == _selectedNetwork) {
        currentNetwork = Map<String, dynamic>.from(n);
        break;
      }
    }
    currentNetwork ??= networksList.isNotEmpty 
        ? Map<String, dynamic>.from(networksList.first as Map) 
        : {'tag': _selectedCoin};
    
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.orange.withOpacity(0.3),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: Colors.orange,
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Important',
                    style: TextStyle(
                      color: Colors.orange,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Only send $_selectedCoin (${currentNetwork['tag']}) to this address. Sending other assets may result in permanent loss.',
                    style: TextStyle(
                      color: Colors.orange.withOpacity(0.8),
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Separate widget for continuous animation in the generating dialog
class _GeneratingAnimation extends StatefulWidget {
  final Color color;
  
  const _GeneratingAnimation({required this.color});

  @override
  State<_GeneratingAnimation> createState() => _GeneratingAnimationState();
}

class _GeneratingAnimationState extends State<_GeneratingAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.rotate(
          angle: _controller.value * 2 * 3.14159,
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [widget.color, widget.color.withOpacity(0.5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: widget.color.withOpacity(0.4),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Icon(
                  Icons.account_balance_wallet_rounded,
                  color: Colors.white,
                  size: 40,
                ),
                // Pulsing ring
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.8, end: 1.2),
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeInOut,
                  builder: (context, scale, child) {
                    return Transform.scale(
                      scale: scale,
                      child: Container(
                        width: 70,
                        height: 70,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Colors.white.withOpacity(0.3),
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                    );
                  },
                  onEnd: () {
                    if (mounted) setState(() {});
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
