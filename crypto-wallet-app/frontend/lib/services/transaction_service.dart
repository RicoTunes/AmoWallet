import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/transaction_model.dart';
import 'blockchain_service.dart';

class TransactionService {
  final FlutterSecureStorage _storage;
  final Logger _logger;
  final BlockchainService _blockchainService;

  TransactionService({
    FlutterSecureStorage? storage, 
    Logger? logger,
    BlockchainService? blockchainService,
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _logger = logger ?? Logger(),
        _blockchainService = blockchainService ?? BlockchainService();

  // ── SharedPreferences helpers (web-safe, no OperationError) ───────────────

  static const String _txPrefix = 'tx_';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<void> _prefsWrite(String key, String value) async {
    final p = await _prefs;
    await p.setString('$_txPrefix$key', value);
  }

  Future<String?> _prefsRead(String key) async {
    final p = await _prefs;
    return p.getString('$_txPrefix$key');
  }

  Future<void> _prefsDelete(String key) async {
    final p = await _prefs;
    await p.remove('$_txPrefix$key');
  }

  Future<Map<String, String>> _prefsReadAll() async {
    final p = await _prefs;
    final result = <String, String>{};
    for (final k in p.getKeys()) {
      if (k.startsWith(_txPrefix)) {
        final v = p.getString(k);
        if (v != null) result[k.substring(_txPrefix.length)] = v;
      }
    }
    return result;
  }

  /// Safe wrapper for reading wallet keys (addresses).
  /// On web, wallet keys are stored in SharedPreferences (FlutterSecureStorage
  /// throws OperationError on web). On native, reads FlutterSecureStorage.
  Future<Map<String, String>> _safeReadAll() async {
    if (kIsWeb) {
      // Wallet keys on web are stored directly in SharedPreferences
      final p = await SharedPreferences.getInstance();
      final result = <String, String>{};
      for (final k in p.getKeys()) {
        // Only include wallet keys (private keys, meta) — skip tx_ prefix keys
        if (k.startsWith(_txPrefix)) continue;
        final v = p.getString(k);
        if (v != null) result[k] = v;
      }
      return result;
    }
    try {
      final dynamic raw = await _storage.readAll();
      if (raw is Map) {
        return Map<String, String>.from(
          raw.map((k, v) => MapEntry(k.toString(), v.toString())),
        );
      }
      return {};
    } catch (e) {
      return {};
    }
  }


  // Store a transaction
  Future<void> storeTransaction(Transaction transaction) async {
    try {
      final key = 'transaction_${transaction.id}';
      await _prefsWrite(key, json.encode(transaction.toJson()));
      _logger.i('Stored transaction: \${transaction.id}');
    } catch (e) {
      _logger.e('Failed to store transaction: $e');
      rethrow;
    }
  }

  // Get all transactions (both stored and from blockchain)
  Future<List<Transaction>> getAllTransactions() async {
    try {
      final Map<String, Transaction> transactionMap = {}; // Use map to prevent duplicates

      // 1. Fetch blockchain transactions for all wallet addresses (primary source of truth)
      try {
        final allStorageKeys = await _safeReadAll();
        final addressesByChain = <String, Set<String>>{};;

        // Group addresses by chain - handle keys like "BTC_address_private" or "USDT-BEP20_address_private"
        for (final k in allStorageKeys.keys) {
          // Only process keys ending with _private
          if (!k.endsWith('_private')) continue;
          
          // Remove the _private suffix and split to find chain and address
          final withoutSuffix = k.substring(0, k.length - 8); // Remove "_private"
          final firstUnderscoreIdx = withoutSuffix.indexOf('_');
          if (firstUnderscoreIdx == -1) continue;
          
          final chain = withoutSuffix.substring(0, firstUnderscoreIdx);
          final address = withoutSuffix.substring(firstUnderscoreIdx + 1);
          
          if (chain.isNotEmpty && address.isNotEmpty) {
            addressesByChain.putIfAbsent(chain, () => {}).add(address);
          }
        }
        
        // Debug: Log detected wallets
        print('DEBUG TX_SERVICE: Detected wallets by chain: $addressesByChain');

        // Fetch transactions for each address
        for (final chain in addressesByChain.keys) {
          // Map chain name to blockchain service chain (e.g., USDT-BEP20 -> BNB for BSC)
          String blockchainChain = chain;
          if (chain.startsWith('USDT-')) {
            if (chain.contains('TRC20')) {
              blockchainChain = 'TRX';
            } else if (chain.contains('BEP20')) {
              blockchainChain = 'BNB';
            } else if (chain.contains('ERC20')) {
              blockchainChain = 'ETH';
            }
          }
          
          for (final address in addressesByChain[chain]!) {
            try {
              print('DEBUG TX_SERVICE: Fetching transactions for $chain (as $blockchainChain) at $address');
              final blockchainTxs = await _blockchainService.getTransactionHistory(blockchainChain, address);
              print('DEBUG TX_SERVICE: Got ${blockchainTxs.length} transactions for $chain');


              // Convert blockchain transactions to Transaction model
              for (final tx in blockchainTxs) {
                final txHash = tx['hash']?.toString() ?? '';
                
                // Skip if no valid hash
                if (txHash.isEmpty) continue;
                
                final txType = tx['type'] ?? 'unknown';
                final isReceived = txType == 'received';

                final transaction = Transaction(
                  id: txHash,
                  type: isReceived ? 'received' : 'sent',
                  coin: chain,
                  amount: (tx['amount'] as num?)?.toDouble() ?? 0.0,
                  address: address,
                  fromAddress: tx['fromAddress']?.toString(),
                  toAddress: tx['toAddress']?.toString(),
                  txHash: txHash,
                  timestamp: DateTime.fromMillisecondsSinceEpoch(
                    ((tx['timestamp'] as int?) ?? 0) * 1000,
                  ),
                  status: ((tx['confirmations'] as int?) ?? 0) > 0 ? 'completed' : 'pending',
                  fee: 0.0,
                  memo: 'Blockchain transaction',
                  confirmations: tx['confirmations'] as int?,
                  isPending: (tx['confirmations'] as int?) == 0,
                );

                // Use txHash as key to prevent duplicates
                transactionMap[txHash] = transaction;
              }
            } catch (e) {
              _logger.w('Failed to fetch transactions for $chain $address: $e');
            }
          }
        }
      } catch (e) {
        _logger.w('Failed to fetch blockchain transactions: $e');
      }

      // 2. Load locally stored transactions (pending ones without txHash yet)
      try {
        final allStorage = await _prefsReadAll();
        for (final entry in allStorage.entries) {
          final key = entry.key;
          if (key.startsWith('transaction_')) {
            try {
              final Map<String, dynamic> jsonData = json.decode(entry.value);
              final localTx = Transaction.fromJson(jsonData);
              
              // Only add if it has a txHash that matches blockchain, or is pending (no txHash)
              final txHash = localTx.txHash;
              if (txHash != null && txHash.isNotEmpty) {
                // Update with local info if blockchain version exists
                if (transactionMap.containsKey(txHash)) {
                  final blockchain = transactionMap[txHash]!;
                  transactionMap[txHash] = Transaction(
                    id: blockchain.id,
                    type: blockchain.type,
                    coin: blockchain.coin,
                    amount: blockchain.amount,
                    address: localTx.address.isNotEmpty ? localTx.address : blockchain.address,
                    fromAddress: blockchain.fromAddress ?? localTx.fromAddress,
                    toAddress: blockchain.toAddress ?? localTx.toAddress,
                    txHash: blockchain.txHash,
                    timestamp: blockchain.timestamp,
                    status: blockchain.status,
                    fee: localTx.fee ?? blockchain.fee,
                    memo: localTx.memo?.isNotEmpty == true ? localTx.memo : blockchain.memo,
                    confirmations: blockchain.confirmations ?? localTx.confirmations,
                    isPending: blockchain.isPending,
                  );
                } else {
                  // Not found on blockchain, keep local (could be still pending)
                  transactionMap[txHash] = localTx;
                }
              } else if (localTx.status == 'pending' || localTx.isPending) {
                // Add pending transactions (they don't have txHash yet)
                transactionMap[localTx.id] = localTx;
              }
              // Skip test/demo transactions that aren't confirmed on blockchain
            } catch (e) {
              _logger.w('Failed to parse stored transaction $key: $e');
            }
          }
        }
      } catch (e) {
        _logger.w('Failed to read local stored transactions: $e');
      }

      // Convert map to list and sort
      final transactions = transactionMap.values.toList();
      transactions.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      return transactions;
    } catch (e) {
      _logger.e('Failed to get transactions: $e');
      return [];
    }
  }

  // Get transactions by coin
  Future<List<Transaction>> getTransactionsByCoin(String coin) async {
    final allTransactions = await getAllTransactions();
    return allTransactions.where((tx) => tx.coin == coin).toList();
  }

  // Get transactions by type (sent/received/swap)
  Future<List<Transaction>> getTransactionsByType(String type) async {
    final allTransactions = await getAllTransactions();
    return allTransactions.where((tx) => tx.type == type).toList();
  }

  // Record a swap transaction
  Future<Transaction> recordSwapTransaction({
    required String fromCoin,
    required String toCoin,
    required double fromAmount,
    required double toAmount,
    required double exchangeRate,
    required double fee,
  }) async {
    final transaction = Transaction(
      id: Transaction.generateId(),
      type: 'swap',
      coin: toCoin, // Show the received coin as primary
      amount: toAmount,
      address: 'Swap',
      timestamp: DateTime.now(),
      status: 'completed',
      fee: fee,
      // Swap-specific fields
      fromCoin: fromCoin,
      toCoin: toCoin,
      fromAmount: fromAmount,
      toAmount: toAmount,
      exchangeRate: exchangeRate,
    );

    await storeTransaction(transaction);
    return transaction;
  }

  // Get transaction by ID
  Future<Transaction?> getTransactionById(String id) async {
    try {
      final key = 'transaction_$id';
      final value = await _prefsRead(key);
      if (value == null) return null;
      return Transaction.fromJson(json.decode(value));
    } catch (e) {
      _logger.e('Failed to get transaction $id: $e');
      return null;
    }
  }

  // Delete a transaction
  Future<void> deleteTransaction(String id) async {
    try {
      final key = 'transaction_$id';
      await _prefsDelete(key);
      _logger.i('Deleted transaction: $id');
    } catch (e) {
      _logger.e('Failed to delete transaction $id: $e');
      rethrow;
    }
  }

  // Clear all transactions
  Future<void> clearAllTransactions() async {
    try {
      final allKeys = await _prefsReadAll();
      for (final key in allKeys.keys) {
        if (key.startsWith('transaction_')) {
          await _prefsDelete(key);
        }
      }
      _logger.i('Cleared all transactions');
    } catch (e) {
      _logger.e('Failed to clear transactions: $e');
      rethrow;
    }
  }

  // Record a sent transaction
  Future<Transaction> recordSentTransaction({
    required String coin,
    required double amount,
    required String toAddress,
    String? fromAddress,
    double? fee,
    String? memo,
    String? txHash,
  }) async {
    final transaction = Transaction(
      id: Transaction.generateId(),
      type: 'sent',
      coin: coin,
      amount: amount,
      address: toAddress,
      toAddress: toAddress,
      fromAddress: fromAddress,
      timestamp: DateTime.now(),
      status: 'pending',
      fee: fee,
      memo: memo,
      txHash: txHash,
      confirmations: 0,
      isPending: true,
    );

    await storeTransaction(transaction);
    return transaction;
  }

  // Record a received transaction
  Future<Transaction> recordReceivedTransaction({
    required String coin,
    required double amount,
    required String fromAddress,
    String? toAddress,
    String? txHash,
    String? memo,
    String status = 'completed',
  }) async {
    // Check if we already have this exact transaction stored (by txHash or combination)
    if (txHash != null && txHash.isNotEmpty) {
      final existingTxs = await getAllTransactions();
      final isDuplicate = existingTxs.any((t) => 
        t.txHash == txHash && 
        t.isReceived && 
        t.coin == coin &&
        (t.amount - amount).abs() < 0.00000001 // same amount (with float tolerance)
      );
      
      if (isDuplicate) {
        _logger.i('Skipped duplicate received transaction: $txHash');
        return existingTxs.firstWhere((t) => t.txHash == txHash);
      }
    }

    final transaction = Transaction(
      id: Transaction.generateId(),
      type: 'received',
      coin: coin,
      amount: amount,
      address: fromAddress,
      fromAddress: fromAddress,
      toAddress: toAddress,
      txHash: txHash,
      timestamp: DateTime.now(),
      status: status,
      isPending: status == 'pending',
      memo: memo,
    );

    await storeTransaction(transaction);
    return transaction;
  }

  // Get transaction statistics
  Future<Map<String, dynamic>> getTransactionStats() async {
    final transactions = await getAllTransactions();
    
    final sentTransactions = transactions.where((tx) => tx.isSent).toList();
    final receivedTransactions = transactions.where((tx) => tx.isReceived).toList();
    final swapTransactions = transactions.where((tx) => tx.isSwap).toList();
    
    final totalSent = sentTransactions.fold(0.0, (sum, tx) => sum + tx.amount);
    final totalReceived = receivedTransactions.fold(0.0, (sum, tx) => sum + tx.amount);
    
    final today = DateTime.now();
    final todayTransactions = transactions.where((tx) =>
      tx.timestamp.year == today.year &&
      tx.timestamp.month == today.month &&
      tx.timestamp.day == today.day
    ).toList();
    
    return {
      'totalTransactions': transactions.length,
      'sentCount': sentTransactions.length,
      'receivedCount': receivedTransactions.length,
      'swapCount': swapTransactions.length,
      'totalSent': totalSent,
      'totalReceived': totalReceived,
      'todayCount': todayTransactions.length,
      'netFlow': totalReceived - totalSent,
    };
  }

  // Search transactions
  Future<List<Transaction>> searchTransactions(String query) async {
    final transactions = await getAllTransactions();
    final lowercaseQuery = query.toLowerCase();
    
    return transactions.where((tx) {
      return tx.coin.toLowerCase().contains(lowercaseQuery) ||
             tx.address.toLowerCase().contains(lowercaseQuery) ||
             (tx.memo?.toLowerCase().contains(lowercaseQuery) ?? false) ||
             tx.type.toLowerCase().contains(lowercaseQuery);
    }).toList();
  }

  // Clear old test transactions (keep only recent ones from last 7 days)
  Future<void> clearOldTestTransactions() async {
    try {
      final allStorage = await _prefsReadAll();
      final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
      
      for (final entry in allStorage.entries) {
        final key = entry.key;
        if (key.startsWith('transaction_')) {
          try {
            final Map<String, dynamic> jsonData = json.decode(entry.value);
            final tx = Transaction.fromJson(jsonData);
            
            // Delete if:
            // 1. Older than 7 days (likely test data)
            // 2. Status is 'pending' and older than 1 hour (failed transactions)
            if (tx.timestamp.isBefore(sevenDaysAgo)) {
              await _prefsDelete(key);
              _logger.i('Deleted old transaction: $key');
            } else if ((tx.status == 'pending' || tx.isPending) && 
                       tx.timestamp.isBefore(DateTime.now().subtract(const Duration(hours: 1)))) {
              await _prefsDelete(key);
              _logger.i('Deleted stale pending transaction: $key');
            }
          } catch (e) {
            _logger.w('Error processing transaction for cleanup: $e');
          }
        }
      }
      _logger.i('Completed transaction cleanup');
    } catch (e) {
      _logger.e('Failed to clear old transactions: $e');
      rethrow;
    }
  }
}
