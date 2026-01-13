import 'dart:async';
import 'package:flutter/foundation.dart';
import 'swap_service.dart';
import 'price_conversion_service.dart';
import 'wallet_service.dart';

/// Service to preload data for faster page loads
class PreloadService {
  static final PreloadService _instance = PreloadService._internal();
  factory PreloadService() => _instance;
  PreloadService._internal();

  final SwapService _swapService = SwapService();
  final PriceConversionService _priceService = PriceConversionService();
  final WalletService _walletService = WalletService();

  // Cached data
  Map<String, double>? _cachedPrices;
  List<SwapProvider>? _cachedProviders;
  Map<String, double>? _cachedBalances;
  Map<String, double>? _cachedExchangeRates;
  DateTime? _lastPreloadTime;
  bool _isPreloading = false;
  
  // Preload status
  bool get isPreloaded => _lastPreloadTime != null && 
      DateTime.now().difference(_lastPreloadTime!).inMinutes < 5;
  
  Map<String, double>? get cachedPrices => _cachedPrices;
  List<SwapProvider>? get cachedProviders => _cachedProviders;
  Map<String, double>? get cachedBalances => _cachedBalances;
  Map<String, double>? get cachedExchangeRates => _cachedExchangeRates;

  /// Preload all swap-related data in the background
  /// Call this when dashboard loads
  Future<void> preloadSwapData() async {
    if (_isPreloading) return;
    _isPreloading = true;
    
    try {
      print('🔄 Preloading swap data in background...');
      
      // Run all preloads in parallel for speed
      await Future.wait([
        _preloadPrices(),
        _preloadProviders(),
        _preloadBalances(),
        _preloadExchangeRates(),
      ], eagerError: false);
      
      _lastPreloadTime = DateTime.now();
      print('✅ Swap data preloaded successfully');
    } catch (e) {
      print('⚠️ Preload partially failed: $e');
    } finally {
      _isPreloading = false;
    }
  }

  Future<void> _preloadPrices() async {
    try {
      final prices = await _priceService.getUSDPrices([
        'BTC', 'ETH', 'BNB', 'USDT', 'USDC', 'MATIC', 'TRX', 'SOL', 'XRP', 'DOGE', 'LTC'
      ]).timeout(const Duration(seconds: 5));
      _cachedPrices = prices;
      print('  ✅ Prices preloaded');
    } catch (e) {
      print('  ⚠️ Price preload failed: $e');
    }
  }

  Future<void> _preloadProviders() async {
    try {
      final providers = await _swapService.getProviders()
          .timeout(const Duration(seconds: 5));
      _cachedProviders = providers;
      print('  ✅ Providers preloaded: ${providers.length}');
    } catch (e) {
      print('  ⚠️ Provider preload failed: $e');
    }
  }

  Future<void> _preloadBalances() async {
    try {
      final balances = await _walletService.getBalances()
          .timeout(const Duration(seconds: 5));
      _cachedBalances = balances;
      print('  ✅ Balances preloaded');
    } catch (e) {
      print('  ⚠️ Balance preload failed: $e');
    }
  }

  Future<void> _preloadExchangeRates() async {
    try {
      final rates = await _swapService.getExchangeRates()
          .timeout(const Duration(seconds: 5));
      _cachedExchangeRates = rates;
      print('  ✅ Exchange rates preloaded');
    } catch (e) {
      print('  ⚠️ Exchange rates preload failed: $e');
    }
  }

  /// Clear cached data
  void clearCache() {
    _cachedPrices = null;
    _cachedProviders = null;
    _cachedBalances = null;
    _cachedExchangeRates = null;
    _lastPreloadTime = null;
  }
}
