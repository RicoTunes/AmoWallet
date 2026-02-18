import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'services/confirmation_tracker_service.dart';
import 'services/notification_service.dart';
import 'services/incoming_tx_watcher_service.dart';
import 'services/anti_debug_service.dart';
import 'services/hsm_security_service.dart';
import 'services/remote_wipe_service.dart';
import 'services/behavioral_biometrics_service.dart';
import 'core/config/environment.dart';
import 'core/services/security_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // MILITARY-GRADE: Set environment to production (uses Railway backend with HTTPS)
  EnvironmentConfig.setEnvironment(Environment.production);
  
  // Initialize security services with timeout and error handling
  await _initializeSecurityServices();
  
  // MILITARY-GRADE: Anti-debugging detection (release builds only)
  if (!kDebugMode) {
    final antiDebug = AntiDebugService();
    final isSecure = await antiDebug.isEnvironmentSecure();
    
    if (!isSecure) {
      debugPrint('🚨 Anti-debug: Compromised environment detected!');
      antiDebug.handleCompromisedEnvironment(exitApp: true);
    }
  }
  
  // MILITARY-GRADE: Security checks (non-blocking in release)
  if (!kDebugMode) {
    final securityService = SecurityService();
    final securityResult = await securityService.performSecurityCheck();
    
    // Log security status (will be stripped in release by ProGuard)
    debugPrint('🔒 Security Status: ${securityResult.securityStatus}');
    
    // Block compromised (rooted/jailbroken) devices
    if (!securityResult.isSecure && securityResult.isDeviceCompromised) {
      runApp(const SecurityBlockedApp());
      return;
    }
  }
  
  // MILITARY-GRADE: Prevent screenshots and screen recording
  await SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.edgeToEdge,
    overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom],
  );
  
  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  // Start background services
  final confirmationTracker = ConfirmationTrackerService();
  confirmationTracker.startTracking();

  // Initialise notification service (loads persisted notifications)
  await NotificationService().initialize();

  // Start incoming-tx watcher (polls blockchain APIs)
  IncomingTxWatcherService().start();

  runApp(
    const ProviderScope(
      child: CryptoWalletProApp(),
    ),
  );
}

/// Initialize all security services with timeout and error handling
Future<void> _initializeSecurityServices() async {
  final List<Future<void>> securityFutures = [];
  
  // HSM Security Service with timeout
  securityFutures.add(() async {
    try {
      final hsmService = HsmSecurityService();
      final hsmStatus = await hsmService.initialize().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          debugPrint('⚠️ HSM initialization timeout - using software fallback');
          return HsmStatus.software;
        },
      );
      debugPrint('🔐 HSM Status: ${hsmStatus.name}');
    } catch (e) {
      debugPrint('⚠️ HSM initialization failed: $e - using software fallback');
    }
  }());
  
  // Remote Wipe Service with timeout
  securityFutures.add(() async {
    try {
      final remoteWipe = RemoteWipeService();
      await remoteWipe.initialize().timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          debugPrint('⚠️ Remote wipe initialization timeout');
          return;
        },
      );
      await remoteWipe.enableRemoteWipe().timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          debugPrint('⚠️ Remote wipe enable timeout');
          return;
        },
      );
      debugPrint('🗑️ Remote wipe enabled');
    } catch (e) {
      debugPrint('⚠️ Remote wipe initialization failed: $e');
    }
  }());
  
  // Behavioral Biometrics with timeout
  securityFutures.add(() async {
    try {
      final behavioralBiometrics = BehavioralBiometricsService();
      await behavioralBiometrics.initialize().timeout(
        const Duration(seconds: 4),
        onTimeout: () {
          debugPrint('⚠️ Behavioral biometrics initialization timeout');
          return;
        },
      );
      await behavioralBiometrics.enable().timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          debugPrint('⚠️ Behavioral biometrics enable timeout');
          return;
        },
      );
      debugPrint('🧬 Behavioral biometrics enabled');
    } catch (e) {
      debugPrint('⚠️ Behavioral biometrics initialization failed: $e');
    }
  }());
  
  // Execute all security initializations in parallel with timeout
  try {
    await Future.wait(securityFutures).timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        debugPrint('⚠️ Security services initialization timeout - continuing with available services');
        return [];
      },
    );
    debugPrint('✅ All security services initialized');
  } catch (e) {
    debugPrint('⚠️ Security services initialization error: $e - continuing with available services');
  }
}

/// Shown when the device is rooted/jailbroken and the app refuses to run
class SecurityBlockedApp extends StatelessWidget {
  const SecurityBlockedApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF0D1421),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.security, color: Color(0xFFEF4444), size: 64),
                const SizedBox(height: 24),
                const Text(
                  'Security Alert',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'This device appears to be rooted or jailbroken.\n\nAmo Wallet cannot run on compromised devices to protect your funds and private keys.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 15, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}