import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../../core/config/api_config.dart';
import '../../../services/biometric_auth_service.dart';

class SpendingLimitsPage extends ConsumerStatefulWidget {
  final String? userAddress;

  const SpendingLimitsPage({super.key, this.userAddress});

  @override
  ConsumerState<SpendingLimitsPage> createState() => _SpendingLimitsPageState();
}

class _SpendingLimitsPageState extends ConsumerState<SpendingLimitsPage> {
  final _dio = Dio();
  bool _isLoading = false;
  Map<String, dynamic>? _statistics;
  Map<String, dynamic>? _limits;

  // Form controllers
  final _dailyLimitController = TextEditingController();
  final _weeklyLimitController = TextEditingController();
  final _monthlyLimitController = TextEditingController();
  final _perTxLimitController = TextEditingController();
  final _elevatedAuthController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadStatistics();
  }

  @override
  void dispose() {
    _dailyLimitController.dispose();
    _weeklyLimitController.dispose();
    _monthlyLimitController.dispose();
    _perTxLimitController.dispose();
    _elevatedAuthController.dispose();
    super.dispose();
  }

  Future<void> _loadStatistics() async {
    if (widget.userAddress == null) return;

    setState(() => _isLoading = true);

    try {
      final response = await _dio.get(
        '${ApiConfig.baseUrl}/api/spending/stats/${widget.userAddress}',
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        setState(() {
          _statistics = response.data['data'];
          _limits = _statistics?['limits'];
          
          // Populate form fields with current limits
          if (_limits != null) {
            _dailyLimitController.text = _limits!['daily'].toString();
            _weeklyLimitController.text = _limits!['weekly'].toString();
            _monthlyLimitController.text = _limits!['monthly'].toString();
            _perTxLimitController.text = _limits!['per_transaction'].toString();
            _elevatedAuthController.text = _limits!['elevated_auth_threshold'].toString();
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading statistics: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _updateLimits() async {
    if (widget.userAddress == null) return;

    // Validate inputs
    final daily = double.tryParse(_dailyLimitController.text);
    final weekly = double.tryParse(_weeklyLimitController.text);
    final monthly = double.tryParse(_monthlyLimitController.text);
    final perTx = double.tryParse(_perTxLimitController.text);
    final elevated = double.tryParse(_elevatedAuthController.text);

    if (daily == null || weekly == null || monthly == null || perTx == null || elevated == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter valid numbers for all limits')),
      );
      return;
    }

    // Validate logic
    if (daily > weekly || weekly > monthly) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Daily ≤ Weekly ≤ Monthly limits required')),
      );
      return;
    }

    // Require biometric auth
    final authService = BiometricAuthService();
    final authenticated = await authService.authenticate(
      reason: 'Authenticate to update spending limits',
    );

    if (!authenticated) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Authentication required')),
        );
      }
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await _dio.post(
        '${ApiConfig.baseUrl}/api/spending/limits',
        data: {
          'address': widget.userAddress,
          'limits': {
            'daily_limit_usd': daily,
            'weekly_limit_usd': weekly,
            'monthly_limit_usd': monthly,
            'per_transaction_limit_usd': perTx,
            'elevated_auth_threshold_usd': elevated,
            'cooling_off_period_hours': 24,
          },
        },
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Spending limits updated successfully')),
          );
          _loadStatistics(); // Reload stats
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating limits: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Spending Limits'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Current statistics card
                  if (_statistics != null) ...[
                    _buildStatisticsCard(theme),
                    const SizedBox(height: 24),
                  ],

                  // Configure limits section
                  Text(
                    'Configure Spending Limits',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Set transaction velocity limits to protect your wallet',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Daily limit
                  _buildLimitField(
                    controller: _dailyLimitController,
                    label: 'Daily Limit (USD)',
                    icon: Icons.calendar_today,
                    hint: '5000',
                  ),
                  const SizedBox(height: 12),

                  // Weekly limit
                  _buildLimitField(
                    controller: _weeklyLimitController,
                    label: 'Weekly Limit (USD)',
                    icon: Icons.calendar_view_week,
                    hint: '20000',
                  ),
                  const SizedBox(height: 12),

                  // Monthly limit
                  _buildLimitField(
                    controller: _monthlyLimitController,
                    label: 'Monthly Limit (USD)',
                    icon: Icons.calendar_month,
                    hint: '50000',
                  ),
                  const SizedBox(height: 12),

                  // Per-transaction limit
                  _buildLimitField(
                    controller: _perTxLimitController,
                    label: 'Per-Transaction Limit (USD)',
                    icon: Icons.attach_money,
                    hint: '10000',
                  ),
                  const SizedBox(height: 12),

                  // Elevated auth threshold
                  _buildLimitField(
                    controller: _elevatedAuthController,
                    label: 'Elevated Auth Threshold (USD)',
                    icon: Icons.security,
                    hint: '5000',
                  ),
                  const SizedBox(height: 24),

                  // Info card
                  Card(
                    color: Colors.blue.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.info_outline, color: Colors.blue.shade700),
                              const SizedBox(width: 8),
                              Text(
                                'Security Features',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildInfoRow(
                            '🔒',
                            'Transactions exceeding limits will be blocked',
                          ),
                          _buildInfoRow(
                            '🔐',
                            'Elevated auth required for amounts above threshold',
                          ),
                          _buildInfoRow(
                            '⏱️',
                            '24-hour rolling window for velocity tracking',
                          ),
                          _buildInfoRow(
                            '🛡️',
                            'All limits enforced by Rust backend',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Update button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _updateLimits,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Update Spending Limits',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildStatisticsCard(ThemeData theme) {
    final spent = _statistics!['spent'];
    final remaining = _statistics!['remaining'];
    final percentages = _statistics!['percentages'];

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current Usage',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // Daily
            _buildUsageBar(
              'Daily',
              spent['daily'],
              remaining['daily'],
              percentages['daily'],
              Colors.green,
            ),
            const SizedBox(height: 12),

            // Weekly
            _buildUsageBar(
              'Weekly',
              spent['weekly'],
              remaining['weekly'],
              percentages['weekly'],
              Colors.blue,
            ),
            const SizedBox(height: 12),

            // Monthly
            _buildUsageBar(
              'Monthly',
              spent['monthly'],
              remaining['monthly'],
              percentages['monthly'],
              Colors.purple,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUsageBar(
    String label,
    double spent,
    double remaining,
    double percentage,
    Color color,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              '\$${spent.toStringAsFixed(2)} / \$${(spent + remaining).toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: percentage / 100,
          backgroundColor: Colors.grey.shade200,
          valueColor: AlwaysStoppedAnimation<Color>(color),
          minHeight: 8,
        ),
        const SizedBox(height: 4),
        Text(
          '${percentage.toStringAsFixed(1)}% used',
          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
        ),
      ],
    );
  }

  Widget _buildLimitField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required String hint,
  }) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String emoji, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
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
}
