import 'package:dio/dio.dart';
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../core/config/api_config.dart';

class PriceService {
  static final PriceService _instance = PriceService._internal();
  factory PriceService() => _instance;
  PriceService._internal();

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 12),
    sendTimeout: const Duration(seconds: 8),
    // Do NOT set User-Agent — browsers block it (unsafe header)
  ));
  
  // Cache to prevent excessive API calls — 10 min on web to avoid CORS/rate-limit spam
  final Map<String, _PriceCache> _priceCache = {};
  static Duration get _cacheDuration =>
      kIsWeb ? const Duration(minutes: 10) : const Duration(minutes: 2);
  
  // Rate limiting and circuit breaker
  final Map<String, DateTime> _lastApiCallTime = {};
  final Map<String, int> _consecutiveFailures = {};
  final Map<String, DateTime> _circuitOpenUntil = {};
  static const int _maxConsecutiveFailures = 3;
  static const Duration _circuitResetDuration = Duration(minutes: 5);
  static const Duration _minApiCallInterval = Duration(seconds: 2);

  // Coin symbol mappings for different APIs
  final Map<String, String> _coinGeckoIds = {
    'BTC': 'bitcoin',
    'ETH': 'ethereum',
    'BNB': 'binancecoin',
    'USDT': 'tether',
    'SOL': 'solana',
    'XRP': 'ripple',
    'DOGE': 'dogecoin',
    'LTC': 'litecoin',
    'MATIC': 'matic-network',
    'AVAX': 'avalanche-2',
    'TRX': 'tron',
  };

  // CoinCap IDs — free, no key, browser CORS-friendly
  final Map<String, String> _coinCapIds = {
    'BTC': 'bitcoin',
    'ETH': 'ethereum',
    'BNB': 'binance-coin',
    'USDT': 'tether',
    'SOL': 'solana',
    'XRP': 'xrp',
    'DOGE': 'dogecoin',
    'LTC': 'litecoin',
    'MATIC': 'matic-network',
    'AVAX': 'avalanche',
    'TRX': 'tron',
  };

  final Map<String, String> _binanceSymbols = {
    'BTC': 'BTCUSDT',
    'ETH': 'ETHUSDT',
    'BNB': 'BNBUSDT',
    'SOL': 'SOLUSDT',
    'XRP': 'XRPUSDT',
    'DOGE': 'DOGEUSDT',
    'LTC': 'LTCUSDT',
    'MATIC': 'MATICUSDT',
    'AVAX': 'AVAXUSDT',
    'TRX': 'TRXUSDT',
  };

  /// Get real-time price with multiple fallback APIs, rate limiting, and circuit breaker
  Future<Map<String, dynamic>> getPrice(String symbol) async {
    // Check cache first
    if (_priceCache.containsKey(symbol)) {
      final cache = _priceCache[symbol]!;
      if (DateTime.now().difference(cache.timestamp) < _cacheDuration) {
        print('📦 Using cached price for $symbol');
        return cache.data;
      }
    }

    // Check circuit breaker
    if (_isCircuitOpen(symbol)) {
      print('⚡ Circuit open for $symbol, using cached or fallback data');
      return _getFallbackPrice(symbol);
    }

    // Apply rate limiting
    await _enforceRateLimit(symbol);

    // On web: use backend proxy only when running locally (localhost).
    // The remote Railway backend doesn't have /api/prices yet.
    // For remote/production, go straight to CoinCap (free, CORS-friendly).
    final isLocalBackend = ApiConfig.baseUrl.contains('localhost');
    final apis = kIsWeb
        ? [
            if (isLocalBackend) () => _getPriceFromBackendProxy(symbol),
            () => _getPriceFromCoinCap(symbol),
            () => _getPriceFromCryptoCompare(symbol),
          ]
        : [
            () => _getPriceFromCoinGecko(symbol),
            () => _getPriceFromCoinCap(symbol),
            () => _getPriceFromCryptoCompare(symbol),
          ];

    for (int i = 0; i < apis.length; i++) {
      final apiCall = apis[i];
      try {
        print('🔄 Attempting API ${i + 1} for $symbol');
        final result = await _callWithRetry(apiCall, symbol, maxRetries: 2);
        
        if (result['price'] != null && result['price'] > 0) {
          // Cache successful result
          _priceCache[symbol] = _PriceCache(
            data: result,
            timestamp: DateTime.now(),
          );
          // Reset failure counter on success
          _consecutiveFailures.remove(symbol);
          _circuitOpenUntil.remove(symbol);
          print('✅ Successfully fetched price for $symbol from ${result['source']}');
          return result;
        }
      } catch (e) {
        print('⚠️ API ${i + 1} failed for $symbol: $e');
        _recordFailure(symbol);
        continue; // Try next API
      }
    }

    // All APIs failed
    print('❌ All price APIs failed for $symbol');
    return _getFallbackPrice(symbol);
  }

  /// Get prices for multiple coins
  Future<Map<String, Map<String, dynamic>>> getPrices(List<String> symbols) async {
    final results = <String, Map<String, dynamic>>{};
    
    // On web: backend proxy only for localhost; CoinCap for remote/production.
    // On non-web: CoinGecko batch.
    final isLocalBackend = ApiConfig.baseUrl.contains('localhost');
    if (kIsWeb) {
      if (isLocalBackend) {
        try {
          final prices = await _getBatchPricesFromBackendProxy(symbols);
          if (prices.isNotEmpty) {
            print('✅ Fetched ${prices.length} prices from backend proxy');
            return prices;
          }
        } catch (e) {
          print('❌ Backend proxy batch failed, trying CoinCap: $e');
        }
      }
      // CoinCap — free, no key, CORS-friendly for all environments
      try {
        final prices = await _getBatchPricesFromCoinCap(symbols);
        if (prices.isNotEmpty) {
          print('✅ Fetched ${prices.length} prices from CoinCap');
          return prices;
        }
      } catch (e) {
        print('❌ CoinCap batch failed: $e');
      }
    } else {
      try {
        final prices = await _getBatchPricesFromCoinGecko(symbols);
        if (prices.isNotEmpty) {
          print('✅ Fetched ${prices.length} prices from CoinGecko');
          return prices;
        }
      } catch (e) {
        print('❌ Batch price fetch failed: $e');
      }
    }

    // Fallback: fetch individually
    for (final symbol in symbols) {
      try {
        results[symbol] = await getPrice(symbol);
      } catch (e) {
        print('❌ Failed to get price for $symbol: $e');
        // Use cached price or fallback
        results[symbol] = _getFallbackPrice(symbol);
      }
    }

    // If still empty, return fallback prices for all
    if (results.isEmpty) {
      print('⚠️ All price APIs failed, using fallback prices');
      for (final symbol in symbols) {
        results[symbol] = _getFallbackPrice(symbol);
      }
    }

    return results;
  }
  
  /// Get fallback price when APIs fail
  Map<String, dynamic> _getFallbackPrice(String symbol) {
    // Use cached price if available
    if (_priceCache.containsKey(symbol)) {
      print('📦 Using cached price for $symbol');
      return _priceCache[symbol]!.data;
    }
    
    // Last resort: approximate prices (updated periodically)
    final fallbackPrices = {
      'BTC': 95000.0,
      'ETH': 3300.0,
      'BNB': 680.0,
      'SOL': 190.0,
      'XRP': 2.80,
      'DOGE': 0.35,
      'LTC': 120.0,
      'USDT': 1.0,
      'TRX': 0.25,
    };
    
    return {
      'price': fallbackPrices[symbol] ?? 0.0,
      'change24h': 0.0,
      'lastUpdated': DateTime.now(),
      'source': 'Fallback',
    };
  }

  /// Backend proxy — our own Node.js server fetches CoinGecko server-side.
  /// Zero CORS issues for the browser. Endpoint: GET /api/prices?symbols=BTC,ETH,...
  Future<Map<String, dynamic>> _getPriceFromBackendProxy(String symbol) async {
    final response = await _dio.get(
      '${ApiConfig.baseUrl}/api/prices',
      queryParameters: {'symbols': symbol},
    );
    if (response.statusCode == 200 && response.data?['success'] == true) {
      final prices = response.data['prices'] as Map<String, dynamic>?;
      final data = prices?[symbol] as Map<String, dynamic>?;
      if (data != null && (data['price'] as num? ?? 0) > 0) {
        return {
          'price': (data['price'] as num).toDouble(),
          'change24h': (data['change24h'] as num?)?.toDouble() ?? 0.0,
          'lastUpdated': DateTime.now(),
          'source': 'BackendProxy',
        };
      }
    }
    throw Exception('No price from backend proxy for $symbol');
  }

  /// Backend proxy batch — single call fetches all symbols at once.
  Future<Map<String, Map<String, dynamic>>> _getBatchPricesFromBackendProxy(
      List<String> symbols) async {
    final response = await _dio.get(
      '${ApiConfig.baseUrl}/api/prices',
      queryParameters: {'symbols': symbols.join(',')},
    );
    final results = <String, Map<String, dynamic>>{};
    if (response.statusCode == 200 && response.data?['success'] == true) {
      final prices = response.data['prices'] as Map<String, dynamic>?;
      if (prices != null) {
        for (final sym in symbols) {
          final data = prices[sym] as Map<String, dynamic>?;
          if (data != null && (data['price'] as num? ?? 0) > 0) {
            results[sym] = {
              'price': (data['price'] as num).toDouble(),
              'change24h': (data['change24h'] as num?)?.toDouble() ?? 0.0,
              'lastUpdated': DateTime.now(),
              'source': 'BackendProxy',
            };
          }
        }
      }
    }
    return results;
  }

  /// CoinCap API — 100% free, no API key, explicit CORS headers (best for browsers)
  /// https://docs.coincap.io/
  Future<Map<String, dynamic>> _getPriceFromCoinCap(String symbol) async {
    final assetId = _coinCapIds[symbol];
    if (assetId == null) throw Exception('Unsupported coin: $symbol');

    final response = await _dio.get(
      'https://api.coincap.io/v2/assets/$assetId',
    );

    if (response.statusCode == 200 && response.data != null) {
      final data = response.data['data'];
      if (data != null) {
        final price = double.tryParse(data['priceUsd'] ?? '0') ?? 0.0;
        final change = double.tryParse(data['changePercent24Hr'] ?? '0') ?? 0.0;
        return {
          'price': price,
          'change24h': change,
          'lastUpdated': DateTime.now(),
          'source': 'CoinCap',
        };
      }
    }
    throw Exception('Invalid response from CoinCap');
  }

  /// CoinCap batch — fetch all assets in one call, parse results per symbol
  Future<Map<String, Map<String, dynamic>>> _getBatchPricesFromCoinCap(
      List<String> symbols) async {
    final ids = symbols
        .map((s) => _coinCapIds[s])
        .where((id) => id != null)
        .join(',');
    if (ids.isEmpty) return {};

    final response = await _dio.get(
      'https://api.coincap.io/v2/assets',
      queryParameters: {'ids': ids, 'limit': '20'},
    );

    final results = <String, Map<String, dynamic>>{};
    if (response.statusCode == 200 && response.data?['data'] is List) {
      final List dataList = response.data['data'];
      // Build reverse lookup: coincap_id → our symbol
      final reverseLookup = {
        for (final e in _coinCapIds.entries) e.value: e.key,
      };
      for (final item in dataList) {
        final ourSymbol = reverseLookup[item['id']];
        if (ourSymbol != null && symbols.contains(ourSymbol)) {
          results[ourSymbol] = {
            'price': double.tryParse(item['priceUsd'] ?? '0') ?? 0.0,
            'change24h':
                double.tryParse(item['changePercent24Hr'] ?? '0') ?? 0.0,
            'lastUpdated': DateTime.now(),
            'source': 'CoinCap',
          };
        }
      }
    }
    return results;
  }

  /// CoinGecko API (Primary - Free, no API key needed)
  Future<Map<String, dynamic>> _getPriceFromCoinGecko(String symbol) async {
    final coinId = _coinGeckoIds[symbol];
    if (coinId == null) throw Exception('Unsupported coin: $symbol');

    final response = await _dio.get(
      'https://api.coingecko.com/api/v3/simple/price',
      queryParameters: {
        'ids': coinId,
        'vs_currencies': 'usd',
        'include_24hr_change': 'true',
        'include_last_updated_at': 'true',
      },
    );

    if (response.statusCode == 200 && response.data != null) {
      final data = response.data[coinId];
      if (data != null) {
        return {
          'price': data['usd']?.toDouble() ?? 0.0,
          'change24h': data['usd_24h_change']?.toDouble() ?? 0.0,
          'lastUpdated': DateTime.fromMillisecondsSinceEpoch(
            (data['last_updated_at'] ?? 0) * 1000,
          ),
          'source': 'CoinGecko',
        };
      }
    }
    throw Exception('Invalid response from CoinGecko');
  }

  /// Batch fetch from CoinGecko
  Future<Map<String, Map<String, dynamic>>> _getBatchPricesFromCoinGecko(List<String> symbols) async {
    final coinIds = symbols.map((s) => _coinGeckoIds[s]).where((id) => id != null).join(',');
    
    final response = await _dio.get(
      'https://api.coingecko.com/api/v3/simple/price',
      queryParameters: {
        'ids': coinIds,
        'vs_currencies': 'usd',
        'include_24hr_change': 'true',
        'include_last_updated_at': 'true',
      },
    );

    final results = <String, Map<String, dynamic>>{};
    
    if (response.statusCode == 200 && response.data != null) {
      for (final symbol in symbols) {
        final coinId = _coinGeckoIds[symbol];
        if (coinId != null && response.data[coinId] != null) {
          final data = response.data[coinId];
          results[symbol] = {
            'price': data['usd']?.toDouble() ?? 0.0,
            'change24h': data['usd_24h_change']?.toDouble() ?? 0.0,
            'lastUpdated': DateTime.fromMillisecondsSinceEpoch(
              (data['last_updated_at'] ?? 0) * 1000,
            ),
            'source': 'CoinGecko',
          };
        }
      }
    }
    
    return results;
  }

  /// Binance API (Fallback 1)
  Future<Map<String, dynamic>> _getPriceFromBinance(String symbol) async {
    final binanceSymbol = _binanceSymbols[symbol];
    if (binanceSymbol == null) throw Exception('Unsupported coin: $symbol');

    final response = await _dio.get(
      'https://api.binance.com/api/v3/ticker/24hr',
      queryParameters: {'symbol': binanceSymbol},
    );

    if (response.statusCode == 200 && response.data != null) {
      return {
        'price': double.parse(response.data['lastPrice'] ?? '0'),
        'change24h': double.parse(response.data['priceChangePercent'] ?? '0'),
        'lastUpdated': DateTime.now(),
        'source': 'Binance',
      };
    }
    throw Exception('Invalid response from Binance');
  }

  /// CoinMarketCap API (Fallback 2 - requires API key for production)
  Future<Map<String, dynamic>> _getPriceFromCoinMarketCap(String symbol) async {
    // Note: Free tier available at https://coinmarketcap.com/api/
    // For now, using public endpoint (limited)
    final response = await _dio.get(
      'https://api.coinmarketcap.com/data-api/v3/cryptocurrency/market-pairs/latest',
      queryParameters: {
        'slug': _coinGeckoIds[symbol],
        'limit': '1',
      },
    );

    if (response.statusCode == 200 && response.data != null) {
      final data = response.data['data'];
      if (data != null && data['marketPairs'] != null && data['marketPairs'].isNotEmpty) {
        final pair = data['marketPairs'][0];
        return {
          'price': pair['price']?.toDouble() ?? 0.0,
          'change24h': pair['priceChangePercentage24h']?.toDouble() ?? 0.0,
          'lastUpdated': DateTime.now(),
          'source': 'CoinMarketCap',
        };
      }
    }
    throw Exception('Invalid response from CoinMarketCap');
  }

  /// CryptoCompare API (Fallback 3)
  Future<Map<String, dynamic>> _getPriceFromCryptoCompare(String symbol) async {
    final response = await _dio.get(
      'https://min-api.cryptocompare.com/data/pricemultifull',
      queryParameters: {
        'fsyms': symbol,
        'tsyms': 'USD',
      },
    );

    if (response.statusCode == 200 && response.data != null) {
      final data = response.data['RAW']?[symbol]?['USD'];
      if (data != null) {
        return {
          'price': data['PRICE']?.toDouble() ?? 0.0,
          'change24h': data['CHANGEPCT24HOUR']?.toDouble() ?? 0.0,
          'lastUpdated': DateTime.fromMillisecondsSinceEpoch(
            (data['LASTUPDATE'] ?? 0) * 1000,
          ),
          'source': 'CryptoCompare',
        };
      }
    }
    throw Exception('Invalid response from CryptoCompare');
  }

  /// Clear cache
  void clearCache() {
    _priceCache.clear();
  }

  /// Clear cache for specific symbol
  void clearCacheForSymbol(String symbol) {
    _priceCache.remove(symbol);
  }

  // --- Rate Limiting and Circuit Breaker Methods ---

  /// Check if circuit is open for a symbol
  bool _isCircuitOpen(String symbol) {
    final openUntil = _circuitOpenUntil[symbol];
    if (openUntil != null && DateTime.now().isBefore(openUntil)) {
      return true;
    }
    // Reset if circuit timeout has passed
    if (openUntil != null && DateTime.now().isAfter(openUntil)) {
      _circuitOpenUntil.remove(symbol);
      _consecutiveFailures.remove(symbol);
    }
    return false;
  }

  /// Enforce rate limiting between API calls
  Future<void> _enforceRateLimit(String symbol) async {
    final lastCall = _lastApiCallTime[symbol];
    if (lastCall != null) {
      final timeSinceLastCall = DateTime.now().difference(lastCall);
      if (timeSinceLastCall < _minApiCallInterval) {
        final waitTime = _minApiCallInterval - timeSinceLastCall;
        print('⏳ Rate limiting: waiting ${waitTime.inMilliseconds}ms for $symbol');
        await Future.delayed(waitTime);
      }
    }
    _lastApiCallTime[symbol] = DateTime.now();
  }

  /// Record a failure and potentially open the circuit
  void _recordFailure(String symbol) {
    final failures = (_consecutiveFailures[symbol] ?? 0) + 1;
    _consecutiveFailures[symbol] = failures;

    if (failures >= _maxConsecutiveFailures) {
      _circuitOpenUntil[symbol] = DateTime.now().add(_circuitResetDuration);
      print('⚡ Circuit opened for $symbol until ${_circuitOpenUntil[symbol]}');
      _consecutiveFailures.remove(symbol);
    }
  }

  /// Call an API with retry logic and exponential backoff
  Future<Map<String, dynamic>> _callWithRetry(
    Future<Map<String, dynamic>> Function() apiCall,
    String symbol,
    {int maxRetries = 2}
  ) async {
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        if (attempt > 0) {
          // Exponential backoff: 1s, 2s, 4s
          final backoff = Duration(seconds: 1 << (attempt - 1));
          print('🔄 Retry attempt $attempt for $symbol after ${backoff.inSeconds}s');
          await Future.delayed(backoff);
        }

        return await apiCall().timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw TimeoutException('API timeout'),
        );
      } catch (e) {
        if (attempt == maxRetries) {
          rethrow;
        }
        print('⚠️ Retry $attempt failed for $symbol: $e');
      }
    }
    throw Exception('All retries exhausted for $symbol');
  }
}

class _PriceCache {
  final Map<String, dynamic> data;
  final DateTime timestamp;

  _PriceCache({
    required this.data,
    required this.timestamp,
  });
}
