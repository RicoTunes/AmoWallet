import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'wallet_service.dart';
import 'notification_service.dart';
import 'transaction_service.dart';

class TransactionMonitorService {
  static final TransactionMonitorService _instance = TransactionMonitorService._internal();
  factory TransactionMonitorService() => _instance;
  TransactionMonitorService._internal();

  final WalletService _walletService = WalletService();
  final NotificationService _notificationService = NotificationService();
  final TransactionService _transactionService = TransactionService();

  Timer? _pollingTimer;
  bool _isMonitoring = false;
  final Map<String, double> _lastBalances = {};
  Set<String> _notifiedTransactions = {};
  final Set<String> _pendingTransactions = {}; // Track pending transactions
  DateTime? _monitorStartTime; // When monitoring first started
  
  static const String _notifiedTxKey = 'transaction_monitor_notified_txs';
  static const String _monitorStartTimeKey = 'transaction_monitor_start_time';

  /// Start monitoring for incoming transactions
  Future<void> startMonitoring({Duration interval = const Duration(seconds: 90)}) async {
    if (_isMonitoring) {
      return;
    }

    _isMonitoring = true;
    debugPrint('🔍 Transaction monitoring started (polling every ${interval.inSeconds}s)');

    // Load persisted data
    await _loadPersistedData();

    // Initial balance snapshot
    await _captureBalances();

    // Poll for changes periodically
    _pollingTimer = Timer.periodic(interval, (_) {
      _checkForNewTransactions();
    });
  }

  /// Load persisted notified transactions
  Future<void> _loadPersistedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Load monitor start time
      final startTimeStr = prefs.getString(_monitorStartTimeKey);
      if (startTimeStr != null) {
        _monitorStartTime = DateTime.parse(startTimeStr);
        debugPrint('📅 Monitor start time: $_monitorStartTime');
      } else {
        // First run - set start time to now
        _monitorStartTime = DateTime.now();
        await prefs.setString(_monitorStartTimeKey, _monitorStartTime!.toIso8601String());
        debugPrint('📅 Set monitor start time to: $_monitorStartTime');
      }
      
      // Load notified transactions
      final notifiedList = prefs.getStringList(_notifiedTxKey);
      if (notifiedList != null) {
        _notifiedTransactions = notifiedList.toSet();
        debugPrint('📋 Loaded ${_notifiedTransactions.length} notified transactions');
      }
    } catch (e) {
      debugPrint('⚠️ Error loading persisted data: $e');
      _monitorStartTime = DateTime.now();
    }
  }

  /// Save notified transactions
  Future<void> _saveNotifiedTransactions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Keep only the last 500 to prevent unbounded growth
      final list = _notifiedTransactions.toList();
      if (list.length > 500) {
        _notifiedTransactions = list.sublist(list.length - 500).toSet();
      }
      await prefs.setStringList(_notifiedTxKey, _notifiedTransactions.toList());
    } catch (e) {
      debugPrint('⚠️ Error saving notified transactions: $e');
    }
  }

  /// Stop monitoring
  void stopMonitoring() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _isMonitoring = false;
    _lastBalances.clear();
    debugPrint('🛑 Transaction monitoring stopped');
  }

  /// Capture current balances
  Future<void> _captureBalances() async {
    try {
      final balances = await _walletService.getBalances();
      for (var entry in balances.entries) {
        _lastBalances[entry.key] = entry.value;
      }
      debugPrint('📊 Captured initial balances: $_lastBalances');
    } catch (e) {
      debugPrint('⚠️ Error capturing balances: $e');
    }
  }

  /// Check for new transactions by comparing current blockchain balances
  /// to the last known balances. Any increase = incoming transaction.
  Future<void> _checkForNewTransactions() async {
    if (!_isMonitoring) return;

    try {
      // Fetch live balances from blockchain / cache
      final currentBalances = await _walletService.getBalances();

      for (final entry in currentBalances.entries) {
        final coin = entry.key;
        final currentBalance = entry.value;
        final lastBalance = _lastBalances[coin];

        if (lastBalance == null) {
          // First time we see this coin — just snapshot it
          _lastBalances[coin] = currentBalance;
          continue;
        }

        final diff = currentBalance - lastBalance;
        // Only fire if balance grew by a meaningful amount (> dust)
        if (diff > 0.000001) {
          final notifKey = '${coin}_incoming_${diff.toStringAsFixed(8)}_${DateTime.now().millisecondsSinceEpoch ~/ 60000}';
          if (!_notifiedTransactions.contains(notifKey)) {
            _notifiedTransactions.add(notifKey);
            await _saveNotifiedTransactions();
            debugPrint('💰 Incoming $coin detected: +$diff (was $lastBalance → $currentBalance)');
            await _notifyIncomingTransaction(coin, diff);
          }
          // Update last balance
          _lastBalances[coin] = currentBalance;
        } else if (diff < 0) {
          // Balance dropped (sent or fee) — just update snapshot
          _lastBalances[coin] = currentBalance;
        }
      }

      // Cleanup old notification keys
      if (_notifiedTransactions.length > 500) {
        final list = _notifiedTransactions.toList();
        _notifiedTransactions = list.sublist(list.length - 300).toSet();
      }
    } catch (e) {
      debugPrint('⚠️ Error checking transactions: $e');
    }
  }
  
  /// Notify user of pending (unconfirmed) transaction
  Future<void> _notifyPendingTransaction(String coin, double amount) async {
    debugPrint('⏳ Pending transaction detected: +$amount $coin');

    try {
      // Don't show notification here — let TransactionMonitorService handle it
      // instead of showing through pending/confirmed flow
      debugPrint('📌 Pending tx already being tracked by ConfirmationTrackerService');
    } catch (e) {
      debugPrint('⚠️ Error notifying pending transaction: $e');
    }
  }
  
  /// Notify user when pending transaction is confirmed
  Future<void> _notifyConfirmedTransaction(String coin, double amount) async {
    debugPrint('✅ Transaction confirmed: +$amount $coin');

    try {
      // ConfirmationTrackerService will handle confirmation notifications
      debugPrint('📌 Confirmed tx notification handled by ConfirmationTrackerService');
    } catch (e) {
      debugPrint('⚠️ Error notifying confirmed transaction: $e');
    }
  }

  /// Notify user of incoming transaction
  Future<void> _notifyIncomingTransaction(String coin, double amount) async {
    // Create unique ID for this transaction to avoid duplicates
    final txId = '$coin-${amount.toStringAsFixed(8)}-${DateTime.now().millisecondsSinceEpoch ~/ 60000}';
    
    if (_notifiedTransactions.contains(txId)) {
      return; // Already notified
    }

    _notifiedTransactions.add(txId);

    // Keep only last 100 transaction IDs to prevent memory leak
    if (_notifiedTransactions.length > 100) {
      _notifiedTransactions.remove(_notifiedTransactions.first);
    }

    debugPrint('💰 Incoming transaction detected: +$amount $coin');

    // Get wallet address for this coin so the detail page shows correct address
    String toAddress = 'My Wallet';
    try {
      final addresses = await _walletService.getStoredAddresses(coin);
      if (addresses.isNotEmpty) toAddress = addresses.first;
    } catch (_) {}

    // Record the transaction first – use txId as the hash so tapping the notification
    // can look up this exact record.
    String finalTxHash = txId;
    try {
      final recorded = await _transactionService.recordReceivedTransaction(
        coin: coin,
        amount: amount,
        toAddress: toAddress,
        fromAddress: 'Unknown',
        txHash: txId,
      );
      finalTxHash = recorded.txHash ?? recorded.id;
    } catch (e) {
      debugPrint('⚠️ Error recording received transaction: $e');
    }

    // Show notification with correct incoming type and txHash for detail navigation
    await _notificationService.showIncomingTransaction(
      amount: amount.toStringAsFixed(8),
      currency: coin,
      from: 'Unknown',
      txHash: finalTxHash,
    );
  }

  /// Manually check for new transactions (called on app resume or user action)
  Future<void> checkNow() async {
    if (!_isMonitoring) {
      await _captureBalances();
      return;
    }
    await _checkForNewTransactions();
  }

  /// Notify for transaction confirmation
  Future<void> notifyTransactionConfirmed({
    required String coin,
    required String txHash,
    required double amount,
  }) async {
    await _notificationService.showNotification(
      title: 'Transaction Confirmed',
      message: '$amount $coin transaction confirmed on blockchain',
      type: NotificationType.confirmed,
      data: {
        'type': 'confirmed',
        'coin': coin,
        'amount': amount,
        'txHash': txHash,
      },
    );
  }

  /// Get monitoring status
  bool get isMonitoring => _isMonitoring;
}
