import 'dart:async';
import 'package:flutter/services.dart';

/// Secure clipboard service that auto-clears clipboard after a timeout
/// This prevents sensitive data (addresses, keys) from being exposed
/// if the user forgets to clear clipboard or device is accessed by others
class SecureClipboardService {
  static final SecureClipboardService _instance = SecureClipboardService._internal();
  factory SecureClipboardService() => _instance;
  SecureClipboardService._internal();

  Timer? _clearTimer;
  static const Duration _defaultClearDuration = Duration(seconds: 60);
  
  // Track what was copied for verification
  String? _lastCopiedValue;

  /// Copy text to clipboard with auto-clear after timeout
  /// 
  /// [text] - The text to copy to clipboard
  /// [clearAfter] - Duration before auto-clearing (default: 60 seconds)
  /// [onCleared] - Optional callback when clipboard is cleared
  Future<void> copyWithAutoClear(
    String text, {
    Duration clearAfter = _defaultClearDuration,
    VoidCallback? onCleared,
  }) async {
    // Cancel any existing timer
    _clearTimer?.cancel();
    
    // Copy to clipboard
    await Clipboard.setData(ClipboardData(text: text));
    _lastCopiedValue = text;
    
    print('📋 Copied to clipboard (will auto-clear in ${clearAfter.inSeconds}s)');
    
    // Set timer to clear clipboard
    _clearTimer = Timer(clearAfter, () async {
      await _clearClipboard();
      onCleared?.call();
      print('🧹 Clipboard auto-cleared for security');
    });
  }

  /// Copy sensitive data (addresses, keys) with shorter timeout
  Future<void> copySensitiveData(
    String text, {
    VoidCallback? onCleared,
  }) async {
    await copyWithAutoClear(
      text,
      clearAfter: const Duration(seconds: 30), // Shorter timeout for sensitive data
      onCleared: onCleared,
    );
  }

  /// Copy wallet address with standard timeout
  Future<void> copyAddress(
    String address, {
    VoidCallback? onCleared,
  }) async {
    await copyWithAutoClear(
      address,
      clearAfter: const Duration(seconds: 60),
      onCleared: onCleared,
    );
  }

  /// Immediately clear the clipboard
  Future<void> clearNow() async {
    _clearTimer?.cancel();
    await _clearClipboard();
    print('🧹 Clipboard cleared immediately');
  }

  /// Clear the clipboard
  Future<void> _clearClipboard() async {
    try {
      // Replace clipboard content with empty string
      await Clipboard.setData(const ClipboardData(text: ''));
      _lastCopiedValue = null;
    } catch (e) {
      print('⚠️ Failed to clear clipboard: $e');
    }
  }

  /// Cancel the auto-clear timer (use when user manually clears or app closes)
  void cancelAutoClear() {
    _clearTimer?.cancel();
    _clearTimer = null;
  }

  /// Check if there's a pending auto-clear
  bool get hasPendingClear => _clearTimer?.isActive ?? false;

  /// Get remaining time before auto-clear (approximate)
  /// Note: This is an approximation since Timer doesn't expose remaining time
  String get remainingTimeText {
    if (!hasPendingClear) return 'No pending clear';
    return 'Clipboard will be cleared soon';
  }

  /// Dispose of resources
  void dispose() {
    _clearTimer?.cancel();
  }
}

/// Extension to add secure copy functionality to any widget
extension SecureClipboardExtension on String {
  /// Copy this string to clipboard with auto-clear
  Future<void> copySecure({
    Duration clearAfter = const Duration(seconds: 60),
    VoidCallback? onCleared,
  }) async {
    await SecureClipboardService().copyWithAutoClear(
      this,
      clearAfter: clearAfter,
      onCleared: onCleared,
    );
  }
}
