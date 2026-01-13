import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class PortfolioChart extends StatefulWidget {
  final double totalBalance;
  final List<Map<String, dynamic>> holdings;
  final List<double>? priceHistory;
  
  const PortfolioChart({
    super.key,
    required this.totalBalance,
    required this.holdings,
    this.priceHistory,
  });

  @override
  State<PortfolioChart> createState() => _PortfolioChartState();
}

class _PortfolioChartState extends State<PortfolioChart> with SingleTickerProviderStateMixin {
  int _selectedTimeRange = 2; // Default to 1M
  int _chartType = 0; // 0 = line, 1 = pie
  late AnimationController _animationController;
  late Animation<double> _animation;
  
  final List<String> _timeRanges = ['24H', '1W', '1M', '3M', '1Y', 'ALL'];
  
  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  List<double> _generateMockPriceHistory() {
    final random = Random(42);
    final List<double> prices = [];
    double currentPrice = widget.totalBalance * 0.8;
    
    int dataPoints;
    switch (_selectedTimeRange) {
      case 0: dataPoints = 24; break;
      case 1: dataPoints = 7; break;
      case 2: dataPoints = 30; break;
      case 3: dataPoints = 90; break;
      case 4: dataPoints = 365; break;
      default: dataPoints = 730; break;
    }
    
    for (int i = 0; i < dataPoints; i++) {
      final change = (random.nextDouble() - 0.45) * currentPrice * 0.05;
      currentPrice += change;
      if (currentPrice < 0) currentPrice = widget.totalBalance * 0.1;
      prices.add(currentPrice);
    }
    
    // Make sure the last price matches current balance
    if (prices.isNotEmpty) {
      prices[prices.length - 1] = widget.totalBalance;
    }
    
    return prices;
  }

  double _calculatePercentChange(List<double> prices) {
    if (prices.length < 2) return 0;
    final first = prices.first;
    final last = prices.last;
    if (first == 0) return 0;
    return ((last - first) / first) * 100;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1A1F2E),
            const Color(0xFF1A1F2E).withOpacity(0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFF8B5CF6).withOpacity(0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B5CF6).withOpacity(0.1),
            blurRadius: 20,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with chart type toggle
          _buildHeader(),
          const SizedBox(height: 20),
          
          // Chart
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 500),
            child: _chartType == 0
                ? _buildLineChart()
                : _buildPieChart(),
          ),
          
          // Time range selector (only for line chart)
          if (_chartType == 0) ...[
            const SizedBox(height: 20),
            _buildTimeRangeSelector(),
          ],
          
          // Holdings list (for pie chart)
          if (_chartType == 1) ...[
            const SizedBox(height: 16),
            _buildHoldingsList(),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final prices = widget.priceHistory ?? _generateMockPriceHistory();
    final percentChange = _calculatePercentChange(prices);
    final isPositive = percentChange >= 0;
    
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Portfolio Value',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '\$${widget.totalBalance.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              if (_chartType == 0)
                Row(
                  children: [
                    Icon(
                      isPositive ? Icons.trending_up : Icons.trending_down,
                      color: isPositive ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                      size: 18,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${isPositive ? '+' : ''}${percentChange.toStringAsFixed(2)}%',
                      style: TextStyle(
                        color: isPositive ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _timeRanges[_selectedTimeRange],
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        
        // Chart type toggle
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFF0D1421),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              _buildChartTypeButton(0, Icons.show_chart, 'Line'),
              _buildChartTypeButton(1, Icons.pie_chart, 'Pie'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChartTypeButton(int type, IconData icon, String label) {
    final isSelected = _chartType == type;
    return GestureDetector(
      onTap: () {
        setState(() => _chartType = type);
        _animationController.reset();
        _animationController.forward();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF8B5CF6).withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? const Color(0xFF8B5CF6) : Colors.white38,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLineChart() {
    final prices = widget.priceHistory ?? _generateMockPriceHistory();
    final isPositive = _calculatePercentChange(prices) >= 0;
    final gradientColor = isPositive ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    
    final minY = prices.reduce(min) * 0.95;
    final maxY = prices.reduce(max) * 1.05;
    
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return SizedBox(
          height: 200,
          child: LineChart(
            LineChartData(
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: (maxY - minY) / 4,
                getDrawingHorizontalLine: (value) => FlLine(
                  color: Colors.white.withOpacity(0.05),
                  strokeWidth: 1,
                ),
              ),
              titlesData: FlTitlesData(
                show: true,
                rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 50,
                    getTitlesWidget: (value, meta) {
                      return Text(
                        '\$${(value / 1000).toStringAsFixed(1)}k',
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 10,
                        ),
                      );
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              minX: 0,
              maxX: prices.length.toDouble() - 1,
              minY: minY,
              maxY: maxY,
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (touchedSpots) {
                    return touchedSpots.map((spot) {
                      return LineTooltipItem(
                        '\$${spot.y.toStringAsFixed(2)}',
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    }).toList();
                  },
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: List.generate(
                    (prices.length * _animation.value).toInt().clamp(1, prices.length),
                    (index) => FlSpot(index.toDouble(), prices[index]),
                  ),
                  isCurved: true,
                  curveSmoothness: 0.3,
                  color: gradientColor,
                  barWidth: 2.5,
                  isStrokeCapRound: true,
                  dotData: FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        gradientColor.withOpacity(0.3),
                        gradientColor.withOpacity(0.0),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPieChart() {
    final colors = [
      const Color(0xFFF7931A), // BTC
      const Color(0xFF627EEA), // ETH
      const Color(0xFFF3BA2F), // BNB
      const Color(0xFF00FFA3), // SOL
      const Color(0xFFEF0027), // TRX
      const Color(0xFF00AAE4), // XRP
      const Color(0xFFC2A633), // DOGE
      const Color(0xFFBFBBBB), // LTC
    ];
    
    final validHoldings = widget.holdings.where((h) => (h['value'] as double) > 0).toList();
    
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return SizedBox(
          height: 200,
          child: validHoldings.isEmpty
              ? Center(
                  child: Text(
                    'No holdings to display',
                    style: TextStyle(color: Colors.white38),
                  ),
                )
              : PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 50,
                    startDegreeOffset: -90,
                    sections: List.generate(validHoldings.length, (index) {
                      final holding = validHoldings[index];
                      final value = holding['value'] as double;
                      final percentage = widget.totalBalance > 0 
                          ? (value / widget.totalBalance * 100) 
                          : 0.0;
                      
                      return PieChartSectionData(
                        value: value * _animation.value,
                        title: percentage > 5 ? '${percentage.toStringAsFixed(1)}%' : '',
                        color: colors[index % colors.length],
                        radius: 35 + (_animation.value * 10),
                        titleStyle: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    }),
                  ),
                ),
        );
      },
    );
  }

  Widget _buildTimeRangeSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(_timeRanges.length, (index) {
        final isSelected = _selectedTimeRange == index;
        return GestureDetector(
          onTap: () {
            setState(() => _selectedTimeRange = index);
            _animationController.reset();
            _animationController.forward();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected 
                  ? const Color(0xFF8B5CF6).withOpacity(0.2) 
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected 
                    ? const Color(0xFF8B5CF6) 
                    : Colors.transparent,
              ),
            ),
            child: Text(
              _timeRanges[index],
              style: TextStyle(
                color: isSelected ? const Color(0xFF8B5CF6) : Colors.white38,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildHoldingsList() {
    final colors = [
      const Color(0xFFF7931A),
      const Color(0xFF627EEA),
      const Color(0xFFF3BA2F),
      const Color(0xFF00FFA3),
      const Color(0xFFEF0027),
      const Color(0xFF00AAE4),
      const Color(0xFFC2A633),
      const Color(0xFFBFBBBB),
    ];
    
    final validHoldings = widget.holdings.where((h) => (h['value'] as double) > 0).toList();
    validHoldings.sort((a, b) => (b['value'] as double).compareTo(a['value'] as double));
    
    return Column(
      children: List.generate(validHoldings.length.clamp(0, 4), (index) {
        final holding = validHoldings[index];
        final value = holding['value'] as double;
        final percentage = widget.totalBalance > 0 
            ? (value / widget.totalBalance * 100) 
            : 0.0;
        
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: colors[index % colors.length],
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  holding['symbol'] ?? 'Unknown',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                ),
              ),
              Text(
                '\$${value.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colors[index % colors.length].withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${percentage.toStringAsFixed(1)}%',
                  style: TextStyle(
                    color: colors[index % colors.length],
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
