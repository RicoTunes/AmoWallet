import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/wallet_service.dart';
import '../../../services/price_conversion_service.dart';

class CoinListPage extends ConsumerStatefulWidget {
  const CoinListPage({super.key});

  @override
  ConsumerState<CoinListPage> createState() => _CoinListPageState();
}

class _CoinListPageState extends ConsumerState<CoinListPage> {
  final WalletService _walletService = WalletService();
  final PriceConversionService _priceService = PriceConversionService();
  
  late Map<String, double> _balances = {};
  late Map<String, double> _usdValues = {};
  bool _loading = true;
  double _totalUSDValue = 0.0;

  @override
  void initState() {
    super.initState();
    _loadCoinData();
  }

  Future<void> _loadCoinData() async {
    setState(() => _loading = true);
    try {
      // Get balances
      final balances = await _walletService.getBalances();
      
      // Get USD prices for all coins
      final coins = balances.keys.toList();
      final priceMap = await _priceService.getUSDPrices(coins);
      
      // Calculate USD values
      double totalUSD = 0.0;
      final usdValues = <String, double>{};
      
      for (final coin in coins) {
        final balance = balances[coin] ?? 0.0;
        final price = priceMap[coin] ?? 0.0;
        final usdValue = balance * price;
        usdValues[coin] = usdValue;
        totalUSD += usdValue;
      }
      
      setState(() {
        _balances = balances;
        _usdValues = usdValues;
        _totalUSDValue = totalUSD;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading coins: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Coins'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black87,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadCoinData,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadCoinData,
              child: CustomScrollView(
                slivers: [
                  // Total Portfolio Value Card
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.blue.shade600, Colors.blue.shade900],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blue.withOpacity(0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Total Portfolio Value',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _priceService.formatUSD(_totalUSDValue),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '${_balances.length} coins • ${_balances.values.where((b) => b > 0).length} with balance',
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Coin List
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final coins = _balances.keys.toList()
                          ..sort((a, b) => (_usdValues[b] ?? 0).compareTo(_usdValues[a] ?? 0));
                        final coin = coins[index];
                        final balance = _balances[coin] ?? 0.0;
                        final usdValue = _usdValues[coin] ?? 0.0;
                        
                        return _CoinListTile(
                          coin: coin,
                          balance: balance,
                          usdValue: usdValue,
                          priceService: _priceService,
                        );
                      },
                      childCount: _balances.length,
                    ),
                  ),
                  const SliverSafeArea(
                    sliver: SliverToBoxAdapter(
                      child: SizedBox(height: 20),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _CoinListTile extends StatefulWidget {
  final String coin;
  final double balance;
  final double usdValue;
  final PriceConversionService priceService;

  const _CoinListTile({
    required this.coin,
    required this.balance,
    required this.usdValue,
    required this.priceService,
  });

  @override
  State<_CoinListTile> createState() => _CoinListTileState();
}

class _CoinListTileState extends State<_CoinListTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final coinEmojis = {
      'BTC': '₿',
      'ETH': 'Ξ',
      'BNB': '🟡',
      'USDT': '₮',
      'MATIC': '🔷',
      'TRX': '⚡',
      'SOL': '◎',
      'XRP': '✕',
      'DOGE': '🐕',
      'LTC': 'Ł',
    };

    final emoji = coinEmojis[widget.coin] ?? '💰';
    final hasBalance = widget.balance > 0;

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ListTile(
            onTap: () => setState(() => _expanded = !_expanded),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: _getGradientForCoin(widget.coin),
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Center(
                child: Text(
                  emoji,
                  style: const TextStyle(fontSize: 24),
                ),
              ),
            ),
            title: Text(
              widget.coin,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            subtitle: Text(
              '${widget.balance.toStringAsFixed(8)} ${widget.coin}',
              style: TextStyle(
                color: hasBalance ? Colors.green.shade600 : Colors.grey,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  widget.priceService.formatUSD(widget.usdValue),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.black87,
                  ),
                ),
                if (hasBalance)
                  Text(
                    '${(widget.balance > 0 ? '↑' : '↓')} $emoji',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.green.shade600,
                    ),
                  ),
              ],
            ),
          ),
        ),
        // Expanded details
        if (_expanded)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: _CoinDetails(
              coin: widget.coin,
              balance: widget.balance,
              usdValue: widget.usdValue,
              priceService: widget.priceService,
            ),
          ),
      ],
    );
  }

  List<Color> _getGradientForCoin(String coin) {
    switch (coin) {
      case 'BTC':
        return [Colors.orange.shade600, Colors.orange.shade900];
      case 'ETH':
        return [Colors.purple.shade600, Colors.purple.shade900];
      case 'BNB':
        return [Colors.yellow.shade600, Colors.yellow.shade900];
      case 'USDT':
        return [Colors.green.shade600, Colors.green.shade900];
      case 'MATIC':
        return [Colors.blue.shade600, Colors.blue.shade900];
      case 'TRX':
        return [Colors.red.shade600, Colors.red.shade900];
      default:
        return [Colors.grey.shade600, Colors.grey.shade900];
    }
  }
}

class _CoinDetails extends StatefulWidget {
  final String coin;
  final double balance;
  final double usdValue;
  final PriceConversionService priceService;

  const _CoinDetails({
    required this.coin,
    required this.balance,
    required this.usdValue,
    required this.priceService,
  });

  @override
  State<_CoinDetails> createState() => _CoinDetailsState();
}

class _CoinDetailsState extends State<_CoinDetails> {
  late Future<double> _pricePerUnitFuture;

  @override
  void initState() {
    super.initState();
    _pricePerUnitFuture = widget.priceService.getUSDPrice(widget.coin);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<double>(
      future: _pricePerUnitFuture,
      builder: (context, snapshot) {
        final pricePerUnit = snapshot.data ?? 0.0;
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DetailRow(
              label: 'Balance',
              value: '${widget.balance.toStringAsFixed(8)} ${widget.coin}',
            ),
            const Divider(height: 16),
            _DetailRow(
              label: 'Price per Unit',
              value: widget.priceService.formatUSD(pricePerUnit),
            ),
            const Divider(height: 16),
            _DetailRow(
              label: 'Total USD Value',
              value: widget.priceService.formatUSD(widget.usdValue),
              valueColor: Colors.green.shade600,
              bold: true,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  // Navigate to send page or wallet details
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${widget.coin} details - Coming soon')),
                  );
                },
                icon: const Icon(Icons.arrow_forward),
                label: Text('View Details'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool bold;

  const _DetailRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade700,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? Colors.black87,
            fontSize: 14,
            fontWeight: bold ? FontWeight.bold : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
