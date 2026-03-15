import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'blockchain_service.dart';
import 'notification_service.dart';
import 'transaction_service.dart';
import 'wallet_service.dart';
import 'confirmation_tracker_service.dart';

/// Polls blockchain APIs at regular intervals and fires in-app notifications
/// for any new incoming transactions that the wallet has received since the
/// last check.  Each transaction is notified exactly once (dedup by txHash
/// stored in SharedPreferences).
class IncomingTxWatcherService {
  static final IncomingTxWatcherService _instance =
      IncomingTxWatcherService._internal();
  factory IncomingTxWatcherService() => _instance;
  IncomingTxWatcherService._internal();

  final BlockchainService _blockchainService = BlockchainService();
  final WalletService _walletService = WalletService();
  final NotificationService _notificationService = NotificationService();
  final TransactionService _transactionService = TransactionService();
  final ConfirmationTrackerService _confirmationTracker =
      ConfirmationTrackerService();

  static const String _seenTxsKey = 'seen_incoming_txs';
  static const int _pollIntervalSeconds = 30;
  static const List<String> _watchedCoins = [
    'ETH', 'BTC', 'BNB', 'SOL',
    'TRX', 'XRP', 'DOGE', 'LTC',
  ];

  Timer? _timer;
  bool _isRunning = false;
  bool _isPolling = false;
  Set<String> _seenTxHashes = {};

  bool get isRunning => _isRunning;

  // ─── Lifecycle ────────────────────────────────────────────────────────────

  Future<void> start() async {
    if (_isRunning) return;
    _isRunning = true;
    await _loadSeenTxs();
    print('🔔 IncomingTxWatcher started (polling every ${_pollIntervalSeconds}s, ${_seenTxHashes.length} seen txs loaded)');

    // First poll shortly after start
    Future.delayed(const Duration(seconds: 8), () => _pollAll());

    _timer = Timer.periodic(
      Duration(seconds: _pollIntervalSeconds),
      (_) => _pollAll(),
    );
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
    print('🔔 IncomingTxWatcher stopped');
  }

  // ─── Core poll ────────────────────────────────────────────────────────────

  Future<void> _pollAll() async {
    if (_isPolling) return; // Prevent overlapping polls
    _isPolling = true;
    try {
      for (final coin in _watchedCoins) {
        try {
          final addresses = await _walletService.getStoredAddresses(coin);
          if (addresses.isEmpty) continue;
          for (final address in addresses) {
            if (address.isEmpty) continue;
            await _pollAddress(coin: coin, address: address);
          }
        } catch (e) {
          print('🔔 [$coin] getStoredAddresses error: $e');
        }
        // Small delay between chains to avoid rate limiting
        await Future.delayed(const Duration(milliseconds: 500));
      }
    } finally {
      _isPolling = false;
    }
  }

  Future<void> _pollAddress({
    required String coin,
    required String address,
  }) async {
    try {
      final txs = await _blockchainService.getTransactionHistory(coin, address, fresh: true);
      if (txs.isEmpty) return;

      int newCount = 0;
      for (final tx in txs) {
        final hash = (tx['hash'] ?? tx['txHash'] ?? tx['signature'] ?? '').toString();
        if (hash.isEmpty) continue;

        // Skip if we have already notified about this tx
        if (_seenTxHashes.contains(hash)) continue;

        // Determine if this is a received transaction.
        // Priority: check the 'type' field set by blockchain_service first,
        // then fall back to address comparison.
        final toAddr = (tx['toAddress'] ?? tx['to'] ?? tx['recipient'] ?? '').toString().toLowerCase();
        final fromAddr = (tx['fromAddress'] ?? tx['from'] ?? tx['sender'] ?? '').toString().toLowerCase();
        final txType = (tx['type'] ?? '').toString().toLowerCase();
        final myAddr = address.toLowerCase();

        final isReceived = txType == 'received' ||
            txType == 'incoming' ||
            txType == 'in' ||
            (toAddr.isNotEmpty && toAddr.contains(myAddr) && !fromAddr.contains(myAddr)) ||
            (toAddr.isEmpty && fromAddr.isNotEmpty && !fromAddr.contains(myAddr));

        if (!isReceived) continue;

        // Mark seen immediately so a retry loop doesn't double-fire
        _seenTxHashes.add(hash);
        await _saveSeenTxs();

        final rawAmount = tx['amount'] ?? tx['value'] ?? tx['lamports'] ?? 0;
        double amount = 0.0;
        if (rawAmount is num) {
          amount = rawAmount.toDouble();
        } else {
          amount = double.tryParse(rawAmount.toString()) ?? 0.0;
        }

        // Skip dust/zero amounts
        if (amount <= 0.00000001) continue;

        final senderAddr = (tx['fromAddress'] ?? tx['from'] ?? tx['sender'] ?? 'Unknown').toString();
        final amountStr = amount.toStringAsFixed(8).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');

        print('🔔 💰 NEW INCOMING $coin: +$amountStr from $senderAddr (hash: ${hash.substring(0, 16)}...)');

        // Determine confirmation state
        final confirmations = (tx['confirmations'] as num?)?.toInt() ?? 0;
        final explicitly = tx['isPending'] == true || tx['status'] == 'pending';
        final isPending = explicitly || confirmations == 0;
        final txStatus = isPending ? 'pending' : 'completed';

        // Save to transaction history so it shows in the history page
        await _transactionService.recordReceivedTransaction(
          coin: coin,
          amount: amount,
          fromAddress: senderAddr,
          toAddress: address,
          txHash: hash,
          status: txStatus,
        );

        // Fire in-app notification
        await _notificationService.showIncomingTransaction(
          amount: amountStr,
          currency: coin,
          from: senderAddr,
          txHash: hash,
        );

        newCount++;
        print('🔔 ✅ Notification fired for $coin tx $hash');

        // Start tracking confirmations so status updates from pending → confirmed
        if (isPending) {
          await _confirmationTracker.trackTransaction(
            txHash: hash,
            chain: coin,
            coin: coin,
            amount: amount,
            type: 'receive',
          );
        }
      }

      if (newCount > 0) {
        print('🔔 [$coin] Found $newCount new incoming tx(s) out of ${txs.length} total');
      }
    } catch (e) {
      print('🔔 [$coin] poll error for ${address.substring(0, 8)}...: $e');
    }
  }

  // ─── Seen-tx persistence ─────────────────────────────────────────────────

  Future<void> _loadSeenTxs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_seenTxsKey) ?? [];
      _seenTxHashes = list.toSet();
    } catch (_) {}
  }

  Future<void> _saveSeenTxs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Keep only last 2000 hashes to avoid bloat
      final limited = _seenTxHashes.toList();
      if (limited.length > 2000) {
        limited.removeRange(0, limited.length - 2000);
        _seenTxHashes = limited.toSet();
      }
      await prefs.setStringList(_seenTxsKey, limited);
    } catch (_) {}
  }

  /// Call after a successful manual send to mark the outgoing tx as "seen"
  /// (so an incoming-mirror of your own transfer isn't falsely alerted).
  Future<void> markSeen(String txHash) async {
    _seenTxHashes.add(txHash);
    await _saveSeenTxs();
  }
}
