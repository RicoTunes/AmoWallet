import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/config/api_config.dart';
import '../../../core/services/api_auth_service.dart';
import '../../../services/biometric_auth_service.dart';

class CreateMultiSigPage extends StatefulWidget {
  const CreateMultiSigPage({super.key});

  @override
  State<CreateMultiSigPage> createState() => _CreateMultiSigPageState();
}

class _CreateMultiSigPageState extends State<CreateMultiSigPage> {
  final _formKey = GlobalKey<FormState>();
  final _ownerControllers = <TextEditingController>[
    TextEditingController(),
    TextEditingController(),
  ];
  int _requiredConfirmations = 2;
  bool _isCreating = false;
  late final Dio _dio;

  @override
  void initState() {
    super.initState();
    _dio = Dio();
    _dio.interceptors.add(ApiAuthService().createDioAuthInterceptor());
  }

  @override
  void dispose() {
    for (var controller in _ownerControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _addOwnerField() {
    setState(() {
      _ownerControllers.add(TextEditingController());
    });
  }

  void _removeOwnerField(int index) {
    if (_ownerControllers.length > 2) {
      setState(() {
        _ownerControllers[index].dispose();
        _ownerControllers.removeAt(index);
        if (_requiredConfirmations > _ownerControllers.length) {
          _requiredConfirmations = _ownerControllers.length;
        }
      });
    }
  }

  Future<void> _createMultiSigWallet() async {
    if (!_formKey.currentState!.validate()) return;

    final authService = BiometricAuthService();
    final authenticated = await authService.requireAuthentication();

    if (!authenticated) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Authentication required')),
        );
      }
      return;
    }

    setState(() => _isCreating = true);

    try {
      final owners = _ownerControllers
          .map((c) => c.text.trim())
          .where((text) => text.isNotEmpty)
          .toList();

      if (owners.length < 2) {
        _showError('At least 2 owner addresses required');
        return;
      }

      // Deploy via Rust backend (on-chain)
      final response = await _dio.post(
        '${ApiConfig.baseUrl}/api/multisig/deploy',
        data: {
          'owners': owners,
          'required': _requiredConfirmations,
        },
        options: Options(validateStatus: (s) => s != null && s < 500),
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode == 200 && response.data['address'] != null) {
        final address = response.data['address'].toString();
        final txHash = (response.data['tx_hash'] ?? '').toString();

        // Persist locally
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('multisig_wallet_address', address);
        await prefs.setStringList('multisig_owners', owners);
        await prefs.setInt('multisig_required', _requiredConfirmations);

        if (mounted) await _showSuccessDialog(address, txHash);
      } else {
        final error = response.data['error'] ?? 'Deployment failed';
        _showError(error.toString());
      }
    } on DioException catch (e) {
      final msg = e.response?.data?['error'] ?? e.message ?? 'Network error';
      _showError(msg.toString());
    } catch (e) {
      _showError('Failed to deploy: $e');
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Future<void> _showSuccessDialog(String address, String txHash) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 8),
            Text('Wallet Deployed!'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Your multi-signature wallet has been deployed on-chain.',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              const Text('Contract Address:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 4),
              SelectableText(
                address,
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              ),
              if (txHash.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Transaction Hash:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 4),
                SelectableText(
                  txHash,
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                ),
              ],
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.security, size: 16, color: Colors.green),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$_requiredConfirmations of ${_ownerControllers.length} signatures required',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: address));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Address copied')),
              );
            },
            child: const Text('Copy Address'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop(); // close dialog
              Navigator.of(context).pop(); // go back to wallet page
            },
            child: const Text('Go to Wallet'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Multi-Sig Wallet'),
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.security, color: Theme.of(context).primaryColor),
                        const SizedBox(width: 8),
                        const Text(
                          'Multi-Signature Security',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'A multi-signature wallet requires multiple approvals before executing transactions. '
                      'This provides enhanced security for large amounts and institutional use.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Wallet Owners',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Enter Ethereum addresses for all wallet owners. Minimum 2 owners required.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 16),
            ..._ownerControllers.asMap().entries.map((entry) {
              final index = entry.key;
              final controller = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: controller,
                        decoration: InputDecoration(
                          labelText: 'Owner ${index + 1} Address',
                          hintText: '0x...',
                          prefixIcon: const Icon(Icons.person),
                          border: const OutlineInputBorder(),
                          suffixIcon: _ownerControllers.length > 2
                              ? IconButton(
                                  icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                                  onPressed: () => _removeOwnerField(index),
                                )
                              : null,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Owner address required';
                          }
                          if (!value.trim().startsWith('0x') || value.trim().length != 42) {
                            return 'Invalid Ethereum address';
                          }
                          return null;
                        },
                        keyboardType: TextInputType.text,
                        textInputAction: TextInputAction.next,
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _addOwnerField,
              icon: const Icon(Icons.add),
              label: const Text('Add Another Owner'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Required Confirmations',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Number of owner approvals required to execute transactions.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Confirmations Required:',
                          style: TextStyle(fontSize: 16),
                        ),
                        Text(
                          '$_requiredConfirmations of ${_ownerControllers.length}',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).primaryColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Slider(
                      value: _requiredConfirmations.toDouble(),
                      min: 1,
                      max: _ownerControllers.length.toDouble(),
                      divisions: _ownerControllers.length - 1,
                      label: _requiredConfirmations.toString(),
                      onChanged: (value) {
                        setState(() {
                          _requiredConfirmations = value.toInt();
                        });
                      },
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '1 (Less Secure)',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                        ),
                        Text(
                          '${_ownerControllers.length} (Most Secure)',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, color: Colors.orange, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Recommended Configurations:',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const SizedBox(height: 4),
                        const Text('• 2-of-3: Good for small teams', style: TextStyle(fontSize: 12)),
                        const Text('• 3-of-5: Recommended for institutions', style: TextStyle(fontSize: 12)),
                        const Text('• Higher ratios: Maximum security', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _isCreating ? null : _createMultiSigWallet,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isCreating
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 12),
                        Text('Deploying on-chain...'),
                      ],
                    )
                  : const Text(
                      'Deploy MultiSig Wallet',
                      style: TextStyle(fontSize: 16),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
