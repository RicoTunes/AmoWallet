import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/wallet_service.dart';
import '../../../services/biometric_auth_service.dart';

class BackupRecoveryPage extends ConsumerStatefulWidget {
  const BackupRecoveryPage({super.key});

  @override
  ConsumerState<BackupRecoveryPage> createState() => _BackupRecoveryPageState();
}

class _BackupRecoveryPageState extends ConsumerState<BackupRecoveryPage> {
  final WalletService _walletService = WalletService();
  final BiometricAuthService _authService = BiometricAuthService();
  
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
                    const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 32),
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
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
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
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.lock_open),
                            label: Text(_loading ? 'Authenticating...' : 'Reveal Recovery Phrase'),
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
                                  children: _mnemonic!.split(' ').asMap().entries.map((entry) {
                                    return _buildWordChip(entry.key + 1, entry.value);
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
                                padding: const EdgeInsets.symmetric(vertical: 16),
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
                                const Icon(Icons.check_circle, color: Colors.green),
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
                color: Theme.of(context).colorScheme.errorContainer.withOpacity(0.3),
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
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
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
      // Check biometric first
      bool canUseBiometric = await _authService.isBiometricAvailable();
      
      if (canUseBiometric) {
        bool authenticated = await _authService.authenticateWithBiometrics(
          reason: 'Authenticate to view recovery phrase',
        );
        
        if (!authenticated) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Authentication failed')),
            );
          }
          return;
        }
      } else {
        // Show warning that they need to set up security
        if (!mounted) return;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Security Required'),
            content: const Text('Please set up PIN or biometric authentication in Settings > Security to view your recovery phrase.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
            ],
          ),
        );
        
        if (confirmed != true) return;
      }

      // Try to get mnemonic from any stored address
      // Start with BTC as the primary chain
      String? mnemonic;
      final chains = ['BTC', 'ETH', 'BNB'];
      
      for (final chain in chains) {
        try {
          final addresses = await _walletService.getStoredAddresses(chain);
          if (addresses.isNotEmpty) {
            mnemonic = await _walletService.getMnemonic(chain, addresses.first);
            if (mnemonic != null) break;
          }
        } catch (e) {
          // Try next chain
          continue;
        }
      }
      
      if (mnemonic == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No recovery phrase found. Please restore your wallet.')),
          );
        }
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Backup'),
        content: const Text(
          'Have you written down your recovery phrase and stored it securely?\n\n'
          'You will not be able to recover your wallet without it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not Yet'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes, I\'ve Saved It'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
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
}
