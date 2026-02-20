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

// Coin data model
class SwapCoinData {
  final String symbol;
  final String name;
  final Color color;
  final IconData icon;

  const SwapCoinData(this.symbol, this.name, this.color, this.icon);
}

class SwapPageV2 extends ConsumerStatefulWidget {
  const SwapPageV2({super.key});

  @override
  ConsumerState<SwapPageV2> createState() => _SwapPageV2State();
}

class _SwapPageV2State extends ConsumerState<SwapPageV2>
    with TickerProviderStateMixin {
  // Services - lazy initialized
  late final SwapService _swapService;
  late final BlockchainService _blockchainService;
  late final WalletService _walletService;
  late final BiometricAuthService _authService;

  // Controllers
  final TextEditingController _amountController = TextEditingController();
  late final ConfettiController _confettiController;
  late final AnimationController _colorAnimationController;
  late Animation<Color?> _headerColorAnimation;

  // State - minimal initial state
  String _fromCoin = 'BTC';
  String _toCoin = 'USDT';
  double _amount = 0.0;
  bool _isLoading = false;
  bool _showQuote = false;
  bool _showPinEntry = false;
  bool _showSlideToSwap = false;
  String _enteredPin = '';
  double _slidePosition = 0.0;
  bool _isSliding = false;
  String? _errorMessage;
  
  // Cached data - loaded lazily
  Map<String, double> _balances = {};
  Map<String, String> _addresses = {};
  bool _dataLoaded = false;
  
  // Quote data
  Map<String, dynamic>? _quoteData;
  
  // Selected percentage
  String _selectedPercentage = '';

  // Current header color
  Color _currentHeaderColor = const Color(0xFFF7931A);

  // Coins list with colors
  final List<SwapCoinData> _coins = const [
    SwapCoinData('BTC', 'Bitcoin', Color(0xFFF7931A), Icons.currency_bitcoin),
    SwapCoinData('ETH', 'Ethereum', Color(0xFF627EEA), Icons.diamond),
    SwapCoinData('BNB', 'BNB', Color(0xFFF0B90B), Icons.hexagon),
    SwapCoinData('USDT', 'Tether', Color(0xFF26A17B), Icons.attach_money),
    SwapCoinData('SOL', 'Solana', Color(0xFF9945FF), Icons.flash_on),
    SwapCoinData('XRP', 'Ripple', Color(0xFF23292F), Icons.water_drop),
    SwapCoinData('TRX', 'Tron', Color(0xFFEB0029), Icons.bolt),
    SwapCoinData('LTC', 'Litecoin', Color(0xFFBFBBBB), Icons.currency_exchange),
    SwapCoinData('DOGE', 'Dogecoin', Color(0xFFC2A633), Icons.pets),
    SwapCoinData('MATIC', 'Polygon', Color(0xFF8247E5), Icons.auto_awesome),
  ];

  // Hardcoded fallback prices (updated regularly in production)
  final Map<String, double> _fallbackPrices = {
    'BTC': 96000.0,
    'ETH': 3600.0,
    'BNB': 625.0,
    'USDT': 1.0,
    'SOL': 235.0,
    'XRP': 2.45,
    'TRX': 0.25,
    'LTC': 102.0,
    'DOGE': 0.40,
    'MATIC': 0.95,
  };

  @override
  void initState() {
    super.initState();
    
    // Initialize services
    _swapService = SwapService();
    _blockchainService = BlockchainService();
    _walletService = WalletService();
    _authService = BiometricAuthService();
    
    // Initialize controllers
    _confettiController = ConfettiController(duration: const Duration(seconds: 3));
    _colorAnimationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    
    _headerColorAnimation = ColorTween(
      begin: _currentHeaderColor,
      end: _currentHeaderColor,
    ).animate(CurvedAnimation(
      parent: _colorAnimationController,
      curve: Curves.easeInOut,
    ));
    
    _amountController.addListener(_onAmountChanged);
    
    // Load data lazily after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadEssentialData();
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    _confettiController.dispose();
    _colorAnimationController.dispose();
    super.dispose();
  }

  // Load only essential data - balances for selected coins
  Future<void> _loadEssentialData() async {
    if (_dataLoaded) return;
    
    try {
      // Load addresses for from/to coins only
      await _loadAddressForCoin(_fromCoin);
      await _loadAddressForCoin(_toCoin);
      
      // Load balance only for fromCoin
      await _loadBalanceForCoin(_fromCoin);
      
      setState(() {
        _dataLoaded = true;
      });
    } catch (e) {
      print('Error loading essential data: $e');
      setState(() {
        _dataLoaded = true; // Continue anyway
      });
    }
  }

  Future<void> _loadAddressForCoin(String coin) async {
    if (_addresses.containsKey(coin)) return;
    
    try {
      final addresses = await _walletService.getStoredAddresses(coin);
      if (addresses.isNotEmpty) {
        _addresses[coin] = addresses.first;
      } else {
        // Try to generate address if none exists
        try {
          final result = await _walletService.generateAddressFor(coin);
          if (result.containsKey('address')) {
            _addresses[coin] = result['address']!;
          }
        } catch (e) {
          print('Could not generate address for $coin: $e');
        }
      }
    } catch (e) {
      print('Error loading address for $coin: $e');
    }
  }

  Future<void> _loadBalanceForCoin(String coin, {bool forceRefresh = false}) async {
    // Skip if already cached and not forcing refresh
    if (!forceRefresh && _balances.containsKey(coin) && _balances[coin]! > 0) return;
    
    try {
      // First ensure we have an address
      if (!_addresses.containsKey(coin)) {
        await _loadAddressForCoin(coin);
      }
      
      final address = _addresses[coin];
      if (address != null && address.isNotEmpty) {
        final balance = await _blockchainService.getBalance(coin, address);
        setState(() {
          _balances[coin] = balance;
        });
      } else {
        // No address available, set to 0
        setState(() {
          _balances[coin] = 0.0;
        });
      }
    } catch (e) {
      print('Error loading balance for $coin: $e');
      // Don't cache failed fetches as 0 - leave unset so it can retry
      if (!_balances.containsKey(coin)) {
        setState(() {
          _balances[coin] = 0.0;
        });
      }
    }
  }

  void _onAmountChanged() {
    final text = _amountController.text;
    setState(() {
      _amount = double.tryParse(text) ?? 0.0;
      _showQuote = false;
      _quoteData = null;
      _errorMessage = null;
    });
  }

  Color _getCoinColor(String coin) {
    return _coins.firstWhere(
      (c) => c.symbol == coin,
      orElse: () => _coins.first,
    ).color;
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

  void _onFromCoinSelected(String coin) async {
    if (coin == _fromCoin) return;
    if (coin == _toCoin) {
      // Swap coins
      setState(() {
        final temp = _fromCoin;
        _fromCoin = coin;
        _toCoin = temp;
        _showQuote = false;
        _quoteData = null;
        _selectedPercentage = '';
        _amountController.clear();
        _amount = 0.0;
        _errorMessage = null;
      });
    } else {
      setState(() {
        _fromCoin = coin;
        _showQuote = false;
        _quoteData = null;
        _selectedPercentage = '';
        _amountController.clear();
        _amount = 0.0;
        _errorMessage = null;
      });
    }
    _animateToColor(_getCoinColor(coin));
    // Load address first, then balance
    await _loadAddressForCoin(coin);
    await _loadBalanceForCoin(coin, forceRefresh: true);
  }

  void _onToCoinSelected(String coin) async {
    if (coin == _toCoin) return;
    if (coin == _fromCoin) {
      // Swap coins
      setState(() {
        final temp = _toCoin;
        _toCoin = coin;
        _fromCoin = temp;
        _showQuote = false;
        _quoteData = null;
        _amountController.clear();
        _amount = 0.0;
        _selectedPercentage = '';
        _errorMessage = null;
      });
      _animateToColor(_getCoinColor(_fromCoin));
      await _loadAddressForCoin(_fromCoin);
      await _loadBalanceForCoin(_fromCoin, forceRefresh: true);
    } else {
      setState(() {
        _toCoin = coin;
        _showQuote = false;
        _quoteData = null;
        _errorMessage = null;
      });
    }
    await _loadAddressForCoin(coin);
  }

  void _swapCoins() async {
    HapticFeedback.mediumImpact();
    setState(() {
      final temp = _fromCoin;
      _fromCoin = _toCoin;
      _toCoin = temp;
      _showQuote = false;
      _quoteData = null;
      _selectedPercentage = '';
      _amountController.clear();
      _amount = 0.0;
      _errorMessage = null;
    });
    _animateToColor(_getCoinColor(_fromCoin));
    await _loadAddressForCoin(_fromCoin);
    await _loadBalanceForCoin(_fromCoin, forceRefresh: true);
  }

  double _getExchangeRate() {
    final fromPrice = _fallbackPrices[_fromCoin] ?? 1.0;
    final toPrice = _fallbackPrices[_toCoin] ?? 1.0;
    return fromPrice / toPrice;
  }

  double _calculateEstimatedReceive() {
    if (_amount <= 0) return 0.0;
    final rate = _getExchangeRate();
    final fee = _amount * 0.01; // 1% platform fee (matches backend)
    return (_amount - fee) * rate;
  }

  /// Smart crypto amount formatting — full 8-decimal precision for small amounts
  String _formatCrypto(double amount) {
    if (amount <= 0) return '0';
    if (amount >= 10000) return amount.toStringAsFixed(2);
    if (amount >= 1) return amount.toStringAsFixed(4);
    return amount.toStringAsFixed(8); // Always full precision for sub-1 amounts
  }

  /// Smart exchange rate formatting — always shows significant digits
  String _formatRate(double rate) {
    if (rate >= 10000) return rate.toStringAsFixed(2);
    if (rate >= 100) return rate.toStringAsFixed(2);
    if (rate >= 1) return rate.toStringAsFixed(4);
    if (rate >= 0.0001) return rate.toStringAsFixed(6);
    return rate.toStringAsFixed(8); // e.g. DOGE→BTC: 0.00000416
  }

  void _setPercentage(double percent) {
    final balance = _balances[_fromCoin] ?? 0.0;
    final fee = balance * 0.003;
    final available = (balance - fee).clamp(0.0, double.infinity);
    final amount = available * percent;
    
    _amountController.text = amount.toStringAsFixed(8);
    setState(() {
      _amount = amount;
      _selectedPercentage = '${(percent * 100).toInt()}%';
    });
  }

  Future<void> _getQuote() async {
    if (_amount <= 0) {
      setState(() => _errorMessage = 'Please enter an amount');
      return;
    }

    final balance = _balances[_fromCoin] ?? 0.0;
    if (_amount > balance) {
      setState(() => _errorMessage = 'Insufficient $_fromCoin balance');
      return;
    }

    // Check source wallet
    if (!_addresses.containsKey(_fromCoin)) {
      await _loadAddressForCoin(_fromCoin);
    }
    if (_addresses[_fromCoin] == null) {
      setState(() => _errorMessage = 'No $_fromCoin wallet found');
      return;
    }

    // Check destination wallet
    if (!_addresses.containsKey(_toCoin)) {
      await _loadAddressForCoin(_toCoin);
    }
    if (_addresses[_toCoin] == null) {
      // Prompt to create wallet
      final created = await _promptCreateWallet(_toCoin);
      if (!created) {
        setState(() => _errorMessage = 'You need a $_toCoin wallet to receive');
        return;
      }
      await _loadAddressForCoin(_toCoin);
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Try to get real quote from backend
      final response = await _swapService.getSwapQuotes(
        fromCoin: _fromCoin,
        toCoin: _toCoin,
        amount: _amount,
        userAddress: _addresses[_fromCoin],
      ).timeout(const Duration(seconds: 5));

      if (response.success && response.quotes.isNotEmpty) {
        final best = response.bestQuote ?? response.quotes.first;
        setState(() {
          _quoteData = {
            'fromCoin': _fromCoin,
            'toCoin': _toCoin,
            'fromAmount': _amount,
            'toAmount': best.toAmount,
            'exchangeRate': best.exchangeRate,
            'fee': best.totalFees,
            'provider': best.provider,
          };
          _showQuote = true;
        });
      } else {
        _setLocalQuote();
      }
    } catch (e) {
      // Use local calculation
      _setLocalQuote();
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _setLocalQuote() {
    final estimated = _calculateEstimatedReceive();
    setState(() {
      _quoteData = {
        'fromCoin': _fromCoin,
        'toCoin': _toCoin,
        'fromAmount': _amount,
        'toAmount': estimated,
        'exchangeRate': _getExchangeRate(),
        'fee': _amount * 0.01, // 1% matches backend fee
        'provider': 'local',
      };
      _showQuote = true;
    });
  }

  Future<bool> _promptCreateWallet(String coin) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(_coins.firstWhere((c) => c.symbol == coin, orElse: () => _coins.first).icon,
                color: _getCoinColor(coin)),
            const SizedBox(width: 12),
            Text('Create $coin Wallet'),
          ],
        ),
        content: Text(
          'You need a $coin wallet to receive swapped coins. Would you like to create one now?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                final result = await _walletService.generateAddressFor(coin);
                if (result.containsKey('address')) {
                  _addresses[coin] = result['address']!;
                  Navigator.pop(context, true);
                } else {
                  Navigator.pop(context, false);
                }
              } catch (e) {
                Navigator.pop(context, false);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _getCoinColor(coin),
            ),
            child: const Text('Create'),
          ),
        ],
      ),
    ) ?? false;
  }

  void _onContinuePressed() {
    if (!_showQuote || _quoteData == null) return;
    
    setState(() {
      _showPinEntry = true;
      _enteredPin = '';
      _showSlideToSwap = false;
    });
  }

  void _onPinDigitPressed(String digit) {
    if (_enteredPin.length < 6) {
      setState(() => _enteredPin += digit);
      
      if (_enteredPin.length == 6) {
        _verifyPin();
      }
    }
  }

  void _onPinBackspace() {
    if (_enteredPin.isNotEmpty) {
      setState(() => _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1));
    }
  }

  Future<void> _verifyPin() async {
    final isValid = await _authService.verifyPIN(_enteredPin);
    
    if (isValid) {
      HapticFeedback.mediumImpact();
      setState(() {
        _showSlideToSwap = true;
      });
    } else {
      HapticFeedback.heavyImpact();
      setState(() => _enteredPin = '');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid PIN'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _onSlideUpdate(double position) {
    setState(() => _slidePosition = position.clamp(0.0, 1.0));
  }

  void _onSlideComplete() {
    if (_slidePosition >= 0.85) {
      HapticFeedback.heavyImpact();
      _executeSwap();
    } else {
      setState(() => _slidePosition = 0.0);
    }
  }

  Future<void> _executeSwap() async {
    setState(() => _isLoading = true);

    try {
      final fromAmount = _quoteData!['fromAmount'] as double;
      final toAmount = _quoteData!['toAmount'] as double;
      final fee = _quoteData!['fee'] as double;

      // Get private key for signing
      final privateKey = await _walletService.getPrivateKey(
        _fromCoin,
        _addresses[_fromCoin]!,
      );

      if (privateKey == null) {
        throw Exception('Cannot access wallet');
      }

      // Execute real swap
      final result = await _swapService.executeRealSwap(
        fromCoin: _fromCoin,
        toCoin: _toCoin,
        fromAmount: fromAmount,
        userAddress: _addresses[_fromCoin]!,
        privateKey: privateKey,
        destinationAddress: _addresses[_toCoin]!,
        provider: 'auto',
        slippage: 1.0,
      );

      if (result.success) {
        // Update balances
        setState(() {
          _balances[_fromCoin] = ((_balances[_fromCoin] ?? 0) - fromAmount - fee)
              .clamp(0.0, double.infinity);
          _balances[_toCoin] = (_balances[_toCoin] ?? 0) + (result.toAmount ?? toAmount);
        });

        // Save to history
        await _walletService.updateCachedBalance(_fromCoin, _balances[_fromCoin]!);
        await _walletService.updateCachedBalance(_toCoin, _balances[_toCoin]!);

        // Show success
        _confettiController.play();
        
        await _showSuccessDialog(
          fromAmount: fromAmount,
          toAmount: result.toAmount ?? toAmount,
          txHash: result.txHash,
        );

        // Reset form
        setState(() {
          _amountController.clear();
          _amount = 0.0;
          _showQuote = false;
          _quoteData = null;
          _showPinEntry = false;
          _showSlideToSwap = false;
          _slidePosition = 0.0;
          _selectedPercentage = '';
        });

        context.go('/dashboard');
      } else {
        throw Exception(result.error ?? 'Swap failed');
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _slidePosition = 0.0;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _showSuccessDialog({
    required double fromAmount,
    required double toAmount,
    String? txHash,
  }) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle, color: Colors.green, size: 50),
              ),
              const SizedBox(height: 20),
              const Text(
                'Swap Successful!',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                '${_formatCrypto(fromAmount)} $_fromCoin',
                style: TextStyle(
                  fontSize: 18,
                  color: _getCoinColor(_fromCoin),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Icon(Icons.arrow_downward, color: Colors.grey),
              Text(
                '${_formatCrypto(toAmount)} $_toCoin',
                style: TextStyle(
                  fontSize: 18,
                  color: _getCoinColor(_toCoin),
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (txHash != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'TX: ${txHash.length > 20 ? '${txHash.substring(0, 10)}...${txHash.substring(txHash.length - 6)}' : txHash}',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _currentHeaderColor,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Done', style: TextStyle(color: Colors.white)),
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
    return Stack(
      children: [
        AnimatedBuilder(
          animation: _colorAnimationController,
          builder: (context, child) {
            final color = _headerColorAnimation.value ?? _currentHeaderColor;
            return Scaffold(
              backgroundColor: Colors.grey[100],
              body: _showPinEntry
                  ? _buildPinEntryPage(color)
                  : _buildMainPage(color),
            );
          },
        ),
        // Confetti
        Align(
          alignment: Alignment.topCenter,
          child: ConfettiWidget(
            confettiController: _confettiController,
            blastDirection: pi / 2,
            maxBlastForce: 5,
            minBlastForce: 2,
            emissionFrequency: 0.05,
            numberOfParticles: 50,
            gravity: 0.1,
            colors: [_currentHeaderColor, Colors.green, Colors.blue, Colors.yellow],
          ),
        ),
      ],
    );
  }

  Widget _buildMainPage(Color headerColor) {
    final balance = _balances[_fromCoin] ?? 0.0;
    final fromPrice = _fallbackPrices[_fromCoin] ?? 0.0;
    
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // Simplified header
          SliverAppBar(
            expandedHeight: 80,
            floating: true,
            pinned: true,
            backgroundColor: headerColor,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
              onPressed: () => context.go('/dashboard'),
            ),
            title: const Text(
              'Swap',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 20),
            ),
            actions: [
              // Balance badge in header
              Container(
                margin: const EdgeInsets.only(right: 16),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${_formatCrypto(balance)} $_fromCoin',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    if (fromPrice > 0) ...[
                      Text(
                        ' (\$${(balance * fromPrice).toStringAsFixed(2)})',
                        style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 11),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Main swap card - unique glass-like design
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: headerColor.withOpacity(0.1),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // From section
                        _buildFromSection(headerColor),
                        
                        const SizedBox(height: 12),
                        
                        // Animated swap button
                        _buildSwapButton(headerColor),
                        
                        const SizedBox(height: 12),
                        
                        // To section
                        _buildToSection(headerColor),
                      ],
                    ),
                  ),

                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.red.withOpacity(0.2)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),

                  // Quote Section with unique design
                  if (_showQuote && _quoteData != null) _buildQuoteCard(headerColor),

                  const SizedBox(height: 20),

                  // Action Button
                  _buildActionButton(headerColor),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFromSection(Color color) {
    final balance = _balances[_fromCoin] ?? 0.0;
    final price = _fallbackPrices[_fromCoin] ?? 0.0;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('From', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey[600])),
            Text(
              'Available: ${_formatCrypto(balance)}',
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 12),
        
        // Coin chips - horizontal scroll
        SizedBox(
          height: 48,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: _coins.length,
            itemBuilder: (context, index) {
              final coin = _coins[index];
              final isSelected = coin.symbol == _fromCoin;
              return GestureDetector(
                onTap: () => _onFromCoinSelected(coin.symbol),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? coin.color : Colors.grey[100],
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: isSelected ? coin.color : Colors.grey[200]!,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(coin.icon, size: 18, color: isSelected ? Colors.white : coin.color),
                      const SizedBox(width: 6),
                      Text(
                        coin.symbol,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.grey[700],
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        
        const SizedBox(height: 16),
        
        // Amount input with percentage buttons
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Column(
            children: [
              // Percentage buttons row
              Row(
                children: [
                  _buildPercentChip('25%', 0.25, color),
                  const SizedBox(width: 6),
                  _buildPercentChip('50%', 0.50, color),
                  const SizedBox(width: 6),
                  _buildPercentChip('75%', 0.75, color),
                  const SizedBox(width: 6),
                  _buildPercentChip('MAX', 1.0, color),
                ],
              ),
              const SizedBox(height: 12),
              
              // Amount input
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: '0.00',
                  hintStyle: TextStyle(color: Colors.grey[400], fontSize: 26),
                  suffixText: _fromCoin,
                  suffixStyle: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              
              if (_amount > 0 && price > 0)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '≈ \$${(_amount * price).toStringAsFixed(2)} USD',
                    style: TextStyle(color: Colors.grey[500], fontSize: 13),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSwapButton(Color color) {
    return GestureDetector(
      onTap: _swapCoins,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color, color.withOpacity(0.8)],
          ),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(Icons.swap_vert_rounded, color: Colors.white, size: 24),
      ),
    );
  }

  Widget _buildToSection(Color color) {
    final toBalance = _balances[_toCoin] ?? 0.0;
    final estimated = _calculateEstimatedReceive();
    final toPrice = _fallbackPrices[_toCoin] ?? 0.0;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('To', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey[600])),
            Text(
              'Balance: ${_formatCrypto(toBalance)}',
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 12),
        
        // Coin chips - horizontal scroll
        SizedBox(
          height: 48,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: _coins.length,
            itemBuilder: (context, index) {
              final coin = _coins[index];
              final isSelected = coin.symbol == _toCoin;
              return GestureDetector(
                onTap: () => _onToCoinSelected(coin.symbol),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? coin.color : Colors.grey[100],
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: isSelected ? coin.color : Colors.grey[200]!,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(coin.icon, size: 18, color: isSelected ? Colors.white : coin.color),
                      const SizedBox(width: 6),
                      Text(
                        coin.symbol,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.grey[700],
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        
        const SizedBox(height: 16),
        
        // Estimated receive display
        Builder(builder: (context) {
          // Use real quoted amount when available, else estimated
          final displayAmount = (_showQuote && _quoteData != null)
              ? (_quoteData!['toAmount'] as double)
              : estimated;
          final isQuoted = _showQuote && _quoteData != null;
          return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _getCoinColor(_toCoin).withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _getCoinColor(_toCoin).withOpacity(0.2)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('You\'ll receive', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(
                    '${isQuoted ? '' : '≈ '}${_formatCrypto(displayAmount)}',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: _getCoinColor(_toCoin),
                    ),
                  ),
                  if (toPrice > 0 && displayAmount > 0)
                    Text(
                      '≈ \$${(displayAmount * toPrice).toStringAsFixed(2)} USD',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _getCoinColor(_toCoin).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _coins.firstWhere((c) => c.symbol == _toCoin, orElse: () => _coins.first).icon,
                  color: _getCoinColor(_toCoin),
                  size: 24,
                ),
              ),
            ],
          ),
        );
        }), // end Builder
      ],
    );
  }

  Widget _buildPercentChip(String label, double percent, Color color) {
    final isSelected = _selectedPercentage == label;
    final balance = _balances[_fromCoin] ?? 0.0;
    final isDisabled = balance <= 0;
    
    return Expanded(
      child: GestureDetector(
        onTap: isDisabled ? null : () => _setPercentage(percent),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isDisabled
                ? Colors.grey[200]
                : (isSelected ? color : Colors.white),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDisabled ? Colors.grey[300]! : (isSelected ? color : Colors.grey[300]!),
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isDisabled ? Colors.grey[400] : (isSelected ? Colors.white : color),
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuoteCard(Color color) {
    final toAmount = _quoteData!['toAmount'] as double;
    final rate = _quoteData!['exchangeRate'] as double;
    final fee = _quoteData!['fee'] as double;
    final toPrice = _fallbackPrices[_toCoin] ?? 0.0;
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, color.withOpacity(0.03)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.2), width: 1.5),
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.08), blurRadius: 15, offset: const Offset(0, 6)),
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
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.check_circle_outline, color: Colors.green, size: 18),
                  ),
                  const SizedBox(width: 10),
                  const Text('Quote Ready', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('Best Rate', style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          
          // Main conversion display
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('You pay', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                      Text(
                        '${_formatCrypto(_amount)} $_fromCoin',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _getCoinColor(_fromCoin)),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.arrow_forward, color: color, size: 18),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('You receive', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                      Text(
                        '${_formatCrypto(toAmount)} $_toCoin',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _getCoinColor(_toCoin)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          if (toPrice > 0) ...[
            const SizedBox(height: 8),
            Center(
              child: Text(
                '≈ \$${(toAmount * toPrice).toStringAsFixed(2)} USD',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
            ),
          ],
          
          const SizedBox(height: 16),
          
          // Rate and fee info
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Rate', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
              Text('1 $_fromCoin = ${_formatRate(rate)} $_toCoin', style: const TextStyle(fontSize: 13)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Platform Fee (${(_quoteData!["provider"] == "local" ? 1.0 : (_amount > 0 ? (fee / _amount * 100) : 1.0)).toStringAsFixed(1)}%)',
                style: TextStyle(color: Colors.grey[500], fontSize: 13),
              ),
              Text('${_formatCrypto(fee)} $_fromCoin', style: const TextStyle(fontSize: 13)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(Color color) {
    if (_isLoading) {
      return Container(
        height: 56,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color, color.withOpacity(0.85)],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
          ),
        ),
      );
    }

    if (!_showQuote) {
      // Get Quote button
      return GestureDetector(
        onTap: _amount > 0 ? _getQuote : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 56,
          decoration: BoxDecoration(
            gradient: _amount > 0
                ? LinearGradient(colors: [color, color.withOpacity(0.85)])
                : null,
            color: _amount > 0 ? null : Colors.grey[300],
            borderRadius: BorderRadius.circular(16),
            boxShadow: _amount > 0
                ? [BoxShadow(color: color.withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 5))]
                : null,
          ),
          child: Center(
            child: Text(
              'Get Quote',
              style: TextStyle(
                color: _amount > 0 ? Colors.white : Colors.grey[500],
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }

    // Continue to confirm button
    return GestureDetector(
      onTap: _onContinuePressed,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [color, color.withOpacity(0.85)]),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: color.withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 5))],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Text(
              'Continue',
              style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
            ),
            SizedBox(width: 8),
            Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildPinEntryPage(Color headerColor) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [headerColor, headerColor.withOpacity(0.9), Colors.white, Colors.white],
          stops: const [0.0, 0.25, 0.25, 1.0],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () {
                      setState(() {
                        _showPinEntry = false;
                        _enteredPin = '';
                        _showSlideToSwap = false;
                      });
                    },
                  ),
                  const Expanded(
                    child: Text(
                      'Confirm Swap',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),

            // Swap Summary
            Container(
              margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 30, offset: const Offset(0, 15))],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _getCoinColor(_fromCoin).withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(_coins.firstWhere((c) => c.symbol == _fromCoin).icon,
                            color: _getCoinColor(_fromCoin), size: 28),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Icon(Icons.arrow_forward, color: Colors.grey),
                      ),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _getCoinColor(_toCoin).withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(_coins.firstWhere((c) => c.symbol == _toCoin).icon,
                            color: _getCoinColor(_toCoin), size: 28),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${_quoteData!['fromAmount']} $_fromCoin',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _getCoinColor(_fromCoin)),
                  ),
                  const Icon(Icons.arrow_downward, color: Colors.grey),
                  Text(
                    '${(_quoteData!['toAmount'] as double).toStringAsFixed(6)} $_toCoin',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _getCoinColor(_toCoin)),
                  ),
                ],
              ),
            ),

            // PIN Entry or Slide to Swap
            Expanded(
              child: _showSlideToSwap
                  ? _buildConfirmSlideToSwap(headerColor)
                  : _buildPinEntry(headerColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPinEntry(Color headerColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 24),
          Text('Enter your PIN', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey[800])),
          const SizedBox(height: 8),
          Text('Enter your 6-digit PIN to confirm', style: TextStyle(color: Colors.grey[500])),
          const SizedBox(height: 32),

          // PIN Dots
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(6, (index) {
              final isFilled = index < _enteredPin.length;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 8),
                width: isFilled ? 16 : 14,
                height: isFilled ? 16 : 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isFilled ? headerColor : Colors.transparent,
                  border: Border.all(color: isFilled ? headerColor : Colors.grey[300]!, width: 2),
                ),
              );
            }),
          ),
          const SizedBox(height: 40),

          // Number Pad
          Expanded(
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 24),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 1.5,
                crossAxisSpacing: 16,
                mainAxisSpacing: 12,
              ),
              itemCount: 12,
              itemBuilder: (context, index) {
                if (index == 9) return const SizedBox();
                if (index == 10) return _buildNumberButton('0');
                if (index == 11) return _buildBackspaceButton();
                return _buildNumberButton('${index + 1}');
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNumberButton(String digit) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        _onPinDigitPressed(digit);
      },
      child: Container(
        decoration: BoxDecoration(color: Colors.grey[100], shape: BoxShape.circle),
        child: Center(
          child: Text(digit, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: Colors.grey[800])),
        ),
      ),
    );
  }

  Widget _buildBackspaceButton() {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        _onPinBackspace();
      },
      child: Container(
        decoration: BoxDecoration(color: Colors.grey[100], shape: BoxShape.circle),
        child: Center(child: Icon(Icons.backspace_outlined, color: Colors.grey[700], size: 26)),
      ),
    );
  }

  Widget _buildConfirmSlideToSwap(Color headerColor) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 500),
          builder: (context, value, child) {
            return Transform.scale(
              scale: value,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), shape: BoxShape.circle),
                child: const Icon(Icons.check_circle, color: Colors.green, size: 50),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        const Text('PIN Verified!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.green)),
        const SizedBox(height: 8),
        Text('Slide to confirm swap', style: TextStyle(color: Colors.grey[600])),
        const SizedBox(height: 40),

        if (_isLoading)
          Column(
            children: [
              CircularProgressIndicator(color: headerColor),
              const SizedBox(height: 16),
              Text('Processing...', style: TextStyle(color: Colors.grey[600])),
            ],
          )
        else
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            height: 70,
            decoration: BoxDecoration(
              color: headerColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(35),
              border: Border.all(color: headerColor.withOpacity(0.3), width: 2),
            ),
            child: Stack(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  width: (MediaQuery.of(context).size.width - 64) * _slidePosition,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [headerColor.withOpacity(0.3), headerColor.withOpacity(0.6)]),
                    borderRadius: BorderRadius.circular(33),
                  ),
                ),
                Center(
                  child: AnimatedOpacity(
                    opacity: _slidePosition < 0.3 ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Text(
                      'Slide to Confirm',
                      style: TextStyle(color: headerColor, fontWeight: FontWeight.w600, fontSize: 16),
                    ),
                  ),
                ),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final maxSlide = constraints.maxWidth - 70;
                    return Positioned(
                      left: _slidePosition * maxSlide,
                      top: 0,
                      bottom: 0,
                      child: GestureDetector(
                        onHorizontalDragStart: (_) => setState(() => _isSliding = true),
                        onHorizontalDragUpdate: (details) {
                          final newPos = (_slidePosition * maxSlide + details.delta.dx) / maxSlide;
                          _onSlideUpdate(newPos);
                        },
                        onHorizontalDragEnd: (_) {
                          setState(() => _isSliding = false);
                          _onSlideComplete();
                        },
                        child: Container(
                          width: 70,
                          height: 70,
                          decoration: BoxDecoration(
                            color: headerColor,
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: headerColor.withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 5))],
                          ),
                          child: Icon(
                            _slidePosition >= 0.85 ? Icons.check : Icons.swap_horiz,
                            color: Colors.white,
                            size: 32,
                          ),
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
