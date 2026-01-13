import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import '../core/config/api_config.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/transaction_model.dart';
import 'transaction_signing_service.dart';
import 'bitcoin_transaction_service.dart';

/// Quote from a DEX provider
class SwapQuote {
  final String provider;
  final String fromCoin;
  final String toCoin;
  final double fromAmount;
  final double toAmount;
  final double exchangeRate;
  final double protocolFee;
  final double gasFee;
  final double bridgeFee;
  final double slippage;
  final double minOutput;
  final String estimatedTime;
  final List<String> route;
  final String? quoteId;

  SwapQuote({
    required this.provider,
    required this.fromCoin,
    required this.toCoin,
    required this.fromAmount,
    required this.toAmount,
    required this.exchangeRate,
    this.protocolFee = 0,
    this.gasFee = 0,
    this.bridgeFee = 0,
    this.slippage = 1.0,
    this.minOutput = 0,
    this.estimatedTime = '1-5 minutes',
    this.route = const [],
    this.quoteId,
  });

  factory SwapQuote.fromJson(Map<String, dynamic> json) {
    return SwapQuote(
      provider: json['provider'] ?? 'unknown',
      fromCoin: json['fromCoin'] ?? '',
      toCoin: json['toCoin'] ?? '',
      fromAmount: (json['fromAmount'] ?? 0).toDouble(),
      toAmount: (json['toAmount'] ?? 0).toDouble(),
      exchangeRate: (json['exchangeRate'] ?? 0).toDouble(),
      protocolFee: (json['protocolFee'] ?? 0).toDouble(),
      gasFee: (json['gasFee'] ?? 0).toDouble(),
      bridgeFee: (json['bridgeFee'] ?? 0).toDouble(),
      slippage: (json['slippage'] ?? 1.0).toDouble(),
      minOutput: (json['minOutput'] ?? 0).toDouble(),
      estimatedTime: json['estimatedTime'] ?? '1-5 minutes',
      route: (json['route'] as List<dynamic>?)?.cast<String>() ?? [],
      quoteId: json['quoteId'],
    );
  }

  double get totalFees => protocolFee + gasFee + bridgeFee;
}

/// Response containing multiple quotes from different providers
class SwapQuoteResponse {
  final bool success;
  final List<SwapQuote> quotes;
  final SwapQuote? bestQuote;
  final String chain;
  final int chainId;
  final String timestamp;
  final String? error;

  SwapQuoteResponse({
    required this.success,
    required this.quotes,
    this.bestQuote,
    this.chain = 'ethereum',
    this.chainId = 1,
    this.timestamp = '',
    this.error,
  });

  factory SwapQuoteResponse.fromJson(Map<String, dynamic> json) {
    final quotesList = (json['quotes'] as List<dynamic>?)
            ?.map((q) => SwapQuote.fromJson(q as Map<String, dynamic>))
            .toList() ??
        [];

    SwapQuote? best;
    if (json['bestQuote'] != null && quotesList.isNotEmpty) {
      final bestProvider = json['bestQuote']['provider'];
      best = quotesList.firstWhere(
        (q) => q.provider == bestProvider,
        orElse: () => quotesList.first,
      );
    } else if (quotesList.isNotEmpty) {
      best = quotesList.first;
    }

    return SwapQuoteResponse(
      success: json['success'] ?? false,
      quotes: quotesList,
      bestQuote: best,
      chain: json['chain'] ?? 'ethereum',
      chainId: json['chainId'] ?? 1,
      timestamp: json['timestamp'] ?? '',
      error: json['error'],
    );
  }
}

/// DEX Provider info
class SwapProvider {
  final String id;
  final String name;
  final String type;
  final List<String> chains;
  final List<String> features;
  final List<String> swapTypes;

  SwapProvider({
    required this.id,
    required this.name,
    required this.type,
    required this.chains,
    required this.features,
    required this.swapTypes,
  });

  factory SwapProvider.fromJson(Map<String, dynamic> json) {
    return SwapProvider(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      type: json['type'] ?? '',
      chains: (json['chains'] as List<dynamic>?)?.cast<String>() ?? [],
      features: (json['features'] as List<dynamic>?)?.cast<String>() ?? [],
      swapTypes: (json['swapTypes'] as List<dynamic>?)?.cast<String>() ?? [],
    );
  }
}

class SwapService {
  static const String _swapTransactionsKey = 'swap_transactions';
  static String get _baseUrl => '${ApiConfig.baseUrl}/api/swap';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final TransactionSigningService _signingService = TransactionSigningService();
  final BitcoinTransactionService _btcService = BitcoinTransactionService();
  final Logger _logger = Logger();

  /// Update swap balance adjustments in SharedPreferences
  Future<void> _updateSwapAdjustments({
    required String fromCoin,
    required String toCoin,
    required double fromAmount,
    required double toAmount,
    required double fee,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Get base coin (USDT-BEP20 -> USDT for balance tracking)
      final fromBase =
          fromCoin.contains('-') ? fromCoin.split('-')[0] : fromCoin;
      final toBase = toCoin.contains('-') ? toCoin.split('-')[0] : toCoin;

      // Debit from source coin
      final currentFromAdj =
          prefs.getDouble('swap_adjustment_$fromBase') ?? 0.0;
      final newFromAdj = currentFromAdj - fromAmount;
      await prefs.setDouble('swap_adjustment_$fromBase', newFromAdj);

      // Credit to destination coin
      final currentToAdj = prefs.getDouble('swap_adjustment_$toBase') ?? 0.0;
      final newToAdj = currentToAdj + toAmount;
      await prefs.setDouble('swap_adjustment_$toBase', newToAdj);

      _logger.i('💾 Updated swap adjustments:');
      _logger.i('   $fromBase: $currentFromAdj → $newFromAdj');
      _logger.i('   $toBase: $currentToAdj → $newToAdj');
    } catch (e) {
      _logger.e('Error updating swap adjustments: $e');
    }
  }

  /// Get swap quotes from multiple DEX providers
  Future<SwapQuoteResponse> getSwapQuotes({
    required String fromCoin,
    required String toCoin,
    required double amount,
    double slippage = 1.0,
    String? userAddress,
    String? preferredProvider,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/quote'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'fromCoin': fromCoin,
          'toCoin': toCoin,
          'amount': amount,
          'slippage': slippage,
          if (userAddress != null) 'userAddress': userAddress,
          if (preferredProvider != null) 'preferredProvider': preferredProvider,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return SwapQuoteResponse.fromJson(data);
      } else {
        final errorData = json.decode(response.body);
        return SwapQuoteResponse(
          success: false,
          quotes: [],
          error: errorData['error'] ?? 'Failed to get quotes',
        );
      }
    } catch (e) {
      return SwapQuoteResponse(
        success: false,
        quotes: [],
        error: 'Network error: $e',
      );
    }
  }

  /// Legacy getSwapQuote for backwards compatibility
  Future<Map<String, dynamic>> getSwapQuote({
    required String fromCoin,
    required String toCoin,
    required double amount,
  }) async {
    final response = await getSwapQuotes(
      fromCoin: fromCoin,
      toCoin: toCoin,
      amount: amount,
    );

    if (!response.success || response.bestQuote == null) {
      throw Exception(response.error ?? 'Failed to get quote');
    }

    final best = response.bestQuote!;
    return {
      'success': true,
      'fromCoin': best.fromCoin.isEmpty ? fromCoin : best.fromCoin,
      'toCoin': best.toCoin.isEmpty ? toCoin : best.toCoin,
      'fromAmount': amount,
      'toAmount': best.toAmount,
      'exchangeRate': best.exchangeRate,
      'fee': best.totalFees,
      'provider': best.provider,
      'minOutput': best.minOutput,
      'estimatedTime': best.estimatedTime,
    };
  }

  /// Get available DEX providers
  Future<List<SwapProvider>> getProviders() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/providers'));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['providers'] != null) {
          return (data['providers'] as List<dynamic>)
              .map((p) => SwapProvider.fromJson(p as Map<String, dynamic>))
              .toList();
        }
      }
      return [];
    } catch (e) {
      print('Failed to load providers: $e');
      return [];
    }
  }

  /// Build transaction for user to sign (non-custodial)
  Future<Map<String, dynamic>> buildTransaction({
    required String provider,
    required String fromCoin,
    required String toCoin,
    required double fromAmount,
    required String userAddress,
    double slippage = 1.0,
    String? quoteId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/build-transaction'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'provider': provider,
          'fromCoin': fromCoin,
          'toCoin': toCoin,
          'fromAmount': fromAmount,
          'userAddress': userAddress,
          'slippage': slippage,
          if (quoteId != null) 'quoteId': quoteId,
        }),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['error'] ?? 'Failed to build transaction');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  // Execute swap via backend API
  Future<Map<String, dynamic>> executeSwap({
    required String fromCoin,
    required String toCoin,
    required double fromAmount,
    required double toAmount,
    required double exchangeRate,
    required double fee,
    required String userAddress,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/execute'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'fromCoin': fromCoin,
          'toCoin': toCoin,
          'fromAmount': fromAmount,
          'toAmount': toAmount,
          'exchangeRate': exchangeRate,
          'fee': fee,
          'userAddress': userAddress,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['success'] == true) {
          // Backend returns swap data directly, not a transaction object
          // Create a local transaction record from the response
          if (data['txHash'] != null) {
            final transaction = Transaction(
              id: data['txHash'],
              type: 'swap',
              amount: fromAmount,
              coin: fromCoin,
              address: userAddress,
              timestamp: DateTime.now(),
              status: data['status'] == 'completed' ? 'completed' : 'pending',
              txHash: data['txHash'],
              fromCoin: fromCoin,
              toCoin: toCoin,
              fromAmount: fromAmount,
              toAmount: toAmount,
              exchangeRate: exchangeRate,
            );
            await _saveSwapTransaction(transaction);
          }
        }

        return data;
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['error'] ?? 'Swap execution failed');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  // Save swap transaction to secure storage
  Future<void> _saveSwapTransaction(Transaction transaction) async {
    try {
      final existingJson = await _storage.read(key: _swapTransactionsKey);
      List<dynamic> transactions = [];

      if (existingJson != null) {
        transactions = json.decode(existingJson) as List<dynamic>;
      }

      transactions.add(transaction.toJson());

      await _storage.write(
        key: _swapTransactionsKey,
        value: json.encode(transactions),
      );
    } catch (e) {
      throw Exception('Failed to save swap transaction: $e');
    }
  }

  // Get all swap transactions
  Future<List<Transaction>> getSwapTransactions() async {
    try {
      final jsonString = await _storage.read(key: _swapTransactionsKey);
      if (jsonString == null) return [];

      final List<dynamic> jsonList = json.decode(jsonString) as List<dynamic>;
      return jsonList
          .map((json) => Transaction.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw Exception('Failed to load swap transactions: $e');
    }
  }

  // Get swap transaction by ID
  Future<Transaction?> getSwapTransactionById(String id) async {
    final transactions = await getSwapTransactions();
    return transactions.firstWhere((tx) => tx.id == id);
  }

  // Clear all swap transactions (for testing)
  Future<void> clearSwapTransactions() async {
    await _storage.delete(key: _swapTransactionsKey);
  }

  // Get available coins for swapping from backend
  Future<List<String>> getAvailableCoins() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/coins'));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['coins'] != null) {
          final coinsList = data['coins'] as List;
          // Handle both List<String> and List<Map> formats
          final result = <String>[];
          for (var coin in coinsList) {
            String? symbol;
            if (coin is String) {
              symbol = coin;
            } else if (coin is Map) {
              symbol = coin['symbol']?.toString();
            }
            if (symbol != null && symbol.isNotEmpty) {
              result.add(symbol);
            }
          }
          return result.isNotEmpty
              ? result
              : ['BTC', 'ETH', 'USDT', 'BNB', 'MATIC'];
        }
      }
      // Return default coins if API fails
      return ['BTC', 'ETH', 'USDT', 'BNB', 'MATIC'];
    } catch (e) {
      print('Failed to load coins from API: $e');
      // Return default coins on error
      return ['BTC', 'ETH', 'USDT', 'BNB', 'MATIC'];
    }
  }

  // Get current exchange rates from backend
  Future<Map<String, double>> getExchangeRates() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/rates'));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final rates = Map<String, double>.from(data['rates']);
          return rates;
        }
      }
      throw Exception('Failed to fetch exchange rates');
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  // Validate swap parameters
  Map<String, dynamic> validateSwap({
    required String fromCoin,
    required String toCoin,
    required double amount,
  }) {
    final errors = <String, String>{};

    if (fromCoin.isEmpty) {
      errors['fromCoin'] = 'Please select a coin to swap from';
    }

    if (toCoin.isEmpty) {
      errors['toCoin'] = 'Please select a coin to swap to';
    }

    if (fromCoin == toCoin) {
      errors['toCoin'] = 'Cannot swap to the same coin';
    }

    if (amount <= 0) {
      errors['amount'] = 'Amount must be greater than 0';
    }

    if (amount > 10000) {
      errors['amount'] = 'Amount cannot exceed 10,000';
    }

    return {
      'isValid': errors.isEmpty,
      'errors': errors,
    };
  }

  // Calculate minimum amount for swap
  double getMinimumSwapAmount(String coin) {
    switch (coin) {
      case 'BTC':
        return 0.0001;
      case 'ETH':
        return 0.001;
      case 'BNB':
        return 0.01;
      case 'USDT':
        return 1.0;
      default:
        return 0.1;
    }
  }

  // Calculate maximum amount for swap
  double getMaximumSwapAmount(String coin) {
    switch (coin) {
      case 'BTC':
        return 10.0;
      case 'ETH':
        return 100.0;
      case 'BNB':
        return 1000.0;
      case 'USDT':
        return 10000.0;
      default:
        return 1000.0;
    }
  }

  /// Execute a REAL swap by signing and broadcasting to the blockchain
  /// This is the main method for production swaps
  Future<RealSwapResult> executeRealSwap({
    required String fromCoin,
    required String toCoin,
    required double fromAmount,
    required String userAddress,
    required String privateKey,
    String?
        destinationAddress, // Address to receive the swapped coins (for cross-chain)
    String provider = 'auto',
    double slippage = 1.0,
    String?
        targetNetwork, // Target network for stablecoins (ERC20, BEP20, TRC20)
  }) async {
    _logger.i('🔄 Starting REAL swap: $fromAmount $fromCoin → $toCoin');
    if (targetNetwork != null) {
      _logger.i('   Target network: $targetNetwork');
    }

    try {
      final fromBaseCoin = fromCoin.split('-')[0];
      final toBaseCoin = toCoin.split('-')[0];
      final isBtcSwap = fromBaseCoin == 'BTC' || toBaseCoin == 'BTC';
      final isEthToUsdt = fromBaseCoin == 'ETH' && toBaseCoin == 'USDT';

      // FOR ETH→USDT SWAPS: Use THORChain for ERC20 USDT
      if (isEthToUsdt) {
        _logger.i('🔗 ETH→USDT swap detected');

        final destAddress = destinationAddress;
        if (destAddress == null || destAddress.isEmpty) {
          throw Exception('Destination address required for ETH→USDT swap');
        }

        // Determine the correct USDT asset based on network
        String usdtAsset =
            'ETH.USDT-0XDAC17F958D2EE523A2206206994597C13D831EC7'; // Default ERC20
        if (targetNetwork == 'BEP20') {
          // For BEP20 USDT, we would need BSC integration
          _logger
              .w('⚠️ BEP20 USDT requires BSC swap - using 1inch/PancakeSwap');
          return await _executeEvmDexSwap(
            fromCoin: fromCoin,
            toCoin: toCoin,
            fromAmount: fromAmount,
            userAddress: userAddress,
            destinationAddress: destAddress,
            privateKey: privateKey,
            chainId: 56, // BSC
            targetNetwork: targetNetwork,
          );
        } else if (targetNetwork == 'TRC20') {
          _logger.w('⚠️ TRC20 USDT requires Tron network - not yet supported');
          throw Exception(
              'TRC20 USDT swaps are not yet supported. Please select ERC20 or BEP20.');
        }

        // For ERC20 USDT, use THORChain or DEX aggregator
        _logger.i('   Using THORChain for ETH→USDT (ERC20)');
        return await _executeEthToUsdtSwap(
          fromAmount: fromAmount,
          userAddress: userAddress,
          destinationAddress: destAddress,
          privateKey: privateKey,
          usdtAsset: usdtAsset,
        );
      }

      // FOR BTC SWAPS: Always use THORChain directly (no simulation!)
      if (isBtcSwap) {
        _logger.i('🔗 BTC swap detected - using THORChain for REAL swap');

        // For cross-chain swaps, we need the destination address for the TO coin
        // If not provided, we'll throw an error
        final destAddress = destinationAddress;
        if (destAddress == null || destAddress.isEmpty) {
          throw Exception(
              'Destination address required for cross-chain BTC swap. Please provide your $toBaseCoin wallet address.');
        }

        _logger.i('   From: $userAddress (BTC)');
        _logger.i('   To: $destAddress ($toBaseCoin)');

        // Get THORChain quote directly
        final thorQuote = await _getThorChainQuote(
          fromCoin: fromCoin,
          toCoin: toCoin,
          amount: fromAmount,
          userAddress: destAddress, // Use destination address for the quote
        );

        if (thorQuote != null) {
          _logger
              .i('✅ THORChain quote received: ${thorQuote.toAmount} $toCoin');
          return await _executeThorChainBtcSwap(
            fromCoin: fromCoin,
            toCoin: toCoin,
            fromAmount: fromAmount,
            userAddress: userAddress,
            destinationAddress: destAddress, // Pass the target chain address!
            privateKey: privateKey,
            quote: thorQuote,
            chainId: fromBaseCoin == 'BTC' ? 0 : _getChainId(fromBaseCoin),
          );
        } else {
          throw Exception('THORChain quote unavailable for BTC swap');
        }
      }

      // Step 1: Get quote from backend for non-BTC swaps
      _logger.i('📊 Step 1: Getting quote...');
      final quoteResponse = await getSwapQuotes(
        fromCoin: fromCoin,
        toCoin: toCoin,
        amount: fromAmount,
        slippage: slippage,
        userAddress: userAddress,
        preferredProvider: provider == 'auto' ? null : provider,
      );

      if (!quoteResponse.success || quoteResponse.bestQuote == null) {
        throw Exception(quoteResponse.error ?? 'Failed to get swap quote');
      }

      final quote = quoteResponse.bestQuote!;
      final chainId = quoteResponse.chainId;
      _logger.i('   Quote: ${quote.toAmount} $toCoin via ${quote.provider}');

      // Check if this is a price-estimate only (no real DEX available)
      if (quote.provider == 'price-estimate') {
        _logger.w('⚠️ No real DEX available for this pair');
        throw Exception(
            'No real DEX available for ${fromCoin} -> ${toCoin}. Try a different pair.');
      }

      // Step 2: Build transaction from backend (only for real DEX providers)
      _logger.i('🔨 Step 2: Building transaction...');
      Map<String, dynamic> txBuildResult;
      try {
        txBuildResult = await buildTransaction(
          provider: quote.provider,
          fromCoin: fromCoin,
          toCoin: toCoin,
          fromAmount: fromAmount,
          userAddress: userAddress,
          slippage: slippage,
          quoteId: quote.quoteId,
        );
      } catch (e) {
        _logger.w('⚠️ Build transaction failed, falling back to simulated: $e');
        // Fallback to simulated swap
        final result = await executeSwap(
          fromCoin: fromCoin,
          toCoin: toCoin,
          fromAmount: fromAmount,
          toAmount: quote.toAmount,
          exchangeRate: quote.exchangeRate,
          fee: quote.totalFees,
          userAddress: userAddress,
        );

        return RealSwapResult(
          success: result['success'] == true,
          txHash: result['txHash'],
          fromCoin: fromCoin,
          toCoin: toCoin,
          fromAmount: fromAmount,
          toAmount: quote.toAmount,
          exchangeRate: quote.exchangeRate,
          provider: quote.provider,
          chainId: chainId,
          explorerUrl: result['explorerUrl'],
          status: SwapStatus.simulated,
          isSimulated: true,
        );
      }

      if (txBuildResult['success'] != true) {
        _logger.w(
            '⚠️ Build transaction returned error, falling back to simulated');
        // Fallback to simulated swap
        final result = await executeSwap(
          fromCoin: fromCoin,
          toCoin: toCoin,
          fromAmount: fromAmount,
          toAmount: quote.toAmount,
          exchangeRate: quote.exchangeRate,
          fee: quote.totalFees,
          userAddress: userAddress,
        );

        return RealSwapResult(
          success: result['success'] == true,
          txHash: result['txHash'],
          fromCoin: fromCoin,
          toCoin: toCoin,
          fromAmount: fromAmount,
          toAmount: quote.toAmount,
          exchangeRate: quote.exchangeRate,
          provider: quote.provider,
          chainId: chainId,
          explorerUrl: result['explorerUrl'],
          status: SwapStatus.simulated,
          isSimulated: true,
        );
      }

      final txData = txBuildResult['transaction'] as Map<String, dynamic>?;

      // Step 3: Check if this is an EVM swap (has transaction data) or simulated
      if (txData != null && txData['to'] != null && txData['data'] != null) {
        // REAL EVM SWAP - Sign and broadcast to blockchain
        _logger.i('🔑 Step 3: Signing transaction...');

        // Check if token approval is needed (for ERC20 tokens)
        if (!['ETH', 'BNB', 'MATIC', 'AVAX'].contains(fromBaseCoin)) {
          // This is a token, check allowance
          final tokenAddress = _getTokenAddress(fromCoin, chainId);
          final spenderAddress = txData['to'] as String;

          if (tokenAddress != null) {
            final allowance = await _signingService.getAllowance(
              tokenAddress,
              userAddress,
              spenderAddress,
              chainId,
            );

            final requiredAmount =
                _toSmallestUnit(fromAmount, _getDecimals(fromCoin));

            if (allowance < requiredAmount) {
              _logger.i('⚠️ Token approval needed, approving...');

              // Approve max uint256 for convenience
              final maxApproval = BigInt.parse(
                'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
                radix: 16,
              );

              final approvalResult = await _signingService.approveToken(
                privateKeyHex: privateKey,
                tokenAddress: tokenAddress,
                spenderAddress: spenderAddress,
                amount: maxApproval,
                chainId: chainId,
              );

              if (!approvalResult.success) {
                throw Exception(
                    'Token approval failed: ${approvalResult.error}');
              }

              _logger.i('✅ Token approved: ${approvalResult.txHash}');

              // Wait a few seconds for approval to confirm
              await Future.delayed(const Duration(seconds: 5));
            }
          }
        }

        // Step 4: Sign and broadcast the swap transaction
        _logger.i('📤 Step 4: Broadcasting transaction...');
        final txResult = await _signingService.executeSwapTransaction(
          privateKeyHex: privateKey,
          transactionData: {
            ...txData,
            'chainId': chainId,
          },
        );

        if (!txResult.success) {
          throw Exception('Transaction failed: ${txResult.error}');
        }

        _logger.i('✅ Transaction sent: ${txResult.txHash}');

        // Step 5: Save transaction record
        final transaction = Transaction(
          id: txResult.txHash ??
              DateTime.now().millisecondsSinceEpoch.toString(),
          type: 'swap',
          amount: fromAmount,
          coin: fromCoin,
          address: userAddress,
          timestamp: DateTime.now(),
          status: 'pending',
          txHash: txResult.txHash,
          fromCoin: fromCoin,
          toCoin: toCoin,
          fromAmount: fromAmount,
          toAmount: quote.toAmount,
          exchangeRate: quote.exchangeRate,
        );
        await _saveSwapTransaction(transaction);

        return RealSwapResult(
          success: true,
          txHash: txResult.txHash,
          fromCoin: fromCoin,
          toCoin: toCoin,
          fromAmount: fromAmount,
          toAmount: quote.toAmount,
          exchangeRate: quote.exchangeRate,
          provider: quote.provider,
          chainId: chainId,
          explorerUrl: txResult.explorerUrl,
          status: SwapStatus.pending,
        );
      } else {
        // SIMULATED SWAP (for BTC or when no DEX available)
        _logger.w('⚠️ No real transaction data, using simulated swap');

        // Execute simulated swap via backend
        final result = await executeSwap(
          fromCoin: fromCoin,
          toCoin: toCoin,
          fromAmount: fromAmount,
          toAmount: quote.toAmount,
          exchangeRate: quote.exchangeRate,
          fee: quote.totalFees,
          userAddress: userAddress,
        );

        return RealSwapResult(
          success: result['success'] == true,
          txHash: result['txHash'],
          fromCoin: fromCoin,
          toCoin: toCoin,
          fromAmount: fromAmount,
          toAmount: quote.toAmount,
          exchangeRate: quote.exchangeRate,
          provider: quote.provider,
          chainId: chainId,
          explorerUrl: result['explorerUrl'],
          status: SwapStatus.simulated,
          isSimulated: true,
        );
      }
    } catch (e) {
      _logger.e('❌ Real swap failed: $e');
      return RealSwapResult(
        success: false,
        error: e.toString(),
        fromCoin: fromCoin,
        toCoin: toCoin,
        fromAmount: fromAmount,
        status: SwapStatus.failed,
      );
    }
  }

  /// Track transaction status on blockchain
  Future<TransactionStatus?> trackTransaction(
      String txHash, int chainId) async {
    try {
      return await _signingService.getTransactionStatus(txHash, chainId);
    } catch (e) {
      _logger.e('Failed to track transaction: $e');
      return null;
    }
  }

  // Helper: Get token address for a coin on a chain
  String? _getTokenAddress(String coin, int chainId) {
    final tokens = {
      1: {
        // Ethereum
        'USDT': '0xdAC17F958D2ee523a2206206994597C13D831ec7',
        'USDC': '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48',
        'DAI': '0x6B175474E89094C44Da98b954EedeAC495271d0F',
        'WBTC': '0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599',
      },
      56: {
        // BSC
        'USDT': '0x55d398326f99059fF775485246999027B3197955',
        'USDC': '0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d',
        'BUSD': '0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56',
      },
      137: {
        // Polygon
        'USDT': '0xc2132D05D31c914a87C6611C10748AEb04B58e8F',
        'USDC': '0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174',
      },
    };

    final baseCoin = coin.split('-')[0];
    return tokens[chainId]?[baseCoin];
  }

  // Helper: Get decimals for a coin
  int _getDecimals(String coin) {
    final baseCoin = coin.split('-')[0];
    const decimals = {
      'USDT': 6,
      'USDC': 6,
      'BTC': 8,
      'WBTC': 8,
    };
    return decimals[baseCoin] ?? 18;
  }

  // Helper: Convert to smallest unit
  BigInt _toSmallestUnit(double amount, int decimals) {
    return BigInt.from(amount * BigInt.from(10).pow(decimals).toDouble());
  }

  // ==================== THORCHAIN BTC SWAP METHODS ====================

  /// Execute a real BTC swap via THORChain
  Future<RealSwapResult> _executeThorChainBtcSwap({
    required String fromCoin,
    required String toCoin,
    required double fromAmount,
    required String userAddress,
    required String
        destinationAddress, // Address on target chain to receive swapped coins
    required String privateKey,
    required SwapQuote quote,
    int? chainId,
  }) async {
    _logger.i('🔗 Executing REAL BTC swap via THORChain');
    _logger.i('   Source address: $userAddress');
    _logger.i('   Destination address: $destinationAddress');

    try {
      final fromBaseCoin = fromCoin.split('-')[0];
      final toBaseCoin = toCoin.split('-')[0];

      // Get THORChain swap details - use destinationAddress which is on the TARGET chain
      final thorData = await _getThorChainSwapDetails(
        fromCoin: fromCoin,
        toCoin: toCoin,
        amount: fromAmount,
        destinationAddress:
            destinationAddress, // Must be address on target chain!
      );

      if (thorData == null) {
        throw Exception('Failed to get THORChain swap details');
      }

      final inboundAddress = thorData['inbound_address'] as String?;
      final memo = thorData['memo'] as String?;
      final expectedOutput = thorData['expected_amount_out'] as String?;

      if (inboundAddress == null || memo == null) {
        throw Exception(
            'THORChain returned invalid data: missing inbound_address or memo');
      }

      _logger.i('   THORChain Vault: $inboundAddress');
      _logger.i('   Memo: $memo');
      _logger.i('   Expected Output: $expectedOutput');

      // Determine if we're swapping FROM BTC or TO BTC
      if (fromBaseCoin == 'BTC') {
        // SENDING BTC to THORChain vault
        _logger.i('📤 Sending BTC to THORChain vault...');

        // Convert amount to satoshis
        final amountSatoshis = (fromAmount * 100000000).round();

        // Use BitcoinTransactionService to send real BTC
        final btcResult = await _btcService.sendBitcoinForSwap(
          privateKeyWIF: _convertToWIF(privateKey),
          fromAddress: userAddress,
          toAddress: inboundAddress,
          amountSatoshis: amountSatoshis,
          memo: memo,
        );

        if (!btcResult.success) {
          throw Exception(btcResult.error ?? 'BTC transaction failed');
        }

        final txHash = btcResult.txId!;
        final isSimulated = btcResult.isSimulated;

        if (isSimulated) {
          _logger.w('⚠️ Swap simulated: ${btcResult.simulationReason}');
        } else {
          _logger.i('✅ BTC sent to THORChain: $txHash');
        }

        // Parse expected output
        double toAmount = quote.toAmount;
        if (expectedOutput != null) {
          toAmount = double.tryParse(expectedOutput) ?? quote.toAmount;
          // THORChain returns in base units, convert
          if (toBaseCoin == 'ETH' || toBaseCoin == 'USDT') {
            toAmount = toAmount / 1e8; // THORChain uses 8 decimals
          }
        }

        // Save transaction
        final transaction = Transaction(
          id: txHash,
          type: 'swap',
          amount: fromAmount,
          coin: fromCoin,
          address: userAddress,
          timestamp: DateTime.now(),
          status: isSimulated ? 'simulated' : 'pending',
          txHash: txHash,
          fromCoin: fromCoin,
          toCoin: toCoin,
          fromAmount: fromAmount,
          toAmount: toAmount,
          exchangeRate: toAmount / fromAmount,
        );
        await _saveSwapTransaction(transaction);

        // Update swap balance adjustments for UI
        await _updateSwapAdjustments(
          fromCoin: fromCoin,
          toCoin: toCoin,
          fromAmount: fromAmount,
          toAmount: toAmount,
          fee: btcResult.fee?.toDouble() ?? 0,
        );

        return RealSwapResult(
          success: true,
          txHash: txHash,
          fromCoin: fromCoin,
          toCoin: toCoin,
          fromAmount: fromAmount,
          toAmount: toAmount,
          exchangeRate: toAmount / fromAmount,
          provider: 'thorchain',
          explorerUrl: isSimulated ? null : 'https://mempool.space/tx/$txHash',
          status: isSimulated ? SwapStatus.simulated : SwapStatus.pending,
          isSimulated: isSimulated,
          simulationReason: btcResult.simulationReason,
        );
      } else {
        // SWAPPING TO BTC (e.g., ETH → BTC)
        // Need to send EVM token to THORChain router
        _logger.i('📤 Sending $fromBaseCoin to THORChain router...');

        // Use EVM signing for ETH/tokens to THORChain
        final txResult = await _signingService.executeSwapTransaction(
          privateKeyHex: privateKey,
          transactionData: {
            'to': inboundAddress,
            'value': (BigInt.from(fromAmount * 1e18)).toString(),
            'chainId': chainId ?? _getChainId(fromBaseCoin),
            'data':
                '0x${_encodeThorchainfMemo(memo).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}',
          },
        );

        if (!txResult.success) {
          throw Exception(txResult.error ?? 'EVM transaction failed');
        }

        _logger.i('✅ Sent to THORChain router: ${txResult.txHash}');

        // Save transaction
        final transaction = Transaction(
          id: txResult.txHash ??
              DateTime.now().millisecondsSinceEpoch.toString(),
          type: 'swap',
          amount: fromAmount,
          coin: fromCoin,
          address: userAddress,
          timestamp: DateTime.now(),
          status: 'pending',
          txHash: txResult.txHash,
          fromCoin: fromCoin,
          toCoin: toCoin,
          fromAmount: fromAmount,
          toAmount: quote.toAmount,
          exchangeRate: quote.exchangeRate,
        );
        await _saveSwapTransaction(transaction);

        // Update swap balance adjustments for UI
        await _updateSwapAdjustments(
          fromCoin: fromCoin,
          toCoin: toCoin,
          fromAmount: fromAmount,
          toAmount: quote.toAmount,
          fee: 0,
        );

        return RealSwapResult(
          success: true,
          txHash: txResult.txHash,
          fromCoin: fromCoin,
          toCoin: toCoin,
          fromAmount: fromAmount,
          toAmount: quote.toAmount,
          exchangeRate: quote.exchangeRate,
          provider: 'thorchain',
          chainId: chainId,
          explorerUrl: txResult.explorerUrl,
          status: SwapStatus.pending,
          isSimulated: false,
        );
      }
    } catch (e) {
      _logger.e('❌ THORChain BTC swap failed: $e');
      return RealSwapResult(
        success: false,
        error: e.toString(),
        fromCoin: fromCoin,
        toCoin: toCoin,
        fromAmount: fromAmount,
        status: SwapStatus.failed,
      );
    }
  }

  /// Execute ETH→USDT swap via THORChain
  Future<RealSwapResult> _executeEthToUsdtSwap({
    required double fromAmount,
    required String userAddress,
    required String destinationAddress,
    required String privateKey,
    required String usdtAsset,
  }) async {
    _logger.i('🔄 Executing ETH→USDT swap via THORChain');

    try {
      // Get THORChain swap details for ETH→USDT
      final thorData = await _getThorChainSwapDetails(
        fromCoin: 'ETH',
        toCoin: 'USDT',
        amount: fromAmount,
        destinationAddress: destinationAddress,
      );

      if (thorData == null) {
        throw Exception('Failed to get THORChain swap details for ETH→USDT');
      }

      final inboundAddress = thorData['inbound_address'] as String?;
      final memo = thorData['memo'] as String?;
      final expectedOutput = thorData['expected_amount_out'] as String?;
      final router = thorData['router'] as String?;

      if (inboundAddress == null || memo == null) {
        throw Exception('THORChain returned invalid data');
      }

      _logger.i('   THORChain Router: ${router ?? inboundAddress}');
      _logger.i('   Memo: $memo');
      _logger.i('   Expected Output: $expectedOutput USDT');

      // Convert ETH amount to wei
      final amountWei = BigInt.from(fromAmount * 1e18);

      // For ETH swaps to THORChain, send ETH directly to the router with memo
      // THORChain reads the memo from transaction input data
      final txResult = await _signingService.executeSwapTransaction(
        privateKeyHex: privateKey,
        transactionData: {
          'to': router ?? inboundAddress,
          'value': amountWei.toString(),
          'chainId': 1, // Ethereum mainnet
          'data':
              '0x${_encodeThorchainfMemo(memo).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}',
          'gasLimit': '80000', // Higher gas for THORChain deposit
        },
      );

      if (!txResult.success) {
        throw Exception(txResult.error ?? 'ETH transaction failed');
      }

      _logger.i('✅ ETH sent to THORChain: ${txResult.txHash}');

      // Parse expected USDT output
      double toAmount = 0.0;
      if (expectedOutput != null) {
        // THORChain returns USDT in 8 decimals, convert to 6
        toAmount = double.tryParse(expectedOutput) ?? 0.0;
        toAmount = toAmount / 1e8 * 1e6 / 1e6; // Convert to human readable
      }

      // Save transaction
      final transaction = Transaction(
        id: txResult.txHash ?? DateTime.now().millisecondsSinceEpoch.toString(),
        type: 'swap',
        amount: fromAmount,
        coin: 'ETH',
        address: userAddress,
        timestamp: DateTime.now(),
        status: 'pending',
        txHash: txResult.txHash,
        fromCoin: 'ETH',
        toCoin: 'USDT',
        fromAmount: fromAmount,
        toAmount: toAmount,
        exchangeRate: toAmount / fromAmount,
      );
      await _saveSwapTransaction(transaction);

      // Update swap balance adjustments
      await _updateSwapAdjustments(
        fromCoin: 'ETH',
        toCoin: 'USDT',
        fromAmount: fromAmount,
        toAmount: toAmount,
        fee: 0,
      );

      return RealSwapResult(
        success: true,
        txHash: txResult.txHash,
        fromCoin: 'ETH',
        toCoin: 'USDT',
        fromAmount: fromAmount,
        toAmount: toAmount,
        exchangeRate: toAmount / fromAmount,
        provider: 'thorchain',
        chainId: 1,
        explorerUrl: 'https://etherscan.io/tx/${txResult.txHash}',
        status: SwapStatus.pending,
        isSimulated: false,
      );
    } catch (e) {
      _logger.e('❌ ETH→USDT swap failed: $e');
      return RealSwapResult(
        success: false,
        error: e.toString(),
        fromCoin: 'ETH',
        toCoin: 'USDT',
        fromAmount: fromAmount,
        status: SwapStatus.failed,
      );
    }
  }

  /// Execute EVM DEX swap (for BEP20 USDT, etc.)
  Future<RealSwapResult> _executeEvmDexSwap({
    required String fromCoin,
    required String toCoin,
    required double fromAmount,
    required String userAddress,
    required String destinationAddress,
    required String privateKey,
    required int chainId,
    String? targetNetwork,
  }) async {
    _logger.i('🔄 Executing EVM DEX swap on chain $chainId');

    try {
      final fromBaseCoin = fromCoin.split('-')[0];
      final toBaseCoin = toCoin.split('-')[0];

      // Get 1inch or DEX quote for BSC
      // For now, we'll use a direct approach with known DEX routers

      if (chainId == 56) {
        // BSC - PancakeSwap or 1inch
        _logger.i('   Using BSC DEX for ${fromBaseCoin}→${toBaseCoin}');

        // WETH/WBNB addresses on BSC
        const wbnbAddress = '0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c';
        const usdtBep20 = '0x55d398326f99059fF775485246999027B3197955';
        const pancakeRouter = '0x10ED43C718714eb63d5aA57B78B54704E256024E';

        // For ETH→USDT on BSC, we need to bridge ETH first or use cross-chain
        // This is complex - for now, return an error with guidance
        if (fromBaseCoin == 'ETH') {
          _logger.w('⚠️ ETH→BEP20 USDT requires bridging ETH to BSC first');
          throw Exception('To get BEP20 USDT, you need BNB on BSC. '
              'Recommendation: Swap ETH→USDT (ERC20) on Ethereum, then bridge to BSC.');
        }

        // If user has BNB, swap BNB→USDT on PancakeSwap
        if (fromBaseCoin == 'BNB') {
          // Encode PancakeSwap swapExactETHForTokens call
          final deadline =
              (DateTime.now().millisecondsSinceEpoch ~/ 1000) + 1200;
          final amountWei = BigInt.from(fromAmount * 1e18);

          // Build swap transaction
          final swapData = _encodePancakeSwapData(
            amountOutMin:
                BigInt.zero, // No minimum for now (use slippage in production)
            path: [wbnbAddress, usdtBep20],
            to: destinationAddress,
            deadline: deadline,
          );

          final txResult = await _signingService.executeSwapTransaction(
            privateKeyHex: privateKey,
            transactionData: {
              'to': pancakeRouter,
              'value': amountWei.toString(),
              'chainId': chainId,
              'data': swapData,
              'gasLimit': '250000',
            },
          );

          if (!txResult.success) {
            throw Exception(txResult.error ?? 'BSC transaction failed');
          }

          _logger.i('✅ BSC swap sent: ${txResult.txHash}');

          return RealSwapResult(
            success: true,
            txHash: txResult.txHash,
            fromCoin: fromCoin,
            toCoin: 'USDT-BEP20',
            fromAmount: fromAmount,
            toAmount: fromAmount * 580, // Approximate BNB/USDT rate
            provider: 'pancakeswap',
            chainId: chainId,
            explorerUrl: 'https://bscscan.com/tx/${txResult.txHash}',
            status: SwapStatus.pending,
            isSimulated: false,
          );
        }
      }

      throw Exception(
          'EVM DEX swap not supported for this pair on chain $chainId');
    } catch (e) {
      _logger.e('❌ EVM DEX swap failed: $e');
      return RealSwapResult(
        success: false,
        error: e.toString(),
        fromCoin: fromCoin,
        toCoin: toCoin,
        fromAmount: fromAmount,
        status: SwapStatus.failed,
      );
    }
  }

  /// Encode PancakeSwap swapExactETHForTokens function call
  String _encodePancakeSwapData({
    required BigInt amountOutMin,
    required List<String> path,
    required String to,
    required int deadline,
  }) {
    // Function signature: swapExactETHForTokens(uint256 amountOutMin, address[] path, address to, uint256 deadline)
    // Selector: 0x7ff36ab5
    final selector = '7ff36ab5';

    // Encode parameters (simplified - production should use proper ABI encoding)
    final amountOutMinHex = amountOutMin.toRadixString(16).padLeft(64, '0');
    final deadlineHex = deadline.toRadixString(16).padLeft(64, '0');
    final toHex = to.toLowerCase().replaceAll('0x', '').padLeft(64, '0');

    // Offset for path array (4 * 32 = 128 = 0x80)
    const pathOffsetHex =
        '0000000000000000000000000000000000000000000000000000000000000080';

    // Path array length
    final pathLengthHex = path.length.toRadixString(16).padLeft(64, '0');

    // Path addresses
    final pathHex = path
        .map((addr) => addr.toLowerCase().replaceAll('0x', '').padLeft(64, '0'))
        .join('');

    return '0x$selector$amountOutMinHex$pathOffsetHex$toHex$deadlineHex$pathLengthHex$pathHex';
  }

  /// Get THORChain swap details from backend
  Future<Map<String, dynamic>?> _getThorChainSwapDetails({
    required String fromCoin,
    required String toCoin,
    required double amount,
    required String destinationAddress,
  }) async {
    try {
      final fromBaseCoin = fromCoin.split('-')[0];
      final toBaseCoin = toCoin.split('-')[0];

      // Map coins to THORChain assets
      final fromAsset = _getThorAsset(fromBaseCoin);
      final toAsset = _getThorAsset(toBaseCoin);

      if (fromAsset == null || toAsset == null) {
        _logger.e('Unsupported THORChain asset: $fromBaseCoin or $toBaseCoin');
        return null;
      }

      // Convert amount to THORChain units (8 decimals)
      final amountInBaseUnits = (amount * 1e8).round();

      // Call THORNode API directly for quote
      final url =
          Uri.parse('https://thornode.ninerealms.com/thorchain/quote/swap'
              '?from_asset=$fromAsset'
              '&to_asset=$toAsset'
              '&amount=$amountInBaseUnits'
              '&destination=$destinationAddress');

      _logger.i('🔗 THORChain quote URL: $url');

      final response = await http.get(url);

      _logger.i('📡 THORChain response status: ${response.statusCode}');
      _logger.i(
          '📡 THORChain response body: ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}...');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _logger.i(
            '✅ THORChain quote received: inbound=${data['inbound_address']}, memo=${data['memo']}');
        return data;
      } else {
        _logger.e(
            'THORChain quote failed: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e, stackTrace) {
      _logger.e('Failed to get THORChain details: $e');
      _logger.e('Stack trace: $stackTrace');
      return null;
    }
  }

  /// Get THORChain quote as SwapQuote object
  Future<SwapQuote?> _getThorChainQuote({
    required String fromCoin,
    required String toCoin,
    required double amount,
    required String userAddress,
  }) async {
    try {
      final details = await _getThorChainSwapDetails(
        fromCoin: fromCoin,
        toCoin: toCoin,
        amount: amount,
        destinationAddress: userAddress,
      );

      if (details == null) return null;

      // Parse THORChain response
      final expectedOut = details['expected_amount_out'] as String?;
      final fees = details['fees'] as Map<String, dynamic>?;

      if (expectedOut == null) return null;

      // THORChain uses 8 decimal places
      final toAmount = double.parse(expectedOut) / 1e8;
      final totalFee = fees?['total'] != null
          ? double.parse(fees!['total'].toString()) / 1e8
          : 0.0;

      return SwapQuote(
        provider: 'thorchain',
        fromCoin: fromCoin,
        toCoin: toCoin,
        fromAmount: amount,
        toAmount: toAmount,
        exchangeRate: toAmount / amount,
        gasFee: totalFee,
        estimatedTime: '15-30 min',
        minOutput: toAmount * 0.97, // 3% slippage buffer
        route: ['THORChain Native Swap'],
      );
    } catch (e) {
      _logger.e('Failed to get THORChain quote: $e');
      return null;
    }
  }

  /// Map coin symbol to THORChain asset identifier
  String? _getThorAsset(String coin) {
    const thorAssets = {
      'BTC': 'BTC.BTC',
      'ETH': 'ETH.ETH',
      'BNB': 'BNB.BNB',
      'DOGE': 'DOGE.DOGE',
      'LTC': 'LTC.LTC',
      'BCH': 'BCH.BCH',
      'AVAX': 'AVAX.AVAX',
      'ATOM': 'GAIA.ATOM',
      'RUNE': 'THOR.RUNE',
      // Stablecoins on ETH
      'USDT': 'ETH.USDT-0XDAC17F958D2EE523A2206206994597C13D831EC7',
      'USDC': 'ETH.USDC-0XA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48',
    };
    return thorAssets[coin.toUpperCase()];
  }

  /// Convert private key hex to WIF format for Bitcoin
  String _convertToWIF(String privateKeyHex) {
    // If already in WIF format, return as-is
    if (privateKeyHex.startsWith('5') ||
        privateKeyHex.startsWith('K') ||
        privateKeyHex.startsWith('L')) {
      return privateKeyHex;
    }

    // Convert hex to WIF (mainnet, compressed)
    // WIF = Base58Check(0x80 + privateKey + 0x01)
    try {
      final keyBytes = _hexToBytes(privateKeyHex);

      // Add version byte (0x80 for mainnet) and compression flag (0x01)
      final extended = [0x80, ...keyBytes, 0x01];

      // Double SHA256 for checksum
      final hash1 = _sha256(extended);
      final hash2 = _sha256(hash1);
      final checksum = hash2.sublist(0, 4);

      // Append checksum
      final wifBytes = [...extended, ...checksum];

      // Base58 encode
      return _base58Encode(wifBytes);
    } catch (e) {
      _logger.e('Failed to convert to WIF: $e');
      return privateKeyHex; // Return original if conversion fails
    }
  }

  List<int> _hexToBytes(String hex) {
    hex = hex.replaceAll('0x', '');
    final result = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      result.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return result;
  }

  List<int> _sha256(List<int> data) {
    // Using pointycastle for SHA256
    final digest = crypto.sha256.convert(data);
    return digest.bytes;
  }

  String _base58Encode(List<int> bytes) {
    const alphabet =
        '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
    var x = BigInt.zero;
    for (var byte in bytes) {
      x = (x << 8) + BigInt.from(byte);
    }

    final result = <String>[];
    while (x > BigInt.zero) {
      final mod = (x % BigInt.from(58)).toInt();
      x = x ~/ BigInt.from(58);
      result.add(alphabet[mod]);
    }

    // Add leading zeros
    for (var byte in bytes) {
      if (byte == 0) {
        result.add('1');
      } else {
        break;
      }
    }

    return result.reversed.join();
  }

  int _getChainId(String coin) {
    const chainIds = {
      'ETH': 1,
      'BNB': 56,
      'MATIC': 137,
      'AVAX': 43114,
      'ARB': 42161,
      'OP': 10,
    };
    return chainIds[coin] ?? 1;
  }

  List<int> _encodeThorchainfMemo(String memo) {
    // For ETH transactions to THORChain, include memo in tx data
    // THORChain reads the memo from the input data
    return utf8.encode(memo);
  }
}

/// Result of a real blockchain swap
class RealSwapResult {
  final bool success;
  final String? txHash;
  final String? error;
  final String fromCoin;
  final String toCoin;
  final double fromAmount;
  final double? toAmount;
  final double? exchangeRate;
  final String? provider;
  final int? chainId;
  final String? explorerUrl;
  final SwapStatus status;
  final bool isSimulated;
  final String? simulationReason;

  RealSwapResult({
    required this.success,
    this.txHash,
    this.error,
    required this.fromCoin,
    required this.toCoin,
    required this.fromAmount,
    this.toAmount,
    this.exchangeRate,
    this.provider,
    this.chainId,
    this.explorerUrl,
    this.status = SwapStatus.pending,
    this.isSimulated = false,
    this.simulationReason,
  });
}

/// Swap execution status
enum SwapStatus {
  pending,
  confirmed,
  failed,
  simulated,
}
