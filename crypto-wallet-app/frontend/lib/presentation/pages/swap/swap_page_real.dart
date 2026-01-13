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

/// Token with network info for cross-chain swaps
class TokenInfo {
  final String symbol;
  final String name;
  final String network;
  final String networkName;
  final Color color;
  final IconData icon;
  final String? contractAddress;
  
  const TokenInfo({
    required this.symbol,
    required this.name,
    required this.network,
    required this.networkName,
    required this.color,
    required this.icon,
    this.contractAddress,
  });
  
  String get displayName => '$symbol ($networkName)';
  String get id => '${symbol}_$network';
}

/// Swap quote from a provider
class SwapQuoteInfo {
  final String provider;
  final String providerName;
  final double rate;
  final double toAmount;
  final double fee;
  final double feePercent;
  final String estimatedTime;
  final bool isBest;
  final Color providerColor;
  
  const SwapQuoteInfo({
    required this.provider,
    required this.providerName,
    required this.rate,
    required this.toAmount,
    required this.fee,
    required this.feePercent,
    required this.estimatedTime,
    this.isBest = false,
    required this.providerColor,
  });
}

/// Real Swap Page with multiple sources and cross-chain support
class SwapPageReal extends ConsumerStatefulWidget {
  const SwapPageReal({super.key});

  @override
  ConsumerState<SwapPageReal> createState() => _SwapPageRealState();
}

class _SwapPageRealState extends ConsumerState<SwapPageReal>
    with TickerProviderStateMixin {
  // Services - lazy init
  SwapService? _swapService;
  BlockchainService? _blockchainService;
  WalletService? _walletService;
  BiometricAuthService? _authService;

  // Controllers
  final TextEditingController _amountController = TextEditingController();
  late ConfettiController _confettiController;
  late AnimationController _pulseController;

  // Available tokens with networks
  static final List<TokenInfo> _tokens = [
    // Ethereum
    const TokenInfo(symbol: 'ETH', name: 'Ethereum', network: 'ethereum', networkName: 'Ethereum', color: Color(0xFF627EEA), icon: Icons.diamond),
    const TokenInfo(symbol: 'USDT', name: 'Tether', network: 'ethereum', networkName: 'ERC20', color: Color(0xFF26A17B), icon: Icons.attach_money, contractAddress: '0xdAC17F958D2ee523a2206206994597C13D831ec7'),
    const TokenInfo(symbol: 'USDC', name: 'USD Coin', network: 'ethereum', networkName: 'ERC20', color: Color(0xFF2775CA), icon: Icons.monetization_on, contractAddress: '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48'),
    
    // BNB Smart Chain
    const TokenInfo(symbol: 'BNB', name: 'BNB', network: 'bsc', networkName: 'BSC', color: Color(0xFFF0B90B), icon: Icons.hexagon),
    const TokenInfo(symbol: 'USDT', name: 'Tether', network: 'bsc', networkName: 'BEP20', color: Color(0xFF26A17B), icon: Icons.attach_money, contractAddress: '0x55d398326f99059fF775485246999027B3197955'),
    const TokenInfo(symbol: 'USDC', name: 'USD Coin', network: 'bsc', networkName: 'BEP20', color: Color(0xFF2775CA), icon: Icons.monetization_on, contractAddress: '0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d'),
    
    // Tron
    const TokenInfo(symbol: 'TRX', name: 'Tron', network: 'tron', networkName: 'Tron', color: Color(0xFFFF0013), icon: Icons.flash_on),
    const TokenInfo(symbol: 'USDT', name: 'Tether', network: 'tron', networkName: 'TRC20', color: Color(0xFF26A17B), icon: Icons.attach_money, contractAddress: 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t'),
    
    // Bitcoin
    const TokenInfo(symbol: 'BTC', name: 'Bitcoin', network: 'bitcoin', networkName: 'Bitcoin', color: Color(0xFFF7931A), icon: Icons.currency_bitcoin),
    
    // Solana
    const TokenInfo(symbol: 'SOL', name: 'Solana', network: 'solana', networkName: 'Solana', color: Color(0xFF9945FF), icon: Icons.bolt),
    const TokenInfo(symbol: 'USDT', name: 'Tether', network: 'solana', networkName: 'SPL', color: Color(0xFF26A17B), icon: Icons.attach_money),
    const TokenInfo(symbol: 'USDC', name: 'USD Coin', network: 'solana', networkName: 'SPL', color: Color(0xFF2775CA), icon: Icons.monetization_on),
    
    // Polygon
    const TokenInfo(symbol: 'MATIC', name: 'Polygon', network: 'polygon', networkName: 'Polygon', color: Color(0xFF8247E5), icon: Icons.auto_awesome),
    const TokenInfo(symbol: 'USDT', name: 'Tether', network: 'polygon', networkName: 'Polygon', color: Color(0xFF26A17B), icon: Icons.attach_money),
    
    // XRP
    const TokenInfo(symbol: 'XRP', name: 'Ripple', network: 'ripple', networkName: 'XRP Ledger', color: Color(0xFF23292F), icon: Icons.water_drop),
  ];

  // DEX/Bridge Providers
  static const List<Map<String, dynamic>> _providers = [
    {'id': '1inch', 'name': '1inch', 'color': Color(0xFF1B314F), 'fee': 0.3},
    {'id': 'uniswap', 'name': 'Uniswap', 'color': Color(0xFFFF007A), 'fee': 0.3},
    {'id': 'pancakeswap', 'name': 'PancakeSwap', 'color': Color(0xFFD1884F), 'fee': 0.25},
    {'id': 'sushiswap', 'name': 'SushiSwap', 'color': Color(0xFFFA52A0), 'fee': 0.3},
    {'id': 'changelly', 'name': 'Changelly', 'color': Color(0xFF00CC66), 'fee': 0.5},
    {'id': 'simpleswap', 'name': 'SimpleSwap', 'color': Color(0xFF5856D6), 'fee': 0.5},
  ];

  // Prices (fallback)
  static const Map<String, double> _prices = {
    'BTC': 97500.0, 'ETH': 3650.0, 'BNB': 715.0, 'SOL': 210.0,
    'XRP': 2.35, 'TRX': 0.26, 'MATIC': 0.52, 'USDT': 1.0, 'USDC': 1.0,
  };

  // State
  TokenInfo _fromToken = _tokens[0]; // ETH
  TokenInfo _toToken = _tokens[3]; // BNB
  double _amount = 0.0;
  String _selectedPercent = '';
  
  // Balances & addresses
  final Map<String, double> _balances = {};
  final Map<String, String> _addresses = {};
  
  // Quote state
  bool _isLoadingQuotes = false;
  List<SwapQuoteInfo> _quotes = [];
  SwapQuoteInfo? _selectedQuote;
  String? _error;
  
  // Swap flow state
  bool _showConfirmation = false;
  bool _isExecuting = false;
  String _enteredPin = '';
  bool _pinVerified = false;
  double _slidePosition = 0.0;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: const Duration(seconds: 3));
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    
    _amountController.addListener(_onAmountChanged);
    
    // Load balance in background after frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initServices();
    });
  }

  Future<void> _initServices() async {
    _swapService ??= SwapService();
    _blockchainService ??= BlockchainService();
    _walletService ??= WalletService();
    _authService ??= BiometricAuthService();
    
    // Load from token balance
    await _loadBalance(_fromToken);
  }

  Future<void> _loadBalance(TokenInfo token) async {
    try {
      _walletService ??= WalletService();
      _blockchainService ??= BlockchainService();
      
      final coin = token.symbol == 'USDT' || token.symbol == 'USDC' 
          ? token.symbol 
          : token.symbol;
      
      // Get address
      if (!_addresses.containsKey(token.id)) {
        final addrs = await _walletService!.getStoredAddresses(coin);
        if (addrs.isNotEmpty) {
          _addresses[token.id] = addrs.first;
        }
      }
      
      // Get balance
      final addr = _addresses[token.id];
      if (addr != null && addr.isNotEmpty) {
        final bal = await _blockchainService!.getBalance(coin, addr)
            .timeout(const Duration(seconds: 3), onTimeout: () => 0.0);
        if (mounted) {
          setState(() => _balances[token.id] = bal);
        }
      }
    } catch (e) {
      debugPrint('Error loading balance: $e');
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _confettiController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _onAmountChanged() {
    final val = double.tryParse(_amountController.text) ?? 0.0;
    if (val != _amount) {
      setState(() {
        _amount = val;
        _quotes = [];
        _selectedQuote = null;
        _error = null;
      });
    }
  }

  double _getPrice(String symbol) => _prices[symbol] ?? 1.0;

  double _getUsdValue(TokenInfo token, double amount) {
    return amount * _getPrice(token.symbol);
  }

  double _getRate(TokenInfo from, TokenInfo to) {
    return _getPrice(from.symbol) / _getPrice(to.symbol);
  }

  void _setPercentage(String label, double pct) {
    final bal = _balances[_fromToken.id] ?? 0.0;
    final fee = bal * 0.003; // Reserve for gas
    final avail = (bal - fee).clamp(0.0, double.infinity);
    final amt = avail * pct;
    
    _amountController.text = amt > 0 ? amt.toStringAsFixed(8) : '';
    setState(() {
      _amount = amt;
      _selectedPercent = label;
    });
  }

  void _selectFromToken(TokenInfo token) {
    if (token.id == _fromToken.id) return;
    HapticFeedback.selectionClick();
    
    setState(() {
      if (token.id == _toToken.id) {
        _toToken = _fromToken;
      }
      _fromToken = token;
      _quotes = [];
      _selectedQuote = null;
      _amountController.clear();
      _amount = 0.0;
      _selectedPercent = '';
    });
    _loadBalance(token);
  }

  void _selectToToken(TokenInfo token) {
    if (token.id == _toToken.id) return;
    HapticFeedback.selectionClick();
    
    setState(() {
      if (token.id == _fromToken.id) {
        _fromToken = _toToken;
        _loadBalance(_fromToken);
      }
      _toToken = token;
      _quotes = [];
      _selectedQuote = null;
    });
  }

  void _swapTokens() {
    HapticFeedback.mediumImpact();
    setState(() {
      final temp = _fromToken;
      _fromToken = _toToken;
      _toToken = temp;
      _quotes = [];
      _selectedQuote = null;
      _amountController.clear();
      _amount = 0.0;
      _selectedPercent = '';
    });
    _loadBalance(_fromToken);
  }

  Future<void> _getQuotes() async {
    if (_amount <= 0) {
      setState(() => _error = 'Enter an amount');
      return;
    }

    final bal = _balances[_fromToken.id] ?? 0.0;
    if (_amount > bal) {
      setState(() => _error = 'Insufficient ${_fromToken.symbol} balance');
      return;
    }

    // Check minimum swap amount (in USD)
    final usdValue = _getUsdValue(_fromToken, _amount);
    final minSwapUsd = 5.0; // Minimum $5 for swaps
    
    if (usdValue < minSwapUsd) {
      setState(() => _error = 'Minimum swap amount is \$${minSwapUsd.toStringAsFixed(0)} USD (you have \$${usdValue.toStringAsFixed(2)})');
      return;
    }

    // Check destination wallet
    if (!_addresses.containsKey(_toToken.id)) {
      _walletService ??= WalletService();
      final addrs = await _walletService!.getStoredAddresses(_toToken.symbol);
      if (addrs.isNotEmpty) {
        _addresses[_toToken.id] = addrs.first;
      } else {
        final created = await _showCreateWalletDialog(_toToken);
        if (!created) {
          setState(() => _error = 'Need ${_toToken.displayName} wallet');
          return;
        }
      }
    }

    setState(() {
      _isLoadingQuotes = true;
      _error = null;
      _quotes = [];
    });

    try {
      // Generate quotes from multiple providers
      final baseRate = _getRate(_fromToken, _toToken);
      final quotes = <SwapQuoteInfo>[];
      
      // Determine which providers support this pair
      final isCrossChain = _fromToken.network != _toToken.network;
      final availableProviders = isCrossChain 
          ? _providers.where((p) => p['id'] == 'changelly' || p['id'] == 'simpleswap' || p['id'] == '1inch').toList()
          : _providers;

      for (final provider in availableProviders) {
        // Simulate slight rate variations between providers
        final variation = 0.97 + (provider['id'].hashCode % 6) * 0.01;
        final rate = baseRate * variation;
        final feePercent = (provider['fee'] as double) + (isCrossChain ? 0.2 : 0.0);
        final fee = _amount * (feePercent / 100);
        final toAmount = (_amount - fee) * rate;
        
        quotes.add(SwapQuoteInfo(
          provider: provider['id'] as String,
          providerName: provider['name'] as String,
          rate: rate,
          toAmount: toAmount,
          fee: fee,
          feePercent: feePercent,
          estimatedTime: isCrossChain ? '5-15 min' : '~30 sec',
          providerColor: provider['color'] as Color,
        ));
      }

      // Sort by best rate (highest toAmount)
      quotes.sort((a, b) => b.toAmount.compareTo(a.toAmount));
      
      // Mark best
      if (quotes.isNotEmpty) {
        final best = quotes.first;
        quotes[0] = SwapQuoteInfo(
          provider: best.provider,
          providerName: best.providerName,
          rate: best.rate,
          toAmount: best.toAmount,
          fee: best.fee,
          feePercent: best.feePercent,
          estimatedTime: best.estimatedTime,
          isBest: true,
          providerColor: best.providerColor,
        );
      }

      setState(() {
        _quotes = quotes;
        _selectedQuote = quotes.isNotEmpty ? quotes.first : null;
      });
    } catch (e) {
      setState(() => _error = 'Failed to get quotes: $e');
    } finally {
      if (mounted) setState(() => _isLoadingQuotes = false);
    }
  }

  Future<bool> _showCreateWalletDialog(TokenInfo token) async {
    return await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(token.icon, color: token.color),
            const SizedBox(width: 12),
            Text('Create ${token.displayName} Wallet'),
          ],
        ),
        content: Text('You need a ${token.displayName} wallet to receive swapped tokens.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                final res = await _walletService!.generateAddressFor(token.symbol);
                if (res.containsKey('address')) {
                  _addresses[token.id] = res['address']!;
                  Navigator.pop(ctx, true);
                } else {
                  Navigator.pop(ctx, false);
                }
              } catch (e) {
                Navigator.pop(ctx, false);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: token.color),
            child: const Text('Create', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ) ?? false;
  }

  void _selectQuote(SwapQuoteInfo quote) {
    HapticFeedback.selectionClick();
    setState(() => _selectedQuote = quote);
  }

  void _onContinue() {
    if (_selectedQuote == null) return;
    setState(() {
      _showConfirmation = true;
      _enteredPin = '';
      _pinVerified = false;
      _slidePosition = 0.0;
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
      setState(() => _pinVerified = true);
    } else {
      HapticFeedback.heavyImpact();
      setState(() => _enteredPin = '');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid PIN'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _executeSwap() async {
    if (_selectedQuote == null) return;
    
    setState(() => _isExecuting = true);

    try {
      _swapService ??= SwapService();
      _walletService ??= WalletService();

      final fromAddr = _addresses[_fromToken.id];
      final toAddr = _addresses[_toToken.id];
      
      if (fromAddr == null || toAddr == null) {
        throw Exception('Wallet addresses not found');
      }

      // Check minimum amount again
      final usdValue = _getUsdValue(_fromToken, _amount);
      if (usdValue < 10.0) {
        throw Exception('Minimum swap amount is \$10 USD');
      }

      // Get private key
      final pk = await _walletService!.getPrivateKey(_fromToken.symbol, fromAddr);
      if (pk == null) throw Exception('Cannot access wallet');

      // Execute REAL swap via selected provider
      final result = await _swapService!.executeRealSwap(
        fromCoin: _fromToken.symbol,
        toCoin: _toToken.symbol,
        fromAmount: _amount,
        userAddress: fromAddr,
        privateKey: pk,
        destinationAddress: toAddr,
        provider: _selectedQuote!.provider,
        slippage: 1.0,
      );

      if (result.success) {
        // Update balances
        final fee = _selectedQuote!.fee;
        _balances[_fromToken.id] = ((_balances[_fromToken.id] ?? 0) - _amount).clamp(0.0, double.infinity);
        _balances[_toToken.id] = (_balances[_toToken.id] ?? 0) + (result.toAmount ?? _selectedQuote!.toAmount);

        await _walletService!.updateCachedBalance(_fromToken.symbol, _balances[_fromToken.id]!);
        await _walletService!.updateCachedBalance(_toToken.symbol, _balances[_toToken.id]!);

        _confettiController.play();
        await _showSuccessDialog(result.txHash);
        
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
        
        // Parse error for user-friendly message
        String errorMsg = e.toString();
        if (errorMsg.contains('failed to send tx')) {
          errorMsg = 'Transaction failed. Your balance may be too low for gas fees, or the swap amount is below the DEX minimum.';
        } else if (errorMsg.contains('insufficient')) {
          errorMsg = 'Insufficient balance for swap + gas fees';
        } else if (errorMsg.contains('Exception:')) {
          errorMsg = errorMsg.replaceAll('Exception:', '').trim();
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _showSuccessDialog(String? txHash) async {
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
                '${_amount.toStringAsFixed(6)} ${_fromToken.displayName}',
                style: TextStyle(color: Colors.grey[600]),
              ),
              const Icon(Icons.arrow_downward, color: Colors.grey),
              Text(
                '${_selectedQuote!.toAmount.toStringAsFixed(6)} ${_toToken.displayName}',
                style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.bold),
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
    return Stack(
      children: [
        Scaffold(
          backgroundColor: Colors.grey[50],
          body: _showConfirmation ? _buildConfirmationPage() : _buildMainPage(),
        ),
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
            colors: [_fromToken.color, _toToken.color, Colors.green, Colors.yellow],
          ),
        ),
      ],
    );
  }

  Widget _buildMainPage() {
    final bal = _balances[_fromToken.id] ?? 0.0;
    final usdBal = _getUsdValue(_fromToken, bal);

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        // Header
        SliverAppBar(
          expandedHeight: 56,
          floating: false,
          pinned: true,
          backgroundColor: _fromToken.color,
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
                '${bal.toStringAsFixed(6)} ${_fromToken.symbol} (\$${usdBal.toStringAsFixed(2)})',
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
                  onTap: _swapTokens,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [_fromToken.color, _toToken.color]),
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: _fromToken.color.withOpacity(0.4), blurRadius: 12)],
                    ),
                    child: const Icon(Icons.swap_vert, color: Colors.white, size: 24),
                  ),
                ),

                // TO Section
                _buildToSection(),

                const SizedBox(height: 16),

                // Get Quotes button or Quotes list
                if (_quotes.isEmpty)
                  _buildGetQuotesButton()
                else
                  _buildQuotesList(),

                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red, size: 20),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_error!, style: const TextStyle(color: Colors.red))),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 100),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFromSection() {
    final bal = _balances[_fromToken.id] ?? 0.0;

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
              const Text('From', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500)),
              Text('Balance: ${bal.toStringAsFixed(8)}', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
            ],
          ),
          const SizedBox(height: 12),

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

          // Amount input + token selector
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
              _buildTokenSelector(_fromToken, true),
            ],
          ),

          // USD value
          if (_amount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '≈ \$${_getUsdValue(_fromToken, _amount).toStringAsFixed(2)} USD',
                style: TextStyle(color: Colors.grey[500], fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildToSection() {
    final est = _selectedQuote?.toAmount ?? (_amount > 0 ? _amount * _getRate(_fromToken, _toToken) * 0.997 : 0.0);
    final bal = _balances[_toToken.id] ?? 0.0;

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
              const Text('To', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500)),
              Text('Balance: ${bal.toStringAsFixed(6)}', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
            ],
          ),
          const SizedBox(height: 12),

          // Token chips for quick selection
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: _tokens
                  .where((t) => t.id != _fromToken.id)
                  .take(8)
                  .map((t) => _buildTokenChip(t))
                  .toList(),
            ),
          ),

          const SizedBox(height: 16),

          // Selected token & estimate
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      est > 0 ? est.toStringAsFixed(6) : '0.00',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: est > 0 ? Colors.black87 : Colors.grey[400],
                      ),
                    ),
                    if (est > 0)
                      Text(
                        '≈ \$${_getUsdValue(_toToken, est).toStringAsFixed(2)} USD',
                        style: TextStyle(color: Colors.grey[500], fontSize: 13),
                      ),
                  ],
                ),
              ),
              _buildTokenSelector(_toToken, false),
            ],
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
          color: sel ? _fromToken.color : Colors.grey[100],
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

  Widget _buildTokenSelector(TokenInfo token, bool isFrom) {
    return GestureDetector(
      onTap: () => _showTokenPicker(isFrom),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: token.color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: token.color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(token.icon, color: token.color, size: 20),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(token.symbol, style: TextStyle(fontWeight: FontWeight.bold, color: token.color, fontSize: 14)),
                Text(token.networkName, style: TextStyle(color: token.color.withOpacity(0.7), fontSize: 10)),
              ],
            ),
            const SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down, color: token.color, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildTokenChip(TokenInfo token) {
    final sel = token.id == _toToken.id;
    return GestureDetector(
      onTap: () => _selectToToken(token),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: sel ? token.color : Colors.grey[100],
          borderRadius: BorderRadius.circular(18),
          border: sel ? null : Border.all(color: Colors.grey[300]!),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(token.icon, size: 14, color: sel ? Colors.white : token.color),
            const SizedBox(width: 4),
            Text(
              '${token.symbol} ${token.networkName}',
              style: TextStyle(
                color: sel ? Colors.white : Colors.grey[700],
                fontWeight: sel ? FontWeight.bold : FontWeight.w500,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTokenPicker(bool isFrom) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) => Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                isFrom ? 'Select token to swap' : 'Select token to receive',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: _tokens.length,
                itemBuilder: (_, i) {
                  final t = _tokens[i];
                  final selected = isFrom ? t.id == _fromToken.id : t.id == _toToken.id;
                  return ListTile(
                    leading: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(color: t.color.withOpacity(0.1), shape: BoxShape.circle),
                      child: Icon(t.icon, color: t.color),
                    ),
                    title: Text(t.name),
                    subtitle: Text('${t.symbol} • ${t.networkName}'),
                    trailing: selected ? Icon(Icons.check_circle, color: t.color) : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      if (isFrom) {
                        _selectFromToken(t);
                      } else {
                        _selectToToken(t);
                      }
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGetQuotesButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isLoadingQuotes ? null : _getQuotes,
        style: ElevatedButton.styleFrom(
          backgroundColor: _fromToken.color,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: _isLoadingQuotes
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                  const SizedBox(width: 12),
                  const Text('Finding best rates...', style: TextStyle(color: Colors.white)),
                ],
              )
            : const Text('Get Quotes', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildQuotesList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Available Rates', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            TextButton.icon(
              onPressed: _getQuotes,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Refresh'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        
        // Quote cards
        ...(_quotes.map((q) => _buildQuoteCard(q))),

        const SizedBox(height: 16),

        // Continue button
        if (_selectedQuote != null)
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _onContinue,
              style: ElevatedButton.styleFrom(
                backgroundColor: _selectedQuote!.providerColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Swap via ${_selectedQuote!.providerName}',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward, color: Colors.white),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildQuoteCard(SwapQuoteInfo quote) {
    final selected = _selectedQuote?.provider == quote.provider;
    
    return GestureDetector(
      onTap: () => _selectQuote(quote),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? quote.providerColor.withOpacity(0.1) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? quote.providerColor : Colors.grey[200]!,
            width: selected ? 2 : 1,
          ),
          boxShadow: selected
              ? [BoxShadow(color: quote.providerColor.withOpacity(0.2), blurRadius: 10)]
              : null,
        ),
        child: Column(
          children: [
            Row(
              children: [
                // Provider logo/icon
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: quote.providerColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      quote.providerName.substring(0, 1),
                      style: TextStyle(
                        color: quote.providerColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                
                // Provider name & tags
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            quote.providerName,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: selected ? quote.providerColor : Colors.black87,
                            ),
                          ),
                          if (quote.isBest) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text('BEST', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        '${quote.estimatedTime} • ${quote.feePercent.toStringAsFixed(2)}% fee',
                        style: TextStyle(color: Colors.grey[500], fontSize: 12),
                      ),
                    ],
                  ),
                ),

                // Radio
                Container(
                  width: 24, height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: selected ? quote.providerColor : Colors.grey[300]!, width: 2),
                    color: selected ? quote.providerColor : Colors.transparent,
                  ),
                  child: selected
                      ? const Icon(Icons.check, color: Colors.white, size: 16)
                      : null,
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Rate details
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('You receive', style: TextStyle(color: Colors.grey, fontSize: 11)),
                      Text(
                        '${quote.toAmount.toStringAsFixed(6)} ${_toToken.symbol}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: selected ? quote.providerColor : Colors.black87,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('Rate', style: TextStyle(color: Colors.grey, fontSize: 11)),
                      Text(
                        '1 ${_fromToken.symbol} = ${quote.rate.toStringAsFixed(4)} ${_toToken.symbol}',
                        style: const TextStyle(fontSize: 12),
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

  Widget _buildConfirmationPage() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_selectedQuote!.providerColor, _selectedQuote!.providerColor.withOpacity(0.8), Colors.white, Colors.white],
          stops: const [0.0, 0.15, 0.15, 1.0],
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
                      _showConfirmation = false;
                      _pinVerified = false;
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

            // Swap summary card
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
                  // From → To
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildCoinBadge(_fromToken, _amount),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Icon(Icons.arrow_forward, color: _selectedQuote!.providerColor),
                      ),
                      _buildCoinBadge(_toToken, _selectedQuote!.toAmount),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // Provider badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _selectedQuote!.providerColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.swap_horiz, color: _selectedQuote!.providerColor, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          'via ${_selectedQuote!.providerName}',
                          style: TextStyle(color: _selectedQuote!.providerColor, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 8),
                  
                  // Details
                  _buildDetailRow('Rate', '1 ${_fromToken.symbol} = ${_selectedQuote!.rate.toStringAsFixed(4)} ${_toToken.symbol}'),
                  _buildDetailRow('Fee', '${_selectedQuote!.fee.toStringAsFixed(6)} ${_fromToken.symbol} (${_selectedQuote!.feePercent}%)'),
                  _buildDetailRow('Time', _selectedQuote!.estimatedTime),
                  
                  // Warning for low amounts
                  if (_getUsdValue(_fromToken, _amount) < 20)
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.orange[200]!),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: Colors.orange[700], size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Small swaps may fail due to high gas fees relative to amount',
                              style: TextStyle(color: Colors.orange[800], fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            // PIN or Slide
            Expanded(
              child: _pinVerified ? _buildSlideToSwap() : _buildPinEntry(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoinBadge(TokenInfo token, double amount) {
    return Column(
      children: [
        Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            color: token.color.withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(color: token.color.withOpacity(0.3)),
          ),
          child: Icon(token.icon, color: token.color, size: 28),
        ),
        const SizedBox(height: 8),
        Text(
          amount.toStringAsFixed(6),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        Text(
          token.displayName,
          style: TextStyle(color: Colors.grey[500], fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
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

  Widget _buildPinEntry() {
    return Column(
      children: [
        const SizedBox(height: 20),
        Text('Enter PIN', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey[800])),
        const SizedBox(height: 8),
        Text('Enter your 6-digit PIN to confirm', style: TextStyle(color: Colors.grey[500])),
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
                color: filled ? _selectedQuote!.providerColor : Colors.transparent,
                border: Border.all(color: filled ? _selectedQuote!.providerColor : Colors.grey[300]!, width: 2),
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
            physics: const NeverScrollableScrollPhysics(),
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
    final color = _selectedQuote!.providerColor;
    
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
              CircularProgressIndicator(color: color),
              const SizedBox(height: 16),
              Text('Executing swap via ${_selectedQuote!.providerName}...', style: TextStyle(color: Colors.grey[600])),
            ],
          )
        else
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            height: 64,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: color.withOpacity(0.3), width: 2),
            ),
            child: Stack(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  width: (MediaQuery.of(context).size.width - 64) * _slidePosition,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [color.withOpacity(0.3), color.withOpacity(0.6)]),
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
                        Text('Slide to Swap', style: TextStyle(color: color, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 8),
                        Icon(Icons.arrow_forward, color: color, size: 20),
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
                            color: color,
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 12)],
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
