import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:confetti/confetti.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../../../services/swap_service.dart';
import '../../../services/blockchain_service.dart';
import '../../../services/wallet_service.dart';
import '../../../services/biometric_auth_service.dart';
import '../../../services/transaction_service.dart';
import '../../../models/transaction_model.dart' as tx_model;

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
  final String? initialFromCoin;
  
  const SwapPageReal({super.key, this.initialFromCoin});

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
  String _statusMessage = '';
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
    
    // Set initial from coin if provided
    if (widget.initialFromCoin != null) {
      _setInitialFromCoin(widget.initialFromCoin!);
    }
    
    // Load balance in background after frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initServices();
    });
  }

  void _setInitialFromCoin(String coinSymbol) {
    // Map the coin symbol to a token
    // Handle USDT variants (USDT-TRC20, USDT-BEP20, USDT-ERC20)
    String symbol = coinSymbol.split('-').first.toUpperCase();
    String? network;
    
    if (coinSymbol.contains('TRC20')) {
      network = 'tron';
    } else if (coinSymbol.contains('BEP20')) {
      network = 'bsc';
    } else if (coinSymbol.contains('ERC20')) {
      network = 'ethereum';
    }
    
    // Find matching token
    TokenInfo? matchingToken;
    for (final token in _tokens) {
      if (token.symbol.toUpperCase() == symbol) {
        if (network != null) {
          if (token.network == network) {
            matchingToken = token;
            break;
          }
        } else {
          matchingToken = token;
          break;
        }
      }
    }
    
    if (matchingToken != null) {
      _fromToken = matchingToken;
      // Set a different default "to" token
      if (_fromToken.symbol == 'BTC') {
        _toToken = _tokens.firstWhere((t) => t.symbol == 'ETH', orElse: () => _tokens[3]);
      } else if (_fromToken.symbol == 'ETH') {
        _toToken = _tokens.firstWhere((t) => t.symbol == 'BTC', orElse: () => _tokens[0]);
      } else {
        _toToken = _tokens.firstWhere((t) => t.symbol == 'USDT' && t.network == 'bsc', orElse: () => _tokens[0]);
      }
    }
  }

  /// Map TokenInfo to the chain identifier used for balance queries.
  /// For tokens like USDT, returns e.g. 'USDT-BEP20', 'USDT-TRC20'.
  /// For native coins, returns the symbol as-is.
  String _balanceChain(TokenInfo token) {
    if (token.contractAddress != null) {
      // It's a token on a specific network
      switch (token.network) {
        case 'ethereum': return '${token.symbol}-ERC20';
        case 'bsc':      return '${token.symbol}-BEP20';
        case 'tron':     return '${token.symbol}-TRC20';
        case 'solana':   return '${token.symbol}-SPL';
        case 'polygon':  return '${token.symbol}-POLYGON';
        default:         return token.symbol;
      }
    }
    return token.symbol;
  }

  /// Map TokenInfo to the underlying native chain for address/key lookup.
  /// USDT on BSC → 'BNB', USDT on Ethereum → 'ETH', USDT on Tron → 'TRX', etc.
  String _nativeChain(TokenInfo token) {
    switch (token.network) {
      case 'ethereum': return 'ETH';
      case 'bsc':      return 'BNB';
      case 'tron':     return 'TRX';
      case 'bitcoin':  return 'BTC';
      case 'solana':   return 'SOL';
      case 'ripple':   return 'XRP';
      case 'polygon':  return 'ETH'; // Polygon uses same addresses as ETH
      default:         return token.symbol;
    }
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
      
      final balChain = _balanceChain(token); // e.g. 'USDT-BEP20' or 'ETH'
      final addrChain = _nativeChain(token);  // e.g. 'BNB' or 'ETH'
      
      // Get address — look up by native chain AND by token chain
      if (!_addresses.containsKey(token.id)) {
        // Try the native chain first (BNB for BEP20, ETH for ERC20, etc.)
        var addrs = await _walletService!.getStoredAddresses(addrChain);
        if (addrs.isEmpty) {
          // Fallback: try with the token chain identifier
          addrs = await _walletService!.getStoredAddresses(balChain);
        }
        // For EVM tokens, also try ETH addresses (same format)
        if (addrs.isEmpty && (token.network == 'bsc' || token.network == 'polygon')) {
          addrs = await _walletService!.getStoredAddresses('ETH');
        }
        if (addrs.isNotEmpty) {
          _addresses[token.id] = addrs.first;
        }
      }
      
      // Get balance using the proper chain identifier
      final addr = _addresses[token.id];
      if (addr != null && addr.isNotEmpty) {
        final bal = await _blockchainService!.getBalance(balChain, addr)
            .timeout(const Duration(seconds: 8), onTimeout: () => 0.0);
        if (mounted) {
          setState(() => _balances[token.id] = bal);
          debugPrint('💱 Swap balance for ${token.id}: $bal ($balChain @ $addr)');
        }
        // If direct call returned 0, fallback to walletService aggregated balances
        if (bal <= 0 && token.contractAddress != null) {
          try {
            final all = await _walletService!.getBalances()
                .timeout(const Duration(seconds: 10), onTimeout: () => <String, double>{});
            final fallback = all[balChain] ?? all[token.symbol] ?? 0.0;
            if (fallback > 0 && mounted) {
              setState(() => _balances[token.id] = fallback);
              debugPrint('💱 Swap fallback balance for ${token.id}: $fallback');
            }
          } catch (_) {}
        }
      } else {
        // No address found — try walletService as last resort
        debugPrint('⚠️ No address for ${token.id} ($addrChain), trying walletService');
        try {
          final all = await _walletService!.getBalances()
              .timeout(const Duration(seconds: 10), onTimeout: () => <String, double>{});
          final fallback = all[balChain] ?? all[token.symbol] ?? 0.0;
          if (fallback > 0 && mounted) {
            setState(() => _balances[token.id] = fallback);
            debugPrint('💱 Swap walletService balance for ${token.id}: $fallback');
          }
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('Error loading balance for ${token.id}: $e');
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
      final toAddrChain = _nativeChain(_toToken);
      var addrs = await _walletService!.getStoredAddresses(toAddrChain);
      // Fallback for EVM tokens — try ETH addresses
      if (addrs.isEmpty && (_toToken.network == 'bsc' || _toToken.network == 'polygon')) {
        addrs = await _walletService!.getStoredAddresses('ETH');
      }
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
                final chain = _nativeChain(token);
                final res = await _walletService!.generateAddressFor(chain);
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
    if (_selectedQuote == null && _quotes.isEmpty) return;
    // Use the user's selected quote, or fallback to best (first) if none selected
    _selectedQuote ??= _quotes.first;
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

  /// Request gas sponsorship from backend (gasless swap UX).
  Future<bool> _requestGasSponsor(String address, String chain) async {
    try {
      final url = '${ApiConfig.baseUrl}/api/blockchain/gas/sponsor';
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'address': address, 'chain': chain}),
      ).timeout(const Duration(seconds: 45));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          // If already funded, no need to wait for tx confirmation
          if (data['alreadyFunded'] == true) return true;
          // Otherwise tx was sent; confirmed flag tells us if it landed
          return data['confirmed'] == true || data['txHash'] != null;
        }
      }
      debugPrint('Gas sponsor HTTP ${response.statusCode}: ${response.body}');
      return false;
    } catch (e) {
      debugPrint('Gas sponsor request failed: $e');
      return false;
    }
  }

  Future<void> _executeSwap() async {
    if (_selectedQuote == null) return;
    
    setState(() {
      _isExecuting = true;
      _statusMessage = 'Executing swap...';
    });

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
      if (usdValue < 5.0) {
        throw Exception('Minimum swap amount is \$5 USD');
      }

      // Auto-sponsor gas for token swaps (gasless UX)
      final fromNative = _nativeChain(_fromToken);
      final isTokenSwap = _fromToken.contractAddress != null;
      if (isTokenSwap && fromAddr.isNotEmpty) {
        _blockchainService ??= BlockchainService();
        final gasBal = await _blockchainService!.getBalance(fromNative, fromAddr)
            .timeout(const Duration(seconds: 8), onTimeout: () => 0.0);
        final minGas = fromNative == 'BNB' ? 0.0005 : 0.002;
        if (gasBal < minGas) {
          // Auto-request gas from backend sponsor
          setState(() => _statusMessage = 'Preparing network fees...');
          final chainParam = fromNative == 'BNB' ? 'BSC' : 'ETH';
          final sponsored = await _requestGasSponsor(fromAddr, chainParam);
          if (!sponsored) {
            throw Exception(
              'Unable to prepare swap automatically.\n\n'
              'Deposit a small amount of $fromNative to your wallet and try again.',
            );
          }
          // Wait for sponsor tx to propagate on chain
          setState(() => _statusMessage = 'Confirming preparation...');
          await Future.delayed(const Duration(seconds: 5));
        }
      }

      setState(() => _statusMessage = 'Executing swap...');

      // Get private key — must use the native chain key
      // Keys are stored as e.g. ETH_0x..._private, BNB_0x..._private, TRX_T..._private
      var pk = await _walletService!.getPrivateKey(fromNative, fromAddr);
      // Fallback: try ETH key for EVM tokens (BNB, Polygon reuse ETH keys)
      if (pk == null && (fromNative == 'BNB' || fromNative == 'MATIC')) {
        pk = await _walletService!.getPrivateKey('ETH', fromAddr);
      }
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
        // REJECT simulated swaps — they are not real blockchain transactions
        if (result.isSimulated) {
          throw Exception(
            'This swap pair is not yet supported for real on-chain execution. '
            'Try swapping between same-chain tokens (e.g. BNB↔USDT on BSC) '
            'or BTC swaps via THORChain.',
          );
        }

        // Update balances
        final fee = _selectedQuote!.fee;
        final toAmount = result.toAmount ?? _selectedQuote!.toAmount;
        _balances[_fromToken.id] = ((_balances[_fromToken.id] ?? 0) - _amount).clamp(0.0, double.infinity);
        _balances[_toToken.id] = (_balances[_toToken.id] ?? 0) + toAmount;

        // Use the proper chain identifiers for cached balance updates
        final fromBal = _balanceChain(_fromToken);
        final toBal = _balanceChain(_toToken);
        await _walletService!.updateCachedBalance(fromBal, _balances[_fromToken.id]!);
        await _walletService!.updateCachedBalance(toBal, _balances[_toToken.id]!);

        // Save swap to history and persist balance adjustments
        final swapTxHash = result.txHash ?? 'swap_${DateTime.now().millisecondsSinceEpoch}';
        await _walletService!.recordSwapTransaction(
          fromCoin: _fromToken.symbol,
          toCoin: _toToken.symbol,
          fromAmount: _amount,
          toAmount: toAmount,
          fee: fee,
          txHash: swapTxHash,
        );

        // Also store as a Transaction so it appears in Transaction History page
        final txService = TransactionService();
        await txService.storeTransaction(tx_model.Transaction(
          id: swapTxHash,
          type: 'swap',
          coin: _toToken.symbol,
          amount: toAmount,
          address: toAddr ?? '',
          txHash: swapTxHash,
          timestamp: DateTime.now(),
          status: 'completed',
          fee: fee,
          fromCoin: _fromToken.symbol,
          toCoin: _toToken.symbol,
          fromAmount: _amount,
          toAmount: toAmount,
          exchangeRate: toAmount / _amount,
        ));

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
          _statusMessage = '';
          _slidePosition = 0.0;
        });
        
        // Parse error for user-friendly message
        String errorMsg = e.toString();
        if (errorMsg.contains('Exception:')) {
          errorMsg = errorMsg.replaceAll('Exception:', '').trim();
        }
        if (errorMsg.contains('Unable to prepare swap')) {
          // Auto-sponsor failed — show simple dialog
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Row(children: [
                Icon(Icons.info_outline, color: Colors.orange[700]),
                const SizedBox(width: 8),
                const Text('Swap Unavailable'),
              ]),
              content: Text(errorMsg),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
          return;
        }
        if (errorMsg.contains('failed to send tx')) {
          errorMsg = 'Transaction failed. Your balance may be too low for gas fees, or the swap amount is below the DEX minimum.';
        } else if (errorMsg.contains('insufficient')) {
          final nativeChain = _nativeChain(_fromToken);
          errorMsg = 'Insufficient $nativeChain balance for gas fees. You need $nativeChain to pay transaction fees on ${_fromToken.networkName}.';
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

  void _showSwapHistory() async {
    _walletService ??= WalletService();
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final swapHistory = await _walletService!.getSwapHistory();
      if (mounted) Navigator.pop(context);
      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) {
          return DraggableScrollableSheet(
            initialChildSize: 0.7,
            minChildSize: 0.4,
            maxChildSize: 0.9,
            expand: false,
            builder: (_, scrollController) {
              return Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40, height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _fromToken.color.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(Icons.history, color: _fromToken.color, size: 24),
                        ),
                        const SizedBox(width: 12),
                        const Text('Swap History', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        const Spacer(),
                        Text('${swapHistory.length} swaps', style: TextStyle(color: Colors.grey[600], fontSize: 14)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    Expanded(
                      child: swapHistory.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.swap_horiz, size: 64, color: Colors.grey[300]),
                                  const SizedBox(height: 16),
                                  Text('No swap history yet', style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                                  const SizedBox(height: 8),
                                  Text('Complete a swap to see it here', style: TextStyle(color: Colors.grey[400], fontSize: 14)),
                                ],
                              ),
                            )
                          : ListView.builder(
                              controller: scrollController,
                              itemCount: swapHistory.length,
                              itemBuilder: (ctx, index) {
                                final swap = swapHistory[index];
                                final fromCoin = swap['fromCoin'] ?? 'Unknown';
                                final toCoin = swap['toCoin'] ?? 'Unknown';
                                final fromAmount = (swap['fromAmount'] ?? 0.0).toDouble();
                                final toAmount = (swap['toAmount'] ?? 0.0).toDouble();
                                final fee = (swap['fee'] ?? 0.0).toDouble();
                                final timestamp = swap['timestamp'] ?? '';

                                String formattedDate = 'Unknown date';
                                try {
                                  final dt = DateTime.parse(timestamp);
                                  formattedDate = '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                                } catch (_) {}

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.withOpacity(0.05),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: Colors.grey.withOpacity(0.1)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(fromCoin, style: const TextStyle(fontWeight: FontWeight.bold)),
                                          const SizedBox(width: 8),
                                          const Icon(Icons.arrow_forward, size: 16, color: Colors.grey),
                                          const SizedBox(width: 8),
                                          Text(toCoin, style: const TextStyle(fontWeight: FontWeight.bold)),
                                          const Spacer(),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.green.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: const Text('Completed', style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.w600)),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text('Sent', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                                              Text('-${fromAmount.toStringAsFixed(6)} $fromCoin', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                                            ],
                                          ),
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            children: [
                                              Text('Received', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                                              Text('+${toAmount.toStringAsFixed(6)} $toCoin', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w600)),
                                            ],
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text('Fee: ${fee.toStringAsFixed(6)} $fromCoin', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                                          Text(formattedDate, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load swap history: $e')),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      children: [
        Scaffold(
          backgroundColor: isDark ? const Color(0xFF0D1421) : Colors.grey[50],
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
            IconButton(
              icon: const Icon(Icons.history, color: Colors.white),
              onPressed: _showSwapHistory,
              tooltip: 'Swap History',
            ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1A1F2E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtextColor = isDark ? Colors.white60 : Colors.grey[500]!;
    final fieldBg = isDark ? const Color(0xFF252B3B) : Colors.grey[50]!;
    final fieldBorder = isDark ? Colors.white.withOpacity(0.1) : Colors.grey[200]!;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.3 : 0.1), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('From', style: TextStyle(color: subtextColor, fontWeight: FontWeight.w500)),
              Text('Balance: ${bal.toStringAsFixed(8)}', style: TextStyle(color: subtextColor, fontSize: 12)),
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
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Container(
                  height: 56,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: fieldBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: fieldBorder),
                  ),
                  alignment: Alignment.centerLeft,
                  child: TextField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: textColor),
                    decoration: InputDecoration(
                      hintText: '0.00',
                      hintStyle: TextStyle(color: subtextColor.withOpacity(0.5)),
                      border: InputBorder.none,
                      filled: true,
                      fillColor: Colors.transparent,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _buildTokenSelector(_fromToken, true),
            ],
          ),

          // USD value
          if (_amount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '≈ \$${_getUsdValue(_fromToken, _amount).toStringAsFixed(2)} USD',
                style: TextStyle(color: subtextColor, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildToSection() {
    final est = _selectedQuote?.toAmount ?? (_amount > 0 ? _amount * _getRate(_fromToken, _toToken) * 0.997 : 0.0);
    final bal = _balances[_toToken.id] ?? 0.0;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1A1F2E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtextColor = isDark ? Colors.white60 : Colors.grey[500]!;
    final fieldBg = isDark ? const Color(0xFF252B3B) : Colors.grey[50]!;
    final fieldBorder = isDark ? Colors.white.withOpacity(0.1) : Colors.grey[200]!;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.3 : 0.1), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('To', style: TextStyle(color: subtextColor, fontWeight: FontWeight.w500)),
              Text('Balance: ${bal.toStringAsFixed(6)}', style: TextStyle(color: subtextColor, fontSize: 12)),
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
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Container(
                  height: 56,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: fieldBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: fieldBorder),
                  ),
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        est > 0 ? est.toStringAsFixed(6) : '0.00',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: est > 0 ? textColor : subtextColor.withOpacity(0.5),
                        ),
                      ),
                      if (est > 0)
                        Text(
                          '≈ \$${_getUsdValue(_toToken, est).toStringAsFixed(2)} USD',
                          style: TextStyle(color: subtextColor, fontSize: 11),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _buildTokenSelector(_toToken, false),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPctBtn(String label, double pct) {
    final sel = _selectedPercent == label;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () => _setPercentage(label, pct),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: sel ? _fromToken.color : (isDark ? const Color(0xFF252B3B) : Colors.grey[100]),
          borderRadius: BorderRadius.circular(20),
          border: sel ? null : Border.all(color: isDark ? Colors.white.withOpacity(0.1) : Colors.grey[300]!),
        ),
        child: Text(label, style: TextStyle(
          color: sel ? Colors.white : (isDark ? Colors.white70 : Colors.grey[700]),
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
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: token.color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: token.color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(token.icon, color: token.color, size: 20),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () => _selectToToken(token),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: sel ? token.color : (isDark ? const Color(0xFF252B3B) : Colors.grey[100]),
          borderRadius: BorderRadius.circular(18),
          border: sel ? null : Border.all(color: isDark ? Colors.white.withOpacity(0.1) : Colors.grey[300]!),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(token.icon, size: 14, color: sel ? Colors.white : token.color),
            const SizedBox(width: 4),
            Text(
              '${token.symbol} ${token.networkName}',
              style: TextStyle(
                color: sel ? Colors.white : (isDark ? Colors.white70 : Colors.grey[700]),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1A1F2E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtextColor = isDark ? Colors.white60 : Colors.grey[500]!;
    final detailBg = isDark ? const Color(0xFF252B3B) : Colors.grey[50]!;
    
    return GestureDetector(
      onTap: () => _selectQuote(quote),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? quote.providerColor.withOpacity(0.1) : cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? quote.providerColor : (isDark ? Colors.white.withOpacity(0.08) : Colors.grey[200]!),
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
                              color: selected ? quote.providerColor : textColor,
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
                        style: TextStyle(color: subtextColor, fontSize: 12),
                      ),
                    ],
                  ),
                ),

                // Radio
                Container(
                  width: 24, height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: selected ? quote.providerColor : (isDark ? Colors.white24 : Colors.grey[300]!), width: 2),
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
                color: detailBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('You receive', style: TextStyle(color: subtextColor, fontSize: 11)),
                      Text(
                        '${quote.toAmount.toStringAsFixed(6)} ${_toToken.symbol}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: selected ? quote.providerColor : textColor,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Rate', style: TextStyle(color: subtextColor, fontSize: 11)),
                      Text(
                        '1 ${_fromToken.symbol} = ${quote.rate.toStringAsFixed(4)} ${_toToken.symbol}',
                        style: TextStyle(fontSize: 12, color: textColor),
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
    final color = _selectedQuote!.providerColor;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color, color.withOpacity(0.8), Colors.white, Colors.white],
          stops: const [0.0, 0.12, 0.12, 1.0],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Compact header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(8),
                    onPressed: () => setState(() {
                      _showConfirmation = false;
                      _pinVerified = false;
                      _enteredPin = '';
                      _slidePosition = 0.0;
                    }),
                  ),
                  const Expanded(
                    child: Text('Confirm Swap', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center),
                  ),
                  const SizedBox(width: 40),
                ],
              ),
            ),

            // Compact swap summary card - horizontal layout
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20)],
              ),
              child: Column(
                children: [
                  // From → To in a single horizontal row
                  Row(
                    children: [
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: _fromToken.color.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(_fromToken.icon, color: _fromToken.color, size: 18),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_amount.toStringAsFixed(6), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            Text(_fromToken.displayName, style: TextStyle(color: Colors.grey[500], fontSize: 10)),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(Icons.arrow_forward_rounded, color: color, size: 20),
                      ),
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: _toToken.color.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(_toToken.icon, color: _toToken.color, size: 18),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_selectedQuote!.toAmount.toStringAsFixed(6), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            Text(_toToken.displayName, style: TextStyle(color: Colors.grey[500], fontSize: 10)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Provider + fee + time in one compact row
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'via ${_selectedQuote!.providerName}',
                          style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 11),
                        ),
                      ),
                      const Spacer(),
                      Text('Fee ${_selectedQuote!.feePercent}%', style: TextStyle(color: Colors.grey[600], fontSize: 11)),
                      const SizedBox(width: 12),
                      Text(_selectedQuote!.estimatedTime, style: TextStyle(color: Colors.grey[600], fontSize: 11)),
                    ],
                  ),
                  // Warning for low amounts
                  if (_getUsdValue(_fromToken, _amount) < 20)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange[200]!),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: Colors.orange[700], size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Small swaps may fail due to high gas fees',
                              style: TextStyle(color: Colors.orange[800], fontSize: 10),
                            ),
                          ),
                        ],
                      ),
                    ),
                  // Gas requirement notice for token swaps
                  if (_fromToken.contractAddress != null) ...[
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green[200]!),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle_outline, color: Colors.green[700], size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Gas fees handled automatically',
                              style: TextStyle(color: Colors.green[800], fontSize: 10),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // PIN or Slide
            if (!_pinVerified)
              Expanded(child: _buildPinEntry())
            else
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: _buildSlideToSwap(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPinEntry() {
    return Column(
      children: [
        const SizedBox(height: 8),
        Text('Enter PIN', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey[800])),
        const SizedBox(height: 4),
        Text('Enter your 6-digit PIN to confirm', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
        const SizedBox(height: 12),

        // PIN dots
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(6, (i) {
            final filled = i < _enteredPin.length;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 6),
              width: filled ? 14 : 12,
              height: filled ? 14 : 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: filled ? _selectedQuote!.providerColor : Colors.transparent,
                border: Border.all(color: filled ? _selectedQuote!.providerColor : Colors.grey[300]!, width: 2),
              ),
            );
          }),
        ),

        const SizedBox(height: 12),

        // Number pad
        Expanded(
          child: GridView.count(
            crossAxisCount: 3,
            childAspectRatio: 1.6,
            padding: const EdgeInsets.symmetric(horizontal: 32),
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
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 72, height: 72,
          decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), shape: BoxShape.circle),
          child: const Icon(Icons.check_circle, color: Colors.green, size: 48),
        ),
        const SizedBox(height: 12),
        const Text('PIN Verified!', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green)),
        const SizedBox(height: 4),
        Text('Tap to confirm your swap', style: TextStyle(color: Colors.grey[600])),
        const SizedBox(height: 16),

        if (_isExecuting)
          Column(
            children: [
              CircularProgressIndicator(color: color),
              const SizedBox(height: 16),
              Text(
                _statusMessage.isNotEmpty ? _statusMessage : 'Executing swap via ${_selectedQuote!.providerName}...',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: () {
                  HapticFeedback.heavyImpact();
                  _executeSwap();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 4,
                  shadowColor: color.withOpacity(0.4),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.swap_horiz, color: Colors.white, size: 22),
                    const SizedBox(width: 8),
                    Text('Confirm Swap', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ),

        const SizedBox(height: 16),
      ],
    );
  }
}
