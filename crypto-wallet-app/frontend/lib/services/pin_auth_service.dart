import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/biometric_auth_service.dart';

class PinAuthService {
  // Configure Android options for better compatibility
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );
  final BiometricAuthService _biometricService = BiometricAuthService();

  static const String _pinKey = 'user_pin_hash'; // Changed to store hash
  static const String _pinSaltKey = 'user_pin_salt';
  static const String _pinEnabledKey = 'pin_enabled';
  static const String _biometricEnabledKey = 'biometric_enabled';

  /// Hash the PIN with salt for secure storage
  /// This ensures PIN is never stored in plain text
  String _hashPin(String pin, String salt) {
    final bytes = utf8.encode(pin + salt);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Generate a random salt for PIN hashing
  String _generateSalt() {
    final random = DateTime.now().millisecondsSinceEpoch.toString();
    final bytes = utf8.encode(random + 'crypto_wallet_salt');
    return sha256.convert(bytes).toString().substring(0, 16);
  }

  // Web-compatible storage helper methods
  Future<String?> _readSecure(String key) async {
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        final value = prefs.get(key);
        if (value == null) return null;
        if (value is String) return value;
        // If it's not a String, try to convert it
        return value.toString();
      }
      return await _secureStorage.read(key: key);
    } catch (e) {
      print('❌ Error reading secure storage for key $key: $e');
      return null;
    }
  }

  Future<void> _writeSecure(String key, String value) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } else {
      await _secureStorage.write(key: key, value: value);
    }
  }

  Future<void> _deleteSecure(String key) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    } else {
      await _secureStorage.delete(key: key);
    }
  }

  // Check if PIN authentication is enabled
  Future<bool> isPinEnabled() async {
    final enabled = await _readSecure(_pinEnabledKey);
    return enabled == 'true';
  }

  // Check if biometric authentication is enabled
  Future<bool> isBiometricEnabled() async {
    final enabled = await _readSecure(_biometricEnabledKey);
    return enabled == 'true';
  }

  // Check if PIN is set
  Future<bool> isPinSet() async {
    final pinHash = await _readSecure(_pinKey);
    final result = pinHash != null && pinHash.isNotEmpty;
    print('🔑 isPinSet (pin_auth_service): $result');
    return result;
  }

  // Set up PIN - stores hashed PIN, never plain text
  Future<bool> setupPin(String pin) async {
    try {
      if (pin.length < 4 || pin.length > 8) {
        return false;
      }

      // Generate salt and hash the PIN
      final salt = _generateSalt();
      final hashedPin = _hashPin(pin, salt);

      // Store hash and salt separately
      await _writeSecure(_pinSaltKey, salt);
      await _writeSecure(_pinKey, hashedPin);
      await _writeSecure(_pinEnabledKey, 'true');
      print('✅ PIN hash saved successfully in pin_auth_service');
      return true;
    } catch (e) {
      print('❌ Error saving PIN: $e');
      return false;
    }
  }

  // Verify PIN by comparing hashes
  Future<bool> verifyPin(String pin) async {
    try {
      final storedHash = await _readSecure(_pinKey);
      final salt = await _readSecure(_pinSaltKey);

      if (storedHash == null || salt == null) {
        print('🔍 Verifying PIN - no stored hash or salt');
        return false;
      }

      // Hash the input PIN with the stored salt
      final inputHash = _hashPin(pin, salt);

      print('🔍 Verifying PIN - comparing hashes');
      return storedHash == inputHash;
    } catch (e) {
      print('❌ Error verifying PIN: $e');
      return false;
    }
  }

  // Change PIN
  Future<bool> changePin(String oldPin, String newPin) async {
    try {
      final isValid = await verifyPin(oldPin);
      if (!isValid) return false;

      return await setupPin(newPin);
    } catch (e) {
      return false;
    }
  }

  // Enable/Disable PIN authentication
  Future<void> setPinEnabled(bool enabled) async {
    await _writeSecure(_pinEnabledKey, enabled ? 'true' : 'false');
  }

  // Enable/Disable biometric authentication
  Future<void> setBiometricEnabled(bool enabled) async {
    await _writeSecure(_biometricEnabledKey, enabled ? 'true' : 'false');
  }

  // Delete PIN
  Future<void> deletePin() async {
    await _deleteSecure(_pinKey);
    await _writeSecure(_pinEnabledKey, 'false');
  }

  // Authenticate with biometric
  Future<bool> authenticateWithBiometric() async {
    final isBiometricEnabled = await this.isBiometricEnabled();
    if (!isBiometricEnabled) return false;

    final canAuthenticate = await _biometricService.isBiometricAvailable();
    if (!canAuthenticate) return false;

    return await _biometricService.authenticateWithBiometrics(
      reason: 'Authenticate to access your wallet',
    );
  }

  // Check if biometric hardware is available
  Future<bool> isBiometricAvailable() async {
    return await _biometricService.isBiometricAvailable();
  }
}
