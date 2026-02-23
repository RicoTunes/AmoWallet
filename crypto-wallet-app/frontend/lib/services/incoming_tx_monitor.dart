import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'blockchain_service.dart';
import 'wallet_service.dart';
import 'notification_service.dart';
import 'transaction_service.dart';

/// Service to monitor and detect incoming transactions
class IncomingTxMonitor {
  static final IncomingTxMonitor _instance = IncomingTxMonitor._internal();
  factory IncomingTxMonitor() => _instance;
  IncomingTxMonitor._internal();

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final BlockchainService _blockchainService = BlockchainService();
  final WalletService _walletService = WalletService();
  final NotificationService _notificationService = NotificationService();
  final TransactionService _transactionService = TransactionService();

  Timer? _monitorTimer;
  bool _isMonitoring = false;
  Map<String, double> _lastKnownBalances = {};
  DateTime? _monitorStartTime; // Track when monitoring started (app install/first run)
  Set<String> _notifiedTxHashes = {}; // Track already notified transaction hashes
  
  static const String LAST_BALANCES_KEY = 'last_known_balances';
  static const String MONITOR_START_TIME_KEY = 'tx_monitor_start_time';
  static const String NOTIFIED_TX_HASHES_KEY = 'notified_tx_hashes';
  static const int CHECK_INTERVAL_SECONDS = 30; // Check every 30 seconds

  /// Start monitoring for incoming transactions
  Future<void> startMonitoring() async {
    if (_isMonitoring) return;
    _isMonitoring = true;
    
    print('🔍 Starting incoming transaction monitor...');
    
    // Load or set the monitor start time (tracks when monitoring first started)
    await _loadOrSetMonitorStartTime();
    
    // Load already notified transaction hashes
    await _loadNotifiedTxHashes();
    
    // Load last known balances
    await _loadLastKnownBalances();
    
    // Capture initial balances if none saved
    if (_lastKnownBalances.isEmpty) {
      await _captureCurrentBalances();
    }
    
    // Start periodic monitoring
    _monitorTimer = Timer.periodic(
      const Duration(seconds: CHECK_INTERVAL_SECONDS),
      (_) => _checkForIncomingTransactions(),
    );
    
    // Do initial check after 5 seconds (gives wallet service time to set up)
    Future.delayed(const Duration(seconds: 5), () {
      if (_isMonitoring) _checkForIncomingTransactions();
    });
  }

  /// Load or set the monitor start time
  Future<void> _loadOrSetMonitorStartTime() async {
    try {
      final stored = await _storage.read(key: MONITOR_START_TIME_KEY);
      if (stored != null) {
        _monitorStartTime = DateTime.parse(stored);
        print('📅 Monitor start time loaded: $_monitorStartTime');
      } else {
        // First time - set the start time to now
        _monitorStartTime = DateTime.now();
        await _storage.write(
          key: MONITOR_START_TIME_KEY,
          value: _monitorStartTime!.toIso8601String(),
        );
        print('📅 Monitor start time set to: $_monitorStartTime');
      }
    } catch (e) {
      _monitorStartTime = DateTime.now();
      print('⚠️ Error loading monitor start time, defaulting to now: $e');
    }
  }

  /// Load already notified transaction hashes
  Future<void> _loadNotifiedTxHashes() async {
    try {
      final stored = await _storage.read(key: NOTIFIED_TX_HASHES_KEY);
      if (stored != null) {
        final List<dynamic> decoded = jsonDecode(stored);
        _notifiedTxHashes = decoded.map((e) => e.toString()).toSet();
        print('📋 Loaded ${_notifiedTxHashes.length} already notified tx hashes');
      }
    } catch (e) {
      print('⚠️ Error loading notified tx hashes: $e');
    }
  }

  /// Save notified transaction hashes
  Future<void> _saveNotifiedTxHashes() async {
    try {
      // Keep only the last 500 tx hashes to prevent unbounded growth
      if (_notifiedTxHashes.length > 500) {
        _notifiedTxHashes = _notifiedTxHashes.toList().sublist(_notifiedTxHashes.length - 500).toSet();
      }
      await _storage.write(
        key: NOTIFIED_TX_HASHES_KEY,
        value: jsonEncode(_notifiedTxHashes.toList()),
      );
    } catch (e) {
      print('⚠️ Error saving notified tx hashes: $e');
    }
  }

  /// Stop monitoring
  void stopMonitoring() {
    _monitorTimer?.cancel();
    _monitorTimer = null;
    _isMonitoring = false;
    print('⏹️ Stopped incoming transaction monitor');
  }

  /// Load last known balances from storage
  Future<void> _loadLastKnownBalances() async {
    try {
      final data = await _storage.read(key: LAST_BALANCES_KEY);
      if (data != null) {
        final Map<String, dynamic> decoded = jsonDecode(data);
        _lastKnownBalances = decoded.map((k, v) => MapEntry(k, (v as num).toDouble()));
        print('📊 Loaded last known balances: $_lastKnownBalances');
      }
    } catch (e) {
      print('Failed to load last known balances: $e');
    }
  }

  /// Save last known balances
  Future<void> _saveLastKnownBalances() async {
    try {
      await _storage.write(
        key: LAST_BALANCES_KEY,
        value: jsonEncode(_lastKnownBalances),
      );
    } catch (e) {
      print('Failed to save last known balances: $e');
    }
  }

  /// Capture current balances
  Future<void> _captureCurrentBalances() async {
    try {
      final balances = await _walletService.getBalances();
      _lastKnownBalances = Map.from(balances);
      await _saveLastKnownBalances();
      print('📊 Captured current balances: $_lastKnownBalances');
    } catch (e) {
      print('Failed to capture current balances: $e');
    }
  }

  /// Check for incoming transactions by scanning blockchain transaction history
  /// for new received hashes we haven't notified about yet.
  /// Falls back to balance-comparison when tx history is unavailable.
  Future<void> _checkForIncomingTransactions() async {
    if (!_isMonitoring) return;
    
    try {
      print('🔍 Checking for incoming transactions...');
      
      // Supported chains
      const chains = ['BTC', 'ETH', 'BNB', 'SOL', 'TRX', 'LTC', 'DOGE', 'XRP'];
      
      for (final coin in chains) {
        try {
          final addresses = await _walletService.getStoredAddresses(coin);
          if (addresses.isEmpty) continue;
          final address = addresses.first;
          
          // Primary: fetch recent tx history and look for new received hashes
          final txs = await _blockchainService.getTransactionHistory(coin, address)
              .timeout(const Duration(seconds: 10), onTimeout: () => <Map<String, dynamic>>[]);
          
          for (final tx in txs) {
            final txHash = (tx['hash'] ?? tx['txHash'] ?? '').toString();
            if (txHash.isEmpty) continue;
            
            // Determine if this is an incoming tx
            final rawType = (tx['type'] ?? '').toString().toLowerCase();
            final toAddr = (tx['toAddress'] ?? tx['to'] ?? '').toString().toLowerCase();
            final fromAddr = (tx['fromAddress'] ?? tx['from'] ?? '').toString().toLowerCase();
            final myAddr = address.toLowerCase();
            
            final isReceived = rawType == 'received' ||
                rawType.contains('incoming') ||
                rawType == 'in' ||
                (toAddr == myAddr && fromAddr != myAddr);
            
            if (!isReceived) continue;
            
            // Skip if already notified
            if (_notifiedTxHashes.contains(txHash)) continue;
            
            // Skip transactions that happened before monitor was installed
            if (_monitorStartTime != null) {
              final ts = (tx['timestamp'] as int?) ?? 0;
              final txTime = ts > 0
                  ? DateTime.fromMillisecondsSinceEpoch(ts > 9999999999 ? ts : ts * 1000)
                  : DateTime.now();
              if (txTime.isBefore(_monitorStartTime!)) continue;
            }
            
            final amount = (tx['amount'] as num?)?.toDouble().abs() ?? 0.0;
            if (amount <= 0.00000001) continue;
            
            // New incoming transaction found!
            print('💰 New incoming $coin detected: +$amount (hash: $txHash)');
            
            _notifiedTxHashes.add(txHash);
            await _saveNotifiedTxHashes();
            
            // Record to transaction history
            await _transactionService.recordReceivedTransaction(
              coin: coin,
              amount: amount,
              fromAddress: fromAddr.isNotEmpty ? fromAddr : 'Unknown',
              toAddress: address,
              txHash: txHash,
            );
            
            // Show notification
            await _notificationService.showIncomingTransaction(
              amount: amount.toStringAsFixed(8).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), ''),
              currency: coin,
              from: fromAddr.isNotEmpty
                  ? (fromAddr.length > 12 ? '${fromAddr.substring(0, 10)}…' : fromAddr)
                  : 'Blockchain',
              txHash: txHash,
            );
            
            print('✅ Notification sent for incoming $coin (txHash: $txHash)');
          }
        } catch (e) {
          print('⚠️ Error checking $coin for incoming txs: $e');
        }
      }
      
      // Also update balance snapshot so other parts of the app stay in sync
      try {
        final currentBalances = await _walletService.getBalances();
        _lastKnownBalances = Map.from(currentBalances);
        await _saveLastKnownBalances();
      } catch (_) {}
      
    } catch (e) {
      print('Error checking for incoming transactions: $e');
    }
  }

  /// Force refresh and check
  Future<void> forceCheck() async {
    await _checkForIncomingTransactions();
  }

  /// Reset monitored balances (use when user manually refreshes)
  Future<void> resetBalances() async {
    await _captureCurrentBalances();
  }
}
