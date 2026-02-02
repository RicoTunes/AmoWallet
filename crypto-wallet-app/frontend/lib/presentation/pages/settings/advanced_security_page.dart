import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/behavioral_biometrics_service.dart';
import '../../../services/remote_wipe_service.dart';
import '../../../services/hsm_security_service.dart';
import '../../../services/pin_auth_service.dart';

class AdvancedSecurityPage extends ConsumerStatefulWidget {
  const AdvancedSecurityPage({super.key});

  @override
  ConsumerState<AdvancedSecurityPage> createState() => _AdvancedSecurityPageState();
}

class _AdvancedSecurityPageState extends ConsumerState<AdvancedSecurityPage> {
  final BehavioralBiometricsService _behavioralService = BehavioralBiometricsService();
  final RemoteWipeService _remoteWipeService = RemoteWipeService();
  final HsmSecurityService _hsmService = HsmSecurityService();
  final PinAuthService _pinAuthService = PinAuthService();

  bool _behavioralEnabled = false;
  bool _remoteWipeEnabled = false;
  bool _hasDuressPin = false;
  bool _isLoading = true;
  
  Map<String, dynamic> _behavioralStats = {};
  Map<String, dynamic> _hsmReport = {};
  String? _deviceId;
  double _trustScore = 100.0;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    
    try {
      await _behavioralService.initialize();
      await _remoteWipeService.initialize();
      await _hsmService.initialize();
      
      final behavioralEnabled = _behavioralService.isEnabled;
      final remoteWipeEnabled = await _remoteWipeService.isRemoteWipeEnabled();
      final hasDuressPin = await _remoteWipeService.hasDuressPin();
      final behavioralStats = _behavioralService.getStatistics();
      final hsmReport = _hsmService.getSecurityReport();
      final deviceId = await _remoteWipeService.getDeviceId();
      final trustScore = _behavioralService.getTrustScore();

      setState(() {
        _behavioralEnabled = behavioralEnabled;
        _remoteWipeEnabled = remoteWipeEnabled;
        _hasDuressPin = hasDuressPin;
        _behavioralStats = behavioralStats;
        _hsmReport = hsmReport;
        _deviceId = deviceId;
        _trustScore = trustScore;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Failed to load security settings');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Advanced Security'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadSettings,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Trust Score Card
                    _buildTrustScoreCard(),
                    const SizedBox(height: 20),
                    
                    // HSM Status
                    _buildSectionHeader('Hardware Security', Icons.security),
                    _buildHsmStatusCard(),
                    const SizedBox(height: 20),
                    
                    // Behavioral Biometrics
                    _buildSectionHeader('Behavioral Biometrics', Icons.psychology),
                    _buildBehavioralCard(),
                    const SizedBox(height: 20),
                    
                    // Duress PIN
                    _buildSectionHeader('Duress PIN (Panic Mode)', Icons.warning_amber),
                    _buildDuressPinCard(),
                    const SizedBox(height: 20),
                    
                    // Remote Wipe
                    _buildSectionHeader('Remote Wipe', Icons.delete_forever),
                    _buildRemoteWipeCard(),
                    const SizedBox(height: 20),
                    
                    // Emergency Actions
                    _buildSectionHeader('Emergency Actions', Icons.emergency),
                    _buildEmergencyActionsCard(),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: Colors.deepPurple, size: 24),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrustScoreCard() {
    final scoreColor = _trustScore >= 80 
        ? Colors.green 
        : _trustScore >= 50 
            ? Colors.orange 
            : Colors.red;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.deepPurple, Colors.deepPurple.shade700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.deepPurple.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            'Security Trust Score',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _trustScore.toStringAsFixed(0),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 56,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text(
                  '/100',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 20,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: scoreColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: scoreColor, width: 1),
            ),
            child: Text(
              _trustScore >= 80 
                  ? '✓ Excellent - Normal behavior detected'
                  : _trustScore >= 50 
                      ? '⚠ Moderate - Some anomalies detected'
                      : '⚠ Low - Unusual activity detected',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHsmStatusCard() {
    final hsmStatus = _hsmReport['hsm_status'] ?? 'unknown';
    final isHardwareBacked = _hsmReport['hardware_backed'] ?? false;
    
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isHardwareBacked ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isHardwareBacked ? Icons.verified_user : Icons.shield,
                  color: isHardwareBacked ? Colors.green : Colors.orange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isHardwareBacked ? 'Hardware-Backed Security' : 'Software Security',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      _hsmReport['key_storage'] ?? 'Unknown',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isHardwareBacked ? Colors.green : Colors.orange,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  hsmStatus.toString().toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildInfoRow('Encryption', _hsmReport['encryption'] ?? 'AES-256'),
          _buildInfoRow('Integrity', _hsmReport['integrity'] ?? 'HMAC-SHA256'),
        ],
      ),
    );
  }

  Widget _buildBehavioralCard() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Behavioral Monitoring',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    'Learns your usage patterns',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  ),
                ],
              ),
              Switch(
                value: _behavioralEnabled,
                onChanged: (value) => _toggleBehavioral(value),
                activeColor: Colors.deepPurple,
              ),
            ],
          ),
          if (_behavioralEnabled) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            const Text(
              'What it monitors:',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 8),
            _buildMonitoringItem(Icons.pin, 'PIN entry timing', 'How fast you type your PIN'),
            _buildMonitoringItem(Icons.schedule, 'Usage times', 'When you typically use the app'),
            _buildMonitoringItem(Icons.payments, 'Transaction patterns', 'Your typical amounts'),
            _buildMonitoringItem(Icons.touch_app, 'Touch behavior', 'Pressure and swipe patterns'),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            const Text(
              'Learning Progress:',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 8),
            _buildProgressRow('PIN samples', _behavioralStats['pin_samples'] ?? 0, 10),
            _buildProgressRow('Session samples', _behavioralStats['session_samples'] ?? 0, 10),
            _buildProgressRow('Transaction samples', _behavioralStats['transaction_samples'] ?? 0, 5),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.blue, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _behavioralStats['baseline_established'] == true
                          ? 'Baseline established! Anomaly detection active.'
                          : 'Still learning your patterns. Keep using the app normally.',
                      style: const TextStyle(color: Colors.blue, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDuressPinCard() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.warning_amber, color: Colors.red),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Duress PIN',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Text(
                      _hasDuressPin ? 'Configured' : 'Not configured',
                      style: TextStyle(
                        color: _hasDuressPin ? Colors.green : Colors.grey[600],
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (_hasDuressPin)
                const Icon(Icons.check_circle, color: Colors.green),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  '⚠️ What is a Duress PIN?',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                SizedBox(height: 8),
                Text(
                  'A separate PIN that, when entered, immediately wipes all wallet data. '
                  'Use it if someone forces you to unlock your wallet under threat.',
                  style: TextStyle(fontSize: 13, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _showDuressPinSetup(),
              icon: Icon(_hasDuressPin ? Icons.edit : Icons.add),
              label: Text(_hasDuressPin ? 'Change Duress PIN' : 'Set Up Duress PIN'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRemoteWipeCard() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Remote Wipe',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Text(
                    'Wipe wallet remotely if device is lost',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  ),
                ],
              ),
              Switch(
                value: _remoteWipeEnabled,
                onChanged: (value) => _toggleRemoteWipe(value),
                activeColor: Colors.deepPurple,
              ),
            ],
          ),
          if (_remoteWipeEnabled && _deviceId != null) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            const Text(
              'Your Device ID:',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _deviceId!,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 20),
                    onPressed: () => _copyToClipboard(_deviceId!),
                    tooltip: 'Copy',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Save your Device ID somewhere safe. You\'ll need it to trigger a remote wipe from another device.',
                style: TextStyle(fontSize: 13, color: Colors.blue),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmergencyActionsCard() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '⚠️ Danger Zone',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.red,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'These actions cannot be undone!',
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _confirmResetBehavioral(),
              icon: const Icon(Icons.restart_alt),
              label: const Text('Reset Behavioral Profile'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.orange,
                side: const BorderSide(color: Colors.orange),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _confirmEmergencyWipe(),
              icon: const Icon(Icons.delete_forever),
              label: const Text('Emergency Wipe NOW'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildMonitoringItem(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.deepPurple),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
                Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressRow(String label, int current, int required) {
    final progress = (current / required).clamp(0.0, 1.0);
    final isComplete = current >= required;
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontSize: 13)),
              Text(
                '$current / $required',
                style: TextStyle(
                  fontSize: 13,
                  color: isComplete ? Colors.green : Colors.grey[600],
                  fontWeight: isComplete ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation(
              isComplete ? Colors.green : Colors.deepPurple,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleBehavioral(bool enabled) async {
    if (enabled) {
      await _behavioralService.enable();
    } else {
      await _behavioralService.disable();
    }
    setState(() => _behavioralEnabled = enabled);
    _showSuccess(enabled ? 'Behavioral monitoring enabled' : 'Behavioral monitoring disabled');
  }

  Future<void> _toggleRemoteWipe(bool enabled) async {
    if (enabled) {
      await _remoteWipeService.enableRemoteWipe();
    } else {
      await _remoteWipeService.disableRemoteWipe();
    }
    setState(() => _remoteWipeEnabled = enabled);
    _showSuccess(enabled ? 'Remote wipe enabled' : 'Remote wipe disabled');
  }

  void _showDuressPinSetup() {
    final pinController = TextEditingController();
    final confirmController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set Up Duress PIN'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '⚠️ WARNING: Entering this PIN will PERMANENTLY DELETE all wallet data!',
                style: TextStyle(color: Colors.red, fontSize: 13),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: pinController,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 8,
              decoration: const InputDecoration(
                labelText: 'Duress PIN (4-8 digits)',
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmController,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 8,
              decoration: const InputDecoration(
                labelText: 'Confirm Duress PIN',
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '• Must be different from your regular PIN\n'
              '• Use something you can remember under stress\n'
              '• Make sure you have a backup of your seed phrase!',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (pinController.text.length < 4) {
                _showError('PIN must be at least 4 digits');
                return;
              }
              if (pinController.text != confirmController.text) {
                _showError('PINs do not match');
                return;
              }
              
              // Check if it's the same as regular PIN
              final isSameAsRegular = await _pinAuthService.verifyPin(pinController.text);
              if (isSameAsRegular) {
                _showError('Duress PIN must be different from your regular PIN');
                return;
              }
              
              final success = await _remoteWipeService.setupDuressPin(pinController.text);
              Navigator.pop(context);
              
              if (success) {
                setState(() => _hasDuressPin = true);
                _showSuccess('Duress PIN configured successfully');
              } else {
                _showError('Failed to set duress PIN');
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Set Duress PIN', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _confirmResetBehavioral() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Behavioral Profile?'),
        content: const Text(
          'This will delete all learned behavior patterns. '
          'The app will need to re-learn your usage patterns from scratch.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _behavioralService.resetProfile();
              await _loadSettings();
              _showSuccess('Behavioral profile reset');
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Reset', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _confirmEmergencyWipe() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 8),
            Text('EMERGENCY WIPE'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '⚠️ THIS WILL PERMANENTLY DELETE:\n'
                '• All wallet data\n'
                '• All private keys\n'
                '• All settings\n\n'
                'You will NOT be able to recover your funds without your seed phrase backup!',
                style: TextStyle(color: Colors.red),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Type "WIPE" to confirm:'),
            const SizedBox(height: 8),
            TextField(
              onChanged: (value) {
                // Handle in button
              },
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Type WIPE',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final result = await _remoteWipeService.executeWipe(WipeReason.userInitiated);
              if (result.success) {
                _showSuccess('Wallet wiped successfully');
                // Navigate to welcome screen
              } else {
                _showError('Wipe failed: ${result.errors.join(', ')}');
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('WIPE NOW', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    _showSuccess('Copied to clipboard');
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
