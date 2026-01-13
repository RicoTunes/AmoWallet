import 'dart:async';
import 'package:flutter/foundation.dart';
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
  final Set<String> _notifiedTransactions = {};
  final Set<String> _pendingTransactions = {}; // Track pending transactions

  /// Start monitoring for incoming transactions
  void startMonitoring({Duration interval = const Duration(seconds: 90)}) {
    if (_isMonitoring) {
      return;
    }

    _isMonitoring = true;
    debugPrint('🔍 Transaction monitoring started (polling every ${interval.inSeconds}s)');

    // Initial balance snapshot
    _captureBalances();

    // Poll for changes periodically
    _pollingTimer = Timer.periodic(interval, (_) {
      _checkForNewTransactions();
    });
  }

  /// Stop monitoring
  void stopMonitoring() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _isMonitoring = false;
    _lastBalances.clear();
    _notifiedTransactions.clear();
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

  /// Check for new transactions by comparing balances
  Future<void> _checkForNewTransactions() async {
    if (!_isMonitoring) return;

    try {
      // Get all transactions to check for pending and confirmed
      final transactions = await _transactionService.getAllTransactions();
      
      // Only track received transactions through pending/confirmed flow
      for (final tx in transactions) {
        if (tx.isReceived) {
          // Use txHash if available, otherwise use id
          final uniqueId = tx.txHash ?? tx.id;
          
          if (tx.isPending) {
            // Pending (unconfirmed) transaction
            final pendingKey = 'pending-$uniqueId';
            if (!_notifiedTransactions.contains(pendingKey)) {
              _pendingTransactions.add(uniqueId);
              _notifiedTransactions.add(pendingKey);
              debugPrint('✅ Tracking pending: $uniqueId (${tx.coin}: ${tx.amount})');
            }
          } else {
            // Confirmed transaction (confirmations > 0)
            final confirmedKey = 'confirmed-$uniqueId';
            if (_pendingTransactions.contains(uniqueId) && !_notifiedTransactions.contains(confirmedKey)) {
              _pendingTransactions.remove(uniqueId);
              _notifiedTransactions.add(confirmedKey);
              debugPrint('✅ Tracking confirmed: $uniqueId');
            }
          }
        }
      }
      
      // Cleanup old notifications to prevent memory leak
      if (_notifiedTransactions.length > 200) {
        final toRemove = _notifiedTransactions.length - 100;
        _notifiedTransactions.removeAll(_notifiedTransactions.take(toRemove));
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
    final txId = '$coin-$amount-${DateTime.now().millisecondsSinceEpoch}';
    
    if (_notifiedTransactions.contains(txId)) {
      return; // Already notified
    }

    _notifiedTransactions.add(txId);

    // Keep only last 100 transaction IDs to prevent memory leak
    if (_notifiedTransactions.length > 100) {
      _notifiedTransactions.remove(_notifiedTransactions.first);
    }

    debugPrint('💰 Incoming transaction detected: +$amount $coin');

    // Show notification
    await _notificationService.showNotification(
      title: 'Received $coin',
      message: 'You received $amount $coin',
      type: NotificationType.incoming,
      data: {
        'type': 'received',
        'coin': coin,
        'amount': amount,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );

    // Record the transaction
    try {
      await _transactionService.recordReceivedTransaction(
        coin: coin,
        amount: amount,
        toAddress: 'My Wallet', // Placeholder - actual address would come from wallet
        fromAddress: 'Unknown', // Unknown sender
      );
    } catch (e) {
      debugPrint('⚠️ Error recording received transaction: $e');
    }
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
