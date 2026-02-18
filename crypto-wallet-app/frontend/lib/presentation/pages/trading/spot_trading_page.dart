import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:async';
import 'dart:math';

import '../../../services/market_service.dart';
import '../../../services/wallet_service.dart';
import '../../../core/providers/market_provider.dart';

class SpotTradingPage extends ConsumerStatefulWidget {
  const SpotTradingPage({super.key});

  @override
  ConsumerState<SpotTradingPage> createState() => _SpotTradingPageState();
}

class _SpotTradingPageState extends ConsumerState<SpotTradingPage> with SingleTickerProviderStateMixin {
  final MarketService _marketService = MarketService();
  final WalletService _walletService = WalletService();
  late TabController _tabController;
  Timer? _chartUpdateTimer;
  Timer? _priceUpdateTimer;
  Timer? _beepTimer;
  double _rippleRadius = 4.0;
  bool _rippleExpanding = true;
  
  // Supported coins from our wallet system
  final List<String> _supportedCoins = ['BTC', 'ETH', 'BNB', 'USDT', 'XRP', 'SOL', 'TRX', 'LTC', 'DOGE'];
  List<String> _tradingPairs = [];
  
  String _selectedPair = 'BTC/USDT';
  String _selectedTimeframe = '24h';
  final List<String> _timeframes = ['24h', '1M', '6M', '1Y', '5Y'];
  
  // Real-time chart data
  List<FlSpot> _chartData = [];
  int _chartDataPoints = 24; // Reduced for better performance
  double _currentPrice = 0.0;
  double _priceChange = 0.0;
  bool _isChartLoading = true;
  double _lastPrice = 0.0;
  
  // Trading state
  bool _isBuyMode = true;
  double _buyAmount = 0.0;
  double _sellAmount = 0.0;
  double _priceInput = 0.0;
  final List<Map<String, dynamic>> _orders = [];
  
  // User balance
  Map<String, double> _userBalances = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _generateTradingPairs();
    _initializeChartData();
    _startChartUpdates();
    _startPriceUpdates();
    _startBeepAnimation();
    _loadUserBalances();
  }

  @override
  void dispose() {
    _chartUpdateTimer?.cancel();
    _priceUpdateTimer?.cancel();
    _beepTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  void _generateTradingPairs() {
    _tradingPairs = [];
    for (final coin in _supportedCoins) {
      if (coin != 'USDT') {
        _tradingPairs.add('$coin/USDT');
      }
    }
    if (_tradingPairs.isNotEmpty) {
      _selectedPair = _tradingPairs.first;
    }
  }

  void _startPriceUpdates() {
    _priceUpdateTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _updateCurrentPrice();
    });
  }

  void _updateCurrentPrice() async {
    if (!mounted) return;
    
    try {
      final marketData = await _marketService.fetchPrices();
      final symbol = _selectedPair.split('/').first;
      final currentData = marketData[symbol];
      
      if (currentData != null && mounted) {
        final newPrice = currentData['price_usd'] as double;
        final newChange = currentData['change_24h'] as double;
        
        setState(() {
          _lastPrice = _currentPrice;
          _currentPrice = newPrice;
          _priceChange = newChange;
          
          // Add new data point to chart only if we have data
          if (_chartData.isNotEmpty) {
            // Shift data left and add new point
            final newData = _chartData.skip(1).toList();
            // Re-index the data
            final reindexedData = newData.asMap().entries.map((entry) {
              return FlSpot(entry.key.toDouble(), entry.value.y);
            }).toList();
            // Add the new price at the end
            reindexedData.add(FlSpot(reindexedData.length.toDouble(), newPrice));
            _chartData = reindexedData;
          }
        });
      }
    } catch (e) {
      // Silently handle errors - use fallback data
      if (mounted) {
        print('Error updating price: $e');
      }
    }
  }

  void _initializeChartData() async {
    if (!mounted) return;
    
    setState(() {
      _isChartLoading = true;
    });
    
    try {
      // Determine days based on selected timeframe
      int days;
      switch (_selectedTimeframe) {
        case '24h':
          days = 1;
          _chartDataPoints = 24;
          break;
        case '1M':
          days = 30;
          _chartDataPoints = 30;
          break;
        case '6M':
          days = 180;
          _chartDataPoints = 26; // ~26 weeks
          break;
        case '1Y':
          days = 365;
          _chartDataPoints = 12; // 12 months
          break;
        case '5Y':
          days = 1825;
          _chartDataPoints = 60; // 60 months
          break;
        default:
          days = 7;
          _chartDataPoints = 24;
      }
      
      // Fetch real historical market data
      final historicalData = await _marketService.fetchHistoricalData(
        _selectedPair.split('/').first,
        days,
      );
      
      if (historicalData.isNotEmpty && mounted) {
        setState(() {
          // Use actual historical data with proper indexing
          _chartData = historicalData.asMap().entries.map((entry) {
            final priceData = entry.value;
            return FlSpot(
              entry.key.toDouble(),
              (priceData['price'] as num).toDouble()
            );
          }).toList();
          
          // Update current price from the latest data point
          if (_chartData.isNotEmpty) {
            _currentPrice = _chartData.last.y;
            _lastPrice = _chartData.length > 1 ? _chartData[_chartData.length - 2].y : _currentPrice;
          }
          
          // Also update price change from market data
          _updatePriceChange();
          _isChartLoading = false;
        });
      } else if (mounted) {
        // Generate fallback data if API fails
        final symbol = _selectedPair.split('/').first;
        final basePrice = _getBasePriceForSymbol(symbol);
        
        setState(() {
          _chartData = List.generate(_chartDataPoints, (index) {
            final randomVariation = (Random().nextDouble() - 0.5) * basePrice * 0.02;
            return FlSpot(index.toDouble(), basePrice + randomVariation);
          });
          _currentPrice = _chartData.last.y;
          _lastPrice = _chartData.length > 1 ? _chartData[_chartData.length - 2].y : _currentPrice;
          _isChartLoading = false;
        });
      }
    } catch (e) {
      print('Error loading historical data: $e');
      if (mounted) {
        // Generate fallback data on error
        final symbol = _selectedPair.split('/').first;
        final basePrice = _getBasePriceForSymbol(symbol);
        
        setState(() {
          _chartData = List.generate(_chartDataPoints, (index) {
            final randomVariation = (Random().nextDouble() - 0.5) * basePrice * 0.02;
            return FlSpot(index.toDouble(), basePrice + randomVariation);
          });
          _currentPrice = _chartData.last.y;
          _lastPrice = _chartData.length > 1 ? _chartData[_chartData.length - 2].y : _currentPrice;
          _isChartLoading = false;
        });
      }
    }
  }

  double _getBasePriceForSymbol(String symbol) {
    switch (symbol) {
      case 'BTC':
        return 60250.0;
      case 'ETH':
        return 3450.0;
      case 'BNB':
        return 485.0;
      case 'SOL':
        return 145.0;
      case 'XRP':
        return 0.62;
      case 'TRX':
        return 0.12;
      case 'LTC':
        return 82.0;
      case 'DOGE':
        return 0.15;
      default:
        return 100.0;
    }
  }

  void _updatePriceChange() async {
    if (!mounted) return;
    
    try {
      final marketData = await _marketService.fetchPrices();
      final symbol = _selectedPair.split('/').first;
      final currentData = marketData[symbol];
      
      if (currentData != null && mounted) {
        setState(() {
          _priceChange = currentData['change_24h'] as double;
        });
      }
    } catch (e) {
      // Silently handle errors
    }
  }

  void _startBeepAnimation() {
    _beepTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_rippleExpanding) {
          _rippleRadius += 0.5;
          if (_rippleRadius >= 8.0) {
            _rippleExpanding = false;
          }
        } else {
          _rippleRadius -= 0.5;
          if (_rippleRadius <= 4.0) {
            _rippleExpanding = true;
          }
        }
      });
    });
  }

  void _startChartUpdates() {
    _chartUpdateTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _updateChartData();
    });
  }

  void _updateChartData() async {
    if (!mounted) return;
    
    try {
      // Only update chart data structure periodically, prices are updated separately
      if (_chartData.isEmpty || _chartData.length < 5) {
        _initializeChartData();
      }
    } catch (e) {
      // Silently handle errors
    }
  }

  void _loadUserBalances() async {
    try {
      final balances = await _walletService.getBalances();
      setState(() {
        _userBalances = balances;
      });
    } catch (e) {
      print('Error loading user balances: $e');
    }
  }

  void _executeTrade() async {
    final symbol = _selectedPair.split('/').first;
    final amount = _isBuyMode ? _buyAmount : _sellAmount;
    final price = _priceInput > 0 ? _priceInput : _currentPrice;
    
    if (amount <= 0) {
      _showSnackBar('Please enter a valid amount');
      return;
    }

    // Check balance for sell orders
    if (!_isBuyMode) {
      final balance = _userBalances[symbol] ?? 0.0;
      if (amount > balance) {
        _showSnackBar('Insufficient $symbol balance');
        return;
      }
    }

    try {
      // Execute real trade through backend
      final result = await _walletService.executeTrade(
        pair: _selectedPair,
        type: _isBuyMode ? 'BUY' : 'SELL',
        amount: amount,
        price: price,
      );

      if (result['success']) {
        final order = {
          'id': DateTime.now().millisecondsSinceEpoch.toString(),
          'type': _isBuyMode ? 'BUY' : 'SELL',
          'pair': _selectedPair,
          'amount': amount,
          'price': price,
          'total': amount * price,
          'timestamp': DateTime.now(),
          'status': 'FILLED'
        };

        setState(() {
          _orders.insert(0, order);
          if (_isBuyMode) {
            _buyAmount = 0.0;
          } else {
            _sellAmount = 0.0;
          }
          _priceInput = 0.0;
        });

        // Reload balances after trade
        _loadUserBalances();
        
        _showSnackBar('${_isBuyMode ? 'Buy' : 'Sell'} order executed for $amount $symbol at \$${price.toStringAsFixed(2)}');
      } else {
        _showSnackBar('Trade failed: ${result['error']}');
      }
    } catch (e) {
      _showSnackBar('Trade error: $e');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final marketPrices = ref.watch(marketPricesProvider);
    
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Spot Trading'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Trading'),
            Tab(text: 'Orders'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTradingTab(marketPrices),
          _buildOrdersTab(),
        ],
      ),
    );
  }

  Widget _buildTradingTab(AsyncValue<Map<String, dynamic>> marketPrices) {
    return Column(
      children: [
        // Trading Pair Selector and Price Info
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).colorScheme.outline.withOpacity(0.1),
              ),
            ),
          ),
          child: Row(
            children: [
              // Trading Pair Selector
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Text(
                      _selectedPair,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_drop_down, size: 20),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              
              // Price and Change - Using real-time data
              Expanded(
                child: Row(
                  children: [
                    Text(
                      '\$${_currentPrice.toStringAsFixed(2)}',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _priceChange >= 0
                            ? Colors.green.withOpacity(0.2)
                            : Colors.red.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${_priceChange >= 0 ? '+' : ''}${_priceChange.toStringAsFixed(2)}%',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: _priceChange >= 0 ? Colors.green : Colors.red,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Timeframe Selector
        Container(
          height: 48,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).colorScheme.outline.withOpacity(0.1),
              ),
            ),
          ),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _timeframes.length,
            itemBuilder: (context, index) {
              final timeframe = _timeframes[index];
              final isSelected = timeframe == _selectedTimeframe;
              
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedTimeframe = timeframe;
                      _initializeChartData(); // Reload chart data when timeframe changes
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      timeframe,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: isSelected
                            ? Theme.of(context).colorScheme.onPrimary
                            : Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        // Chart Area with ripple effect dot and titles
        Container(
          height: 200,
          padding: const EdgeInsets.all(8),
          child: _isChartLoading
              ? const Center(child: CircularProgressIndicator())
              : LineChart(
                  LineChartData(
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: true,
                      drawHorizontalLine: true,
                      horizontalInterval: _calculateChartInterval(),
                      verticalInterval: _chartDataPoints.toDouble() / 4,
                      getDrawingHorizontalLine: (value) {
                        return FlLine(
                          color: Colors.grey.withOpacity(0.3),
                          strokeWidth: 1,
                          dashArray: [5, 5],
                        );
                      },
                      getDrawingVerticalLine: (value) {
                        return FlLine(
                          color: Colors.grey.withOpacity(0.3),
                          strokeWidth: 1,
                          dashArray: [5, 5],
                        );
                      },
                    ),
                    titlesData: FlTitlesData(
                      show: true,
                      rightTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      topTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 22,
                          interval: _chartDataPoints.toDouble() / 4,
                          getTitlesWidget: (value, meta) {
                            return Text(
                              _formatXAxisTitle(value),
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 10,
                              ),
                            );
                          },
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 40,
                          interval: _calculateChartInterval(),
                          getTitlesWidget: (value, meta) {
                            return Text(
                              '\$${value.toStringAsFixed(2)}',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 10,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    minX: 0,
                    maxX: _chartData.isEmpty ? (_chartDataPoints - 1).toDouble() : (_chartData.length - 1).toDouble(),
                    minY: _calculateMinY(),
                    maxY: _calculateMaxY(),
                    lineTouchData: LineTouchData(
                      enabled: true,
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipItems: (touchedSpots) {
                          return touchedSpots.map((touchedSpot) {
                            return LineTooltipItem(
                              '\$${touchedSpot.y.toStringAsFixed(2)}',
                              const TextStyle(color: Colors.white),
                            );
                          }).toList();
                        },
                      ),
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        spots: _chartData,
                        isCurved: true,
                        color: _currentPrice >= _lastPrice ? Colors.green : Colors.red,
                        barWidth: 2,
                        isStrokeCapRound: true,
                        belowBarData: BarAreaData(
                          show: true,
                          color: _currentPrice >= _lastPrice
                              ? Colors.green.withOpacity(0.1)
                              : Colors.red.withOpacity(0.1),
                        ),
                        dotData: FlDotData(
                          show: true,
                          getDotPainter: (spot, percent, barData, index) {
                            // Show ripple effect dot only at the current rate (last point)
                            if (index == _chartData.length - 1) {
                              return FlDotCirclePainter(
                                radius: _rippleRadius,
                                color: _currentPrice >= _lastPrice ? Colors.green : Colors.red,
                                strokeWidth: 2,
                                strokeColor: Colors.white,
                              );
                            }
                            return FlDotCirclePainter(
                              radius: 0,
                              color: Colors.transparent,
                            );
                          },
                        ),
                        gradient: LinearGradient(
                          colors: [
                            _currentPrice >= _lastPrice
                                ? Colors.green.withOpacity(0.8)
                                : Colors.red.withOpacity(0.8),
                            _currentPrice >= _lastPrice
                                ? Colors.green.withOpacity(0.1)
                                : Colors.red.withOpacity(0.1),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.topRight,
                        ),
                      ),
                    ],
                  ),
                ),
        ),

        // Trade Section - Moved under chart
        Expanded(
          child: _buildTradeTab(),
        ),
      ],
    );
  }

  double _calculateChartInterval() {
    if (_chartData.isEmpty) return 1000;
    final minY = _calculateMinY();
    final maxY = _calculateMaxY();
    final range = maxY - minY;
    // Return a reasonable interval (about 4 divisions)
    return range > 0 ? range / 4 : 1000;
  }

  double _calculateMinY() {
    if (_chartData.isEmpty) return 0;
    final minValue = _chartData.map((spot) => spot.y).reduce((a, b) => a < b ? a : b);
    // Add 1% padding below minimum
    return minValue * 0.99;
  }

  double _calculateMaxY() {
    if (_chartData.isEmpty) return 1000;
    final maxValue = _chartData.map((spot) => spot.y).reduce((a, b) => a > b ? a : b);
    // Add 1% padding above maximum
    return maxValue * 1.01;
  }

  String _formatXAxisTitle(double value) {
    if (_chartData.isEmpty) return '';
    final index = value.toInt();
    if (index >= _chartData.length) return '';
    
    // For demo purposes, format based on timeframe
    switch (_selectedTimeframe) {
      case '24h':
        return '${index + 1}h';
      case '1M':
        return '${index + 1}d';
      case '6M':
        return '${(index + 1) * 7}d';
      case '1Y':
        return '${index + 1}M';
      case '5Y':
        return '${index + 1}Y';
      default:
        return '${index + 1}';
    }
  }

  Widget _buildTradeTab() {
    final symbol = _selectedPair.split('/').first;
    final baseBalance = _userBalances[symbol] ?? 0.0;
    final quoteBalance = _userBalances['USDT'] ?? 0.0;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Balance Display
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      Text(
                        'Available $symbol',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey,
                        ),
                      ),
                      Text(
                        baseBalance.toStringAsFixed(6),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    children: [
                      Text(
                        'Available USDT',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey,
                        ),
                      ),
                      Text(
                        quoteBalance.toStringAsFixed(2),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Buy/Sell Toggle
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _isBuyMode = true;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _isBuyMode
                            ? Colors.green
                            : Colors.transparent,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(8),
                          bottomLeft: Radius.circular(8),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'BUY',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: _isBuyMode
                                ? Colors.white
                                : Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _isBuyMode = false;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: !_isBuyMode
                            ? Colors.red
                            : Colors.transparent,
                        borderRadius: const BorderRadius.only(
                          topRight: Radius.circular(8),
                          bottomRight: Radius.circular(8),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'SELL',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: !_isBuyMode
                                ? Colors.white
                                : Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Price Input
          TextField(
            decoration: InputDecoration(
              labelText: 'Price (USDT)',
              hintText: _currentPrice.toStringAsFixed(2),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            keyboardType: TextInputType.number,
            onChanged: (value) {
              _priceInput = double.tryParse(value) ?? 0.0;
            },
          ),
          const SizedBox(height: 16),

          // Amount Input
          TextField(
            decoration: InputDecoration(
              labelText: 'Amount',
              hintText: 'Enter amount to ${_isBuyMode ? 'buy' : 'sell'}',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            keyboardType: TextInputType.number,
            onChanged: (value) {
              final amount = double.tryParse(value) ?? 0.0;
              if (_isBuyMode) {
                _buyAmount = amount;
              } else {
                _sellAmount = amount;
              }
            },
          ),
          const SizedBox(height: 24),

          // Execute Button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _executeTrade,
              style: ElevatedButton.styleFrom(
                backgroundColor: _isBuyMode ? Colors.green : Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                '${_isBuyMode ? 'BUY' : 'SELL'} ${_selectedPair.split('/').first}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrdersTab() {
    return _orders.isEmpty
        ? const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.receipt_long, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'No orders yet',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          )
        : ListView.builder(
            itemCount: _orders.length,
            itemBuilder: (context, index) {
              final order = _orders[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: order['type'] == 'BUY'
                          ? Colors.green.withOpacity(0.2)
                          : Colors.red.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      order['type'] == 'BUY' ? Icons.arrow_upward : Icons.arrow_downward,
                      color: order['type'] == 'BUY' ? Colors.green : Colors.red,
                    ),
                  ),
                  title: Text(
                    '${order['type']} ${order['pair']}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '${order['amount']} ${order['pair'].split('/').first} @ \$${order['price'].toStringAsFixed(2)}',
                  ),
                  trailing: Text(
                    '\$${order['total'].toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
              );
            },
          );
  }
}
