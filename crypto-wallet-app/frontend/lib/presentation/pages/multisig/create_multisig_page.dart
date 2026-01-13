import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Require authentication
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

      // Show deployment instructions dialog
      if (mounted) {
        await _showDeploymentInstructions(owners, _requiredConfirmations);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create multi-sig wallet: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  Future<void> _showDeploymentInstructions(
    List<String> owners,
    int required,
  ) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.blue),
            SizedBox(width: 8),
            Text('Deploy Multi-Sig Wallet'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Multi-signature wallet configuration:',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text('Owners: ${owners.length}'),
              ...owners.asMap().entries.map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(left: 16, top: 4),
                      child: Text(
                        '${entry.key + 1}. ${entry.value.substring(0, 10)}...${entry.value.substring(entry.value.length - 8)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
              const SizedBox(height: 12),
              Text('Required Confirmations: $required'),
              const Divider(height: 24),
              const Text(
                'Deployment Steps:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _buildStep('1', 'cd backend/contracts'),
              _buildStep('2', 'npm install'),
              _buildStep('3', 'Configure .env file with owner addresses'),
              _buildStep('4', 'npm run compile'),
              _buildStep('5', 'npm run deploy:sepolia'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.lightbulb_outline, size: 16, color: Colors.blue),
                        SizedBox(width: 4),
                        Text(
                          'Environment Variables:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      'MULTISIG_OWNERS=${owners.join(',')}',
                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      'REQUIRED_CONFIRMATIONS=$required',
                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
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
              Clipboard.setData(ClipboardData(
                text: 'MULTISIG_OWNERS=${owners.join(',')}\nREQUIRED_CONFIRMATIONS=$required',
              ));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Configuration copied to clipboard')),
              );
            },
            child: const Text('Copy Config'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            number,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13),
            ),
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
                        Text('Creating...'),
                      ],
                    )
                  : const Text(
                      'Generate Deployment Configuration',
                      style: TextStyle(fontSize: 16),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
