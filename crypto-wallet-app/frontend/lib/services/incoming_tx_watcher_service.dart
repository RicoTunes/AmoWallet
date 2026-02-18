import 'dart:async';
import 'package:logger/logger.dart';
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

  final Logger _logger = Logger();
  final BlockchainService _blockchainService = BlockchainService();
  final WalletService _walletService = WalletService();
  final NotificationService _notificationService = NotificationService();
  final TransactionService _transactionService = TransactionService();
  final ConfirmationTrackerService _confirmationTracker =
      ConfirmationTrackerService();

  static const String _seenTxsKey = 'seen_incoming_txs';
  static const int _pollIntervalSeconds = 45;
  // USDT/USDC are omitted here: their addresses are the same as ETH/BNB/TRX
  // and are already covered when we poll those base chains.
  static const List<String> _watchedCoins = [
    'ETH', 'BTC', 'BNB', 'MATIC', 'SOL',
    'TRX', 'XRP', 'DOGE', 'LTC',
  ];

  Timer? _timer;
  bool _isRunning = false;
  Set<String> _seenTxHashes = {};

  bool get isRunning => _isRunning;

  // ─── Lifecycle ────────────────────────────────────────────────────────────

  Future<void> start() async {
    if (_isRunning) return;
    _isRunning = true;
    await _loadSeenTxs();
    _logger.i('IncomingTxWatcher started (polling every ${_pollIntervalSeconds}s)');

    // First poll shortly after start
    await Future.delayed(const Duration(seconds: 5));
    await _pollAll();

    _timer = Timer.periodic(
      Duration(seconds: _pollIntervalSeconds),
      (_) => _pollAll(),
    );
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
    _logger.i('IncomingTxWatcher stopped');
  }

  // ─── Core poll ────────────────────────────────────────────────────────────

  Future<void> _pollAll() async {
    for (final coin in _watchedCoins) {
      try {
        final addresses = await _walletService.getStoredAddresses(coin);
        for (final address in addresses) {
          if (address.isEmpty) continue;
          await _pollAddress(coin: coin, address: address);
        }
      } catch (e) {
        // Skip unsupported chains silently
      }
    }
  }

  Future<void> _pollAddress({
    required String coin,
    required String address,
  }) async {
    try {
      final txs = await _blockchainService.getTransactionHistory(coin, address);

      for (final tx in txs) {
        final hash = (tx['hash'] ?? tx['txHash'] ?? tx['signature'] ?? '').toString();
        if (hash.isEmpty) continue;

        // Only look at received transactions.
        // Some chains (SOL, DOGE, LTC) don't populate toAddress — fall back to
        // the 'type' field they do set, or check fromAddress mismatch.
        final toAddr = (tx['to'] ?? tx['toAddress'] ?? tx['recipient'] ?? '').toString().toLowerCase();
        final txType = (tx['type'] ?? '').toString().toLowerCase();
        final fromAddr2 = (tx['from'] ?? tx['fromAddress'] ?? tx['sender'] ?? '').toString().toLowerCase();
        final isReceived = toAddr.contains(address.toLowerCase()) ||
            (toAddr.isEmpty && txType == 'received') ||
            (toAddr.isEmpty && txType.isEmpty && fromAddr2.isNotEmpty && !fromAddr2.contains(address.toLowerCase()));
        if (!isReceived) continue;

        // Skip if we have already notified about this tx
        if (_seenTxHashes.contains(hash)) continue;

        // Mark seen immediately so a retry loop doesn't double-fire
        _seenTxHashes.add(hash);
        await _saveSeenTxs();

        final rawAmount = tx['value'] ?? tx['amount'] ?? tx['lamports'] ?? 0;
        double amount = 0.0;
        if (rawAmount is num) {
          amount = rawAmount.toDouble();
        } else {
          amount = double.tryParse(rawAmount.toString()) ?? 0.0;
        }

        final fromAddr = (tx['from'] ?? tx['fromAddress'] ?? tx['sender'] ?? 'Unknown').toString();
        final amountStr = amount.toStringAsFixed(8).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');

        _logger.i('New incoming $coin tx detected: $hash');

        // Determine confirmation state
        final confirmations = (tx['confirmations'] as num?)?.toInt() ?? 0;
        final explicitly = tx['isPending'] == true || tx['status'] == 'pending';
        final isPending = explicitly || confirmations == 0;
        final txStatus = isPending ? 'pending' : 'completed';

        // Save to transaction history so it shows in the history page
        await _transactionService.recordReceivedTransaction(
          coin: coin,
          amount: amount,
          fromAddress: fromAddr,
          toAddress: address,
          txHash: hash,
          status: txStatus,
        );

        // Fire in-app notification (dedup handled inside NotificationService too)
        await _notificationService.showIncomingTransaction(
          amount: amountStr,
          currency: coin,
          from: fromAddr,
          txHash: hash,
        );

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
    } catch (e) {
      // Silent – network errors are expected when offline
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
