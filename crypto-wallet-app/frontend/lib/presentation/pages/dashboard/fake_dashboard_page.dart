import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';

import '../../../core/constants/app_constants.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../services/price_service.dart';
import '../../../core/providers/fake_wallet_provider.dart';
import '../../../services/fake_wallet_service.dart';

/// Fake dashboard page shown when duress PIN is detected
/// Same design as real wallet but with $0 balance and fake coins
class FakeDashboardPage extends ConsumerStatefulWidget {
  const FakeDashboardPage({super.key});

  @override
  ConsumerState<FakeDashboardPage> createState() => _FakeDashboardPageState();
}

class _FakeDashboardPageState extends ConsumerState<FakeDashboardPage> {
  final PriceService _priceService = PriceService();
  final FakeWalletService _fakeWalletService = FakeWalletService();

  Map<String, Map<String, dynamic>> _priceData = {};
  bool _isLoading = true;
  bool _refreshing = false;

  // Coin data with colors - matches real dashboard
  final List<Map<String, dynamic>> _coins = [
    {'symbol': 'BTC', 'name': 'Bitcoin', 'color': Color(0xFFF7931A)},
    {'symbol': 'ETH', 'name': 'Ethereum', 'color': Color(0xFF627EEA)},
    {'symbol': 'BNB', 'name': 'BNB', 'color': Color(0xFFF3BA2F)},
    {'symbol': 'SOL', 'name': 'Solana', 'color': Color(0xFF00FFA3)},
    {'symbol': 'TRX', 'name': 'TRON', 'color': Color(0xFFEF0027)},
    {'symbol': 'LTC', 'name': 'Litecoin', 'color': Color(0xFFBFBBBB)},
    {'symbol': 'XRP', 'name': 'XRP', 'color': Color(0xFF00AAE4)},
    {'symbol': 'DOGE', 'name': 'Dogecoin', 'color': Color(0xFFC2A633)},
  ];

  @override
  void initState() {
    super.initState();
    _loadPrices();
  }

  Future<void> _loadPrices() async {
    if (mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final symbols = _coins.map((c) => c['symbol'] as String).toList();
      
      final prices = await _priceService.getPrices(symbols).timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          print('⏱️ Price fetch timeout - using cached/fallback');
          return <String, Map<String, dynamic>>{};
        },
      );

      // Build fallback prices
      final fallbackPrices = {
        'BTC': 96000.0, 'ETH': 3400.0, 'BNB': 680.0, 'SOL': 200.0,
        'XRP': 2.50, 'DOGE': 0.35, 'LTC': 120.0, 'TRX': 0.25,
      };

      if (mounted) {
        setState(() {
          _priceData = prices.isNotEmpty ? prices : _buildFallbackPrices(fallbackPrices);
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Price load error: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Map<String, Map<String, dynamic>> _buildFallbackPrices(Map<String, double> prices) {
    return prices.map((symbol, price) => MapEntry(symbol, {
      'price': price,
      'change24h': 0.0,
      'source': 'Fallback',
    }));
  }

  Future<void> _refreshData() async {
    HapticFeedback.mediumImpact();
    setState(() => _refreshing = true);
    await _loadPrices();
    setState(() => _refreshing = false);
  }

  String _formatPrice(double price) {
    if (price >= 1000) {
      return '\$${price.toStringAsFixed(2).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}';
    } else if (price >= 1) {
      return '\$${price.toStringAsFixed(2)}';
    }
    return '\$${price.toStringAsFixed(4)}';
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeProvider);
    final isDark = themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system &&
            MediaQuery.of(context).platformBrightness == Brightness.dark);

    final bgColor = isDark ? const Color(0xFF0D1421) : const Color(0xFFF8FAFC);
    final cardColor = isDark ? const Color(0xFF1A1F2E) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final subtextColor = isDark ? Colors.white70 : const Color(0xFF64748B);

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            _buildHeader(cardColor, textColor),

            // Scrollable content
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refreshData,
                color: const Color(0xFF8B5CF6),
                backgroundColor: cardColor,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    // Total Balance Card
                    _buildBalanceCard(cardColor, textColor, subtextColor),

                    // Action Buttons
                    _buildActionButtons(cardColor, textColor),

                    // Coin List
                    _buildCoinList(cardColor, textColor, subtextColor),

                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(Color cardColor, Color textColor) {
    return Container(
      color: Colors.transparent,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _buildIconButton(Icons.search_rounded, () {}, cardColor, textColor),
          const SizedBox(width: 12),
          _buildIconButton(Icons.notifications_rounded, () {}, cardColor, textColor),
          const SizedBox(width: 12),
          _buildIconButton(Icons.history_rounded, () {}, cardColor, textColor),
        ],
      ),
    );
  }

  Widget _buildIconButton(IconData icon, VoidCallback onTap, Color cardColor, Color textColor) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, color: textColor.withOpacity(0.7), size: 20),
      ),
    );
  }

  Widget _buildBalanceCard(Color cardColor, Color textColor, Color subtextColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF8B5CF6).withOpacity(0.9),
              const Color(0xFF6366F1).withOpacity(0.7),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF8B5CF6).withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Total Balance',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '\$0.00',
              style: TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(Color cardColor, Color textColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: _buildActionButton(
              'Send',
              Icons.send_rounded,
              () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('No funds to send')),
              ),
              cardColor,
              textColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildActionButton(
              'Receive',
              Icons.call_received_rounded,
              () {},
              cardColor,
              textColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    String label,
    IconData icon,
    VoidCallback onTap,
    Color cardColor,
    Color textColor,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: textColor.withOpacity(0.7), size: 24),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: textColor,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoinList(Color cardColor, Color textColor, Color subtextColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 0, bottom: 12),
            child: Text(
              'Cryptocurrencies',
              style: TextStyle(
                color: textColor,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (_isLoading)
            SizedBox(
              height: 200,
              child: Center(
                child: CircularProgressIndicator(
                  color: const Color(0xFF8B5CF6),
                ),
              ),
            )
          else
            ...List.generate(_coins.length, (index) {
              final coin = _coins[index];
              final symbol = coin['symbol'] as String;
              final priceInfo = _priceData[symbol];
              final price = (priceInfo?['price'] as double?) ?? 0.0;
              final change = (priceInfo?['change24h'] as double?) ?? 0.0;

              return _buildCoinTile(
                coin,
                price,
                change,
                cardColor,
                textColor,
                subtextColor,
              );
            }),
        ],
      ),
    );
  }

  Widget _buildCoinTile(
    Map<String, dynamic> coin,
    double price,
    double change,
    Color cardColor,
    Color textColor,
    Color subtextColor,
  ) {
    final symbol = coin['symbol'] as String;
    final name = coin['name'] as String;
    final color = coin['color'] as Color;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Coin icon
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                symbol[0],
                style: TextStyle(
                  color: color,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Coin name
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  symbol,
                  style: TextStyle(
                    color: subtextColor,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          // Balance and price
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '0.00 $symbol',
                style: TextStyle(
                  color: textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                _formatPrice(price),
                style: TextStyle(
                  color: subtextColor,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
