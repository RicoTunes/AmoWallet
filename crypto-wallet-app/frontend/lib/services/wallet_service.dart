import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logger/logger.dart';
import 'bip39_wallet.dart';
import 'blockchain_service.dart';
import '../core/config/api_config.dart';

class WalletService {
  final Dio _dio;
  final dynamic _storage;
  final Logger _logger;
  SharedPreferences? _prefs;

  /// WalletService constructor. Optional dependencies may be injected for testing.
  WalletService({Dio? dio, dynamic storage, Logger? logger})
      : _dio = dio ?? Dio(BaseOptions(
          baseUrl: '${ApiConfig.baseUrl}/api/wallet',
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        )),
        _storage = storage ?? (kIsWeb || !Platform.isAndroid ? null : const FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: true),
        )),
        _logger = logger ?? Logger();

  /// Get shared preferences instance for web/fallback storage
  Future<SharedPreferences> _getPrefs() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  // --------------- Safe storage wrappers (web = SharedPreferences, mobile = FlutterSecureStorage) ---------------

  Future<Map<String, String>> _safeReadAll() async {
    if (kIsWeb || _storage == null) {
      final prefs = await _getPrefs();
      return prefs.getKeys().fold<Map<String, String>>({}, (map, key) {
        final v = prefs.get(key);
        if (v != null) map[key] = v.toString();
        return map;
      });
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
      _logger.w('Secure storage readAll failed, falling back to SharedPreferences: $e');
      final prefs = await _getPrefs();
      return prefs.getKeys().fold<Map<String, String>>({}, (map, key) {
        final v = prefs.get(key);
        if (v != null) map[key] = v.toString();
        return map;
      });
    }
  }

  Future<String?> _safeRead(String key) async {
    if (kIsWeb || _storage == null) {
      final prefs = await _getPrefs();
      return prefs.get(key)?.toString();
    }
    try {
      return await _storage.read(key: key);
    } catch (e) {
      _logger.w('Secure storage read failed for $key, falling back: $e');
      final prefs = await _getPrefs();
      return prefs.get(key)?.toString();
    }
  }

  Future<void> _safeWrite(String key, String value) async {
    if (kIsWeb || _storage == null) {
      final prefs = await _getPrefs();
      await prefs.setString(key, value);
      return;
    }
    try {
      await _storage.write(key: key, value: value);
    } catch (e) {
      _logger.w('Secure storage write failed for $key, falling back: $e');
      final prefs = await _getPrefs();
      await prefs.setString(key, value);
    }
  }

  Future<void> _safeDelete(String key) async {
    if (kIsWeb || _storage == null) {
      final prefs = await _getPrefs();
      await prefs.remove(key);
      return;
    }
    try {
      await _storage.delete(key: key);
    } catch (e) {
      _logger.w('Secure storage delete failed for $key: $e');
    }
  }

  /// Store wallet credentials in the format expected by getBalances()
  Future<void> storeWalletCredentials(String chain, String address, String? privateKey, String? mnemonic) async {
    try {
      if (kIsWeb || _storage == null) {
        // Web platform - use SharedPreferences
        final prefs = await _getPrefs();
        if (privateKey != null) {
          await prefs.setString('${chain}_${address}_private', privateKey);
        }
        if (mnemonic != null) {
          await prefs.setString('${chain}_${address}_mnemonic', mnemonic);
        }
        await prefs.setString('${chain}_${address}_meta', DateTime.now().toIso8601String());
      } else {
        // Mobile platform - use secure storage
        if (privateKey != null) {
          await _safeWrite('${chain}_${address}_private', privateKey);
        }
        if (mnemonic != null) {
          await _safeWrite('${chain}_${address}_mnemonic', mnemonic);
        }
        await _safeWrite('${chain}_${address}_meta', DateTime.now().toIso8601String());
      }
      _logger.i('✅ Stored credentials for $chain wallet: $address');
    } catch (e) {
      _logger.e('❌ Failed to store wallet credentials: $e');
      rethrow;
    }
  }

  /// Generate a blockchain-specific address for the given chain.
  /// preferLocal: try to generate locally (BIP39/BIP44) for supported chains (ETH, BTC, TRX, BNB, LTC, XRP, DOGE, SOL).
  Future<Map<String, String>> generateAddressFor(String chain, {bool preferLocal = true}) async {
    try {
      final uc = chain.toUpperCase();
      _logger.i('🔧 generateAddressFor called with chain: $chain (uppercase: $uc), preferLocal: $preferLocal');

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
      _logger.i('🔧 Backend chain resolved to: $backendChain');

      if (preferLocal && (backendChain == 'ETH' || backendChain == 'BTC' || backendChain == 'TRX' || backendChain == 'BNB' || backendChain == 'LTC' || backendChain == 'XRP' || backendChain == 'DOGE' || backendChain == 'SOL')) {
        _logger.i('🔧 Attempting local generation for $backendChain');
        try {
          final local = await Bip39Wallet.generate(chain: backendChain);

          final address = local['address']!;
          final privateKey = local['privateKey'];
          final mnemonic = local['mnemonic'];

          _logger.i('🔧 Local generation succeeded: address=$address, privateKey=${privateKey != null ? "present" : "absent"}, mnemonic=${mnemonic != null ? "present" : "absent"}');

          // Store generated secrets locally only
          if (privateKey != null) {
            await _safeWrite('${chain}_${address}_private', privateKey);
          }
          if (mnemonic != null) {
            await _safeWrite('${chain}_${address}_mnemonic', mnemonic);
          }

          final result = <String, String>{'address': address};
          if (privateKey != null) result['privateKey'] = privateKey;
          if (mnemonic != null) result['mnemonic'] = mnemonic;
          _logger.i('🔧 Returning local generation result');
          return result;
        } catch (e) {
          _logger.w('🔧 Local generation failed for $chain, falling back to backend: $e');
        }
      } else {
        _logger.i('🔧 Local generation not attempted (preferLocal=$preferLocal, backendChain=$backendChain not in supported list)');
      }

      _logger.i('🔧 Calling backend API at ${_dio.options.baseUrl}/generate with chain: $backendChain');
      final response = await _dio.post('/generate', queryParameters: {'chain': backendChain});
      final data = response.data;
      _logger.i('🔧 Backend response status: ${response.statusCode}, data type: ${data.runtimeType}');

      if (data == null || data is! Map) {
        _logger.e('🔧 Invalid response from backend: $data');
        throw Exception('Invalid response from backend');
      }

      final address = data['address']?.toString();
      final privateKey = data['privateKey']?.toString();
      final mnemonic = data['mnemonic']?.toString();

      _logger.i('🔧 Parsed from backend: address=$address, privateKey=${privateKey != null ? "present" : "absent"}, mnemonic=${mnemonic != null ? "present" : "absent"}');

      if (address == null) {
        _logger.e('🔧 Missing address in backend response');
        throw Exception('Missing address in response');
      }

      if (privateKey != null) {
        await _safeWrite('${chain}_${address}_private', privateKey);
        if (mnemonic != null) {
          await _safeWrite('${chain}_${address}_mnemonic', mnemonic);
        }
        _logger.i('🔧 Stored private key and mnemonic for $chain address $address');
      } else {
        await _safeWrite('${chain}_${address}_meta', DateTime.now().toIso8601String());
        _logger.i('🔧 Stored meta marker for $chain address $address (no private key)');
      }

      final result = <String, String>{'address': address};
      if (privateKey != null) result['privateKey'] = privateKey;
      if (mnemonic != null) result['mnemonic'] = mnemonic;
      _logger.i('🔧 Returning backend generation result');
      return result;
    } catch (e) {
      _logger.e('🔧 Failed to generate address for $chain: $e');
      rethrow;
    }
  }

  /// Get the list of stored addresses for a given chain
  /// Handles token aliases (USDT-ERC20 uses ETH addresses, USDT-BEP20 uses BNB addresses, etc.)
  Future<List<String>> getStoredAddresses(String chain) async {
    try {
      final rawKeys = await _safeReadAll();
      final addresses = <String>{};
      
      // Normalize chain to uppercase for matching (storage keys use uppercase)
      final normalizedChain = chain.toUpperCase();
      
      // Map tokens to their underlying chain
      String lookupChain = normalizedChain;
      if (normalizedChain.startsWith('USDT-') || normalizedChain.startsWith('USDC-')) {
        if (normalizedChain.contains('TRC20')) {
          lookupChain = 'TRX';
        } else if (normalizedChain.contains('BEP20')) {
          lookupChain = 'BNB';
        } else if (normalizedChain.contains('ERC20')) {
          lookupChain = 'ETH';
        }
      } else if (normalizedChain == 'USDT' || normalizedChain == 'USDC') {
        // Default to ETH for plain USDT/USDC
        lookupChain = 'ETH';
      }
      
      // Handle type casting carefully for web compatibility
      for (final entry in rawKeys.entries) {
        {
          final k = entry.key;
          final kUpper = k.toUpperCase();
          
          // First try exact chain match (case-insensitive)
          if (kUpper.startsWith('${normalizedChain}_')) {
            _parseAndAddAddress(k, normalizedChain, addresses);
          }
          
          // Then try mapped chain if different
          if (lookupChain != normalizedChain && kUpper.startsWith('${lookupChain}_')) {
            _parseAndAddAddress(k, lookupChain, addresses);
          }
        }
      }
      
      debugPrint('🔍 getStoredAddresses($chain) → normalized: $normalizedChain, lookup: $lookupChain → found: $addresses');
      return addresses.toList();
    } catch (e) {
      _logger.e('Failed to get stored addresses: $e');
      return [];
    }
  }
  
  void _parseAndAddAddress(String key, String chain, Set<String> addresses) {
    // Case-insensitive check since storage keys might be lowercase
    if (!key.toUpperCase().startsWith('${chain}_')) return;
    
    // Key format: CHAIN_ADDRESS_SUFFIX
    // We need to extract the address carefully because addresses can vary in format
    final suffixes = ['_private', '_meta', '_mnemonic'];
    String? suffix;
    for (final s in suffixes) {
      if (key.endsWith(s)) {
        suffix = s;
        break;
      }
    }
    if (suffix == null) return;
    
    // Find the first underscore to skip chain prefix
    final firstUnderscore = key.indexOf('_');
    if (firstUnderscore == -1) return;
    
    // Remove chain prefix and suffix to get address
    final withoutChain = key.substring(firstUnderscore + 1); // +1 for the underscore
    final address = withoutChain.substring(0, withoutChain.length - suffix.length);
    
    if (address.isNotEmpty) {
      addresses.add(address);
    }
  }

  /// Get the private key for a given address
  Future<String?> getPrivateKey(String chain, String address) async {
    try {
      return await _safeRead('${chain}_${address}_private');
    } catch (e) {
      _logger.e('Failed to get private key: $e');
      return null;
    }
  }

  /// Get the mnemonic phrase for a given address
  Future<String?> getMnemonic(String chain, String address) async {
    try {
      return await _safeRead('${chain}_${address}_mnemonic');
    } catch (e) {
      _logger.e('Failed to get mnemonic: $e');
      return null;
    }
  }

  /// Scan ALL storage locations (secure storage + SharedPreferences) and return
  /// the first mnemonic found, regardless of which chain it belongs to.
  /// This is robust against wallets created on any chain.
  Future<String?> findAnyMnemonic() async {
    try {
      // 1. Try secure storage (mobile)
      try {
        final rawKeys = await _safeReadAll();
        if (rawKeys.isNotEmpty) {
          for (final entry in rawKeys.entries) {
            final key = entry.key;
            final value = entry.value;
            if (key.endsWith('_mnemonic') && value.trim().isNotEmpty) {
              // Validate it looks like a BIP39 mnemonic (12 or 24 words)
              final wordCount = value.trim().split(RegExp(r'\s+')).length;
              if (wordCount == 12 || wordCount == 24) {
                _logger.i('✅ Found mnemonic in secure storage key: $key ($wordCount words)');
                return value.trim();
              }
            }
          }
        }
      } catch (e) {
        _logger.w('Secure storage readAll failed in findAnyMnemonic: $e');
      }

      // 2. Fallback: SharedPreferences (web or if secure storage failed)
      try {
        final prefs = await _getPrefs();
        for (final key in prefs.getKeys()) {
          if (key.endsWith('_mnemonic')) {
            final value = prefs.getString(key) ?? '';
            if (value.trim().isNotEmpty) {
              final wordCount = value.trim().split(RegExp(r'\s+')).length;
              if (wordCount == 12 || wordCount == 24) {
                _logger.i('✅ Found mnemonic in SharedPreferences key: $key ($wordCount words)');
                return value.trim();
              }
            }
          }
        }
      } catch (e) {
        _logger.w('SharedPreferences scan failed in findAnyMnemonic: $e');
      }

      _logger.w('⚠️ No mnemonic found in any storage');
      return null;
    } catch (e) {
      _logger.e('findAnyMnemonic error: $e');
      return null;
    }
  }

  /// Mark that the user has completed the backup verification process
  Future<void> markBackupCompleted() async {
    try {
      await _safeWrite('backup_completed', 'true');
      _logger.i('Backup marked as completed');
    } catch (e) {
      _logger.e('Failed to mark backup completed: $e');
      rethrow;
    }
  }

  /// Check if the user has completed backup verification
  Future<bool> isBackupCompleted() async {
    try {
      final value = await _safeRead('backup_completed');
      return value == 'true';
    } catch (e) {
      _logger.e('Failed to check backup status: $e');
      return false;
    }
  }

  /// Delete all stored keys for an address
  Future<void> deleteAddress(String chain, String address) async {
    try {
      await _safeDelete('${chain}_${address}_private');
      await _safeDelete('${chain}_${address}_mnemonic');
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

  // ------------------ Audit helpers ------------------

  Future<void> recordRevealEvent(String chain, String address, bool success) async {
    try {
      final raw = await _safeRead('reveal_audit');
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
      await _safeWrite('reveal_audit', json.encode(entries));
    } catch (e) {
      _logger.w('Failed to record reveal event: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getRevealAudit() async {
    try {
      final raw = await _safeRead('reveal_audit');
      if (raw == null) return [];
      final parsed = json.decode(raw) as List;
      return parsed.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e) {
      _logger.w('Failed to read reveal audit: $e');
      return [];
    }
  }

  /// Try every known storage location to find a valid BIP39 mnemonic.
  /// Order: secure storage chain keys → AuthService 'mnemonic' key → SharedPreferences brute-scan.
  Future<String?> _recoverMnemonicFromAnyStorage() async {
    // 1. Try findAnyMnemonic (scans chain-keyed entries)
    final m1 = await findAnyMnemonic();
    if (m1 != null) return m1;

    // 2. Try the AuthService plain 'mnemonic' key
    try {
      final prefs = await _getPrefs();
      final m2 = prefs.getString('mnemonic');
      if (m2 != null && m2.trim().isNotEmpty) {
        final words = m2.trim().split(RegExp(r'\s+'));
        if (words.length == 12 || words.length == 24) {
          debugPrint('✅ Found mnemonic in AuthService SharedPreferences key');
          return m2.trim();
        }
      }
    } catch (_) {}

    // 3. Secure storage 'mnemonic' key (mobile only)
    if (!kIsWeb && _storage != null) {
      try {
        final m3 = await _storage.read(key: 'mnemonic');
        if (m3 != null && m3.trim().isNotEmpty) {
          final words = m3.trim().split(RegExp(r'\s+'));
          if (words.length == 12 || words.length == 24) {
            debugPrint('✅ Found mnemonic in secure storage "mnemonic" key');
            return m3.trim();
          }
        }
      } catch (_) {}
    }

    return null;
  }

  /// Derive addresses for all supported chains from a mnemonic, store them,
  /// and populate [addressesByChain] in-place.
  Future<void> _deriveAndStoreAllChains(
      String mnemonic, Map<String, Set<String>> addressesByChain) async {
    const chains = ['BTC', 'ETH', 'BNB', 'SOL', 'TRX', 'LTC', 'DOGE', 'XRP'];
    for (final chain in chains) {
      try {
        final wallet = await Bip39Wallet.restore(mnemonic: mnemonic, chain: chain);
        final address = wallet['address'];
        final privateKey = wallet['privateKey'];
        if (address != null && address.isNotEmpty) {
          await storeWalletCredentials(chain, address, privateKey, mnemonic);
          addressesByChain.putIfAbsent(chain, () => {}).add(address);
          debugPrint('🔄 Auto-restored $chain: $address');
        }
      } catch (e) {
        debugPrint('⚠️ Could not restore $chain from mnemonic: $e');
      }
    }
  }

  /// Get balances for all stored addresses across all chains
  /// Incorporates swap adjustments from local storage
  Future<Map<String, double>> getBalances() async {
    try {
      final balances = <String, double>{};
      
      // Define valid blockchain chains - expanded to include more chains and tokens
      const validChains = {
        'BTC', 'ETH', 'BNB', 'USDT', 'TRX', 'XRP', 'SOL', 'LTC', 'DOGE',
        'POLYGON', 'ARBITRUM', 'OPTIMISM', 'AVALANCHE', 'ONT', 'MATIC',
        'USDC', 'DAI', 'BUSD', 'WBTC', 'SHIB', 'ADA', 'DOT', 'AVAX', 'FTM',
        'USDT-ERC20', 'USDT-BEP20', 'USDT-TRC20', 'USDC-ERC20', 'USDC-BEP20'
      };
      
      // Get all stored addresses across all chains
      final allKeys = await _safeReadAll();

      debugPrint('🔑 Total keys in storage: ${allKeys.length}');
      
      // Debug: print all keys to understand storage structure
      for (final k in allKeys.keys) {
        if (k.contains('_private') || k.contains('_meta')) {
          debugPrint('🔑 Key: $k');
        }
      }
      
      final addressesByChain = <String, Set<String>>{};
      
      for (final k in allKeys.keys) {
        // Keys are stored as: CHAIN_ADDRESS_TYPE (e.g., ETH_0x123..._private)
        // We need to find keys that end with _private or _meta
        if (!k.endsWith('_private') && !k.endsWith('_meta') && !k.endsWith('_mnemonic')) {
          continue;
        }
        
        // Remove the suffix to get CHAIN_ADDRESS
        String keyWithoutSuffix = k;
        if (k.endsWith('_private')) {
          keyWithoutSuffix = k.substring(0, k.length - 8); // Remove '_private'
        } else if (k.endsWith('_meta')) {
          keyWithoutSuffix = k.substring(0, k.length - 5); // Remove '_meta'
        } else if (k.endsWith('_mnemonic')) {
          keyWithoutSuffix = k.substring(0, k.length - 9); // Remove '_mnemonic'
        }
        
        // Find the first underscore to separate chain from address
        final firstUnderscore = keyWithoutSuffix.indexOf('_');
        if (firstUnderscore == -1) continue;
        
        final chain = keyWithoutSuffix.substring(0, firstUnderscore);
        final address = keyWithoutSuffix.substring(firstUnderscore + 1);
        
        // Normalize chain to uppercase for validation
        final normalizedChain = chain.toUpperCase();
        
        // Only process valid blockchain chains (case-insensitive)
        if (!validChains.contains(normalizedChain)) {
          debugPrint('⚠️ Skipping invalid chain: $chain (normalized: $normalizedChain)');
          continue;
        }
        
        // Use normalized chain for further processing
        final processingChain = normalizedChain;
        
        // Validate address format
        if (address.isEmpty) {
          debugPrint('⚠️ Empty address for chain: $chain');
          continue;
        }
        
        debugPrint('📍 Found wallet: $processingChain - ${address.length > 20 ? "${address.substring(0, 10)}...${address.substring(address.length - 6)}" : address}');
        addressesByChain.putIfAbsent(processingChain, () => {}).add(address);
      }
      
      debugPrint('💼 Wallets by chain: ${addressesByChain.length} chains - $addressesByChain');
      
      if (addressesByChain.isEmpty) {
        debugPrint('⚠️ No wallets found in storage — attempting auto-recovery from mnemonic...');
        // Auto-recovery: derive all chain addresses from stored mnemonic
        final mnemonic = await _recoverMnemonicFromAnyStorage();
        if (mnemonic != null) {
          await _deriveAndStoreAllChains(mnemonic, addressesByChain);
          debugPrint('✅ Auto-recovered ${addressesByChain.length} chains from mnemonic');
        }
        if (addressesByChain.isEmpty) {
          debugPrint('❌ Auto-recovery failed — no mnemonic found anywhere');
          return {};
        }
      }
      
      // Query balance for each address using blockchain service - IN PARALLEL for speed
      final blockchainService = BlockchainService();
      
      // Create list of futures for parallel execution
      final balanceFutures = <Future<MapEntry<String, double>>>[];
      
      for (final chain in addressesByChain.keys) {
        for (final address in addressesByChain[chain]!) {
          balanceFutures.add(
            _fetchBalanceWithTimeout(blockchainService, chain, address)
          );
        }
      }
      
      // Execute all balance fetches in parallel with 10 second timeout
      final results = await Future.wait(balanceFutures);
      
      // Aggregate results by chain
      for (final entry in results) {
        final chain = entry.key;
        final balance = entry.value;
        if (balance > 0) {
          balances[chain] = (balances[chain] ?? 0.0) + balance;
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
        debugPrint('💱 Applied swap adjustment for $coin: $current + $adjustment = $adjusted');
      }
      
      debugPrint('💰 Total balances (with swaps): $balances');
      return balances;
    } catch (e) {
      debugPrint('❌ Failed to get balances: $e');
      _logger.e('Failed to get balances: $e');
      return {};
    }
  }
  
  /// Fetch balance with timeout to prevent slow chains from blocking
  Future<MapEntry<String, double>> _fetchBalanceWithTimeout(
    BlockchainService blockchainService, 
    String chain, 
    String address
  ) async {
    try {
      debugPrint('🔍 Fetching balance for $chain $address');
      final balance = await blockchainService.getBalance(chain, address)
          .timeout(const Duration(seconds: 8), onTimeout: () {
        debugPrint('⏱️ Timeout fetching $chain balance');
        return 0.0;
      });
      debugPrint('✅ Balance for $chain $address: $balance');
      return MapEntry(chain, balance);
    } catch (e) {
      debugPrint('❌ Failed to get balance for $chain $address: $e');
      _logger.w('Failed to get balance for $chain $address: $e');
      return MapEntry(chain, 0.0);
    }
  }
  
  /// Get swap balance adjustments from SharedPreferences (persists on web)
  Future<Map<String, double>> _getSwapBalanceAdjustments() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final adjustments = <String, double>{};
      
      // Get all keys and filter swap adjustments
      final allKeys = prefs.getKeys();
      debugPrint('🔍 SharedPreferences keys: ${allKeys.length} total');
      debugPrint('🔍 All keys: $allKeys');
      
      for (final key in allKeys) {
        if (key.startsWith('swap_adjustment_')) {
          final coin = key.replaceFirst('swap_adjustment_', '');
          final value = prefs.getDouble(key) ?? 0.0;
          debugPrint('💱 Found swap adjustment: $key = $value');
          if (value != 0.0) {
            adjustments[coin] = value;
          }
        }
      }
      
      debugPrint('📊 Total swap adjustments found: $adjustments');
      return adjustments;
    } catch (e) {
      debugPrint('❌ Failed to get swap adjustments: $e');
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
      debugPrint('✅ Swap recorded: $fromAmount $fromCoin → $toAmount $toCoin (fee: $fee)');
      debugPrint('📊 New adjustments: $fromBase=$newFromAdj, $toBase=$newToAdj');
      debugPrint('💾 Swap saved to SharedPreferences (persists on restart)');
    } catch (e) {
      _logger.e('Failed to record swap transaction: $e');
      debugPrint('❌ Failed to record swap: $e');
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
      debugPrint('❌ Failed to load swap history: $e');
      return [];
    }
  }

  /// Get cached balance for a coin
  Future<double> getCachedBalance(String coin) async {
    try {
      final cached = await _safeRead('balance_cache_$coin');
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
