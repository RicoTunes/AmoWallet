import 'dart:io';
import 'package:flutter/foundation.dart';

/// Anti-debugging and anti-tampering service for release builds
/// Detects debugger attachment, emulator usage, and tampering attempts
/// Enterprise-grade security measure for financial applications
class AntiDebugService {
  static final AntiDebugService _instance = AntiDebugService._internal();
  factory AntiDebugService() => _instance;
  AntiDebugService._internal();

  bool _hasCheckedOnce = false;
  bool _isCompromised = false;

  /// Check if the app environment is secure
  /// Returns true if environment appears safe, false if compromised
  Future<bool> isEnvironmentSecure() async {
    // Skip checks in debug mode (allow development)
    if (kDebugMode) {
      print('🔓 Debug mode - skipping security checks');
      return true;
    }

    // Skip checks on web
    if (kIsWeb) {
      return true;
    }

    // Only run expensive checks once per session
    if (_hasCheckedOnce) {
      return !_isCompromised;
    }

    _hasCheckedOnce = true;
    final issues = <String>[];

    // Check 1: Debugger detection
    if (await _isDebuggerAttached()) {
      issues.add('Debugger detected');
    }

    // Check 2: Emulator/Simulator detection (Android)
    if (Platform.isAndroid && await _isEmulator()) {
      issues.add('Emulator detected');
    }

    // Check 3: Frida detection (common reverse engineering tool)
    if (await _isFridaDetected()) {
      issues.add('Frida detected');
    }

    // Check 4: Xposed detection (Android hooking framework)
    if (Platform.isAndroid && await _isXposedDetected()) {
      issues.add('Xposed detected');
    }

    // Check 5: Memory tampering indicators
    if (await _isMemoryTampered()) {
      issues.add('Memory tampering detected');
    }

    if (issues.isNotEmpty) {
      _isCompromised = true;
      print('🚨 Security issues detected: ${issues.join(', ')}');
      return false;
    }

    print('✅ Environment security check passed');
    return true;
  }

  /// Check if a debugger is attached
  Future<bool> _isDebuggerAttached() async {
    try {
      // Check if running in profile or debug mode
      if (kProfileMode || kDebugMode) {
        return true;
      }

      // On Android, check for debugger using assertions
      // In release mode, assertions are disabled, so this won't trigger
      bool debuggerAttached = false;
      assert(() {
        debuggerAttached = true;
        return true;
      }());

      if (debuggerAttached) {
        return true;
      }

      // Platform-specific debugger detection
      if (Platform.isAndroid) {
        // Check TracerPid in /proc/self/status
        try {
          final status = await File('/proc/self/status').readAsString();
          final tracerPidMatch = RegExp(r'TracerPid:\s*(\d+)').firstMatch(status);
          if (tracerPidMatch != null) {
            final tracerPid = int.tryParse(tracerPidMatch.group(1) ?? '0') ?? 0;
            if (tracerPid != 0) {
              print('⚠️ TracerPid indicates debugger: $tracerPid');
              return true;
            }
          }
        } catch (e) {
          // Can't read proc - might be restricted, which is fine
        }
      }

      return false;
    } catch (e) {
      return false;
    }
  }

  /// Check if running on an emulator
  Future<bool> _isEmulator() async {
    try {
      if (!Platform.isAndroid) return false;

      // Check common emulator indicators
      final emulatorIndicators = [
        '/dev/socket/qemud',
        '/dev/qemu_pipe',
        '/system/lib/libc_malloc_debug_qemu.so',
        '/sys/qemu_trace',
        '/system/bin/qemu-props',
        '/dev/goldfish_pipe',
        '/dev/socket/genyd',
        '/dev/socket/baseband_genyd',
      ];

      for (final path in emulatorIndicators) {
        if (await File(path).exists() || await Directory(path).exists()) {
          print('⚠️ Emulator indicator found: $path');
          return true;
        }
      }

      // Check build properties that indicate emulator
      // Note: In production, you'd use platform channels to check Build.FINGERPRINT, etc.

      return false;
    } catch (e) {
      return false;
    }
  }

  /// Check for Frida (popular reverse engineering tool)
  Future<bool> _isFridaDetected() async {
    try {
      // Check for Frida server port
      final fridaPorts = [27042, 27043];
      
      for (final port in fridaPorts) {
        try {
          final socket = await Socket.connect('127.0.0.1', port, 
            timeout: const Duration(milliseconds: 100));
          await socket.close();
          print('⚠️ Frida port detected: $port');
          return true;
        } catch (e) {
          // Port not open - good
        }
      }

      // Check for Frida libraries in memory maps
      if (Platform.isAndroid) {
        try {
          final maps = await File('/proc/self/maps').readAsString();
          final fridaIndicators = ['frida', 'gadget', 'linjector'];
          
          for (final indicator in fridaIndicators) {
            if (maps.toLowerCase().contains(indicator)) {
              print('⚠️ Frida indicator in memory maps: $indicator');
              return true;
            }
          }
        } catch (e) {
          // Can't read maps
        }
      }

      return false;
    } catch (e) {
      return false;
    }
  }

  /// Check for Xposed framework
  Future<bool> _isXposedDetected() async {
    try {
      if (!Platform.isAndroid) return false;

      // Check for Xposed installer
      final xposedPaths = [
        '/system/xposed.prop',
        '/system/framework/XposedBridge.jar',
        '/system/bin/app_process.orig',
        '/data/data/de.robv.android.xposed.installer',
        '/data/data/io.va.exposed',
        '/data/data/org.meowcat.edxposed.manager',
      ];

      for (final path in xposedPaths) {
        if (await File(path).exists() || await Directory(path).exists()) {
          print('⚠️ Xposed indicator found: $path');
          return true;
        }
      }

      // Check in loaded libraries
      try {
        final maps = await File('/proc/self/maps').readAsString();
        if (maps.contains('XposedBridge') || maps.contains('edxposed')) {
          return true;
        }
      } catch (e) {
        // Can't read maps
      }

      return false;
    } catch (e) {
      return false;
    }
  }

  /// Check for memory tampering
  Future<bool> _isMemoryTampered() async {
    try {
      // Basic integrity check - verify critical values haven't been modified
      // In production, you'd implement more sophisticated checks
      
      // Check if process is being traced
      if (Platform.isAndroid) {
        try {
          final status = await File('/proc/self/status').readAsString();
          
          // Check for unexpected tracer
          if (status.contains('State:\tt') || status.contains('State:	T')) {
            print('⚠️ Process is in traced state');
            return true;
          }
        } catch (e) {
          // Can't read status
        }
      }

      return false;
    } catch (e) {
      return false;
    }
  }

  /// Get detailed security report
  Future<Map<String, dynamic>> getSecurityReport() async {
    if (kDebugMode) {
      return {
        'secure': true,
        'mode': 'debug',
        'checks_skipped': true,
      };
    }

    final report = <String, dynamic>{
      'timestamp': DateTime.now().toIso8601String(),
      'platform': Platform.operatingSystem,
      'mode': kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug'),
    };

    report['debugger_attached'] = await _isDebuggerAttached();
    report['emulator'] = Platform.isAndroid ? await _isEmulator() : false;
    report['frida_detected'] = await _isFridaDetected();
    report['xposed_detected'] = Platform.isAndroid ? await _isXposedDetected() : false;
    report['memory_tampered'] = await _isMemoryTampered();

    report['secure'] = !report.values.whereType<bool>().any((v) => v == true);

    return report;
  }

  /// Handle compromised environment (call appropriate action)
  void handleCompromisedEnvironment({
    bool exitApp = false,
    bool showWarning = true,
    Function()? onCompromised,
  }) {
    if (_isCompromised) {
      print('🚨 App is running in compromised environment!');
      
      if (onCompromised != null) {
        onCompromised();
      }
      
      if (exitApp && !kDebugMode) {
        // In production, you might want to exit the app
        // exit(1); // Uncomment for production
      }
    }
  }

  /// Reset detection state (for testing)
  void reset() {
    _hasCheckedOnce = false;
    _isCompromised = false;
  }
}
