import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/api_config.dart';
import '../../../core/services/api_auth_service.dart';
import '../../../services/biometric_auth_service.dart';
import '../../../services/pin_auth_service.dart';

class MultiSigWalletPage extends ConsumerStatefulWidget {
  const MultiSigWalletPage({super.key});

  @override
  ConsumerState<MultiSigWalletPage> createState() => _MultiSigWalletPageState();
}

class _MultiSigWalletPageState extends ConsumerState<MultiSigWalletPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;
  late final Dio _dio;
  final _biometricService = BiometricAuthService();
  final _pinAuthService = PinAuthService();

  // ── Wallet state ──────────────────────────────────────────────────────────
  String? _walletAddress;
  List<dynamic> _pendingTransactions = [];
  List<dynamic> _historyTransactions = [];
  List<dynamic> _owners = [];
  int _requiredSignatures = 2;
  bool _loading = false;
  bool _hasWallet = false;
  double _balance = 0.0;

  // ── Persisted create-wallet form state ────────────────────────────────────
  final TextEditingController _cwOwnersCountCtrl =
      TextEditingController(text: '3');
  final TextEditingController _cwRequiredSigsCtrl =
      TextEditingController(text: '2');
  List<TextEditingController> _cwOwnerAddressCtrl =
      List.generate(3, (_) => TextEditingController());

  // ── Design tokens ─────────────────────────────────────────────────────────
  static const Color _bg = Color(0xFF0D1421);
  static const Color _card = Color(0xFF1A2332);
  static const Color _cardAlt = Color(0xFF1E2A3A);
  static const Color _accent = Color(0xFF8B5CF6);
  static const Color _accentLight = Color(0xFFA78BFA);
  static const Color _accentDark = Color(0xFF6D28D9);
  static const Color _textPrimary = Colors.white;
  static const Color _textSecondary = Color(0xFF94A3B8);
  static const Color _border = Color(0xFF2D3748);
  static const Color _success = Color(0xFF10B981);
  static const Color _warning = Color(0xFFF59E0B);
  static const Color _danger = Color(0xFFEF4444);

  @override
  void initState() {
    super.initState();
    _dio = Dio();
    _dio.interceptors.add(ApiAuthService().createDioAuthInterceptor());
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 3, vsync: this);
    _restoreCreateWalletForm();
    _loadExistingWallet();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _persistCreateWalletForm();
    }
  }

  Future<void> _persistCreateWalletForm() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('_cw_ownersCount', _cwOwnersCountCtrl.text);
    await prefs.setString('_cw_requiredSigs', _cwRequiredSigsCtrl.text);
    final addrs = _cwOwnerAddressCtrl.map((c) => c.text).toList();
    await prefs.setStringList('_cw_ownerAddresses', addrs);
  }

  Future<void> _restoreCreateWalletForm() async {
    final prefs = await SharedPreferences.getInstance();
    final count = prefs.getString('_cw_ownersCount');
    final required = prefs.getString('_cw_requiredSigs');
    final addrs = prefs.getStringList('_cw_ownerAddresses');
    if (count != null) _cwOwnersCountCtrl.text = count;
    if (required != null) _cwRequiredSigsCtrl.text = required;
    if (addrs != null && addrs.isNotEmpty) {
      while (_cwOwnerAddressCtrl.length < addrs.length) {
        _cwOwnerAddressCtrl.add(TextEditingController());
      }
      for (int i = 0; i < addrs.length; i++) {
        _cwOwnerAddressCtrl[i].text = addrs[i];
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    _cwOwnersCountCtrl.dispose();
    _cwRequiredSigsCtrl.dispose();
    for (final c in _cwOwnerAddressCtrl) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Data loading ──────────────────────────────────────────────────────────

  Future<void> _loadExistingWallet() async {
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedAddress = prefs.getString('multisig_wallet_address');

      if (storedAddress != null && storedAddress.isNotEmpty) {
        setState(() {
          _walletAddress = storedAddress;
          _hasWallet = true;
        });
        await _loadWalletDetails();
        return;
      }

      // Try backend — silently handle 401 / no wallet
      try {
        final response = await _dio
            .get(
              '${ApiConfig.baseUrl}/api/multisig/my-wallet',
              options: Options(
                  validateStatus: (s) => s != null && s < 500),
            )
            .timeout(const Duration(seconds: 5));

        if (response.statusCode == 200 &&
            response.data['address'] != null) {
          setState(() {
            _walletAddress = response.data['address'];
            _hasWallet = true;
          });
          await prefs.setString(
              'multisig_wallet_address', _walletAddress!);
          await _loadWalletDetails();
        }
      } catch (_) {
        // Network unavailable — user can create locally
      }
    } catch (e) {
      debugPrint('MultiSig load error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadWalletDetails() async {
    if (_walletAddress == null) return;
    try {
      final response = await _dio
          .get('${ApiConfig.baseUrl}/api/multisig/owners/$_walletAddress',
              options: Options(validateStatus: (s) => s != null && s < 500))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        setState(() {
          _owners = response.data['owners'] ?? [];
          _requiredSignatures = (response.data['required'] ?? 2) is int
              ? response.data['required']
              : int.tryParse(response.data['required'].toString()) ?? 2;
          _balance = double.tryParse(
                  response.data['balance']?.toString() ?? '0') ??
              0.0;
        });
        await _loadPendingTransactions();
        await _loadHistory();
      }
    } catch (_) {
      // Load from local cache
      final prefs = await SharedPreferences.getInstance();
      final storedOwners = prefs.getStringList('multisig_owners') ?? [];
      final storedRequired = prefs.getInt('multisig_required') ?? 2;
      if (storedOwners.isNotEmpty) {
        setState(() {
          _owners = storedOwners;
          _requiredSignatures = storedRequired;
        });
      }
    }
  }

  Future<void> _loadPendingTransactions() async {
    if (_walletAddress == null) return;
    try {
      final response = await _dio
          .get('${ApiConfig.baseUrl}/api/multisig/pending/$_walletAddress',
              options: Options(validateStatus: (s) => s != null && s < 500))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        setState(() {
          _pendingTransactions = response.data['pending'] ?? [];
        });
      }
    } catch (_) {}
  }

  Future<void> _loadHistory() async {
    if (_walletAddress == null) return;
    try {
      final response = await _dio
          .get('${ApiConfig.baseUrl}/api/multisig/history/$_walletAddress',
              options: Options(validateStatus: (s) => s != null && s < 500))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        setState(() {
          _historyTransactions = response.data['transactions'] ?? [];
        });
      }
    } catch (_) {}
  }

  // ── Auth ──────────────────────────────────────────────────────────────────

  Future<bool> _authenticate() async {
    final biometricAvailable =
        await _biometricService.isBiometricAvailable();
    final biometricEnabled = await _pinAuthService.isBiometricEnabled();
    if (biometricAvailable && biometricEnabled) {
      final result = await _biometricService.authenticateWithBiometrics(
        reason: 'Authenticate to access MultiSig wallet',
      );
      if (result) return true;
    }
    return await _showPinSheet();
  }

  /// PIN entry as a bottom sheet — avoids IntrinsicWidth crash from AlertDialog.
  Future<bool> _showPinSheet() async {
    bool result = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PinEntrySheet(
        pinAuthService: _pinAuthService,
        accent: _accent,
        onResult: (valid) {
          result = valid;
          Navigator.pop(ctx);
        },
      ),
    );
    return result;
  }

  // ── Validation ────────────────────────────────────────────────────────────

  bool _isValidEthAddress(String address) {
    return RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(address);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: _accent))
          : _hasWallet
              ? _buildWalletView()
              : _buildSetupView(),
    );
  }

  // ── Setup screen ──────────────────────────────────────────────────────────

  Widget _buildSetupView() {
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: 180,
          backgroundColor: _bg,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: _textPrimary),
            onPressed: () => context.go('/dashboard'),
          ),
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1A0533), _bg],
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              colors: [_accentDark, _accent]),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(Icons.security,
                            color: Colors.white, size: 32),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'MultiSig Wallet',
                        style: TextStyle(
                          color: _textPrimary,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Require multiple approvals for every transaction',
                        style: TextStyle(
                            color: _textSecondary, fontSize: 13),
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
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _featureTile(Icons.people_alt_outlined, 'Multiple Signers',
                    'Add 2–10 co-signers who must approve transactions'),
                const SizedBox(height: 12),
                _featureTile(Icons.verified_user_outlined,
                    'Custom Threshold',
                    'Choose how many signatures are required (e.g. 2 of 3)'),
                const SizedBox(height: 12),
                _featureTile(Icons.lock_outline, 'Cold-Storage Ready',
                    'Ideal for securing large amounts of crypto'),
                const SizedBox(height: 32),
                _actionButton(
                  label: 'Create MultiSig Wallet',
                  icon: Icons.add_circle_outline,
                  onTap: _showCreateWalletSheet,
                ),
                const SizedBox(height: 12),
                _actionButton(
                  label: 'Import Existing Wallet',
                  icon: Icons.download_outlined,
                  onTap: _showImportSheet,
                  filled: false,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _featureTile(IconData icon, String title, String desc) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _accent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: _accent, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: _textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14)),
                const SizedBox(height: 3),
                Text(desc,
                    style: const TextStyle(
                        color: _textSecondary, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    bool filled = true,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: filled
          ? DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [_accentDark, _accent]),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                      color: _accent.withOpacity(0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4)),
                ],
              ),
              child: TextButton.icon(
                onPressed: onTap,
                icon: Icon(icon, color: Colors.white, size: 20),
                label: Text(label,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
                style: TextButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            )
          : OutlinedButton.icon(
              onPressed: onTap,
              icon: Icon(icon, color: _accentLight, size: 20),
              label: Text(label,
                  style: const TextStyle(
                      color: _accentLight,
                      fontWeight: FontWeight.w600,
                      fontSize: 15)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: _accent, width: 1.5),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
    );
  }

  // ── Wallet view (has wallet) ───────────────────────────────────────────────

  Widget _buildWalletView() {
    return NestedScrollView(
      headerSliverBuilder: (context, _) => [
        SliverAppBar(
          pinned: true,
          expandedHeight: 210,
          backgroundColor: _bg,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: _textPrimary),
            onPressed: () => context.go('/dashboard'),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh, color: _textPrimary),
              onPressed: _loadWalletDetails,
            ),
            IconButton(
              icon: const Icon(Icons.more_vert, color: _textPrimary),
              onPressed: _showSettingsSheet,
            ),
          ],
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1A0533), _bg],
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 60, 24, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                  colors: [_accentDark, _accent]),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.security,
                                color: Colors.white, size: 18),
                          ),
                          const SizedBox(width: 10),
                          const Text('MultiSig Wallet',
                              style: TextStyle(
                                  color: _textSecondary, fontSize: 13)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_balance.toStringAsFixed(4)} ETH',
                        style: const TextStyle(
                          color: _textPrimary,
                          fontSize: 34,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: () {
                          Clipboard.setData(
                              ClipboardData(text: _walletAddress ?? ''));
                          _snack('Address copied', isSuccess: true);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.12)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _formatAddress(_walletAddress ?? ''),
                                style: const TextStyle(
                                  color: _textSecondary,
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Icon(Icons.copy,
                                  color: _textSecondary, size: 13),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _accent.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: _accent.withOpacity(0.3)),
                        ),
                        child: Text(
                          '$_requiredSignatures of ${_owners.length} required',
                          style: const TextStyle(
                              color: _accentLight,
                              fontSize: 11,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(46),
            child: Container(
              decoration: BoxDecoration(
                color: _card,
                border: Border(
                    bottom:
                        BorderSide(color: _border.withOpacity(0.5))),
              ),
              child: TabBar(
                controller: _tabController,
                labelColor: _accentLight,
                unselectedLabelColor: _textSecondary,
                indicatorColor: _accent,
                indicatorWeight: 2.5,
                labelStyle: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13),
                tabs: const [
                  Tab(text: 'Pending'),
                  Tab(text: 'Owners'),
                  Tab(text: 'History'),
                ],
              ),
            ),
          ),
        ),
      ],
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

  // ── Pending tab ───────────────────────────────────────────────────────────

  Widget _buildPendingTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient:
                    const LinearGradient(colors: [_accentDark, _accent]),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                      color: _accent.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 3)),
                ],
              ),
              child: TextButton.icon(
                onPressed: () async {
                  if (await _authenticate()) _showNewTxSheet();
                },
                icon: const Icon(Icons.send, color: Colors.white, size: 18),
                label: const Text('New Transaction',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold)),
                style: TextButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: _pendingTransactions.isEmpty
              ? _emptyState(
                  icon: Icons.hourglass_empty_rounded,
                  message: 'No pending transactions',
                  sub: 'Submit a new transaction to get started',
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: _pendingTransactions.length,
                  itemBuilder: (_, i) =>
                      _pendingTxCard(_pendingTransactions[i]
                          as Map<String, dynamic>),
                ),
        ),
      ],
    );
  }

  Widget _pendingTxCard(Map<String, dynamic> tx) {
    final confirmations =
        (tx['num_confirmations'] ?? tx['confirmations'] ?? 0) as int;
    final progress =
        _requiredSignatures > 0 ? confirmations / _requiredSignatures : 0.0;
    final isReady = tx['can_execute'] == true ||
        confirmations >= _requiredSignatures;
    // Rust returns value_eth as a string; fall back to wei conversion
    final valueEth = tx['value_eth'] != null
        ? double.tryParse(tx['value_eth'].toString()) ?? 0.0
        : ((tx['value'] ?? 0) as num).toDouble() / 1e18;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isReady ? _success.withOpacity(0.4) : _border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _warning.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.pending_actions,
                      color: _warning, size: 18),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TX #${tx['tx_index'] ?? tx['txIndex'] ?? tx['index'] ?? '?'}',
                      style: const TextStyle(
                          color: _textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 14),
                    ),
                    Text(
                      _formatAddress(tx['to'] as String? ?? ''),
                      style: const TextStyle(
                          color: _textSecondary,
                          fontFamily: 'monospace',
                          fontSize: 11),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  '${valueEth.toStringAsFixed(4)} ETH',
                  style: const TextStyle(
                      color: _textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 15),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                      backgroundColor: _border,
                      valueColor: AlwaysStoppedAnimation(
                          isReady ? _success : _accent),
                      minHeight: 6,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '$confirmations/$_requiredSignatures',
                  style: TextStyle(
                      color: isReady ? _success : _textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _txBtn('Approve', Colors.transparent, _success,
                    BorderSide(color: _success, width: 1.2), () async {
                  if (await _authenticate()) {
                    _confirmTransaction(
                        (tx['tx_index'] ?? tx['txIndex'] as num).toInt());
                  }
                }),
                const SizedBox(width: 8),
                _txBtn('Reject', Colors.transparent, _danger,
                    BorderSide(color: _danger, width: 1.2), () async {
                  if (await _authenticate()) {
                    _revokeConfirmation(
                        (tx['tx_index'] ?? tx['txIndex'] as num).toInt());
                  }
                }),
                if (isReady) ...[
                  const SizedBox(width: 8),
                  _txBtn(
                      'Execute',
                      _success.withOpacity(0.15),
                      _success,
                      BorderSide(color: _success, width: 1.2), () async {
                    if (await _authenticate()) {
                      _executeTransaction(
                          (tx['tx_index'] ?? tx['txIndex'] as num).toInt());
                    }
                  }),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _txBtn(String label, Color bg, Color fg, BorderSide border,
      VoidCallback onTap) {
    return Expanded(
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          side: border,
          padding: const EdgeInsets.symmetric(vertical: 8),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
          minimumSize: const Size(0, 36),
        ),
        child: Text(label,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    );
  }

  // ── Owners tab ────────────────────────────────────────────────────────────

  Widget _buildOwnersTab() {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _accent.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _accent.withOpacity(0.25)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline,
                  color: _accentLight, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Requires $_requiredSignatures of ${_owners.length} owners to execute',
                  style: const TextStyle(
                      color: _accentLight, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _owners.isEmpty
              ? _emptyState(
                  icon: Icons.people_outline,
                  message: 'No owners configured',
                  sub: 'Create or import a wallet to see owners',
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: _owners.length,
                  itemBuilder: (_, i) {
                    final owner = _owners[i];
                    final address =
                        owner is String ? owner : owner['address'] ?? '';
                    final name = owner is Map
                        ? (owner['name'] ?? 'Owner ${i + 1}')
                        : 'Owner ${i + 1}';
                    return _ownerCard(i, name, address as String);
                  },
                ),
        ),
      ],
    );
  }

  Widget _ownerCard(int index, String name, String address) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [_accentDark, _accent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text('${index + 1}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        color: _textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14)),
                const SizedBox(height: 3),
                Text(_formatAddress(address),
                    style: const TextStyle(
                        color: _textSecondary,
                        fontFamily: 'monospace',
                        fontSize: 11)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy,
                color: _textSecondary, size: 18),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: address));
              _snack('Address copied', isSuccess: true);
            },
          ),
        ],
      ),
    );
  }

  // ── History tab ───────────────────────────────────────────────────────────

  Widget _buildHistoryTab() {
    if (_historyTransactions.isEmpty) {
      return _emptyState(
        icon: Icons.history,
        message: 'No transaction history',
        sub: 'Completed transactions will appear here',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: _historyTransactions.length,
      itemBuilder: (_, i) {
        final tx = _historyTransactions[i] as Map<String, dynamic>;
        final executed = tx['executed'] == true;
        final valueEth = tx['value_eth'] != null
            ? double.tryParse(tx['value_eth'].toString()) ?? 0.0
            : 0.0;
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: executed ? _success.withOpacity(0.3) : _border),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (executed ? _success : _textSecondary)
                      .withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                    executed ? Icons.check_circle : Icons.pending,
                    color: executed ? _success : _textSecondary,
                    size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TX #${tx['tx_index'] ?? '?'}',
                      style: const TextStyle(
                          color: _textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 13),
                    ),
                    Text(
                      _formatAddress(tx['to'] as String? ?? ''),
                      style: const TextStyle(
                          color: _textSecondary,
                          fontFamily: 'monospace',
                          fontSize: 11),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${valueEth.toStringAsFixed(4)} ETH',
                    style: const TextStyle(
                        color: _textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 13),
                  ),
                  Text(
                    executed ? 'Executed' : 'Pending',
                    style: TextStyle(
                        color: executed ? _success : _warning,
                        fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _emptyState(
      {required IconData icon,
      required String message,
      required String sub}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 56, color: _textSecondary.withOpacity(0.3)),
          const SizedBox(height: 14),
          Text(message,
              style: const TextStyle(
                  color: _textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(sub,
              style: const TextStyle(
                  color: _textSecondary, fontSize: 12)),
        ],
      ),
    );
  }

  String _formatAddress(String address) {
    if (address.length > 20) {
      return '${address.substring(0, 10)}…${address.substring(address.length - 6)}';
    }
    return address;
  }

  void _snack(String msg,
      {bool isSuccess = false, bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor:
          isError ? _danger : isSuccess ? _success : _card,
      behavior: SnackBarBehavior.floating,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ── Bottom sheets ─────────────────────────────────────────────────────────

  void _showCreateWalletSheet() {
    final currentCount = int.tryParse(_cwOwnersCountCtrl.text) ?? 3;
    while (_cwOwnerAddressCtrl.length < currentCount) {
      _cwOwnerAddressCtrl.add(TextEditingController());
    }
    while (_cwOwnerAddressCtrl.length > currentCount) {
      _cwOwnerAddressCtrl.last.dispose();
      _cwOwnerAddressCtrl.removeLast();
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setSheet) => _DarkSheet(
          title: 'Create MultiSig Wallet',
          subtitle:
              'Set up a wallet with trusted co-signers',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                      child: _sheetField(
                          'Total Owners', _cwOwnersCountCtrl,
                          keyboard: TextInputType.number,
                          onChanged: (val) {
                            final n = int.tryParse(val) ?? 3;
                            setSheet(() {
                              while (
                                  _cwOwnerAddressCtrl.length < n) {
                                _cwOwnerAddressCtrl
                                    .add(TextEditingController());
                              }
                              while (
                                  _cwOwnerAddressCtrl.length > n) {
                                _cwOwnerAddressCtrl.last.dispose();
                                _cwOwnerAddressCtrl.removeLast();
                              }
                            });
                          })),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _sheetField(
                          'Required Sigs', _cwRequiredSigsCtrl,
                          keyboard: TextInputType.number)),
                ],
              ),
              const SizedBox(height: 20),
              const Text('Owner Addresses',
                  style: TextStyle(
                      color: _textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
              const SizedBox(height: 10),
              ..._cwOwnerAddressCtrl.asMap().entries.map((e) =>
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _sheetField(
                        'Owner ${e.key + 1}', e.value,
                        hint: '0x…'),
                  )),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [_accentDark, _accent]),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: TextButton(
                    onPressed: () async {
                      final owners = _cwOwnerAddressCtrl
                          .map((c) => c.text.trim())
                          .where((s) => s.isNotEmpty)
                          .toList();
                      final reqSigs =
                          int.tryParse(_cwRequiredSigsCtrl.text.trim()) ??
                              2;
                      if (owners.isEmpty) {
                        _snack('Add at least one owner address',
                            isError: true);
                        return;
                      }
                      for (final addr in owners) {
                        if (!_isValidEthAddress(addr)) {
                          _snack(
                              'Invalid ETH address: ${_formatAddress(addr)}',
                              isError: true);
                          return;
                        }
                      }
                      if (reqSigs < 1 || reqSigs > owners.length) {
                        _snack(
                            'Required sigs must be 1–${owners.length}',
                            isError: true);
                        return;
                      }
                      Navigator.pop(ctx);
                      await _createWallet(owners, reqSigs);
                      final prefs =
                          await SharedPreferences.getInstance();
                      await prefs.remove('_cw_ownersCount');
                      await prefs.remove('_cw_requiredSigs');
                      await prefs.remove('_cw_ownerAddresses');
                    },
                    style: TextButton.styleFrom(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Create Wallet',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showImportSheet() {
    final addrCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _DarkSheet(
        title: 'Import Wallet',
        subtitle:
            'Enter the contract address of an existing MultiSig wallet',
        child: Column(
          children: [
            _sheetField('Contract Address', addrCtrl, hint: '0x…'),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [_accentDark, _accent]),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: TextButton(
                  onPressed: () {
                    final addr = addrCtrl.text.trim();
                    if (!_isValidEthAddress(addr)) {
                      _snack('Invalid ETH address', isError: true);
                      return;
                    }
                    Navigator.pop(ctx);
                    _importWallet(addr);
                  },
                  style: TextButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Import',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showNewTxSheet() {
    final toCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _DarkSheet(
        title: 'New Transaction',
        subtitle: 'Submit a transaction for approval by co-signers',
        child: Column(
          children: [
            _sheetField('Recipient Address', toCtrl, hint: '0x…'),
            const SizedBox(height: 12),
            _sheetField('Amount (ETH)', amountCtrl,
                keyboard: const TextInputType.numberWithOptions(
                    decimal: true)),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [_accentDark, _accent]),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: TextButton(
                  onPressed: () {
                    final to = toCtrl.text.trim();
                    final amount = amountCtrl.text.trim();
                    if (!_isValidEthAddress(to)) {
                      _snack('Invalid recipient address',
                          isError: true);
                      return;
                    }
                    final amtVal = double.tryParse(amount);
                    if (amtVal == null || amtVal <= 0) {
                      _snack('Enter a valid amount', isError: true);
                      return;
                    }
                    Navigator.pop(ctx);
                    _submitTransaction(to, amount);
                  },
                  style: TextButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Submit Transaction',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSettingsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: _card,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: _border,
                  borderRadius: BorderRadius.circular(2)),
            ),
            _settingsTile(Icons.person_add_outlined, 'Add Owner',
                _textPrimary, () => Navigator.pop(ctx)),
            _settingsTile(Icons.tune, 'Change Threshold',
                _textPrimary, () => Navigator.pop(ctx)),
            const Divider(color: _border, height: 1),
            _settingsTile(Icons.logout, 'Disconnect Wallet', _danger, () {
              Navigator.pop(ctx);
              setState(() {
                _hasWallet = false;
                _walletAddress = null;
                _owners = [];
                _pendingTransactions = [];
              });
            }),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _settingsTile(IconData icon, String label, Color color,
      VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: color, size: 20),
      title: Text(label,
          style: TextStyle(color: color, fontSize: 14)),
      onTap: onTap,
    );
  }

  Widget _sheetField(
    String label,
    TextEditingController controller, {
    String? hint,
    TextInputType keyboard = TextInputType.text,
    void Function(String)? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: _textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboard,
          onChanged: onChanged,
          style: const TextStyle(color: _textPrimary, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
                color: _textSecondary, fontSize: 13),
            filled: true,
            fillColor: _cardAlt,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: _accent, width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }

  // ── API methods ───────────────────────────────────────────────────────────

  Future<void> _createWallet(List<String> owners, int required) async {
    setState(() => _loading = true);
    try {
      final response = await _dio.post(
        '${ApiConfig.baseUrl}/api/multisig/deploy',
        data: {'owners': owners, 'required': required},
        options: Options(validateStatus: (s) => s != null && s < 500),
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode == 200 &&
          response.data['address'] != null) {
        final addr = response.data['address'].toString();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('multisig_wallet_address', addr);
        await prefs.setStringList('multisig_owners', owners);
        await prefs.setInt('multisig_required', required);
        setState(() {
          _walletAddress = addr;
          _hasWallet = true;
          _owners = owners;
          _requiredSignatures = required;
        });
        await _loadWalletDetails();
        _snack('MultiSig wallet deployed on-chain!', isSuccess: true);
      } else {
        final err = response.data?['error'] ?? 'Deploy failed';
        _snack(err.toString(), isError: true);
      }
    } on DioException catch (e) {
      final msg = e.response?.data?['error'] ?? e.message ?? 'Network error';
      _snack(msg.toString(), isError: true);
    } catch (e) {
      _snack('Failed to create wallet: $e', isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _importWallet(String address) async {
    setState(() => _loading = true);
    try {
      // Call Rust import to read on-chain state
      final response = await _dio.post(
        '${ApiConfig.baseUrl}/api/multisig/import',
        data: {'contractAddress': address},
        options: Options(validateStatus: (s) => s != null && s < 500),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 && response.data['address'] != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('multisig_wallet_address', address);
        final importedOwners = (response.data['owners'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [];
        await prefs.setStringList('multisig_owners', importedOwners);
        await prefs.setInt('multisig_required',
            (response.data['required'] ?? 2) as int);
      }
    } catch (_) {
      // Import failed — still show wallet view, will load via owners endpoint
    } finally {
      setState(() {
        _walletAddress = address;
        _hasWallet = true;
        _loading = false;
      });
      await _loadWalletDetails();
    }
  }

  Future<void> _submitTransaction(String to, String amount) async {
    try {
      final amountWei =
          (double.parse(amount) * 1e18).toStringAsFixed(0);
      await _dio.post(
          '${ApiConfig.baseUrl}/api/multisig/submit',
          data: {
            'contractAddress': _walletAddress,
            'to': to,
            'value': amountWei,
            'data': '0x',
          });
      await _loadPendingTransactions();
      _snack('Transaction submitted', isSuccess: true);
    } catch (e) {
      _snack('Submit failed: $e', isError: true);
    }
  }

  Future<void> _confirmTransaction(int txIndex) async {
    try {
      await _dio.post(
          '${ApiConfig.baseUrl}/api/multisig/confirm',
          data: {
            'contractAddress': _walletAddress,
            'txIndex': txIndex
          });
      await _loadPendingTransactions();
      _snack('Transaction approved', isSuccess: true);
    } catch (e) {
      _snack('Error: $e', isError: true);
    }
  }

  Future<void> _revokeConfirmation(int txIndex) async {
    try {
      await _dio.post(
          '${ApiConfig.baseUrl}/api/multisig/revoke',
          data: {
            'contractAddress': _walletAddress,
            'txIndex': txIndex
          });
      await _loadPendingTransactions();
      _snack('Confirmation revoked');
    } catch (e) {
      _snack('Error: $e', isError: true);
    }
  }

  Future<void> _executeTransaction(int txIndex) async {
    try {
      await _dio.post(
          '${ApiConfig.baseUrl}/api/multisig/execute',
          data: {
            'contractAddress': _walletAddress,
            'txIndex': txIndex
          });
      await _loadPendingTransactions();
      await _loadWalletDetails();
      _snack('Transaction executed', isSuccess: true);
    } catch (e) {
      _snack('Execute failed: $e', isError: true);
    }
  }
}

// ── PIN Entry Sheet ───────────────────────────────────────────────────────────
// Replaces AlertDialog to avoid IntrinsicWidth layout crash (min 280, max 350).

class _PinEntrySheet extends StatefulWidget {
  const _PinEntrySheet({
    required this.pinAuthService,
    required this.accent,
    required this.onResult,
  });

  final PinAuthService pinAuthService;
  final Color accent;
  final void Function(bool valid) onResult;

  @override
  State<_PinEntrySheet> createState() => _PinEntrySheetState();
}

class _PinEntrySheetState extends State<_PinEntrySheet> {
  String _pin = '';
  bool _checking = false;
  bool _error = false;

  static const Color _bg = Color(0xFF1A2332);
  static const Color _cardAlt2 = Color(0xFF1E2A3A);
  static const Color _border = Color(0xFF2D3748);
  static const Color _textPrimary = Colors.white;
  static const Color _textSecondary = Color(0xFF94A3B8);

  void _append(String digit) async {
    if (_checking || _pin.length >= 6) return;
    HapticFeedback.lightImpact();
    setState(() {
      _pin += digit;
      _error = false;
    });
    if (_pin.length == 6) {
      setState(() => _checking = true);
      final valid = await widget.pinAuthService.verifyPin(_pin);
      if (!valid && mounted) {
        setState(() {
          _pin = '';
          _checking = false;
          _error = true;
        });
      } else if (mounted) {
        widget.onResult(valid);
      }
    }
  }

  void _backspace() {
    if (_pin.isNotEmpty) {
      HapticFeedback.lightImpact();
      setState(() => _pin = _pin.substring(0, _pin.length - 1));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: _border,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 24),
            const Text('Enter PIN',
                style: TextStyle(
                    color: _textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(
              _error ? 'Incorrect PIN. Try again.' : 'Enter your 6-digit PIN',
              style: TextStyle(
                  color: _error
                      ? const Color(0xFFEF4444)
                      : _textSecondary,
                  fontSize: 13),
            ),
            const SizedBox(height: 24),
            // PIN dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(6, (i) {
                final filled = i < _pin.length;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled ? widget.accent : Colors.transparent,
                    border: Border.all(
                      color: _error
                          ? const Color(0xFFEF4444)
                          : filled
                              ? widget.accent
                              : _border,
                      width: 2,
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 28),
            // Number pad – no IntrinsicWidth, pure Row/Column
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                children: [
                  for (final row in [
                    ['1', '2', '3'],
                    ['4', '5', '6'],
                    ['7', '8', '9'],
                    ['', '0', '⌫'],
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: row.map((d) {
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5),
                              child: d.isEmpty
                                  ? const SizedBox(height: 52)
                                  : _padBtn(
                                      onTap: d == '⌫'
                                          ? _backspace
                                          : () => _append(d),
                                      child: d == '⌫'
                                          ? const Icon(
                                              Icons.backspace_outlined,
                                              color: _textSecondary,
                                              size: 20)
                                          : Text(d,
                                              style: const TextStyle(
                                                  color: _textPrimary,
                                                  fontSize: 22,
                                                  fontWeight:
                                                      FontWeight.w500)),
                                    ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _padBtn({required Widget child, required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _checking ? null : onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: _cardAlt2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _border),
          ),
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );
  }
}

// ── Dark-themed bottom sheet container ────────────────────────────────────────

class _DarkSheet extends StatelessWidget {
  const _DarkSheet({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  static const Color _bg = Color(0xFF1A2332);
  static const Color _border = Color(0xFF2D3748);
  static const Color _textPrimary = Colors.white;
  static const Color _textSecondary = Color(0xFF94A3B8);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        decoration: const BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: _border,
                  borderRadius: BorderRadius.circular(2)),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: _textPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: const TextStyle(
                            color: _textSecondary, fontSize: 13)),
                    const SizedBox(height: 20),
                    child,
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
