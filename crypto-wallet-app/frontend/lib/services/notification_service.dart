import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';

enum NotificationType {
  incoming,
  confirmed,
  failed,
  success,
  warning,
  info,
}

class AppNotification {
  final String id;
  final String title;
  final String message;
  final NotificationType type;
  final DateTime timestamp;
  final bool isRead;
  final Map<String, dynamic>? data;

  AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.timestamp,
    this.isRead = false,
    this.data,
  });

  AppNotification copyWith({bool? isRead}) {
    return AppNotification(
      id: id,
      title: title,
      message: message,
      type: type,
      timestamp: timestamp,
      isRead: isRead ?? this.isRead,
      data: data,
    );
  }
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  
  final List<AppNotification> _notifications = [];
  final List<Function(List<AppNotification>)> _listeners = [];

  List<AppNotification> get notifications => List.unmodifiable(_notifications);
  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  Future<void> initialize() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings();

    const LinuxInitializationSettings initializationSettingsLinux =
        LinuxInitializationSettings(defaultActionName: 'Open notification');

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
      linux: initializationSettingsLinux,
    );

    await _flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );
  }

  void _onNotificationTapped(NotificationResponse response) {
    // Handle notification tap
    print('Notification tapped: ${response.payload}');
  }

  void addListener(Function(List<AppNotification>) listener) {
    _listeners.add(listener);
  }

  void removeListener(Function(List<AppNotification>) listener) {
    _listeners.remove(listener);
  }

  void _notifyListeners() {
    for (var listener in _listeners) {
      listener(_notifications);
    }
  }

  Future<void> showNotification({
    required String title,
    required String message,
    required NotificationType type,
    Map<String, dynamic>? data,
    bool playSound = true,
  }) async {
    // Add to internal list
    final now = DateTime.now();
    final id = '${now.millisecondsSinceEpoch}_${now.microsecond}';
    final notification = AppNotification(
      id: id,
      title: title,
      message: message,
      type: type,
      timestamp: now,
      data: data,
    );

    _notifications.insert(0, notification);
    
    // Keep only last 50 notifications
    if (_notifications.length > 50) {
      _notifications.removeLast();
    }

    _notifyListeners();

    // Play sound
    if (playSound) {
      await _playNotificationSound(type);
    }

    // Show system notification
    // Use hash of the ID to ensure unique int value
    final notificationId = id.hashCode.abs() % 0x7FFFFFFF;
    await _showSystemNotification(
      id: notificationId,
      title: title,
      message: message,
      type: type,
    );
  }

  Future<void> _showSystemNotification({
    required int id,
    required String title,
    required String message,
    required NotificationType type,
  }) async {
    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'crypto_wallet_channel',
      'Crypto Wallet Notifications',
      channelDescription: 'Notifications for crypto wallet transactions and updates',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      color: _getNotificationColor(type),
      enableVibration: true,
      playSound: false, // We handle sound separately
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: false,
    );

    final NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _flutterLocalNotificationsPlugin.show(
      id,
      title,
      message,
      platformDetails,
    );
  }

  Color _getNotificationColor(NotificationType type) {
    switch (type) {
      case NotificationType.incoming:
        return Colors.blue;
      case NotificationType.confirmed:
        return Colors.green;
      case NotificationType.failed:
        return Colors.red;
      case NotificationType.success:
        return Colors.green;
      case NotificationType.warning:
        return Colors.orange;
      case NotificationType.info:
        return Colors.grey;
    }
  }

  Future<void> _playNotificationSound(NotificationType type) async {
    // Sound playback disabled for stability
    // The system notification will use device default sound
  }

  void markAsRead(String notificationId) {
    final index = _notifications.indexWhere((n) => n.id == notificationId);
    if (index != -1) {
      _notifications[index] = _notifications[index].copyWith(isRead: true);
      _notifyListeners();
    }
  }

  void markAllAsRead() {
    for (int i = 0; i < _notifications.length; i++) {
      _notifications[i] = _notifications[i].copyWith(isRead: true);
    }
    _notifyListeners();
  }

  void clearNotification(String notificationId) {
    _notifications.removeWhere((n) => n.id == notificationId);
    _notifyListeners();
  }

  void clearAllNotifications() {
    _notifications.clear();
    _notifyListeners();
  }

  // Helper methods for common notification types
  Future<void> showIncomingTransaction({
    required String amount,
    required String currency,
    required String from,
  }) async {
    await showNotification(
      title: 'Incoming Transaction',
      message: 'Received $amount $currency from ${from.substring(0, 10)}...',
      type: NotificationType.incoming,
      data: {'amount': amount, 'currency': currency, 'from': from},
    );
  }

  Future<void> showTransactionConfirmed({
    required String amount,
    required String currency,
    required String txHash,
  }) async {
    await showNotification(
      title: 'Transaction Confirmed',
      message: '$amount $currency transaction confirmed',
      type: NotificationType.confirmed,
      data: {'amount': amount, 'currency': currency, 'txHash': txHash},
    );
  }

  Future<void> showTransactionFailed({
    required String amount,
    required String currency,
    required String reason,
  }) async {
    await showNotification(
      title: 'Transaction Failed',
      message: 'Failed to send $amount $currency: $reason',
      type: NotificationType.failed,
      data: {'amount': amount, 'currency': currency, 'reason': reason},
    );
  }

  Future<void> showSwapCompleted({
    required String fromAmount,
    required String fromCurrency,
    required String toAmount,
    required String toCurrency,
  }) async {
    await showNotification(
      title: 'Swap Completed',
      message: 'Swapped $fromAmount $fromCurrency to $toAmount $toCurrency',
      type: NotificationType.success,
      data: {
        'fromAmount': fromAmount,
        'fromCurrency': fromCurrency,
        'toAmount': toAmount,
        'toCurrency': toCurrency,
      },
    );
  }

  Future<void> showPriceAlert({
    required String currency,
    required String price,
    required String change,
  }) async {
    await showNotification(
      title: 'Price Alert',
      message: '$currency is now at \$$price ($change%)',
      type: NotificationType.info,
      data: {'currency': currency, 'price': price, 'change': change},
    );
  }

  void dispose() {
    // Cleanup resources
  }
}
