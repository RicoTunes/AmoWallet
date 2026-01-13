import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logger/logger.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'bip39_wallet.dart';
import 'blockchain_service.dart';
import '../core/config/api_config.dart';

class WalletService {
  final Dio _dio;
  final dynamic _storage;
  final Logger _logger;

  /// WalletService constructor. Optional dependencies may be injected for testing.
  WalletService({Dio? dio, dynamic storage, Logger? logger})
      : _dio = dio ?? Dio(BaseOptions(
          baseUrl: '${ApiConfig.baseUrl}/api/wallet',
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        )),
        _storage = storage ?? const FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: true),
        ),
        _logger = logger ?? Logger();

  /// Store wallet credentials in the format expected by getBalances()
  Future<void> storeWalletCredentials(String chain, String address, String? privateKey, String? mnemonic) async {
    if (privateKey != null) {
      await _storage.write(key: '${chain}_${address}_private', value: privateKey);
    }
    if (mnemonic != null) {
      await _storage.write(key: '${chain}_${address}_mnemonic', value: mnemonic);
    }
    // Also store a simple marker for this address
    await _storage.write(key: '${chain}_${address}_meta', value: DateTime.now().toIso8601String());
    _logger.i('Stored credentials for $chain wallet: $address');
  }

  /// Generate a blockchain-specific address for the given chain.
  /// preferLocal: try to generate locally (BIP39/BIP44) for supported chains (ETH, BTC, TRX, BNB, LTC, XRP, DOGE, SOL).
  Future<Map<String, String>> generateAddressFor(String chain, {bool preferLocal = true}) async {
    try {
      final uc = chain.toUpperCase();

      // Resolve token network aliases. Support USDT/USDC on ERC20, BEP20 (BSC) and TRC20 (Tron).
      String backendChain;
      if (uc.startsWith('USDT-') || uc.startsWith('USDC-')) {
        if (uc.contains('TRC20')) {
          backendChain = 'TRX'; // Tron
        } else {
          // ERC20 and BEP20 are EVM compatible; derive using ETH keys/addresses
          backendChain = 'ETH';
        }
      } else {
        final evmLike = {'USDT', 'USDC', 'BNB', 'MATIC', 'AVAX', 'FTM', 'ONE', 'ARB'};
        backendChain = (evmLike.contains(uc)) ? 'ETH' : uc;
      }

  if (preferLocal && (backendChain == 'ETH' || backendChain == 'BTC' || backendChain == 'TRX' || backendChain == 'BNB' || backendChain == 'LTC' || backendChain == 'XRP' || backendChain == 'DOGE' || backendChain == 'SOL')) {
        try {
          final local = await Bip39Wallet.generate(chain: backendChain);

          final address = local['address']!;
          final privateKey = local['privateKey'];
          final mnemonic = local['mnemonic'];

          // Store generated secrets locally only
          if (privateKey != null) {
            await _storage.write(key: '${chain}_${address}_private', value: privateKey);
          }
          if (mnemonic != null) {
            await _storage.write(key: '${chain}_${address}_mnemonic', value: mnemonic);
          }

          final result = <String, String>{'address': address};
          if (privateKey != null) result['privateKey'] = privateKey;
          if (mnemonic != null) result['mnemonic'] = mnemonic;
          return result;
        } catch (e) {
          _logger.w('Local generation failed for $chain, falling back to backend: $e');
        }
      }

      final response = await _dio.post('/generate', queryParameters: {'chain': backendChain});
      final data = response.data;

      if (data == null || data is! Map) {
        throw Exception('Invalid response from backend');
      }

      final address = data['address']?.toString();
      final privateKey = data['privateKey']?.toString();
      final mnemonic = data['mnemonic']?.toString();

      if (address == null) {
        throw Exception('Missing address in response');
      }

      if (privateKey != null) {
        await _storage.write(key: '${chain}_${address}_private', value: privateKey);
        if (mnemonic != null) {
          await _storage.write(key: '${chain}_${address}_mnemonic', value: mnemonic);
        }
      } else {
        await _storage.write(key: '${chain}_${address}_meta', value: DateTime.now().toIso8601String());
      }

      final result = <String, String>{'address': address};
      if (privateKey != null) result['privateKey'] = privateKey;
      if (mnemonic != null) result['mnemonic'] = mnemonic;
      return result;
    } catch (e) {
      _logger.e('Failed to generate address for $chain: $e');
      rethrow;
    }
  }

  /// Get the list of stored addresses for a given chain
  Future<List<String>> getStoredAddresses(String chain) async {
    try {
      final dynamic rawKeys = await _storage.readAll();
      final addresses = <String>{};
      
      // Handle type casting carefully for web compatibility
      if (rawKeys != null && rawKeys is Map) {
        for (final entry in rawKeys.entries) {
          final k = entry.key?.toString() ?? '';
          if (!k.startsWith('${chain}_')) continue;
          final parts = k.split('_');
          if (parts.length < 3) continue;
          final addr = parts[1];
          final suffix = parts.sublist(2).join('_');
          if (suffix == 'private' || suffix == 'meta' || suffix == 'mnemonic') {
            addresses.add(addr);
          }
        }
      }
      return addresses.toList();
    } catch (e) {
      _logger.e('Failed to get stored addresses: $e');
      return [];
    }
  }

  /// Get the private key for a given address
  Future<String?> getPrivateKey(String chain, String address) async {
    try {
      return await _storage.read(key: '${chain}_${address}_private');
    } catch (e) {
      _logger.e('Failed to get private key: $e');
      return null;
    }
  }

  /// Get the mnemonic phrase for a given address
  Future<String?> getMnemonic(String chain, String address) async {
    try {
      return await _storage.read(key: '${chain}_${address}_mnemonic');
    } catch (e) {
      _logger.e('Failed to get mnemonic: $e');
      return null;
    }
  }

  /// Mark that the user has completed the backup verification process
  Future<void> markBackupCompleted() async {
    try {
      await _storage.write(key: 'backup_completed', value: 'true');
      _logger.i('Backup marked as completed');
    } catch (e) {
      _logger.e('Failed to mark backup completed: $e');
      rethrow;
    }
  }

  /// Check if the user has completed backup verification
  Future<bool> isBackupCompleted() async {
    try {
      final value = await _storage.read(key: 'backup_completed');
      return value == 'true';
    } catch (e) {
      _logger.e('Failed to check backup status: $e');
      return false;
    }
  }

  /// Delete all stored keys for an address
  Future<void> deleteAddress(String chain, String address) async {
    try {
      await _storage.delete(key: '${chain}_${address}_private');
      await _storage.delete(key: '${chain}_${address}_mnemonic');
    } catch (e) {
      _logger.e('Failed to delete address: $e');
      rethrow;
    }
  }

  /// Sign a message using the private key for the given chain and address
  Future<String> signMessage(String chain, String address, String message) async {
    try {
      final privateKey = await getPrivateKey(chain, address);
      if (privateKey == null) {
        throw Exception('Private key not found for this address');
      }

      final response = await _dio.post('/sign', data: {
        'chain': chain,
        'privateKey': privateKey,
        'message': message,
      });

      final signature = response.data['signature'] ?? response.data['result'];
      if (signature == null) throw Exception('No signature in response');
      return signature.toString();
    } catch (e) {
      _logger.e('Failed to sign message: $e');
      rethrow;
    }
  }

  /// Verify a signature against a message using a public key
  Future<bool> verifySignature(String publicKey, String message, String signature) async {
    try {
      final response = await _dio.post('/verify', data: {
        'publicKey': publicKey,
        'message': message,
        'signature': signature,
      });

      return response.data['valid'] ?? response.data['result'] ?? false;
    } catch (e) {
      _logger.e('Failed to verify signature: $e');
      rethrow;
    }
  }

  /// Backwards-compatible helper used by some UI pages.
  /// Generates a wallet/address for the provided chain (defaults to BTC) and returns the result map.
  Future<Map<String, String>> generateWallet({String? chain}) async {
    final c = chain ?? 'BTC';
    return await generateAddressFor(c);
  }

  // ------------------ PIN & Audit helpers ------------------
  String _hashPin(String pin, String salt) {
    final digest = SHA256Digest();
    final input = Uint8List.fromList(utf8.encode(salt + pin));
    final out = digest.process(input);
    return base64.encode(out);
  }

  Future<void> setPin(String pin) async {
    final rnd = Random.secure();
    final saltBytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    final salt = base64.encode(saltBytes);
    final hash = _hashPin(pin, salt);
    await _storage.write(key: 'wallet_pin', value: '$salt:$hash');
  }

  Future<bool> hasPin() async {
    final v = await _storage.read(key: 'wallet_pin');
    return v != null;
  }

  Future<bool> verifyPin(String pin) async {
    try {
      final v = await _storage.read(key: 'wallet_pin');
      if (v == null) return false;
      final parts = v.split(':');
      if (parts.length != 2) return false;
      final salt = parts[0];
      final stored = parts[1];
      final hash = _hashPin(pin, salt);
      return hash == stored;
    } catch (_) {
      return false;
    }
  }

  /// Remove the stored wallet PIN (used for PIN reset/remove flows).
  Future<void> deletePin() async {
    try {
      await _storage.delete(key: 'wallet_pin');
    } catch (e) {
      _logger.w('Failed to delete PIN: $e');
    }
  }

  Future<void> recordRevealEvent(String chain, String address, bool success) async {
    try {
      final raw = await _storage.read(key: 'reveal_audit');
      List entries = [];
      if (raw != null) {
        entries = json.decode(raw) as List;
      }
      entries.add({
        'timestamp': DateTime.now().toIso8601String(),
        'chain': chain,
        'address': address,
        'success': success,
      });
      // keep last 200 events
      if (entries.length > 200) entries = entries.sublist(entries.length - 200);
      await _storage.write(key: 'reveal_audit', value: json.encode(entries));
    } catch (e) {
      _logger.w('Failed to record reveal event: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getRevealAudit() async {
    try {
      final raw = await _storage.read(key: 'reveal_audit');
      if (raw == null) return [];
      final parsed = json.decode(raw) as List;
      return parsed.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e) {
      _logger.w('Failed to read reveal audit: $e');
      return [];
    }
  }

  /// Get balances for all stored addresses across all chains
  /// Incorporates swap adjustments from local storage
  Future<Map<String, double>> getBalances() async {
    try {
      final balances = <String, double>{};
      
      // Define valid blockchain chains
      const validChains = {
        'BTC', 'ETH', 'BNB', 'USDT', 'TRX', 'XRP', 'SOL', 'LTC', 'DOGE',
        'POLYGON', 'ARBITRUM', 'OPTIMISM', 'AVALANCHE'
      };
      
      // Get all stored addresses across all chains
      final dynamic rawKeys = await _storage.readAll();
      final allKeys = rawKeys is Map ? Map<String, String>.from(rawKeys.map((k, v) => MapEntry(k.toString(), v.toString()))) : <String, String>{};
      print('🔑 Total keys in storage: ${allKeys.length}');
      
      final addressesByChain = <String, Set<String>>{};
      
      for (final k in allKeys.keys) {
        final parts = k.split('_');
        if (parts.length >= 3) {
          final chain = parts[0];
          final address = parts[1];
          
          // Only process valid blockchain chains
          if (!validChains.contains(chain)) {
            continue; // Skip non-wallet keys like 'is_logged', 'transaction_tx', etc.
          }
          
          print('📍 Found wallet: $chain - $address');
          addressesByChain.putIfAbsent(chain, () => {}).add(address);
        }
      }
      
      print('💼 Wallets by chain: ${addressesByChain.length} chains');
      
      if (addressesByChain.isEmpty) {
        print('⚠️ No wallets found in storage!');
        return {};
      }
      
      // Query balance for each address using blockchain service
      final blockchainService = BlockchainService();
      
      for (final chain in addressesByChain.keys) {
        double chainTotal = 0.0;
        for (final address in addressesByChain[chain]!) {
          try {
            print('🔍 Fetching balance for $chain $address');
            // Get real balance from blockchain service
            final balance = await blockchainService.getBalance(chain, address);
            print('✅ Balance for $chain $address: $balance');
            chainTotal += balance;
          } catch (e) {
            print('❌ Failed to get balance for $chain $address: $e');
            _logger.w('Failed to get balance for $chain $address: $e');
          }
        }
        if (chainTotal > 0) {
          balances[chain] = chainTotal;
        }
      }
      
      // Apply swap adjustments from local storage
      final swapAdjustments = await _getSwapBalanceAdjustments();
      for (final coin in swapAdjustments.keys) {
        final adjustment = swapAdjustments[coin] ?? 0.0;
        final current = balances[coin] ?? 0.0;
        final adjusted = current + adjustment;
        
        // Always add/update the coin if adjustment exists
        if (adjusted > 0) {
          balances[coin] = adjusted;
        } else if (adjusted <= 0) {
          // Set to 0 if negative, but keep in map so it shows up
          balances[coin] = 0.0;
        }
        print('💱 Applied swap adjustment for $coin: $current + $adjustment = $adjusted');
      }
      
      print('💰 Total balances (with swaps): $balances');
      return balances;
    } catch (e) {
      print('❌ Failed to get balances: $e');
      _logger.e('Failed to get balances: $e');
      return {};
    }
  }
  
  /// Get swap balance adjustments from SharedPreferences (persists on web)
  Future<Map<String, double>> _getSwapBalanceAdjustments() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final adjustments = <String, double>{};
      
      // Get all keys and filter swap adjustments
      final allKeys = prefs.getKeys();
      print('🔍 SharedPreferences keys: ${allKeys.length} total');
      print('🔍 All keys: $allKeys');
      
      for (final key in allKeys) {
        if (key.startsWith('swap_adjustment_')) {
          final coin = key.replaceFirst('swap_adjustment_', '');
          final value = prefs.getDouble(key) ?? 0.0;
          print('💱 Found swap adjustment: $key = $value');
          if (value != 0.0) {
            adjustments[coin] = value;
          }
        }
      }
      
      print('📊 Total swap adjustments found: $adjustments');
      return adjustments;
    } catch (e) {
      print('❌ Failed to get swap adjustments: $e');
      _logger.e('Failed to get swap adjustments: $e');
      return {};
    }
  }

  /// Execute a trade on the spot market
  Future<Map<String, dynamic>> executeTrade({
    required String pair,
    required String type,
    required double amount,
    required double price,
  }) async {
    try {
      // Mock implementation - replace with actual trading API
      _logger.i('Executing trade: $type $amount $pair at $price');
      
      // Simulate trade execution
      await Future.delayed(const Duration(milliseconds: 500));
      
      return {
        'success': true,
        'orderId': DateTime.now().millisecondsSinceEpoch.toString(),
        'type': type,
        'pair': pair,
        'amount': amount,
        'price': price,
        'timestamp': DateTime.now().toIso8601String(),
        'status': 'filled',
      };
    } catch (e) {
      _logger.e('Failed to execute trade: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Update swap adjustment for a coin (delta, not absolute value)
  /// positive = received coins, negative = sent coins
  Future<void> updateCachedBalance(String coin, double absoluteBalance) async {
    // This is kept for backwards compatibility but now delegates to swap adjustment
    _logger.i('updateCachedBalance called for $coin with $absoluteBalance');
  }

  /// Record a swap transaction and update balance adjustments
  /// Uses SharedPreferences for persistence (works better on web)
  Future<void> recordSwapTransaction({
    required String fromCoin,
    required String toCoin,
    required double fromAmount,
    required double toAmount,
    required double fee,
    required String txHash,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Get base coin (USDT-BEP20 -> USDT for balance tracking)
      final fromBase = fromCoin.contains('-') ? fromCoin.split('-')[0] : fromCoin;
      final toBase = toCoin.contains('-') ? toCoin.split('-')[0] : toCoin;
      
      // Update swap adjustments (delta values) - use SharedPreferences for persistence
      // Debit from source coin
      final currentFromAdj = prefs.getDouble('swap_adjustment_$fromBase') ?? 0.0;
      final newFromAdj = currentFromAdj - fromAmount - fee;
      await prefs.setDouble('swap_adjustment_$fromBase', newFromAdj);
      
      // Credit to destination coin
      final currentToAdj = prefs.getDouble('swap_adjustment_$toBase') ?? 0.0;
      final newToAdj = currentToAdj + toAmount;
      await prefs.setDouble('swap_adjustment_$toBase', newToAdj);
      
      // Save the swap transaction for history
      final timestamp = DateTime.now().toIso8601String();
      final swapData = {
        'txHash': txHash,
        'fromCoin': fromCoin,
        'toCoin': toCoin,
        'fromAmount': fromAmount,
        'toAmount': toAmount,
        'fee': fee,
        'timestamp': timestamp,
        'status': 'completed',
        'type': 'swap',
      };
      
      // Store swap in history list
      final historyJson = prefs.getString('swap_history') ?? '[]';
      final history = List<Map<String, dynamic>>.from(jsonDecode(historyJson));
      history.insert(0, swapData); // Add to beginning
      await prefs.setString('swap_history', jsonEncode(history));
      
      _logger.i('✅ Recorded swap: -$fromAmount $fromBase, +$toAmount $toBase');
      print('✅ Swap recorded: $fromAmount $fromCoin → $toAmount $toCoin (fee: $fee)');
      print('📊 New adjustments: $fromBase=$newFromAdj, $toBase=$newToAdj');
      print('💾 Swap saved to SharedPreferences (persists on restart)');
    } catch (e) {
      _logger.e('Failed to record swap transaction: $e');
      print('❌ Failed to record swap: $e');
    }
  }

  /// Get all swap transactions for history from SharedPreferences
  Future<List<Map<String, dynamic>>> getSwapHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getString('swap_history') ?? '[]';
      final history = List<Map<String, dynamic>>.from(
        jsonDecode(historyJson).map((item) => Map<String, dynamic>.from(item))
      );
      return history;
    } catch (e) {
      _logger.e('Failed to get swap history: $e');
      print('❌ Failed to load swap history: $e');
      return [];
    }
  }

  /// Get cached balance for a coin
  Future<double> getCachedBalance(String coin) async {
    try {
      final cached = await _storage.read(key: 'balance_cache_$coin');
      if (cached != null) {
        return double.tryParse(cached) ?? 0.0;
      }
      return 0.0;
    } catch (e) {
      _logger.e('Failed to get cached balance: $e');
      return 0.0;
    }
  }
  
  /// Clear all swap adjustments (for testing/reset)
  Future<void> clearSwapAdjustments() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();
      for (final key in allKeys) {
        if (key.startsWith('swap_adjustment_')) {
          await prefs.remove(key);
        }
      }
      await prefs.remove('swap_history');
      _logger.i('Cleared all swap adjustments');
    } catch (e) {
      _logger.e('Failed to clear swap adjustments: $e');
    }
  }
}