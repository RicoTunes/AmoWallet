import 'package:flutter/material.dart';
import '../widgets/price_chart_widget.dart';

class PriceChartPage extends StatelessWidget {
  final String coinSymbol;
  final String coinName;
  final double currentPrice;
  final double priceChange24h;

  const PriceChartPage({
    super.key,
    required this.coinSymbol,
    required this.coinName,
    required this.currentPrice,
    required this.priceChange24h,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('$coinName Chart'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: PriceChartWidget(
            coinSymbol: coinSymbol,
            coinColor: _getCoinColor(coinSymbol),
            currentPrice: currentPrice,
            showFullScreen: true,
          ),
        ),
      ),
    );
  }

  Color _getCoinColor(String symbol) {
    final colors = {
      'BTC': const Color(0xFFF7931A),
      'ETH': const Color(0xFF627EEA),
      'BNB': const Color(0xFFF0B90B),
      'SOL': const Color(0xFF00FFA3),
      'XRP': const Color(0xFF23292F),
      'TRX': const Color(0xFFFF060A),
      'LTC': const Color(0xFFBFBBBB),
      'DOGE': const Color(0xFFC2A633),
      'USDT': const Color(0xFF26A17B),
      'MATIC': const Color(0xFF8247E5),
      'AVAX': const Color(0xFFE84142),
    };
    return colors[symbol] ?? Colors.blue;
  }
}