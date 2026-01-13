import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/wallet_service.dart';
import '../../../services/bip39_wallet.dart';
import '../../../services/auth_service.dart';

class WalletCreatePage extends ConsumerStatefulWidget {
  const WalletCreatePage({super.key});

  @override
  ConsumerState<WalletCreatePage> createState() => _WalletCreatePageState();
}

class _WalletCreatePageState extends ConsumerState<WalletCreatePage> {
  int _currentStep = 0;
  final List<String> _mnemonicWords = [];
  bool _isGenerating = false;
  bool _isBackedUp = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Wallet'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_currentStep > 0) {
              setState(() => _currentStep--);
            } else {
              context.go('/onboarding');
            }
          },
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.defaultPadding),
          child: Column(
            children: [
              // Progress Indicator
              LinearProgressIndicator(
                value: (_currentStep + 1) / 3,
                backgroundColor: Theme.of(context).colorScheme.outline,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 32),

              // Step Content
              Expanded(
                child: _buildStepContent(),
              ),

              // Navigation Buttons
              const SizedBox(height: 32),
              _buildNavigationButtons(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildSecurityInfoStep();
      case 1:
        return _buildMnemonicStep();
      case 2:
        return _buildBackupConfirmationStep();
      default:
        return const SizedBox();
    }
  }

  Widget _buildSecurityInfoStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Security First',
          style: AppTheme.headlineMedium.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Your wallet security is our top priority. Follow these important steps:',
          style: AppTheme.bodyLarge.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 32),

        _buildSecurityItem(
          icon: Icons.security,
          title: 'Non-Custodial',
          description: 'You control your private keys. We never have access to your funds.',
        ),
        const SizedBox(height: 24),
        _buildSecurityItem(
          icon: Icons.backup,
          title: 'Backup Your Recovery Phrase',
          description: 'Write down your 12-word recovery phrase and store it securely.',
        ),
        const SizedBox(height: 24),
        _buildSecurityItem(
          icon: Icons.warning_amber,
          title: 'Never Share Your Phrase',
          description: 'Anyone with your recovery phrase can access your funds.',
        ),
        const SizedBox(height: 24),
        _buildSecurityItem(
          icon: Icons.devices,
          title: 'Multiple Devices',
          description: 'You can restore your wallet on any device using your recovery phrase.',
        ),
      ],
    );
  }

  Widget _buildSecurityItem({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
                Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withAlpha((0.1 * 255).round()),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            color: Theme.of(context).colorScheme.primary,
            size: 20,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTheme.titleSmall.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: AppTheme.bodyMedium.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMnemonicStep() {
    if (_mnemonicWords.isEmpty && !_isGenerating) {
      _generateMnemonic();
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with gradient
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).colorScheme.primary,
                  Theme.of(context).colorScheme.secondary,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.security,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Your Recovery Phrase',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '12 words to secure your wallet',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Warning message
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).colorScheme.error.withOpacity(0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning_rounded,
                  color: Theme.of(context).colorScheme.error,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Write these words down in order. Never share them with anyone!',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          if (_isGenerating)
            Center(
              child: Column(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    'Generating secure phrase...',
                    style: AppTheme.bodyMedium.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            )
          else
            Column(
              children: [
                // Mnemonic words grid with improved styling
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Theme.of(context).colorScheme.surface,
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 2.5,
                    ),
                    itemCount: _mnemonicWords.length,
                    itemBuilder: (context, index) {
                      return Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 5,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Center(
                          child: RichText(
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text: '${index + 1}. ',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.primary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                TextSpan(
                                  text: _mnemonicWords[index],
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.onSurface,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 20),

                // Copy button with beautiful styling
                ElevatedButton.icon(
                  onPressed: () {
                    final phraseText = _mnemonicWords.join(' ');
                    Clipboard.setData(ClipboardData(text: phraseText));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Row(
                          children: [
                            Icon(Icons.check_circle, color: Colors.white),
                            SizedBox(width: 12),
                            Text('Recovery phrase copied to clipboard!'),
                          ],
                        ),
                        backgroundColor: Colors.green,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('Copy Recovery Phrase'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 56),
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildBackupConfirmationStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Confirm Your Backup',
          style: AppTheme.headlineMedium.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'To ensure you have properly backed up your recovery phrase, please confirm:',
          style: AppTheme.bodyLarge.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 32),

        CheckboxListTile(
          title: Text(
            'I have written down my 12-word recovery phrase',
            style: AppTheme.bodyMedium.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          value: _isBackedUp,
          onChanged: (value) {
            setState(() {
              _isBackedUp = value ?? false;
            });
          },
          controlAffinity: ListTileControlAffinity.leading,
        ),

        const SizedBox(height: 16),
        CheckboxListTile(
          title: Text(
            'I understand that losing my recovery phrase means losing access to my funds forever',
            style: AppTheme.bodyMedium.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          value: _isBackedUp,
          onChanged: (value) {
            setState(() {
              _isBackedUp = value ?? false;
            });
          },
          controlAffinity: ListTileControlAffinity.leading,
        ),

        const SizedBox(height: 16),
        CheckboxListTile(
          title: Text(
            'I will never share my recovery phrase with anyone',
            style: AppTheme.bodyMedium.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          value: _isBackedUp,
          onChanged: (value) {
            setState(() {
              _isBackedUp = value ?? false;
            });
          },
          controlAffinity: ListTileControlAffinity.leading,
        ),
      ],
    );
  }

  Widget _buildNavigationButtons() {
    return Column(
      children: [
        if (_currentStep < 2)
          ElevatedButton(
            onPressed: () {
              if (_currentStep == 1 && _mnemonicWords.isEmpty) return;
              setState(() => _currentStep++);
            },
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 56),
            ),
            child: Text(
              _currentStep == 0 ? 'Generate Recovery Phrase' : 'Continue',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        if (_currentStep == 2)
          ElevatedButton(
            onPressed: _isBackedUp
                  ? () async {
                      // Generate wallets for all supported chains from the same mnemonic
                      final svc = WalletService();
                      final authService = AuthService();
                      try {
                        // The mnemonic was already generated locally
                        final mnemonic = _mnemonicWords.join(' ');
                        
                        // Generate/restore addresses for all chains from this mnemonic
                        final chains = ['BTC', 'ETH', 'BNB', 'SOL', 'TRX', 'LTC', 'DOGE', 'XRP'];
                        String? primaryAddress;
                        
                        for (final chain in chains) {
                          try {
                            final wallet = await Bip39Wallet.restore(mnemonic: mnemonic, chain: chain);
                            final address = wallet['address']!;
                            final privateKey = wallet['privateKey'];
                            
                            // Store in format expected by getBalances()
                            await svc.storeWalletCredentials(chain, address, privateKey, mnemonic);
                            
                            // Use ETH as primary address for display
                            if (chain == 'ETH') {
                              primaryAddress = address;
                            }
                            // ignore: avoid_print
                            print('✅ Generated $chain wallet: $address');
                          } catch (e) {
                            // ignore: avoid_print
                            print('⚠️ Failed to generate $chain wallet: $e');
                          }
                        }
                        
                        // Save wallet data and set logged in state
                        await authService.saveWalletData(
                          address: primaryAddress ?? '',
                          mnemonic: mnemonic,
                        );
                        
                        // After async work, ensure widget is still mounted before navigation
                        if (!mounted) return;
                        // Navigate to dashboard after success
                        context.go('/dashboard');
                      } catch (e) {
                        // ignore: avoid_print
                        print('Failed to create wallet: $e');
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Failed to create wallet. Try again.')),
                        );
                      }
                    }
                  : null,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 56),
            ),
            child: const Text(
              'Complete Setup',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        if (_currentStep > 0)
          const SizedBox(height: 16),
        if (_currentStep > 0)
          TextButton(
            onPressed: () => setState(() => _currentStep--),
            child: const Text('Back'),
          ),
      ],
    );
  }

  void _generateMnemonic() async {
    setState(() => _isGenerating = true);

    try {
      // Generate real mnemonic using the wallet service
      final svc = WalletService();
      final result = await svc.generateWallet(chain: 'BTC'); // Generate BTC wallet with mnemonic
      
      if (result['mnemonic'] != null) {
        final mnemonic = result['mnemonic']!;
        final words = mnemonic.split(' ');
        
        setState(() {
          _mnemonicWords.clear();
          _mnemonicWords.addAll(words);
          _isGenerating = false;
        });
      } else {
        // Fallback: if backend doesn't return mnemonic, use local generation
        throw Exception('No mnemonic returned from backend');
      }
    } catch (e) {
      // ignore: avoid_print
      print('Error generating mnemonic: $e');
      
      // Fallback: generate locally if backend fails
      try {
        final result = await Bip39Wallet.generate(chain: 'BTC');
        final mnemonic = result['mnemonic'];
        
        if (mnemonic != null) {
          final words = mnemonic.split(' ');
          setState(() {
            _mnemonicWords.clear();
            _mnemonicWords.addAll(words);
            _isGenerating = false;
          });
        } else {
          throw Exception('No mnemonic from local generation');
        }
      } catch (fallbackError) {
        // ignore: avoid_print
        print('Fallback generation failed: $fallbackError');
        setState(() {
          _isGenerating = false;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to generate recovery phrase. Please try again.')),
          );
        }
      }
    }
  }
}