import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../services/pin_auth_service.dart';
import '../../../core/providers/fake_wallet_provider.dart';

class PinEntryPage extends ConsumerStatefulWidget {
  const PinEntryPage({super.key});

  @override
  ConsumerState<PinEntryPage> createState() => _PinEntryPageState();
}

class _PinEntryPageState extends ConsumerState<PinEntryPage> 
    with SingleTickerProviderStateMixin {
  final PinAuthService _pinAuthService = PinAuthService();
  String _pin = '';
  bool _isLoading = false;
  int _attemptCount = 0;
  String? _returnRoute;
  bool _biometricAttempted = false;
  bool _isAuthenticating = false;
  
  // Lockout timer
  bool _isLockedOut = false;
  Duration _remainingLockout = Duration.zero;
  Timer? _lockoutTimer;
  
  // Static flag to prevent biometric from being called multiple times globally
  static bool _globalBiometricInProgress = false;
  
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;
  
  @override
  void initState() {
    super.initState();
    
    // Shake animation for wrong PIN
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 24)
        .chain(CurveTween(curve: Curves.elasticIn))
        .animate(_shakeController);
    _shakeController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _shakeController.reverse();
      }
    });
    
    _loadReturnRoute();
    _checkAuthenticationMethods();
    _checkLockout();
  }
  
  @override
  void dispose() {
    _shakeController.dispose();
    _lockoutTimer?.cancel();
    super.dispose();
  }
  
  Future<void> _checkLockout() async {
    final locked = await _pinAuthService.isLockedOut();
    if (locked) {
      final remaining = await _pinAuthService.getRemainingLockoutDuration();
      setState(() {
        _isLockedOut = true;
        _remainingLockout = remaining;
      });
      _startLockoutCountdown();
    }
  }
  
  void _startLockoutCountdown() {
    _lockoutTimer?.cancel();
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_remainingLockout.inSeconds <= 1) {
        _lockoutTimer?.cancel();
        setState(() {
          _isLockedOut = false;
          _remainingLockout = Duration.zero;
          _attemptCount = 0;
        });
      } else {
        setState(() {
          _remainingLockout -= const Duration(seconds: 1);
        });
      }
    });
  }
  
  String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours}h ${d.inMinutes.remainder(60)}m ${d.inSeconds.remainder(60)}s';
    } else if (d.inMinutes > 0) {
      return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
    }
    return '${d.inSeconds}s';
  }
  
  Future<void> _loadReturnRoute() async {
    // If duress mode is already active (persisted), go straight to fake dashboard
    final fakeWalletState = ref.read(fakeWalletProvider);
    if (fakeWalletState.isActive && fakeWalletState.isDuressMode) {
      debugPrint('🎭 Duress mode already active - redirecting to fake dashboard');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/fake-dashboard');
      });
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    // Allow all main app pages as return route (including send, swap, receive)
    final allowedRoutes = ['/dashboard', '/portfolio', '/coins', '/settings', '/send', '/swap', '/receive', '/transactions'];
    final savedRoute = prefs.getString('last_route');
    if (savedRoute != null && allowedRoutes.any((r) => savedRoute.startsWith(r))) {
      setState(() {
        _returnRoute = savedRoute;
      });
      debugPrint('📍 Will return to: $_returnRoute after PIN verification');
    } else {
      setState(() {
        _returnRoute = '/dashboard';
      });
      debugPrint('📍 Forced return to dashboard after PIN verification');
    }
  }
  
  Future<void> _checkAuthenticationMethods() async {
    // Check all flags including global to prevent double popup
    if (_isAuthenticating || _biometricAttempted || _globalBiometricInProgress) {
      debugPrint('⏭️ _checkAuthenticationMethods skipped - biometric already in progress');
      return;
    }
    
    final isPinSet = await _pinAuthService.isPinSet();
    
    if (!isPinSet) {
      if (mounted) context.go('/pin-setup');
      return;
    }
    
    final isBiometricEnabled = await _pinAuthService.isBiometricEnabled();
    final isBiometricAvailable = await _pinAuthService.isBiometricAvailable();
    
    if (isBiometricEnabled && isBiometricAvailable && !_biometricAttempted && !_globalBiometricInProgress) {
      _authenticateWithBiometric();
    }
  }
  
  Future<void> _authenticateWithBiometric() async {
    // Check both local and global flags to prevent double popup
    if (_biometricAttempted || _isAuthenticating || _globalBiometricInProgress) {
      debugPrint('⏭️ Skipping biometric - already in progress (local: $_biometricAttempted, auth: $_isAuthenticating, global: $_globalBiometricInProgress)');
      return;
    }
    
    setState(() {
      _biometricAttempted = true;
      _isAuthenticating = true;
    });
    _globalBiometricInProgress = true;
    
    try {
      final success = await _pinAuthService.authenticateWithBiometric();
      
      if (success && mounted) {
        debugPrint('✅ Biometric auth success - returning to: $_returnRoute');
        
        // Save auth time FIRST before any navigation
        final prefs = await SharedPreferences.getInstance();
        final authTime = DateTime.now().millisecondsSinceEpoch;
        await prefs.setInt('last_auth_time', authTime);
        debugPrint('💾 Saved auth time: $authTime');
        
        // Small delay to ensure auth time is saved before navigation
        await Future.delayed(const Duration(milliseconds: 100));
        
        // Reset global flag before navigation
        _globalBiometricInProgress = false;
        
        if (mounted) {
          final targetRoute = _returnRoute ?? '/dashboard';
          debugPrint('🚀 Navigating to: $targetRoute');
          context.go(targetRoute);
        }
      } else {
        debugPrint('❌ Biometric auth failed or cancelled - please enter PIN');
        _globalBiometricInProgress = false;
        if (mounted) {
          setState(() {
            _isAuthenticating = false;
            _biometricAttempted = false; // Allow retry on button press
          });
        }
      }
    } catch (e) {
      debugPrint('❌ Biometric error: $e');
      _globalBiometricInProgress = false;
      if (mounted) {
        setState(() {
          _isAuthenticating = false;
          _biometricAttempted = false; // Allow retry on button press
        });
      }
    }
  }
  
  void _onNumberPressed(String number) {
    if (_isLockedOut || _pin.length >= 6) return;
    HapticFeedback.lightImpact();
    HapticFeedback.vibrate();
    setState(() {
      _pin += number;
      if (_pin.length == 6) {
        _verifyPin();
      }
    });
  }
  
  void _onDeletePressed() {
    if (_isLockedOut) return;
    if (_pin.isNotEmpty) {
      HapticFeedback.lightImpact();
      HapticFeedback.vibrate();
      setState(() {
        _pin = _pin.substring(0, _pin.length - 1);
      });
    }
  }
  
  Future<void> _verifyPin() async {
    if (_isLockedOut) return;
    
    setState(() {
      _isLoading = true;
    });
    
    // Check lockout before even trying
    final locked = await _pinAuthService.isLockedOut();
    if (locked) {
      final remaining = await _pinAuthService.getRemainingLockoutDuration();
      setState(() {
        _isLockedOut = true;
        _remainingLockout = remaining;
        _pin = '';
        _isLoading = false;
      });
      _startLockoutCountdown();
      return;
    }
    
    final isValid = await _pinAuthService.verifyPin(_pin, ref: ref);
    
    if (isValid && mounted) {
      debugPrint('✅ PIN verification success - returning to: $_returnRoute');
      HapticFeedback.mediumImpact();
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('last_auth_time', DateTime.now().millisecondsSinceEpoch);
      
      try {
        context.go(_returnRoute ?? '/dashboard');
      } catch (navError) {
        debugPrint('⚠️ Navigation error after PIN verification: $navError');
        if (mounted) {
          Navigator.of(context).pushReplacementNamed(_returnRoute ?? '/dashboard');
        }
      }
    } else if (!isValid && mounted) {
      // Check if fake wallet was activated (duress PIN)
      final fakeWalletState = ref.read(fakeWalletProvider);
      if (fakeWalletState.isActive && fakeWalletState.isDuressMode) {
        debugPrint('🎭 Fake wallet activated - showing decoy dashboard');
        HapticFeedback.mediumImpact();
        try {
          context.go('/fake-dashboard');
        } catch (navError) {
          debugPrint('⚠️ Navigation error to fake dashboard: $navError');
        }
      } else {
        // Regular invalid PIN
        _attemptCount++;
        HapticFeedback.heavyImpact();
        HapticFeedback.vibrate();
        _shakeController.forward();
        
        // Check if lockout was triggered by the service
        final nowLocked = await _pinAuthService.isLockedOut();
        if (nowLocked) {
          final remaining = await _pinAuthService.getRemainingLockoutDuration();
          setState(() {
            _isLockedOut = true;
            _remainingLockout = remaining;
            _pin = '';
            _isLoading = false;
            _attemptCount = 0;
          });
          _startLockoutCountdown();
        } else {
          final remainingAttempts = await _pinAuthService.getRemainingAttempts();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.white),
                    const SizedBox(width: 8),
                    Text('Incorrect PIN. $remainingAttempts attempt${remainingAttempts == 1 ? '' : 's'} remaining.'),
                  ],
                ),
                backgroundColor: Colors.red.shade700,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                margin: const EdgeInsets.all(16),
              ),
            );
          }
          setState(() {
            _pin = '';
            _isLoading = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final backgroundColor = isDark ? const Color(0xFF121212) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtextColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    
    return Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        children: [
          // Background image
          Container(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/images/apponboarding.png'),
                fit: BoxFit.cover,
              ),
            ),
          ),
          // Dark overlay for readability
          Container(
            color: Colors.black.withOpacity(0.4),
          ),
          // Content
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
          child: Column(
            children: [
              const SizedBox(height: 16),
              
              // App Logo - helmet image
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: primaryColor.withOpacity(0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: Image.asset(
                    'assets/icons/applogonnewhelpmet.png',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Welcome text - smaller
              Text(
                'Welcome Back',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                  letterSpacing: -0.5,
                ),
              ),
              
              const SizedBox(height: 4),
              
              Text(
                _isLockedOut ? 'Account Temporarily Locked' : 'Enter your PIN to unlock',
                style: TextStyle(
                  fontSize: 13,
                  color: _isLockedOut ? Colors.redAccent : Colors.white,
                ),
              ),
              
              // Lockout countdown banner
              if (_isLockedOut) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.withOpacity(0.4)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.lock_clock, color: Colors.redAccent, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Try again in ${_formatDuration(_remainingLockout)}',
                            style: const TextStyle(color: Colors.redAccent, fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      GestureDetector(
                        onTap: () => context.go('/forgot-pin'),
                        child: Text(
                          'Use recovery phrase to unlock now',
                          style: TextStyle(
                            color: primaryColor,
                            fontSize: 12,
                            decoration: TextDecoration.underline,
                            decorationColor: primaryColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              
              const SizedBox(height: 24),
              
              // PIN Dots with animation
              AnimatedBuilder(
                animation: _shakeAnimation,
                builder: (context, child) {
                  return Transform.translate(
                    offset: Offset(_shakeAnimation.value * ((_shakeController.status == AnimationStatus.reverse) ? -1 : 1), 0),
                    child: child,
                  );
                },
                child: _isLoading
                    ? SizedBox(
                        height: 40,
                        child: Center(
                          child: CircularProgressIndicator(
                            color: primaryColor,
                            strokeWidth: 2,
                          ),
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(6, (index) {
                          final isFilled = index < _pin.length;
                          
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                            width: isFilled ? 16 : 14,
                            height: isFilled ? 16 : 14,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isFilled ? primaryColor : Colors.transparent,
                              border: Border.all(
                                color: isFilled ? primaryColor : subtextColor.withOpacity(0.5),
                                width: 2,
                              ),
                              boxShadow: isFilled
                                  ? [
                                      BoxShadow(
                                        color: primaryColor.withOpacity(0.4),
                                        blurRadius: 6,
                                        spreadRadius: 1,
                                      ),
                                    ]
                                  : null,
                            ),
                          );
                        }),
                      ),
              ),
              
              const SizedBox(height: 20),
              
              // Biometric Button
              FutureBuilder<bool>(
                future: _pinAuthService.isBiometricEnabled(),
                builder: (context, snapshot) {
                  if (snapshot.data == true) {
                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white,
                          width: 2,
                        ),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _authenticateWithBiometric,
                          borderRadius: BorderRadius.circular(12),
                          splashColor: Colors.white.withOpacity(0.2),
                          highlightColor: Colors.white.withOpacity(0.1),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.fingerprint,
                                  size: 24,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Use Biometric',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
              
              const SizedBox(height: 24),
              
              // Number Pad - compact layout
              GridView.count(
                shrinkWrap: true,
                crossAxisCount: 3,
                childAspectRatio: 1.6,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  ...List.generate(9, (index) {
                    final number = (index + 1).toString();
                    return _buildNumberButton(number);
                  }),
                  const SizedBox(), // Empty space
                  _buildNumberButton('0'),
                  _buildDeleteButton(),
                ],
              ),
              
              const SizedBox(height: 16),
              
              // Forgot PIN
              TextButton(
                onPressed: () => context.go('/forgot-pin'),
                child: const Text(
                  'Forgot PIN?',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildNumberButton(String number) {
    final disabled = _isLoading || _isLockedOut;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: disabled ? null : () => _onNumberPressed(number),
        borderRadius: BorderRadius.circular(50),
        splashColor: Colors.white.withOpacity(0.2),
        highlightColor: Colors.white.withOpacity(0.1),
        onLongPress: null,
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withOpacity(0.1),
            border: Border.all(
              color: Colors.white.withOpacity(0.5),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.white.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildDeleteButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: (_isLoading || _isLockedOut) ? null : _onDeletePressed,
        borderRadius: BorderRadius.circular(50),
        splashColor: Colors.white.withOpacity(0.2),
        highlightColor: Colors.white.withOpacity(0.1),
        onLongPress: null,
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withOpacity(0.1),
            border: Border.all(
              color: Colors.white.withOpacity(0.5),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.white.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Center(
            child: Icon(
              Icons.backspace_outlined,
              size: 26,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
