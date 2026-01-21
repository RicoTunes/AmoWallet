import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:ui' as ui;
import 'dart:typed_data';

import '../../../services/wallet_service.dart';
import '../../../services/blockchain_service.dart';

class ReceivePageEnhanced extends ConsumerStatefulWidget {
  final String? initialCoin;
  
  const ReceivePageEnhanced({super.key, this.initialCoin});

  @override
  ConsumerState<ReceivePageEnhanced> createState() => _ReceivePageEnhancedState();
}

class _ReceivePageEnhancedState extends ConsumerState<ReceivePageEnhanced>
    with TickerProviderStateMixin {
  final WalletService _walletService = WalletService();
  final BlockchainService _blockchainService = BlockchainService();

  late AnimationController _colorAnimationController;
  late Animation<Color?> _headerColorAnimation;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  String _selectedCoin = 'BTC';
  String? _address;
  List<String> _allAddresses = []; // Store all addresses for the coin
  bool _loading = true;
  bool _copied = false;
  Color _currentHeaderColor = const Color(0xFFF7931A);

  // Main coins (USDT is grouped, networks shown separately)
  final List<CoinData> _mainCoins = [
    CoinData('BTC', 'Bitcoin', const Color(0xFFF7931A), Icons.currency_bitcoin, 'Bitcoin Network'),
    CoinData('ETH', 'Ethereum', const Color(0xFF627EEA), Icons.diamond, 'Ethereum (ERC20)'),
    CoinData('BNB', 'BNB Chain', const Color(0xFFF0B90B), Icons.hexagon, 'BNB Smart Chain (BEP20)'),
    CoinData('USDT', 'Tether', const Color(0xFF26A17B), Icons.attach_money, 'Select Network'),
    CoinData('SOL', 'Solana', const Color(0xFF9945FF), Icons.flash_on, 'Solana Network'),
    CoinData('TRX', 'Tron', const Color(0xFFEB0029), Icons.bolt, 'TRON Network'),
    CoinData('LTC', 'Litecoin', const Color(0xFFBFBBBB), Icons.currency_exchange, 'Litecoin Network'),
    CoinData('DOGE', 'Dogecoin', const Color(0xFFC2A633), Icons.pets, 'Dogecoin Network'),
  ];

  // USDT network options
  final List<CoinData> _usdtNetworks = [
    CoinData('USDT-TRC20', 'TRC20 (Tron)', const Color(0xFFEB0029), Icons.bolt, 'TRON Network - Low fees'),
    CoinData('USDT-BEP20', 'BEP20 (BSC)', const Color(0xFFF0B90B), Icons.hexagon, 'BNB Smart Chain - Low fees'),
    CoinData('USDT-ERC20', 'ERC20 (Ethereum)', const Color(0xFF627EEA), Icons.diamond, 'Ethereum Network - Higher fees'),
  ];

  // Combined coin data for lookups
  List<CoinData> get _coins => [..._mainCoins, ..._usdtNetworks];

  @override
  void initState() {
    super.initState();
    _selectedCoin = widget.initialCoin ?? 'BTC';
    _currentHeaderColor = _getCoinColor(_selectedCoin);

    _colorAnimationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _headerColorAnimation = ColorTween(
      begin: _currentHeaderColor,
      end: _currentHeaderColor,
    ).animate(CurvedAnimation(
      parent: _colorAnimationController,
      curve: Curves.easeInOut,
    ));

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _loadAddress();
  }

  @override
  void dispose() {
    _colorAnimationController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Color _getCoinColor(String coin) {
    return _coins.firstWhere(
      (c) => c.symbol == coin,
      orElse: () => _coins.first,
    ).color;
  }

  CoinData _getCoinData(String coin) {
    return _coins.firstWhere(
      (c) => c.symbol == coin,
      orElse: () => _coins.first,
    );
  }

  void _animateToColor(Color newColor) {
    _headerColorAnimation = ColorTween(
      begin: _currentHeaderColor,
      end: newColor,
    ).animate(CurvedAnimation(
      parent: _colorAnimationController,
      curve: Curves.easeInOut,
    ));
    _colorAnimationController.forward(from: 0).then((_) {
      setState(() {
        _currentHeaderColor = newColor;
      });
    });
  }

  void _onCoinSelected(String coin) {
    // If USDT is selected, show network picker
    if (coin == 'USDT') {
      _showUsdtNetworkPicker();
      return;
    }
    
    if (coin != _selectedCoin) {
      HapticFeedback.selectionClick();
      setState(() {
        _selectedCoin = coin;
        _loading = true;
        _copied = false;
      });
      _animateToColor(_getCoinColor(coin));
      _loadAddress();
    }
  }

  void _showUsdtNetworkPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Title
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF26A17B).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.attach_money, color: Color(0xFF26A17B), size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Select USDT Network',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Choose your preferred network',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Network options
            ..._usdtNetworks.map((network) => _buildNetworkOption(network)),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildNetworkOption(CoinData network) {
    final isSelected = _selectedCoin == network.symbol;
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        HapticFeedback.selectionClick();
        setState(() {
          _selectedCoin = network.symbol;
          _loading = true;
          _copied = false;
        });
        _animateToColor(network.color);
        _loadAddress();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? network.color.withOpacity(0.1) : null,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: network.color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(network.icon, color: network.color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    network.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: isSelected ? network.color : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    network.network,
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: network.color, size: 22)
            else
              Icon(Icons.arrow_forward_ios, color: Colors.grey[400], size: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _loadAddress() async {
    try {
      final addresses = await _walletService.getStoredAddresses(_selectedCoin);
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

  Future<void> _generateNewAddress() async {
    print('🟢 _generateNewAddress called for $_selectedCoin');
    setState(() => _loading = true);
    try {
      print('🟡 Calling walletService.generateAddressFor($_selectedCoin)');
      final result = await _walletService.generateAddressFor(_selectedCoin);
      print('🟢 Got result: $result');
      final newAddress = result['address'];
      
      // Reload all addresses to include the new one
      final addresses = await _walletService.getStoredAddresses(_selectedCoin);
      
      setState(() {
        _allAddresses = addresses;
        _address = newAddress; // Select the newly created address
        _loading = false;
      });
      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text('New $_selectedCoin address created!'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      print('🔴 Error generating address: $e');
      setState(() {
        _address = null;
        _loading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate address: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _copyAddress() async {
    if (_address == null) return;
    
    await Clipboard.setData(ClipboardData(text: _address!));
    HapticFeedback.mediumImpact();
    
    setState(() => _copied = true);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            const Text('Address copied to clipboard'),
          ],
        ),
        backgroundColor: _currentHeaderColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );

    // Reset copied state after delay
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  Future<void> _shareAddress() async {
    if (_address == null) return;
    
    final coinData = _getCoinData(_selectedCoin);
    final shareText = 'My ${coinData.name} (${_selectedCoin.split('-').first}) address:\n$_address';
    
    await Clipboard.setData(ClipboardData(text: shareText));
    HapticFeedback.mediumImpact();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Address ready to share'),
        backgroundColor: _currentHeaderColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _colorAnimationController,
      builder: (context, child) {
        final color = _headerColorAnimation.value ?? _currentHeaderColor;
        return Scaffold(
          backgroundColor: Colors.grey[100],
          body: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // Header
              SliverAppBar(
                expandedHeight: 100,
                floating: false,
                pinned: true,
                backgroundColor: color,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => context.go('/dashboard'),
                ),
                title: const Text(
                  'Receive',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                  ),
                ),
                actions: [
                  // Create new address button
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: IconButton(
                      icon: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.add, color: Colors.white),
                      onPressed: _loading ? null : _generateNewAddress,
                      tooltip: 'Create new address',
                    ),
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [color, color.withOpacity(0.85)],
                      ),
                    ),
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Coin Selection
                      const Text(
                        'Select Coin',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildCoinSelector(),

                      const SizedBox(height: 24),

                      // QR Code Card
                      _buildQrCard(color),

                      const SizedBox(height: 16),

                      // Address Card
                      _buildAddressCard(color),

                      const SizedBox(height: 16),

                      // Action Buttons
                      _buildActionButtons(color),

                      const SizedBox(height: 24),

                      // Warning Card
                      _buildWarningCard(color),

                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCoinSelector() {
    return SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _mainCoins.length,
        itemBuilder: (context, index) {
          final coin = _mainCoins[index];
          // For USDT, check if any USDT network is selected
          final isUsdtSelected = coin.symbol == 'USDT' && _selectedCoin.startsWith('USDT');
          final isSelected = coin.symbol == _selectedCoin || isUsdtSelected;
          // Get the actual color (for USDT use the selected network color)
          final displayColor = isUsdtSelected ? _getCoinColor(_selectedCoin) : coin.color;
          
          return GestureDetector(
            onTap: () => _onCoinSelected(coin.symbol),
            child: Container(
              width: 80,
              margin: const EdgeInsets.only(right: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedScale(
                    scale: isSelected ? 1.15 : 1.0,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutBack,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: isSelected ? displayColor : Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? displayColor : Colors.grey[300]!,
                              width: isSelected ? 3 : 2,
                            ),
                            boxShadow: isSelected
                                ? [BoxShadow(color: displayColor.withOpacity(0.5), blurRadius: 15, offset: const Offset(0, 5))]
                                : [BoxShadow(color: Colors.grey.withOpacity(0.2), blurRadius: 5, offset: const Offset(0, 2))],
                          ),
                          child: Center(
                            child: Icon(
                              coin.icon,
                              color: isSelected ? Colors.white : coin.color,
                              size: 28,
                            ),
                          ),
                        ),
                        // Show network indicator for USDT when selected
                        if (coin.symbol == 'USDT' && isUsdtSelected)
                          Positioned(
                            right: -4,
                            bottom: -4,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: displayColor,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: const Icon(Icons.check, color: Colors.white, size: 10),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    coin.symbol == 'USDT' && isUsdtSelected 
                        ? _selectedCoin.split('-').last  // Show TRC20, BEP20, etc
                        : coin.symbol.split('-').first,
                    style: TextStyle(
                      color: isSelected ? displayColor : Colors.grey[600],
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildQrCard(Color color) {
    final coinData = _getCoinData(_selectedCoin);
    
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          // Network badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lan, size: 14, color: color),
                const SizedBox(width: 6),
                Text(
                  coinData.network,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // QR Code
          _loading
              ? SizedBox(
                  width: 200,
                  height: 200,
                  child: Center(
                    child: CircularProgressIndicator(color: color),
                  ),
                )
              : _address != null
                  ? AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _pulseAnimation.value,
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: color.withOpacity(0.3), width: 3),
                              boxShadow: [
                                BoxShadow(
                                  color: color.withOpacity(0.2),
                                  blurRadius: 20,
                                  spreadRadius: 2,
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
                                color: color,
                              ),
                              dataModuleStyle: QrDataModuleStyle(
                                dataModuleShape: QrDataModuleShape.square,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        );
                      },
                    )
                  : Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline, color: Colors.grey[400], size: 48),
                          const SizedBox(height: 12),
                          Text(
                            'No address available',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: _generateNewAddress,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: color,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Generate Address'),
                          ),
                        ],
                      ),
                    ),

          const SizedBox(height: 20),

          // Scan instruction
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.qr_code_scanner, color: Colors.grey[400], size: 18),
              const SizedBox(width: 6),
              Text(
                'Scan to receive ${_selectedCoin.split('-').first}',
                style: TextStyle(color: Colors.grey[500], fontSize: 13),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAddressCard(Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    'Your ${_selectedCoin.split('-').first} Address',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  if (_allAddresses.length > 1) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_allAddresses.length}',
                        style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (_address != null)
                GestureDetector(
                  onTap: _copyAddress,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _copied ? Colors.green : color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _copied ? Icons.check : Icons.copy,
                          size: 14,
                          color: _copied ? Colors.white : color,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _copied ? 'Copied!' : 'Copy',
                          style: TextStyle(
                            color: _copied ? Colors.white : color,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Address dropdown or single address display
          if (_allAddresses.length > 1)
            _buildAddressDropdown(color)
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: _loading
                  ? Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: color, strokeWidth: 2),
                      ),
                    )
                  : Text(
                      _address ?? 'No address yet. Tap + to create one.',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: _address != null ? Colors.black87 : Colors.grey,
                      ),
                    ),
            ),
        ],
      ),
    );
  }

  Widget _buildAddressDropdown(Color color) {
    // Ensure selected address is in the list
    final selectedAddress = _allAddresses.contains(_address) ? _address : (_allAddresses.isNotEmpty ? _allAddresses.first : null);
    
    if (selectedAddress == null || _allAddresses.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: const Text(
          'No addresses available',
          style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.grey),
        ),
      );
    }
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedAddress,
          isExpanded: true,
          icon: Icon(Icons.keyboard_arrow_down, color: color),
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            color: Colors.black87,
          ),
          dropdownColor: Colors.white,
          borderRadius: BorderRadius.circular(12),
          items: _allAddresses.asMap().entries.map((entry) {
            final index = entry.key;
            final address = entry.value;
            final isSelected = address == selectedAddress;
            return DropdownMenuItem<String>(
              value: address,
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: isSelected ? color : Colors.grey[300],
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.black54,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      address,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) {
              setState(() {
                _address = value;
                _copied = false;
              });
            }
          },
        ),
      ),
    );
  }

  Widget _buildActionButtons(Color color) {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: _copyAddress,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.copy, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'Copy Address',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: _shareAddress,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: color, width: 2),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.share, color: color, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Share',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWarningCard(Color color) {
    final coinData = _getCoinData(_selectedCoin);
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange[200]!),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.orange[100],
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.warning_amber_rounded, color: Colors.orange[700], size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Important',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.orange[800],
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Only send ${coinData.name} (${_selectedCoin.split('-').first}) to this address on the ${coinData.network}. Sending other assets may result in permanent loss.',
                  style: TextStyle(
                    color: Colors.orange[700],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CoinData {
  final String symbol;
  final String name;
  final Color color;
  final IconData icon;
  final String network;

  CoinData(this.symbol, this.name, this.color, this.icon, this.network);
}
