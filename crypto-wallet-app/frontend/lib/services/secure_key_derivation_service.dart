import 'package:bip39/bip39.dart' as bip39;
import 'package:bip32/bip32.dart' as bip32;
import 'package:hex/hex.dart';
import 'package:web3dart/web3dart.dart';
import 'package:pointycastle/ecc/api.dart';
import 'package:pointycastle/ecc/curves/secp256k1.dart';
import 'package:crypto/crypto.dart';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure key derivation service
/// NEVER stores private keys, only encrypted mnemonics
/// Derives keys on-demand when needed for transactions
class SecureKeyDerivationService {
  static final SecureKeyDerivationService _instance = SecureKeyDerivationService._internal();
  factory SecureKeyDerivationService() => _instance;
  SecureKeyDerivationService._internal();

  // Configure Android options for better compatibility
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );
  
  static const String _mnemonicKey = 'encrypted_mnemonic';

  // BIP44 derivation paths for different cryptocurrencies
  static const Map<String, String> _derivationPaths = {
    'BTC': "m/44'/0'/0'/0/0",      // Bitcoin
    'ETH': "m/44'/60'/0'/0/0",     // Ethereum
    'BNB': "m/44'/714'/0'/0/0",    // Binance Chain
    'LTC': "m/44'/2'/0'/0/0",      // Litecoin
    'DOGE': "m/44'/3'/0'/0/0",     // Dogecoin
    'TRX': "m/44'/195'/0'/0/0",    // Tron
    'XRP': "m/44'/144'/0'/0/0",    // Ripple
    'SOL': "m/44'/501'/0'/0/0",    // Solana
  };

  /// Store encrypted mnemonic (only this is stored, never private keys)
  Future<void> storeMnemonic(String mnemonic) async {
    if (!bip39.validateMnemonic(mnemonic)) {
      throw Exception('Invalid mnemonic phrase');
    }
    
    // Store mnemonic in secure storage (encrypted by the OS)
    await _secureStorage.write(key: _mnemonicKey, value: mnemonic);
  }

  /// Retrieve mnemonic from secure storage
  Future<String?> getMnemonic() async {
    return await _secureStorage.read(key: _mnemonicKey);
  }

  /// Derive private key on-demand from mnemonic
  /// Private key is NEVER stored, only computed when needed
  Future<String> derivePrivateKey(String coin, {int accountIndex = 0, int addressIndex = 0}) async {
    final mnemonic = await getMnemonic();
    if (mnemonic == null) {
      throw Exception('No mnemonic found. Please create or restore a wallet first.');
    }

    // Validate mnemonic
    if (!bip39.validateMnemonic(mnemonic)) {
      throw Exception('Invalid mnemonic in storage');
    }

    // Generate seed from mnemonic
    final seed = bip39.mnemonicToSeed(mnemonic);

    // Get derivation path for the coin
    String path = _derivationPaths[coin] ?? "m/44'/60'/0'/0/0"; // Default to ETH path
    
    // Support custom account and address indices
    if (accountIndex != 0 || addressIndex != 0) {
      final pathParts = path.split('/');
      pathParts[pathParts.length - 2] = "$accountIndex'";
      pathParts[pathParts.length - 1] = addressIndex.toString();
      path = pathParts.join('/');
    }

    // Derive the key
    final root = bip32.BIP32.fromSeed(seed);
    final child = root.derivePath(path);

    // Return private key in hex format
    return HEX.encode(child.privateKey!);
  }

  /// Derive Ethereum wallet credentials on-demand
  /// Returns EthPrivateKey that can be used for signing
  Future<EthPrivateKey> deriveEthereumCredentials({int accountIndex = 0, int addressIndex = 0}) async {
    final privateKeyHex = await derivePrivateKey('ETH', accountIndex: accountIndex, addressIndex: addressIndex);
    final privateKeyBytes = HEX.decode(privateKeyHex);
    return EthPrivateKey.fromHex(HEX.encode(privateKeyBytes));
  }

  /// Get Ethereum address without exposing private key
  Future<String> getEthereumAddress({int accountIndex = 0, int addressIndex = 0}) async {
    final credentials = await deriveEthereumCredentials(accountIndex: accountIndex, addressIndex: addressIndex);
    return credentials.address.hex;
  }

  /// Get Bitcoin address (P2PKH format)
  Future<String> getBitcoinAddress({int accountIndex = 0, int addressIndex = 0}) async {
    final privateKeyHex = await derivePrivateKey('BTC', accountIndex: accountIndex, addressIndex: addressIndex);
    final privateKeyBytes = HEX.decode(privateKeyHex);
    
    // Get public key from private key
    final params = ECCurve_secp256k1();
    final privateKey = BigInt.parse(privateKeyHex, radix: 16);
    final publicKey = (params.G * privateKey) as ECPoint;
    
    // Compress public key
    final x = publicKey.x!.toBigInteger()!;
    final y = publicKey.y!.toBigInteger()!;
    final prefix = y.isEven ? 0x02 : 0x03;
    final xBytes = _bigIntToBytes(x, 32);
    final compressedPubKey = Uint8List.fromList([prefix, ...xBytes]);
    
    // Hash public key (SHA256 then RIPEMD160)
    final sha256Hash = sha256.convert(compressedPubKey).bytes;
    // Note: For production, use proper RIPEMD160
    // This is a simplified version - use a proper Bitcoin library
    
    return _encodeBase58Check(Uint8List.fromList([0x00, ...sha256Hash.sublist(0, 20)]));
  }

  /// Sign transaction data with derived private key (ephemeral - key not stored)
  Future<Uint8List> signEthereumTransaction({
    required String toAddress,
    required BigInt value,
    required BigInt gasPrice,
    required int gasLimit,
    required int nonce,
    String? data,
    int accountIndex = 0,
    int addressIndex = 0,
  }) async {
    final credentials = await deriveEthereumCredentials(
      accountIndex: accountIndex,
      addressIndex: addressIndex,
    );

    final transaction = Transaction(
      to: EthereumAddress.fromHex(toAddress),
      value: EtherAmount.inWei(value),
      gasPrice: EtherAmount.inWei(gasPrice),
      maxGas: gasLimit,
      nonce: nonce,
      data: data != null ? Uint8List.fromList(HEX.decode(data)) : null,
    );

    // Sign transaction using credentials
    // Note: In web3dart, transaction signing is done through Web3Client
    // Here we return the credentials and transaction for external signing
    final privateKeyHex = await derivePrivateKey('ETH', accountIndex: accountIndex, addressIndex: addressIndex);
    final privateKeyBytes = Uint8List.fromList(HEX.decode(privateKeyHex));
    
    // Return the private key bytes for use with Web3Client.sendTransaction
    return privateKeyBytes;
  }

  /// Clear mnemonic from storage (on logout)
  Future<void> clearMnemonic() async {
    await _secureStorage.delete(key: _mnemonicKey);
  }

  /// Check if mnemonic exists
  Future<bool> hasMnemonic() async {
    final mnemonic = await _secureStorage.read(key: _mnemonicKey);
    return mnemonic != null && mnemonic.isNotEmpty;
  }

  /// Verify mnemonic without exposing it
  Future<bool> verifyMnemonic(String mnemonic) async {
    final stored = await getMnemonic();
    return stored == mnemonic;
  }

  // Helper: Convert BigInt to bytes with padding
  Uint8List _bigIntToBytes(BigInt number, int length) {
    final hex = number.toRadixString(16).padLeft(length * 2, '0');
    return Uint8List.fromList(HEX.decode(hex));
  }

  // Helper: Base58Check encoding for Bitcoin addresses
  String _encodeBase58Check(Uint8List payload) {
    // Simplified - use proper Base58 library in production
    const alphabet = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
    
    // Add checksum
    final checksum = sha256.convert(sha256.convert(payload).bytes).bytes;
    final fullPayload = Uint8List.fromList([...payload, ...checksum.sublist(0, 4)]);
    
    // Convert to base58
    var num = BigInt.parse(HEX.encode(fullPayload), radix: 16);
    var encoded = '';
    
    while (num > BigInt.zero) {
      final remainder = (num % BigInt.from(58)).toInt();
      encoded = alphabet[remainder] + encoded;
      num = num ~/ BigInt.from(58);
    }
    
    // Add leading zeros
    for (var byte in fullPayload) {
      if (byte != 0) break;
      encoded = '1$encoded';
    }
    
    return encoded;
  }
}
