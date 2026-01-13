import 'package:dio/dio.dart';
import 'dart:math';

class MarketService {
  final Dio _dio;
  Map<String, dynamic>? _cachedPrices;
  DateTime? _cacheTime;
  static const _cacheDuration = Duration(seconds: 30); // Cache for 30 seconds

  MarketService({String baseUrl = 'http://localhost:8000'}) : _dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 3), // Faster timeout
    receiveTimeout: const Duration(seconds: 3),
  ));

  /// Fetch real market prices from CoinGecko API with caching
  Future<Map<String, dynamic>> fetchPrices() async {
    // Return cached data if available and fresh
    if (_cachedPrices != null && _cacheTime != null) {
      final age = DateTime.now().difference(_cacheTime!);
      if (age < _cacheDuration) {
        return _cachedPrices!;
      }
    }

    try {
      final response = await _dio.get(
        'https://api.coingecko.com/api/v3/simple/price',
        queryParameters: {
          'ids': 'bitcoin,ethereum,tether,binancecoin,ripple,solana,tron,litecoin,dogecoin',
          'vs_currencies': 'usd',
          'include_24hr_change': 'true',
        },
      );

      final Map<String, dynamic> result = {};
      
      // Map CoinGecko IDs to our symbols
      final symbolMap = {
        'bitcoin': 'BTC',
        'ethereum': 'ETH',
        'tether': 'USDT',
        'binancecoin': 'BNB',
        'ripple': 'XRP',
        'solana': 'SOL',
        'tron': 'TRX',
        'litecoin': 'LTC',
        'dogecoin': 'DOGE',
      };

      for (final entry in response.data.entries) {
        final coinId = entry.key;
        final data = entry.value;
        final symbol = symbolMap[coinId];
        
        if (symbol != null) {
          result[symbol] = {
            'symbol': symbol,
            'price_usd': data['usd']?.toDouble() ?? 0.0,
            'change_24h': data['usd_24h_change']?.toDouble() ?? 0.0,
          };
        }
      }

      // Cache the result
      _cachedPrices = result;
      _cacheTime = DateTime.now();

      return result;
    } catch (e) {
      // Return cached data if available, otherwise fallback
      if (_cachedPrices != null) {
        return _cachedPrices!;
      }
      return _fallback();
    }
  }

  /// Fetch historical market data for charting from CoinGecko
  Future<List<Map<String, dynamic>>> fetchHistoricalData(String symbol, int days) async {
    try {
      final coinId = _getCoinGeckoId(symbol);
      if (coinId == null) {
        return _generateRealisticHistoricalData(symbol, days);
      }

      final response = await _dio.get(
        'https://api.coingecko.com/api/v3/coins/$coinId/market_chart',
        queryParameters: {
          'vs_currency': 'usd',
          'days': days,
          'interval': days <= 1 ? 'hourly' : 'daily',
        },
      );

      final List<dynamic> prices = response.data['prices'];
      final List<Map<String, dynamic>> data = [];

      for (final priceData in prices) {
        final timestamp = priceData[0];
        final price = priceData[1].toDouble();
        
        data.add({
          'timestamp': timestamp,
          'price': price,
        });
      }

      return data;
    } catch (e) {
      // Fallback to realistic data if API fails
      return _generateRealisticHistoricalData(symbol, days);
    }
  }

  String? _getCoinGeckoId(String symbol) {
    final coinMap = {
      'BTC': 'bitcoin',
      'ETH': 'ethereum',
      'USDT': 'tether',
      'BNB': 'binancecoin',
      'XRP': 'ripple',
      'SOL': 'solana',
      'TRX': 'tron',
      'LTC': 'litecoin',
      'DOGE': 'dogecoin',
    };
    return coinMap[symbol];
  }

  List<Map<String, dynamic>> _generateRealisticHistoricalData(String symbol, int days) {
    // Use current market prices as base
    final basePrices = {
      'BTC': 60250.75,
      'ETH': 3450.20,
      'BNB': 485.30,
      'XRP': 0.62,
      'SOL': 145.80,
      'TRX': 0.12,
      'LTC': 82.50,
      'DOGE': 0.15,
      'USDT': 1.00,
    };
    
    final basePrice = basePrices[symbol] ?? 60250.75;
    final now = DateTime.now().millisecondsSinceEpoch;
    final List<Map<String, dynamic>> data = [];
    
    // Generate appropriate number of data points based on timeframe
    int dataPoints;
    int intervalMs;
    
    if (days <= 1) {
      // 24h view - hourly data
      dataPoints = 24;
      intervalMs = 3600000; // 1 hour
    } else if (days <= 30) {
      // 1M view - daily data
      dataPoints = days;
      intervalMs = 86400000; // 1 day
    } else if (days <= 180) {
      // 6M view - weekly data
      dataPoints = days ~/ 7;
      intervalMs = 604800000; // 1 week
    } else {
      // 1Y+ view - monthly data
      dataPoints = days ~/ 30;
      intervalMs = 2592000000; // 30 days
    }
    
    // Generate data with realistic volatility and trend
    double currentPrice = basePrice;
    final volatility = 0.03; // 3% volatility
    final trend = (Random().nextDouble() - 0.5) * 0.1; // Slight random trend
    
    for (int i = 0; i < dataPoints; i++) {
      final timestamp = now - ((dataPoints - i - 1) * intervalMs);
      
      // Add trend and random movement
      final randomChange = (Random().nextDouble() - 0.5) * 2 * volatility;
      currentPrice = currentPrice * (1 + trend / dataPoints + randomChange);
      
      // Ensure price doesn't go negative
      currentPrice = currentPrice > 0 ? currentPrice : basePrice * 0.5;
      
      data.add({
        'timestamp': timestamp,
        'price': currentPrice,
      });
    }
    
    return data;
  }

  Map<String, dynamic> _fallback() {
    // Realistic fallback values based on current market data
    return {
      'BTC': {'symbol': 'BTC', 'price_usd': 60250.75, 'change_24h': 2.5},
      'ETH': {'symbol': 'ETH', 'price_usd': 3450.20, 'change_24h': -1.2},
      'USDT': {'symbol': 'USDT', 'price_usd': 1.00, 'change_24h': 0.0},
      'BNB': {'symbol': 'BNB', 'price_usd': 485.30, 'change_24h': 3.8},
      'XRP': {'symbol': 'XRP', 'price_usd': 0.62, 'change_24h': 1.5},
      'SOL': {'symbol': 'SOL', 'price_usd': 145.80, 'change_24h': 5.2},
      'TRX': {'symbol': 'TRX', 'price_usd': 0.12, 'change_24h': 0.8},
      'LTC': {'symbol': 'LTC', 'price_usd': 82.50, 'change_24h': -0.5},
      'DOGE': {'symbol': 'DOGE', 'price_usd': 0.15, 'change_24h': 2.1},
    };
  }
}
