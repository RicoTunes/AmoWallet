import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/biometric_auth_service.dart';
import '../services/remote_wipe_service.dart';
import '../core/providers/fake_wallet_provider.dart';

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
  
  // Security: PIN attempt limiting keys
  static const String _failedAttemptsKey = 'pin_failed_attempts';
  static const String _lockoutUntilKey = 'pin_lockout_until';
  static const int _maxFailedAttempts = 5;
  static const int _lockoutDurationMinutes = 30;

  /// Hash the PIN with salt for secure storage
  /// This ensures PIN is never stored in plain text
  String _hashPin(String pin, String salt) {
    final bytes = utf8.encode(pin + salt);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Generate a cryptographically secure random salt for PIN hashing
  /// Uses SecureRandom for unpredictable salt generation
  String _generateSalt() {
    final secureRandom = Random.secure();
    final saltBytes = Uint8List(32); // 256 bits of entropy
    for (int i = 0; i < saltBytes.length; i++) {
      saltBytes[i] = secureRandom.nextInt(256);
    }
    // Convert to base64 for storage, take first 32 chars
    return base64Url.encode(saltBytes).substring(0, 32);
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
      debugPrint('❌ Error reading secure storage for key $key: $e');
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
    debugPrint('🔑 isPinSet (pin_auth_service): $result');
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
      debugPrint('✅ PIN hash saved successfully in pin_auth_service');
      return true;
    } catch (e) {
      debugPrint('❌ Error saving PIN: $e');
      return false;
    }
  }

  // Verify PIN by comparing hashes - includes attempt limiting and duress PIN check
  Future<bool> verifyPin(String pin, {WidgetRef? ref}) async {
    try {
      // CHECK FOR DURESS PIN FIRST (highest priority)
      final remoteWipeService = RemoteWipeService();
      if (await remoteWipeService.hasDuressPin()) {
        if (await remoteWipeService.isDuressPin(pin)) {
          debugPrint('🚨 DURESS PIN DETECTED - ACTIVATING DECOY WALLET');
          
          // Activate fake wallet decoy persistently instead of wiping
          if (ref != null) {
            await ref.read(fakeWalletProvider.notifier).activateFakeWallet();
            debugPrint('✅ Fake wallet PERSISTENTLY activated - all balances set to 0.00');
          }
          
          // Return false to not log user in normally
          return false;
        }
      }

      // Check if account is locked out
      if (await isLockedOut()) {
        final remainingTime = await getRemainingLockoutTime();
        debugPrint('🔒 Account locked! Remaining time: $remainingTime minutes');
        return false;
      }
      
      final storedHash = await _readSecure(_pinKey);
      final salt = await _readSecure(_pinSaltKey);

      if (storedHash == null || salt == null) {
        debugPrint('🔍 Verifying PIN - no stored hash or salt');
        return false;
      }

      // Hash the input PIN with the stored salt
      final inputHash = _hashPin(pin, salt);

      debugPrint('🔍 Verifying PIN - comparing hashes');
      final isValid = storedHash == inputHash;
      
      if (isValid) {
        // Reset failed attempts on successful login
        await _resetFailedAttempts();
        debugPrint('✅ PIN verified successfully');
      } else {
        // Increment failed attempts
        await _incrementFailedAttempts();
        final attempts = await getFailedAttempts();
        final remaining = _maxFailedAttempts - attempts;
        debugPrint('❌ Invalid PIN! $remaining attempts remaining');
        
        // Check if should lock out
        if (attempts >= _maxFailedAttempts) {
          await _setLockout();
          debugPrint('🔒 Account locked for $_lockoutDurationMinutes minutes!');
        }
      }
      
      return isValid;
    } catch (e) {
      debugPrint('❌ Error verifying PIN: $e');
      return false;
    }
  }

  /// Check if account is currently locked out
  Future<bool> isLockedOut() async {
    final lockoutUntilStr = await _readSecure(_lockoutUntilKey);
    if (lockoutUntilStr == null) return false;
    
    final lockoutUntil = DateTime.tryParse(lockoutUntilStr);
    if (lockoutUntil == null) return false;
    
    if (DateTime.now().isBefore(lockoutUntil)) {
      return true;
    } else {
      // Lockout expired, clear it
      await _resetFailedAttempts();
      return false;
    }
  }

  /// Get remaining lockout time in minutes
  Future<int> getRemainingLockoutTime() async {
    final lockoutUntilStr = await _readSecure(_lockoutUntilKey);
    if (lockoutUntilStr == null) return 0;
    
    final lockoutUntil = DateTime.tryParse(lockoutUntilStr);
    if (lockoutUntil == null) return 0;
    
    final remaining = lockoutUntil.difference(DateTime.now()).inMinutes;
    return remaining > 0 ? remaining + 1 : 0; // +1 to round up
  }

  /// Get current failed attempt count
  Future<int> getFailedAttempts() async {
    final attemptsStr = await _readSecure(_failedAttemptsKey);
    return int.tryParse(attemptsStr ?? '0') ?? 0;
  }

  /// Get remaining attempts before lockout
  Future<int> getRemainingAttempts() async {
    final attempts = await getFailedAttempts();
    return (_maxFailedAttempts - attempts).clamp(0, _maxFailedAttempts);
  }

  /// Increment failed attempts counter
  Future<void> _incrementFailedAttempts() async {
    final current = await getFailedAttempts();
    await _writeSecure(_failedAttemptsKey, (current + 1).toString());
  }

  /// Set lockout timestamp
  Future<void> _setLockout() async {
    final lockoutUntil = DateTime.now().add(Duration(minutes: _lockoutDurationMinutes));
    await _writeSecure(_lockoutUntilKey, lockoutUntil.toIso8601String());
  }

  /// Reset failed attempts and lockout
  Future<void> _resetFailedAttempts() async {
    await _deleteSecure(_failedAttemptsKey);
    await _deleteSecure(_lockoutUntilKey);
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
    debugPrint('💾 PinAuthService: Saving biometric enabled = $enabled');
    await _writeSecure(_biometricEnabledKey, enabled ? 'true' : 'false');
    // Verify write
    final verify = await _readSecure(_biometricEnabledKey);
    debugPrint('💾 PinAuthService: Verified biometric saved = $verify');
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
