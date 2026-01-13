import 'package:dio/dio.dart';
import 'dart:async';

class PriceService {
  static final PriceService _instance = PriceService._internal();
  factory PriceService() => _instance;
  PriceService._internal();

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    sendTimeout: const Duration(seconds: 10),
  ));
  
  // Cache to prevent excessive API calls
  final Map<String, _PriceCache> _priceCache = {};
  static const Duration _cacheDuration = Duration(minutes: 2);

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

  /// Get real-time price with multiple fallback APIs
  Future<Map<String, dynamic>> getPrice(String symbol) async {
    // Check cache first
    if (_priceCache.containsKey(symbol)) {
      final cache = _priceCache[symbol]!;
      if (DateTime.now().difference(cache.timestamp) < _cacheDuration) {
        return cache.data;
      }
    }

    // Try multiple APIs in order with fallback
    final apis = [
      () => _getPriceFromCoinGecko(symbol),
      () => _getPriceFromBinance(symbol),
      () => _getPriceFromCoinMarketCap(symbol),
      () => _getPriceFromCryptoCompare(symbol),
    ];

    for (final apiCall in apis) {
      try {
        final result = await apiCall().timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw TimeoutException('API timeout'),
        );
        
        if (result['price'] != null && result['price'] > 0) {
          // Cache successful result
          _priceCache[symbol] = _PriceCache(
            data: result,
            timestamp: DateTime.now(),
          );
          return result;
        }
      } catch (e) {
        print('Price API failed for $symbol: $e');
        continue; // Try next API
      }
    }

    // All APIs failed - throw error instead of returning placeholder
    throw Exception('Unable to fetch real-time price for $symbol. Please check your internet connection.');
  }

  /// Get prices for multiple coins
  Future<Map<String, Map<String, dynamic>>> getPrices(List<String> symbols) async {
    final results = <String, Map<String, dynamic>>{};
    
    // Try to fetch all prices from CoinGecko first (most efficient for multiple coins)
    try {
      final prices = await _getBatchPricesFromCoinGecko(symbols);
      if (prices.isNotEmpty) {
        return prices;
      }
    } catch (e) {
      print('Batch price fetch failed: $e');
    }

    // Fallback: fetch individually
    for (final symbol in symbols) {
      try {
        results[symbol] = await getPrice(symbol);
      } catch (e) {
        print('Failed to get price for $symbol: $e');
        // Don't include failed prices
      }
    }

    if (results.isEmpty) {
      throw Exception('Unable to fetch any real-time prices. Please check your internet connection.');
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
}

class _PriceCache {
  final Map<String, dynamic> data;
  final DateTime timestamp;

  _PriceCache({
    required this.data,
    required this.timestamp,
  });
}
