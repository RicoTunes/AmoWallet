import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../services/pin_auth_service.dart';

class PinEntryPage extends ConsumerStatefulWidget {
  const PinEntryPage({super.key});

  @override
  ConsumerState<PinEntryPage> createState() => _PinEntryPageState();
}

class _PinEntryPageState extends ConsumerState<PinEntryPage> {
  final PinAuthService _pinAuthService = PinAuthService();
  String _pin = '';
  bool _isLoading = false;
  int _attemptCount = 0;
  String? _returnRoute;
  
  @override
  void initState() {
    super.initState();
    _loadReturnRoute();
    _checkAuthenticationMethods();
  }
  
  Future<void> _loadReturnRoute() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _returnRoute = prefs.getString('last_route') ?? '/dashboard';
    });
    print('📍 Will return to: $_returnRoute after PIN verification');
  }
  
  Future<void> _checkAuthenticationMethods() async {
    // Check if PIN is set up
    final isPinSet = await _pinAuthService.isPinSet();
    
    if (!isPinSet) {
      // No PIN set up - go to PIN setup
      if (mounted) context.go('/pin-setup');
      return;
    }
    
    // Check if biometric is enabled and available
    final isBiometricEnabled = await _pinAuthService.isBiometricEnabled();
    final isBiometricAvailable = await _pinAuthService.isBiometricAvailable();
    
    if (isBiometricEnabled && isBiometricAvailable) {
      // Try biometric authentication automatically
      _authenticateWithBiometric();
    }
  }
  
  Future<void> _authenticateWithBiometric() async {
    final success = await _pinAuthService.authenticateWithBiometric();
    
    if (success && mounted) {
      print('✅ Biometric auth success - returning to: $_returnRoute');
      context.go(_returnRoute ?? '/dashboard');
    }
  }
  
  void _onNumberPressed(String number) {
    if (_pin.length < 6) {
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
      
      // Save auth time to prevent re-authentication too soon
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('last_auth_time', DateTime.now().millisecondsSinceEpoch);
      
      try {
        context.go(_returnRoute ?? '/dashboard');
      } catch (navError) {
        // Log and fallback to Navigator in case go_router fails for some reason
        print('⚠️ Navigation error after PIN verification: $navError');
        if (mounted) {
          Navigator.of(context).pushReplacementNamed(_returnRoute ?? '/dashboard');
        }
      }
    } else {
      _attemptCount++;
      
      if (mounted) {
        // Show snackbar before mutating state to avoid disposing context used
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_attemptCount >= 3 
                ? 'Too many failed attempts. Please try again later.'
                : 'Incorrect PIN. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );

        setState(() {
          _pin = '';
          _isLoading = false;
        });
        
        if (_attemptCount >= 5) {
          // Lock out after 5 failed attempts
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
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      const SizedBox(height: 20),
                      
                      // App Icon
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          Icons.account_balance_wallet_rounded,
                          size: 32,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Title
                      const Text(
                        'Enter your PIN',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      
                      const SizedBox(height: 8),
                      
                      Text(
                        'Enter your 6-digit PIN to unlock',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                      
                      const SizedBox(height: 40),
              
              // PIN Dots
              if (!_isLoading)
                Wrap(
                  alignment: WrapAlignment.center,
                  children: List.generate(6, (index) {
                    final isFilled = index < _pin.length;
                    
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isFilled 
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey[300],
                        border: Border.all(
                          color: isFilled 
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey[400]!,
                          width: 2,
                        ),
                      ),
                    );
                  }),
                )
              else
                const CircularProgressIndicator(),
              
              const SizedBox(height: 32),
              
              // Biometric Button
              FutureBuilder<bool>(
                future: _pinAuthService.isBiometricEnabled(),
                builder: (context, snapshot) {
                  if (snapshot.data == true) {
                    return Column(
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.fingerprint,
                            size: 48,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          onPressed: _authenticateWithBiometric,
                        ),
                        const Text(
                          'Use biometric',
                          style: TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 20),
                      ],
                    );
                  }
                  return const SizedBox();
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
                  // Show dialog to reset PIN (requires wallet recovery)
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Forgot PIN?'),
                      content: const Text(
                        'To reset your PIN, you\'ll need to restore your wallet using your recovery phrase.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            context.go('/wallet-import');
                          },
                          child: const Text('Restore Wallet'),
                        ),
                      ],
                    ),
                  );
                },
                child: const Text('Forgot PIN?'),
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isLoading ? null : () => _onNumberPressed(number),
        borderRadius: BorderRadius.circular(50),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.grey[300]!, width: 1),
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w500,
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
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.grey[300]!, width: 1),
          ),
          child: const Center(
            child: Icon(Icons.backspace_outlined, size: 28),
          ),
        ),
      ),
    );
  }
}
