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
  }
  
  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
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
    if (_pin.length < 6) {
      HapticFeedback.lightImpact();
      HapticFeedback.vibrate();
      setState(() {
        _pin += number;
        if (_pin.length == 6) {
          _verifyPin();
        }
      });
    }
  }
  
  void _onDeletePressed() {
    if (_pin.isNotEmpty) {
      HapticFeedback.lightImpact();
      HapticFeedback.vibrate();
      setState(() {
        _pin = _pin.substring(0, _pin.length - 1);
      });
    }
  }
  
  Future<void> _verifyPin() async {
    setState(() {
      _isLoading = true;
    });
    
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
        
        // Navigate to fake dashboard
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
        for (int i = 0; i < 2; i++) {
          Future.delayed(Duration(milliseconds: i * 200), () {
            HapticFeedback.heavyImpact();
          });
        }
        _shakeController.forward();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(_attemptCount >= 3 
                      ? 'Too many failed attempts. Please wait.'
                      : 'Incorrect PIN. ${5 - _attemptCount} attempts remaining.'),
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
        
        if (_attemptCount >= 5) {
          await Future.delayed(const Duration(seconds: 30));
          setState(() {
            _attemptCount = 0;
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
              
              // App Logo with gradient background - smaller
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      primaryColor,
                      primaryColor.withOpacity(0.7),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: primaryColor.withOpacity(0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.account_balance_wallet_rounded,
                  size: 30,
                  color: Colors.white,
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
                'Enter your PIN to unlock',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white,
                ),
              ),
              
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
                onPressed: () {
                  final isDark = Theme.of(context).brightness == Brightness.dark;
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      title: Row(
                        children: [
                          Icon(Icons.help_outline, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 10),
                          const Text('Forgot PIN?'),
                        ],
                      ),
                      content: const Text(
                        'To reset your PIN, you\'ll need to restore your wallet using your recovery phrase.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(
                            'Cancel',
                            style: TextStyle(color: subtextColor),
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            context.go('/wallet-import');
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text('Restore Wallet'),
                        ),
                      ],
                    ),
                  );
                },
                child: Text(
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isLoading ? null : () => _onNumberPressed(number),
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
        onTap: _isLoading ? null : _onDeletePressed,
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
