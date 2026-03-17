import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'dart:math' as math;
import '../../../services/pin_auth_service.dart';

class PinSetupPage extends ConsumerStatefulWidget {
  const PinSetupPage({super.key});

  @override
  ConsumerState<PinSetupPage> createState() => _PinSetupPageState();
}

class _PinSetupPageState extends ConsumerState<PinSetupPage>
    with TickerProviderStateMixin {
  final PinAuthService _pinAuthService = PinAuthService();
  String _pin = '';
  String _confirmPin = '';
  bool _isConfirmingPin = false;
  bool _showError = false;

  late AnimationController _shieldController;
  late Animation<double> _shieldFloat;
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;
  late AnimationController _dotScaleController;

  @override
  void initState() {
    super.initState();
    _shieldController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    _shieldFloat = Tween<double>(begin: -6, end: 6).animate(
      CurvedAnimation(parent: _shieldController, curve: Curves.easeInOut),
    );

    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );

    _dotScaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
  }

  @override
  void dispose() {
    _shieldController.dispose();
    _shakeController.dispose();
    _dotScaleController.dispose();
    super.dispose();
  }

  void _onNumberPressed(String number) {
    HapticFeedback.lightImpact();
    setState(() {
      _showError = false;
      if (!_isConfirmingPin) {
        if (_pin.length < 6) {
          _pin += number;
          _dotScaleController.forward(from: 0);
          if (_pin.length == 6) {
            Future.delayed(const Duration(milliseconds: 300), () {
              if (mounted) setState(() => _isConfirmingPin = true);
            });
          }
        }
      } else {
        if (_confirmPin.length < 6) {
          _confirmPin += number;
          _dotScaleController.forward(from: 0);
          if (_confirmPin.length == 6) {
            _verifyAndSetupPin();
          }
        }
      }
    });
  }

  void _onDeletePressed() {
    HapticFeedback.selectionClick();
    setState(() {
      if (!_isConfirmingPin) {
        if (_pin.isNotEmpty) {
          _pin = _pin.substring(0, _pin.length - 1);
        }
      } else {
        if (_confirmPin.isNotEmpty) {
          _confirmPin = _confirmPin.substring(0, _confirmPin.length - 1);
        }
      }
    });
  }

  Future<void> _verifyAndSetupPin() async {
    if (_pin != _confirmPin) {
      HapticFeedback.heavyImpact();
      _shakeController.forward(from: 0);
      setState(() => _showError = true);
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) {
        setState(() {
          _pin = '';
          _confirmPin = '';
          _isConfirmingPin = false;
          _showError = false;
        });
      }
      return;
    }

    final success = await _pinAuthService.setupPin(_pin);

    if (success && mounted) {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: const [
              Icon(Icons.check_circle, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Text('PIN set up successfully!',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
      if (context.canPop()) {
        context.pop(true);
      } else {
        context.go('/dashboard');
      }
    } else if (mounted) {
      HapticFeedback.heavyImpact();
      _shakeController.forward(from: 0);
      setState(() {
        _showError = true;
        _pin = '';
        _confirmPin = '';
        _isConfirmingPin = false;
      });
    }
  }

  void _skipPinSetup() {
    context.go('/dashboard');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenH = MediaQuery.of(context).size.height;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor:
            isDark ? const Color(0xFF0A0E1A) : const Color(0xFF1A1040),
      ),
      child: Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isDark
                  ? [
                      const Color(0xFF0F0C29),
                      const Color(0xFF1A1040),
                      const Color(0xFF0A0E1A),
                    ]
                  : [
                      const Color(0xFF1A1040),
                      const Color(0xFF2D1B69),
                      const Color(0xFF0F0C29),
                    ],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                // Top bar
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new,
                            color: Colors.white70, size: 20),
                        onPressed: () =>
                            context.canPop() ? context.pop() : context.go('/dashboard'),
                      ),
                      TextButton(
                        onPressed: _skipPinSetup,
                        child: Text(
                          'Skip',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                SizedBox(height: screenH * 0.02),

                // Animated shield icon
                AnimatedBuilder(
                  animation: _shieldFloat,
                  builder: (context, child) {
                    return Transform.translate(
                      offset: Offset(0, _shieldFloat.value),
                      child: child,
                    );
                  },
                  child: Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFF8B5CF6),
                          const Color(0xFF6D28D9),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF8B5CF6).withOpacity(0.4),
                          blurRadius: 30,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: Icon(
                      _isConfirmingPin
                          ? Icons.verified_user_rounded
                          : Icons.shield_rounded,
                      color: Colors.white,
                      size: 44,
                    ),
                  ),
                ),

                SizedBox(height: screenH * 0.03),

                // Title
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, anim) =>
                      FadeTransition(opacity: anim, child: child),
                  child: Text(
                    _isConfirmingPin ? 'Confirm Your PIN' : 'Create Your PIN',
                    key: ValueKey(_isConfirmingPin),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    _showError
                        ? 'PINs didn\'t match. Try again.'
                        : _isConfirmingPin
                            ? 'Re-enter your 6-digit PIN'
                            : 'Set a 6-digit PIN to secure your wallet',
                    key: ValueKey('$_isConfirmingPin$_showError'),
                    style: TextStyle(
                      color: _showError
                          ? const Color(0xFFEF4444)
                          : Colors.white.withOpacity(0.5),
                      fontSize: 15,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

                SizedBox(height: screenH * 0.04),

                // PIN dots
                AnimatedBuilder(
                  animation: _shakeAnimation,
                  builder: (context, child) {
                    final shake = _showError
                        ? math.sin(_shakeAnimation.value * 3 * math.pi) * 12
                        : 0.0;
                    return Transform.translate(
                      offset: Offset(shake, 0),
                      child: child,
                    );
                  },
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(6, (index) {
                      final currentPin =
                          _isConfirmingPin ? _confirmPin : _pin;
                      final isFilled = index < currentPin.length;
                      final isNext = index == currentPin.length;

                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutBack,
                        margin: const EdgeInsets.symmetric(horizontal: 10),
                        width: isFilled ? 18 : 14,
                        height: isFilled ? 18 : 14,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _showError
                              ? const Color(0xFFEF4444)
                              : isFilled
                                  ? const Color(0xFF8B5CF6)
                                  : Colors.transparent,
                          border: Border.all(
                            color: _showError
                                ? const Color(0xFFEF4444)
                                : isFilled
                                    ? const Color(0xFF8B5CF6)
                                    : isNext
                                        ? Colors.white.withOpacity(0.5)
                                        : Colors.white.withOpacity(0.2),
                            width: isFilled ? 0 : 2,
                          ),
                          boxShadow: isFilled
                              ? [
                                  BoxShadow(
                                    color: (_showError
                                            ? const Color(0xFFEF4444)
                                            : const Color(0xFF8B5CF6))
                                        .withOpacity(0.5),
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

                // Step indicator
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildStepDot(true),
                    Container(
                      width: 30,
                      height: 2,
                      color: _isConfirmingPin
                          ? const Color(0xFF8B5CF6)
                          : Colors.white.withOpacity(0.15),
                    ),
                    _buildStepDot(_isConfirmingPin),
                  ],
                ),

                const Spacer(),

                // Number pad
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    children: [
                      for (int row = 0; row < 4; row++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: _buildPadRow(row),
                          ),
                        ),
                    ],
                  ),
                ),

                SizedBox(height: screenH * 0.03),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepDot(bool active) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active
            ? const Color(0xFF8B5CF6)
            : Colors.white.withOpacity(0.15),
      ),
    );
  }

  List<Widget> _buildPadRow(int row) {
    if (row < 3) {
      return List.generate(3, (col) {
        final number = (row * 3 + col + 1).toString();
        return _buildKeyButton(number);
      });
    }
    // Last row:  [biometric placeholder]  0  [delete]
    return [
      const SizedBox(width: 72),
      _buildKeyButton('0'),
      _buildDeleteKey(),
    ];
  }

  Widget _buildKeyButton(String number) {
    return GestureDetector(
      onTap: () => _onNumberPressed(number),
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.08),
          border: Border.all(
            color: Colors.white.withOpacity(0.1),
          ),
        ),
        child: Center(
          child: Text(
            number,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDeleteKey() {
    return GestureDetector(
      onTap: _onDeletePressed,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.05),
        ),
        child: Center(
          child: Icon(
            Icons.backspace_outlined,
            color: Colors.white.withOpacity(0.7),
            size: 26,
          ),
        ),
      ),
    );
  }
}
