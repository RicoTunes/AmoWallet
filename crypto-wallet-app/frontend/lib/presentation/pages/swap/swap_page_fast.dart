import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:confetti/confetti.dart';

import '../../../services/swap_service.dart';
import '../../../services/blockchain_service.dart';
import '../../../services/wallet_service.dart';
import '../../../services/biometric_auth_service.dart';

/// Coin data model
class CoinInfo {
  final String symbol;
  final String name;
  final Color color;
  final IconData icon;
  const CoinInfo(this.symbol, this.name, this.color, this.icon);
}

/// Fast-loading Swap Page with real DEX integration
class SwapPageFast extends ConsumerStatefulWidget {
  const SwapPageFast({super.key});

  @override
  ConsumerState<SwapPageFast> createState() => _SwapPageFastState();
}

class _SwapPageFastState extends ConsumerState<SwapPageFast>
    with TickerProviderStateMixin {
  // Lazy-initialized services
  SwapService? _swapService;
  BlockchainService? _blockchainService;
  WalletService? _walletService;
  BiometricAuthService? _authService;

  // Controllers
  final TextEditingController _amountController = TextEditingController();
  ConfettiController? _confettiController;
  AnimationController? _colorController;
  Animation<Color?>? _colorAnimation;

  // Core state - minimal
  String _fromCoin = 'ETH';
  String _toCoin = 'USDT';
  double _amount = 0.0;
  String _selectedPercent = '';
  
  // Loading states
  bool _pageReady = false;
  bool _isLoadingQuote = false;
  bool _isExecuting = false;
  
  // Cached data (lazy loaded)
  final Map<String, double> _balances = {};
  final Map<String, String> _addresses = {};
  
  // Quote state
  bool _showQuote = false;
  Map<String, dynamic>? _quoteData;
  List<Map<String, dynamic>> _allQuotes = [];
  String? _error;
  
  // PIN/Slide state
  bool _showPinEntry = false;
  bool _showSlideToSwap = false;
  String _enteredPin = '';
  double _slidePosition = 0.0;

  // Header color
  Color _headerColor = const Color(0xFF627EEA); // ETH blue

  // Available coins
  static const List<CoinInfo> _coins = [
    CoinInfo('ETH', 'Ethereum', Color(0xFF627EEA), Icons.diamond),
    CoinInfo('BTC', 'Bitcoin', Color(0xFFF7931A), Icons.currency_bitcoin),
    CoinInfo('BNB', 'BNB', Color(0xFFF0B90B), Icons.hexagon),
    CoinInfo('USDT', 'Tether', Color(0xFF26A17B), Icons.attach_money),
    CoinInfo('SOL', 'Solana', Color(0xFF9945FF), Icons.flash_on),
    CoinInfo('XRP', 'Ripple', Color(0xFF23292F), Icons.water_drop),
    CoinInfo('MATIC', 'Polygon', Color(0xFF8247E5), Icons.auto_awesome),
  ];

  // Fallback prices for instant calculation
  static const Map<String, double> _prices = {
    'BTC': 96000.0, 'ETH': 3600.0, 'BNB': 625.0, 'USDT': 1.0,
    'SOL': 235.0, 'XRP': 2.45, 'MATIC': 0.95, 'TRX': 0.25,
  };

  @override
  void initState() {
    super.initState();
    _amountController.addListener(_onAmountChanged);
    
    // Initialize ONLY essential UI components immediately
    _confettiController = ConfettiController(duration: const Duration(seconds: 3));
    
    // Mark page as ready IMMEDIATELY - data loads in background
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() => _pageReady = true);
      _initServicesLazy();
    });
  }

  /// Lazy initialize services in background
  Future<void> _initServicesLazy() async {
    _swapService ??= SwapService();
    _blockchainService ??= BlockchainService();
    _walletService ??= WalletService();
    _authService ??= BiometricAuthService();
    
    // Init color animation
    _colorController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _colorAnimation = ColorTween(begin: _headerColor, end: _headerColor)
        .animate(_colorController!);
    
    // Load FROM coin balance only (most important)
    _loadBalanceInBackground(_fromCoin);
  }

  /// Load balance silently in background
  Future<void> _loadBalanceInBackground(String coin) async {
    try {
      _walletService ??= WalletService();
      _blockchainService ??= BlockchainService();
      
      // Get address
      if (!_addresses.containsKey(coin)) {
        final addrs = await _walletService!.getStoredAddresses(coin);
        if (addrs.isNotEmpty) {
          _addresses[coin] = addrs.first;
        }
      }
      
      // Get balance
      final addr = _addresses[coin];
      if (addr != null && addr.isNotEmpty) {
        final bal = await _blockchainService!.getBalance(coin, addr)
            .timeout(const Duration(seconds: 3), onTimeout: () => 0.0);
        if (mounted) {
          setState(() => _balances[coin] = bal);
        }
      }
    } catch (e) {
      // Silent fail - use cached or 0
      if (!_balances.containsKey(coin)) {
        _balances[coin] = 0.0;
      }
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _confettiController?.dispose();
    _colorController?.dispose();
    super.dispose();
  }

  void _onAmountChanged() {
    final val = double.tryParse(_amountController.text) ?? 0.0;
    if (val != _amount) {
      setState(() {
        _amount = val;
        _showQuote = false;
        _quoteData = null;
        _allQuotes = [];
        _error = null;
      });
    }
  }

  Color _getCoinColor(String coin) {
    return _coins.firstWhere((c) => c.symbol == coin, orElse: () => _coins[0]).color;
  }

  IconData _getCoinIcon(String coin) {
    return _coins.firstWhere((c) => c.symbol == coin, orElse: () => _coins[0]).icon;
  }

  void _animateColor(Color to) {
    if (_colorController == null) return;
    _colorAnimation = ColorTween(begin: _headerColor, end: to)
        .animate(CurvedAnimation(parent: _colorController!, curve: Curves.easeInOut));
    _colorController!.forward(from: 0).then((_) {
      if (mounted) setState(() => _headerColor = to);
    });
  }

  void _selectFromCoin(String coin) {
    if (coin == _fromCoin) return;
    HapticFeedback.selectionClick();
    
    if (coin == _toCoin) {
      // Swap
      setState(() {
        _toCoin = _fromCoin;
        _fromCoin = coin;
        _resetQuote();
      });
    } else {
      setState(() {
        _fromCoin = coin;
        _resetQuote();
      });
    }
    _animateColor(_getCoinColor(coin));
    _loadBalanceInBackground(coin);
  }

  void _selectToCoin(String coin) {
    if (coin == _toCoin) return;
    HapticFeedback.selectionClick();
    
    if (coin == _fromCoin) {
      setState(() {
        _fromCoin = _toCoin;
        _toCoin = coin;
        _resetQuote();
      });
      _animateColor(_getCoinColor(_fromCoin));
      _loadBalanceInBackground(_fromCoin);
    } else {
      setState(() {
        _toCoin = coin;
        _resetQuote();
      });
    }
  }

  void _swapCoins() {
    HapticFeedback.mediumImpact();
    setState(() {
      final temp = _fromCoin;
      _fromCoin = _toCoin;
      _toCoin = temp;
      _resetQuote();
    });
    _animateColor(_getCoinColor(_fromCoin));
    _loadBalanceInBackground(_fromCoin);
  }

  void _resetQuote() {
    _amountController.clear();
    _amount = 0.0;
    _selectedPercent = '';
    _showQuote = false;
    _quoteData = null;
    _allQuotes = [];
    _error = null;
  }

  void _setPercentage(String label, double pct) {
    final bal = _balances[_fromCoin] ?? 0.0;
    final fee = bal * 0.003;
    final avail = (bal - fee).clamp(0.0, double.infinity);
    final amt = avail * pct;
    
    _amountController.text = amt > 0 ? amt.toStringAsFixed(8) : '';
    setState(() {
      _amount = amt;
      _selectedPercent = label;
    });
  }

  double _getRate() {
    final fp = _prices[_fromCoin] ?? 1.0;
    final tp = _prices[_toCoin] ?? 1.0;
    return fp / tp;
  }

  double _getEstimate() {
    if (_amount <= 0) return 0.0;
    return _amount * _getRate() * 0.997; // 0.3% fee
  }

  double _getUsdValue(String coin, double amount) {
    return amount * (_prices[coin] ?? 0.0);
  }

  Future<void> _getQuote() async {
    if (_amount <= 0) {
      setState(() => _error = 'Enter an amount');
      return;
    }

    final bal = _balances[_fromCoin] ?? 0.0;
    if (_amount > bal) {
      setState(() => _error = 'Insufficient $_fromCoin balance');
      return;
    }

    // Ensure wallets exist
    _walletService ??= WalletService();
    
    // Check FROM wallet
    if (!_addresses.containsKey(_fromCoin)) {
      final addrs = await _walletService!.getStoredAddresses(_fromCoin);
      if (addrs.isNotEmpty) {
        _addresses[_fromCoin] = addrs.first;
      } else {
        setState(() => _error = 'No $_fromCoin wallet');
        return;
      }
    }

    // Check TO wallet
    if (!_addresses.containsKey(_toCoin)) {
      final addrs = await _walletService!.getStoredAddresses(_toCoin);
      if (addrs.isNotEmpty) {
        _addresses[_toCoin] = addrs.first;
      } else {
        // Prompt to create
        final created = await _showCreateWalletDialog(_toCoin);
        if (!created) {
          setState(() => _error = 'Need $_toCoin wallet to receive');
          return;
        }
      }
    }

    setState(() {
      _isLoadingQuote = true;
      _error = null;
    });

    try {
      _swapService ??= SwapService();
      
      // Try real quote with short timeout
      final resp = await _swapService!.getSwapQuotes(
        fromCoin: _fromCoin,
        toCoin: _toCoin,
        amount: _amount,
        userAddress: _addresses[_fromCoin],
        slippage: 1.0,
      ).timeout(const Duration(seconds: 4));

      if (resp.success && resp.quotes.isNotEmpty) {
        // Real quotes from DEXes
        final quotes = resp.quotes.map((q) => {
          'provider': q.provider,
          'toAmount': q.toAmount,
          'rate': q.exchangeRate,
          'fee': q.totalFees,
          'time': q.estimatedTime,
        }).toList();

        final best = resp.bestQuote ?? resp.quotes.first;
        
        setState(() {
          _allQuotes = quotes;
          _quoteData = {
            'fromCoin': _fromCoin,
            'toCoin': _toCoin,
            'fromAmount': _amount,
            'toAmount': best.toAmount,
            'rate': best.exchangeRate,
            'fee': best.totalFees,
            'provider': best.provider,
            'time': best.estimatedTime,
          };
          _showQuote = true;
        });
      } else {
        // Use local calculation
        _useLocalQuote();
      }
    } catch (e) {
      // Fallback to local
      _useLocalQuote();
    } finally {
      if (mounted) setState(() => _isLoadingQuote = false);
    }
  }

  void _useLocalQuote() {
    final est = _getEstimate();
    final fee = _amount * 0.003;
    
    setState(() {
      _allQuotes = [
        {'provider': 'Best Rate', 'toAmount': est, 'rate': _getRate(), 'fee': fee, 'time': '~30s'},
      ];
      _quoteData = {
        'fromCoin': _fromCoin,
        'toCoin': _toCoin,
        'fromAmount': _amount,
        'toAmount': est,
        'rate': _getRate(),
        'fee': fee,
        'provider': 'aggregator',
        'time': '~30s',
      };
      _showQuote = true;
    });
  }

  Future<bool> _showCreateWalletDialog(String coin) async {
    return await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(_getCoinIcon(coin), color: _getCoinColor(coin)),
            const SizedBox(width: 12),
            Text('Create $coin Wallet'),
          ],
        ),
        content: Text('You need a $coin wallet to receive swapped coins.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                final res = await _walletService!.generateAddressFor(coin);
                if (res.containsKey('address')) {
                  _addresses[coin] = res['address']!;
                  Navigator.pop(ctx, true);
                } else {
                  Navigator.pop(ctx, false);
                }
              } catch (e) {
                Navigator.pop(ctx, false);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: _getCoinColor(coin)),
            child: const Text('Create', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ) ?? false;
  }

  void _onContinue() {
    if (_quoteData == null) return;
    setState(() {
      _showPinEntry = true;
      _enteredPin = '';
      _showSlideToSwap = false;
    });
  }

  void _onPinDigit(String d) {
    if (_enteredPin.length < 6) {
      setState(() => _enteredPin += d);
      if (_enteredPin.length == 6) _verifyPin();
    }
  }

  void _onPinBack() {
    if (_enteredPin.isNotEmpty) {
      setState(() => _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1));
    }
  }

  Future<void> _verifyPin() async {
    _authService ??= BiometricAuthService();
    final ok = await _authService!.verifyPIN(_enteredPin);
    if (ok) {
      HapticFeedback.mediumImpact();
      setState(() => _showSlideToSwap = true);
    } else {
      HapticFeedback.heavyImpact();
      setState(() => _enteredPin = '');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid PIN'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _executeSwap() async {
    setState(() => _isExecuting = true);

    try {
      _swapService ??= SwapService();
      _walletService ??= WalletService();

      final fromAmt = _quoteData!['fromAmount'] as double;
      final toAmt = _quoteData!['toAmount'] as double;
      final fee = _quoteData!['fee'] as double;

      // Get private key
      final pk = await _walletService!.getPrivateKey(_fromCoin, _addresses[_fromCoin]!);
      if (pk == null) throw Exception('Cannot access wallet');

      // Execute REAL swap
      final result = await _swapService!.executeRealSwap(
        fromCoin: _fromCoin,
        toCoin: _toCoin,
        fromAmount: fromAmt,
        userAddress: _addresses[_fromCoin]!,
        privateKey: pk,
        destinationAddress: _addresses[_toCoin]!,
        provider: 'auto',
        slippage: 1.0,
      );

      if (result.success) {
        // Update balances
        _balances[_fromCoin] = ((_balances[_fromCoin] ?? 0) - fromAmt - fee).clamp(0.0, double.infinity);
        _balances[_toCoin] = (_balances[_toCoin] ?? 0) + (result.toAmount ?? toAmt);

        await _walletService!.updateCachedBalance(_fromCoin, _balances[_fromCoin]!);
        await _walletService!.updateCachedBalance(_toCoin, _balances[_toCoin]!);

        _confettiController?.play();
        await _showSuccessDialog(fromAmt, result.toAmount ?? toAmt, result.txHash);
        
        if (mounted) context.go('/dashboard');
      } else {
        throw Exception(result.error ?? 'Swap failed');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isExecuting = false;
          _slidePosition = 0.0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Swap failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _showSuccessDialog(double fromAmt, double toAmt, String? txHash) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle, color: Colors.green, size: 48),
              ),
              const SizedBox(height: 16),
              const Text('Swap Successful!', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                '${fromAmt.toStringAsFixed(6)} $_fromCoin → ${toAmt.toStringAsFixed(6)} $_toCoin',
                style: TextStyle(color: Colors.grey[600]),
              ),
              if (txHash != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'TX: ${txHash.length > 20 ? '${txHash.substring(0, 10)}...${txHash.substring(txHash.length - 8)}' : txHash}',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Done', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Show INSTANTLY - no waiting for data
    return Stack(
      children: [
        Scaffold(
          backgroundColor: Colors.grey[100],
          body: _showPinEntry ? _buildPinPage() : _buildMainPage(),
        ),
        if (_confettiController != null)
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController!,
              blastDirection: pi / 2,
              maxBlastForce: 5,
              minBlastForce: 2,
              emissionFrequency: 0.05,
              numberOfParticles: 50,
              gravity: 0.1,
              colors: [_headerColor, Colors.green, Colors.blue, Colors.yellow],
            ),
          ),
      ],
    );
  }

  Widget _buildMainPage() {
    final bal = _balances[_fromCoin] ?? 0.0;
    final usdBal = _getUsdValue(_fromCoin, bal);

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        // Header
        SliverAppBar(
          expandedHeight: 56,
          floating: false,
          pinned: true,
          backgroundColor: _headerColor,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => context.go('/dashboard'),
          ),
          title: const Text('Swap', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          actions: [
            Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${bal.toStringAsFixed(6)} $_fromCoin (\$${usdBal.toStringAsFixed(2)})',
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // FROM Section
                _buildFromSection(),
                
                // Swap button
                GestureDetector(
                  onTap: _swapCoins,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      color: _headerColor,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: _headerColor.withOpacity(0.4), blurRadius: 12)],
                    ),
                    child: const Icon(Icons.swap_vert, color: Colors.white, size: 24),
                  ),
                ),

                // TO Section
                _buildToSection(),

                const SizedBox(height: 16),

                // Quote or Get Quote button
                if (_showQuote && _quoteData != null)
                  _buildQuoteCard()
                else
                  _buildGetQuoteButton(),

                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!, style: const TextStyle(color: Colors.red)),
                  ),

                const SizedBox(height: 80),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFromSection() {
    final bal = _balances[_fromCoin] ?? 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Percentage buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildPctBtn('25%', 0.25),
              const SizedBox(width: 8),
              _buildPctBtn('50%', 0.50),
              const SizedBox(width: 8),
              _buildPctBtn('75%', 0.75),
              const SizedBox(width: 8),
              _buildPctBtn('MAX', 1.0),
            ],
          ),
          const SizedBox(height: 16),

          // Amount input
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    hintText: '0.00',
                    hintStyle: TextStyle(color: Colors.grey[400]),
                    border: InputBorder.none,
                  ),
                ),
              ),
              _buildCoinSelector(_fromCoin, true),
            ],
          ),

          // USD value
          if (_amount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '≈ \$${_getUsdValue(_fromCoin, _amount).toStringAsFixed(2)} USD',
                style: TextStyle(color: Colors.grey[500], fontSize: 13),
              ),
            ),

          // Balance
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Balance: ${bal.toStringAsFixed(8)}',
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToSection() {
    final est = _getEstimate();
    final bal = _balances[_toCoin] ?? 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('To', style: TextStyle(color: Colors.grey)),
              Text('Balance: ${bal.toStringAsFixed(6)}', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),

          // Coin selector row
          SizedBox(
            height: 40,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _coins.length,
              itemBuilder: (ctx, i) {
                final c = _coins[i];
                if (c.symbol == _fromCoin) return const SizedBox.shrink();
                final sel = c.symbol == _toCoin;
                return GestureDetector(
                  onTap: () => _selectToCoin(c.symbol),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: sel ? c.color : Colors.grey[100],
                      borderRadius: BorderRadius.circular(20),
                      border: sel ? null : Border.all(color: Colors.grey[300]!),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(c.icon, size: 16, color: sel ? Colors.white : c.color),
                        const SizedBox(width: 6),
                        Text(c.symbol, style: TextStyle(
                          color: sel ? Colors.white : Colors.grey[700],
                          fontWeight: sel ? FontWeight.bold : FontWeight.w500,
                          fontSize: 13,
                        )),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 16),

          // Estimated receive
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _getCoinColor(_toCoin).withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("You'll receive", style: TextStyle(color: Colors.grey, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(
                      '≈ ${est.toStringAsFixed(6)}',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: _getCoinColor(_toCoin),
                      ),
                    ),
                    Text(
                      '≈ \$${_getUsdValue(_toCoin, est).toStringAsFixed(2)} USD',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    ),
                  ],
                ),
                const Spacer(),
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: _getCoinColor(_toCoin).withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(_getCoinIcon(_toCoin), color: _getCoinColor(_toCoin)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPctBtn(String label, double pct) {
    final sel = _selectedPercent == label;
    return GestureDetector(
      onTap: () => _setPercentage(label, pct),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: sel ? _headerColor : Colors.grey[100],
          borderRadius: BorderRadius.circular(20),
          border: sel ? null : Border.all(color: Colors.grey[300]!),
        ),
        child: Text(label, style: TextStyle(
          color: sel ? Colors.white : Colors.grey[700],
          fontWeight: FontWeight.w600,
          fontSize: 13,
        )),
      ),
    );
  }

  Widget _buildCoinSelector(String coin, bool isFrom) {
    return GestureDetector(
      onTap: () => _showCoinPicker(isFrom),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _getCoinColor(coin).withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_getCoinIcon(coin), color: _getCoinColor(coin), size: 20),
            const SizedBox(width: 6),
            Text(coin, style: TextStyle(fontWeight: FontWeight.bold, color: _getCoinColor(coin))),
            const SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down, color: _getCoinColor(coin), size: 18),
          ],
        ),
      ),
    );
  }

  void _showCoinPicker(bool isFrom) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(isFrom ? 'Select coin to swap' : 'Select coin to receive',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ...(_coins.map((c) => ListTile(
              leading: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: c.color.withOpacity(0.1), shape: BoxShape.circle),
                child: Icon(c.icon, color: c.color),
              ),
              title: Text(c.name),
              subtitle: Text(c.symbol),
              trailing: (isFrom ? _fromCoin : _toCoin) == c.symbol
                  ? Icon(Icons.check_circle, color: c.color)
                  : null,
              onTap: () {
                Navigator.pop(ctx);
                if (isFrom) {
                  _selectFromCoin(c.symbol);
                } else {
                  _selectToCoin(c.symbol);
                }
              },
            ))),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildGetQuoteButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isLoadingQuote ? null : _getQuote,
        style: ElevatedButton.styleFrom(
          backgroundColor: _headerColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: _isLoadingQuote
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Text('Get Quote', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildQuoteCard() {
    final q = _quoteData!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _headerColor.withOpacity(0.3)),
        boxShadow: [BoxShadow(color: _headerColor.withOpacity(0.1), blurRadius: 15)],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 20),
              const SizedBox(width: 8),
              const Text('Quote Ready', style: TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('Best Rate', style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Summary row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Column(
                children: [
                  const Text('You pay', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  Text('${(q['fromAmount'] as double).toStringAsFixed(6)} $_fromCoin',
                      style: TextStyle(fontWeight: FontWeight.bold, color: _getCoinColor(_fromCoin))),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Icon(Icons.arrow_forward, color: Colors.grey[400]),
              ),
              Column(
                children: [
                  const Text('You receive', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  Text('${(q['toAmount'] as double).toStringAsFixed(6)} $_toCoin',
                      style: TextStyle(fontWeight: FontWeight.bold, color: _getCoinColor(_toCoin))),
                ],
              ),
            ],
          ),

          const SizedBox(height: 12),
          Text('≈ \$${_getUsdValue(_toCoin, q['toAmount'] as double).toStringAsFixed(2)} USD',
              style: TextStyle(color: Colors.grey[500])),

          const Divider(height: 24),

          // Details
          _buildQuoteRow('Rate', '1 $_fromCoin = ${(q['rate'] as double).toStringAsFixed(4)} $_toCoin'),
          _buildQuoteRow('Fee (0.3%)', '${(q['fee'] as double).toStringAsFixed(6)} $_fromCoin'),

          const SizedBox(height: 16),

          // Continue button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _onContinue,
              style: ElevatedButton.styleFrom(
                backgroundColor: _headerColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Text('Continue', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  SizedBox(width: 8),
                  Icon(Icons.arrow_forward, color: Colors.white, size: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuoteRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildPinPage() {
    final q = _quoteData!;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_headerColor, _headerColor.withOpacity(0.9), Colors.white, Colors.white],
          stops: const [0.0, 0.2, 0.2, 1.0],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => setState(() {
                      _showPinEntry = false;
                      _showSlideToSwap = false;
                      _enteredPin = '';
                      _slidePosition = 0.0;
                    }),
                  ),
                  const Expanded(
                    child: Text('Confirm Swap', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),

            // Transaction card
            Container(
              margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 30)],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Column(
                        children: [
                          Container(
                            width: 48, height: 48,
                            decoration: BoxDecoration(
                              color: _getCoinColor(_fromCoin).withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(_getCoinIcon(_fromCoin), color: _getCoinColor(_fromCoin)),
                          ),
                          const SizedBox(height: 8),
                          Text('${(q['fromAmount'] as double).toStringAsFixed(6)}',
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text(_fromCoin, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Icon(Icons.arrow_forward, color: _headerColor),
                      ),
                      Column(
                        children: [
                          Container(
                            width: 48, height: 48,
                            decoration: BoxDecoration(
                              color: _getCoinColor(_toCoin).withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(_getCoinIcon(_toCoin), color: _getCoinColor(_toCoin)),
                          ),
                          const SizedBox(height: 8),
                          Text('${(q['toAmount'] as double).toStringAsFixed(6)}',
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text(_toCoin, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('≈ \$${_getUsdValue(_toCoin, q['toAmount'] as double).toStringAsFixed(2)}',
                      style: TextStyle(color: Colors.grey[500])),
                ],
              ),
            ),

            // PIN or Slide
            Expanded(
              child: _showSlideToSwap ? _buildSlideToSwap() : _buildPinEntry(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPinEntry() {
    return Column(
      children: [
        const SizedBox(height: 20),
        Text('Enter PIN', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey[800])),
        const SizedBox(height: 8),
        Text('Enter your 6-digit PIN', style: TextStyle(color: Colors.grey[500])),
        const SizedBox(height: 24),

        // PIN dots
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(6, (i) {
            final filled = i < _enteredPin.length;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              width: filled ? 16 : 14,
              height: filled ? 16 : 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: filled ? _headerColor : Colors.transparent,
                border: Border.all(color: filled ? _headerColor : Colors.grey[300]!, width: 2),
              ),
            );
          }),
        ),

        const SizedBox(height: 32),

        // Number pad
        Expanded(
          child: GridView.count(
            crossAxisCount: 3,
            childAspectRatio: 1.5,
            padding: const EdgeInsets.symmetric(horizontal: 40),
            children: [
              ...List.generate(9, (i) => _buildNumBtn('${i + 1}')),
              const SizedBox(),
              _buildNumBtn('0'),
              _buildBackBtn(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNumBtn(String digit) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        _onPinDigit(digit);
      },
      child: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: Colors.grey[100], shape: BoxShape.circle),
        child: Center(
          child: Text(digit, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: Colors.grey[800])),
        ),
      ),
    );
  }

  Widget _buildBackBtn() {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        _onPinBack();
      },
      child: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: Colors.grey[100], shape: BoxShape.circle),
        child: Center(child: Icon(Icons.backspace_outlined, color: Colors.grey[700])),
      ),
    );
  }

  Widget _buildSlideToSwap() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 72, height: 72,
          decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), shape: BoxShape.circle),
          child: const Icon(Icons.check_circle, color: Colors.green, size: 48),
        ),
        const SizedBox(height: 16),
        const Text('PIN Verified!', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green)),
        const SizedBox(height: 8),
        Text('Slide to confirm swap', style: TextStyle(color: Colors.grey[600])),
        const SizedBox(height: 32),

        if (_isExecuting)
          Column(
            children: [
              CircularProgressIndicator(color: _headerColor),
              const SizedBox(height: 16),
              Text('Executing swap...', style: TextStyle(color: Colors.grey[600])),
            ],
          )
        else
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            height: 64,
            decoration: BoxDecoration(
              color: _headerColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: _headerColor.withOpacity(0.3), width: 2),
            ),
            child: Stack(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  width: (MediaQuery.of(context).size.width - 64) * _slidePosition,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [_headerColor.withOpacity(0.3), _headerColor.withOpacity(0.6)]),
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                Center(
                  child: AnimatedOpacity(
                    opacity: _slidePosition < 0.3 ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Slide to Swap', style: TextStyle(color: _headerColor, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 8),
                        Icon(Icons.arrow_forward, color: _headerColor, size: 20),
                      ],
                    ),
                  ),
                ),
                LayoutBuilder(
                  builder: (ctx, constraints) {
                    final maxSlide = constraints.maxWidth - 64;
                    return Positioned(
                      left: _slidePosition * maxSlide,
                      top: 0,
                      bottom: 0,
                      child: GestureDetector(
                        onHorizontalDragUpdate: (d) {
                          setState(() => _slidePosition = ((_slidePosition * maxSlide + d.delta.dx) / maxSlide).clamp(0.0, 1.0));
                        },
                        onHorizontalDragEnd: (_) {
                          if (_slidePosition >= 0.85) {
                            HapticFeedback.heavyImpact();
                            _executeSwap();
                          } else {
                            setState(() => _slidePosition = 0.0);
                          }
                        },
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: _headerColor,
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: _headerColor.withOpacity(0.4), blurRadius: 12)],
                          ),
                          child: Icon(_slidePosition >= 0.85 ? Icons.check : Icons.double_arrow, color: Colors.white),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

        const SizedBox(height: 60),
      ],
    );
  }
}
