import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:dio/dio.dart';
import 'dart:math' as math;
import 'dart:async';

import '../../services/price_service.dart';

class PortfolioChartWidget extends StatefulWidget {
  final double totalValue;
  final List<Map<String, dynamic>> holdings;
  final List<Map<String, dynamic>>? historicalData;

  const PortfolioChartWidget({
    super.key,
    required this.totalValue,
    required this.holdings,
    this.historicalData,
  });

  @override
  State<PortfolioChartWidget> createState() => _PortfolioChartWidgetState();
}

class _PortfolioChartWidgetState extends State<PortfolioChartWidget> {
    @override
    void didUpdateWidget(covariant PortfolioChartWidget oldWidget) {
      super.didUpdateWidget(oldWidget);
      // Reload chart data if totalValue or holdings change
      if (widget.totalValue != oldWidget.totalValue || widget.holdings != oldWidget.holdings) {
        _loadChartData();
      }
    }
  String _selectedTimeframe = '1W';
  int _touchedIndex = -1;
  bool _loading = true;
  List<FlSpot> _chartData = [];
  double _portfolioChange = 0.0;
  final Dio _dio = Dio();
  final PriceService _priceService = PriceService();
  Timer? _updateTimer;

  final List<String> _timeframes = ['1D', '1W', '1M', '3M', '1Y', 'ALL'];

  @override
  void initState() {
    super.initState();
    _loadChartData();
    _startLiveUpdates();
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  void _startLiveUpdates() {
    // Update chart every 30 seconds for live feel
    _updateTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        _updateChartData();
      }
    });
  }

  void _updateChartData() {
    if (!mounted) return;
    
    // Update the last data point with current portfolio value
    if (_chartData.isNotEmpty) {
      final lastIndex = _chartData.length - 1;
      final newSpots = List<FlSpot>.from(_chartData);
      
      // Update last point with current value (slight variation for realism)
      final random = math.Random();
      final variation = 1 + (random.nextDouble() * 0.02 - 0.01); // ±1% variation
      final currentValue = widget.totalValue * variation;
      
      newSpots[lastIndex] = FlSpot(lastIndex.toDouble(), currentValue);
      
      // Calculate portfolio change
      final firstValue = _chartData.first.y;
      final changePercent = ((currentValue - firstValue) / firstValue) * 100;
      
      setState(() {
        _chartData = newSpots;
        _portfolioChange = changePercent;
      });
    }
  }

  Future<void> _loadChartData() async {
    if (!mounted) return;
    
    setState(() {
      _loading = true;
    });

    try {
      // Try to get historical data for the portfolio
      await _loadHistoricalPortfolioData();
    } catch (e) {
      print('❌ Portfolio chart load failed: $e');
      // Fallback to realistic generated data based on current portfolio value
      _generateRealisticChartData();
    }

    if (!mounted) return;
    setState(() {
      _loading = false;
    });
  }

  Future<void> _loadHistoricalPortfolioData() async {
    // For now, generate realistic data based on current portfolio value
    // In a real app, you would fetch historical portfolio data from your backend
    _generateRealisticChartData();
  }

  void _generateRealisticChartData() {
    final random = math.Random();
    final spots = <FlSpot>[];
    double minValue = widget.totalValue;
    double maxValue = widget.totalValue;
    final dataPoints = _getDataPointCount();
    final baseValue = widget.totalValue > 0 ? widget.totalValue : 1.0;
    // Generate realistic portfolio movement
    final volatility = 0.02; // 2% daily volatility
    // Start from 85% of current value and work up
    double value = baseValue * 0.85;
    for (int i = 0; i < dataPoints; i++) {
      final randomWalk = random.nextDouble() * 2 - 1; // -1 to 1
      value = value * (1 + randomWalk * volatility);
      value = value * (1 + 0.0005);
      if (value < baseValue * 0.7) value = baseValue * 0.7;
      if (value > baseValue * 1.1) value = baseValue * 1.1;
      spots.add(FlSpot(i.toDouble(), value));
      if (value < minValue) minValue = value;
      if (value > maxValue) maxValue = value;
    }
    // Ensure last point is current value
    if (spots.isNotEmpty) {
      spots[spots.length - 1] = FlSpot((spots.length - 1).toDouble(), widget.totalValue);
    }
    // Calculate portfolio change
    final firstValue = spots.isNotEmpty ? spots.first.y : baseValue;
    final lastValue = spots.isNotEmpty ? spots.last.y : baseValue;
    final change = firstValue != 0 ? ((lastValue - firstValue) / firstValue) * 100 : 0.0;
    if (!mounted) return;
    setState(() {
      _chartData = spots;
      _portfolioChange = change;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Line Chart Section
        _buildLineChartSection(),
        const SizedBox(height: 24),
        
        // Allocation Pie Chart
        _buildAllocationSection(),
      ],
    );
  }

  Widget _buildLineChartSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1A1F2E).withOpacity(0.9),
            const Color(0xFF0D1421).withOpacity(0.9),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFF8B5CF6).withOpacity(0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Portfolio Value',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '\$${_formatNumber(widget.totalValue)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              _buildChangeIndicator(),
            ],
          ),
          const SizedBox(height: 20),
          
          // Timeframe selector
          _buildTimeframeSelector(),
          const SizedBox(height: 20),
          
          // Line Chart
          SizedBox(
            height: 200,
            child: _loading 
                ? Center(
                    child: CircularProgressIndicator(
                      color: const Color(0xFF8B5CF6),
                      strokeWidth: 2,
                    ),
                  )
                : _buildLineChart(),
          ),
        ],
      ),
    );
  }

  Widget _buildChangeIndicator() {
    final isPositive = _portfolioChange >= 0;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: (isPositive ? const Color(0xFF10B981) : const Color(0xFFEF4444))
            .withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPositive ? Icons.trending_up : Icons.trending_down,
            color: isPositive ? const Color(0xFF10B981) : const Color(0xFFEF4444),
            size: 16,
          ),
          const SizedBox(width: 4),
          Text(
            '${isPositive ? '+' : ''}${_portfolioChange.toStringAsFixed(2)}%',
            style: TextStyle(
              color: isPositive ? const Color(0xFF10B981) : const Color(0xFFEF4444),
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeframeSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: _timeframes.map((tf) {
        final isSelected = _selectedTimeframe == tf;
        return GestureDetector(
          onTap: () {
            setState(() {
              _selectedTimeframe = tf;
              _loadChartData();
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected 
                  ? const Color(0xFF8B5CF6) 
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              tf,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white54,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildLineChart() {
    if (_chartData.isEmpty) {
      return Center(
        child: Text(
          'No chart data available',
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
          ),
        ),
      );
    }
    
    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 1,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: Colors.white.withOpacity(0.05),
              strokeWidth: 1,
            );
          },
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: _getInterval(),
              getTitlesWidget: (value, meta) {
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _getBottomTitle(value.toInt()),
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                    ),
                  ),
                );
              },
            ),
          ),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        borderData: FlBorderData(show: false),
        minX: 0,
        maxX: _chartData.length.toDouble() - 1,
        minY: _chartData.map((s) => s.y).reduce(math.min) * 0.95,
        maxY: _chartData.map((s) => s.y).reduce(math.max) * 1.05,
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF1A1F2E),
            tooltipPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                return LineTooltipItem(
                  '\$${_formatNumber(spot.y)}',
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
            spots: _chartData,
            isCurved: true,
            curveSmoothness: 0.3,
            gradient: const LinearGradient(
              colors: [Color(0xFF8B5CF6), Color(0xFF06B6D4)],
            ),
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF8B5CF6).withOpacity(0.3),
                  const Color(0xFF06B6D4).withOpacity(0.0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  int _getDataPointCount() {
    switch (_selectedTimeframe) {
      case '1D': return 24;
      case '1W': return 7;
      case '1M': return 30;
      case '3M': return 90;
      case '1Y': return 52;
      case 'ALL': return 100;
      default: return 7;
    }
  }

  double _getInterval() {
    switch (_selectedTimeframe) {
      case '1D': return 6;
      case '1W': return 1;
      case '1M': return 7;
      case '3M': return 30;
      case '1Y': return 13;
      case 'ALL': return 25;
      default: return 1;
    }
  }

  String _getBottomTitle(int index) {
    switch (_selectedTimeframe) {
      case '1D':
        return '${(index).toString().padLeft(2, '0')}:00';
      case '1W':
        const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        return days[index % 7];
      case '1M':
        return '${index + 1}';
      case '3M':
        final months = ['Jan', 'Feb', 'Mar'];
        return months[index ~/ 30];
      case '1Y':
        const months = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];
        return months[(index ~/ 4) % 12];
      default:
        return '';
    }
  }

  Widget _buildAllocationSection() {
    if (widget.holdings.isEmpty) return const SizedBox.shrink();
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1A1F2E).withOpacity(0.9),
            const Color(0xFF0D1421).withOpacity(0.9),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFF8B5CF6).withOpacity(0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Asset Allocation',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          
          Row(
            children: [
              // Pie Chart
              SizedBox(
                width: 140,
                height: 140,
                child: PieChart(
                  PieChartData(
                    pieTouchData: PieTouchData(
                      touchCallback: (FlTouchEvent event, pieTouchResponse) {
                        setState(() {
                          if (!event.isInterestedForInteractions ||
                              pieTouchResponse == null ||
                              pieTouchResponse.touchedSection == null) {
                            _touchedIndex = -1;
                            return;
                          }
                          _touchedIndex = pieTouchResponse
                              .touchedSection!.touchedSectionIndex;
                        });
                      },
                    ),
                    borderData: FlBorderData(show: false),
                    sectionsSpace: 2,
                    centerSpaceRadius: 35,
                    sections: _buildPieSections(),
                  ),
                ),
              ),
              const SizedBox(width: 20),
              
              // Legend
              Expanded(
                child: Column(
                  children: widget.holdings.take(5).map((holding) {
                    return _buildLegendItem(holding);
                  }).toList(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<PieChartSectionData> _buildPieSections() {
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
    
    return widget.holdings.asMap().entries.map((entry) {
      final index = entry.key;
      final holding = entry.value;
      final isTouched = index == _touchedIndex;
      final double percentage = (holding['percentage'] as num?)?.toDouble() ?? 
          (holding['value'] as num).toDouble() / widget.totalValue * 100;
      
      return PieChartSectionData(
        color: colors[index % colors.length],
        value: percentage,
        title: isTouched ? '${percentage.toStringAsFixed(1)}%' : '',
        radius: isTouched ? 45 : 40,
        titleStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      );
    }).toList();
  }

  Widget _buildLegendItem(Map<String, dynamic> holding) {
    final colors = {
      'BTC': const Color(0xFFF7931A),
      'ETH': const Color(0xFF627EEA),
      'BNB': const Color(0xFFF3BA2F),
      'SOL': const Color(0xFF00FFA3),
      'TRX': const Color(0xFFEF0027),
      'XRP': const Color(0xFF00AAE4),
      'DOGE': const Color(0xFFC2A633),
      'LTC': const Color(0xFFBFBBBB),
    };
    
    final symbol = holding['symbol'] ?? holding['coin'] ?? 'UNK';
    final color = colors[symbol] ?? const Color(0xFF8B5CF6);
    final percentage = (holding['percentage'] as num?)?.toDouble() ?? 
        (holding['value'] as num).toDouble() / widget.totalValue * 100;
    final value = (holding['value'] as num).toDouble();
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  symbol,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Text(
                  '\$${_formatNumber(value)}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${percentage.toStringAsFixed(1)}%',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  String _formatNumber(double value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(2)}M';
    } else if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(2)}K';
    } else if (value >= 1) {
      return value.toStringAsFixed(2);
    } else {
      return value.toStringAsFixed(4);
    }
  }
}
