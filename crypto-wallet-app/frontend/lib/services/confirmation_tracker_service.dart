import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logger/logger.dart';
import 'dart:convert';
import 'blockchain_service.dart';
import 'notification_service.dart';

/// Service for tracking transaction confirmations on various blockchains
/// Monitors pending transactions and notifies users at confirmation milestones
class ConfirmationTrackerService {
  static final ConfirmationTrackerService _instance = ConfirmationTrackerService._internal();
  factory ConfirmationTrackerService() => _instance;
  ConfirmationTrackerService._internal();

  final Logger _logger = Logger();
  final BlockchainService _blockchainService = BlockchainService();
  final NotificationService _notificationService = NotificationService();

  Timer? _trackingTimer;
  bool _isTracking = false;
  
  // Confirmation thresholds for notifications
  static const int THRESHOLD_LOW = 1;  // 1 confirmation
  static const int THRESHOLD_MEDIUM = 6;  // 6 confirmations (standard for most)
  static const int THRESHOLD_HIGH = 12;  // 12 confirmations (high security)
  
  // Check interval in seconds
  static const int CHECK_INTERVAL = 30;
  
  // Storage key for pending transactions
  static const String PENDING_TX_KEY = 'pending_transactions';

  /// Start monitoring transaction confirmations
  Future<void> startTracking({int intervalSeconds = CHECK_INTERVAL}) async {
    if (_isTracking) {
      _logger.i('Confirmation tracking already running');
      return;
    }

    _isTracking = true;
    _logger.i('Starting confirmation tracking (checking every ${intervalSeconds}s)');

    // Initial check
    await _checkPendingTransactions();

    // Set up periodic checks
    _trackingTimer = Timer.periodic(
      Duration(seconds: intervalSeconds),
      (_) => _checkPendingTransactions(),
    );
  }

  /// Stop monitoring
  void stopTracking() {
    _trackingTimer?.cancel();
    _trackingTimer = null;
    _isTracking = false;
    _logger.i('Stopped confirmation tracking');
  }

  /// Add a transaction to track
  Future<void> trackTransaction({
    required String txHash,
    required String chain,
    required String coin,
    required double amount,
    required String type, // 'send' or 'receive'
  }) async {
    try {
      final pendingTxs = await _getPendingTransactions();
      
      // Check if already tracking
      if (pendingTxs.any((tx) => tx['txHash'] == txHash)) {
        _logger.i('Already tracking transaction: $txHash');
        return;
      }

      // Add new transaction
      pendingTxs.add({
        'txHash': txHash,
        'chain': chain,
        'coin': coin,
        'amount': amount,
        'type': type,
        'addedAt': DateTime.now().toIso8601String(),
        'lastChecked': DateTime.now().toIso8601String(),
        'confirmations': 0,
        'notifiedAt': {
          THRESHOLD_LOW.toString(): false,
          THRESHOLD_MEDIUM.toString(): false,
          THRESHOLD_HIGH.toString(): false,
        },
      });

      await _savePendingTransactions(pendingTxs);
      _logger.i('Now tracking transaction: $txHash on $chain');

      // Trigger immediate check
      if (_isTracking) {
        await _checkPendingTransactions();
      }
    } catch (e) {
      _logger.e('Error tracking transaction: $e');
    }
  }

  /// Check all pending transactions for confirmations
  Future<void> _checkPendingTransactions() async {
    try {
      final pendingTxs = await _getPendingTransactions();
      
      if (pendingTxs.isEmpty) {
        return;
      }

      _logger.i('Checking ${pendingTxs.length} pending transaction(s)');

      final updatedTxs = <Map<String, dynamic>>[];
      final completedTxHashes = <String>[];

      for (final tx in pendingTxs) {
        try {
          final txHash = tx['txHash'] as String;
          final chain = tx['chain'] as String;
          final coin = tx['coin'] as String;
          final amount = tx['amount'] as double;
          final type = tx['type'] as String;
          final prevConfirmations = tx['confirmations'] as int;

          // Get current confirmation count
          final confirmations = await _getConfirmationCount(chain, txHash);
          
          if (confirmations < 0) {
            // Transaction not found or error - keep tracking for now
            updatedTxs.add(tx);
            continue;
          }

          // Update transaction
          tx['confirmations'] = confirmations;
          tx['lastChecked'] = DateTime.now().toIso8601String();

          // If the tx has now at least 1 confirmation, update local stored transaction record
          if (confirmations > 0) {
            try {
              final prefs = await SharedPreferences.getInstance();
              final keys = prefs.getKeys().where((k) => k.startsWith('tx_'));
              for (final key in keys) {
                final raw = prefs.getString(key);
                if (raw == null) continue;
                try {
                  final Map<String, dynamic> jsonData =
                      json.decode(raw) as Map<String, dynamic>;
                  if (jsonData['txHash'] == txHash) {
                    jsonData['confirmations'] = confirmations;
                    jsonData['status'] = 'completed';
                    jsonData['isPending'] = false;
                    await prefs.setString(key, json.encode(jsonData));
                    _logger.i(
                        'Updated local stored transaction $key as confirmed ($confirmations)');
                  }
                } catch (e) {
                  // ignore parse errors for unrelated keys
                }
              }
              // Also update notification centre status
              await _notificationService.updateTxStatus(txHash, TxStatus.confirmed);
            } catch (e) {
              _logger.w('Failed to update local stored transaction for $txHash: $e');
            }
          }

          // Check if we should notify at thresholds
          await _checkAndNotify(
            tx,
            prevConfirmations,
            confirmations,
            txHash,
            chain,
            coin,
            amount,
            type,
          );

          // Keep tracking if not fully confirmed (< 12)
          if (confirmations < THRESHOLD_HIGH) {
            updatedTxs.add(tx);
          } else {
            completedTxHashes.add(txHash);
            _logger.i('Transaction $txHash fully confirmed with $confirmations confirmations');
          }
        } catch (e) {
          _logger.e('Error checking transaction: $e');
          // Keep the transaction in the list to retry later
          updatedTxs.add(tx);
        }
      }

      // Save updated list
      await _savePendingTransactions(updatedTxs);

      // Notify about completed transactions
      if (completedTxHashes.isNotEmpty) {
        _logger.i('Removed ${completedTxHashes.length} fully confirmed transaction(s)');
      }
    } catch (e) {
      _logger.e('Error in confirmation tracking: $e');
    }
  }

  /// Get confirmation count for a transaction
  Future<int> _getConfirmationCount(String chain, String txHash) async {
    try {
      final response = await _blockchainService.getTransactionConfirmations(chain, txHash);
      return response['confirmations'] ?? 0;
    } catch (e) {
      _logger.e('Error getting confirmations for $txHash: $e');
      return -1;
    }
  }

  /// Check thresholds and send notifications
  Future<void> _checkAndNotify(
    Map<String, dynamic> tx,
    int prevConfirmations,
    int currentConfirmations,
    String txHash,
    String chain,
    String coin,
    double amount,
    String type,
  ) async {
    final notifiedAt = tx['notifiedAt'] as Map<String, dynamic>;

    // Check each threshold
    for (final threshold in [THRESHOLD_LOW, THRESHOLD_MEDIUM, THRESHOLD_HIGH]) {
      final thresholdKey = threshold.toString();
      final alreadyNotified = notifiedAt[thresholdKey] == true;

      if (!alreadyNotified && currentConfirmations >= threshold && prevConfirmations < threshold) {
        // Send notification
        await _sendConfirmationNotification(
          threshold: threshold,
          confirmations: currentConfirmations,
          txHash: txHash,
          coin: coin,
          amount: amount,
          type: type,
        );

        // Mark as notified
        notifiedAt[thresholdKey] = true;
        _logger.i('Notified for transaction $txHash at $threshold confirmation(s)');
      }
    }
  }

  /// Send notification for confirmation milestone
  Future<void> _sendConfirmationNotification({
    required int threshold,
    required int confirmations,
    required String txHash,
    required String coin,
    required double amount,
    required String type,
  }) async {
    String title;
    String message;

    if (threshold == THRESHOLD_LOW) {
      final direction = type == 'send' ? 'Sent' : 'Received';
      title = '✓ $direction $coin Confirmed';
      message = '${amount.toStringAsFixed(8)} $coin — 1+ confirmation';
    } else if (threshold == THRESHOLD_MEDIUM) {
      title = '✓✓ $coin Transaction Secure';
      message = '${amount.toStringAsFixed(8)} $coin — 6+ confirmations (Standard)';
    } else {
      title = '✓✓✓ $coin Transaction Finalized';
      message = '${amount.toStringAsFixed(8)} $coin — 12+ confirmations (High Security)';
    }

    // Update existing notification's displayed status
    await _notificationService.updateTxStatus(txHash, TxStatus.confirmed);

    // Push a new "confirmed" notification so badge increments
    await _notificationService.showNotification(
      title: title,
      message: message,
      type: NotificationType.confirmed,
      txHash: txHash,
      coin: coin,
      amount: amount.toStringAsFixed(8),
      txStatus: TxStatus.confirmed,
      data: {
        'type': 'confirmation',
        'txHash': txHash,
        'confirmations': confirmations.toString(),
        'coin': coin,
        'amount': amount.toString(),
      },
    );
  }

  /// Get list of pending transactions
  Future<List<Map<String, dynamic>>> _getPendingTransactions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString(PENDING_TX_KEY);
      if (data == null) return [];
      final List<dynamic> list = json.decode(data) as List<dynamic>;
      return list.cast<Map<String, dynamic>>();
    } catch (e) {
      _logger.e('Error reading pending transactions: $e');
      return [];
    }
  }

  /// Save list of pending transactions
  Future<void> _savePendingTransactions(List<Map<String, dynamic>> transactions) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(PENDING_TX_KEY, json.encode(transactions));
    } catch (e) {
      _logger.e('Error saving pending transactions: $e');
    }
  }

  /// Get all pending transactions (for UI display)
  Future<List<Map<String, dynamic>>> getPendingTransactions() async {
    return await _getPendingTransactions();
  }

  /// Get confirmation count for a specific transaction
  Future<int> getConfirmations(String chain, String txHash) async {
    return await _getConfirmationCount(chain, txHash);
  }

  /// Remove a transaction from tracking
  Future<void> stopTrackingTransaction(String txHash) async {
    try {
      final pendingTxs = await _getPendingTransactions();
      pendingTxs.removeWhere((tx) => tx['txHash'] == txHash);
      await _savePendingTransactions(pendingTxs);
      _logger.i('Stopped tracking transaction: $txHash');
    } catch (e) {
      _logger.e('Error stopping tracking: $e');
    }
  }

  /// Clear all pending transactions
  Future<void> clearAllTracking() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(PENDING_TX_KEY);
    _logger.i('Cleared all pending transaction tracking');
  }

  /// Check if service is currently tracking
  bool get isTracking => _isTracking;

  /// Get number of pending transactions
  Future<int> getPendingCount() async {
    final txs = await _getPendingTransactions();
    return txs.length;
  }
}
