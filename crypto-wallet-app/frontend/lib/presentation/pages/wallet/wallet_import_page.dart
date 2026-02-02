import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/bip39_wallet.dart';
import '../../../services/auth_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class WalletImportPage extends ConsumerStatefulWidget {
  const WalletImportPage({super.key});

  @override
  ConsumerState<WalletImportPage> createState() => _WalletImportPageState();
}

class _WalletImportPageState extends ConsumerState<WalletImportPage> {
  final TextEditingController _mnemonicController = TextEditingController();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final AuthService _authService = AuthService();
  bool _isLoading = false;

  @override
  void dispose() {
    _mnemonicController.dispose();
    super.dispose();
  }

  Future<void> _importWallet() async {
    final mnemonic = _mnemonicController.text.trim();
    
    if (mnemonic.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your recovery phrase')),
      );
      return;
    }

    // Validate mnemonic (should be 12 or 24 words)
    final words = mnemonic.split(' ').where((w) => w.isNotEmpty).toList();
    if (words.length != 12 && words.length != 24) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recovery phrase must be 12 or 24 words')),
      );
      return;
    }

    setState(() => _isLoading = true);

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => WillPopScope(
        onWillPop: () async => false,
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 60,
                  height: 60,
                  child: CircularProgressIndicator(
                    strokeWidth: 4,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Importing Your Wallet',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Recovering your keys from recovery phrase...',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    minHeight: 4,
                    backgroundColor: Colors.grey[300],
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Ensure dialog is visible for at least 500ms
    await Future.delayed(const Duration(milliseconds: 500));

    try {
      // Restore wallet for main chains (BTC, ETH)
      final chains = ['BTC', 'ETH'];
      String? primaryAddress;
      
      for (final chain in chains) {
        try {
          final walletData = await Bip39Wallet.restore(
            mnemonic: mnemonic,
            chain: chain,
          );
          
          final address = walletData['address']!;
          final privateKey = walletData['privateKey'];
          
          // Use the first address as the primary wallet address
          primaryAddress ??= address;
          
          // Store the keys securely
          if (privateKey != null) {
            await _storage.write(
              key: '${chain}_${address}_private',
              value: privateKey,
            );
            await _storage.write(
              key: '${chain}_${address}_mnemonic',
              value: mnemonic,
            );
          }
        } catch (e) {
          // Continue with other chains even if one fails
          print('Failed to restore $chain wallet: $e');
        }
      }
      
      // Mark backup as completed since user already has the mnemonic
      await _storage.write(key: 'backup_completed', value: 'true');
      
      // IMPORTANT: Set logged in state and save wallet data
      if (primaryAddress != null) {
        await _authService.saveWalletData(
          address: primaryAddress,
          mnemonic: mnemonic,
        );
      } else {
        // Set logged in even if we couldn't get an address
        await _authService.setLoggedIn(true);
      }
      
      if (mounted) {
        // Dismiss loading dialog
        Navigator.pop(context);
        
        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Wallet imported successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        
        // Navigate to dashboard
        context.go('/dashboard');
      }
    } catch (e) {
      if (mounted) {
        // Dismiss loading dialog
        Navigator.pop(context);
        
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to import wallet: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import Wallet'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/onboarding'),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.defaultPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Import Existing Wallet',
                style: AppTheme.headlineMedium.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Enter your 12-word recovery phrase to restore your wallet',
                style: AppTheme.bodyLarge.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 32),
              
              // Recovery Phrase Input
              Expanded(
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                      child: TextField(
                        controller: _mnemonicController,
                        enabled: !_isLoading,
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText: 'Enter your 12-word recovery phrase separated by spaces',
                          border: InputBorder.none,
                          hintStyle: AppTheme.bodyMedium.copyWith(
                            color: Theme.of(context).colorScheme.onSurface.withAlpha((0.5 * 255).round()),
                          ),
                        ),
                        style: AppTheme.bodyMedium.copyWith(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // Security Warning
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.security,
                          color: Theme.of(context).colorScheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Your recovery phrase is never sent to our servers. All processing happens securely on your device.',
                            style: AppTheme.bodyMedium.copyWith(
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              // Import Button with Loading Animation
              ElevatedButton(
                onPressed: _isLoading ? null : _importWallet,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 56),
                  backgroundColor: _isLoading 
                      ? Theme.of(context).colorScheme.primary.withAlpha((0.7 * 255).round())
                      : Theme.of(context).colorScheme.primary,
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (Widget child, Animation<double> animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                        scale: animation,
                        child: child,
                      ),
                    );
                  },
                  child: _isLoading
                      ? Row(
                          key: const ValueKey('loading'),
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Importing Wallet...',
                              style: const TextStyle(
                                fontSize: 16, 
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        )
                      : const Text(
                          key: ValueKey('ready'),
                          'Import Wallet',
                          style: TextStyle(
                            fontSize: 16, 
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}