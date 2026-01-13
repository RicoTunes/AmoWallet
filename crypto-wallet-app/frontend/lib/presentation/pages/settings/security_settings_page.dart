import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../services/pin_auth_service.dart';

class SecuritySettingsPage extends ConsumerStatefulWidget {
  const SecuritySettingsPage({super.key});

  @override
  ConsumerState<SecuritySettingsPage> createState() => _SecuritySettingsPageState();
}

class _SecuritySettingsPageState extends ConsumerState<SecuritySettingsPage> {
  final PinAuthService _pinAuthService = PinAuthService();
  bool _pinEnabled = false;
  bool _biometricEnabled = false;
  bool _isPinSet = false;
  bool _isBiometricAvailable = false;
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
    
    setState(() => _isLoading = false);
  }

  Future<void> _togglePin(bool value) async {
    if (value && !_isPinSet) {
      // Navigate to PIN setup using go_router
      context.push('/pin-setup');
      // Reload settings after returning
      await Future.delayed(const Duration(milliseconds: 500));
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
    if (value && !_isPinSet) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please set up a PIN first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (value && !_isBiometricAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Biometric authentication not available on this device'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    await _pinAuthService.setBiometricEnabled(value);
    setState(() => _biometricEnabled = value);
  }

  Future<void> _changePin() async {
    final controller = TextEditingController();
    final newPinController = TextEditingController();
    final confirmPinController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
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
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (newPinController.text != confirmPinController.text) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('New PINs do not match')),
                );
                return;
              }
              
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
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Security Settings')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Security Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // PIN Section
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('PIN Authentication'),
                  subtitle: Text(_isPinSet 
                      ? 'Require PIN when opening app'
                      : 'Set up a PIN for security'),
                  secondary: const Icon(Icons.lock_outline),
                  value: _pinEnabled,
                  onChanged: _togglePin,
                ),
                if (_isPinSet) ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.edit),
                    title: const Text('Change PIN'),
                    onTap: _changePin,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.delete_outline, color: Colors.red),
                    title: const Text('Delete PIN', style: TextStyle(color: Colors.red)),
                    onTap: _deletePin,
                  ),
                ],
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Biometric Section
          Card(
            child: SwitchListTile(
              title: const Text('Biometric Authentication'),
              subtitle: Text(_isBiometricAvailable
                  ? 'Use fingerprint or face to unlock'
                  : 'Not available on this device'),
              secondary: const Icon(Icons.fingerprint),
              value: _biometricEnabled,
              onChanged: _isBiometricAvailable ? _toggleBiometric : null,
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Info Card
          Card(
            color: Colors.blue.withOpacity(0.1),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Security features help protect your wallet when the app is closed or sent to background.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
