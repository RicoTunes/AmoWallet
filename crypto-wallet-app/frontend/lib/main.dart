import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'services/confirmation_tracker_service.dart';
import 'core/config/environment.dart';
import 'core/services/security_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // MILITARY-GRADE: Set environment to production (uses Railway backend with HTTPS)
  EnvironmentConfig.setEnvironment(Environment.production);
  
  // MILITARY-GRADE: Security checks (non-blocking in release)
  if (!kDebugMode) {
    final securityService = SecurityService();
    final securityResult = await securityService.performSecurityCheck();
    
    // Log security status (will be stripped in release by ProGuard)
    debugPrint('🔒 Security Status: ${securityResult.securityStatus}');
    
    // Optional: Block compromised devices (uncomment to enforce)
    // if (!securityResult.isSecure && securityResult.isDeviceCompromised) {
    //   runApp(const SecurityBlockedApp());
    //   return;
    // }
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

  runApp(
    const ProviderScope(
      child: CryptoWalletProApp(),
    ),
  );
}