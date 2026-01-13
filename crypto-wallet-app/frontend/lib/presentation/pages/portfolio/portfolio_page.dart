import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/wallet_service.dart';
import '../../../services/price_service.dart';

class PortfolioPage extends ConsumerStatefulWidget {
  const PortfolioPage({super.key});

  @override
  ConsumerState<PortfolioPage> createState() => _PortfolioPageState();
}

class _PortfolioPageState extends ConsumerState<PortfolioPage> {
  final WalletService _walletService = WalletService();
  final PriceService _priceService = PriceService();
  
  Map<String, double> _balances = {};
  Map<String, Map<String, dynamic>> _priceData = {};
  bool _isLoading = true;
  double _totalValue = 0.0;

  @override
  void initState() {
    super.initState();
    _loadPortfolio();
  }

  Future<void> _loadPortfolio() async {
    setState(() => _isLoading = true);
    
    try {
      // Load wallet balances
      final balances = await _walletService.getBalances();
      
      // Load prices for all coins
      final symbols = ['BTC', 'ETH', 'BNB', 'SOL', 'XRP', 'DOGE', 'LTC'];
      final prices = await _priceService.getPrices(symbols);
      
      // Calculate total value
      double total = 0.0;
      balances.forEach((symbol, balance) {
        if (balance > 0 && prices[symbol] != null) {
          total += balance * (prices[symbol]!['price'] as double);
        }
      });
      
      setState(() {
        _balances = balances;
        _priceData = prices;
        _totalValue = total;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  String _formatCurrency(double amount) {
    final formatter = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    String formattedAmount = amount.toStringAsFixed(2).replaceAllMapped(
      formatter,
      (Match m) => '${m[1]},',
    );
    return '\$$formattedAmount';
  }

  @override
  Widget build(BuildContext context) {
    // Filter balances to only show assets with balance > 0
    final activeAssets = _balances.entries
        .where((entry) => entry.value > 0)
        .toList();

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadPortfolio,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : activeAssets.isEmpty
                  ? _buildEmptyState()
                  : _buildPortfolioContent(activeAssets),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.defaultPadding),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                size: 80,
                color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
              ),
              const SizedBox(height: 24),
              Text(
                'No Assets Yet',
                style: AppTheme.headlineSmall.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Start by adding funds to your wallet.\nYour crypto assets will appear here.',
                style: AppTheme.bodyMedium.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: () => context.go('/dashboard'),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Go to Dashboard'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPortfolioContent(List<MapEntry<String, double>> activeAssets) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppConstants.defaultPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          
          // Total Portfolio Value Header
          Text(
            'Total Portfolio Value',
            style: AppTheme.bodyLarge.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _formatCurrency(_totalValue),
            style: AppTheme.headlineLarge.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 32),

          // Assets List
          Text(
            'Your Assets',
            style: AppTheme.titleLarge.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),

          // Asset Cards
          ...activeAssets.map((entry) {
            final symbol = entry.key;
            final balance = entry.value;
            final priceInfo = _priceData[symbol];
            
            if (priceInfo == null) return const SizedBox.shrink();
            
            final price = priceInfo['price'] as double;
            final change24h = priceInfo['change24h'] as double;
            final value = balance * price;
            
            return _buildAssetCard(
              context,
              symbol: symbol,
              balance: balance,
              price: price,
              change24h: change24h,
              value: value,
            );
          }),
        ],
      ),
    );
  }

  Widget _buildAssetCard(
    BuildContext context, {
    required String symbol,
    required double balance,
    required double price,
    required double change24h,
    required double value,
  }) {
    final isPositive = change24h >= 0;
    
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: () {
          // TODO: Navigate to asset details
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Coin Icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    symbol,
                    style: AppTheme.titleMedium.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              
              // Coin Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _getCoinName(symbol),
                      style: AppTheme.titleMedium.copyWith(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${balance.toStringAsFixed(8)} $symbol',
                      style: AppTheme.bodySmall.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
              
              // Value and Change
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatCurrency(value),
                    style: AppTheme.titleMedium.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isPositive
                          ? Colors.green.withOpacity(0.1)
                          : Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isPositive ? Icons.arrow_upward : Icons.arrow_downward,
                          size: 12,
                          color: isPositive ? Colors.green : Colors.red,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${change24h.abs().toStringAsFixed(2)}%',
                          style: AppTheme.bodySmall.copyWith(
                            color: isPositive ? Colors.green : Colors.red,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getCoinName(String symbol) {
    const Map<String, String> names = {
      'BTC': 'Bitcoin',
      'ETH': 'Ethereum',
      'BNB': 'Binance Coin',
      'SOL': 'Solana',
      'XRP': 'Ripple',
      'DOGE': 'Dogecoin',
      'LTC': 'Litecoin',
    };
    return names[symbol] ?? symbol;
  }
}