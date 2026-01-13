import 'package:dio/dio.dart';
import 'dart:async';

/// Service to convert cryptocurrency amounts to USD values
class PriceConversionService {
  static final PriceConversionService _instance = PriceConversionService._internal();
  factory PriceConversionService() => _instance;
  PriceConversionService._internal();

  final Dio _dio = Dio();
  final Map<String, _PriceCache> _priceCache = {};
  static const Duration _cacheDuration = Duration(minutes: 5);

  final Map<String, String> _coinGeckoIds = {
    'BTC': 'bitcoin',
    'ETH': 'ethereum',
    'BNB': 'binancecoin',
    'USDT': 'tether',
    'MATIC': 'matic-network',
    'TRX': 'tron',
    'SOL': 'solana',
    'XRP': 'ripple',
    'DOGE': 'dogecoin',
    'LTC': 'litecoin',
  };

  /// Get USD price for a single coin
  Future<double> getUSDPrice(String symbol) async {
    try {
      // Check cache first
      if (_priceCache.containsKey(symbol)) {
        final cache = _priceCache[symbol]!;
        if (DateTime.now().difference(cache.timestamp) < _cacheDuration) {
          return cache.data;
        }
      }

      final coinId = _coinGeckoIds[symbol];
      if (coinId == null) {
        print('Unknown coin symbol: $symbol');
        return 0.0;
      }

      final response = await _dio.get(
        'https://api.coingecko.com/api/v3/simple/price',
        queryParameters: {
          'ids': coinId,
          'vs_currencies': 'usd',
        },
      ).timeout(const Duration(seconds: 5));

      final price = (response.data[coinId]['usd'] ?? 0.0).toDouble();
      
      // Cache the result
      _priceCache[symbol] = _PriceCache(data: price, timestamp: DateTime.now());
      
      return price;
    } catch (e) {
      print('Error fetching USD price for $symbol: $e');
      // Return cached price if available
      if (_priceCache.containsKey(symbol)) {
        return _priceCache[symbol]!.data;
      }
      return 0.0;
    }
  }

  /// Get USD prices for multiple coins at once
  Future<Map<String, double>> getUSDPrices(List<String> symbols) async {
    final result = <String, double>{};
    
    try {
      // Get unique coin IDs
      final coinIds = <String>[];
      final symbolMap = <String, String>{};
      
      for (final symbol in symbols) {
        final coinId = _coinGeckoIds[symbol];
        if (coinId != null && !coinIds.contains(coinId)) {
          coinIds.add(coinId);
          symbolMap[coinId] = symbol;
        }
      }

      if (coinIds.isEmpty) return result;

      final response = await _dio.get(
        'https://api.coingecko.com/api/v3/simple/price',
        queryParameters: {
          'ids': coinIds.join(','),
          'vs_currencies': 'usd',
        },
      ).timeout(const Duration(seconds: 5));

      final timestamp = DateTime.now();
      for (final entry in response.data.entries) {
        final symbol = symbolMap[entry.key];
        if (symbol != null) {
          final price = (entry.value['usd'] ?? 0.0).toDouble();
          result[symbol] = price;
          _priceCache[symbol] = _PriceCache(data: price, timestamp: timestamp);
        }
      }
    } catch (e) {
      print('Error fetching batch USD prices: $e');
      // Return cached prices if available
      for (final symbol in symbols) {
        if (_priceCache.containsKey(symbol)) {
          result[symbol] = _priceCache[symbol]!.data;
        }
      }
    }

    return result;
  }

  /// Convert an amount to USD
  Future<double> convertToUSD(String symbol, double amount) async {
    try {
      final usdPrice = await getUSDPrice(symbol);
      return amount * usdPrice;
    } catch (e) {
      print('Error converting $symbol to USD: $e');
      return 0.0;
    }
  }

  /// Format USD amount with proper currency symbol
  String formatUSD(double amount) {
    if (amount == 0) return '\$0.00';
    if (amount < 0.01) return '\$${amount.toStringAsFixed(8)}';
    return '\$${amount.toStringAsFixed(2)}';
  }

  /// Clear cache
  void clearCache() {
    _priceCache.clear();
  }

  /// Clear specific coin from cache
  void clearCoinCache(String symbol) {
    _priceCache.remove(symbol);
  }
}

class _PriceCache {
  final double data;
  final DateTime timestamp;

  _PriceCache({required this.data, required this.timestamp});
}
