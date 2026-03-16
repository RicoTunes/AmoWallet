import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../services/auth_service.dart';
import '../../../services/wallet_service.dart';
import '../../../services/biometric_auth_service.dart';
import '../../../services/pin_auth_service.dart';
import '../../../services/screenshot_service.dart';
import 'security_settings_page.dart';
import 'backup_recovery_page.dart';
import 'network_settings_page.dart';
import 'language_settings_page.dart';
import 'currency_settings_page.dart';
import 'help_support_page.dart';
import 'report_bug_page.dart';
import 'terms_privacy_page.dart';
import 'notification_settings_page.dart';

// Provider for biometric state
final biometricEnabledProvider = StateProvider<bool?>((ref) => null);
final biometricAvailableProvider = StateProvider<bool>((ref) => false);
final screenshotAllowedProvider = StateProvider<bool>((ref) => false);

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final BiometricAuthService _biometricService = BiometricAuthService();
  final PinAuthService _pinAuthService = PinAuthService();
  final ScreenshotService _screenshotService = ScreenshotService();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    // Load biometric status
    final available = await _biometricService.isBiometricAvailable();
    final enabled = await _pinAuthService.isBiometricEnabled();
    ref.read(biometricAvailableProvider.notifier).state = available;
    ref.read(biometricEnabledProvider.notifier).state = enabled;
    
    // Load screenshot status
    final screenshotAllowed = await _screenshotService.isScreenshotAllowed();
    ref.read(screenshotAllowedProvider.notifier).state = screenshotAllowed;
  }

  @override
  Widget build(BuildContext context) {
    final biometricEnabled = ref.watch(biometricEnabledProvider);
    final screenshotAllowed = ref.watch(screenshotAllowedProvider);
    return BackButtonListener(
      onBackButtonPressed: () async {
        context.go('/dashboard');
        return true;
      },
      child: PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) {
          context.go('/dashboard');
        }
      },
      child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/dashboard'),
        ),
        title: const Text('Settings'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.defaultPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 32),
              
              // Settings Options
              Expanded(
                child: ListView(
                  children: [
                    _buildSettingsSection(
                      context,
                      title: 'Wallet',
                      children: [
                        _buildSettingsItem(
                          context,
                          icon: Icons.security,
                          title: 'Security',
                          subtitle: 'Manage wallet security',
                          onTap: () {
                            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SecuritySettingsPage()));
                          },
                        ),
                        _buildSettingsItem(
                          context,
                          icon: Icons.shield,
                          title: 'Advanced Security',
                          subtitle: 'HSM, Behavioral, Remote Wipe',
                          onTap: () {
                            context.push('/advanced-security');
                          },
                        ),
                        _buildSettingsItem(
                          context,
                          icon: Icons.backup,
                          title: 'Backup & Recovery',
                          subtitle: 'Manage recovery phrase',
                          onTap: () {
                            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BackupRecoveryPage()));
                          },
                        ),
                        _buildSettingsItem(
                          context,
                          icon: Icons.network_check,
                          title: 'Networks',
                          subtitle: 'Configure blockchain networks',
                          onTap: () {
                            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NetworkSettingsPage()));
                          },
                        ),
                        _buildSettingsItem(
                          context,
                          icon: Icons.contacts_rounded,
                          title: 'Address Book',
                          subtitle: 'Manage saved contacts',
                          onTap: () {
                            context.push('/address-book');
                          },
                        ),
                        _buildSettingsItem(
                          context,
                          icon: Icons.fingerprint,
                          title: 'Biometric Authentication',
                          subtitle: biometricEnabled == true ? 'Enabled' : 'Disabled',
                          trailing: Switch(
                            value: biometricEnabled ?? false,
                            onChanged: (value) async {
                              if (value) {
                                // Check if PIN is set first
                                final isPinSet = await _pinAuthService.isPinSet();
                                if (!isPinSet) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Please set up a PIN first in Security Settings'),
                                        backgroundColor: Colors.orange,
                                      ),
                                    );
                                  }
                                  return;
                                }
                                // Try to authenticate, but enable anyway if device supports it
                                try {
                                  final authenticated = await _biometricService.authenticateWithBiometrics(
                                    reason: 'Authenticate to enable biometric login',
                                  );
                                  if (authenticated) {
                                    await _pinAuthService.setBiometricEnabled(true);
                                    ref.read(biometricEnabledProvider.notifier).state = true;
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Biometric authentication enabled'),
                                          backgroundColor: Colors.green,
                                        ),
                                      );
                                    }
                                  }
                                } catch (e) {
                                  // Enable anyway - authentication will handle failures gracefully
                                  await _pinAuthService.setBiometricEnabled(true);
                                  ref.read(biometricEnabledProvider.notifier).state = true;
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Biometric enabled - authenticate when unlocking'),
                                        backgroundColor: Colors.green,
                                      ),
                                    );
                                  }
                                }
                              } else {
                                await _pinAuthService.setBiometricEnabled(false);
                                ref.read(biometricEnabledProvider.notifier).state = false;
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Biometric authentication disabled')),
                                  );
                                }
                              }
                            },
                          ),
                        ),
                        _buildSettingsItem(
                          context,
                          icon: Icons.refresh,
                          title: 'Reset Balances',
                          subtitle: 'Clear swap data & show blockchain balances',
                          onTap: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Reset Balances?'),
                                content: const Text(
                                  'This will clear all swap adjustment data and show only your actual blockchain balances.\n\n'
                                  'Use this if your balances appear incorrect.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Cancel'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red,
                                    ),
                                    child: const Text('Reset', style: TextStyle(color: Colors.white)),
                                  ),
                                ],
                              ),
                            );
                            
                            if (confirm == true) {
                              final walletService = WalletService();
                              await walletService.clearSwapAdjustments();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Balances reset! Go to Dashboard to see updated balances.'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            }
                          },
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 24),
                    
                    _buildSettingsSection(
                      context,
                      title: 'Preferences',
                      children: [
                        _buildSettingsItem(
                          context,
                          icon: Icons.dark_mode,
                          title: 'Dark Mode',
                          subtitle: ref.watch(themeProvider) == ThemeMode.dark ? 'Enabled' : 'Disabled',
                          trailing: Switch(
                            value: ref.watch(themeProvider) == ThemeMode.dark,
                            onChanged: (value) {
                              ref.read(themeProvider.notifier).toggleTheme();
                            },
                          ),
                        ),
                        _buildSettingsItem(
                          context,
                          icon: screenshotAllowed ? Icons.screenshot : Icons.no_photography,
                          title: 'Allow Screenshots',
                          subtitle: screenshotAllowed ? 'Screenshots enabled' : 'Screenshots blocked',
                          trailing: Switch(
                            value: screenshotAllowed,
                            onChanged: (value) async {
                              await _screenshotService.setScreenshotAllowed(value);
                              ref.read(screenshotAllowedProvider.notifier).state = value;
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(value 
                                        ? 'Screenshots enabled - Less secure'
                                        : 'Screenshots blocked - More secure'),
                                    backgroundColor: value ? Colors.orange : Colors.green,
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                        _buildSettingsItem(
                          context,
                          icon: Icons.language,
                          title: 'Language',
                          subtitle: 'English',
                          onTap: () {
                            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LanguageSettingsPage()));
                          },
                        ),
                        _buildSettingsItem(
                          context,
                          icon: Icons.currency_exchange,
                          title: 'Currency',
                          subtitle: 'USD',
                          onTap: () {
                            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CurrencySettingsPage()));
                          },
                        ),
                        _buildSettingsItem(
                          context,
                          icon: Icons.notifications_active,
                          title: 'Notifications',
                          subtitle: 'Price alerts & transaction notifications',
                          onTap: () {
                            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationSettingsPage()));
                          },
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 24),
                    
                    _buildSettingsSection(
                      context,
                      title: 'Support',
                      children: [
                        _buildSettingsItem(
                          context,
                          icon: Icons.help_outline,
                          title: 'Help & Support',
                          subtitle: 'Get help with the app',
                          onTap: () {
                            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HelpSupportPage()));
                          },
                        ),
                        _buildSettingsItem(
                          context,
                          icon: Icons.bug_report,
                          title: 'Report a Bug',
                          subtitle: 'Found an issue? Let us know',
                          onTap: () {
                            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReportBugPage()));
                          },
                        ),
                        _buildSettingsItem(
                          context,
                          icon: Icons.description,
                          title: 'Terms & Privacy',
                          subtitle: 'Legal information',
                          onTap: () {
                            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TermsPrivacyPage()));
                          },
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 24),
                    
                    _buildSettingsSection(
                      context,
                      title: 'About',
                      children: [
                        _buildSettingsItem(
                          context,
                          icon: Icons.info_outline,
                          title: 'About CryptoWallet Pro',
                          subtitle: 'Version ${AppConstants.appVersion}',
                          onTap: () {
                            showDialog(
                              context: context,
                              builder: (dialogContext) => AlertDialog(
                                title: Row(
                                  children: [
                                    Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).colorScheme.primary,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(
                                        Icons.account_balance_wallet,
                                        color: Colors.white,
                                        size: 28,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'CryptoWallet Pro',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          'Version ${AppConstants.appVersion}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                content: SingleChildScrollView(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Text(
                                        'A secure, non-custodial cryptocurrency wallet for managing your digital assets.',
                                        style: TextStyle(fontSize: 14),
                                      ),
                                      const SizedBox(height: 16),
                                      const Text(
                                        '✅ Multi-chain support\n'
                                        '✅ Multi-signature wallets\n'
                                        '✅ Secure key storage\n'
                                        '✅ Real-time prices\n'
                                        '✅ Transaction history',
                                        style: TextStyle(fontSize: 13),
                                      ),
                                      const SizedBox(height: 16),
                                      const Divider(),
                                      const SizedBox(height: 8),
                                      Text(
                                        '© ${DateTime.now().year} CryptoWallet Pro\nAll rights reserved.',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(dialogContext),
                                    child: const Text('Close'),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // Logout Button
                    OutlinedButton(
                      onPressed: () async {
                        // Show confirmation dialog
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Logout'),
                            content: const Text('Are you sure you want to logout? Make sure you have backed up your recovery phrase.'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                style: TextButton.styleFrom(
                                  foregroundColor: Theme.of(context).colorScheme.error,
                                ),
                                child: const Text('Logout'),
                              ),
                            ],
                          ),
                        );
                        
                        if (confirm == true && context.mounted) {
                          await AuthService().logout();
                          if (context.mounted) {
                            context.go('/onboarding');
                          }
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                        side: BorderSide(color: Theme.of(context).colorScheme.error),
                        minimumSize: const Size(double.infinity, 56),
                      ),
                      child: const Text(
                        'Logout',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    ),
    );
  }

  Widget _buildSettingsSection(
    BuildContext context, {
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTheme.titleSmall.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: children,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Container(
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
      title: Text(
        title,
        style: AppTheme.bodyMedium.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: AppTheme.bodySmall.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
      trailing: trailing,
      onTap: onTap,
    );
  }
}