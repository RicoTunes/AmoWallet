import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/biometric_auth_service.dart';
import '../../services/pin_auth_service.dart';

class PINSetupDialog extends StatefulWidget {
  final String title;
  final String? subtitle;

  const PINSetupDialog({
    super.key,
    this.title = 'Set up PIN',
    this.subtitle,
  });

  @override
  State<PINSetupDialog> createState() => _PINSetupDialogState();
}

class _PINSetupDialogState extends State<PINSetupDialog> {
  final BiometricAuthService _authService = BiometricAuthService();
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _confirmPinController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  Future<void> _setupPIN() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final pin = _pinController.text;
    final confirmPin = _confirmPinController.text;

    // Validation
    if (pin.length < 4) {
      setState(() {
        _errorMessage = 'PIN must be at least 4 digits';
        _isLoading = false;
      });
      return;
    }

    if (pin != confirmPin) {
      setState(() {
        _errorMessage = 'PINs do not match';
        _isLoading = false;
      });
      return;
    }

    try {
      await _authService.setPIN(pin);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.subtitle != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  widget.subtitle!,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            TextField(
              controller: _pinController,
              decoration: const InputDecoration(
                labelText: 'Enter PIN',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock),
              ),
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _confirmPinController,
              decoration: const InputDecoration(
                labelText: 'Confirm PIN',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock_outline),
              ),
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onSubmitted: (_) => _setupPIN(),
            ),
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _setupPIN,
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Set PIN'),
        ),
      ],
    );
  }
}

class PINVerificationDialog extends StatefulWidget {
  final String title;
  final String? subtitle;
  final int maxAttempts;

  const PINVerificationDialog({
    super.key,
    this.title = 'Enter PIN',
    this.subtitle,
    this.maxAttempts = 3,
  });

  @override
  State<PINVerificationDialog> createState() => _PINVerificationDialogState();
}

class _PINVerificationDialogState extends State<PINVerificationDialog> {
  final PinAuthService _pinAuthService = PinAuthService();
  final BiometricAuthService _biometricService = BiometricAuthService();
  final TextEditingController _pinController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  int _attempts = 0;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _verifyPIN() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final pin = _pinController.text;

    if (pin.length < 4) {
      setState(() {
        _errorMessage = 'PIN must be at least 4 digits';
        _isLoading = false;
      });
      return;
    }

    try {
      print('🔍 Attempting to verify PIN...');
      
      // Try PinAuthService first (plain PIN)
      bool isValid = await _pinAuthService.verifyPin(pin);
      
      // If not valid, also try BiometricAuthService (hashed PIN)
      if (!isValid) {
        isValid = await _biometricService.verifyPIN(pin);
      }
      
      print('🔍 PIN verification result: $isValid');
      
      if (isValid) {
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      } else {
        _attempts++;
        if (_attempts >= widget.maxAttempts) {
          if (mounted) {
            // Pop first with false, don't use ScaffoldMessenger from dialog context
            Navigator.of(context).pop(false);
          }
        } else {
          setState(() {
            _errorMessage = 'Incorrect PIN ($_attempts/${widget.maxAttempts} attempts)';
            _isLoading = false;
          });
          _pinController.clear();
        }
      }
    } catch (e) {
      print('❌ PIN verification error: $e');
      setState(() {
        _errorMessage = 'Verification failed: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _tryBiometric() async {
    try {
      final success = await _biometricService.authenticateWithBiometrics(
        reason: 'Authenticate to continue',
      );
      
      if (success && mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      print('Biometric auth error: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    // Don't auto-try biometric in dialog, let user trigger manually
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.subtitle != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                widget.subtitle!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          TextField(
            controller: _pinController,
            decoration: const InputDecoration(
              labelText: 'Enter PIN',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.lock),
            ),
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            autofocus: true,
            onSubmitted: (_) => _verifyPIN(),
          ),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _errorMessage!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ),
          const SizedBox(height: 16),
          FutureBuilder<bool>(
            future: _pinAuthService.isBiometricAvailable(),
            builder: (context, snapshot) {
              if (snapshot.data == true) {
                return Center(
                  child: TextButton.icon(
                    onPressed: _tryBiometric,
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('Use Biometric'),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _verifyPIN,
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Verify'),
        ),
      ],
    );
  }
}
