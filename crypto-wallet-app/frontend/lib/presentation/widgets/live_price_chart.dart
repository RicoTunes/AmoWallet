import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class LivePriceChart extends StatefulWidget {
  final String coinSymbol;
  final Color chartColor;
  final double initialPrice;
  final double change24h;

  const LivePriceChart({
    Key? key,
    required this.coinSymbol,
    required this.chartColor,
    required this.initialPrice,
    required this.change24h,
  }) : super(key: key);

  @override
  State<LivePriceChart> createState() => _LivePriceChartState();
}

class _LivePriceChartState extends State<LivePriceChart> with TickerProviderStateMixin {
  late List<FlSpot> _chartData;
  late AnimationController _animationController;
  late Animation<double> _animation;
  double _currentPrice = 0.0;
  double _maxPrice = 0.0;
  double _minPrice = 0.0;
  int _currentIndex = 0;
  bool _isAnimating = true;

  @override
  void initState() {
    super.initState();
    
    // Initialize chart data with realistic price movements
    _initializeChartData();
    
    // Set up animation controller for continuous updates
    _animationController = AnimationController(
      duration: const Duration(seconds: 30), // Update every 30 seconds
      vsync: this,
    );
    
    _animation = Tween<double>(begin: 0, end: 1).animate(_animationController);
    
    // Start the animation loop
    _animationController.repeat();
    _animationController.addListener(_updateChart);
  }

  void _initializeChartData() {
    // Create initial chart data based on the initial price
    final basePrice = widget.initialPrice;
    _chartData = List.generate(20, (index) {
      // Simulate small random fluctuations around the base price
      final fluctuation = (index % 5 == 0) ? 0.0 : (0.5 - (index * 0.02)) * (widget.change24h / 100);
      final price = basePrice + (basePrice * fluctuation);
      return FlSpot(index.toDouble(), price);
    });
    
    // Calculate initial min/max
    _calculateMinMax();
  }

  void _updateChart() {
    if (!_isAnimating) return;
    
    // Add new data point with slight variation
    final lastPrice = _chartData.isNotEmpty ? _chartData.last.y : widget.initialPrice;
    final randomFactor = (0.5 - (DateTime.now().millisecond % 100) / 100) * 0.005; // Small random variation
    final trendFactor = widget.change24h / 1000; // Slow trend based on 24h change
    
    final newPrice = lastPrice * (1 + randomFactor + trendFactor);
    
    // Remove oldest point and add new one
    if (_chartData.length >= 20) {
      _chartData.removeAt(0);
    }
    
    _chartData.add(FlSpot(_currentIndex.toDouble(), newPrice));
    _currentIndex++;
    
    // Update current price
    _currentPrice = newPrice;
    
    // Recalculate min/max
    _calculateMinMax();
    
    // Trigger rebuild
    if (mounted) {
      setState(() {});
    }
  }

  void _calculateMinMax() {
    if (_chartData.isEmpty) return;
    
    _maxPrice = _chartData.map((spot) => spot.y).reduce((a, b) => a > b ? a : b);
    _minPrice = _chartData.map((spot) => spot.y).reduce((a, b) => a < b ? a : b);
    
    // Add some padding to min/max values
    final padding = (_maxPrice - _minPrice) * 0.05;
    _maxPrice += padding;
    _minPrice -= padding;
  }

  @override
  void dispose() {
    _animationController.removeListener(_updateChart);
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F2E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        children: [
          LineChart(
            LineChartData(
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: (_maxPrice - _minPrice) / 5,
                getDrawingHorizontalLine: (value) {
                  return FlLine(
                    color: Colors.white.withOpacity(0.1),
                    strokeWidth: 1,
                  );
                },
              ),
              titlesData: FlTitlesData(
                show: true,
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 20,
                    getTitlesWidget: (value, meta) {
                      // Show relative time labels
                      final timeLabels = ['Now', '20m', '40m', '1h', '1h20', '1h40', '2h'];
                      final index = (value ~/ 3).toInt();
                      if (index < timeLabels.length) {
                        return Text(
                          timeLabels[index],
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                          ),
                        );
                      }
                      return const Text('');
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    interval: (_maxPrice - _minPrice) / 5,
                    getTitlesWidget: (value, meta) {
                      return Text(
                        r'$' + value.toStringAsFixed(2),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                        ),
                      );
                    },
                  ),
                ),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(
                show: false,
              ),
              minX: 0,
              maxX: 20,
              minY: _minPrice,
              maxY: _maxPrice,
              lineBarsData: [
                LineChartBarData(
                  spots: _chartData,
                  isCurved: true,
                  color: widget.chartColor,
                  barWidth: 2,
                  isStrokeCapRound: true,
                  dotData: FlDotData(
                    show: false,
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    color: widget.chartColor.withOpacity(0.2),
                  ),
                ),
              ],
            ),
          ),
          // Current price indicator with blinking animation
          Positioned(
            right: 10,
            top: 20,
            child: AnimatedBuilder(
              animation: _animationController,
              builder: (context, child) {
                final blink = (_animationController.value % 1) > 0.5;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        r'$' + _currentPrice.toStringAsFixed(2),
                        style: TextStyle(
                          color: blink ? widget.chartColor : Colors.white,
                          fontWeight: blink ? FontWeight.bold : FontWeight.normal,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        widget.change24h >= 0 ? Icons.trending_up : Icons.trending_down,
                        color: widget.change24h >= 0 ? Colors.lightGreen : Colors.red,
                        size: 12,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}