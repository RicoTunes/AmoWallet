import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:bip32/bip32.dart' as bip32;
import 'package:bip39/bip39.dart' as bip39;
import 'package:pointycastle/pointycastle.dart';
import 'package:web3dart/web3dart.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RealWalletService {
  static const String _storageKey = 'wallet_mnemonic';
  // Configure Android options for better compatibility
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );
  final SharedPreferences _prefs;

  RealWalletService(this._prefs);

  // BIP44 derivation paths for different coins
  static const Map<String, String> derivationPaths = {
    'BTC': "m/44'/0'/0'/0/0",
    'ETH': "m/44'/60'/0'/0/0",
    'BNB': "m/44'/714'/0'/0/0",
    'LTC': "m/44'/2'/0'/0/0",
    'DOGE': "m/44'/3'/0'/0/0",
    'TRX': "m/44'/195'/0'/0/0",
    'XRP': "m/44'/144'/0'/0/0",
    'SOL': "m/44'/501'/0'/0/0",
  };

  /// Generate a new wallet with a mnemonic phrase
  Future<Map<String, dynamic>> createNewWallet() async {
    try {
      // Generate a random mnemonic (12 words)
      final mnemonic = bip39.generateMnemonic();
      
      // Generate seed from mnemonic
      final seed = bip39.mnemonicToSeed(mnemonic);
      
      // Store mnemonic securely
      await _secureStorage.write(key: _storageKey, value: mnemonic);
      
      // Generate addresses for all supported coins
      final addresses = await _generateAllAddresses(mnemonic);
      
      return {
        'success': true,
        'mnemonic': mnemonic,
        'addresses': addresses,
        'message': 'Wallet created successfully'
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Failed to create wallet: $e'
      };
    }
  }

  /// Import wallet from existing mnemonic
  Future<Map<String, dynamic>> importWallet(String mnemonic) async {
    try {
      // Validate mnemonic
      if (!bip39.validateMnemonic(mnemonic)) {
        return {
          'success': false,
          'error': 'Invalid mnemonic phrase'
        };
      }

      // Store mnemonic securely
      await _secureStorage.write(key: _storageKey, value: mnemonic);
      
      // Generate addresses for all supported coins
      final addresses = await _generateAllAddresses(mnemonic);
      
      return {
        'success': true,
        'addresses': addresses,
        'message': 'Wallet imported successfully'
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Failed to import wallet: $e'
      };
    }
  }

  /// Generate addresses for all supported coins
  Future<Map<String, String>> _generateAllAddresses(String mnemonic) async {
    final seed = bip39.mnemonicToSeed(mnemonic);
    final root = bip32.BIP32.fromSeed(seed);
    
    final addresses = <String, String>{};
    
    for (final coin in derivationPaths.keys) {
      try {
        final path = derivationPaths[coin]!;
        final child = root.derivePath(path);
        
        switch (coin) {
          case 'BTC':
            addresses[coin] = _generateBitcoinAddress(child);
            break;
          case 'ETH':
            addresses[coin] = _generateEthereumAddress(child);
            break;
          case 'BNB':
            addresses[coin] = _generateEthereumAddress(child); // BSC uses same format as ETH
            break;
          case 'LTC':
            addresses[coin] = _generateLitecoinAddress(child);
            break;
          case 'DOGE':
            addresses[coin] = _generateDogecoinAddress(child);
            break;
          case 'TRX':
            addresses[coin] = _generateTronAddress(child);
            break;
          case 'XRP':
            addresses[coin] = _generateRippleAddress(child);
            break;
          case 'SOL':
            addresses[coin] = _generateSolanaAddress(child);
            break;
        }
      } catch (e) {
        print('Error generating address for $coin: $e');
      }
    }
    
    return addresses;
  }

  /// Generate Bitcoin address (P2PKH)
  String _generateBitcoinAddress(bip32.BIP32 key) {
    // For demo purposes, we'll generate a mock address
    // In production, use a proper Bitcoin address generation library
    final publicKey = key.publicKey;
    final hash = _sha256ripemd160(publicKey);
    return '1${_base58CheckEncode(hash, 0x00)}'.substring(0, 34);
  }

  /// Generate Ethereum address
  String _generateEthereumAddress(bip32.BIP32 key) {
    final publicKey = key.publicKey;
    // Take the last 20 bytes of the keccak256 hash of the public key
    final hash = _keccak256(publicKey.sublist(1)); // Remove compression byte
    final addressBytes = hash.sublist(12); // Last 20 bytes
    return '0x${_bytesToHex(addressBytes)}';
  }

  /// Generate Litecoin address
  String _generateLitecoinAddress(bip32.BIP32 key) {
    final publicKey = key.publicKey;
    final hash = _sha256ripemd160(publicKey);
    return 'L${_base58CheckEncode(hash, 0x30)}'.substring(0, 34);
  }

  /// Generate Dogecoin address
  String _generateDogecoinAddress(bip32.BIP32 key) {
    final publicKey = key.publicKey;
    final hash = _sha256ripemd160(publicKey);
    return 'D${_base58CheckEncode(hash, 0x1E)}'.substring(0, 34);
  }

  /// Generate Tron address
  String _generateTronAddress(bip32.BIP32 key) {
    final publicKey = key.publicKey;
    final hash = _keccak256(publicKey.sublist(1));
    final addressBytes = hash.sublist(12);
    final base58 = _base58CheckEncode(addressBytes, 0x41);
    return 'T$base58';
  }

  /// Generate Ripple address
  String _generateRippleAddress(bip32.BIP32 key) {
    final publicKey = key.publicKey;
    final hash = _sha256ripemd160(publicKey);
    return 'r${_base58CheckEncode(hash, 0x00)}'.substring(0, 34);
  }

  /// Generate Solana address
  String _generateSolanaAddress(bip32.BIP32 key) {
    final publicKey = key.publicKey;
    // Solana uses Ed25519, so we use the public key directly
    return _base58Encode(publicKey).substring(0, 44);
  }

  /// Get wallet addresses
  Future<Map<String, String>> getWalletAddresses() async {
    final mnemonic = await _secureStorage.read(key: _storageKey);
    if (mnemonic == null) {
      return {};
    }
    return await _generateAllAddresses(mnemonic);
  }

  /// Get specific coin address
  Future<String?> getAddress(String coin) async {
    final addresses = await getWalletAddresses();
    return addresses[coin];
  }

  /// Check if wallet exists
  Future<bool> walletExists() async {
    final mnemonic = await _secureStorage.read(key: _storageKey);
    return mnemonic != null;
  }

  /// Get mnemonic (for backup)
  Future<String?> getMnemonic() async {
    return await _secureStorage.read(key: _storageKey);
  }

  /// Delete wallet
  Future<void> deleteWallet() async {
    await _secureStorage.delete(key: _storageKey);
    await _prefs.clear();
  }

  // Utility functions for address generation

  String _bytesToHex(List<int> bytes) {
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  List<int> _sha256ripemd160(List<int> data) {
    final sha256 = Digest('SHA-256');
    final ripemd160 = Digest('RIPEMD-160');
    final sha256Hash = sha256.process(Uint8List.fromList(data));
    return ripemd160.process(sha256Hash);
  }

  List<int> _keccak256(List<int> data) {
    final digest = Digest('SHA-3/256');
    return digest.process(Uint8List.fromList(data));
  }

  String _base58CheckEncode(List<int> payload, int version) {
    final versioned = Uint8List.fromList([version, ...payload]);
    final checksum = _doubleSha256(versioned).sublist(0, 4);
    final combined = Uint8List.fromList([...versioned, ...checksum]);
    return _base58Encode(combined);
  }

  List<int> _doubleSha256(List<int> data) {
    final sha256 = Digest('SHA-256');
    final first = sha256.process(Uint8List.fromList(data));
    return sha256.process(first);
  }

  String _base58Encode(List<int> input) {
    const alphabet = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
    var number = BigInt.zero;
    
    for (var i = 0; i < input.length; i++) {
      number = number * BigInt.from(256) + BigInt.from(input[i]);
    }
    
    var result = '';
    while (number > BigInt.zero) {
      final remainder = number % BigInt.from(58);
      number = number ~/ BigInt.from(58);
      result = alphabet[remainder.toInt()] + result;
    }
    
    // Add leading '1's for each leading zero byte
    for (var i = 0; i < input.length && input[i] == 0; i++) {
      result = '1$result';
    }
    
    return result;
  }
}