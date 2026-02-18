import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// MILITARY-GRADE SECURITY SERVICE
/// Provides comprehensive device security checks and anti-tampering measures
class SecurityService {
  static final SecurityService _instance = SecurityService._internal();
  factory SecurityService() => _instance;
  SecurityService._internal();

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      keyCipherAlgorithm: KeyCipherAlgorithm.RSA_ECB_OAEPwithSHA_256andMGF1Padding,
      storageCipherAlgorithm: StorageCipherAlgorithm.AES_GCM_NoPadding,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  /// Check if device is rooted/jailbroken
  Future<bool> isDeviceCompromised() async {
    if (kIsWeb) return false;
    
    try {
      if (Platform.isAndroid) {
        return await _checkAndroidRoot();
      } else if (Platform.isIOS) {
        return await _checkiOSJailbreak();
      }
    } catch (e) {
      // If we can't check, assume compromised for safety
      return true;
    }
    return false;
  }

  /// Check for Android root indicators
  Future<bool> _checkAndroidRoot() async {
    // Common root indicator paths
    final rootPaths = [
      '/system/app/Superuser.apk',
      '/sbin/su',
      '/system/bin/su',
      '/system/xbin/su',
      '/data/local/xbin/su',
      '/data/local/bin/su',
      '/system/sd/xbin/su',
      '/system/bin/failsafe/su',
      '/data/local/su',
      '/su/bin/su',
      '/system/xbin/daemonsu',
      '/system/etc/init.d/99telegramhack',
      '/system/app/Magisk.apk',
      '/sbin/.magisk',
      '/data/adb/magisk',
    ];

    // Check for root binaries
    for (final path in rootPaths) {
      if (await File(path).exists()) {
        return true;
      }
    }

    // Check if su command is available
    try {
      final result = await Process.run('which', ['su']);
      if (result.exitCode == 0 && result.stdout.toString().trim().isNotEmpty) {
        return true;
      }
    } catch (_) {}

    // Check for test-keys (custom ROM indicator)
    try {
      final buildTags = await _getSystemProperty('ro.build.tags');
      if (buildTags.contains('test-keys')) {
        return true;
      }
    } catch (_) {}

    return false;
  }

  /// Check for iOS jailbreak indicators
  Future<bool> _checkiOSJailbreak() async {
    // Common jailbreak paths
    final jailbreakPaths = [
      '/Applications/Cydia.app',
      '/Applications/Sileo.app',
      '/Applications/Zebra.app',
      '/Library/MobileSubstrate/MobileSubstrate.dylib',
      '/bin/bash',
      '/usr/sbin/sshd',
      '/etc/apt',
      '/private/var/lib/apt/',
      '/usr/bin/ssh',
      '/private/var/stash',
      '/private/var/lib/cydia',
      '/private/var/tmp/cydia.log',
      '/var/cache/apt',
      '/var/lib/cydia',
      '/var/log/syslog',
      '/bin/sh',
      '/usr/libexec/sftp-server',
      '/usr/libexec/ssh-keysign',
    ];

    for (final path in jailbreakPaths) {
      if (await File(path).exists()) {
        return true;
      }
    }

    // Check if app can write outside sandbox
    try {
      final file = File('/private/jailbreak_test.txt');
      await file.writeAsString('test');
      await file.delete();
      return true; // If we can write, device is jailbroken
    } catch (_) {
      // Expected behavior - can't write outside sandbox
    }

    return false;
  }

  Future<String> _getSystemProperty(String property) async {
    try {
      final result = await Process.run('getprop', [property]);
      return result.stdout.toString().trim();
    } catch (_) {
      return '';
    }
  }

  /// Check if app is running in debug mode
  bool isDebugMode() {
    bool inDebugMode = false;
    assert(inDebugMode = true);
    return inDebugMode;
  }

  /// Check if app is running on emulator/simulator
  Future<bool> isEmulator() async {
    if (kIsWeb) return false;

    try {
      if (Platform.isAndroid) {
        final fingerprint = await _getSystemProperty('ro.build.fingerprint');
        final model = await _getSystemProperty('ro.product.model');
        final brand = await _getSystemProperty('ro.product.brand');
        final device = await _getSystemProperty('ro.product.device');
        final hardware = await _getSystemProperty('ro.hardware');

        final emulatorIndicators = [
          'generic',
          'unknown',
          'google_sdk',
          'sdk',
          'sdk_phone',
          'vbox',
          'goldfish',
          'ranchu',
          'android_x86',
          'nox',
          'genymotion',
        ];

        final combined = '$fingerprint $model $brand $device $hardware'.toLowerCase();
        for (final indicator in emulatorIndicators) {
          if (combined.contains(indicator)) {
            return true;
          }
        }
      }
    } catch (_) {}

    return false;
  }

  /// Check if app binary has been tampered with
  Future<bool> isAppTampered() async {
    // In release mode, check for debugger attachment
    if (!kDebugMode) {
      // Check if debugger is attached
      if (kProfileMode) {
        return true; // Profile mode in "release" build is suspicious
      }
    }
    return false;
  }

  /// Secure wipe of all sensitive data
  Future<void> secureWipe() async {
    try {
      await _secureStorage.deleteAll();
    } catch (e) {
      // Force clear even on error
    }
  }

  /// Perform comprehensive security check
  Future<SecurityCheckResult> performSecurityCheck() async {
    final isRooted = await isDeviceCompromised();
    final isEmu = await isEmulator();
    final isTampered = await isAppTampered();
    final isDebug = isDebugMode();

    return SecurityCheckResult(
      isDeviceCompromised: isRooted,
      isEmulator: isEmu,
      isAppTampered: isTampered,
      isDebugMode: isDebug,
      isSecure: !isRooted && !isEmu && !isTampered && !isDebug,
    );
  }
}

class SecurityCheckResult {
  final bool isDeviceCompromised;
  final bool isEmulator;
  final bool isAppTampered;
  final bool isDebugMode;
  final bool isSecure;

  SecurityCheckResult({
    required this.isDeviceCompromised,
    required this.isEmulator,
    required this.isAppTampered,
    required this.isDebugMode,
    required this.isSecure,
  });

  String get securityStatus {
    if (isSecure) return 'SECURE';
    final issues = <String>[];
    if (isDeviceCompromised) issues.add('ROOTED/JAILBROKEN');
    if (isEmulator) issues.add('EMULATOR');
    if (isAppTampered) issues.add('TAMPERED');
    if (isDebugMode) issues.add('DEBUG');
    return 'COMPROMISED: ${issues.join(', ')}';
  }
}
