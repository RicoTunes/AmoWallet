// ============================================================================
// rust_security_service.dart — Flutter-side encryption bridge to Rust.
// All private-key material is AES-256-GCM encrypted BEFORE leaving this
// device.  HMAC-SHA256 protects every request from tampering.
//
// Flow:  Flutter encrypts key → Node.js forwards blindly → Rust decrypts & signs
// ============================================================================

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter/foundation.dart';

import '../core/config/api_config.dart';

class RustSecurityService {
  static final RustSecurityService _instance = RustSecurityService._internal();
  factory RustSecurityService() => _instance;

  late final Uint8List _aesKey;
  late final Uint8List _hmacKey;
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 60),
    receiveTimeout: const Duration(seconds: 120),
    sendTimeout: const Duration(seconds: 60),
  ));

  /// Must match RUST_BRIDGE_SECRET env var on the server (or the default).
  static const String _defaultBridgeSecret =
      'AmoWallet_Rust_Bridge_2026_SecureKey_Zx9Fk2mQ7v';

  RustSecurityService._internal() {
    final secret = _defaultBridgeSecret; // In prod: fetch from secure config

    // Derive AES key  =  SHA-256(secret || "aes-key-derive")
    _aesKey = Uint8List.fromList(
        sha256.convert(utf8.encode('${secret}aes-key-derive')).bytes);

    // Derive HMAC key =  SHA-256(secret || "hmac-key-derive")
    _hmacKey = Uint8List.fromList(
        sha256.convert(utf8.encode('${secret}hmac-key-derive')).bytes);
  }

  // -----------------------------------------------------------------------
  // AES-256-GCM encryption
  // -----------------------------------------------------------------------

  /// Encrypt [plaintext] with AES-256-GCM.
  /// Returns base64( nonce[12] || ciphertext || tag[16] ).
  String encryptAesGcm(String plaintext) {
    final key = encrypt.Key(_aesKey);
    final iv = encrypt.IV.fromSecureRandom(12); // 96-bit nonce
    final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.gcm));

    // encrypt package returns ciphertext with appended GCM tag by default
    final encrypted = encrypter.encrypt(plaintext, iv: iv);

    // Combine nonce + ciphertext+tag
    final combined = Uint8List(12 + encrypted.bytes.length);
    combined.setRange(0, 12, iv.bytes);
    combined.setRange(12, combined.length, encrypted.bytes);

    return base64Encode(combined);
  }

  // -----------------------------------------------------------------------
  // HMAC-SHA256
  // -----------------------------------------------------------------------

  /// Compute HMAC-SHA256 of [data] using the derived HMAC key.
  String computeHmac(String data) {
    final hmac = Hmac(sha256, _hmacKey);
    final digest = hmac.convert(utf8.encode(data));
    return digest.toString(); // hex string
  }

  // -----------------------------------------------------------------------
  // Secure EVM Send  (ETH / BNB)
  // -----------------------------------------------------------------------

  /// Sign and send an EVM transaction through Rust.
  /// The private key is AES-256-GCM encrypted and NEVER sent as plaintext.
  Future<Map<String, dynamic>> secureEvmSend({
    required String privateKey,
    required String chain,
    required String from,
    required String to,
    required String amount,
    int gasLimit = 21000,
    double? amountUsd,
    String? memo,
  }) async {
    final encryptedKey = encryptAesGcm(privateKey);

    final payload = <String, dynamic>{
      'encrypted_key': encryptedKey,
      'chain': chain,
      'from': from,
      'to': to,
      'amount': amount,
      'gas_limit': gasLimit,
      if (memo != null) 'memo': memo,
      if (amountUsd != null) 'amount_usd': amountUsd,
    };

    // Compute HMAC over the payload (without the hmac field itself)
    final payloadJson = jsonEncode(payload);
    payload['hmac'] = computeHmac(payloadJson);

    try {
      final response = await _dio.post(
        '${ApiConfig.baseUrl}/api/secure/sign-evm',
        data: payload,
      );

      final data = response.data;
      if (data is Map<String, dynamic>) {
        // Unwrap Rust's { success, data, error } wrapper if present
        if (data.containsKey('data') && data['data'] is Map) {
          return Map<String, dynamic>.from(data['data']);
        }
        return data;
      }
      throw Exception('Unexpected response format');
    } on DioException catch (e) {
      final errBody = e.response?.data;
      String msg;
      if (errBody is Map && errBody['error'] != null) {
        msg = errBody['error'].toString();
      } else if (e.type == DioExceptionType.receiveTimeout) {
        msg = 'Server timeout - transaction may still be processing';
      } else if (e.type == DioExceptionType.connectionTimeout) {
        msg = 'Connection timeout - check your internet';
      } else if (e.type == DioExceptionType.connectionError) {
        msg = 'Cannot reach server - check your internet';
      } else {
        msg = 'Send failed: ${e.message ?? "unknown error"}';
      }
      throw Exception(msg);
    }
  }

  // -----------------------------------------------------------------------
  // Secure Non-EVM Validate  (BTC, LTC, DOGE, SOL, TRX, XRP)
  // -----------------------------------------------------------------------

  /// Validate a non-EVM transaction through Rust (spending limits + decrypt).
  /// Returns the validated (decrypted) key for Node.js to sign internally.
  /// The key is ONLY transmitted Rust→Node.js over localhost TCP.
  Future<Map<String, dynamic>> secureValidate({
    required String privateKey,
    required String chain,
    required String from,
    required String to,
    required String amount,
    double? amountUsd,
  }) async {
    final encryptedKey = encryptAesGcm(privateKey);

    final payload = <String, dynamic>{
      'encrypted_key': encryptedKey,
      'chain': chain,
      'from': from,
      'to': to,
      'amount': amount,
      if (amountUsd != null) 'amount_usd': amountUsd,
    };

    final payloadJson = jsonEncode(payload);
    payload['hmac'] = computeHmac(payloadJson);

    try {
      final response = await _dio.post(
        '${ApiConfig.baseUrl}/api/secure/validate',
        data: payload,
      );

      final data = response.data;
      if (data is Map<String, dynamic>) {
        if (data.containsKey('data') && data['data'] is Map) {
          return Map<String, dynamic>.from(data['data']);
        }
        return data;
      }
      throw Exception('Unexpected response format');
    } on DioException catch (e) {
      final errBody = e.response?.data;
      String msg = 'Secure validation failed';
      if (errBody is Map && errBody['error'] != null) {
        msg = errBody['error'].toString();
      }
      throw Exception(msg);
    }
  }

  // -----------------------------------------------------------------------
  // Health check
  // -----------------------------------------------------------------------

  Future<bool> isRustSecureAvailable() async {
    try {
      final response = await _dio.get(
        '${ApiConfig.baseUrl}/api/secure/health',
        options: Options(
          receiveTimeout: const Duration(seconds: 5),
        ),
      );
      return response.data?['success'] == true ||
          (response.data?['data']?['success'] == true);
    } catch (_) {
      return false;
    }
  }
}
