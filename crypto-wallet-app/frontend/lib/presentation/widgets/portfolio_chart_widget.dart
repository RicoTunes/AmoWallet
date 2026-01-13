import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math' as math;

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
  String _selectedTimeframe = '1W';
  int _touchedIndex = -1;

  final List<String> _timeframes = ['1D', '1W', '1M', '3M', '1Y', 'ALL'];

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
            child: _buildLineChart(),
          ),
        ],
      ),
    );
  }

  Widget _buildChangeIndicator() {
    // Mock data - in real app, calculate from historical data
    final change = 5.23;
    final isPositive = change >= 0;
    
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
            '${isPositive ? '+' : ''}${change.toStringAsFixed(2)}%',
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
          onTap: () => setState(() => _selectedTimeframe = tf),
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
    final spots = _generateChartData();
    
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
        maxX: spots.length.toDouble() - 1,
        minY: spots.map((s) => s.y).reduce(math.min) * 0.95,
        maxY: spots.map((s) => s.y).reduce(math.max) * 1.05,
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
            spots: spots,
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

  List<FlSpot> _generateChartData() {
    // Generate realistic looking price data
    final random = math.Random(42);
    final dataPoints = _getDataPointCount();
    final List<FlSpot> spots = [];
    
    double value = widget.totalValue * 0.85;
    for (int i = 0; i < dataPoints; i++) {
      final change = (random.nextDouble() - 0.45) * (value * 0.03);
      value = value + change;
      if (value < widget.totalValue * 0.7) value = widget.totalValue * 0.7;
      if (value > widget.totalValue * 1.1) value = widget.totalValue * 1.1;
      spots.add(FlSpot(i.toDouble(), value));
    }
    
    // Ensure last point is close to current value
    spots[spots.length - 1] = FlSpot((spots.length - 1).toDouble(), widget.totalValue);
    
    return spots;
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
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              symbol,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
              ),
            ),
          ),
          Text(
            '${percentage.toStringAsFixed(1)}%',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
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
    }
    return value.toStringAsFixed(2);
  }
}

// Standalone Portfolio Chart Page
class PortfolioChartPage extends StatelessWidget {
  final double totalValue;
  final List<Map<String, dynamic>> holdings;

  const PortfolioChartPage({
    super.key,
    required this.totalValue,
    required this.holdings,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1421),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1F2E),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Text(
                      'Portfolio Analytics',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              
              PortfolioChartWidget(
                totalValue: totalValue,
                holdings: holdings,
              ),
              
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }
}
