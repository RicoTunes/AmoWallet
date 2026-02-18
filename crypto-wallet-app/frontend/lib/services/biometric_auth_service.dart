import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'pin_auth_service.dart';

/// BiometricAuthService handles biometric authentication and device capabilities.
/// IMPORTANT: For biometric ENABLED state, this service delegates to PinAuthService
/// to ensure consistency across the app. Always use a single source of truth.
class BiometricAuthService {
  static final BiometricAuthService _instance = BiometricAuthService._internal();
  factory BiometricAuthService() => _instance;
  BiometricAuthService._internal();

  // GLOBAL LOCK to prevent double biometric prompts across the entire app
  static bool _isAuthenticating = false;
  static DateTime? _lastAuthAttempt;
  static const int _minAuthIntervalMs = 2000; // Minimum 2 seconds between auth attempts

  final LocalAuthentication _localAuth = LocalAuthentication();
  // Configure Android options for better compatibility
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );

  static const String _pinKey = 'user_pin_hash';
  static const String _pinSaltKey = 'pin_salt';
  // IMPORTANT: This key MUST match the one in PinAuthService for consistency
  static const String _biometricEnabledKey = 'biometric_enabled';
  static const String _lastAuthTimeKey = 'last_auth_time';
  static const int _authTimeoutMinutes = 5; // Require re-auth after 5 minutes

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

  /// Check if biometric authentication is available on the device
  Future<bool> isBiometricAvailable() async {
    try {
      return await _localAuth.canCheckBiometrics || await _localAuth.isDeviceSupported();
    } catch (e) {
      return false;
    }
  }

  /// Get list of available biometric types (fingerprint, face, etc.)
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (e) {
      return [];
    }
  }

  /// Check if biometric authentication is enabled by user
  Future<bool> isBiometricEnabled() async {
    final enabled = await _readSecure(_biometricEnabledKey);
    return enabled == 'true';
  }

  /// Enable or disable biometric authentication
  /// This writes to secure storage with 'true'/'false' string values
  /// to match PinAuthService's format
  Future<void> setBiometricEnabled(bool enabled) async {
    // Use 'true'/'false' strings to match PinAuthService format
    await _writeSecure(_biometricEnabledKey, enabled ? 'true' : 'false');
    print('💾 BiometricAuthService: Saved biometric enabled = $enabled');
  }

  /// Authenticate using biometrics (fingerprint, face ID, etc.)
  Future<bool> authenticateWithBiometrics({
    String reason = 'Please authenticate to continue',
  }) async {
    // Prevent double prompts with strict locking
    if (_isAuthenticating) {
      print('🔒 BiometricAuthService: Already authenticating, skipping duplicate call');
      return false;
    }
    
    // Also check if we just attempted authentication (within minimum interval)
    if (_lastAuthAttempt != null) {
      final elapsed = DateTime.now().difference(_lastAuthAttempt!).inMilliseconds;
      if (elapsed < _minAuthIntervalMs) {
        print('🔒 BiometricAuthService: Too soon since last attempt (${elapsed}ms), skipping');
        return false;
      }
    }
    
    _isAuthenticating = true;
    _lastAuthAttempt = DateTime.now();
    
    try {
      final bool canAuthenticate = await isBiometricAvailable();
      if (!canAuthenticate) {
        return false;
      }

      print('🔐 BiometricAuthService: Starting biometric authentication...');
      final bool didAuthenticate = await _localAuth.authenticate(
        localizedReason: reason,
      );
      print('🔐 BiometricAuthService: Authentication result: $didAuthenticate');

      if (didAuthenticate) {
        await _updateLastAuthTime();
      }

      return didAuthenticate;
    } on PlatformException catch (e) {
      print('Biometric authentication error: $e');
      return false;
    } finally {
      // Small delay before clearing the lock to prevent rapid re-calls
      await Future.delayed(const Duration(milliseconds: 500));
      _isAuthenticating = false;
    }
  }

  /// Set up a new PIN
  Future<void> setPIN(String pin) async {
    if (pin.length < 4) {
      throw Exception('PIN must be at least 4 digits');
    }

    // Generate a random salt
    final salt = DateTime.now().millisecondsSinceEpoch.toString();
    await _writeSecure(_pinSaltKey, salt);

    // Hash the PIN with salt
    final hash = _hashPIN(pin, salt);
    await _writeSecure(_pinKey, hash);
    print('✅ PIN saved successfully (hash: ${hash.substring(0, 10)}...)');
  }

  /// Verify a PIN — always delegates to PinAuthService (PBKDF2) as the single source of truth.
  Future<bool> verifyPIN(String pin) async {
    final isValid = await PinAuthService().verifyPin(pin);
    if (isValid) {
      await _updateLastAuthTime();
    }
    return isValid;
  }

  /// Check if PIN is set
  Future<bool> isPINSet() async {
    // Check both hashed PIN (this service) and plain PIN (PinAuthService)
    final pinHash = await _readSecure(_pinKey);
    if (pinHash != null && pinHash.isNotEmpty) {
      print('🔑 isPINSet check: true (hashed PIN exists)');
      return true;
    }
    
    // Also check for plain PIN from PinAuthService
    final plainPin = await _readSecure('user_pin');
    final result = plainPin != null && plainPin.isNotEmpty;
    print('🔑 isPINSet check: $result (plain PIN exists: ${plainPin != null})');
    return result;
  }

  /// Remove PIN
  Future<void> removePIN() async {
    await _deleteSecure(_pinKey);
    await _deleteSecure(_pinSaltKey);
  }

  /// Authenticate with biometrics or PIN fallback
  Future<bool> authenticate({
    String reason = 'Please authenticate to continue',
    bool allowPINFallback = true,
  }) async {
    // Check if biometric is enabled and available
    final biometricEnabled = await isBiometricEnabled();
    final biometricAvailable = await isBiometricAvailable();

    if (biometricEnabled && biometricAvailable) {
      return await authenticateWithBiometrics(reason: reason);
    }

    // Fallback to PIN if biometrics not available
    if (allowPINFallback) {
      final pinSet = await isPINSet();
      if (!pinSet) {
        // No authentication method set up
        return false;
      }
      // PIN verification will be handled by UI
      return false; // Return false to trigger PIN dialog in UI
    }

    return false;
  }

  /// Check if authentication is required (based on timeout)
  Future<bool> isAuthenticationRequired() async {
    final lastAuthStr = await _readSecure(_lastAuthTimeKey);
    if (lastAuthStr == null) {
      return true;
    }

    final lastAuth = DateTime.tryParse(lastAuthStr);
    if (lastAuth == null) {
      return true;
    }

    final now = DateTime.now();
    final difference = now.difference(lastAuth);

    return difference.inMinutes >= _authTimeoutMinutes;
  }

  /// Update last authentication time
  Future<void> _updateLastAuthTime() async {
    await _writeSecure(_lastAuthTimeKey, DateTime.now().toIso8601String());
  }

  /// Clear authentication session (e.g., on logout)
  Future<void> clearAuthSession() async {
    await _deleteSecure(_lastAuthTimeKey);
  }

  /// Hash PIN with salt using SHA-256
  String _hashPIN(String pin, String salt) {
    final bytes = utf8.encode(pin + salt);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Require authentication for sensitive operations
  Future<bool> requireAuthentication({
    String reason = 'Authentication required',
  }) async {
    // Check if we need to authenticate based on timeout
    final authRequired = await isAuthenticationRequired();
    if (!authRequired) {
      return true; // Recently authenticated, no need to re-authenticate
    }

    // Try biometric authentication first
    final biometricEnabled = await isBiometricEnabled();
    final biometricAvailable = await isBiometricAvailable();

    if (biometricEnabled && biometricAvailable) {
      return await authenticateWithBiometrics(reason: reason);
    }

    // Check if PIN is set up - if yes, let UI handle PIN entry
    // Return false to trigger PIN dialog, but only if PIN exists
    final pinSet = await isPINSet();
    if (pinSet) {
      return false; // PIN exists, UI will show PIN dialog
    }

    // No authentication method available
    return false;
  }
}
