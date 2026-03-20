import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0D1421) : const Color(0xFFF5F6FA);
    final cardColor = isDark ? const Color(0xFF1A1F2E) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1F2E);
    final subtextColor = isDark ? Colors.white60 : Colors.grey[600]!;
    final dividerColor = isDark ? Colors.white.withOpacity(0.06) : Colors.grey.withOpacity(0.1);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: bgColor,
      ),
      child: BackButtonListener(
        onBackButtonPressed: () async {
          context.go('/dashboard');
          return true;
        },
        child: PopScope(
          canPop: false,
          onPopInvoked: (didPop) {
            if (!didPop) context.go('/dashboard');
          },
          child: Scaffold(
            backgroundColor: bgColor,
            body: CustomScrollView(
              slivers: [
                // â”€â”€ Gradient Header â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                SliverToBoxAdapter(
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF6D28D9), Color(0xFF8B5CF6), Color(0xFF4F46E5)],
                      ),
                    ),
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                        child: Column(
                          children: [
                            // Top row
                            Row(
                              children: [
                                GestureDetector(
                                  onTap: () => context.go('/dashboard'),
                                  child: Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
                                  ),
                                ),
                                const Spacer(),
                                const Text('Settings', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                                const Spacer(),
                                const SizedBox(width: 38),
                              ],
                            ),
                            const SizedBox(height: 24),
                            // Profile area
                            Row(
                              children: [
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      colors: [Colors.white.withOpacity(0.25), Colors.white.withOpacity(0.1)],
                                    ),
                                    border: Border.all(color: Colors.white.withOpacity(0.3), width: 2),
                                  ),
                                  child: const Icon(Icons.person_rounded, color: Colors.white, size: 28),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('AmoWallet User',
                                          style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
                                      const SizedBox(height: 3),
                                      Text('Version ${AppConstants.appVersion}',
                                          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // â”€â”€ Body â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // â”€â”€ WALLET SECTION â”€â”€
                        _sectionHeader('Wallet', Icons.account_balance_wallet_rounded, const Color(0xFF8B5CF6), textColor),
                        const SizedBox(height: 10),
                        _groupCard(cardColor, dividerColor, [
                          _settingsRow(Icons.shield_rounded, 'Security', 'PIN, passwords & protection',
                              const Color(0xFF8B5CF6), textColor, subtextColor,
                              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SecuritySettingsPage()))),
                          _settingsRow(Icons.security_rounded, 'Advanced Security', 'HSM, Behavioral, Remote Wipe',
                              const Color(0xFF6D28D9), textColor, subtextColor,
                              onTap: () => context.push('/advanced-security')),
                          _settingsRow(Icons.backup_rounded, 'Backup & Recovery', 'Manage recovery phrase',
                              const Color(0xFF059669), textColor, subtextColor,
                              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BackupRecoveryPage()))),
                          _settingsRow(Icons.hub_rounded, 'Networks', 'Configure blockchains',
                              const Color(0xFF0EA5E9), textColor, subtextColor,
                              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NetworkSettingsPage()))),
                          _settingsRow(Icons.contacts_rounded, 'Address Book', 'Manage saved contacts',
                              const Color(0xFFF59E0B), textColor, subtextColor,
                              onTap: () => context.push('/address-book')),
                          _settingsRow(Icons.fingerprint, 'Biometrics', biometricEnabled == true ? 'Enabled' : 'Disabled',
                              const Color(0xFFEC4899), textColor, subtextColor,
                              trailing: _styledSwitch(biometricEnabled ?? false, (value) async {
                                if (value) {
                                  final isPinSet = await _pinAuthService.isPinSet();
                                  if (!isPinSet) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Please set up a PIN first'), backgroundColor: Colors.orange),
                                      );
                                    }
                                    return;
                                  }
                                  try {
                                    final auth = await _biometricService.authenticateWithBiometrics(reason: 'Enable biometric login');
                                    if (auth) {
                                      await _pinAuthService.setBiometricEnabled(true);
                                      ref.read(biometricEnabledProvider.notifier).state = true;
                                    }
                                  } catch (_) {
                                    await _pinAuthService.setBiometricEnabled(true);
                                    ref.read(biometricEnabledProvider.notifier).state = true;
                                  }
                                } else {
                                  await _pinAuthService.setBiometricEnabled(false);
                                  ref.read(biometricEnabledProvider.notifier).state = false;
                                }
                              })),
                          _settingsRow(Icons.refresh_rounded, 'Reset Balances', 'Clear swap data & fix balances',
                              const Color(0xFFEF4444), textColor, subtextColor,
                              onTap: () => _resetBalances()),
                        ]),

                        const SizedBox(height: 24),

                        // â”€â”€ PREFERENCES SECTION â”€â”€
                        _sectionHeader('Preferences', Icons.tune_rounded, const Color(0xFF0EA5E9), textColor),
                        const SizedBox(height: 10),
                        _groupCard(cardColor, dividerColor, [
                          _settingsRow(Icons.dark_mode_rounded, 'Dark Mode',
                              ref.watch(themeProvider) == ThemeMode.dark ? 'On' : 'Off',
                              const Color(0xFF6366F1), textColor, subtextColor,
                              trailing: _styledSwitch(ref.watch(themeProvider) == ThemeMode.dark, (v) {
                                ref.read(themeProvider.notifier).toggleTheme();
                              })),
                          _settingsRow(
                              screenshotAllowed ? Icons.screenshot_rounded : Icons.no_photography_rounded,
                              'Screenshots',
                              screenshotAllowed ? 'Allowed' : 'Blocked',
                              const Color(0xFFF59E0B), textColor, subtextColor,
                              trailing: _styledSwitch(screenshotAllowed, (v) async {
                                await _screenshotService.setScreenshotAllowed(v);
                                ref.read(screenshotAllowedProvider.notifier).state = v;
                              })),
                          _settingsRow(Icons.language_rounded, 'Language', 'English',
                              const Color(0xFF10B981), textColor, subtextColor,
                              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LanguageSettingsPage()))),
                          _settingsRow(Icons.attach_money_rounded, 'Currency', 'USD',
                              const Color(0xFF8B5CF6), textColor, subtextColor,
                              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CurrencySettingsPage()))),
                          _settingsRow(Icons.notifications_active_rounded, 'Notifications', 'Alerts & updates',
                              const Color(0xFFEF4444), textColor, subtextColor,
                              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationSettingsPage()))),
                        ]),

                        const SizedBox(height: 24),

                        // â”€â”€ SUPPORT SECTION â”€â”€
                        _sectionHeader('Support', Icons.support_agent_rounded, const Color(0xFF10B981), textColor),
                        const SizedBox(height: 10),
                        _groupCard(cardColor, dividerColor, [
                          _settingsRow(Icons.help_outline_rounded, 'Help & Support', 'FAQs and guides',
                              const Color(0xFF0EA5E9), textColor, subtextColor,
                              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HelpSupportPage()))),
                          _settingsRow(Icons.bug_report_rounded, 'Report a Bug', 'Found an issue?',
                              const Color(0xFFF59E0B), textColor, subtextColor,
                              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReportBugPage()))),
                          _settingsRow(Icons.description_rounded, 'Terms & Privacy', 'Legal information',
                              const Color(0xFF6366F1), textColor, subtextColor,
                              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TermsPrivacyPage()))),
                          _settingsRow(Icons.info_outline_rounded, 'About AmoWallet', 'Version ${AppConstants.appVersion}',
                              const Color(0xFF8B5CF6), textColor, subtextColor,
                              onTap: () => _showAboutDialog()),
                        ]),

                        const SizedBox(height: 28),

                        // â”€â”€ LOGOUT â”€â”€
                        GestureDetector(
                          onTap: _logout,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.3)),
                              color: const Color(0xFFEF4444).withOpacity(0.08),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.logout_rounded, color: const Color(0xFFEF4444), size: 20),
                                const SizedBox(width: 10),
                                const Text('Log Out',
                                    style: TextStyle(color: Color(0xFFEF4444), fontSize: 16, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 100),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // â”€â”€ Helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _sectionHeader(String title, IconData icon, Color accent, Color textColor) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: accent.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: accent, size: 16),
        ),
        const SizedBox(width: 10),
        Text(title, style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
      ],
    );
  }

  Widget _groupCard(Color cardColor, Color dividerColor, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 56),
                child: Divider(height: 1, color: dividerColor),
              ),
          ],
        ],
      ),
    );
  }

  Widget _settingsRow(IconData icon, String title, String subtitle, Color accent,
      Color textColor, Color subtextColor, {VoidCallback? onTap, Widget? trailing}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accent, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(color: subtextColor, fontSize: 12)),
                  ],
                ),
              ),
              if (trailing != null) trailing
              else if (onTap != null)
                Icon(Icons.chevron_right_rounded, color: subtextColor.withOpacity(0.5), size: 22),
            ],
          ),
        ),
      ),
    );
  }

  Widget _styledSwitch(bool value, ValueChanged<bool> onChanged) {
    return Transform.scale(
      scale: 0.85,
      child: Switch.adaptive(
        value: value,
        onChanged: onChanged,
        activeColor: const Color(0xFF8B5CF6),
        activeTrackColor: const Color(0xFF8B5CF6).withOpacity(0.3),
      ),
    );
  }

  Future<void> _resetBalances() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Balances?'),
        content: const Text(
          'This will clear all swap adjustment data and show only your actual blockchain balances.\n\n'
          'Use this if your balances appear incorrect.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Reset', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await WalletService().clearSwapAdjustments();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Balances reset! Go to Dashboard to see updates.'), backgroundColor: Colors.green),
        );
      }
    }
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.account_balance_wallet, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('AmoWallet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text('Version ${AppConstants.appVersion}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ],
        ),
        content: const Text(
          'A secure, non-custodial cryptocurrency wallet.\n\n'
          'âœ… Multi-chain support\n'
          'âœ… Real-time prices\n'
          'âœ… Secure key storage\n'
          'âœ… Transaction history',
          style: TextStyle(fontSize: 14),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('Make sure you have backed up your recovery phrase before logging out.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFEF4444)),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await AuthService().logout();
      if (mounted) context.go('/onboarding');
    }
  }
}
