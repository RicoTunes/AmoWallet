import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service to manage screenshot prevention settings
class ScreenshotService {
  static final ScreenshotService _instance = ScreenshotService._internal();
  factory ScreenshotService() => _instance;
  ScreenshotService._internal();

  static const String _screenshotEnabledKey = 'screenshot_enabled';
  static const MethodChannel _channel = MethodChannel('com.amo.wallet/screenshot');

  /// Check if screenshots are allowed
  Future<bool> isScreenshotAllowed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Default to false (screenshots blocked) for security
      return prefs.getBool(_screenshotEnabledKey) ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Set screenshot permission
  Future<void> setScreenshotAllowed(bool allowed) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_screenshotEnabledKey, allowed);
      
      // Communicate with native Android code
      await _setNativeScreenshotFlag(!allowed); // Invert: allowed=true means FLAG_SECURE=false
    } catch (e) {
      print('Error setting screenshot permission: $e');
    }
  }

  /// Set the native FLAG_SECURE flag
  Future<void> _setNativeScreenshotFlag(bool secure) async {
    try {
      await _channel.invokeMethod('setSecureFlag', {'secure': secure});
    } catch (e) {
      // If method channel fails, it will be enforced at activity level
      print('Method channel not available: $e');
    }
  }

  /// Apply current setting (call on app start)
  Future<void> applySetting() async {
    final allowed = await isScreenshotAllowed();
    await _setNativeScreenshotFlag(!allowed);
  }
}
