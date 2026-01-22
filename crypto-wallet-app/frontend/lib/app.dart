import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/constants/app_constants.dart';
import 'core/routes/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/providers/theme_provider.dart';
import 'services/pin_auth_service.dart';

class CryptoWalletProApp extends ConsumerStatefulWidget {
  const CryptoWalletProApp({super.key});

  @override
  ConsumerState<CryptoWalletProApp> createState() => _CryptoWalletProAppState();
}

class _CryptoWalletProAppState extends ConsumerState<CryptoWalletProApp> with WidgetsBindingObserver {
  final PinAuthService _pinAuthService = PinAuthService();
  bool _isAppInBackground = false;
  DateTime? _lastAuthTime;
  bool _isCheckingAuth = false; // Prevent multiple concurrent auth checks
  bool _justAuthenticated = false; // Prevent immediate re-lock after auth
  
  // Minimum time (in seconds) before requiring re-authentication
  static const int _authCooldownSeconds = 120; // 2 minutes cooldown
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadLastAuthTime();
  }
  
  Future<void> _loadLastAuthTime() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getInt('last_auth_time');
    if (timestamp != null) {
      _lastAuthTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    }
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // App is going to background
      _isAppInBackground = true;
    } else if (state == AppLifecycleState.resumed && _isAppInBackground) {
      // App is returning from background
      _isAppInBackground = false;
      _checkAuthenticationOnResume();
    }
  }
  
  Future<void> _checkAuthenticationOnResume() async {
    // Prevent concurrent auth checks
    if (_isCheckingAuth) {
      print('⏭️ Already checking auth, skipping');
      return;
    }
    _isCheckingAuth = true;
    
    try {
      // Reload last auth time from storage (may have been updated by PIN entry page)
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt('last_auth_time');
      if (timestamp != null) {
        _lastAuthTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      }
      
      // Check if we recently authenticated (within cooldown period)
      if (_lastAuthTime != null) {
        final elapsed = DateTime.now().difference(_lastAuthTime!).inSeconds;
        if (elapsed < _authCooldownSeconds) {
          print('⏭️ Skipping re-auth, only ${elapsed}s since last auth (cooldown: ${_authCooldownSeconds}s)');
          return;
        }
      }
      
      final isPinEnabled = await _pinAuthService.isPinEnabled();
      final isPinSet = await _pinAuthService.isPinSet();
      
      if (isPinEnabled && isPinSet) {
        // Save current route before navigating to PIN entry
        final router = ref.read(routerProvider);
        final currentLocation = router.routerDelegate.currentConfiguration.uri.toString();
        
        // Don't save PIN entry or splash routes, and don't redirect if already on PIN entry
        if (currentLocation.contains('/pin-entry')) {
          print('⏭️ Already on PIN entry page, skipping redirect');
          return;
        }
        
        if (!currentLocation.contains('/splash') &&
            !currentLocation.contains('/onboarding')) {
          await prefs.setString('last_route', currentLocation);
          print('💾 Saved current route: $currentLocation');
        }
        
        // Navigate to PIN entry page
        router.go('/pin-entry');
      }
    } finally {
      _isCheckingAuth = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeProvider);

    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      
      // Material Design 3 with dynamic theme switching
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      
      // Routing
      routerConfig: router,
      
      // Localization
      localizationsDelegates: const [
        // Add localization delegates here
      ],
      supportedLocales: const [
        Locale('en', 'US'),
      ],
    );
  }
}