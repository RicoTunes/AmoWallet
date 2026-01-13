import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/swap_service.dart';
import '../../../services/blockchain_service.dart';
import '../../../services/wallet_service.dart';
import '../../../services/biometric_auth_service.dart';
import '../../../services/price_conversion_service.dart';
import '../../../services/preload_service.dart';
import '../../widgets/pin_dialogs.dart';
import '../../widgets/transaction_confirmation_dialog.dart';

class SwapPage extends ConsumerStatefulWidget {
  const SwapPage({super.key});

  @override
  ConsumerState<SwapPage> createState() => _SwapPageState();
}

class _SwapPageState extends ConsumerState<SwapPage> {
  final SwapService _swapService = SwapService();
  final BlockchainService _blockchainService = BlockchainService();
  final WalletService _walletService = WalletService();
  final BiometricAuthService _authService = BiometricAuthService();
  final PriceConversionService _priceService = PriceConversionService();
  final PreloadService _preloadService = PreloadService();

  String _fromCoin = 'BTC';
  String _toCoin = 'USDT';
  String _selectedUsdtNetwork = 'ERC20'; // Default USDT network for receiving
  double _amount = 0.0;
  bool _isLoading = false;
  bool _showQuote = false;
  Map<String, dynamic>? _quoteData;
  String? _errorMessage;
  List<String> _availableCoins = [
    'BTC',
    'ETH',
    'USDT',
    'BNB',
    'MATIC',
    'SOL',
    'XRP',
    'DOGE',
    'LTC'
  ]; // Simple coin list - network only matters on Send
  bool _loadingCoins = false;
  final Map<String, double> _cachedBalances = {};
  bool _balancesLoaded = false;
  Map<String, double> _exchangeRates = {};
  Map<String, double> _usdPrices = {}; // Real-time USD prices from CoinGecko
  final Map<String, String> _userAddresses = {};
  bool _showUSDValue = true; // Toggle to show USD value conversion
  String _selectedPercentage = ''; // Track selected percentage button

  // Multi-provider swap state
  List<SwapQuote> _availableQuotes = [];
  SwapQuote? _selectedQuote;
  String _swapMode = 'auto'; // 'auto' or 'manual'
  List<SwapProvider> _providers = [];
  
  // USDT network options for receiving
  final List<Map<String, dynamic>> _usdtNetworks = [
    {
      'id': 'ERC20',
      'name': 'Ethereum (ERC20)',
      'chain': 'ETH',
      'icon': '⟠',
      'color': Color(0xFF627EEA),
      'fee': 'Low (~\$1-5)',
      'speed': '~12 min',
      'supported': true,
    },
    {
      'id': 'BEP20',
      'name': 'BNB Smart Chain (BEP20)',
      'chain': 'BNB',
      'icon': '🔶',
      'color': Color(0xFFF0B90B),
      'fee': 'Very Low (~\$0.10)',
      'speed': '~3 min',
      'supported': true,
    },
    {
      'id': 'TRC20',
      'name': 'Tron (TRC20)',
      'chain': 'TRX',
      'icon': '🔴',
      'color': Color(0xFFFF0013),
      'fee': 'Very Low (~\$0.50)',
      'speed': '~3 min',
      'supported': true,
    },
    {
      'id': 'POLYGON',
      'name': 'Polygon (MATIC)',
      'chain': 'MATIC',
      'icon': '🟣',
      'color': Color(0xFF8247E5),
      'fee': 'Very Low (~\$0.01)',
      'speed': '~2 min',
      'supported': false, // Not yet supported
    },
  ];

  // Network selection only matters when sending/withdrawing coins
  // During swap, we just track the base coin (USDT, not USDT-ERC20)

  final TextEditingController _amountController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _amountController.addListener(_onAmountChanged);
    _loadAvailableCoins();
    _initializeWithCachedData();
  }

  /// Initialize with cached data first, then refresh in background
  void _initializeWithCachedData() {
    // Use preloaded data immediately if available
    if (_preloadService.isPreloaded) {
      print('⚡ Using preloaded swap data for instant load');
      
      if (_preloadService.cachedPrices != null) {
        setState(() {
          _usdPrices = _preloadService.cachedPrices!;
        });
      }
      
      if (_preloadService.cachedProviders != null) {
        setState(() {
          _providers = _preloadService.cachedProviders!;
        });
      }
      
      if (_preloadService.cachedBalances != null) {
        setState(() {
          _cachedBalances.addAll(_preloadService.cachedBalances!);
          _balancesLoaded = true;
        });
      }
      
      if (_preloadService.cachedExchangeRates != null) {
        setState(() {
          _exchangeRates = _preloadService.cachedExchangeRates!;
        });
      }
      
      // Refresh in background without blocking UI
      Future.delayed(const Duration(milliseconds: 500), () {
        _refreshDataInBackground();
      });
    } else {
      // No cached data, load everything
      print('📡 No cached data, loading fresh...');
      _loadBalances();
      _loadExchangeRates();
      _loadRealTimePrices();
      _loadProviders();
    }
  }

  /// Refresh data in background without blocking UI
  Future<void> _refreshDataInBackground() async {
    // Don't show loading states, just update when done
    _loadBalances();
    _loadExchangeRates();
    _loadRealTimePrices();
    _loadProviders();
  }

  // Load available DEX providers
  Future<void> _loadProviders() async {
    try {
      final providers = await _swapService.getProviders();
      setState(() {
        _providers = providers;
      });
      print('✅ Loaded ${providers.length} swap providers');
    } catch (e) {
      print('Failed to load providers: $e');
    }
  }

  // Load real-time USD prices from CoinGecko
  Future<void> _loadRealTimePrices() async {
    try {
      final prices = await _priceService.getUSDPrices([
        'BTC',
        'ETH',
        'BNB',
        'USDT',
        'USDC',
        'MATIC',
        'TRX',
        'SOL',
        'XRP',
        'DOGE',
        'LTC'
      ]);
      setState(() {
        _usdPrices = prices;
      });
      print('✅ Loaded real-time prices: $_usdPrices');
    } catch (e) {
      print('Failed to load real-time prices: $e');
    }
  }

  Future<void> _loadAvailableCoins() async {
    if (mounted) {
      setState(() {
        _loadingCoins = true;
      });
    }

    try {
      // Just use simple base coins - network only matters when sending out
      if (mounted) {
        setState(() {
          _availableCoins = ['BTC', 'ETH', 'USDT', 'BNB', 'MATIC', 'SOL', 'XRP', 'DOGE', 'LTC'];
          _fromCoin = 'BTC';
          _toCoin = 'USDT';
        });
      }
    } catch (e) {
      // Keep default coins if API fails
      print('Failed to load coins: $e');
      if (mounted) {
        setState(() {
          _availableCoins = ['BTC', 'ETH', 'USDT', 'BNB', 'MATIC', 'SOL', 'XRP', 'DOGE', 'LTC'];
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loadingCoins = false;
        });
      }
    }
  }

  Future<void> _loadBalances() async {
    try {
      if (mounted) {
        setState(() {
          _balancesLoaded = false;
        });
      }

      // Get user addresses for each coin
      await _loadUserAddresses();

      // Use walletService.getBalances() which includes swap adjustments
      final balances = await _walletService.getBalances();
      
      // Also fetch any coins not in balances that might have real blockchain balance
      for (String coin in _availableCoins) {
        if (_userAddresses.containsKey(coin)) {
          if (balances.containsKey(coin)) {
            // Use the balance from walletService (includes swap adjustments)
            if (mounted) {
              setState(() {
                _cachedBalances[coin] = balances[coin]!;
              });
            }
          } else {
            // Fetch from blockchain for coins not in the balances map
            try {
              final balance = await _blockchainService.getBalance(
                  coin, _userAddresses[coin]!);
              if (mounted) {
                setState(() {
                  _cachedBalances[coin] = balance;
                });
              }
            } catch (e) {
              print('Failed to load balance for $coin: $e');
              if (mounted) {
                setState(() {
                  _cachedBalances[coin] = 0.0;
                });
              }
            }
          }
        } else {
          if (mounted) {
            setState(() {
              _cachedBalances[coin] = 0.0;
            });
          }
        }
      }

      if (mounted) {
        setState(() {
          _balancesLoaded = true;
        });
      }
    } catch (e) {
      print('Failed to load balances: $e');
      if (mounted) {
        setState(() {
          _balancesLoaded = true;
        });
      }
    }
  }

  Future<void> _loadUserAddresses() async {
    try {
      for (String coin in _availableCoins) {
        final addresses = await _walletService.getStoredAddresses(coin);
        if (addresses.isNotEmpty) {
          _userAddresses[coin] = addresses.first;
        } else {
          // If no address exists, generate one
          try {
            final result = await _walletService.generateAddressFor(coin);
            if (result.containsKey('address')) {
              _userAddresses[coin] = result['address']!;
            }
          } catch (e) {
            print('Failed to generate address for $coin: $e');
          }
        }
      }
    } catch (e) {
      print('Failed to load user addresses: $e');
    }
  }

  Future<void> _loadExchangeRates() async {
    try {
      final rates = await _swapService.getExchangeRates();
      if (mounted) {
        setState(() {
          _exchangeRates = rates;
        });
      }
    } catch (e) {
      // Fallback to default rates if API fails
      if (mounted) {
        setState(() {
          _exchangeRates = {
            'BTC/USDT': 45000.0,
            'ETH/USDT': 3000.0,
            'BNB/USDT': 350.0,
            'BTC/ETH': 15.0,
            'ETH/BTC': 0.0667,
          };
        });
      }
      print('Failed to load exchange rates: $e');
    }
  }

  double _getBalance(String coin) {
    return _cachedBalances[coin] ?? 0.0;
  }

  // Get the base coin symbol (strip network suffix like -BEP20, -TRC20)
  String _getBaseCoin(String coin) {
    if (coin.contains('-')) {
      return coin.split('-').first;
    }
    return coin;
  }

  // Get real-time USD price for a coin
  double _getUSDPrice(String coin) {
    final baseCoin = _getBaseCoin(coin);
    // Stablecoins are always $1
    if (baseCoin == 'USDT' ||
        baseCoin == 'USDC' ||
        baseCoin == 'DAI' ||
        baseCoin == 'BUSD') {
      return 1.0;
    }
    return _usdPrices[baseCoin] ?? 0.0;
  }

  double _getExchangeRate(String fromCoin, String toCoin) {
    // First try cached exchange rates from API
    final key = '$fromCoin/$toCoin';
    if (_exchangeRates.containsKey(key)) {
      return _exchangeRates[key]!;
    }

    // Calculate inverse rate if available
    final inverseKey = '$toCoin/$fromCoin';
    if (_exchangeRates.containsKey(inverseKey)) {
      return 1.0 / _exchangeRates[inverseKey]!;
    }

    // Use real-time USD prices to calculate exchange rate
    final fromPrice = _getUSDPrice(fromCoin);
    final toPrice = _getUSDPrice(toCoin);

    if (fromPrice > 0 && toPrice > 0) {
      // Exchange rate = fromCoin USD price / toCoin USD price
      return fromPrice / toPrice;
    }

    // Stablecoin handling
    final fromBase = _getBaseCoin(fromCoin);
    final toBase = _getBaseCoin(toCoin);

    // Stablecoin to stablecoin (1:1)
    if ((fromBase == 'USDT' || fromBase == 'USDC') &&
        (toBase == 'USDT' || toBase == 'USDC')) {
      return 1.0;
    }

    // If we have one side with USD price
    if (fromPrice > 0 && (toBase == 'USDT' || toBase == 'USDC')) {
      return fromPrice; // Convert to stablecoin = USD price
    }

    if ((fromBase == 'USDT' || fromBase == 'USDC') && toPrice > 0) {
      return 1.0 / toPrice; // Convert from stablecoin = 1/USD price
    }

    return 1.0; // Default 1:1 for unknown pairs
  }

  // Calculate estimated amount user will receive in real-time
  double _calculateEstimatedReceive() {
    if (_amount <= 0) return 0.0;

    final rate = _getExchangeRate(_fromCoin, _toCoin);
    final fee = _amount * 0.003; // 0.3% fee
    final amountAfterFee = _amount - fee;
    return amountAfterFee * rate;
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _onAmountChanged() {
    final text = _amountController.text;
    if (text.isNotEmpty) {
      setState(() {
        _amount = double.tryParse(text) ?? 0.0;
        _showQuote = false;
        _quoteData = null;
      });
    } else {
      setState(() {
        _amount = 0.0;
        _showQuote = false;
        _quoteData = null;
      });
    }
  }

  Future<void> _getQuote() async {
    if (_amount <= 0) {
      setState(() {
        _errorMessage = 'Please enter a valid amount';
      });
      return;
    }

    // Check if user has a source wallet
    final sourceWallet = _userAddresses[_fromCoin];
    if (sourceWallet == null || sourceWallet.isEmpty) {
      setState(() {
        _errorMessage = 'You need a $_fromCoin wallet to swap from. Please create one first.';
      });
      return;
    }

    // Check if user has sufficient balance
    final availableBalance = _cachedBalances[_fromCoin] ?? 0.0;
    if (_amount > availableBalance) {
      setState(() {
        _errorMessage =
            'Insufficient balance. Available: ${availableBalance.toStringAsFixed(8)} $_fromCoin';
      });
      return;
    }

    // IMPORTANT: Check if destination wallet exists BEFORE showing quote
    final destWallet = _userAddresses[_toCoin];
    if (destWallet == null || destWallet.isEmpty) {
      // Prompt user to create destination wallet
      final created = await _promptCreateWallet(_toCoin);
      if (!created) {
        setState(() {
          _errorMessage = 'You need a $_toCoin wallet to receive swapped coins.';
        });
        return;
      }
      // Reload user addresses after wallet creation
      await _loadUserAddresses();
    }

    final validation = _swapService.validateSwap(
      fromCoin: _fromCoin,
      toCoin: _toCoin,
      amount: _amount,
    );

    if (!validation['isValid']) {
      final errors = validation['errors'] as Map<String, String>;
      setState(() {
        _errorMessage = errors.values.first;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _availableQuotes = [];
      _selectedQuote = null;
    });

    try {
      // Get REAL quotes from multiple DEX providers
      final response = await _swapService.getSwapQuotes(
        fromCoin: _fromCoin,
        toCoin: _toCoin,
        amount: _amount,
        userAddress: _userAddresses[_fromCoin],
      );

      if (response.success && response.quotes.isNotEmpty) {
        // Got real DEX quotes!
        setState(() {
          _availableQuotes = response.quotes;
          _selectedQuote = response.bestQuote ?? response.quotes.first;
          _quoteData = {
            'fromCoin': _fromCoin,
            'toCoin': _toCoin,
            'fromAmount': _amount,
            'toAmount': _selectedQuote!.toAmount,
            'exchangeRate': _selectedQuote!.exchangeRate,
            'fee': _selectedQuote!.totalFees,
            'provider': _selectedQuote!.provider,
            'minOutput': _selectedQuote!.minOutput,
            'estimatedTime': _selectedQuote!.estimatedTime,
            'route': _selectedQuote!.route,
          };
          _showQuote = true;
        });
        
        print('✅ Got ${response.quotes.length} real quotes from DEX providers');
        for (var q in response.quotes) {
          print('   ${q.provider}: ${q.toAmount.toStringAsFixed(6)} $_toCoin');
        }
      } else {
        // Fallback to local calculation if no quotes
        final estimatedReceive = _calculateEstimatedReceive();
        final localFee = _amount * 0.003;
        
        setState(() {
          _quoteData = {
            'fromCoin': _fromCoin,
            'toCoin': _toCoin,
            'fromAmount': _amount,
            'toAmount': estimatedReceive,
            'exchangeRate': _getExchangeRate(_fromCoin, _toCoin),
            'fee': localFee,
            'provider': 'estimate',
          };
          _showQuote = true;
        });
      }
    } catch (e) {
      // Even if API fails, show quote with local calculation
      final estimatedReceive = _calculateEstimatedReceive();
      setState(() {
        _quoteData = {
          'fromCoin': _fromCoin,
          'toCoin': _toCoin,
          'fromAmount': _amount,
          'toAmount': estimatedReceive,
          'exchangeRate': _getExchangeRate(_fromCoin, _toCoin),
          'fee': _amount * 0.003,
          'provider': 'estimate',
        };
        _showQuote = true;
        _errorMessage = null; // Clear error, we have a local quote
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _executeSwap() async {
    if (_quoteData == null) return;

    // Double-check destination wallet exists (should have been created in _getQuote)
    final targetWallet = _userAddresses[_toCoin];
    if (targetWallet == null || targetWallet.isEmpty) {
      if (mounted) {
        final created = await _promptCreateWallet(_toCoin);
        if (!created) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Cannot proceed without $_toCoin wallet'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
        // Reload addresses after creating wallet
        await _loadUserAddresses();
      }
    }

    // Verify source wallet exists
    final sourceWallet = _userAddresses[_fromCoin];
    if (sourceWallet == null || sourceWallet.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Source wallet for $_fromCoin not found'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Step 1: Require PIN authentication
    final pinSet = await _authService.isPINSet();
    if (!pinSet) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please set up PIN authentication in Settings first'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    // Show PIN dialog for authentication
    bool authenticated = false;
    if (mounted) {
      authenticated = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (context) => const PINVerificationDialog(
              title: 'Confirm Swap',
              subtitle: 'Enter your PIN to authorize this swap',
            ),
          ) ??
          false;
    }

    if (!authenticated) {
      return;
    }

    // Step 2: Show swap confirmation dialog with REAL swap option
    if (mounted) {
      final confirmed = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (context) => SwapConfirmationDialog(
              fromCoin: _quoteData!['fromCoin'],
              toCoin: _quoteData!['toCoin'],
              fromAmount: _quoteData!['fromAmount'].toString(),
              toAmount: _quoteData!['toAmount'].toString(),
              exchangeRate:
                  '1 ${_quoteData!['fromCoin']} = ${_quoteData!['exchangeRate']} ${_quoteData!['toCoin']}',
              networkFee: '${_quoteData!['fee']} ${_quoteData!['fromCoin']}',
              slippage: '0.5%',
              onConfirm: () {},
            ),
          ) ??
          false;

      if (!confirmed) {
        return;
      }
    }

    // Step 3: Execute REAL swap with blockchain transaction
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Get private key for signing the transaction
      final privateKey = await _walletService.getPrivateKey(_fromCoin, sourceWallet);
      
      if (privateKey == null) {
        throw Exception('Unable to access wallet private key');
      }

      // Get destination wallet address for cross-chain swaps
      final destinationWallet = _userAddresses[_toCoin];
      if (destinationWallet == null || destinationWallet.isEmpty) {
        throw Exception('No $_toCoin wallet found. Please create a $_toCoin wallet first to receive swapped coins.');
      }

      final fromAmount = _quoteData!['fromAmount'] is double 
          ? _quoteData!['fromAmount'] as double
          : double.parse(_quoteData!['fromAmount'].toString());
      final toAmount = _quoteData!['toAmount'] is double 
          ? _quoteData!['toAmount'] as double
          : double.parse(_quoteData!['toAmount'].toString());
      final fee = _quoteData!['fee'] is double 
          ? _quoteData!['fee'] as double
          : double.parse(_quoteData!['fee'].toString());

      // Determine the actual toCoin with network (for USDT)
      String actualToCoin = _quoteData!['toCoin'];
      if (actualToCoin == 'USDT') {
        actualToCoin = 'USDT-$_selectedUsdtNetwork';
        print('🔄 Swapping to USDT on $_selectedUsdtNetwork network');
      }

      // Execute REAL blockchain swap
      final result = await _swapService.executeRealSwap(
        fromCoin: _quoteData!['fromCoin'],
        toCoin: actualToCoin, // Use network-specific coin for USDT
        fromAmount: fromAmount,
        userAddress: sourceWallet,
        privateKey: privateKey,
        destinationAddress: destinationWallet, // Address to receive swapped coins
        provider: _selectedQuote?.provider ?? 'auto',
        slippage: 1.0,
        targetNetwork: _toCoin == 'USDT' ? _selectedUsdtNetwork : null,
      );

      if (result.success) {
        // Update local balances after successful swap
        setState(() {
          // Deduct from "From" coin balance (amount + fee)
          final currentFromBalance = _cachedBalances[_fromCoin] ?? 0.0;
          _cachedBalances[_fromCoin] = (currentFromBalance - fromAmount - fee)
              .clamp(0.0, double.infinity);

          // Add to "To" coin balance
          final currentToBalance = _cachedBalances[_toCoin] ?? 0.0;
          _cachedBalances[_toCoin] = currentToBalance + (result.toAmount ?? toAmount);

          // Clear the swap form
          _amountController.clear();
          _amount = 0.0;
          _showQuote = false;
          _quoteData = null;
          _selectedPercentage = '';
        });

        // Save swap to wallet service for persistence
        await _saveSwapToWalletHistory(
          fromCoin: _fromCoin,
          toCoin: _toCoin,
          fromAmount: fromAmount,
          toAmount: result.toAmount ?? toAmount,
          fee: fee,
          txHash: result.txHash ?? 'swap_${DateTime.now().millisecondsSinceEpoch}',
        );

        // Update cached balances
        await _walletService.updateCachedBalance(_fromCoin, _cachedBalances[_fromCoin] ?? 0);
        await _walletService.updateCachedBalance(_toCoin, _cachedBalances[_toCoin] ?? 0);

        if (mounted) {
          // Show success dialog with swap summary and transaction details
          await _showRealSwapSuccessDialog(
            fromCoin: _fromCoin,
            toCoin: _toCoin,
            fromAmount: fromAmount,
            toAmount: result.toAmount ?? toAmount,
            fee: fee,
            txHash: result.txHash,
            explorerUrl: result.explorerUrl,
            isSimulated: result.isSimulated,
          );

          // Navigate back to dashboard
          context.go('/dashboard');
        }
      } else {
        setState(() {
          _errorMessage = result.error ?? 'Swap failed';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Swap execution failed: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Show success dialog for REAL blockchain swaps
  Future<void> _showRealSwapSuccessDialog({
    required String fromCoin,
    required String toCoin,
    required double fromAmount,
    required double toAmount,
    required double fee,
    String? txHash,
    String? explorerUrl,
    bool isSimulated = false,
  }) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                isSimulated 
                    ? Colors.orange.withOpacity(0.1) 
                    : Colors.green.withOpacity(0.1),
                Colors.white,
              ],
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isSimulated 
                      ? Colors.orange.withOpacity(0.15) 
                      : Colors.green.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isSimulated ? Icons.info_outline : Icons.check_circle,
                  size: 48,
                  color: isSimulated ? Colors.orange : Colors.green,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                isSimulated ? 'Swap Simulated' : 'Swap Successful! 🎉',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isSimulated 
                    ? 'This swap was simulated (BTC or no DEX available)'
                    : 'Your transaction is being processed on the blockchain',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 20),
              // Swap details
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    _buildSwapDetailRow('From', '$fromAmount $fromCoin'),
                    const Divider(height: 16),
                    _buildSwapDetailRow('To', '${toAmount.toStringAsFixed(6)} $toCoin'),
                    const Divider(height: 16),
                    _buildSwapDetailRow('Network Fee', '${fee.toStringAsFixed(8)} $fromCoin'),
                    if (txHash != null && !isSimulated) ...[
                      const Divider(height: 16),
                      _buildSwapDetailRow('Status', 'Pending Confirmation', 
                          valueColor: Colors.orange),
                    ],
                  ],
                ),
              ),
              if (txHash != null && explorerUrl != null && !isSimulated) ...[
                const SizedBox(height: 12),
                InkWell(
                  onTap: () {
                    // Open explorer URL (would need url_launcher package)
                    print('Open: $explorerUrl');
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.open_in_new, size: 16, color: Colors.blue[700]),
                        const SizedBox(width: 8),
                        Text(
                          'View on Explorer',
                          style: TextStyle(
                            color: Colors.blue[700],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'TX: ${txHash.substring(0, 10)}...${txHash.substring(txHash.length - 8)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                    fontFamily: 'monospace',
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: isSimulated ? Colors.orange : AppTheme.primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Done',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSwapDetailRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  /// Save swap transaction to wallet history for persistence
  Future<void> _saveSwapToWalletHistory({
    required String fromCoin,
    required String toCoin,
    required double fromAmount,
    required double toAmount,
    required double fee,
    required String txHash,
  }) async {
    try {
      // Record the swap transaction with balance adjustments
      await _walletService.recordSwapTransaction(
        fromCoin: fromCoin,
        toCoin: toCoin,
        fromAmount: fromAmount,
        toAmount: toAmount,
        fee: fee,
        txHash: txHash,
      );
      print('✅ Swap recorded: $fromAmount $fromCoin -> $toAmount $toCoin');
    } catch (e) {
      print('Failed to save swap to history: $e');
    }
  }

  /// Prompt user to create a wallet for receiving swapped coins
  Future<bool> _promptCreateWallet(String coin) async {
    bool? confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppTheme.primaryColor.withOpacity(0.1), Colors.white],
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 48,
                  color: AppTheme.primaryColor,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                '$coin Wallet Required',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'You need a $coin wallet to receive your swapped coins.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Would you like to create one now?',
                textAlign: TextAlign.center,
                style:
                    AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: BorderSide(color: Colors.grey[300]!),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: AppTheme.primaryColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Create Wallet',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed == true) {
      // Show loading dialog
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(),
          ),
        );
      }

      try {
        // Create wallet for the coin
        final result = await _walletService.generateAddressFor(coin);
        final address = result['address'];

        if (address != null && address.isNotEmpty) {
          setState(() {
            _userAddresses[coin] = address;
            _cachedBalances[coin] = 0.0;
          });

          if (mounted) {
            Navigator.pop(context); // Close loading dialog
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('$coin wallet created successfully!'),
                backgroundColor: Colors.green,
              ),
            );
          }

          return true;
        } else {
          if (mounted) {
            Navigator.pop(context); // Close loading dialog
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to create $coin wallet'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return false;
        }
      } catch (e) {
        if (mounted) {
          Navigator.pop(context); // Close loading dialog
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error creating wallet: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return false;
      }
    }

    return false;
  }

  void _swapCoins() {
    setState(() {
      final temp = _fromCoin;
      _fromCoin = _toCoin;
      _toCoin = temp;
      _showQuote = false;
      _quoteData = null;
      _errorMessage = null;
    });
  }

  // Network variants not needed for swap - only matters when sending
  bool _hasNetworkVariants(String coin) {
    return false; // Simplified - network selection happens on Send page
  }

  // Network info - simplified for swap
  List<Map<String, String>> _getNetworkVariants(String coin) {
    return []; // Not needed for swap
  }

  // Get network name from coin symbol
  String _getNetworkName(String coinSymbol) {
    if (coinSymbol.contains('-ERC20')) return 'Ethereum Network';
    if (coinSymbol.contains('-BEP20')) return 'BNB Smart Chain';
    if (coinSymbol.contains('-TRC20')) return 'Tron Network';
    if (coinSymbol.contains('-SOL')) return 'Solana Network';

    switch (coinSymbol.toUpperCase()) {
      case 'BTC':
        return 'Bitcoin Network';
      case 'ETH':
        return 'Ethereum Network';
      case 'BNB':
        return 'BNB Smart Chain';
      case 'TRX':
        return 'Tron Network';
      case 'SOL':
        return 'Solana Network';
      case 'XRP':
        return 'XRP Ledger';
      case 'DOGE':
        return 'Dogecoin Network';
      case 'LTC':
        return 'Litecoin Network';
      case 'MATIC':
        return 'Polygon Network';
      default:
        return 'Main Network';
    }
  }

  /// Show network selection dialog for USDT
  Future<String?> _showUsdtNetworkSelectionDialog() async {
    return await showDialog<String>(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.green.withOpacity(0.08),
                Colors.white,
                Colors.teal.withOpacity(0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.green.withOpacity(0.2),
                      Colors.teal.withOpacity(0.2),
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Text('💵', style: TextStyle(fontSize: 40)),
              ),
              const SizedBox(height: 16),
              const Text(
                'Select USDT Network',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose which network you want to receive USDT on',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 24),
              
              // Network options
              ..._usdtNetworks.map((network) {
                final isSelected = _selectedUsdtNetwork == network['id'];
                final isSupported = network['supported'] == true;
                
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: InkWell(
                    onTap: isSupported ? () {
                      Navigator.pop(context, network['id']);
                    } : null,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isSelected 
                            ? (network['color'] as Color).withOpacity(0.15)
                            : Colors.grey.withOpacity(isSupported ? 0.05 : 0.02),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected 
                              ? (network['color'] as Color)
                              : Colors.grey.withOpacity(isSupported ? 0.2 : 0.1),
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Opacity(
                        opacity: isSupported ? 1.0 : 0.5,
                        child: Row(
                          children: [
                            // Network Icon
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: (network['color'] as Color).withOpacity(0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  network['icon'] as String,
                                  style: const TextStyle(fontSize: 24),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Network info
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        network['name'] as String,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: isSupported ? null : Colors.grey,
                                        ),
                                      ),
                                      if (!isSupported) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.orange.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text(
                                            'Coming Soon',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.orange,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(Icons.speed, size: 12, color: Colors.grey[500]),
                                      const SizedBox(width: 4),
                                      Text(
                                        network['speed'] as String,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Icon(Icons.local_gas_station, size: 12, color: Colors.grey[500]),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Fee: ${network['fee']}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            // Selection indicator
                            if (isSelected && isSupported)
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: network['color'] as Color,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
              
              const SizedBox(height: 8),
              
              // Info text
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Your USDT will be sent to your wallet on the selected network',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue[700],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Handle coin selection - show network selection for USDT
  Future<void> _handleCoinSelection(String coin, bool isFromCoin) async {
    // If selecting USDT as the "To" coin, show network selection
    if (!isFromCoin && coin == 'USDT') {
      final selectedNetwork = await _showUsdtNetworkSelectionDialog();
      if (selectedNetwork != null) {
        setState(() {
          _selectedUsdtNetwork = selectedNetwork;
        });
      } else {
        return; // User cancelled, don't change coin
      }
    }
    await _selectCoinWithNetwork(coin, isFromCoin);
  }

  // Select coin and check if wallet exists
  Future<void> _selectCoinWithNetwork(String coin, bool isFromCoin) async {
    // Check if user has wallet for this coin
    final hasWallet =
        _userAddresses.containsKey(coin) && _userAddresses[coin]!.isNotEmpty;

    if (!hasWallet && !isFromCoin) {
      // For "To" coin, prompt to create wallet
      final created = await _showWalletCreationWizard(coin);
      if (!created) {
        // User cancelled, don't change selection
        return;
      }
    }

    setState(() {
      if (isFromCoin) {
        _fromCoin = coin;
        _amountController.clear();
        _amount = 0.0;
      } else {
        _toCoin = coin;
      }
      _showQuote = false;
      _quoteData = null;
    });

    // Reload balance for the selected coin
    if (!_cachedBalances.containsKey(coin)) {
      await _loadBalanceForCoin(coin);
    }
  }

  // Load balance for a specific coin
  Future<void> _loadBalanceForCoin(String coin) async {
    if (_userAddresses.containsKey(coin)) {
      try {
        final balance =
            await _blockchainService.getBalance(coin, _userAddresses[coin]!);
        setState(() {
          _cachedBalances[coin] = balance;
        });
      } catch (e) {
        print('Failed to load balance for $coin: $e');
        setState(() {
          _cachedBalances[coin] = 0.0;
        });
      }
    }
  }

  // Network selection not needed for swap - simplified
  // Network is only chosen when sending coins OUT of the wallet
  Future<String?> _showNetworkSelectionDialog(
      String baseCoin, bool isFromCoin) async {
    return null; // Not used - network selection happens on Send page
  }

  // Get network color
  Color _getNetworkColor(String network) {
    if (network.contains('Ethereum')) return const Color(0xFF627EEA);
    if (network.contains('BNB') || network.contains('BSC'))
      return const Color(0xFFF0B90B);
    if (network.contains('Tron')) return const Color(0xFFFF0013);
    if (network.contains('Solana')) return const Color(0xFF00FFA3);
    if (network.contains('Polygon')) return const Color(0xFF8247E5);
    return AppTheme.primaryColor;
  }

  // Get network icon emoji
  String _getNetworkIcon(String network) {
    if (network.contains('Ethereum')) return '⟠';
    if (network.contains('BNB') || network.contains('BSC')) return '🔶';
    if (network.contains('Tron')) return '🔴';
    if (network.contains('Solana')) return '◎';
    if (network.contains('Polygon')) return '🟣';
    return '🪙';
  }

  // Show wallet creation wizard
  Future<bool> _showWalletCreationWizard(String coin) async {
    final networkName = _getNetworkName(coin);

    bool? confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.primaryColor.withOpacity(0.08),
                Colors.white,
                AppTheme.secondaryColor.withOpacity(0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Animated Icon Container
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primaryColor.withOpacity(0.2),
                      AppTheme.secondaryColor.withOpacity(0.2),
                    ],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryColor.withOpacity(0.2),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 56,
                  color: AppTheme.primaryColor,
                ),
              ),
              const SizedBox(height: 24),

              // Title
              Text(
                '🎉 Create $coin Wallet',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              // Description
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.withOpacity(0.2)),
                ),
                child: Column(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue[700], size: 24),
                    const SizedBox(height: 8),
                    Text(
                      "You don't have a $coin wallet yet.\nLet's create one to receive your swapped coins!",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.blue[800],
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Network info card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _getNetworkColor(networkName).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: _getNetworkColor(networkName).withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Text(
                      _getNetworkIcon(networkName),
                      style: const TextStyle(fontSize: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            networkName,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: _getNetworkColor(networkName),
                            ),
                          ),
                          Text(
                            'Your new wallet will be created on this network',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Steps
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'What happens next:',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildStepItem('1', 'Generate secure wallet address'),
                    const SizedBox(height: 6),
                    _buildStepItem('2', 'Store private key securely'),
                    const SizedBox(height: 6),
                    _buildStepItem('3', 'Ready to receive $coin!'),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        side: BorderSide(color: Colors.grey[300]!),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: AppTheme.primaryColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 3,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.add_circle_outline,
                              color: Colors.white, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Create Wallet',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed == true) {
      return await _createWalletWithProgress(coin);
    }
    return false;
  }

  Widget _buildStepItem(String number, String text) {
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryColor,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          text,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey[700],
          ),
        ),
      ],
    );
  }

  // Create wallet with progress dialog
  Future<bool> _createWalletWithProgress(String coin) async {
    // Show loading dialog with progress
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              Text(
                'Creating $coin Wallet...',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Generating secure address',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      // Create wallet for the coin
      final result = await _walletService.generateAddressFor(coin);
      final address = result['address'];

      if (mounted) {
        Navigator.pop(context); // Close loading dialog
      }

      if (address != null && address.isNotEmpty) {
        setState(() {
          _userAddresses[coin] = address;
          _cachedBalances[coin] = 0.0;
        });

        // Show success dialog
        if (mounted) {
          await _showWalletCreatedSuccess(coin, address);
        }
        return true;
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to create $coin wallet'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return false;
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating wallet: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }
  }

  // Show wallet created success dialog
  Future<void> _showWalletCreatedSuccess(String coin, String address) async {
    await showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle,
                  size: 56,
                  color: Colors.green,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                '🎉 Wallet Created!',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Your $coin wallet is ready',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${address.substring(0, 12)}...${address.substring(address.length - 8)}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Continue',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Show swap success dialog with summary
  Future<void> _showSwapSuccessDialog({
    required String fromCoin,
    required String toCoin,
    required double fromAmount,
    required double toAmount,
    required double fee,
  }) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.green.withOpacity(0.08),
                Colors.white,
              ],
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Success animation placeholder
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.green.withOpacity(0.2),
                      Colors.green.withOpacity(0.1),
                    ],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.green.withOpacity(0.3),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.check_circle,
                  size: 64,
                  color: Colors.green,
                ),
              ),
              const SizedBox(height: 24),

              const Text(
                '🎉 Swap Successful!',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),

              // Swap summary
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    // From row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.remove_circle_outline,
                                color: Colors.red, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Sent',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '-${fromAmount.toStringAsFixed(8)} $fromCoin',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Arrow
                    Icon(Icons.arrow_downward,
                        color: Colors.grey[400], size: 24),
                    const SizedBox(height: 12),

                    // To row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.add_circle_outline,
                                color: Colors.green, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Received',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '+${toAmount.toStringAsFixed(8)} $toCoin',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),

                    const Divider(height: 24),

                    // Fee row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Network Fee',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                        Text(
                          '${fee.toStringAsFixed(8)} $fromCoin',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // New balances info
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue[600], size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Your balances have been updated',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.blue[700],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Done button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 3,
                  ),
                  child: const Text(
                    'Done',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _setAmountByPercentage(double percentage) {
    final balance = _getBalance(_fromCoin);
    final amount = balance * (percentage / 100);
    setState(() {
      _amount = amount;
      _amountController.text = amount.toStringAsFixed(8);
      _selectedPercentage = '${percentage.toInt()}%';
    });
  }

  /// Show swap history dialog with real swap transactions
  void _showSwapHistory() async {
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final swapHistory = await _walletService.getSwapHistory();
      if (mounted) Navigator.pop(context); // Close loading

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
                    // Handle bar
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    // Title
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(Icons.history, color: AppTheme.primaryColor, size: 24),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Swap History',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        Text(
                          '${swapHistory.length} swaps',
                          style: TextStyle(color: Colors.grey[600], fontSize: 14),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    // Swap list
                    Expanded(
                      child: swapHistory.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.swap_horiz, size: 64, color: Colors.grey[300]),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No swap history yet',
                                    style: TextStyle(color: Colors.grey[600], fontSize: 16),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Complete a swap to see it here',
                                    style: TextStyle(color: Colors.grey[400], fontSize: 14),
                                  ),
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
                                final fromAmount = swap['fromAmount'] ?? 0.0;
                                final toAmount = swap['toAmount'] ?? 0.0;
                                final fee = swap['fee'] ?? 0.0;
                                final timestamp = swap['timestamp'] ?? '';
                                
                                // Parse timestamp
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
                                      // Swap direction
                                      Row(
                                        children: [
                                          _buildSwapCoinBadge(fromCoin),
                                          const SizedBox(width: 8),
                                          const Icon(Icons.arrow_forward, size: 16, color: Colors.grey),
                                          const SizedBox(width: 8),
                                          _buildSwapCoinBadge(toCoin),
                                          const Spacer(),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.green.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: const Text(
                                              'Completed',
                                              style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.w600),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      // Amounts
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text('Sent', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                                              Text(
                                                '-${_formatSwapAmount(fromAmount)} $fromCoin',
                                                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
                                              ),
                                            ],
                                          ),
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            children: [
                                              Text('Received', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                                              Text(
                                                '+${_formatSwapAmount(toAmount)} $toCoin',
                                                style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w600),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      // Fee and date
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            'Fee: ${_formatSwapAmount(fee)} $fromCoin',
                                            style: TextStyle(color: Colors.grey[500], fontSize: 12),
                                          ),
                                          Text(
                                            formattedDate,
                                            style: TextStyle(color: Colors.grey[500], fontSize: 12),
                                          ),
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
      if (mounted) Navigator.pop(context); // Close loading
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load swap history: $e')),
        );
      }
    }
  }

  Widget _buildSwapCoinBadge(String coin) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _getSwapCoinColor(coin).withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        coin,
        style: TextStyle(
          color: _getSwapCoinColor(coin),
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
    );
  }

  Color _getSwapCoinColor(String coin) {
    switch (coin.toUpperCase()) {
      case 'BTC': return Colors.orange;
      case 'ETH': return Colors.blue;
      case 'USDT': return Colors.green;
      case 'BNB': return Colors.amber;
      case 'SOL': return Colors.purple;
      case 'XRP': return Colors.blueGrey;
      case 'DOGE': return Colors.brown;
      case 'LTC': return Colors.grey;
      default: return AppTheme.primaryColor;
    }
  }

  String _formatSwapAmount(dynamic amount) {
    if (amount is double) {
      if (amount < 0.0001) return amount.toStringAsFixed(8);
      if (amount < 1) return amount.toStringAsFixed(6);
      return amount.toStringAsFixed(4);
    }
    return amount.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Swap Coins'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/dashboard'),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black87,
        actions: [
          // Swap History Button
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: _showSwapHistory,
            tooltip: 'Swap History',
          ),
          // USD Toggle Button
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _showUSDValue = !_showUSDValue;
                  });
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _showUSDValue
                        ? Theme.of(context).colorScheme.primary.withOpacity(0.2)
                        : Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _showUSDValue
                          ? Theme.of(context)
                              .colorScheme
                              .primary
                              .withOpacity(0.5)
                          : Colors.grey.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'USD',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _showUSDValue
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        _showUSDValue ? Icons.visibility : Icons.visibility_off,
                        size: 14,
                        color: _showUSDValue
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: GestureDetector(
          onTap: () {
            // Dismiss keyboard when tapping outside text fields
            FocusScope.of(context).unfocus();
          },
          behavior: HitTestBehavior.translucent,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Swap Card with gradient background
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Theme.of(context).colorScheme.primary.withOpacity(0.08),
                        Theme.of(context).colorScheme.secondary.withOpacity(0.08),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color:
                          Theme.of(context).colorScheme.primary.withOpacity(0.1),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withOpacity(0.05),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // From Section
                      _buildSwapSection(
                        context,
                        label: 'From',
                        coin: _fromCoin,
                        amount: _amount,
                        balance: _getBalance(_fromCoin),
                        onCoinChanged: (value) {
                          if (value != null) {
                            _handleCoinSelection(value, true);
                          }
                        },
                        controller: _amountController,
                        isFrom: true,
                      ),

                      // Swap Button
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: GestureDetector(
                          onTap: _swapCoins,
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Theme.of(context).colorScheme.primary,
                                  Theme.of(context).colorScheme.secondary,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withOpacity(0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.swap_vert_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                      ),

                      // To Section
                      _buildSwapSection(
                        context,
                        label: 'To',
                        coin: _toCoin,
                        amount: _quoteData?['toAmount'] ??
                            _calculateEstimatedReceive(),
                        balance: _getBalance(_toCoin),
                        onCoinChanged: (value) {
                          if (value != null) {
                            _handleCoinSelection(value, false);
                          }
                        },
                        controller: null,
                        isFrom: false,
                      ),

                      const SizedBox(height: 20),

                      // Get Quote Button
                      if (!_showQuote)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _getQuote,
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  Theme.of(context).colorScheme.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 4,
                              shadowColor: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withOpacity(0.3),
                            ),
                            child: _isLoading
                                ? Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                  Colors.white),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        'Getting Quote...',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.currency_exchange, size: 20),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Get Quote',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),

                      // Error Message
                      if (_errorMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(
                            _errorMessage!,
                            style: AppTheme.bodyMedium.copyWith(
                              color: AppTheme.errorColor,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                    ],
                  ),
                ),

                // Quote Details
                if (_showQuote && _quoteData != null) ...[
                  const SizedBox(height: 24),
                  _buildQuoteDetails(context),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSwapSection(
    BuildContext context, {
    required String label,
    required String coin,
    required double amount,
    required double balance,
    required Function(String?)? onCoinChanged,
    required TextEditingController? controller,
    required bool isFrom,
  }) {
    // Get network info for USDT
    Map<String, dynamic>? networkInfo;
    if (!isFrom && coin == 'USDT') {
      networkInfo = _usdtNetworks.firstWhere(
        (n) => n['id'] == _selectedUsdtNetwork,
        orElse: () => _usdtNetworks.first,
      );
    }
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with label and balance
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    label,
                    style: AppTheme.titleSmall.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  // Show network badge for USDT
                  if (networkInfo != null) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () async {
                        final selected = await _showUsdtNetworkSelectionDialog();
                        if (selected != null) {
                          setState(() {
                            _selectedUsdtNetwork = selected;
                            _showQuote = false;
                            _quoteData = null;
                          });
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: (networkInfo['color'] as Color).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: (networkInfo['color'] as Color).withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              networkInfo['icon'] as String,
                              style: const TextStyle(fontSize: 12),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _selectedUsdtNetwork,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: networkInfo['color'] as Color,
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              Icons.arrow_drop_down,
                              size: 14,
                              color: networkInfo['color'] as Color,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (_balancesLoaded)
                GestureDetector(
                  onTap: isFrom ? () => _setAmountByPercentage(100) : null,
                  child: Text(
                    'Balance: ${balance.toStringAsFixed(8)}',
                    style: AppTheme.bodySmall.copyWith(
                      color: isFrom
                          ? Colors.blue
                          : Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.6),
                      fontWeight: isFrom ? FontWeight.w600 : FontWeight.w400,
                      decoration: isFrom ? TextDecoration.underline : null,
                    ),
                  ),
                )
              else
                Text(
                  'Balance: Loading...',
                  style: AppTheme.bodySmall.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.4),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Input field and coin selector
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: isFrom
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.grey[800]
                              : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                          ),
                        ),
                        child: TextField(
                          controller: controller,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: InputDecoration(
                            hintText: '0.00',
                            border: InputBorder.none,
                            hintStyle: AppTheme.headlineMedium.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.3),
                              fontSize: 28,
                            ),
                            contentPadding: EdgeInsets.zero,
                            isDense: true,
                          ),
                          style: AppTheme.headlineMedium.copyWith(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    : Text(
                        amount.toStringAsFixed(8),
                        style: AppTheme.headlineMedium.copyWith(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              // Coin selector button
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {}, // Empty tap to ensure hit testing works
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color:
                          Theme.of(context).colorScheme.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color:
                            Theme.of(context).colorScheme.primary.withOpacity(0.2),
                      ),
                    ),
                    child: DropdownButton<String>(
                      value: coin,
                      onChanged: onCoinChanged,
                      items: _availableCoins
                          .where((c) => c.isNotEmpty)
                          .map((String coinItem) {
                        // Check if this is a multi-chain coin with network info
                        final hasNetwork = coinItem.contains('-');
                        final baseCoin = _getBaseCoin(coinItem);
                        final networkName =
                            hasNetwork ? _getNetworkName(coinItem) : '';
                        final networkColor = hasNetwork
                            ? _getNetworkColor(networkName)
                            : Theme.of(context).colorScheme.primary;

                        return DropdownMenuItem<String>(
                          value: coinItem,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: networkColor.withOpacity(0.15),
                                ),
                                child: Center(
                                  child: Text(
                                    hasNetwork
                                        ? _getNetworkIcon(networkName)
                                        : (coinItem.isNotEmpty
                                            ? coinItem.substring(0, 1)
                                            : '?'),
                                    style: AppTheme.bodySmall.copyWith(
                                      fontSize: hasNetwork ? 14 : 12,
                                      fontWeight: FontWeight.bold,
                                      color: networkColor,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    hasNetwork ? baseCoin : coinItem,
                                    style: AppTheme.bodyMedium.copyWith(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (hasNetwork)
                                    Text(
                                      coinItem.split('-').last,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: networkColor,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      underline: const SizedBox(),
                      isExpanded: false,
                      icon: Icon(
                        Icons.arrow_drop_down_rounded,
                        color: isFrom
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.primary,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          // Percentage buttons - only show for FROM field
          if (isFrom && _balancesLoaded) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [25, 50, 75, 100].map((percentage) {
                final isSelected = _selectedPercentage == '$percentage%';
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: percentage != 100 ? 8 : 0,
                    ),
                    child: OutlinedButton(
                      onPressed: () =>
                          _setAmountByPercentage(percentage.toDouble()),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        backgroundColor: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.transparent,
                        side: BorderSide(
                          color: isSelected
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withOpacity(0.3),
                          width: isSelected ? 2 : 1,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        '$percentage%',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.w600,
                          color: isSelected
                              ? Colors.white
                              : Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuoteDetails(BuildContext context) {
    if (_quoteData == null) return const SizedBox();

    final provider = _quoteData!['provider'] ?? 'unknown';
    final isRealQuote = provider != 'estimate';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Provider Badge
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isRealQuote 
                      ? AppTheme.successColor.withOpacity(0.15)
                      : Colors.orange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isRealQuote 
                        ? AppTheme.successColor.withOpacity(0.3)
                        : Colors.orange.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isRealQuote ? Icons.verified : Icons.calculate_outlined,
                      size: 16,
                      color: isRealQuote ? AppTheme.successColor : Colors.orange,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isRealQuote ? _getProviderDisplayName(provider) : 'Estimated',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isRealQuote ? AppTheme.successColor : Colors.orange,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (isRealQuote)
                Text(
                  'Real DEX Quote',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.successColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
          
          // Multiple Quotes Selector (if available)
          if (_availableQuotes.length > 1) ...[
            const SizedBox(height: 16),
            Text(
              'Available Providers (${_availableQuotes.length})',
              style: AppTheme.bodySmall.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 56,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _availableQuotes.length,
                itemBuilder: (context, index) {
                  final quote = _availableQuotes[index];
                  final isSelected = _selectedQuote?.provider == quote.provider;
                  return GestureDetector(
                    onTap: () => _selectQuote(quote),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected 
                            ? Theme.of(context).colorScheme.primary.withOpacity(0.15)
                            : Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected 
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outline.withOpacity(0.3),
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getProviderDisplayName(quote.provider),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isSelected 
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${quote.toAmount.toStringAsFixed(4)} $_toCoin',
                            style: TextStyle(
                              fontSize: 10,
                              color: isSelected 
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
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
          
          const SizedBox(height: 20),
          
          Row(
            children: [
              Icon(
                Icons.swap_horiz_rounded,
                color: Theme.of(context).colorScheme.primary,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                'Swap Details',
                style: AppTheme.titleMedium.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Exchange Rate
          _buildQuoteRow(
            'Exchange Rate',
            '1 $_fromCoin = ${(_quoteData!['exchangeRate'] ?? _getExchangeRate(_fromCoin, _toCoin)).toStringAsFixed(6)} $_toCoin',
          ),
          const SizedBox(height: 12),

          // You Pay
          _buildQuoteRow(
            'You Pay',
            '${(_quoteData!['fromAmount'] ?? _amount).toStringAsFixed(8)} $_fromCoin',
          ),
          const SizedBox(height: 12),

          // You Receive
          _buildQuoteRow(
            'You Receive',
            '${(_quoteData!['toAmount'] ?? _calculateEstimatedReceive()).toStringAsFixed(8)} $_toCoin',
          ),
          const SizedBox(height: 12),

          // Minimum Output (for real quotes)
          if (isRealQuote && _quoteData!['minOutput'] != null) ...[
            _buildQuoteRow(
              'Min. Received (after slippage)',
              '${(_quoteData!['minOutput']).toStringAsFixed(8)} $_toCoin',
            ),
            const SizedBox(height: 12),
          ],

          // Fee
          _buildQuoteRow(
            'Network Fee',
            _quoteData!['fee'] != null && (_quoteData!['fee'] as num) > 0
                ? '\$${(_quoteData!['fee'] as num).toStringAsFixed(2)}'
                : 'Included',
          ),
          const SizedBox(height: 12),

          // Route (for real quotes)
          if (isRealQuote && _quoteData!['route'] != null) ...[
            _buildQuoteRow(
              'Route',
              (_quoteData!['route'] as List).join(' → '),
            ),
            const SizedBox(height: 12),
          ],

          // Estimated Time
          _buildQuoteRow(
            'Estimated Time',
            _quoteData!['estimatedTime'] ?? '1-5 minutes',
          ),

          const SizedBox(height: 20),

          // Non-custodial notice
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.security, size: 20, color: Colors.blue),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Non-custodial swap: You sign the transaction locally. We never hold your funds.',
                    style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Execute Swap Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _executeSwap,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.successColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 4,
                shadowColor: AppTheme.successColor.withOpacity(0.3),
              ),
              child: _isLoading
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Processing...',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_outline, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          isRealQuote ? 'Confirm Swap via ${_getProviderDisplayName(provider)}' : 'Confirm Swap',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
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

  void _selectQuote(SwapQuote quote) {
    setState(() {
      _selectedQuote = quote;
      _quoteData = {
        'fromCoin': _fromCoin,
        'toCoin': _toCoin,
        'fromAmount': _amount,
        'toAmount': quote.toAmount,
        'exchangeRate': quote.exchangeRate,
        'fee': quote.totalFees,
        'provider': quote.provider,
        'minOutput': quote.minOutput,
        'estimatedTime': quote.estimatedTime,
        'route': quote.route,
      };
    });
  }

  String _getProviderDisplayName(String provider) {
    switch (provider.toLowerCase()) {
      case '1inch':
        return '1inch';
      case '0x':
        return '0x Protocol';
      case 'paraswap':
        return 'Paraswap';
      case 'lifi':
        return 'LI.FI';
      case 'thorchain':
        return 'THORChain';
      case 'price-estimate':
      case 'estimate':
        return 'Estimate';
      default:
        return provider;
    }
  }

  Widget _buildQuoteRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          flex: 2,
          child: Text(
            label,
            style: AppTheme.bodyMedium.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          flex: 3,
          child: Text(
            value,
            style: AppTheme.bodyMedium.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
