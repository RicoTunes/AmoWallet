import 'dart:typed_data';
import 'package:bip39/bip39.dart' as bip39;
import 'package:bip32/bip32.dart' as bip32;
import 'package:web3dart/web3dart.dart';
// web3crypto not required directly; web3dart provides helpers used below
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/digests/ripemd160.dart';
import 'package:bitcoin_base/bitcoin_base.dart';
import 'package:flutter/foundation.dart' show compute;

/// Generate a new mnemonic and derive keys for the provided chain.
/// Top-level function required by compute() to run in a background isolate.
Map<String, String> _generateWalletSync(String chain) {
  final uc = chain.toUpperCase();
  final mnemonic = bip39.generateMnemonic();
  final seed = bip39.mnemonicToSeed(mnemonic);
  final root = bip32.BIP32.fromSeed(seed);

  if (uc == 'ETH' || uc == 'BNB') {
    final path = "m/44'/60'/0'/0/0";
    final child = root.derivePath(path);
    final priv = child.privateKey;
    if (priv == null) throw Exception('Failed to derive $uc private key');
    final privHex = Bip39Wallet.bytesToHex(priv);
    final ethCred = EthPrivateKey.fromHex(privHex);
    return {'address': ethCred.address.hexEip55, 'privateKey': '0x$privHex', 'mnemonic': mnemonic};
  } else if (uc == 'BTC') {
    final path = "m/84'/0'/0'/0/0";
    final child = root.derivePath(path);
    final priv = child.privateKey;
    if (priv == null) throw Exception('Failed to derive BTC keys');
    final privHex = Bip39Wallet.bytesToHex(priv);
    final ecPrivate = ECPrivate.fromBytes(priv);
    final ecPublic = ecPrivate.getPublic();
    final segwitAddress = ecPublic.toSegwitAddress();
    final address = segwitAddress.toAddress(BitcoinNetwork.mainnet);
    return {'address': address, 'privateKey': privHex, 'mnemonic': mnemonic};
  } else if (uc == 'TRX' || uc == 'TRON') {
    final path = "m/44'/195'/0'/0/0";
    final child = root.derivePath(path);
    final priv = child.privateKey;
    if (priv == null) throw Exception('Failed to derive TRX private key');
    final privHex = Bip39Wallet.bytesToHex(priv);
    final ethCred = EthPrivateKey.fromHex(privHex);
    final ethAddr = ethCred.address.hex;
    final ethHex = ethAddr.startsWith('0x') ? ethAddr.substring(2) : ethAddr;
    final ethBytes = Bip39Wallet.hexToBytes(ethHex);
    final payload = Uint8List(1 + ethBytes.length);
    payload[0] = 0x41;
    payload.setRange(1, payload.length, ethBytes);
    final checksumFull = SHA256Digest().process(SHA256Digest().process(payload));
    final checksum = checksumFull.sublist(0, 4);
    final addressBytes = Uint8List(payload.length + 4);
    addressBytes.setRange(0, payload.length, payload);
    addressBytes.setRange(payload.length, addressBytes.length, checksum);
    return {'address': Bip39Wallet._base58Encode(addressBytes), 'privateKey': '0x$privHex', 'mnemonic': mnemonic};
  } else if (uc == 'LTC') {
    final path = "m/44'/2'/0'/0/0";
    final child = root.derivePath(path);
    final priv = child.privateKey;
    final pub = child.publicKey;
    if (priv == null) throw Exception('Failed to derive LTC keys');
    final sha = SHA256Digest().process(pub);
    final rip = RIPEMD160Digest().process(sha);
    final pl = Uint8List(rip.length + 1)..[0] = 0x30;
    pl.setRange(1, pl.length, rip);
    final cs = SHA256Digest().process(SHA256Digest().process(pl)).sublist(0, 4);
    final ab = Uint8List(pl.length + 4);
    ab.setRange(0, pl.length, pl);
    ab.setRange(pl.length, ab.length, cs);
    return {'address': Bip39Wallet._base58Encode(ab), 'privateKey': Bip39Wallet.bytesToHex(priv), 'mnemonic': mnemonic};
  } else if (uc == 'XRP') {
    final path = "m/44'/144'/0'/0/0";
    final child = root.derivePath(path);
    final priv = child.privateKey;
    final pub = child.publicKey;
    if (priv == null) throw Exception('Failed to derive XRP keys');
    final sha = SHA256Digest().process(pub);
    final rip = RIPEMD160Digest().process(sha);
    final pl = Uint8List(rip.length + 1)..[0] = 0x00;
    pl.setRange(1, pl.length, rip);
    final cs = SHA256Digest().process(SHA256Digest().process(pl)).sublist(0, 4);
    final ab = Uint8List(pl.length + 4);
    ab.setRange(0, pl.length, pl);
    ab.setRange(pl.length, ab.length, cs);
    return {'address': Bip39Wallet._base58Encode(ab), 'privateKey': Bip39Wallet.bytesToHex(priv), 'mnemonic': mnemonic};
  } else if (uc == 'DOGE') {
    final path = "m/44'/3'/0'/0/0";
    final child = root.derivePath(path);
    final priv = child.privateKey;
    final pub = child.publicKey;
    if (priv == null) throw Exception('Failed to derive DOGE keys');
    final sha = SHA256Digest().process(pub);
    final rip = RIPEMD160Digest().process(sha);
    final pl = Uint8List(rip.length + 1)..[0] = 0x1E;
    pl.setRange(1, pl.length, rip);
    final cs = SHA256Digest().process(SHA256Digest().process(pl)).sublist(0, 4);
    final ab = Uint8List(pl.length + 4);
    ab.setRange(0, pl.length, pl);
    ab.setRange(pl.length, ab.length, cs);
    return {'address': Bip39Wallet._base58Encode(ab), 'privateKey': Bip39Wallet.bytesToHex(priv), 'mnemonic': mnemonic};
  } else if (uc == 'SOL') {
    final path = "m/44'/501'/0'/0'";
    final child = root.derivePath(path);
    final priv = child.privateKey;
    final pub = child.publicKey;
    if (priv == null) throw Exception('Failed to derive SOL keys');
    return {'address': Bip39Wallet._base58Encode(pub), 'privateKey': Bip39Wallet.bytesToHex(priv), 'mnemonic': mnemonic};
  } else {
    throw Exception('Unsupported chain for local generation: $chain');
  }
}

/// Restore wallet from mnemonic for the provided chain.
/// Top-level function required by compute() to run in a background isolate.
Map<String, String> _restoreWalletSync(List<String> args) {
  final mnemonic = args[0];
  final chain = args[1];
  if (!bip39.validateMnemonic(mnemonic)) throw Exception('Invalid mnemonic phrase');
  final uc = chain.toUpperCase();
  final seed = bip39.mnemonicToSeed(mnemonic);
  final root = bip32.BIP32.fromSeed(seed);

  if (uc == 'ETH' || uc == 'BNB') {
    final child = root.derivePath("m/44'/60'/0'/0/0");
    final priv = child.privateKey;
    if (priv == null) throw Exception('Failed to derive $uc private key');
    final privHex = Bip39Wallet.bytesToHex(priv);
    final ethCred = EthPrivateKey.fromHex(privHex);
    return {'address': ethCred.address.hexEip55, 'privateKey': '0x$privHex', 'mnemonic': mnemonic};
  } else if (uc == 'BTC') {
    final child = root.derivePath("m/84'/0'/0'/0/0");
    final priv = child.privateKey;
    if (priv == null) throw Exception('Failed to derive BTC keys');
    final privHex = Bip39Wallet.bytesToHex(priv);
    final ecPrivate = ECPrivate.fromBytes(priv);
    final ecPublic = ecPrivate.getPublic();
    final segwitAddress = ecPublic.toSegwitAddress();
    final address = segwitAddress.toAddress(BitcoinNetwork.mainnet);
    return {'address': address, 'privateKey': privHex, 'mnemonic': mnemonic};
  } else if (uc == 'TRX' || uc == 'TRON') {
    final child = root.derivePath("m/44'/195'/0'/0/0");
    final priv = child.privateKey;
    if (priv == null) throw Exception('Failed to derive TRX private key');
    final privHex = Bip39Wallet.bytesToHex(priv);
    final ethCred = EthPrivateKey.fromHex(privHex);
    final ethAddr = ethCred.address.hex;
    final ethBytes = Bip39Wallet.hexToBytes(ethAddr.startsWith('0x') ? ethAddr.substring(2) : ethAddr);
    final payload = Uint8List(ethBytes.length + 1)..[0] = 0x41;
    payload.setRange(1, payload.length, ethBytes);
    final cs = SHA256Digest().process(SHA256Digest().process(payload)).sublist(0, 4);
    final ab = Uint8List(payload.length + 4);
    ab.setRange(0, payload.length, payload);
    ab.setRange(payload.length, ab.length, cs);
    return {'address': Bip39Wallet._base58Encode(ab), 'privateKey': '0x$privHex', 'mnemonic': mnemonic};
  } else if (uc == 'LTC') {
    final child = root.derivePath("m/44'/2'/0'/0/0");
    final priv = child.privateKey;
    final pub = child.publicKey;
    if (priv == null) throw Exception('Failed to derive LTC keys');
    final sha = SHA256Digest().process(pub);
    final rip = RIPEMD160Digest().process(sha);
    final pl = Uint8List(rip.length + 1)..[0] = 0x30;
    pl.setRange(1, pl.length, rip);
    final cs = SHA256Digest().process(SHA256Digest().process(pl)).sublist(0, 4);
    final ab = Uint8List(pl.length + 4);
    ab.setRange(0, pl.length, pl);
    ab.setRange(pl.length, ab.length, cs);
    return {'address': Bip39Wallet._base58Encode(ab), 'privateKey': Bip39Wallet.bytesToHex(priv), 'mnemonic': mnemonic};
  } else if (uc == 'XRP') {
    final child = root.derivePath("m/44'/144'/0'/0/0");
    final priv = child.privateKey;
    final pub = child.publicKey;
    if (priv == null) throw Exception('Failed to derive XRP keys');
    final sha = SHA256Digest().process(pub);
    final rip = RIPEMD160Digest().process(sha);
    final pl = Uint8List(rip.length + 1)..[0] = 0x00;
    pl.setRange(1, pl.length, rip);
    final cs = SHA256Digest().process(SHA256Digest().process(pl)).sublist(0, 4);
    final ab = Uint8List(pl.length + 4);
    ab.setRange(0, pl.length, pl);
    ab.setRange(pl.length, ab.length, cs);
    return {'address': Bip39Wallet._base58Encode(ab), 'privateKey': Bip39Wallet.bytesToHex(priv), 'mnemonic': mnemonic};
  } else if (uc == 'DOGE') {
    final child = root.derivePath("m/44'/3'/0'/0/0");
    final priv = child.privateKey;
    final pub = child.publicKey;
    if (priv == null) throw Exception('Failed to derive DOGE keys');
    final sha = SHA256Digest().process(pub);
    final rip = RIPEMD160Digest().process(sha);
    final pl = Uint8List(rip.length + 1)..[0] = 0x1E;
    pl.setRange(1, pl.length, rip);
    final cs = SHA256Digest().process(SHA256Digest().process(pl)).sublist(0, 4);
    final ab = Uint8List(pl.length + 4);
    ab.setRange(0, pl.length, pl);
    ab.setRange(pl.length, ab.length, cs);
    return {'address': Bip39Wallet._base58Encode(ab), 'privateKey': Bip39Wallet.bytesToHex(priv), 'mnemonic': mnemonic};
  } else if (uc == 'SOL') {
    final child = root.derivePath("m/44'/501'/0'/0'");
    final priv = child.privateKey;
    final pub = child.publicKey;
    if (priv == null) throw Exception('Failed to derive SOL keys');
    return {'address': Bip39Wallet._base58Encode(pub), 'privateKey': Bip39Wallet.bytesToHex(priv), 'mnemonic': mnemonic};
  } else {
    throw Exception('Unsupported chain for wallet restore: $chain');
  }
}

/// Minimal local BIP39/BIP44 wallet helper for ETH, BTC, TRON (TRX), BSC (BNB), LTC, XRP, DOGE, and SOL
/// - Generates a mnemonic (BIP39)
/// - Derives BIP44 account private key for ETH (m/44'/60'/0'/0/0), BTC (m/44'/0'/0'/0/0),
///   TRX (m/44'/195'/0'/0/0), BSC (m/44'/60'/0'/0/0), LTC (m/44'/2'/0'/0/0), XRP (m/44'/144'/0'/0/0), DOGE (m/44'/3'/0'/0/0), SOL (m/44'/501'/0'/0')
/// - Returns address, privateKey (hex, with 0x for ETH/TRX/BNB), and mnemonic
class Bip39Wallet {
  /// Generate a new mnemonic and derive keys for the provided chain.
  /// Supported chains: 'ETH', 'BTC', 'TRX', 'BNB', 'LTC', 'XRP', 'DOGE', 'SOL' (case-insensitive).
  /// Runs in a background isolate to prevent ANR on Android.
  static Future<Map<String, String>> generate({required String chain}) =>
      compute(_generateWalletSync, chain);

  /// Restore wallet from existing mnemonic phrase.
  /// Returns address, privateKey, and mnemonic for the given chain.
  /// Runs in a background isolate to prevent ANR on Android.
  static Future<Map<String, String>> restore({
    required String mnemonic,
    required String chain,
  }) =>
      compute(_restoreWalletSync, [mnemonic, chain]);

  static String bytesToHex(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

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

    int zeros = 0;
    for (final b in bytes) {
      if (b == 0) {
        zeros++;
      } else {
        break;
      }
    }

    BigInt value = BigInt.zero;
    for (final b in bytes) {
      value = (value << 8) | BigInt.from(b);
    }

    final chars = <int>[];
    while (value > BigInt.zero) {
      final divmod = value.remainder(BigInt.from(58));
      value = value ~/ BigInt.from(58);
      chars.add(divmod.toInt());
    }

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
