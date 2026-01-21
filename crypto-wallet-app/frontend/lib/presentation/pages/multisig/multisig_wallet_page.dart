import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';

import '../../../core/config/api_config.dart';
import '../../../services/biometric_auth_service.dart';
import '../../../services/pin_auth_service.dart';

class MultiSigWalletPage extends ConsumerStatefulWidget {
  const MultiSigWalletPage({super.key});

  @override
  ConsumerState<MultiSigWalletPage> createState() => _MultiSigWalletPageState();
}

class _MultiSigWalletPageState extends ConsumerState<MultiSigWalletPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _dio = Dio();
  final _biometricService = BiometricAuthService();
  final _pinAuthService = PinAuthService();

  // State
  String? _walletAddress;
  Map<String, dynamic>? _walletInfo;
  List<dynamic> _pendingTransactions = [];
  List<dynamic> _owners = [];
  int _requiredSignatures = 2;
  bool _loading = false;
  bool _hasWallet = false;
  double _balance = 0.0;

  // Theme colors
  static const Color _primaryColor = Color(0xFF6366F1);
  static const Color _secondaryColor = Color(0xFF8B5CF6);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadExistingWallet();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadExistingWallet() async {
    setState(() => _loading = true);
    try {
      // Check if user has existing multisig wallet stored
      // For now, we'll check a backend endpoint
      final response = await _dio.get(
        '${ApiConfig.baseUrl}/api/multisig/my-wallet',
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200 && response.data['address'] != null) {
        setState(() {
          _walletAddress = response.data['address'];
          _hasWallet = true;
        });
        await _loadWalletDetails();
      }
    } catch (e) {
      // No existing wallet
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadWalletDetails() async {
    if (_walletAddress == null) return;

    try {
      final response = await _dio.get(
        '${ApiConfig.baseUrl}/api/multisig/owners/$_walletAddress',
      );

      if (response.statusCode == 200) {
        setState(() {
          _walletInfo = response.data;
          _owners = response.data['owners'] ?? [];
          _requiredSignatures = response.data['required'] ?? 2;
          _balance = (response.data['balance'] ?? 0).toDouble();
        });
        await _loadPendingTransactions();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load wallet: $e')),
        );
      }
    }
  }

  Future<void> _loadPendingTransactions() async {
    if (_walletAddress == null) return;

    try {
      final response = await _dio.get(
        '${ApiConfig.baseUrl}/api/multisig/pending/$_walletAddress',
      );

      if (response.statusCode == 200) {
        setState(() {
          _pendingTransactions = response.data['pending'] ?? [];
        });
      }
    } catch (e) {
      // Silent fail
    }
  }

  Future<bool> _authenticate() async {
    // Try biometric first
    final biometricAvailable = await _biometricService.isBiometricAvailable();
    // Use PinAuthService as single source of truth for biometric enabled
    final biometricEnabled = await _pinAuthService.isBiometricEnabled();

    if (biometricAvailable && biometricEnabled) {
      final result = await _biometricService.authenticateWithBiometrics(
        reason: 'Authenticate to access MultiSig wallet',
      );
      if (result) return true;
    }

    // Fall back to PIN
    return await _showPinDialog();
  }

  Future<bool> _showPinDialog() async {
    String enteredPin = '';
    bool isValid = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text('Enter PIN', textAlign: TextAlign.center),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // PIN dots
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(6, (index) {
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: index < enteredPin.length
                              ? _primaryColor
                              : Colors.grey[300],
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 24),
                  // Number pad
                  SizedBox(
                    height: 240,
                    child: GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        childAspectRatio: 1.5,
                      ),
                      itemCount: 12,
                      itemBuilder: (ctx, index) {
                        if (index == 9) return const SizedBox();
                        if (index == 10) {
                          return _buildPinButton('0', () {
                            if (enteredPin.length < 6) {
                              setDialogState(() => enteredPin += '0');
                              if (enteredPin.length == 6) {
                                _pinAuthService.verifyPin(enteredPin).then((valid) {
                                  isValid = valid;
                                  Navigator.pop(context);
                                });
                              }
                            }
                          });
                        }
                        if (index == 11) {
                          return IconButton(
                            icon: const Icon(Icons.backspace_outlined),
                            onPressed: () {
                              if (enteredPin.isNotEmpty) {
                                setDialogState(() {
                                  enteredPin = enteredPin.substring(0, enteredPin.length - 1);
                                });
                              }
                            },
                          );
                        }
                        return _buildPinButton('${index + 1}', () {
                          if (enteredPin.length < 6) {
                            setDialogState(() => enteredPin += '${index + 1}');
                            if (enteredPin.length == 6) {
                              _pinAuthService.verifyPin(enteredPin).then((valid) {
                                isValid = valid;
                                Navigator.pop(context);
                              });
                            }
                          }
                        });
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    return isValid;
  }

  Widget _buildPinButton(String digit, VoidCallback onTap) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Center(
        child: Text(
          digit,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _hasWallet
              ? _buildWalletView()
              : _buildSetupView(),
    );
  }

  Widget _buildSetupView() {
    return CustomScrollView(
      slivers: [
        // Header
        SliverAppBar(
          expandedHeight: 200,
          pinned: true,
          backgroundColor: _primaryColor,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => context.go('/dashboard'),
          ),
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_primaryColor, _secondaryColor],
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.security,
                          color: Colors.white,
                          size: 48,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'MultiSig Wallet',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                // Info card
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.shield_outlined,
                        size: 64,
                        color: _primaryColor,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Enhanced Security',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'MultiSig wallets require multiple signatures to authorize transactions, providing an extra layer of security for your assets.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Features
                _buildFeatureCard(
                  Icons.people,
                  'Multiple Signers',
                  'Add 2-10 co-signers who must approve transactions',
                ),
                const SizedBox(height: 12),
                _buildFeatureCard(
                  Icons.verified_user,
                  'Customizable Threshold',
                  'Set how many signatures are required (e.g., 2 of 3)',
                ),
                const SizedBox(height: 12),
                _buildFeatureCard(
                  Icons.lock_outline,
                  'Cold Storage Ready',
                  'Perfect for securing large amounts of crypto',
                ),

                const SizedBox(height: 32),

                // Create button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () => _showCreateWalletDialog(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 4,
                      shadowColor: _primaryColor.withOpacity(0.4),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_circle_outline),
                        SizedBox(width: 8),
                        Text(
                          'Create MultiSig Wallet',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Import button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: OutlinedButton(
                    onPressed: () => _showImportWalletDialog(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _primaryColor,
                      side: const BorderSide(color: _primaryColor, width: 2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.download_outlined),
                        SizedBox(width: 8),
                        Text(
                          'Import Existing Wallet',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureCard(IconData icon, String title, String description) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: _primaryColor, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWalletView() {
    return NestedScrollView(
      headerSliverBuilder: (context, innerBoxIsScrolled) {
        return [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: _primaryColor,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => context.go('/dashboard'),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white),
                onPressed: _loadWalletDetails,
              ),
              IconButton(
                icon: const Icon(Icons.settings, color: Colors.white),
                onPressed: () => _showSettingsDialog(),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [_primaryColor, _secondaryColor],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        const Text(
                          'MultiSig Wallet',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_balance.toStringAsFixed(4)} ETH',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: _walletAddress ?? ''));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Address copied')),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _formatAddress(_walletAddress ?? ''),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Icon(Icons.copy, color: Colors.white70, size: 14),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: Container(
                color: _primaryColor.withOpacity(0.9),
                child: TabBar(
                  controller: _tabController,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white60,
                  indicatorColor: Colors.white,
                  indicatorWeight: 3,
                  tabs: const [
                    Tab(text: 'Pending'),
                    Tab(text: 'Owners'),
                    Tab(text: 'History'),
                  ],
                ),
              ),
            ),
          ),
        ];
      },
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPendingTab(),
          _buildOwnersTab(),
          _buildHistoryTab(),
        ],
      ),
    );
  }

  Widget _buildPendingTab() {
    return Column(
      children: [
        // Action buttons
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final authenticated = await _authenticate();
                    if (authenticated) {
                      _showSubmitTransactionDialog();
                    }
                  },
                  icon: const Icon(Icons.send),
                  label: const Text('New Transaction'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Pending transactions list
        Expanded(
          child: _pendingTransactions.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.hourglass_empty, size: 64, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      Text(
                        'No pending transactions',
                        style: TextStyle(color: Colors.grey[500], fontSize: 16),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _pendingTransactions.length,
                  itemBuilder: (context, index) {
                    final tx = _pendingTransactions[index];
                    return _buildPendingTxCard(tx);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildPendingTxCard(Map<String, dynamic> tx) {
    final confirmations = tx['confirmations'] ?? 0;
    final required = _requiredSignatures;
    final progress = confirmations / required;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.pending_actions, color: Colors.orange, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TX #${tx['txIndex'] ?? (tx['index'] ?? '?')}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        _formatAddress(tx['to'] ?? ''),
                        style: TextStyle(color: Colors.grey[500], fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
              Text(
                '${(tx['value'] ?? 0) / 1e18} ETH',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Progress
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.grey[200],
                    valueColor: AlwaysStoppedAnimation(
                      progress >= 1 ? Colors.green : _primaryColor,
                    ),
                    minHeight: 8,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '$confirmations/$required',
                style: TextStyle(
                  color: progress >= 1 ? Colors.green : Colors.grey[600],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          // Actions
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final authenticated = await _authenticate();
                    if (authenticated) {
                      _confirmTransaction(tx['txIndex']);
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.green,
                    side: const BorderSide(color: Colors.green),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Approve'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final authenticated = await _authenticate();
                    if (authenticated) {
                      _revokeConfirmation(tx['txIndex']);
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Reject'),
                ),
              ),
              if (progress >= 1) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      final authenticated = await _authenticate();
                      if (authenticated) {
                        _executeTransaction(tx['txIndex']);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('Execute'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOwnersTab() {
    return Column(
      children: [
        // Info card
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: _primaryColor),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'This wallet requires $_requiredSignatures of ${_owners.length} signatures to execute transactions',
                  style: TextStyle(color: _primaryColor, fontSize: 13),
                ),
              ),
            ],
          ),
        ),

        // Owners list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _owners.length,
            itemBuilder: (context, index) {
              final owner = _owners[index];
              final address = owner is String ? owner : owner['address'] ?? '';
              final name = owner is Map ? owner['name'] ?? 'Owner ${index + 1}' : 'Owner ${index + 1}';
              
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.08),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [_primaryColor.withOpacity(0.8), _secondaryColor],
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatAddress(address),
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.copy, color: Colors.grey[400]),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: address));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Address copied')),
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'Transaction history coming soon',
            style: TextStyle(color: Colors.grey[500], fontSize: 16),
          ),
        ],
      ),
    );
  }

  String _formatAddress(String address) {
    if (address.length > 20) {
      return '${address.substring(0, 10)}...${address.substring(address.length - 6)}';
    }
    return address;
  }

  // Dialog methods
  void _showCreateWalletDialog() {
    final ownersController = TextEditingController(text: '3');
    final requiredController = TextEditingController(text: '2');
    final List<TextEditingController> ownerAddresses = [
      TextEditingController(),
      TextEditingController(),
      TextEditingController(),
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.85,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  // Handle
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Create MultiSig Wallet',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Set up a new multi-signature wallet with your trusted co-signers',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 24),

                          // Threshold
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Total Owners', style: TextStyle(fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 8),
                                    TextField(
                                      controller: ownersController,
                                      keyboardType: TextInputType.number,
                                      decoration: InputDecoration(
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                      ),
                                      onChanged: (val) {
                                        final count = int.tryParse(val) ?? 3;
                                        setSheetState(() {
                                          while (ownerAddresses.length < count) {
                                            ownerAddresses.add(TextEditingController());
                                          }
                                          while (ownerAddresses.length > count) {
                                            ownerAddresses.removeLast();
                                          }
                                        });
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Required Signatures', style: TextStyle(fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 8),
                                    TextField(
                                      controller: requiredController,
                                      keyboardType: TextInputType.number,
                                      decoration: InputDecoration(
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 24),
                          const Text('Owner Addresses', style: TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 12),

                          ...ownerAddresses.asMap().entries.map((entry) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: TextField(
                                controller: entry.value,
                                decoration: InputDecoration(
                                  labelText: 'Owner ${entry.key + 1}',
                                  hintText: '0x...',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                ),
                              ),
                            );
                          }),

                          const SizedBox(height: 24),

                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: ElevatedButton(
                              onPressed: () async {
                                Navigator.pop(context);
                                await _createWallet(
                                  ownerAddresses.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList(),
                                  int.tryParse(requiredController.text) ?? 2,
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _primaryColor,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              child: const Text('Create Wallet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showImportWalletDialog() {
    final addressController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Import MultiSig Wallet'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: addressController,
                decoration: InputDecoration(
                  labelText: 'Contract Address',
                  hintText: '0x...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
              onPressed: () {
                Navigator.pop(context);
                _importWallet(addressController.text.trim());
              },
              style: ElevatedButton.styleFrom(backgroundColor: _primaryColor),
              child: const Text('Import'),
            ),
          ],
        );
      },
    );
  }

  void _showSubmitTransactionDialog() {
    final toController = TextEditingController();
    final amountController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'New Transaction',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: toController,
                    decoration: InputDecoration(
                      labelText: 'Recipient Address',
                      hintText: '0x...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Amount (ETH)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _submitTransaction(toController.text.trim(), amountController.text.trim());
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text('Submit Transaction', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showSettingsDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.person_add),
                title: const Text('Add Owner'),
                onTap: () {
                  Navigator.pop(context);
                  // TODO: Implement
                },
              ),
              ListTile(
                leading: const Icon(Icons.tune),
                title: const Text('Change Threshold'),
                onTap: () {
                  Navigator.pop(context);
                  // TODO: Implement
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text('Disconnect Wallet', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _hasWallet = false;
                    _walletAddress = null;
                  });
                },
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  // API methods
  Future<void> _createWallet(List<String> owners, int required) async {
    setState(() => _loading = true);
    try {
      final response = await _dio.post(
        '${ApiConfig.baseUrl}/api/multisig/deploy',
        data: {'owners': owners, 'required': required},
      );

      if (response.statusCode == 200) {
        setState(() {
          _walletAddress = response.data['address'];
          _hasWallet = true;
        });
        await _loadWalletDetails();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('MultiSig wallet created successfully'), backgroundColor: Colors.green),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create wallet: $e')),
        );
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _importWallet(String address) async {
    if (address.isEmpty || !address.startsWith('0x')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid address')),
      );
      return;
    }

    setState(() {
      _walletAddress = address;
      _hasWallet = true;
    });
    await _loadWalletDetails();
  }

  Future<void> _submitTransaction(String to, String amount) async {
    if (to.isEmpty || amount.isEmpty) return;

    try {
      final amountWei = (double.parse(amount) * 1e18).toStringAsFixed(0);
      
      await _dio.post(
        '${ApiConfig.baseUrl}/api/multisig/submit',
        data: {
          'contractAddress': _walletAddress,
          'to': to,
          'value': amountWei,
          'data': '0x',
        },
      );

      await _loadPendingTransactions();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transaction submitted'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _confirmTransaction(int txIndex) async {
    try {
      await _dio.post(
        '${ApiConfig.baseUrl}/api/multisig/confirm',
        data: {'contractAddress': _walletAddress, 'txIndex': txIndex},
      );
      await _loadPendingTransactions();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _revokeConfirmation(int txIndex) async {
    try {
      await _dio.post(
        '${ApiConfig.baseUrl}/api/multisig/revoke',
        data: {'contractAddress': _walletAddress, 'txIndex': txIndex},
      );
      await _loadPendingTransactions();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _executeTransaction(int txIndex) async {
    try {
      await _dio.post(
        '${ApiConfig.baseUrl}/api/multisig/execute',
        data: {'contractAddress': _walletAddress, 'txIndex': txIndex},
      );
      await _loadPendingTransactions();
      await _loadWalletDetails();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transaction executed'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }
}
