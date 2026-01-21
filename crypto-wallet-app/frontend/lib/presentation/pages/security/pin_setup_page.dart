import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../services/pin_auth_service.dart';

class PinSetupPage extends ConsumerStatefulWidget {
  const PinSetupPage({super.key});

  @override
  ConsumerState<PinSetupPage> createState() => _PinSetupPageState();
}

class _PinSetupPageState extends ConsumerState<PinSetupPage> {
  final PinAuthService _pinAuthService = PinAuthService();
  String _pin = '';
  String _confirmPin = '';
  bool _isConfirmingPin = false;
  
  void _onNumberPressed(String number) {
    setState(() {
      if (!_isConfirmingPin) {
        if (_pin.length < 6) {
          _pin += number;
          if (_pin.length == 6) {
            Future.delayed(const Duration(milliseconds: 200), () {
              setState(() {
                _isConfirmingPin = true;
              });
            });
          }
        }
      } else {
        if (_confirmPin.length < 6) {
          _confirmPin += number;
          if (_confirmPin.length == 6) {
            _verifyAndSetupPin();
          }
        }
      }
    });
  }
  
  void _onDeletePressed() {
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
      // PINs don't match
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PINs do not match. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() {
        _pin = '';
        _confirmPin = '';
        _isConfirmingPin = false;
      });
      return;
    }
    
    // Set up PIN
    final success = await _pinAuthService.setupPin(_pin);
    
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PIN setup successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      
      // Pop back to previous screen (security settings or onboarding)
      if (context.canPop()) {
        context.pop(true); // Return true to indicate success
      } else {
        context.go('/dashboard');
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to setup PIN. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() {
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
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => context.pop(),
                  ),
                  TextButton(
                    onPressed: _skipPinSetup,
                    child: const Text('Skip'),
                  ),
                ],
              ),
              
              const SizedBox(height: 40),
              
              // Title
              Text(
                _isConfirmingPin ? 'Confirm your PIN' : 'Create a PIN',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              
              const SizedBox(height: 10),
              
              Text(
                _isConfirmingPin 
                    ? 'Re-enter your PIN to confirm'
                    : 'Create a 6-digit PIN to secure your wallet',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 60),
              
              // PIN Dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(6, (index) {
                  final currentPin = _isConfirmingPin ? _confirmPin : _pin;
                  final isFilled = index < currentPin.length;
                  
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
              ),
              
              const Spacer(),
              
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
              
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildNumberButton(String number) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onNumberPressed(number),
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
        onTap: _onDeletePressed,
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
