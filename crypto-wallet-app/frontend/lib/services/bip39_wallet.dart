import 'dart:typed_data';
import 'package:bip39/bip39.dart' as bip39;
import 'package:bip32/bip32.dart' as bip32;
import 'package:web3dart/web3dart.dart';
// web3crypto not required directly; web3dart provides helpers used below
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/digests/ripemd160.dart';
import 'package:bitcoin_base/bitcoin_base.dart';

/// Minimal local BIP39/BIP44 wallet helper for ETH, BTC, TRON (TRX), BSC (BNB), LTC, XRP, DOGE, and SOL
/// - Generates a mnemonic (BIP39)
/// - Derives BIP44 account private key for ETH (m/44'/60'/0'/0/0), BTC (m/44'/0'/0'/0/0),
///   TRX (m/44'/195'/0'/0/0), BSC (m/44'/60'/0'/0/0), LTC (m/44'/2'/0'/0/0), XRP (m/44'/144'/0'/0/0), DOGE (m/44'/3'/0'/0/0), SOL (m/44'/501'/0'/0')
/// - Returns address, privateKey (hex, with 0x for ETH/TRX/BNB), and mnemonic
class Bip39Wallet {
  /// Generate a new mnemonic and derive keys for the provided chain.
  /// Supported chains: 'ETH', 'BTC', 'TRX', 'BNB', 'LTC', 'XRP', 'DOGE', 'SOL' (case-insensitive).
  static Future<Map<String, String>> generate({required String chain}) async {
    final uc = chain.toUpperCase();
    final mnemonic = bip39.generateMnemonic();

    // bip39.mnemonicToSeed returns Uint8List
    final seed = bip39.mnemonicToSeed(mnemonic);

    final root = bip32.BIP32.fromSeed(seed);

    if (uc == 'ETH' || uc == 'BNB') {
      // Both ETH and BSC (BNB) use the same derivation path since BSC is EVM-compatible
      final path = "m/44'/60'/0'/0/0";
      final child = root.derivePath(path);
      final priv = child.privateKey;
      if (priv == null) throw Exception('Failed to derive $uc private key');
      final privHex = bytesToHex(priv);

      // web3dart EthPrivateKey wants a hex string with or without 0x
      final ethCred = EthPrivateKey.fromHex(privHex);
      final address = ethCred.address.hexEip55;

      return {
        'address': address,
        'privateKey': '0x$privHex',
        'mnemonic': mnemonic,
      };
    } else if (uc == 'BTC') {
      // Use BIP84 path for native SegWit (bc1 addresses)
      final path = "m/84'/0'/0'/0/0";
      final child = root.derivePath(path);
      final priv = child.privateKey;
      if (priv == null) {
        throw Exception('Failed to derive BTC keys');
      }

      final privHex = bytesToHex(priv);
      
      // Use bitcoin_base to generate native SegWit (P2WPKH) address
      final ecPrivate = ECPrivate.fromBytes(priv);
      final ecPublic = ecPrivate.getPublic();
      
      // Generate native SegWit (bc1) address
      final segwitAddress = ecPublic.toSegwitAddress();
      final address = segwitAddress.toAddress(BitcoinNetwork.mainnet);

      return {
        'address': address,
        'privateKey': privHex,
        'mnemonic': mnemonic,
      };
    } else if (uc == 'TRX' || uc == 'TRON') {
      // Tron uses coin type 195. The address bytes are the same as Ethereum's (last 20 bytes
      // of keccak(pubkey)) but with a 0x41 prefix and Base58Check encoding.
      final path = "m/44'/195'/0'/0/0";
      final child = root.derivePath(path);
      final priv = child.privateKey;
      if (priv == null) throw Exception('Failed to derive TRX private key');
      final privHex = bytesToHex(priv);

      // Use web3dart to get the Ethereum-style address bytes (20 bytes)
    final ethCred = EthPrivateKey.fromHex(privHex);
    final ethAddress = ethCred.address.hex; // 0x-prefixed
      final ethHex = ethAddress.startsWith('0x') ? ethAddress.substring(2) : ethAddress;
      final ethBytes = hexToBytes(ethHex);

      // Tron payload: 0x41 + ethAddressBytes
      final payload = Uint8List(1 + ethBytes.length);
      payload[0] = 0x41;
      payload.setRange(1, payload.length, ethBytes);

      // Checksum = first 4 bytes of double SHA256
      final checksumFull = SHA256Digest().process(SHA256Digest().process(payload));
      final checksum = checksumFull.sublist(0, 4);

      final addressBytes = Uint8List(payload.length + 4);
      addressBytes.setRange(0, payload.length, payload);
      addressBytes.setRange(payload.length, addressBytes.length, checksum);

      final address = _base58Encode(addressBytes);

      return {
        'address': address,
        'privateKey': '0x$privHex',
        'mnemonic': mnemonic,
      };
    } else if (uc == 'LTC') {
      // Litecoin uses coin type 2, same derivation as BTC but different address prefix
      final path = "m/44'/2'/0'/0/0";
      final child = root.derivePath(path);
      final priv = child.privateKey;
      final pub = child.publicKey;
      if (priv == null) {
        throw Exception('Failed to derive LTC keys');
      }

      // Compute P2PKH address for Litecoin (version byte 0x30 for mainnet)
      final sha256 = SHA256Digest().process(pub);
      final ripemd = RIPEMD160Digest().process(sha256);

      // Prepend version byte 0x30 for Litecoin mainnet
      final payload = Uint8List(ripemd.length + 1);
      payload[0] = 0x30;
      payload.setRange(1, payload.length, ripemd);

      // Checksum = first 4 bytes of double SHA256
      final checksumFull = SHA256Digest().process(SHA256Digest().process(payload));
      final checksum = checksumFull.sublist(0, 4);

      final addressBytes = Uint8List(payload.length + 4);
      addressBytes.setRange(0, payload.length, payload);
      addressBytes.setRange(payload.length, addressBytes.length, checksum);

      final address = _base58Encode(addressBytes);
      final privHex = bytesToHex(priv);

      return {
        'address': address,
        'privateKey': privHex,
        'mnemonic': mnemonic,
      };
    } else if (uc == 'XRP') {
      // XRP uses coin type 144 (Ripple)
      final path = "m/44'/144'/0'/0/0";
      final child = root.derivePath(path);
      final priv = child.privateKey;
      final pub = child.publicKey;
      if (priv == null) {
        throw Exception('Failed to derive XRP keys');
      }

      // XRP address generation: SHA256 of public key, then RIPEMD160
      final sha256 = SHA256Digest().process(pub);
      final ripemd = RIPEMD160Digest().process(sha256);

      // XRP uses version byte 0x00 for mainnet
      final payload = Uint8List(ripemd.length + 1);
      payload[0] = 0x00;
      payload.setRange(1, payload.length, ripemd);

      // Checksum = first 4 bytes of double SHA256
      final checksumFull = SHA256Digest().process(SHA256Digest().process(payload));
      final checksum = checksumFull.sublist(0, 4);

      final addressBytes = Uint8List(payload.length + 4);
      addressBytes.setRange(0, payload.length, payload);
      addressBytes.setRange(payload.length, addressBytes.length, checksum);

      final address = _base58Encode(addressBytes);
      final privHex = bytesToHex(priv);

      return {
        'address': address,
        'privateKey': privHex,
        'mnemonic': mnemonic,
      };
    } else if (uc == 'DOGE') {
      // Dogecoin uses coin type 3
      final path = "m/44'/3'/0'/0/0";
      final child = root.derivePath(path);
      final priv = child.privateKey;
      final pub = child.publicKey;
      if (priv == null) {
        throw Exception('Failed to derive DOGE keys');
      }

      // Compute P2PKH address for Dogecoin (version byte 0x1E for mainnet)
      final sha256 = SHA256Digest().process(pub);
      final ripemd = RIPEMD160Digest().process(sha256);

      // Prepend version byte 0x1E for Dogecoin mainnet
      final payload = Uint8List(ripemd.length + 1);
      payload[0] = 0x1E;
      payload.setRange(1, payload.length, ripemd);

      // Checksum = first 4 bytes of double SHA256
      final checksumFull = SHA256Digest().process(SHA256Digest().process(payload));
      final checksum = checksumFull.sublist(0, 4);

      final addressBytes = Uint8List(payload.length + 4);
      addressBytes.setRange(0, payload.length, payload);
      addressBytes.setRange(payload.length, addressBytes.length, checksum);

      final address = _base58Encode(addressBytes);
      final privHex = bytesToHex(priv);

      return {
        'address': address,
        'privateKey': privHex,
        'mnemonic': mnemonic,
      };
    } else if (uc == 'SOL') {
      // Solana uses coin type 501 and Ed25519 curve
      final path = "m/44'/501'/0'/0'";
      final child = root.derivePath(path);
      final priv = child.privateKey;
      final pub = child.publicKey;
      if (priv == null) {
        throw Exception('Failed to derive SOL keys');
      }

      // Solana uses Ed25519 public keys directly as addresses (Base58 encoded)
      // The public key is 32 bytes for Ed25519
      final address = _base58Encode(pub);
      final privHex = bytesToHex(priv);

      return {
        'address': address,
        'privateKey': privHex,
        'mnemonic': mnemonic,
      };
    } else {
      throw Exception('Unsupported chain for local generation: $chain');
    }
  }

  /// Restore wallet from existing mnemonic phrase
  /// Returns address, privateKey, and mnemonic for the given chain
  static Future<Map<String, String>> restore({
    required String mnemonic,
    required String chain,
  }) async {
    // Validate mnemonic
    if (!bip39.validateMnemonic(mnemonic)) {
      throw Exception('Invalid mnemonic phrase');
    }

    final uc = chain.toUpperCase();
    
    // Use the mnemonic to derive keys (same logic as generate but with provided mnemonic)
    final seed = bip39.mnemonicToSeed(mnemonic);
    final root = bip32.BIP32.fromSeed(seed);

    if (uc == 'ETH' || uc == 'BNB') {
      final path = "m/44'/60'/0'/0/0";
      final child = root.derivePath(path);
      final priv = child.privateKey;
      if (priv == null) throw Exception('Failed to derive $uc private key');
      final privHex = bytesToHex(priv);

      final ethCred = EthPrivateKey.fromHex(privHex);
      final address = ethCred.address.hexEip55;

      return {
        'address': address,
        'privateKey': '0x$privHex',
        'mnemonic': mnemonic,
      };
    } else if (uc == 'BTC') {
      // Use BIP84 path for native SegWit (bc1 addresses)
      final path = "m/84'/0'/0'/0/0";
      final child = root.derivePath(path);
      final priv = child.privateKey;
      if (priv == null) {
        throw Exception('Failed to derive BTC keys');
      }

      final privHex = bytesToHex(priv);
      
      // Use bitcoin_base to generate native SegWit (P2WPKH) address
      final ecPrivate = ECPrivate.fromBytes(priv);
      final ecPublic = ecPrivate.getPublic();
      
      // Generate native SegWit (bc1) address
      final segwitAddress = ecPublic.toSegwitAddress();
      final address = segwitAddress.toAddress(BitcoinNetwork.mainnet);

      return {
        'address': address,
        'privateKey': privHex,
        'mnemonic': mnemonic,
      };
    } else if (uc == 'TRX' || uc == 'TRON') {
      final path = "m/44'/195'/0'/0/0";
      final child = root.derivePath(path);
      final priv = child.privateKey;
      if (priv == null) throw Exception('Failed to derive TRX private key');
      final privHex = bytesToHex(priv);

      final ethCred = EthPrivateKey.fromHex(privHex);
      final ethAddr = ethCred.address.hex;
      final ethBytes = hexToBytes(ethAddr);

      final payload = Uint8List(ethBytes.length + 1);
      payload[0] = 0x41;
      payload.setRange(1, payload.length, ethBytes);

      final checksumFull = SHA256Digest().process(SHA256Digest().process(payload));
      final checksum = checksumFull.sublist(0, 4);

      final addressBytes = Uint8List(payload.length + 4);
      addressBytes.setRange(0, payload.length, payload);
      addressBytes.setRange(payload.length, addressBytes.length, checksum);

      final address = _base58Encode(addressBytes);

      return {
        'address': address,
        'privateKey': '0x$privHex',
        'mnemonic': mnemonic,
      };
    } else {
      // For unsupported chains, throw an error
      throw Exception('Unsupported chain for wallet restore: $chain');
    }
  }

  static String bytesToHex(Uint8List bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static Uint8List hexToBytes(String hex) {
    final clean = hex.startsWith('0x') ? hex.substring(2) : hex;
    final out = Uint8List(clean.length ~/ 2);
    for (var i = 0; i < clean.length; i += 2) {
      out[i ~/ 2] = int.parse(clean.substring(i, i + 2), radix: 16);
    }
    return out;
  }

  /// Local Base58 (Bitcoin alphabet) encoder for Base58Check addresses.
  /// Handles leading zero bytes (converted to '1').
  static String _base58Encode(Uint8List bytes) {
    const alphabet = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

    // Count leading zeros.
    int zeros = 0;
    for (final b in bytes) {
      if (b == 0) {
        zeros++;
      } else {
        break;
      }
    }

    // Convert bytes to BigInt
    BigInt value = BigInt.zero;
    for (final b in bytes) {
      value = (value << 8) | BigInt.from(b);
    }

    // Build the Base58 string
    final chars = <int>[];
    while (value > BigInt.zero) {
      final divmod = value.remainder(BigInt.from(58));
      value = value ~/ BigInt.from(58);
      chars.add(divmod.toInt());
    }

    // Leading zeros become '1'
    final result = StringBuffer();
    for (int i = 0; i < zeros; i++) {
      result.write('1');
    }
    for (int i = chars.length - 1; i >= 0; i--) {
      result.write(alphabet[chars[i]]);
    }
    return result.toString();
  }
}

