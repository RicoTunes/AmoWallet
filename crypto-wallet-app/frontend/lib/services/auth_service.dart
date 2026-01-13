import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  // Configure Android options for better compatibility
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );
  
  static const String _keyIsLoggedIn = 'is_logged_in';
  static const String _keyWalletAddress = 'wallet_address';
  static const String _keyMnemonic = 'mnemonic';
  static const String _keyPin = 'user_pin';

  // Check if user is logged in
  Future<bool> isLoggedIn() async {
    final value = await _secureStorage.read(key: _keyIsLoggedIn);
    return value == 'true';
  }

  // Save login state
  Future<void> setLoggedIn(bool value) async {
    await _secureStorage.write(
      key: _keyIsLoggedIn,
      value: value.toString(),
    );
  }

  // Save wallet data
  Future<void> saveWalletData({
    required String address,
    required String mnemonic,
  }) async {
    await _secureStorage.write(key: _keyWalletAddress, value: address);
    await _secureStorage.write(key: _keyMnemonic, value: mnemonic);
    await setLoggedIn(true);
  }

  // Get wallet address
  Future<String?> getWalletAddress() async {
    return await _secureStorage.read(key: _keyWalletAddress);
  }

  // Get mnemonic
  Future<String?> getMnemonic() async {
    return await _secureStorage.read(key: _keyMnemonic);
  }

  // Logout - clear all data
  Future<void> logout() async {
    await _secureStorage.deleteAll();
  }

  // Check if wallet exists
  Future<bool> hasWallet() async {
    final address = await _secureStorage.read(key: _keyWalletAddress);
    return address != null && address.isNotEmpty;
  }

  // Set PIN
  Future<void> setPin(String pin) async {
    await _secureStorage.write(key: _keyPin, value: pin);
  }

  // Verify PIN
  Future<bool> verifyPIN(String pin) async {
    final storedPin = await _secureStorage.read(key: _keyPin);
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
    final pin = await _secureStorage.read(key: _keyPin);
    return pin != null && pin.isNotEmpty;
  }
}
