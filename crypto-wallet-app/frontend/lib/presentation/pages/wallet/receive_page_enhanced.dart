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
  bool _loading = true;
  bool _copied = false;
  Color _currentHeaderColor = const Color(0xFFF7931A);

  // Coin data with colors and networks
  final List<CoinData> _coins = [
    CoinData('BTC', 'Bitcoin', const Color(0xFFF7931A), Icons.currency_bitcoin, 'Bitcoin Network'),
    CoinData('ETH', 'Ethereum', const Color(0xFF627EEA), Icons.diamond, 'Ethereum (ERC20)'),
    CoinData('BNB', 'BNB Chain', const Color(0xFFF0B90B), Icons.hexagon, 'BNB Smart Chain (BEP20)'),
    CoinData('USDT-BEP20', 'USDT BEP20', const Color(0xFF26A17B), Icons.attach_money, 'BNB Smart Chain'),
    CoinData('USDT-ERC20', 'USDT ERC20', const Color(0xFF26A17B), Icons.attach_money, 'Ethereum Network'),
    CoinData('SOL', 'Solana', const Color(0xFF9945FF), Icons.flash_on, 'Solana Network'),
    CoinData('XRP', 'Ripple', const Color(0xFF23292F), Icons.water_drop, 'XRP Ledger'),
    CoinData('TRX', 'Tron', const Color(0xFFEB0029), Icons.bolt, 'TRON Network'),
    CoinData('LTC', 'Litecoin', const Color(0xFFBFBBBB), Icons.currency_exchange, 'Litecoin Network'),
    CoinData('DOGE', 'Dogecoin', const Color(0xFFC2A633), Icons.pets, 'Dogecoin Network'),
  ];

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

  Future<void> _loadAddress() async {
    try {
      final addresses = await _walletService.getStoredAddresses(_selectedCoin);
      if (addresses.isNotEmpty) {
        setState(() {
          _address = addresses.first;
          _loading = false;
        });
      } else {
        // Try to generate address
        await _generateNewAddress();
      }
    } catch (e) {
      setState(() {
        _address = null;
        _loading = false;
      });
    }
  }

  Future<void> _generateNewAddress() async {
    setState(() => _loading = true);
    try {
      final result = await _walletService.generateAddressFor(_selectedCoin);
      final newAddress = result['address'];
      setState(() {
        _address = newAddress;
        _loading = false;
      });
    } catch (e) {
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
        itemCount: _coins.length,
        itemBuilder: (context, index) {
          final coin = _coins[index];
          final isSelected = coin.symbol == _selectedCoin;
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
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: isSelected ? coin.color : Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? coin.color : Colors.grey[300]!,
                          width: isSelected ? 3 : 2,
                        ),
                        boxShadow: isSelected
                            ? [BoxShadow(color: coin.color.withOpacity(0.5), blurRadius: 15, offset: const Offset(0, 5))]
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
                  ),
                  const SizedBox(height: 6),
                  Text(
                    coin.symbol.split('-').first,
                    style: TextStyle(
                      color: isSelected ? coin.color : Colors.grey[600],
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
              Text(
                'Your ${_selectedCoin.split('-').first} Address',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
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
                    _address ?? 'No address available',
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
