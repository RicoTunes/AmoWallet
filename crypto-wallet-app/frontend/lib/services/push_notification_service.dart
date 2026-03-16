import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_service.dart';

/// Price Alert Model
class PriceAlert {
  final String id;
  final String coinSymbol;
  final double targetPrice;
  final bool isAbove; // true = alert when price goes ABOVE target
  final bool isEnabled;
  final DateTime createdAt;

  PriceAlert({
    required this.id,
    required this.coinSymbol,
    required this.targetPrice,
    required this.isAbove,
    this.isEnabled = true,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'coinSymbol': coinSymbol,
    'targetPrice': targetPrice,
    'isAbove': isAbove,
    'isEnabled': isEnabled,
    'createdAt': createdAt.toIso8601String(),
  };

  factory PriceAlert.fromJson(Map<String, dynamic> json) => PriceAlert(
    id: json['id'],
    coinSymbol: json['coinSymbol'],
    targetPrice: json['targetPrice'],
    isAbove: json['isAbove'],
    isEnabled: json['isEnabled'] ?? true,
    createdAt: DateTime.parse(json['createdAt']),
  );
}

/// Enhanced Push Notification Service
class PushNotificationService {
  static final PushNotificationService _instance = PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  final NotificationService _notificationService = NotificationService();
  final Dio _dio = Dio();
  
  Timer? _priceCheckTimer;
  Timer? _transactionCheckTimer;
  
  final List<PriceAlert> _priceAlerts = [];
  final Map<String, double> _lastKnownPrices = {};
  final Set<String> _monitoredAddresses = {};
  
  bool _isInitialized = false;
  bool _priceAlertsEnabled = true;
  bool _transactionAlertsEnabled = true;
  double _significantPriceChange = 5.0; // Notify if price changes by 5%

  // Coin ID mapping for CoinGecko
  final Map<String, String> _coinIds = {
    'BTC': 'bitcoin',
    'ETH': 'ethereum',
    'BNB': 'binancecoin',
    'SOL': 'solana',
    'XRP': 'ripple',
    'TRX': 'tron',
    'LTC': 'litecoin',
    'DOGE': 'dogecoin',
    'USDT': 'tether',
  };

  List<PriceAlert> get priceAlerts => List.unmodifiable(_priceAlerts);
  bool get priceAlertsEnabled => _priceAlertsEnabled;
  bool get transactionAlertsEnabled => _transactionAlertsEnabled;

  /// Initialize the service
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    await _notificationService.initialize();
    await _loadSettings();
    await _loadPriceAlerts();
    
    // Start monitoring
    _startPriceMonitoring();
    
    _isInitialized = true;
  }

  /// Load settings from storage
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _priceAlertsEnabled = prefs.getBool('push_price_alerts') ?? true;
    _transactionAlertsEnabled = prefs.getBool('push_tx_alerts') ?? true;
    _significantPriceChange = prefs.getDouble('significant_price_change') ?? 5.0;
  }

  /// Save settings
  Future<void> saveSettings({
    bool? priceAlertsEnabled,
    bool? transactionAlertsEnabled,
    double? significantPriceChange,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    
    if (priceAlertsEnabled != null) {
      _priceAlertsEnabled = priceAlertsEnabled;
      await prefs.setBool('push_price_alerts', priceAlertsEnabled);
    }
    
    if (transactionAlertsEnabled != null) {
      _transactionAlertsEnabled = transactionAlertsEnabled;
      await prefs.setBool('push_tx_alerts', transactionAlertsEnabled);
    }
    
    if (significantPriceChange != null) {
      _significantPriceChange = significantPriceChange;
      await prefs.setDouble('significant_price_change', significantPriceChange);
    }
  }

  /// Load price alerts from storage
  Future<void> _loadPriceAlerts() async {
    final prefs = await SharedPreferences.getInstance();
    final alertsJson = prefs.getStringList('price_alerts') ?? [];
    
    _priceAlerts.clear();
    for (final json in alertsJson) {
      try {
        final Map<String, dynamic> data = {};
        // Simple parsing
        final parts = json.split('|');
        if (parts.length >= 5) {
          data['id'] = parts[0];
          data['coinSymbol'] = parts[1];
          data['targetPrice'] = double.parse(parts[2]);
          data['isAbove'] = parts[3] == 'true';
          data['isEnabled'] = parts[4] == 'true';
          data['createdAt'] = parts.length > 5 ? parts[5] : DateTime.now().toIso8601String();
          _priceAlerts.add(PriceAlert.fromJson(data));
        }
      } catch (e) {
        // Skip invalid entries
      }
    }
  }

  /// Save price alerts to storage
  Future<void> _savePriceAlerts() async {
    final prefs = await SharedPreferences.getInstance();
    final alertsJson = _priceAlerts.map((a) => 
      '${a.id}|${a.coinSymbol}|${a.targetPrice}|${a.isAbove}|${a.isEnabled}|${a.createdAt.toIso8601String()}'
    ).toList();
    await prefs.setStringList('price_alerts', alertsJson);
  }

  /// Add a price alert
  Future<void> addPriceAlert({
    required String coinSymbol,
    required double targetPrice,
    required bool isAbove,
  }) async {
    final alert = PriceAlert(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      coinSymbol: coinSymbol,
      targetPrice: targetPrice,
      isAbove: isAbove,
    );
    
    _priceAlerts.add(alert);
    await _savePriceAlerts();
    
    await _notificationService.showNotification(
      title: 'Price Alert Created',
      message: 'Alert: ${coinSymbol.split('-').first} ${isAbove ? "above" : "below"} \$${targetPrice.toStringAsFixed(2)}',
      type: NotificationType.info,
    );
  }

  /// Remove a price alert
  Future<void> removePriceAlert(String alertId) async {
    _priceAlerts.removeWhere((a) => a.id == alertId);
    await _savePriceAlerts();
  }

  /// Toggle a price alert
  Future<void> togglePriceAlert(String alertId, bool enabled) async {
    final index = _priceAlerts.indexWhere((a) => a.id == alertId);
    if (index != -1) {
      final alert = _priceAlerts[index];
      _priceAlerts[index] = PriceAlert(
        id: alert.id,
        coinSymbol: alert.coinSymbol,
        targetPrice: alert.targetPrice,
        isAbove: alert.isAbove,
        isEnabled: enabled,
        createdAt: alert.createdAt,
      );
      await _savePriceAlerts();
    }
  }

  /// Start price monitoring
  void _startPriceMonitoring() {
    _priceCheckTimer?.cancel();
    _priceCheckTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_priceAlertsEnabled) {
        _checkPrices();
      }
    });
    
    // Initial check
    if (_priceAlertsEnabled) {
      _checkPrices();
    }
  }

  /// Check prices and trigger alerts
  Future<void> _checkPrices() async {
    try {
      // Get unique coins to check
      final coinsToCheck = <String>{};
      for (final alert in _priceAlerts.where((a) => a.isEnabled)) {
        coinsToCheck.add(alert.coinSymbol.split('-').first);
      }
      
      // Also check main coins for significant change alerts
      coinsToCheck.addAll(['BTC', 'ETH', 'BNB', 'SOL']);
      
      if (coinsToCheck.isEmpty) return;
      
      // Build CoinGecko IDs
      final ids = coinsToCheck
          .map((c) => _coinIds[c] ?? c.toLowerCase())
          .join(',');
      
      final response = await _dio.get(
        'https://api.coingecko.com/api/v3/simple/price',
        queryParameters: {
          'ids': ids,
          'vs_currencies': 'usd',
          'include_24hr_change': 'true',
        },
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        
        for (final coin in coinsToCheck) {
          final coinId = _coinIds[coin] ?? coin.toLowerCase();
          if (data.containsKey(coinId)) {
            final price = (data[coinId]['usd'] as num).toDouble();
            final change24h = (data[coinId]['usd_24h_change'] as num?)?.toDouble() ?? 0.0;
            
            // Check custom price alerts
            _checkPriceAlerts(coin, price);
            
            // Check for significant price changes
            _checkSignificantChange(coin, price, change24h);
            
            _lastKnownPrices[coin] = price;
          }
        }
      }
    } catch (e) {
      // Silently fail - will retry next interval
    }
  }

  /// Check if any price alerts should trigger
  void _checkPriceAlerts(String coin, double currentPrice) {
    for (final alert in _priceAlerts.where((a) => a.isEnabled && a.coinSymbol.startsWith(coin))) {
      bool shouldTrigger = false;
      
      if (alert.isAbove && currentPrice >= alert.targetPrice) {
        shouldTrigger = true;
      } else if (!alert.isAbove && currentPrice <= alert.targetPrice) {
        shouldTrigger = true;
      }
      
      if (shouldTrigger) {
        _notificationService.showNotification(
          title: '🚨 Price Alert: ${coin}',
          message: '${coin} is now ${alert.isAbove ? "above" : "below"} \$${alert.targetPrice.toStringAsFixed(2)} (Current: \$${currentPrice.toStringAsFixed(2)})',
          type: NotificationType.warning,
          data: {
            'type': 'price_alert',
            'coin': coin,
            'price': currentPrice,
            'target': alert.targetPrice,
          },
        );
        
        // Disable alert after triggering (one-time alert)
        togglePriceAlert(alert.id, false);
      }
    }
  }

  /// Check for significant price changes
  void _checkSignificantChange(String coin, double currentPrice, double change24h) {
    if (change24h.abs() >= _significantPriceChange) {
      final lastNotified = _lastKnownPrices[coin];
      
      // Only notify once per price level
      if (lastNotified == null || (currentPrice - lastNotified).abs() / lastNotified * 100 >= _significantPriceChange) {
        final isUp = change24h > 0;
        _notificationService.showNotification(
          title: '${isUp ? "📈" : "📉"} $coin ${isUp ? "Up" : "Down"} ${change24h.abs().toStringAsFixed(1)}%',
          message: '$coin is now \$${currentPrice.toStringAsFixed(2)} (${isUp ? "+" : ""}${change24h.toStringAsFixed(1)}% in 24h)',
          type: NotificationType.info,
          data: {
            'type': 'price_change',
            'coin': coin,
            'price': currentPrice,
            'change': change24h,
          },
        );
      }
    }
  }

  /// Notify about incoming transaction
  Future<void> notifyIncomingTransaction({
    required String coin,
    required double amount,
    required String from,
    required String txHash,
  }) async {
    if (!_transactionAlertsEnabled) return;
    
    await _notificationService.showNotification(
      title: '💰 Incoming $coin',
      message: 'Received ${amount.toStringAsFixed(8)} $coin from ${_shortenAddress(from)}',
      type: NotificationType.incoming,
      data: {
        'type': 'incoming_tx',
        'coin': coin,
        'amount': amount,
        'from': from,
        'txHash': txHash,
      },
    );
  }

  /// Notify about transaction confirmation
  Future<void> notifyTransactionConfirmed({
    required String coin,
    required double amount,
    required String txHash,
    required int confirmations,
  }) async {
    if (!_transactionAlertsEnabled) return;
    
    await _notificationService.showNotification(
      title: '✅ Transaction Confirmed',
      message: '${amount.toStringAsFixed(8)} $coin confirmed ($confirmations confirmations)',
      type: NotificationType.confirmed,
      data: {
        'type': 'tx_confirmed',
        'coin': coin,
        'amount': amount,
        'txHash': txHash,
        'confirmations': confirmations,
      },
    );
  }

  /// Notify about sent transaction
  Future<void> notifyTransactionSent({
    required String coin,
    required double amount,
    required String to,
    required String txHash,
  }) async {
    if (!_transactionAlertsEnabled) return;
    
    await _notificationService.showNotification(
      title: '📤 $coin Sent',
      message: 'Sent ${amount.toStringAsFixed(8)} $coin to ${_shortenAddress(to)}',
      type: NotificationType.success,
      data: {
        'type': 'sent_tx',
        'coin': coin,
        'amount': amount,
        'to': to,
        'txHash': txHash,
      },
    );
  }

  /// Notify about failed transaction
  Future<void> notifyTransactionFailed({
    required String coin,
    required double amount,
    required String reason,
  }) async {
    if (!_transactionAlertsEnabled) return;
    
    await _notificationService.showNotification(
      title: '❌ Transaction Failed',
      message: 'Failed to send ${amount.toStringAsFixed(8)} $coin: $reason',
      type: NotificationType.failed,
      data: {
        'type': 'tx_failed',
        'coin': coin,
        'amount': amount,
        'reason': reason,
      },
    );
  }

  /// Notify about swap completion
  Future<void> notifySwapCompleted({
    required String fromCoin,
    required double fromAmount,
    required String toCoin,
    required double toAmount,
  }) async {
    if (!_transactionAlertsEnabled) return;
    
    await _notificationService.showNotification(
      title: '🔄 Swap Completed',
      message: 'Swapped ${fromAmount.toStringAsFixed(6)} $fromCoin → ${toAmount.toStringAsFixed(6)} $toCoin',
      type: NotificationType.success,
      data: {
        'type': 'swap_completed',
        'fromCoin': fromCoin,
        'fromAmount': fromAmount,
        'toCoin': toCoin,
        'toAmount': toAmount,
      },
    );
  }

  String _shortenAddress(String address) {
    if (address.length > 16) {
      return '${address.substring(0, 8)}...${address.substring(address.length - 6)}';
    }
    return address;
  }

  /// Get current price for a coin
  Future<double?> getCurrentPrice(String coin) async {
    try {
      final coinId = _coinIds[coin.split('-').first] ?? coin.toLowerCase();
      final response = await _dio.get(
        'https://api.coingecko.com/api/v3/simple/price',
        queryParameters: {
          'ids': coinId,
          'vs_currencies': 'usd',
        },
      );
      
      if (response.statusCode == 200) {
        return (response.data[coinId]['usd'] as num).toDouble();
      }
    } catch (e) {
      // Return null on error
    }
    return null;
  }

  /// Dispose resources
  void dispose() {
    _priceCheckTimer?.cancel();
    _transactionCheckTimer?.cancel();
  }
}
