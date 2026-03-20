import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../services/auth_service.dart';
import '../../../services/pin_auth_service.dart';

class ForgotPinPage extends StatefulWidget {
  const ForgotPinPage({super.key});

  @override
  State<ForgotPinPage> createState() => _ForgotPinPageState();
}

class _ForgotPinPageState extends State<ForgotPinPage> {
  final AuthService _authService = AuthService();
  final PinAuthService _pinAuthService = PinAuthService();

  // Step: 0 = enter phrase, 1 = new PIN, 2 = confirm PIN, 3 = processing/done
  int _step = 0;
  bool _isProcessing = false;
  String _errorMessage = '';

  // Recovery phrase
  final List<TextEditingController> _wordControllers =
      List.generate(12, (_) => TextEditingController());
  final List<FocusNode> _wordFocusNodes = List.generate(12, (_) => FocusNode());

  // New PIN
  String _newPin = '';
  String _confirmPin = '';

  @override
  void dispose() {
    for (final c in _wordControllers) {
      c.dispose();
    }
    for (final f in _wordFocusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _verifyRecoveryPhrase() async {
    final enteredWords =
        _wordControllers.map((c) => c.text.trim().toLowerCase()).toList();

    if (enteredWords.any((w) => w.isEmpty)) {
      setState(() => _errorMessage = 'Please fill in all 12 words');
      return;
    }

    setState(() {
      _isProcessing = true;
      _errorMessage = '';
    });

    try {
      final storedMnemonic = await _authService.getMnemonic();
      if (storedMnemonic == null || storedMnemonic.isEmpty) {
        setState(() {
          _isProcessing = false;
          _errorMessage = 'No recovery phrase found. Please restore wallet.';
        });
        return;
      }

      final storedWords =
          storedMnemonic.trim().toLowerCase().split(RegExp(r'\s+'));
      final entered = enteredWords.join(' ');
      final stored = storedWords.join(' ');

      if (entered == stored) {
        // Phrase matches — go to new PIN step
        // Reset lockout since user proved ownership
        await _pinAuthService.resetLockoutAfterRecovery();
        setState(() {
          _isProcessing = false;
          _step = 1;
        });
      } else {
        setState(() {
          _isProcessing = false;
          _errorMessage = 'Recovery phrase does not match. Please try again.';
        });
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _errorMessage = 'Error verifying phrase: $e';
      });
    }
  }

  void _onNewPinDigit(String digit) {
    if (_step == 1 && _newPin.length < 6) {
      HapticFeedback.lightImpact();
      setState(() {
        _newPin += digit;
        _errorMessage = '';
      });
      if (_newPin.length == 6) {
        setState(() => _step = 2);
      }
    } else if (_step == 2 && _confirmPin.length < 6) {
      HapticFeedback.lightImpact();
      setState(() {
        _confirmPin += digit;
        _errorMessage = '';
      });
      if (_confirmPin.length == 6) {
        _saveNewPin();
      }
    }
  }

  void _onPinBack() {
    if (_step == 1 && _newPin.isNotEmpty) {
      HapticFeedback.lightImpact();
      setState(() => _newPin = _newPin.substring(0, _newPin.length - 1));
    } else if (_step == 2 && _confirmPin.isNotEmpty) {
      HapticFeedback.lightImpact();
      setState(() =>
          _confirmPin = _confirmPin.substring(0, _confirmPin.length - 1));
    }
  }

  Future<void> _saveNewPin() async {
    if (_newPin != _confirmPin) {
      HapticFeedback.heavyImpact();
      setState(() {
        _confirmPin = '';
        _errorMessage = 'PINs do not match. Try again.';
        _step = 2;
      });
      return;
    }

    setState(() {
      _step = 3;
      _isProcessing = true;
      _errorMessage = '';
    });

    try {
      final success = await _pinAuthService.setupPin(_newPin);
      if (success) {
        // Small delay for UX
        await Future.delayed(const Duration(milliseconds: 1500));
        if (mounted) {
          HapticFeedback.mediumImpact();
          context.go('/pin-entry');
        }
      } else {
        setState(() {
          _isProcessing = false;
          _errorMessage = 'Failed to save PIN. Please try again.';
          _step = 1;
          _newPin = '';
          _confirmPin = '';
        });
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _errorMessage = 'Error: $e';
        _step = 1;
        _newPin = '';
        _confirmPin = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      body: Stack(
        children: [
          // Background
          Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/images/apponboarding.png'),
                fit: BoxFit.cover,
              ),
            ),
          ),
          Container(color: Colors.black.withOpacity(0.5)),
          SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      IconButton(
                        icon:
                            const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () {
                          if (_step == 0) {
                            context.go('/pin-entry');
                          } else if (_step == 1) {
                            setState(() {
                              _step = 0;
                              _newPin = '';
                            });
                          } else if (_step == 2) {
                            setState(() {
                              _step = 1;
                              _newPin = '';
                              _confirmPin = '';
                            });
                          }
                        },
                      ),
                      Expanded(
                        child: Text(
                          _step == 0
                              ? 'Recovery Phrase'
                              : _step == 1
                                  ? 'New PIN'
                                  : _step == 2
                                      ? 'Confirm PIN'
                                      : 'Resetting PIN...',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),

                // Step indicator
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 40, vertical: 8),
                  child: Row(
                    children: List.generate(3, (i) {
                      final active = i <= _step.clamp(0, 2);
                      return Expanded(
                        child: Container(
                          height: 3,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: active
                                ? primary
                                : Colors.white.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      );
                    }),
                  ),
                ),

                // Content
                Expanded(
                  child: _step == 0
                      ? _buildPhraseEntry()
                      : _step == 3
                          ? _buildProcessing()
                          : _buildPinEntry(),
                ),

                // Error
                if (_errorMessage.isNotEmpty)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.withOpacity(0.4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline,
                              color: Colors.redAccent, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(_errorMessage,
                                style: const TextStyle(
                                    color: Colors.redAccent, fontSize: 12)),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhraseEntry() {
    return Column(
      children: [
        const SizedBox(height: 8),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'Enter your 12-word recovery phrase to reset your PIN',
            style: TextStyle(color: Colors.white70, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                // 12 word fields in 2 columns
                for (int row = 0; row < 6; row++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        _buildWordField(row * 2),
                        const SizedBox(width: 10),
                        _buildWordField(row * 2 + 1),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                // Verify button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isProcessing ? null : _verifyRecoveryPhrase,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: _isProcessing
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Text('Verify & Continue',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWordField(int index) {
    return Expanded(
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withOpacity(0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              alignment: Alignment.center,
              child: Text(
                '${index + 1}',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.5), fontSize: 11),
              ),
            ),
            Expanded(
              child: TextField(
                controller: _wordControllers[index],
                focusNode: _wordFocusNodes[index],
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                ),
                textInputAction: index < 11
                    ? TextInputAction.next
                    : TextInputAction.done,
                onSubmitted: (_) {
                  if (index < 11) {
                    _wordFocusNodes[index + 1].requestFocus();
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPinEntry() {
    final pin = _step == 1 ? _newPin : _confirmPin;
    final title = _step == 1 ? 'Enter New PIN' : 'Confirm New PIN';
    final subtitle = _step == 1
        ? 'Choose a 6-digit PIN'
        : 'Re-enter your PIN to confirm';
    final primary = Theme.of(context).colorScheme.primary;

    return Column(
      children: [
        const SizedBox(height: 16),
        Text(title,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text(subtitle,
            style: const TextStyle(color: Colors.white60, fontSize: 13)),
        const SizedBox(height: 20),

        // PIN dots
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(6, (i) {
            final filled = i < pin.length;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 7),
              width: filled ? 16 : 13,
              height: filled ? 16 : 13,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: filled ? primary : Colors.transparent,
                border: Border.all(
                    color: filled
                        ? primary
                        : Colors.white.withOpacity(0.4),
                    width: 2),
                boxShadow: filled
                    ? [
                        BoxShadow(
                            color: primary.withOpacity(0.4),
                            blurRadius: 6,
                            spreadRadius: 1)
                      ]
                    : null,
              ),
            );
          }),
        ),

        const SizedBox(height: 16),

        // Number pad
        Expanded(
          child: GridView.count(
            crossAxisCount: 3,
            childAspectRatio: 1.6,
            padding: const EdgeInsets.symmetric(horizontal: 32),
            physics: const NeverScrollableScrollPhysics(),
            children: [
              ...List.generate(
                  9, (i) => _buildNumBtn('${i + 1}')),
              const SizedBox(),
              _buildNumBtn('0'),
              _buildBackBtn(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNumBtn(String digit) {
    return GestureDetector(
      onTap: () => _onNewPinDigit(digit),
      child: Container(
        margin: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.1),
          border: Border.all(color: Colors.white.withOpacity(0.4), width: 1.5),
        ),
        child: Center(
          child: Text(digit,
              style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                  color: Colors.white)),
        ),
      ),
    );
  }

  Widget _buildBackBtn() {
    return GestureDetector(
      onTap: _onPinBack,
      child: Container(
        margin: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.1),
          border: Border.all(color: Colors.white.withOpacity(0.4), width: 1.5),
        ),
        child: const Center(
          child: Icon(Icons.backspace_outlined, color: Colors.white, size: 24),
        ),
      ),
    );
  }

  Widget _buildProcessing() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 60,
            height: 60,
            child: CircularProgressIndicator(
              color: Theme.of(context).colorScheme.primary,
              strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 24),
          const Text('Resetting Your PIN...',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Please wait',
              style: TextStyle(color: Colors.white60, fontSize: 13)),
        ],
      ),
    );
  }
}
