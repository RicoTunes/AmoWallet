import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

enum NotificationType {
  incoming,
  outgoing,
  confirmed,
  failed,
  success,
  warning,
  info,
}

/// Status of a transaction-linked notification.
enum TxStatus { pending, confirmed, failed }

class AppNotification {
  final String id;
  final String title;
  final String message;
  final NotificationType type;
  final DateTime timestamp;
  final bool isRead;
  final Map<String, dynamic>? data;
  // Transaction-specific fields
  final String? txHash;
  final String? coin;
  final String? amount;
  TxStatus txStatus;

  AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.timestamp,
    this.isRead = false,
    this.data,
    this.txHash,
    this.coin,
    this.amount,
    this.txStatus = TxStatus.pending,
  });

  AppNotification copyWith({
    bool? isRead,
    TxStatus? txStatus,
    String? title,
    String? message,
  }) {
    return AppNotification(
      id: id,
      title: title ?? this.title,
      message: message ?? this.message,
      type: type,
      timestamp: timestamp,
      isRead: isRead ?? this.isRead,
      data: data,
      txHash: txHash,
      coin: coin,
      amount: amount,
      txStatus: txStatus ?? this.txStatus,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'message': message,
        'type': type.name,
        'timestamp': timestamp.toIso8601String(),
        'isRead': isRead,
        'data': data,
        'txHash': txHash,
        'coin': coin,
        'amount': amount,
        'txStatus': txStatus.name,
      };

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: j['id'] as String,
        title: j['title'] as String,
        message: j['message'] as String,
        type: NotificationType.values.firstWhere(
          (e) => e.name == j['type'],
          orElse: () => NotificationType.info,
        ),
        timestamp: DateTime.parse(j['timestamp'] as String),
        isRead: j['isRead'] as bool? ?? false,
        data: j['data'] != null ? Map<String, dynamic>.from(j['data'] as Map) : null,
        txHash: j['txHash'] as String?,
        coin: j['coin'] as String?,
        amount: j['amount'] as String?,
        txStatus: TxStatus.values.firstWhere(
          (e) => e.name == (j['txStatus'] ?? 'pending'),
          orElse: () => TxStatus.pending,
        ),
      );
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static const String _prefsKey = 'app_notifications';
  static const int _maxNotifications = 100;

  final List<AppNotification> _notifications = [];
  final List<Function(List<AppNotification>)> _listeners = [];

  /// An optional callback the app can set so tapping a notification navigates
  /// to the transactions page. Set during app initialisation.
  Function()? onTapNavigateToTransactions;

  List<AppNotification> get notifications => List.unmodifiable(_notifications);
  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  // ─── Init ────────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    await _loadFromPrefs();

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
    onTapNavigateToTransactions?.call();
  }

  // ─── Listeners ───────────────────────────────────────────────────────────

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

  // ─── Persistence ─────────────────────────────────────────────────────────

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      final List<dynamic> list = json.decode(raw) as List<dynamic>;
      _notifications.clear();
      for (final item in list) {
        try {
          _notifications.add(AppNotification.fromJson(Map<String, dynamic>.from(item as Map)));
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> _saveToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _notifications.map((n) => n.toJson()).toList();
      await prefs.setString(_prefsKey, json.encode(list));
    } catch (_) {}
  }

  // ─── Core add ────────────────────────────────────────────────────────────

  /// Returns true if a notification with this [txHash] and same direction already exists.
  bool _hasTxNotification(String txHash) {
    return _notifications.any((n) => n.txHash == txHash);
  }

  Future<void> showNotification({
    required String title,
    required String message,
    required NotificationType type,
    Map<String, dynamic>? data,
    bool playSound = true,
    String? txHash,
    String? coin,
    String? amount,
    TxStatus txStatus = TxStatus.pending,
    /// If true and a notification with the same txHash already exists, skip.
    bool deduplicateByTxHash = false,
  }) async {
    // Deduplicate incoming transactions – notify only once per txHash
    if (deduplicateByTxHash && txHash != null && _hasTxNotification(txHash)) {
      return;
    }

    final now = DateTime.now();
    final id = '${now.millisecondsSinceEpoch}_${now.microsecond}';
    final notification = AppNotification(
      id: id,
      title: title,
      message: message,
      type: type,
      timestamp: now,
      data: data,
      txHash: txHash,
      coin: coin,
      amount: amount,
      txStatus: txStatus,
    );

    _notifications.insert(0, notification);

    // Keep max 100 notifications
    if (_notifications.length > _maxNotifications) {
      _notifications.removeLast();
    }

    _notifyListeners();
    await _saveToPrefs();

    // Show system notification (best-effort on web – won't crash)
    try {
      final notificationId = id.hashCode.abs() % 0x7FFFFFFF;
      await _showSystemNotification(
        id: notificationId,
        title: title,
        message: message,
        type: type,
      );
    } catch (_) {}
  }

  // ─── Status update (pending → confirmed / failed) ─────────────────────

  /// Update the status shown in the notification centre for a tracked tx.
  Future<void> updateTxStatus(String txHash, TxStatus newStatus) async {
    bool changed = false;
    for (int i = 0; i < _notifications.length; i++) {
      if (_notifications[i].txHash == txHash &&
          _notifications[i].txStatus != newStatus) {
        final n = _notifications[i];
        String newTitle = n.title;
        String newMessage = n.message;
        if (newStatus == TxStatus.confirmed) {
          final direction = n.type == NotificationType.incoming ? 'Received' : 'Sent';
          newTitle = '✓ $direction ${n.coin ?? ''} Confirmed';
          newMessage = '${n.amount ?? ''} ${n.coin ?? ''} — Transaction confirmed';
        } else if (newStatus == TxStatus.failed) {
          newTitle = '✗ Transaction Failed';
          newMessage = '${n.amount ?? ''} ${n.coin ?? ''} — Transaction failed';
        }
        _notifications[i] = n.copyWith(
          txStatus: newStatus,
          title: newTitle,
          message: newMessage,
          isRead: false, // mark unread again so badge shows
        );
        changed = true;
      }
    }
    if (changed) {
      _notifyListeners();
      await _saveToPrefs();
    }
  }

  // ─── Read management ─────────────────────────────────────────────────────

  void markAsRead(String notificationId) {
    final index = _notifications.indexWhere((n) => n.id == notificationId);
    if (index != -1) {
      _notifications[index] = _notifications[index].copyWith(isRead: true);
      _notifyListeners();
      _saveToPrefs();
    }
  }

  void markAllAsRead() {
    for (int i = 0; i < _notifications.length; i++) {
      _notifications[i] = _notifications[i].copyWith(isRead: true);
    }
    _notifyListeners();
    _saveToPrefs();
  }

  void clearNotification(String notificationId) {
    _notifications.removeWhere((n) => n.id == notificationId);
    _notifyListeners();
    _saveToPrefs();
  }

  void clearAllNotifications() {
    _notifications.clear();
    _notifyListeners();
    _saveToPrefs();
  }

  // ─── System notifications ─────────────────────────────────────────────

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
      playSound: false,
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
      case NotificationType.outgoing:
        return Colors.orange;
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
  }

  // ─── Convenience helpers ─────────────────────────────────────────────────

  Future<void> showIncomingTransaction({
    required String amount,
    required String currency,
    required String from,
    required String txHash,
  }) async {
    await showNotification(
      title: '↙ Received $currency',
      message: '+$amount $currency from ${from.length > 12 ? '${from.substring(0, 10)}…' : from}',
      type: NotificationType.incoming,
      txHash: txHash,
      coin: currency,
      amount: amount,
      txStatus: TxStatus.pending,
      deduplicateByTxHash: true,
      data: {'amount': amount, 'currency': currency, 'from': from, 'txHash': txHash},
    );
  }

  Future<void> showOutgoingTransaction({
    required String amount,
    required String currency,
    required String to,
    required String txHash,
  }) async {
    await showNotification(
      title: '↗ Sent $currency',
      message: '-$amount $currency to ${to.length > 12 ? '${to.substring(0, 10)}…' : to}',
      type: NotificationType.outgoing,
      txHash: txHash,
      coin: currency,
      amount: amount,
      txStatus: TxStatus.pending,
      deduplicateByTxHash: true,
      data: {'amount': amount, 'currency': currency, 'to': to, 'txHash': txHash},
    );
  }

  Future<void> showTransactionConfirmed({
    required String amount,
    required String currency,
    required String txHash,
  }) async {
    // Update existing notification if present; otherwise add a new one.
    if (_hasTxNotification(txHash)) {
      await updateTxStatus(txHash, TxStatus.confirmed);
      // Also fire a fresh "confirmed" notification so the badge increments.
      await showNotification(
        title: '✓ $currency Confirmed',
        message: '$amount $currency transaction confirmed',
        type: NotificationType.confirmed,
        coin: currency,
        amount: amount,
        txStatus: TxStatus.confirmed,
        data: {'amount': amount, 'currency': currency, 'txHash': txHash},
      );
    } else {
      await showNotification(
        title: '✓ $currency Confirmed',
        message: '$amount $currency transaction confirmed',
        type: NotificationType.confirmed,
        txHash: txHash,
        coin: currency,
        amount: amount,
        txStatus: TxStatus.confirmed,
        data: {'amount': amount, 'currency': currency, 'txHash': txHash},
      );
    }
  }

  Future<void> showTransactionFailed({
    required String amount,
    required String currency,
    required String reason,
    String? txHash,
  }) async {
    if (txHash != null && _hasTxNotification(txHash)) {
      await updateTxStatus(txHash, TxStatus.failed);
    }
    await showNotification(
      title: '✗ Transaction Failed',
      message: 'Failed to send $amount $currency: $reason',
      type: NotificationType.failed,
      txHash: txHash,
      coin: currency,
      amount: amount,
      txStatus: TxStatus.failed,
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
      title: '⇄ Swap Completed',
      message: 'Swapped $fromAmount $fromCurrency → $toAmount $toCurrency',
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
      title: '📈 Price Alert',
      message: '$currency is now at \$$price ($change%)',
      type: NotificationType.info,
      data: {'currency': currency, 'price': price, 'change': change},
    );
  }

  void dispose() {
    // Cleanup resources
  }
}
