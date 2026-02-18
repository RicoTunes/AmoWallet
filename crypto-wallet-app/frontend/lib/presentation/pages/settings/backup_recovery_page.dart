import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/wallet_service.dart';
import '../../../services/biometric_auth_service.dart';
import '../../../services/pin_auth_service.dart';
import '../../widgets/pin_dialogs.dart';

class BackupRecoveryPage extends ConsumerStatefulWidget {
  const BackupRecoveryPage({super.key});

  @override
  ConsumerState<BackupRecoveryPage> createState() => _BackupRecoveryPageState();
}

class _BackupRecoveryPageState extends ConsumerState<BackupRecoveryPage> {
  final WalletService _walletService = WalletService();
  final BiometricAuthService _authService = BiometricAuthService();
  final PinAuthService _pinAuthService = PinAuthService();

  String? _mnemonic;
  bool _isRevealed = false;
  bool _isVerified = false;
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Backup & Recovery'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppConstants.defaultPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Warning Banner
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  border: Border.all(color: Colors.orange, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: Colors.orange, size: 32),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Important Security Notice',
                            style: AppTheme.titleMedium.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Never share your recovery phrase with anyone. It provides full access to your funds.',
                            style: AppTheme.bodySmall.copyWith(
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Security Tips
              _buildInfoCard(
                icon: Icons.security,
                title: 'Security Best Practices',
                items: [
                  'Write down your recovery phrase on paper',
                  'Store it in a secure, fireproof location',
                  'Never store it digitally (screenshots, cloud, etc.)',
                  'Keep multiple copies in different secure locations',
                  'Never share it with anyone, including support staff',
                ],
              ),
              const SizedBox(height: 24),

              // View Recovery Phrase Section
              if (!_isRevealed) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppConstants.defaultPadding),
                    child: Column(
                      children: [
                        Icon(
                          Icons.visibility_off,
                          size: 48,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'View Recovery Phrase',
                          style: AppTheme.titleMedium.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'You\'ll need to verify your identity before viewing your recovery phrase.',
                          style: AppTheme.bodySmall.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.7),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _loading ? null : _revealMnemonic,
                            icon: _loading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.lock_open),
                            label: Text(_loading
                                ? 'Authenticating...'
                                : 'Reveal Recovery Phrase'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                // Recovery Phrase Display
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(AppConstants.defaultPadding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.warning_rounded,
                              color: Theme.of(context).colorScheme.error,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Your Recovery Phrase',
                              style: AppTheme.titleMedium.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              if (_mnemonic != null)
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: _mnemonic!
                                      .split(' ')
                                      .asMap()
                                      .entries
                                      .map((entry) {
                                    return _buildWordChip(
                                        entry.key + 1, entry.value);
                                  }).toList(),
                                ),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: _copyMnemonic,
                                  icon: const Icon(Icons.copy),
                                  label: const Text('Copy to Clipboard'),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (!_isVerified) ...[
                          Text(
                            'Please write this down and verify you\'ve saved it correctly.',
                            style: AppTheme.bodySmall.copyWith(
                              color: Theme.of(context).colorScheme.error,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _verifyBackup,
                              style: ElevatedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                              ),
                              child: const Text('I\'ve Written It Down'),
                            ),
                          ),
                        ] else ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.check_circle,
                                    color: Colors.green),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Backup verified! Keep your recovery phrase safe.',
                                    style: AppTheme.bodySmall.copyWith(
                                      color: Colors.green,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Test Recovery
              _buildInfoCard(
                icon: Icons.restore,
                title: 'Test Your Backup',
                items: [
                  'Write down your recovery phrase',
                  'Use it to restore your wallet on another device',
                  'Verify all your assets are accessible',
                  'Delete the test wallet after verification',
                ],
              ),

              const SizedBox(height: 24),

              // What if I lose my phrase?
              Card(
                color: Theme.of(context)
                    .colorScheme
                    .errorContainer
                    .withOpacity(0.3),
                child: Padding(
                  padding: const EdgeInsets.all(AppConstants.defaultPadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.help_outline,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Lost Your Recovery Phrase?',
                            style: AppTheme.titleMedium.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'If you lose your recovery phrase and lose access to your device, your funds will be permanently lost. We cannot recover your wallet for you.',
                        style: AppTheme.bodyMedium.copyWith(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'This is why backing up your recovery phrase is critical!',
                        style: AppTheme.bodySmall.copyWith(
                          color: Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required List<String> items,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: AppTheme.titleMedium.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...items.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '• ',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          item,
                          style: AppTheme.bodyMedium.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.8),
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildWordChip(int index, String word) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$index.',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.primary.withOpacity(0.6),
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            word,
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _revealMnemonic() async {
    setState(() => _loading = true);

    try {
      bool authenticated = false;

      // Try biometric authentication first, but catch any exceptions
      try {
        bool canUseBiometric = await _authService.isBiometricAvailable();
        // Use PinAuthService as single source of truth for biometric enabled
        bool biometricEnabled = await _pinAuthService.isBiometricEnabled();

        if (canUseBiometric && biometricEnabled) {
          authenticated = await _authService.authenticateWithBiometrics(
            reason: 'Authenticate to view recovery phrase',
          );
        }
      } catch (e) {
        // Biometric failed (UIUnavailable error, etc.) - fall back to PIN
        print('Biometric auth failed: $e - falling back to PIN');
        authenticated = false;
      }

      // If biometric didn't work or wasn't available, try PIN
      if (!authenticated) {
        final pinSet = await _pinAuthService.isPinSet();

        if (pinSet && mounted) {
          // Show PIN entry dialog
          final pin = await showDialog<String>(
            context: context,
            barrierDismissible: false,
            builder: (context) => _PinEntryDialog(
              title: 'Enter PIN',
              subtitle: 'Enter your PIN to view recovery phrase',
            ),
          );

          if (pin != null && pin.isNotEmpty) {
            authenticated = await _pinAuthService.verifyPin(pin);
            if (!authenticated && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Invalid PIN'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        } else if (mounted) {
          // No security set up - show warning
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Security Required'),
              content: const Text(
                'Please set up PIN or biometric authentication in Settings > Security to view your recovery phrase.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
          setState(() => _loading = false);
          return;
        }
      }

      if (!authenticated) {
        setState(() => _loading = false);
        return;
      }

      // Scan ALL storage keys for any mnemonic - works regardless of which
      // chain the wallet was originally created on
      String? mnemonic = await _walletService.findAnyMnemonic();

      if (mnemonic == null || mnemonic.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'No recovery phrase found. Please restore your wallet.')),
          );
        }
        setState(() => _loading = false);
        return;
      }

      setState(() {
        _mnemonic = mnemonic;
        _isRevealed = true;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _copyMnemonic() async {
    if (_mnemonic != null) {
      await Clipboard.setData(ClipboardData(text: _mnemonic!));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Recovery phrase copied to clipboard'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _verifyBackup() async {
    setState(() => _isVerified = true);

    // Mark backup as completed in preferences
    await _walletService.markBackupCompleted();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Backup verified successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }
}

/// Simple PIN entry dialog for authentication
class _PinEntryDialog extends StatefulWidget {
  final String title;
  final String subtitle;

  const _PinEntryDialog({
    required this.title,
    required this.subtitle,
  });

  @override
  State<_PinEntryDialog> createState() => _PinEntryDialogState();
}

class _PinEntryDialogState extends State<_PinEntryDialog> {
  String _enteredPin = '';

  void _onDigitPressed(String digit) {
    if (_enteredPin.length < 6) {
      setState(() {
        _enteredPin += digit;
      });

      // Auto-submit when 6 digits entered
      if (_enteredPin.length == 6) {
        Navigator.of(context).pop(_enteredPin);
      }
    }
  }

  void _onBackspace() {
    if (_enteredPin.isNotEmpty) {
      setState(() {
        _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.subtitle,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // PIN Dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(6, (index) {
                final isFilled = index < _enteredPin.length;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isFilled
                        ? Theme.of(context).colorScheme.primary
                        : Colors.transparent,
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

            const SizedBox(height: 24),

            // Number Pad
            SizedBox(
              width: 250,
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 1.5,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 8,
                ),
                itemCount: 12,
                itemBuilder: (context, index) {
                  if (index == 9) {
                    return const SizedBox();
                  } else if (index == 10) {
                    return _buildNumberButton('0');
                  } else if (index == 11) {
                    return _buildBackspaceButton();
                  } else {
                    return _buildNumberButton('${index + 1}');
                  }
                },
              ),
            ),

            const SizedBox(height: 16),

            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNumberButton(String digit) {
    return GestureDetector(
      onTap: () => _onDigitPressed(digit),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[200],
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            digit,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackspaceButton() {
    return GestureDetector(
      onTap: _onBackspace,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[200],
          shape: BoxShape.circle,
        ),
        child: const Center(
          child: Icon(Icons.backspace_outlined, size: 22),
        ),
      ),
    );
  }
}
