import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  // Configure Android options for better compatibility
  final FlutterSecureStorage? _secureStorage = kIsWeb ? null : const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );

  SharedPreferences? _prefs;
  Future<SharedPreferences> _getPrefs() async =>
      _prefs ??= await SharedPreferences.getInstance();

  Future<String?> _read(String key) async {
    if (kIsWeb || _secureStorage == null) {
      return (await _getPrefs()).get(key)?.toString();
    }
    try {
      return await _secureStorage!.read(key: key);
    } catch (_) {
      return (await _getPrefs()).get(key)?.toString();
    }
  }

  Future<void> _write(String key, String value) async {
    if (kIsWeb || _secureStorage == null) {
      await (await _getPrefs()).setString(key, value);
      return;
    }
    try {
      await _secureStorage!.write(key: key, value: value);
    } catch (_) {
      await (await _getPrefs()).setString(key, value);
    }
  }

  Future<void> _deleteAll() async {
    if (kIsWeb || _secureStorage == null) {
      final prefs = await _getPrefs();
      for (final k in [_keyIsLoggedIn, _keyWalletAddress, _keyMnemonic, _keyPin]) {
        await prefs.remove(k);
      }
      return;
    }
    try {
      await _secureStorage!.deleteAll();
    } catch (_) {
      final prefs = await _getPrefs();
      for (final k in [_keyIsLoggedIn, _keyWalletAddress, _keyMnemonic, _keyPin]) {
        await prefs.remove(k);
      }
    }
  }

  static const String _keyIsLoggedIn = 'is_logged_in';
  static const String _keyWalletAddress = 'wallet_address';
  static const String _keyMnemonic = 'mnemonic';
  static const String _keyPin = 'user_pin';

  // Check if user is logged in
  Future<bool> isLoggedIn() async {
    final value = await _read(_keyIsLoggedIn);
    return value == 'true';
  }

  // Save login state
  Future<void> setLoggedIn(bool value) async {
    await _write(_keyIsLoggedIn, value.toString());
  }

  // Save wallet data
  Future<void> saveWalletData({
    required String address,
    required String mnemonic,
  }) async {
    await _write(_keyWalletAddress, address);
    await _write(_keyMnemonic, mnemonic);
    await setLoggedIn(true);
  }

  // Get wallet address
  Future<String?> getWalletAddress() async {
    return await _read(_keyWalletAddress);
  }

  // Get mnemonic
  Future<String?> getMnemonic() async {
    return await _read(_keyMnemonic);
  }

  // Logout - clear all data
  Future<void> logout() async {
    await _deleteAll();
  }

  // Check if wallet exists
  Future<bool> hasWallet() async {
    final address = await _read(_keyWalletAddress);
    return address != null && address.isNotEmpty;
  }

  // Set PIN
  Future<void> setPin(String pin) async {
    await _write(_keyPin, pin);
  }

  // Verify PIN
  Future<bool> verifyPIN(String pin) async {
    final storedPin = await _read(_keyPin);
    debugPrint('🔐 AuthService.verifyPIN - storedPin exists: ${storedPin != null}, input length: ${pin.length}');
    // If no PIN is set, accept any 6-digit PIN (for demo/first use)
    if (storedPin == null || storedPin.isEmpty) {
      debugPrint('✅ No PIN stored - accepting any 6-digit PIN');
      return pin.length == 6;
    }
    final match = storedPin == pin;
    debugPrint('🔐 PIN match: $match');
    return match;
  }

  // Check if PIN is set
  Future<bool> hasPin() async {
    final pin = await _read(_keyPin);
    return pin != null && pin.isNotEmpty;
  }
}
