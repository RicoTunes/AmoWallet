import 'package:flutter/material.dart';
import '../../../services/push_notification_service.dart';

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() => _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  final PushNotificationService _pushService = PushNotificationService();
  
  bool _priceAlertsEnabled = true;
  bool _transactionAlertsEnabled = true;
  double _significantPriceChange = 5.0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    await _pushService.initialize();
    setState(() {
      _priceAlertsEnabled = _pushService.priceAlertsEnabled;
      _transactionAlertsEnabled = _pushService.transactionAlertsEnabled;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D1117) : Colors.grey[50],
      appBar: AppBar(
        title: const Text('Notification Settings'),
        backgroundColor: isDark ? const Color(0xFF161B22) : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Transaction Alerts Section
                  _buildSectionHeader('Transaction Alerts', Icons.receipt_long),
                  const SizedBox(height: 12),
                  _buildSettingsCard([
                    _buildSwitchTile(
                      title: 'Transaction Alerts',
                      subtitle: 'Receive notifications for incoming/outgoing transactions',
                      icon: Icons.swap_horiz,
                      value: _transactionAlertsEnabled,
                      onChanged: (value) async {
                        setState(() => _transactionAlertsEnabled = value);
                        await _pushService.saveSettings(transactionAlertsEnabled: value);
                      },
                      isDark: isDark,
                    ),
                  ], isDark),
                  
                  const SizedBox(height: 24),
                  
                  // Price Alerts Section
                  _buildSectionHeader('Price Alerts', Icons.trending_up),
                  const SizedBox(height: 12),
                  _buildSettingsCard([
                    _buildSwitchTile(
                      title: 'Price Alerts',
                      subtitle: 'Get notified when prices hit your targets',
                      icon: Icons.notifications_active,
                      value: _priceAlertsEnabled,
                      onChanged: (value) async {
                        setState(() => _priceAlertsEnabled = value);
                        await _pushService.saveSettings(priceAlertsEnabled: value);
                      },
                      isDark: isDark,
                    ),
                    const Divider(height: 1),
                    _buildSliderTile(
                      title: 'Significant Price Change',
                      subtitle: 'Alert when 24h change exceeds ${_significantPriceChange.toInt()}%',
                      icon: Icons.percent,
                      value: _significantPriceChange,
                      min: 1,
                      max: 20,
                      divisions: 19,
                      onChanged: _priceAlertsEnabled
                          ? (value) async {
                              setState(() => _significantPriceChange = value);
                              await _pushService.saveSettings(significantPriceChange: value);
                            }
                          : null,
                      isDark: isDark,
                    ),
                  ], isDark),
                  
                  const SizedBox(height: 24),
                  
                  // Price Alert List
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildSectionHeader('Your Price Alerts', Icons.price_change),
                      IconButton(
                        onPressed: () => _showAddAlertDialog(),
                        icon: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.add, color: Colors.blue, size: 20),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildPriceAlertsList(isDark),
                  
                  const SizedBox(height: 24),
                  
                  // Info Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, color: Colors.blue),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Price alerts check every minute using CoinGecko API. Custom alerts trigger once and are automatically disabled.',
                            style: TextStyle(
                              color: isDark ? Colors.white70 : Colors.black87,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.blue),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsCard(List<Widget> children, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2530) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required Function(bool) onChanged,
    required bool isDark,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.blue.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: Colors.blue, size: 20),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white : Colors.black87,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 12,
          color: isDark ? Colors.white54 : Colors.black54,
        ),
      ),
      trailing: Switch.adaptive(
        value: value,
        onChanged: onChanged,
        activeColor: Colors.blue,
      ),
    );
  }

  Widget _buildSliderTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required Function(double)? onChanged,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: Colors.blue, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white54 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: '${value.toInt()}%',
            onChanged: onChanged,
            activeColor: Colors.blue,
            inactiveColor: isDark ? Colors.white24 : Colors.grey[300],
          ),
        ],
      ),
    );
  }

  Widget _buildPriceAlertsList(bool isDark) {
    final alerts = _pushService.priceAlerts;
    
    if (alerts.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E2530) : Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Column(
            children: [
              Icon(
                Icons.notifications_none,
                size: 48,
                color: isDark ? Colors.white38 : Colors.grey[400],
              ),
              const SizedBox(height: 12),
              Text(
                'No price alerts set',
                style: TextStyle(
                  color: isDark ? Colors.white54 : Colors.grey[600],
                ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => _showAddAlertDialog(),
                icon: const Icon(Icons.add),
                label: const Text('Add your first alert'),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2530) : Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: alerts.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final alert = alerts[index];
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: alert.isAbove ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
              child: Icon(
                alert.isAbove ? Icons.arrow_upward : Icons.arrow_downward,
                color: alert.isAbove ? Colors.green : Colors.red,
                size: 20,
              ),
            ),
            title: Text(
              '${alert.coinSymbol.split('-').first} ${alert.isAbove ? "Above" : "Below"} \$${alert.targetPrice.toStringAsFixed(2)}',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
                decoration: alert.isEnabled ? null : TextDecoration.lineThrough,
              ),
            ),
            subtitle: Text(
              alert.isEnabled ? 'Active' : 'Triggered',
              style: TextStyle(
                fontSize: 12,
                color: alert.isEnabled ? Colors.green : Colors.grey,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch.adaptive(
                  value: alert.isEnabled,
                  onChanged: (value) async {
                    await _pushService.togglePriceAlert(alert.id, value);
                    setState(() {});
                  },
                  activeColor: Colors.blue,
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline, color: Colors.red[400]),
                  onPressed: () async {
                    await _pushService.removePriceAlert(alert.id);
                    setState(() {});
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showAddAlertDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    String selectedCoin = 'BTC';
    double targetPrice = 0;
    bool isAbove = true;
    final priceController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E2530) : Colors.white,
          title: Text(
            'Add Price Alert',
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Coin selector
              DropdownButtonFormField<String>(
                value: selectedCoin,
                dropdownColor: isDark ? const Color(0xFF2A3340) : Colors.white,
                decoration: InputDecoration(
                  labelText: 'Coin',
                  labelStyle: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF2A3340) : Colors.grey[100],
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                items: ['BTC', 'ETH', 'BNB', 'SOL', 'XRP', 'TRX', 'LTC', 'DOGE']
                    .map((c) => DropdownMenuItem(
                          value: c,
                          child: Text(c, style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                        ))
                    .toList(),
                onChanged: (value) => setDialogState(() => selectedCoin = value!),
              ),
              const SizedBox(height: 16),
              
              // Price input
              TextField(
                controller: priceController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                decoration: InputDecoration(
                  labelText: 'Target Price (USD)',
                  labelStyle: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
                  prefixText: '\$ ',
                  prefixStyle: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF2A3340) : Colors.grey[100],
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onChanged: (value) {
                  targetPrice = double.tryParse(value) ?? 0;
                },
              ),
              const SizedBox(height: 16),
              
              // Above/Below selector
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setDialogState(() => isAbove = true),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isAbove ? Colors.green.withOpacity(0.2) : (isDark ? const Color(0xFF2A3340) : Colors.grey[100]),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isAbove ? Colors.green : Colors.transparent,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.arrow_upward, color: isAbove ? Colors.green : Colors.grey, size: 20),
                            const SizedBox(width: 8),
                            Text('Above', style: TextStyle(color: isAbove ? Colors.green : Colors.grey)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setDialogState(() => isAbove = false),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: !isAbove ? Colors.red.withOpacity(0.2) : (isDark ? const Color(0xFF2A3340) : Colors.grey[100]),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: !isAbove ? Colors.red : Colors.transparent,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.arrow_downward, color: !isAbove ? Colors.red : Colors.grey, size: 20),
                            const SizedBox(width: 8),
                            Text('Below', style: TextStyle(color: !isAbove ? Colors.red : Colors.grey)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (targetPrice > 0) {
                  await _pushService.addPriceAlert(
                    coinSymbol: selectedCoin,
                    targetPrice: targetPrice,
                    isAbove: isAbove,
                  );
                  Navigator.pop(context);
                  setState(() {});
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              child: const Text('Add Alert'),
            ),
          ],
        ),
      ),
    );
  }
}
