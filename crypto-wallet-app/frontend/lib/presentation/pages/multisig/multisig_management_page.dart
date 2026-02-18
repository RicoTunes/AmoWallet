import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/config/api_config.dart';
import '../../../services/biometric_auth_service.dart';

class MultiSigManagementPage extends StatefulWidget {
  const MultiSigManagementPage({super.key});

  @override
  State<MultiSigManagementPage> createState() => _MultiSigManagementPageState();
}

class _MultiSigManagementPageState extends State<MultiSigManagementPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _contractAddressController = TextEditingController();
  final _dio = Dio();
  String? _savedContractAddress;
  Map<String, dynamic>? _contractInfo;
  List<dynamic> _pendingTransactions = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadSavedAddress();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _contractAddressController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedAddress() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('multisig_wallet_address');
    if (saved != null && saved.isNotEmpty) {
      setState(() {
        _savedContractAddress = saved;
        _contractAddressController.text = saved;
      });
      await _loadContractInfo();
      await _loadPendingTransactions();
    }
  }

  Future<void> _loadContractInfo() async {
    final address = _contractAddressController.text.trim();
    if (address.isEmpty || !address.startsWith('0x') || address.length != 42) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid contract address')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await _dio.get(
        '${ApiConfig.baseUrl}/api/multisig/owners/$address',
      );

      if (response.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('multisig_wallet_address', address);
        setState(() {
          _contractInfo = response.data;
          _savedContractAddress = address;
        });
      } else {
        throw Exception('Failed to load contract info');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadPendingTransactions() async {
    final address = _savedContractAddress ?? _contractAddressController.text.trim();
    if (address.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final response = await _dio.get(
        '${ApiConfig.baseUrl}/api/multisig/pending/$address',
      );

      if (response.statusCode == 200) {
        setState(() {
          _pendingTransactions = response.data['pending'] ?? [];
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading transactions: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _submitTransaction() async {
    final authenticated = await BiometricAuthService().requireAuthentication();
    if (!authenticated) return;

    await _showSubmitTransactionDialog();
  }

  Future<void> _showSubmitTransactionDialog() async {
    final recipientController = TextEditingController();
    final amountController = TextEditingController();
    
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Submit Transaction'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: recipientController,
                decoration: const InputDecoration(
                  labelText: 'Recipient Address',
                  hintText: '0x...',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: amountController,
                decoration: const InputDecoration(
                  labelText: 'Amount (ETH)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _submitTransactionToContract(
                recipientController.text.trim(),
                amountController.text.trim(),
              );
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitTransactionToContract(String to, String amount) async {
    if (to.isEmpty || amount.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      // Convert amount to wei (1 ETH = 10^18 wei)
      final amountInWei = (double.parse(amount) * 1e18).toStringAsFixed(0);
      
      final response = await _dio.post(
        '${ApiConfig.baseUrl}/api/multisig/submit',
        data: {
          'contractAddress': _savedContractAddress,
          'to': to,
          'value': amountInWei,
          'data': '0x',
        },
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Transaction submitted successfully'),
              backgroundColor: Colors.green,
            ),
          );
          await _loadPendingTransactions();
        }
      } else {
        throw Exception('Submission failed');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _confirmTransaction(int txIndex) async {
    final authenticated = await BiometricAuthService().requireAuthentication();
    if (!authenticated) return;

    setState(() => _isLoading = true);

    try {
      final response = await _dio.post(
        '${ApiConfig.baseUrl}/api/multisig/confirm',
        data: {
          'contractAddress': _savedContractAddress,
          'txIndex': txIndex,
        },
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Transaction confirmed'),
              backgroundColor: Colors.green,
            ),
          );
          await _loadPendingTransactions();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _executeTransaction(int txIndex) async {
    final authenticated = await BiometricAuthService().requireAuthentication();
    if (!authenticated) return;

    setState(() => _isLoading = true);

    try {
      final response = await _dio.post(
        '${ApiConfig.baseUrl}/api/multisig/execute',
        data: {
          'contractAddress': _savedContractAddress,
          'txIndex': txIndex,
        },
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Transaction executed successfully'),
              backgroundColor: Colors.green,
            ),
          );
          await _loadPendingTransactions();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Multi-Sig Wallet'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Overview', icon: Icon(Icons.dashboard)),
            Tab(text: 'Pending', icon: Icon(Icons.pending_actions)),
            Tab(text: 'Submit', icon: Icon(Icons.send)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOverviewTab(),
          _buildPendingTab(),
          _buildSubmitTab(),
        ],
      ),
    );
  }

  Widget _buildOverviewTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Contract Address',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _contractAddressController,
                  decoration: InputDecoration(
                    hintText: '0x...',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.qr_code_scanner),
                      onPressed: () {
                        // TODO: Implement QR scanner
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _loadContractInfo,
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Load Wallet Info'),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_contractInfo != null) ...[
          const SizedBox(height: 16),
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
                        'Wallet Information',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  _buildInfoRow('Owners', '${_contractInfo!['owners']?.length ?? 0}'),
                  _buildInfoRow('Required Confirmations', '${_contractInfo!['requiredConfirmations'] ?? 'N/A'}'),
                  _buildInfoRow('Balance', '${_contractInfo!['balance'] ?? '0'} ETH'),
                  const SizedBox(height: 16),
                  if (_savedContractAddress != null)
                    OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _savedContractAddress!));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Address copied')),
                        );
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy Address'),
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPendingTab() {
    return RefreshIndicator(
      onRefresh: _loadPendingTransactions,
      child: _pendingTransactions.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No pending transactions',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _loadPendingTransactions,
                    child: const Text('Refresh'),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _pendingTransactions.length,
              itemBuilder: (context, index) {
                final tx = _pendingTransactions[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.orange.withOpacity(0.2),
                      child: const Icon(Icons.pending_actions, color: Colors.orange),
                    ),
                    title: Text('Transaction #${tx['txIndex']}'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('To: ${tx['to']?.substring(0, 10)}...'),
                        Text('Confirmations: ${tx['numConfirmations']}/${_contractInfo?['requiredConfirmations'] ?? '?'}'),
                      ],
                    ),
                    trailing: PopupMenuButton(
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'confirm',
                          child: Row(
                            children: [
                              Icon(Icons.check, color: Colors.green),
                              SizedBox(width: 8),
                              Text('Confirm'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'execute',
                          child: Row(
                            children: [
                              Icon(Icons.play_arrow, color: Colors.blue),
                              SizedBox(width: 8),
                              Text('Execute'),
                            ],
                          ),
                        ),
                      ],
                      onSelected: (value) {
                        if (value == 'confirm') {
                          _confirmTransaction(tx['txIndex']);
                        } else if (value == 'execute') {
                          _executeTransaction(tx['txIndex']);
                        }
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildSubmitTab() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.send,
              size: 80,
              color: Theme.of(context).primaryColor.withOpacity(0.5),
            ),
            const SizedBox(height: 24),
            const Text(
              'Submit New Transaction',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Propose a transaction for multi-signature approval',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _savedContractAddress == null ? null : _submitTransaction,
              icon: const Icon(Icons.add),
              label: const Text('Submit Transaction'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
              ),
            ),
            if (_savedContractAddress == null)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Text(
                  'Load wallet info in Overview tab first',
                  style: TextStyle(color: Colors.orange, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.grey),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
