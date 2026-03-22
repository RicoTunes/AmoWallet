import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logger/logger.dart';
import 'bip39_wallet.dart';
import 'blockchain_service.dart';
import 'rust_security_service.dart';
import '../core/config/api_config.dart';

class WalletService {
  final Dio _dio;
  final dynamic _storage;
  final Logger _logger;
  SharedPreferences? _prefs;

  /// WalletService constructor. Optional dependencies may be injected for testing.
  /// SECURITY: FlutterSecureStorage is ALWAYS used for private keys and mnemonics.
  /// SharedPreferences is ONLY used for non-sensitive metadata (swap history, etc.).
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

  /// Get shared preferences instance for web/fallback storage
  Future<SharedPreferences> _getPrefs() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  // --------------- Secure storage wrappers — NEVER fall back to SharedPreferences for keys ---------------

  Future<Map<String, String>> _safeReadAll() async {
    try {
      final dynamic raw = await _storage.readAll();
      if (raw is Map) {
        return Map<String, String>.from(
          raw.map((k, v) => MapEntry(k.toString(), v.toString())),
        );
      }
      return {};
    } catch (e) {
      _logger.e('Secure storage readAll failed: $e');
      return {};
    }
  }

  Future<String?> _safeRead(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (e) {
      _logger.e('Secure storage read failed for $key: $e');
      return null;
    }
  }

  Future<void> _safeWrite(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (e) {
      _logger.e('Secure storage write failed for $key: $e');
      rethrow;
    }
  }

  Future<void> _safeDelete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (e) {
      _logger.e('Secure storage delete failed for $key: $e');
    }
  }

  /// Store wallet credentials SECURELY — FlutterSecureStorage only.
  /// Private keys and mnemonics are NEVER written to SharedPreferences.
  Future<void> storeWalletCredentials(String chain, String address, String? privateKey, String? mnemonic) async {
    try {
      if (privateKey != null) {
        await _safeWrite('${chain}_${address}_private', privateKey);
      }
      if (mnemonic != null) {
        await _safeWrite('${chain}_${address}_mnemonic', mnemonic);
      }
      await _safeWrite('${chain}_${address}_meta', DateTime.now().toIso8601String());
      _logger.i('✅ Stored credentials for $chain wallet: $address (secure storage only)');
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
      // BEP20 tokens can use either BNB or ETH addresses (same EVM address)
      List<String> extraLookupChains = [];
      if (normalizedChain.startsWith('USDT-') || normalizedChain.startsWith('USDC-')) {
        if (normalizedChain.contains('TRC20')) {
          lookupChain = 'TRX';
        } else if (normalizedChain.contains('BEP20')) {
          lookupChain = 'BNB';
          extraLookupChains = ['ETH']; // EVM addresses are the same
        } else if (normalizedChain.contains('ERC20')) {
          lookupChain = 'ETH';
          extraLookupChains = ['BNB']; // EVM addresses are the same
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
          
          // Also try extra chains (e.g. ETH address for BEP20, BNB address for ERC20)
          for (final extra in extraLookupChains) {
            if (kUpper.startsWith('${extra}_')) {
              _parseAndAddAddress(k, extra, addresses);
            }
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

  /// Scan secure storage and return the first mnemonic found.
  /// SECURITY: Only reads from FlutterSecureStorage — never SharedPreferences.
  Future<String?> findAnyMnemonic() async {
    try {
      final rawKeys = await _safeReadAll();
      if (rawKeys.isNotEmpty) {
        for (final entry in rawKeys.entries) {
          final key = entry.key;
          final value = entry.value;
          if (key.endsWith('_mnemonic') && value.trim().isNotEmpty) {
            final wordCount = value.trim().split(RegExp(r'\s+')).length;
            if (wordCount == 12 || wordCount == 24) {
              _logger.i('✅ Found mnemonic in secure storage key: $key ($wordCount words)');
              return value.trim();
            }
          }
        }
      }

      _logger.w('⚠️ No mnemonic found in secure storage');
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

  /// Sign a message using the private key for the given chain and address.
  /// SECURITY: Private key is encrypted before sending to Rust for signing.
  Future<String> signMessage(String chain, String address, String message) async {
    try {
      final privateKey = await getPrivateKey(chain, address);
      if (privateKey == null) {
        throw Exception('Private key not found for this address');
      }

      // Encrypt private key before sending
      final rustSecurity = RustSecurityService();
      final encryptedKey = rustSecurity.encryptAesGcm(privateKey);

      final response = await _dio.post('/sign', data: {
        'chain': chain,
        'encrypted_key': encryptedKey,
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

  /// Try secure storage locations to find a valid BIP39 mnemonic.
  /// SECURITY: Only reads from FlutterSecureStorage.
  Future<String?> _recoverMnemonicFromAnyStorage() async {
    // 1. Try findAnyMnemonic (scans chain-keyed entries in secure storage)
    final m1 = await findAnyMnemonic();
    if (m1 != null) return m1;

    // 2. Try the plain 'mnemonic' key in secure storage
    try {
      final m3 = await _safeRead('mnemonic');
      if (m3 != null && m3.trim().isNotEmpty) {
        final words = m3.trim().split(RegExp(r'\s+'));
        if (words.length == 12 || words.length == 24) {
          debugPrint('✅ Found mnemonic in secure storage "mnemonic" key');
          return m3.trim();
        }
      }
    } catch (_) {}

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
      } else {
        // Some chains exist — fill in any missing ones from mnemonic silently
        const allChains = ['BTC', 'ETH', 'BNB', 'SOL', 'TRX', 'LTC', 'DOGE', 'XRP'];
        final missingChains = allChains.where((c) => !addressesByChain.containsKey(c)).toList();
        if (missingChains.isNotEmpty) {
          debugPrint('⚙️ ${missingChains.length} chains missing (${missingChains.join(", ")}) — deriving from mnemonic...');
          final mnemonic = await _recoverMnemonicFromAnyStorage();
          if (mnemonic != null) {
            for (final chain in missingChains) {
              try {
                final wallet = await Bip39Wallet.restore(mnemonic: mnemonic, chain: chain);
                final address = wallet['address'];
                final privateKey = wallet['privateKey'];
                if (address != null && address.isNotEmpty) {
                  await storeWalletCredentials(chain, address, privateKey, mnemonic);
                  addressesByChain.putIfAbsent(chain, () => {}).add(address);
                  debugPrint('🔄 Derived missing $chain: $address');
                }
              } catch (e) {
                debugPrint('⚠️ Could not derive $chain: $e');
              }
            }
          }
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
      
      // ── Fetch USDT token balances on each chain ──
      // Native chain balance fetches above don't include token balances.
      // We must explicitly query USDT on ERC20 (ETH), BEP20 (BNB), and TRC20 (TRX).
      final tokenFutures = <Future<MapEntry<String, double>>>[];
      
      final ethAddresses = addressesByChain['ETH'] ?? {};
      final bnbAddresses = addressesByChain['BNB'] ?? {};
      final trxAddresses = addressesByChain['TRX'] ?? {};
      
      for (final addr in ethAddresses) {
        tokenFutures.add(
          _fetchBalanceWithTimeout(blockchainService, 'USDT-ERC20', addr),
        );
      }
      for (final addr in bnbAddresses) {
        tokenFutures.add(
          _fetchBalanceWithTimeout(blockchainService, 'USDT-BEP20', addr),
        );
      }
      // BEP20 uses same address format as ETH — also check ETH addresses on BSC
      for (final addr in ethAddresses) {
        if (!bnbAddresses.contains(addr)) {
          tokenFutures.add(
            _fetchBalanceWithTimeout(blockchainService, 'USDT-BEP20', addr),
          );
        }
      }
      for (final addr in trxAddresses) {
        tokenFutures.add(
          _fetchBalanceWithTimeout(blockchainService, 'USDT-TRC20', addr),
        );
      }
      
      if (tokenFutures.isNotEmpty) {
        final tokenResults = await Future.wait(tokenFutures);
        double totalUsdt = 0.0;
        for (final entry in tokenResults) {
          if (entry.value > 0) {
            totalUsdt += entry.value;
            // Store per-chain USDT balance (e.g. USDT-BEP20, USDT-ERC20, USDT-TRC20)
            balances[entry.key] = (balances[entry.key] ?? 0.0) + entry.value;
            debugPrint('💵 USDT token balance on ${entry.key}: ${entry.value}');
          }
        }
        if (totalUsdt > 0) {
          balances['USDT'] = (balances['USDT'] ?? 0.0) + totalUsdt;
          debugPrint('💵 Total USDT from token queries: $totalUsdt');
        }
      }
      
      // One-time cleanup: purge any phantom swap adjustments from old simulated swaps
      await _purgeStaleSwapAdjustments();
      
      debugPrint('💰 Total balances (on-chain only): $balances');
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
  
  /// Purge stale swap adjustments (one-time migration)
  /// Old simulated swaps wrote fake balance adjustments that created phantom money
  Future<void> _purgeStaleSwapAdjustments() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('swap_adjustments_purged_v3') == true) return;
      
      final allKeys = prefs.getKeys().toList();
      int cleared = 0;
      for (final key in allKeys) {
        if (key.startsWith('swap_adjustment_') || key.startsWith('balance_cache_')) {
          await prefs.remove(key);
          cleared++;
        }
      }
      await prefs.remove('swap_history');
      // Clear stale cached balances that had phantom values baked in
      await prefs.remove('dashboard_cached_balances');
      await prefs.remove('pending_deductions');
      await prefs.setBool('swap_adjustments_purged_v3', true);
      debugPrint('🧹 Purged $cleared phantom swap adjustments + stale cached balances');
    } catch (e) {
      debugPrint('❌ Failed to purge swap adjustments: $e');
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
      debugPrint('� Swap saved to history (persists on restart)');
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
