import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'blockchain_service.dart';
import 'wallet_service.dart';
import 'notification_service.dart';
import 'transaction_service.dart';
import '../models/transaction_model.dart';

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
  static const int CHECK_INTERVAL_SECONDS = 60; // Check every minute

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
    
    // Do initial check after 10 seconds
    Future.delayed(const Duration(seconds: 10), () {
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

  /// Check for incoming transactions by comparing balances
  Future<void> _checkForIncomingTransactions() async {
    if (!_isMonitoring) return;
    
    try {
      print('🔍 Checking for incoming transactions...');
      
      // Get current balances
      final currentBalances = await _walletService.getBalances();
      
      // Compare with last known
      for (final coin in currentBalances.keys) {
        final currentBalance = currentBalances[coin] ?? 0.0;
        final lastBalance = _lastKnownBalances[coin] ?? 0.0;
        
        // Detect increase (incoming)
        if (currentBalance > lastBalance) {
          final increase = currentBalance - lastBalance;
          
          // Only notify for meaningful amounts
          if (increase > 0.00000001) {
            print('💰 Detected incoming $coin: +$increase');
            await _handleIncomingTransaction(coin, increase, currentBalance);
          }
        }
      }
      
      // Update last known balances
      _lastKnownBalances = Map.from(currentBalances);
      await _saveLastKnownBalances();
      
    } catch (e) {
      print('Error checking for incoming transactions: $e');
    }
  }

  /// Handle detected incoming transaction
  Future<void> _handleIncomingTransaction(
    String coin, 
    double amount, 
    double newBalance,
  ) async {
    try {
      // Create a unique identifier for this transaction
      final txIdentifier = '$coin-${amount.toStringAsFixed(8)}-${DateTime.now().millisecondsSinceEpoch ~/ 60000}';
      
      // Check if we've already notified about this transaction
      if (_notifiedTxHashes.contains(txIdentifier)) {
        print('⏭️ Already notified about transaction: $txIdentifier');
        return;
      }
      
      // Add to notified set and save
      _notifiedTxHashes.add(txIdentifier);
      await _saveNotifiedTxHashes();
      
      // Get USD value
      final usdValue = await _getUsdValue(coin, amount);
      final usdString = usdValue > 0 ? ' (\$${usdValue.toStringAsFixed(2)})' : '';
      
      // Show notification
      await _notificationService.showNotification(
        title: '💰 $coin Received!',
        message: '+${amount.toStringAsFixed(8)} $coin$usdString\nNew balance: ${newBalance.toStringAsFixed(8)} $coin',
        type: NotificationType.success,
        data: {
          'type': 'incoming',
          'coin': coin,
          'amount': amount,
          'newBalance': newBalance,
        },
      );
      
      // Try to fetch the actual transaction from blockchain
      await _fetchAndSaveTransaction(coin, amount);
      
      print('✅ Notification sent for incoming $coin');
    } catch (e) {
      print('Error handling incoming transaction: $e');
    }
  }

  /// Get USD value of amount
  Future<double> _getUsdValue(String coin, double amount) async {
    try {
      // Use cached prices or fetch
      final prices = {
        'BTC': 95000.0,
        'ETH': 3020.0,
        'BNB': 650.0,
        'USDT': 1.0,
        'SOL': 200.0,
        'XRP': 2.0,
        'DOGE': 0.30,
        'LTC': 100.0,
      };
      
      return amount * (prices[coin] ?? 0);
    } catch (e) {
      return 0;
    }
  }

  /// Try to fetch the actual transaction and save to history
  Future<void> _fetchAndSaveTransaction(String coin, double amount) async {
    try {
      // Get user's address for this coin
      final addresses = await _walletService.getStoredAddresses(coin);
      if (addresses.isEmpty) return;
      
      final address = addresses.first;
      
      // Fetch recent transactions
      final transactions = await _blockchainService.getTransactionHistory(coin, address);
      
      // Find matching incoming transaction
      for (final tx in transactions) {
        final txType = tx['type']?.toString() ?? '';
        if ((txType == 'receive' || txType == 'received') && 
            ((tx['amount'] as num?)?.toDouble().abs() ?? 0) - amount.abs() < 0.00000001) {
          
          // Save to transaction history
          final transaction = Transaction(
            id: tx['hash'] ?? tx['txHash'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
            coin: coin,
            type: 'received',
            amount: amount,
            status: 'completed',
            timestamp: DateTime.tryParse(tx['timestamp']?.toString() ?? '') ?? DateTime.now(),
            fromAddress: tx['from']?.toString() ?? 'Unknown',
            toAddress: address,
            address: address,
            txHash: tx['hash'] ?? tx['txHash'],
            confirmations: (tx['confirmations'] as num?)?.toInt() ?? 1,
          );
          
          await _transactionService.storeTransaction(transaction);
          print('💾 Saved incoming transaction to history: ${transaction.txHash}');
          return;
        }
      }
    } catch (e) {
      print('Failed to fetch/save transaction details: $e');
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
