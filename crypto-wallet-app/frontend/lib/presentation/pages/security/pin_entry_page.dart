import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../services/pin_auth_service.dart';
import '../../../core/providers/theme_provider.dart';

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
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _returnRoute = prefs.getString('last_route') ?? '/dashboard';
    });
    print('📍 Will return to: $_returnRoute after PIN verification');
  }
  
  Future<void> _checkAuthenticationMethods() async {
    if (_isAuthenticating || _biometricAttempted) return;
    
    final isPinSet = await _pinAuthService.isPinSet();
    
    if (!isPinSet) {
      if (mounted) context.go('/pin-setup');
      return;
    }
    
    final isBiometricEnabled = await _pinAuthService.isBiometricEnabled();
    final isBiometricAvailable = await _pinAuthService.isBiometricAvailable();
    
    if (isBiometricEnabled && isBiometricAvailable && !_biometricAttempted) {
      _authenticateWithBiometric();
    }
  }
  
  Future<void> _authenticateWithBiometric() async {
    if (_biometricAttempted || _isAuthenticating) {
      print('⏭️ Skipping biometric - already attempted or authenticating');
      return;
    }
    
    setState(() {
      _biometricAttempted = true;
      _isAuthenticating = true;
    });
    
    try {
      final success = await _pinAuthService.authenticateWithBiometric();
      
      if (success && mounted) {
        print('✅ Biometric auth success - returning to: $_returnRoute');
        
        // Save auth time FIRST before any navigation
        final prefs = await SharedPreferences.getInstance();
        final authTime = DateTime.now().millisecondsSinceEpoch;
        await prefs.setInt('last_auth_time', authTime);
        print('💾 Saved auth time: $authTime');
        
        // Small delay to ensure auth time is saved before navigation
        await Future.delayed(const Duration(milliseconds: 100));
        
        if (mounted) {
          final targetRoute = _returnRoute ?? '/dashboard';
          print('🚀 Navigating to: $targetRoute');
          context.go(targetRoute);
        }
      } else {
        print('❌ Biometric auth failed or cancelled - please enter PIN');
        if (mounted) {
          setState(() => _isAuthenticating = false);
        }
      }
    } catch (e) {
      print('❌ Biometric error: $e');
      if (mounted) {
        setState(() => _isAuthenticating = false);
      }
    }
  }
  
  void _onNumberPressed(String number) {
    if (_pin.length < 6) {
      HapticFeedback.lightImpact();
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
      setState(() {
        _pin = _pin.substring(0, _pin.length - 1);
      });
    }
  }
  
  Future<void> _verifyPin() async {
    setState(() {
      _isLoading = true;
    });
    
    final isValid = await _pinAuthService.verifyPin(_pin);
    
    if (isValid && mounted) {
      print('✅ PIN verification success - returning to: $_returnRoute');
      HapticFeedback.mediumImpact();
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('last_auth_time', DateTime.now().millisecondsSinceEpoch);
      
      try {
        context.go(_returnRoute ?? '/dashboard');
      } catch (navError) {
        print('⚠️ Navigation error after PIN verification: $navError');
        if (mounted) {
          Navigator.of(context).pushReplacementNamed(_returnRoute ?? '/dashboard');
        }
      }
    } else {
      _attemptCount++;
      HapticFeedback.heavyImpact();
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
    final surfaceColor = isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade50;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtextColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    
    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
                  child: Column(
                    children: [
                      const SizedBox(height: 40),
                      
                      // App Logo with gradient background
                      Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              primaryColor,
                              primaryColor.withOpacity(0.7),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: primaryColor.withOpacity(0.4),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.account_balance_wallet_rounded,
                          size: 45,
                          color: Colors.white,
                        ),
                      ),
                      
                      const SizedBox(height: 32),
                      
                      // Welcome text
                      Text(
                        'Welcome Back',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                          letterSpacing: -0.5,
                        ),
                      ),
                      
                      const SizedBox(height: 8),
                      
                      Text(
                        'Enter your PIN to unlock AmoWallet',
                        style: TextStyle(
                          fontSize: 15,
                          color: subtextColor,
                        ),
                      ),
                      
                      const SizedBox(height: 48),
              
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
                        height: 50,
                        child: Center(
                          child: CircularProgressIndicator(
                            color: primaryColor,
                            strokeWidth: 3,
                          ),
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(6, (index) {
                          final isFilled = index < _pin.length;
                          
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 10),
                            width: isFilled ? 20 : 18,
                            height: isFilled ? 20 : 18,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isFilled ? primaryColor : Colors.transparent,
                              border: Border.all(
                                color: isFilled ? primaryColor : subtextColor.withOpacity(0.5),
                                width: 2.5,
                              ),
                              boxShadow: isFilled
                                  ? [
                                      BoxShadow(
                                        color: primaryColor.withOpacity(0.4),
                                        blurRadius: 8,
                                        spreadRadius: 1,
                                      ),
                                    ]
                                  : null,
                            ),
                          );
                        }),
                      ),
              ),
              
              const SizedBox(height: 40),
              
              // Biometric Button
              FutureBuilder<bool>(
                future: _pinAuthService.isBiometricEnabled(),
                builder: (context, snapshot) {
                  if (snapshot.data == true) {
                    return Column(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: surfaceColor,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: primaryColor.withOpacity(0.3),
                              width: 1.5,
                            ),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _authenticateWithBiometric,
                              borderRadius: BorderRadius.circular(16),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.fingerprint,
                                      size: 28,
                                      color: primaryColor,
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      'Use Biometric',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: primaryColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                      ],
                    );
                  }
                  return const SizedBox(height: 16);
                },
              ),
              
              // Number Pad
              GridView.count(
                shrinkWrap: true,
                crossAxisCount: 3,
                childAspectRatio: 1.5,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
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
              
              const SizedBox(height: 20),
              
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
                    color: subtextColor,
                    fontSize: 14,
                  ),
                ),
              ),
              
              const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
  
  Widget _buildNumberButton(String number) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final surfaceColor = isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade100;
    final textColor = isDark ? Colors.white : Colors.black87;
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isLoading ? null : () => _onNumberPressed(number),
        borderRadius: BorderRadius.circular(50),
        splashColor: primaryColor.withOpacity(0.3),
        highlightColor: primaryColor.withOpacity(0.1),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: surfaceColor,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: Text(
              number,
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildDeleteButton() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final surfaceColor = isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade100;
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isLoading ? null : _onDeletePressed,
        borderRadius: BorderRadius.circular(50),
        splashColor: Colors.red.withOpacity(0.3),
        highlightColor: Colors.red.withOpacity(0.1),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: surfaceColor,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: Icon(
              Icons.backspace_outlined,
              size: 26,
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            ),
          ),
        ),
      ),
    );
  }
}
