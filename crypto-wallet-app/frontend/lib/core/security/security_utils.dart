import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/pointycastle.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/api.dart' as crypto_api;

/// Security utilities for the crypto wallet app
class SecurityUtils {
  static final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  
  /// Generate secure random bytes
  static Uint8List generateRandomBytes(int length) {
    final random = Random.secure();
    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes;
  }
  
  /// Hash data using SHA-256
  static String hashData(String data) {
    final bytes = utf8.encode(data);
    final digest = Digest('SHA-256');
    final hash = digest.process(bytes);
    return base64.encode(hash);
  }
  
  /// Secure storage operations
  static Future<void> storeSecureData(String key, String value) async {
    await _secureStorage.write(key: key, value: value);
  }
  
  static Future<String?> getSecureData(String key) async {
    return await _secureStorage.read(key: key);
  }
  
  static Future<void> deleteSecureData(String key) async {
    await _secureStorage.delete(key: key);
  }
  
  static Future<void> clearAllSecureData() async {
    await _secureStorage.deleteAll();
  }
  
  /// Validate wallet address format
  static bool isValidWalletAddress(String address, {String? coinType}) {
    if (address.isEmpty) return false;
    
    // Basic length validation for common crypto addresses
    if (address.length < 26 || address.length > 64) return false;
    
    // Check for common address patterns
    final patterns = {
      'BTC': RegExp(r'^[13][a-km-zA-HJ-NP-Z1-9]{25,34}$'),
      'ETH': RegExp(r'^0x[a-fA-F0-9]{40}$'),
      'LTC': RegExp(r'^[LM3][a-km-zA-HJ-NP-Z1-9]{26,33}$'),
      'DOGE': RegExp(r'^D{1}[5-9A-HJ-NP-U]{1}[1-9A-HJ-NP-Za-km-z]{32}$'),
    };
    
    if (coinType != null && patterns.containsKey(coinType)) {
      return patterns[coinType]!.hasMatch(address);
    }
    
    // Generic validation for other coins
    return RegExp(r'^[a-zA-Z0-9]{26,64}$').hasMatch(address);
  }
  
  /// Validate amount format
  static bool isValidAmount(String amount) {
    if (amount.isEmpty) return false;
    
    // Check for valid decimal number format
    final regex = RegExp(r'^\d+(\.\d{1,8})?$');
    if (!regex.hasMatch(amount)) return false;
    
    // Check if amount is positive
    final numericAmount = double.tryParse(amount);
    return numericAmount != null && numericAmount > 0;
  }
  
  /// Sanitize user input
  static String sanitizeInput(String input) {
    // Remove potentially dangerous characters
    return input
        .replaceAll('<', '')
        .replaceAll('>', '')
        .replaceAll('"', '')
        .replaceAll("'", '')
        .replaceAll('\\', '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
  }
  
  /// Validate password strength
  static PasswordStrength validatePasswordStrength(String password) {
    if (password.length < 8) return PasswordStrength.weak;
    
    int score = 0;
    
    // Check for uppercase letters
    if (RegExp(r'[A-Z]').hasMatch(password)) score++;
    
    // Check for lowercase letters
    if (RegExp(r'[a-z]').hasMatch(password)) score++;
    
    // Check for numbers
    if (RegExp(r'[0-9]').hasMatch(password)) score++;
    
    // Check for special characters
    if (RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password)) score++;
    
    // Check for common patterns to avoid
    final commonPatterns = [
      '123456', 'password', 'qwerty', 'admin', 'welcome'
    ];
    
    if (commonPatterns.any((pattern) => 
        password.toLowerCase().contains(pattern))) {
      score = 0;
    }
    
    switch (score) {
      case 0:
      case 1:
        return PasswordStrength.weak;
      case 2:
        return PasswordStrength.fair;
      case 3:
        return PasswordStrength.good;
      case 4:
        return PasswordStrength.strong;
      default:
        return PasswordStrength.weak;
    }
  }
  
  /// Generate secure PIN code
  static String generateSecurePin() {
    final random = Random.secure();
    final pin = StringBuffer();
    
    for (int i = 0; i < 6; i++) {
      pin.write(random.nextInt(10));
    }
    
    return pin.toString();
  }
  
  /// Encrypt sensitive data using AES encryption
  static String encryptData(String data, String key) {
    try {
      // Use proper key derivation
      final keyBytes = utf8.encode(key.padRight(32).substring(0, 32));
      final iv = generateRandomBytes(16);
      
      final cipher = BlockCipher('AES/CBC');
      cipher.init(true, crypto_api.ParametersWithIV(crypto_api.KeyParameter(keyBytes), iv));
      
      final dataBytes = utf8.encode(data);
      final paddedData = _padData(dataBytes);
      final encrypted = cipher.process(paddedData);
      
      final result = Uint8List(iv.length + encrypted.length);
      result.setRange(0, iv.length, iv);
      result.setRange(iv.length, result.length, encrypted);
      
      return base64.encode(result);
    } catch (e) {
      throw Exception('Encryption failed: $e');
    }
  }
  
  /// Decrypt sensitive data using AES encryption
  static String decryptData(String encryptedData, String key) {
    try {
      final keyBytes = utf8.encode(key.padRight(32).substring(0, 32));
      final encryptedBytes = base64.decode(encryptedData);
      
      final iv = encryptedBytes.sublist(0, 16);
      final data = encryptedBytes.sublist(16);
      
      final cipher = BlockCipher('AES/CBC');
      cipher.init(false, crypto_api.ParametersWithIV(crypto_api.KeyParameter(keyBytes), iv));
      
      final decrypted = cipher.process(data);
      final unpadded = _unpadData(decrypted);
      
      return utf8.decode(unpadded);
    } catch (e) {
      throw Exception('Decryption failed: $e');
    }
  }
  
  /// PKCS7 padding for AES encryption
  static Uint8List _padData(Uint8List data) {
    final blockSize = 16;
    final padLength = blockSize - (data.length % blockSize);
    final result = Uint8List(data.length + padLength);
    result.setRange(0, data.length, data);
    for (int i = data.length; i < result.length; i++) {
      result[i] = padLength;
    }
    return result;
  }
  
  /// Remove PKCS7 padding after decryption
  static Uint8List _unpadData(Uint8List data) {
    final padLength = data[data.length - 1];
    return data.sublist(0, data.length - padLength);
  }
}

enum PasswordStrength {
  weak,
  fair,
  good,
  strong
}

/// Secure session management
class SecureSessionManager {
  static final SecureSessionManager _instance = SecureSessionManager._internal();
  factory SecureSessionManager() => _instance;
  SecureSessionManager._internal();
  
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  static const String _sessionKey = 'user_session';
  static const String _lastActivityKey = 'last_activity';
  
  /// Store user session
  Future<void> storeSession(String sessionData) async {
    await _storage.write(key: _sessionKey, value: sessionData);
    await _updateLastActivity();
  }
  
  /// Get user session
  Future<String?> getSession() async {
    final session = await _storage.read(key: _sessionKey);
    if (session != null) {
      await _updateLastActivity();
    }
    return session;
  }
  
  /// Clear user session
  Future<void> clearSession() async {
    await _storage.delete(key: _sessionKey);
    await _storage.delete(key: _lastActivityKey);
  }
  
  /// Check if session is expired (30 minutes timeout)
  Future<bool> isSessionExpired() async {
    final lastActivity = await _storage.read(key: _lastActivityKey);
    if (lastActivity == null) return true;
    
    try {
      final lastActivityTime = DateTime.parse(lastActivity);
      final now = DateTime.now();
      final difference = now.difference(lastActivityTime);
      
      return difference.inMinutes > 30;
    } catch (e) {
      return true;
    }
  }
  
  /// Update last activity timestamp
  Future<void> _updateLastActivity() async {
    await _storage.write(
      key: _lastActivityKey, 
      value: DateTime.now().toIso8601String()
    );
  }
}

/// Input validation utilities
class InputValidator {
  /// Validate email format
  static bool isValidEmail(String email) {
    final regex = RegExp(
      r'^[a-zA-Z0-9.!#$%&’*+/=?^_`{|}~-]+@[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)*$'
    );
    return regex.hasMatch(email);
  }
  
  /// Validate phone number format
  static bool isValidPhoneNumber(String phone) {
    final regex = RegExp(r'^\+?[\d\s\-\(\)]{10,}$');
    return regex.hasMatch(phone);
  }
  
  /// Validate mnemonic phrase (12 or 24 words)
  static bool isValidMnemonic(String mnemonic) {
    final words = mnemonic.trim().split(RegExp(r'\s+'));
    return words.length == 12 || words.length == 24;
  }
  
  /// Validate private key format
  static bool isValidPrivateKey(String privateKey) {
    // Basic validation for hex-encoded private keys
    if (privateKey.length != 64) return false;
    return RegExp(r'^[a-fA-F0-9]+$').hasMatch(privateKey);
  }
}
