import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../services/pin_auth_service.dart';
import '../../../services/screenshot_service.dart';

class SecuritySettingsPage extends ConsumerStatefulWidget {
  const SecuritySettingsPage({super.key});

  @override
  ConsumerState<SecuritySettingsPage> createState() => _SecuritySettingsPageState();
}

class _SecuritySettingsPageState extends ConsumerState<SecuritySettingsPage> {
  final PinAuthService _pinAuthService = PinAuthService();
  final ScreenshotService _screenshotService = ScreenshotService();
  bool _pinEnabled = false;
  bool _biometricEnabled = false;
  bool _isPinSet = false;
  bool _isBiometricAvailable = false;
  bool _screenshotAllowed = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    
    _pinEnabled = await _pinAuthService.isPinEnabled();
    _biometricEnabled = await _pinAuthService.isBiometricEnabled();
    _isPinSet = await _pinAuthService.isPinSet();
    _isBiometricAvailable = await _pinAuthService.isBiometricAvailable();
    _screenshotAllowed = await _screenshotService.isScreenshotAllowed();
    
    setState(() => _isLoading = false);
  }

  Future<void> _togglePin(bool value) async {
    if (value && !_isPinSet) {
      // Navigate to PIN setup using go_router and wait for return
      await context.push('/pin-setup');
      // Reload settings after returning from PIN setup
      await _loadSettings();
    } else {
      await _pinAuthService.setPinEnabled(value);
      setState(() => _pinEnabled = value);
      
      if (!value) {
        // Also disable biometric if PIN is disabled
        await _pinAuthService.setBiometricEnabled(false);
        setState(() => _biometricEnabled = false);
      }
    }
  }

  Future<void> _toggleBiometric(bool value) async {
    print('🔐 Toggling biometric to: $value');
    print('🔐 isPinSet: $_isPinSet, isBiometricAvailable: $_isBiometricAvailable');
    
    // Reload pin status first to ensure we have latest state
    _isPinSet = await _pinAuthService.isPinSet();
    print('🔐 After reload - isPinSet: $_isPinSet');
    
    if (value && !_isPinSet) {
      // Navigate to PIN setup first
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please set up a PIN first'),
          backgroundColor: Colors.orange,
        ),
      );
      
      // Navigate to PIN setup and wait
      final result = await context.push<bool>('/pin-setup');
      
      // Reload settings after PIN setup
      await _loadSettings();
      
      // Check if PIN is now set
      if (!_isPinSet) {
        // User cancelled PIN setup
        return;
      }
      
      // If PIN was just set, continue to enable biometric
      if (result != true) {
        return;
      }
    }

    // Don't block - just enable biometric regardless of device support
    // The actual authentication will fail gracefully if not available
    try {
      await _pinAuthService.setBiometricEnabled(value);
      
      // Verify it was saved by re-reading
      final savedValue = await _pinAuthService.isBiometricEnabled();
      print('✅ Biometric saved: $value, read back: $savedValue');
      
      setState(() => _biometricEnabled = savedValue);
      
      if (value) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Biometric authentication enabled'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('❌ Error setting biometric: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _changePin() async {
    final controller = TextEditingController();
    final newPinController = TextEditingController();
    final confirmPinController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        bool isLoading = false;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Change PIN'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    labelText: 'Current PIN',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  obscureText: true,
                  enabled: !isLoading,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: newPinController,
                  decoration: const InputDecoration(
                    labelText: 'New PIN',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  obscureText: true,
                  enabled: !isLoading,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: confirmPinController,
                  decoration: const InputDecoration(
                    labelText: 'Confirm New PIN',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  obscureText: true,
                  enabled: !isLoading,
                ),
                if (isLoading) ...[
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Changing PIN...',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: isLoading ? null : () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: isLoading
                    ? null
                    : () async {
                        if (newPinController.text != confirmPinController.text) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('New PINs do not match')),
                          );
                          return;
                        }

                        setDialogState(() => isLoading = true);

                        final success = await _pinAuthService.changePin(
                          controller.text,
                          newPinController.text,
                        );

                        if (context.mounted) {
                          Navigator.pop(context, success);
                        }
                      },
                child: const Text('Change'),
              ),
            ],
          ),
        );
      },
    );

    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PIN changed successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } else if (result == false && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to change PIN. Check your current PIN.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deletePin() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete PIN?'),
        content: const Text(
          'Are you sure you want to delete your PIN? This will also disable biometric authentication.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _pinAuthService.deletePin();
      await _pinAuthService.setBiometricEnabled(false);
      await _loadSettings();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PIN deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0D1421) : const Color(0xFFF5F5F7);
    final cardColor = isDark ? const Color(0xFF1A2035) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subtextColor = isDark ? Colors.white60 : Colors.grey[600]!;
    final dividerColor = isDark ? Colors.white.withOpacity(0.06) : Colors.grey.withOpacity(0.12);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: bgColor,
      ),
      child: Scaffold(
        backgroundColor: bgColor,
        body: _isLoading
            ? Center(
                child: CircularProgressIndicator(
                  color: const Color(0xFF8B5CF6),
                ),
              )
            : CustomScrollView(
                slivers: [
                  // Gradient header
                  SliverToBoxAdapter(
                    child: Container(
                      padding: EdgeInsets.only(
                        top: MediaQuery.of(context).padding.top + 10,
                        left: 20,
                        right: 20,
                        bottom: 28,
                      ),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF6D28D9), Color(0xFF8B5CF6)],
                        ),
                        borderRadius: BorderRadius.only(
                          bottomLeft: Radius.circular(28),
                          bottomRight: Radius.circular(28),
                        ),
                      ),
                      child: Column(
                        children: [
                          // Top row
                          Row(
                            children: [
                              GestureDetector(
                                onTap: () => context.pop(),
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(Icons.arrow_back_ios_new,
                                      color: Colors.white, size: 18),
                                ),
                              ),
                              const Spacer(),
                            ],
                          ),
                          const SizedBox(height: 20),
                          // Shield icon
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.shield_rounded,
                                color: Colors.white, size: 32),
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'Security Settings',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Protect your wallet and assets',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        // ── Authentication Section ──
                        _sectionHeader('Authentication', Icons.lock_outline, textColor),
                        const SizedBox(height: 10),
                        Container(
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: isDark
                                ? []
                                : [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.04),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                          ),
                          child: Column(
                            children: [
                              // PIN Authentication toggle
                              _buildSettingRow(
                                icon: Icons.dialpad_rounded,
                                iconBgColor: const Color(0xFF8B5CF6),
                                title: 'PIN Authentication',
                                subtitle: _isPinSet
                                    ? 'Require PIN when opening app'
                                    : 'Set up a PIN for security',
                                textColor: textColor,
                                subtextColor: subtextColor,
                                trailing: Switch.adaptive(
                                  value: _pinEnabled,
                                  onChanged: _togglePin,
                                  activeColor: const Color(0xFF8B5CF6),
                                ),
                              ),
                              if (_isPinSet) ...[
                                Divider(height: 1, indent: 68, color: dividerColor),
                                // Change PIN
                                _buildSettingRow(
                                  icon: Icons.edit_rounded,
                                  iconBgColor: const Color(0xFF3B82F6),
                                  title: 'Change PIN',
                                  subtitle: 'Update your security PIN',
                                  textColor: textColor,
                                  subtextColor: subtextColor,
                                  trailing: Icon(Icons.chevron_right_rounded,
                                      color: subtextColor, size: 22),
                                  onTap: _changePin,
                                ),
                                Divider(height: 1, indent: 68, color: dividerColor),
                                // Delete PIN
                                _buildSettingRow(
                                  icon: Icons.delete_outline_rounded,
                                  iconBgColor: const Color(0xFFEF4444),
                                  title: 'Delete PIN',
                                  subtitle: 'Remove PIN protection',
                                  textColor: const Color(0xFFEF4444),
                                  subtextColor: const Color(0xFFEF4444).withOpacity(0.6),
                                  trailing: Icon(Icons.chevron_right_rounded,
                                      color: const Color(0xFFEF4444).withOpacity(0.5), size: 22),
                                  onTap: _deletePin,
                                ),
                              ],
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),

                        // ── Biometric Section ──
                        Container(
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: isDark
                                ? []
                                : [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.04),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                          ),
                          child: _buildSettingRow(
                            icon: Icons.fingerprint_rounded,
                            iconBgColor: const Color(0xFF10B981),
                            title: 'Biometric Unlock',
                            subtitle: _isBiometricAvailable
                                ? 'Use fingerprint or face to unlock'
                                : 'Enable biometric unlock',
                            textColor: textColor,
                            subtextColor: subtextColor,
                            trailing: Switch.adaptive(
                              value: _biometricEnabled,
                              onChanged: _toggleBiometric,
                              activeColor: const Color(0xFF10B981),
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // ── Privacy Section ──
                        _sectionHeader('Privacy', Icons.visibility_off_rounded, textColor),
                        const SizedBox(height: 10),
                        Container(
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: isDark
                                ? []
                                : [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.04),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                          ),
                          child: _buildSettingRow(
                            icon: _screenshotAllowed
                                ? Icons.screenshot_rounded
                                : Icons.no_photography_rounded,
                            iconBgColor: _screenshotAllowed
                                ? const Color(0xFFF59E0B)
                                : const Color(0xFF6366F1),
                            title: 'Allow Screenshots',
                            subtitle: _screenshotAllowed
                                ? 'Screenshots and recording enabled'
                                : 'Screenshots and recording blocked',
                            textColor: textColor,
                            subtextColor: subtextColor,
                            trailing: Switch.adaptive(
                              value: _screenshotAllowed,
                              onChanged: (value) async {
                                await _screenshotService.setScreenshotAllowed(value);
                                setState(() => _screenshotAllowed = value);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Row(
                                        children: [
                                          Icon(
                                            value ? Icons.warning_amber_rounded : Icons.check_circle,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 10),
                                          Text(value
                                              ? 'Screenshots enabled — less secure'
                                              : 'Screenshots blocked — more secure'),
                                        ],
                                      ),
                                      backgroundColor: value ? Colors.orange : Colors.green,
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12)),
                                      margin: const EdgeInsets.all(16),
                                    ),
                                  );
                                }
                              },
                              activeColor: const Color(0xFFF59E0B),
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // ── Info Card ──
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF8B5CF6).withOpacity(isDark ? 0.12 : 0.08),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFF8B5CF6).withOpacity(0.15),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF8B5CF6).withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.info_outline_rounded,
                                    color: Color(0xFF8B5CF6), size: 22),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  'Security features protect your wallet when the app is closed or in background.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: subtextColor,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ]),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon, Color textColor) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF8B5CF6), size: 18),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              color: textColor.withOpacity(0.7),
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingRow({
    required IconData icon,
    required Color iconBgColor,
    required String title,
    required String subtitle,
    required Color textColor,
    required Color subtextColor,
    required Widget trailing,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: iconBgColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconBgColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: subtextColor,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}
