import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'dart:math' as math;

import '../../../core/constants/app_constants.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../services/price_service.dart';
import '../../../services/wallet_service.dart';
import '../../../services/notification_service.dart';
import '../../../services/transaction_service.dart';
import '../../../services/preload_service.dart';
import '../../../services/incoming_tx_monitor.dart';
import '../../../models/transaction_model.dart';
import '../../widgets/portfolio_chart_widget.dart';

class DashboardPageEnhanced extends ConsumerStatefulWidget {
  const DashboardPageEnhanced({super.key});

  @override
  ConsumerState<DashboardPageEnhanced> createState() =>
      _DashboardPageEnhancedState();
}

class _DashboardPageEnhancedState extends ConsumerState<DashboardPageEnhanced>
    with TickerProviderStateMixin {
  final PriceService _priceService = PriceService();
  final WalletService _walletService = WalletService();
  final NotificationService _notificationService = NotificationService();
  final TransactionService _transactionService = TransactionService();
  final PreloadService _preloadService = PreloadService();
  final IncomingTxMonitor _incomingTxMonitor = IncomingTxMonitor();

  // Animation controllers
  late AnimationController _logoAnimationController;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  Map<String, Map<String, dynamic>> _priceData = {};
  Map<String, double> _balances = {};
  double _totalPortfolioValue = 0.0;
  List<Transaction> _recentTransactions = [];
  bool _isLoading = true;
  bool _refreshing = false;
  Set<String> _favorites = {'BTC', 'ETH'}; // Default favorites
  bool _balanceHidden = false; // Toggle to hide/show balance

  // Coin data with colors
  final List<Map<String, dynamic>> _allCoins = [
    {
      'symbol': 'BTC',
      'name': 'Bitcoin',
      'color': Color(0xFFF7931A),
      'icon': '₿'
    },
    {
      'symbol': 'ETH',
      'name': 'Ethereum',
      'color': Color(0xFF627EEA),
      'icon': 'Ξ'
    },
    {
      'symbol': 'SOL',
      'name': 'Solana',
      'color': Color(0xFF00FFA3),
      'icon': '◎'
    },
    {'symbol': 'BNB', 'name': 'BNB', 'color': Color(0xFFF3BA2F), 'icon': 'B'},
    {
      'symbol': 'TRX',
      'name': 'TRON',
      'color': Color(0xFFEF0027),
      'icon': '⧫'
    },
    {'symbol': 'XRP', 'name': 'XRP', 'color': Color(0xFF00AAE4), 'icon': 'X'},
    {
      'symbol': 'DOGE',
      'name': 'Dogecoin',
      'color': Color(0xFFC2A633),
      'icon': 'Ð'
    },
    {
      'symbol': 'LTC',
      'name': 'Litecoin',
      'color': Color(0xFFBFBBBB),
      'icon': 'Ł'
    },
    {
      'symbol': 'USDT',
      'name': 'Tether',
      'color': Color(0xFF26A17B),
      'icon': '₮'
    },
  ];

  @override
  void initState() {
    super.initState();

    // Logo rotation animation
    _logoAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();

    // Pulse animation for the glow
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _loadDashboardData();
    _preloadService.preloadSwapData();
    _incomingTxMonitor.startMonitoring();
    _loadFavorites();
  }

  @override
  void dispose() {
    _logoAnimationController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadFavorites() async {
    // Load favorites from storage (mock for now)
    setState(() {
      _favorites = {'BTC', 'ETH', 'SOL'};
    });
  }

  void _toggleFavorite(String symbol) {
    setState(() {
      if (_favorites.contains(symbol)) {
        _favorites.remove(symbol);
      } else {
        _favorites.add(symbol);
      }
    });
    HapticFeedback.lightImpact();
  }

  Future<void> _loadDashboardData() async {
    if (mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final symbols = [
        'BTC',
        'ETH',
        'BNB',
        'SOL',
        'XRP',
        'DOGE',
        'LTC',
        'USDT'
      ];
      final prices = await _priceService.getPrices(symbols);
      final realBalances = await _walletService.getBalances();

      double totalValue = 0.0;
      realBalances.forEach((symbol, balance) {
        final coinPrice = prices[symbol];
        if (coinPrice != null && balance > 0) {
          totalValue += balance * (coinPrice['price'] as double? ?? 0);
        }
      });

      final allTx = await _transactionService.getAllTransactions();

      if (mounted) {
        setState(() {
          _priceData = prices;
          _balances = realBalances;
          _totalPortfolioValue = totalValue;
          _recentTransactions = allTx.take(5).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _refreshData() async {
    HapticFeedback.mediumImpact();
    setState(() => _refreshing = true);
    await _loadDashboardData();
    await _incomingTxMonitor.resetBalances();
    setState(() => _refreshing = false);
  }

  String _formatCurrency(double amount) {
    if (amount >= 1000000) {
      return '\$${(amount / 1000000).toStringAsFixed(2)}M';
    } else if (amount >= 1000) {
      return '\$${(amount / 1000).toStringAsFixed(2)}K';
    }
    return '\$${amount.toStringAsFixed(2)}';
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

    // Theme colors
    final bgColor = isDark ? const Color(0xFF0D1421) : const Color(0xFFF8FAFC);
    final cardColor = isDark ? const Color(0xFF1A1F2E) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final subtextColor = isDark ? Colors.white70 : const Color(0xFF64748B);

    return WillPopScope(
      onWillPop: () async {
        SystemNavigator.pop();
        return false;
      },
      child: Scaffold(
        backgroundColor: bgColor,
        body: SafeArea(
          child: Column(
            children: [
              // Static Header - doesn't scroll
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
                      // Central Balance Card
                      _buildCentralLogo(
                          isDark, cardColor, textColor, subtextColor),

                      // Receive / Buy Buttons
                      _buildActionButtons(isDark, cardColor, textColor),

                      // Coin List
                      _buildCoinList(
                          isDark, cardColor, textColor, subtextColor),

                      // Bottom padding for nav bar
                      const SizedBox(height: 100),
                    ],
                  ),
                ),
              ),
            ],
          ),
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
          // Right icons - Search, Notification, History
          _buildIconButton(Icons.search_rounded, () {
            _showSearchSheet();
          }, cardColor, textColor),
          const SizedBox(width: 12),
          _buildNotificationButton(cardColor, textColor),
          const SizedBox(width: 12),
          _buildIconButton(Icons.history_rounded, () {
            context.go('/transactions');
          }, cardColor, textColor),
        ],
      ),
    );
  }

  Widget _buildNotificationButton(Color cardColor, Color textColor) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        _showNotifications();
      },
      child: Stack(
        children: [
          Container(
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
            child: Icon(
              Icons.notifications_rounded,
              color: textColor.withOpacity(0.7),
              size: 20,
            ),
          ),
          // Notification badge
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444),
                shape: BoxShape.circle,
                border: Border.all(
                  color: cardColor,
                  width: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showPortfolioCharts() {
    // Build holdings list from current balances
    final holdings = <Map<String, dynamic>>[];
    _balances.forEach((coin, balance) {
      final price = _priceData[coin]?['price'] ?? 0.0;
      final value = balance * price;
      if (value > 0) {
        holdings.add({
          'symbol': coin,
          'balance': balance,
          'value': value,
          'percentage': _totalPortfolioValue > 0 
              ? (value / _totalPortfolioValue * 100) 
              : 0.0,
        });
      }
    });
    
    // Sort by value descending
    holdings.sort((a, b) => (b['value'] as double).compareTo(a['value'] as double));
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0D1421),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Title
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Portfolio Analytics',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1F2E),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.close,
                          color: Colors.white60,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Charts
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: PortfolioChartWidget(
                    totalValue: _totalPortfolioValue,
                    holdings: holdings,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSearchSheet() {
    final searchController = TextEditingController();
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final query = searchController.text.toLowerCase();
            final filteredCoins = _allCoins.where((coin) {
              final symbol = (coin['symbol'] as String).toLowerCase();
              final name = (coin['name'] as String).toLowerCase();
              return symbol.contains(query) || name.contains(query);
            }).toList();
            
            return Container(
              height: MediaQuery.of(context).size.height * 0.85,
              decoration: const BoxDecoration(
                color: Color(0xFF0D1421),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  // Handle
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  
                  // Search header
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Search',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        // Search input
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1F2E),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFF8B5CF6).withOpacity(0.3),
                            ),
                          ),
                          child: TextField(
                            controller: searchController,
                            autofocus: true,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              hintText: 'Search coins, tokens...',
                              hintStyle: TextStyle(
                                color: Colors.white.withOpacity(0.4),
                              ),
                              prefixIcon: Icon(
                                Icons.search_rounded,
                                color: Colors.white.withOpacity(0.4),
                              ),
                              suffixIcon: searchController.text.isNotEmpty
                                  ? IconButton(
                                      icon: Icon(
                                        Icons.close_rounded,
                                        color: Colors.white.withOpacity(0.4),
                                      ),
                                      onPressed: () {
                                        searchController.clear();
                                        setSheetState(() {});
                                      },
                                    )
                                  : null,
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                            ),
                            onChanged: (_) => setSheetState(() {}),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Results
                  Expanded(
                    child: filteredCoins.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.search_off_rounded,
                                  size: 64,
                                  color: Colors.white.withOpacity(0.2),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  query.isEmpty 
                                      ? 'Start typing to search' 
                                      : 'No results for "$query"',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.5),
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.only(left: 20, right: 20, bottom: 100),
                            itemCount: filteredCoins.length,
                            itemBuilder: (context, index) {
                              final coin = filteredCoins[index];
                              final symbol = coin['symbol'] as String;
                              final name = coin['name'] as String;
                              final color = coin['color'] as Color;
                              final balance = _balances[symbol] ?? 0.0;
                              final priceInfo = _priceData[symbol];
                              final price = priceInfo?['price'] as double? ?? 0.0;
                              final change = priceInfo?['change24h'] as double? ?? 0.0;
                              final usdValue = balance * price;
                              final isPositive = change >= 0;
                              
                              return GestureDetector(
                                onTap: () {
                                  Navigator.pop(sheetContext);
                                  _showCoinDetailSheet(coin);
                                },
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1A1F2E),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: color.withOpacity(0.2),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      // Coin icon
                                      Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [color, color.withOpacity(0.7)],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                        child: Center(
                                          child: _getCoinIcon(symbol, color),
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      
                                      // Coin info
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              name,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                Text(
                                                  _formatPrice(price),
                                                  style: TextStyle(
                                                    color: Colors.white.withOpacity(0.6),
                                                    fontSize: 13,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: isPositive
                                                        ? const Color(0xFF10B981).withOpacity(0.2)
                                                        : const Color(0xFFEF4444).withOpacity(0.2),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Text(
                                                    '${isPositive ? '+' : ''}${change.toStringAsFixed(1)}%',
                                                    style: TextStyle(
                                                      color: isPositive
                                                          ? const Color(0xFF10B981)
                                                          : const Color(0xFFEF4444),
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w500,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      
                                      // Balance
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            symbol,
                                            style: TextStyle(
                                              color: color,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          if (balance > 0)
                                            Text(
                                              '\$${usdValue.toStringAsFixed(2)}',
                                              style: TextStyle(
                                                color: Colors.white.withOpacity(0.6),
                                                fontSize: 13,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showNotifications() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(
          color: Color(0xFF1A1F2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Title
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Notifications',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'Clear all',
                      style: TextStyle(
                        color: Color(0xFF8B5CF6),
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Notification list
            Expanded(
              child: _recentTransactions.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.notifications_off_outlined,
                            size: 64,
                            color: Colors.white.withOpacity(0.2),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No notifications yet',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: _recentTransactions.length,
                      itemBuilder: (context, index) {
                        final tx = _recentTransactions[index];
                        final isReceived = tx.type == 'received';
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF252B3B),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: isReceived
                                      ? const Color(0xFF10B981).withOpacity(0.1)
                                      : const Color(0xFFEF4444)
                                          .withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  isReceived
                                      ? Icons.south_west
                                      : Icons.north_east,
                                  color: isReceived
                                      ? const Color(0xFF10B981)
                                      : const Color(0xFFEF4444),
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      isReceived
                                          ? 'Received ${tx.coin}'
                                          : 'Sent ${tx.coin}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${tx.amount.toStringAsFixed(6)} ${tx.coin}',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.5),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                _formatTimeAgo(tx.timestamp),
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.4),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dateTime.day}/${dateTime.month}';
  }

  Widget _buildIconButton(
      IconData icon, VoidCallback onTap, Color cardColor, Color textColor) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
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
        child: Icon(
          icon,
          color: textColor.withOpacity(0.7),
          size: 20,
        ),
      ),
    );
  }

  Widget _buildCentralLogo(
      bool isDark, Color cardColor, Color textColor, Color subtextColor) {
    final gradientColors = isDark
        ? [const Color(0xFF1A1F2E), const Color(0xFF252B3B).withOpacity(0.8)]
        : [Colors.white, const Color(0xFFF1F5F9)];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: const Color(0xFF8B5CF6).withOpacity(0.2),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? const Color(0xFF8B5CF6).withOpacity(0.1)
                  : Colors.black.withOpacity(0.08),
              blurRadius: 30,
              spreadRadius: -5,
            ),
          ],
        ),
        child: Column(
          children: [
            // Total Balance Label with Eye Toggle
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFF10B981),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Total Balance',
                        style: TextStyle(
                          color: subtextColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          setState(() => _balanceHidden = !_balanceHidden);
                        },
                        child: Icon(
                          _balanceHidden ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                          color: subtextColor,
                          size: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Main Balance Amount
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return ShaderMask(
                  shaderCallback: (bounds) => LinearGradient(
                    colors: [
                      textColor,
                      textColor.withOpacity(0.9),
                      const Color(0xFF8B5CF6).withOpacity(0.8),
                    ],
                  ).createShader(bounds),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      _balanceHidden
                          ? '••••••••'
                          : (_totalPortfolioValue > 0
                              ? _formatCurrency(_totalPortfolioValue)
                              : '\$0.00'),
                      key: ValueKey(_balanceHidden),
                      style: TextStyle(
                        color: textColor,
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        letterSpacing: _balanceHidden ? 4 : -2,
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            // Percentage Change (mock)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.trending_up_rounded,
                    color: Color(0xFF10B981),
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _totalPortfolioValue > 0
                        ? '+2.4% today'
                        : 'Start investing',
                    style: const TextStyle(
                      color: Color(0xFF10B981),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Quick Stats Row
            Row(
              children: [
                Expanded(
                  child: _buildQuickStat(
                    icon: Icons.arrow_downward_rounded,
                    label: 'Received',
                    value: '\$0',
                    color: const Color(0xFF10B981),
                    textColor: textColor,
                    subtextColor: subtextColor,
                  ),
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: textColor.withOpacity(0.1),
                ),
                Expanded(
                  child: _buildQuickStat(
                    icon: Icons.arrow_upward_rounded,
                    label: 'Sent',
                    value: '\$0',
                    color: const Color(0xFFEF4444),
                    textColor: textColor,
                    subtextColor: subtextColor,
                  ),
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: textColor.withOpacity(0.1),
                ),
                Expanded(
                  child: _buildQuickStat(
                    icon: Icons.swap_horiz_rounded,
                    label: 'Swapped',
                    value: '\$0',
                    color: const Color(0xFF8B5CF6),
                    textColor: textColor,
                    subtextColor: subtextColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // View Charts Button
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                _showPortfolioCharts();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF8B5CF6).withOpacity(0.2),
                      const Color(0xFF06B6D4).withOpacity(0.2),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF8B5CF6).withOpacity(0.3),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.show_chart_rounded,
                      color: textColor.withOpacity(0.8),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'View Portfolio Analytics',
                      style: TextStyle(
                        color: textColor.withOpacity(0.8),
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickStat({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required Color textColor,
    required Color subtextColor,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: textColor,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: subtextColor,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _buildFundSection() {
    return const SizedBox.shrink(); // Removed - content moved to central card
  }

  Widget _buildActionButtons(bool isDark, Color cardColor, Color textColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
      child: Row(
        children: [
          // Receive button
          Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                context.go('/receive');
              },
              child: Container(
                height: 50,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFF10B981).withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.download_rounded,
                      color: const Color(0xFF10B981),
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Receive',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Send button
          Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                context.go('/send');
              },
              child: Container(
                height: 50,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFFEF4444).withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.upload_rounded,
                      color: const Color(0xFFEF4444),
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Send',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Swap button
          Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                context.go('/swap');
              },
              child: Container(
                height: 50,
                margin: const EdgeInsets.only(left: 8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF8B5CF6), Color(0xFF7C3AED)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.swap_horiz_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Swap',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoinList(
      bool isDark, Color cardColor, Color textColor, Color subtextColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: _allCoins.map((coin) {
          return _buildCoinTile(coin, cardColor, textColor, subtextColor);
        }).toList(),
      ),
    );
  }

  Widget _buildCoinTile(Map<String, dynamic> coin, Color cardColor,
      Color textColor, Color subtextColor) {
    final symbol = coin['symbol'] as String;
    final name = coin['name'] as String;
    final color = coin['color'] as Color;
    final isFavorite = _favorites.contains(symbol);

    final priceInfo = _priceData[symbol];
    final price = priceInfo?['price'] as double? ?? 0.0;
    final change = priceInfo?['change24h'] as double? ?? 0.0;
    final balance = _balances[symbol] ?? 0.0;
    final isPositive = change >= 0;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        _showCoinDetailSheet(coin);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            // Favorite star
            GestureDetector(
              onTap: () => _toggleFavorite(symbol),
              child: Icon(
                isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                color: isFavorite
                    ? const Color(0xFFFFD700)
                    : subtextColor.withOpacity(0.3),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),

            // Coin icon
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    color,
                    color.withOpacity(0.7),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: _getCoinIcon(symbol, color),
              ),
            ),
            const SizedBox(width: 12),

            // Coin name and change
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (change != 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: textColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '%',
                            style: TextStyle(
                              color: subtextColor,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        _formatPrice(price),
                        style: TextStyle(
                          color: subtextColor,
                          fontSize: 13,
                        ),
                      ),
                      if (change != 0) ...[
                        const SizedBox(width: 8),
                        Text(
                          '${isPositive ? '+' : ''}${change.toStringAsFixed(1)}%',
                          style: TextStyle(
                            color: isPositive
                                ? const Color(0xFF10B981)
                                : const Color(0xFFEF4444),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // Symbol
            Text(
              symbol,
              style: TextStyle(
                color: balance > 0 ? color : subtextColor.withOpacity(0.6),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCoinDetailSheet(Map<String, dynamic> coin) {
    final symbol = coin['symbol'] as String;
    final name = coin['name'] as String;
    final color = coin['color'] as Color;

    final priceInfo = _priceData[symbol];
    final price = priceInfo?['price'] as double? ?? 0.0;
    final change = priceInfo?['change24h'] as double? ?? 0.0;
    final balance = _balances[symbol] ?? 0.0;
    final usdValue = balance * price;
    final isPositive = change >= 0;

    // Filter transactions for this coin
    final coinTransactions =
        _recentTransactions.where((tx) => tx.coin == symbol).toList();

    // Store parent context for navigation after sheet closes
    final parentContext = context;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.95,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        snap: true,
        snapSizes: const [0.5, 0.95],
        builder: (innerContext, scrollController) => Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0D1421),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(
              color: color.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: SingleChildScrollView(
            controller: scrollController,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header with coin info
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      color.withOpacity(0.2),
                      Colors.transparent,
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Column(
                  children: [
                    // Coin icon
                    Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [color, color.withOpacity(0.7)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: color.withOpacity(0.4),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Center(
                        child: _getCoinIcon(symbol, color),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Price
                    Text(
                      _formatPrice(price),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),

                    // Name and change
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isPositive
                                ? const Color(0xFF10B981).withOpacity(0.2)
                                : const Color(0xFFEF4444).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${isPositive ? '+' : ''}${change.toStringAsFixed(2)}%',
                            style: TextStyle(
                              color: isPositive
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFFEF4444),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Balance section
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1F2E),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        Text(
                          balance.toStringAsFixed(8),
                          style: TextStyle(
                            color: color,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          symbol,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      width: 1,
                      height: 40,
                      color: Colors.white12,
                    ),
                    Column(
                      children: [
                        Text(
                          _formatCurrency(usdValue),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Value',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Chart placeholder
              Container(
                margin: const EdgeInsets.all(20),
                height: 120,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1F2E),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: CustomPaint(
                  size: const Size(double.infinity, 120),
                  painter: _SimpleChartPainter(
                    color: color,
                    isPositive: isPositive,
                  ),
                ),
              ),

              // Time period selector
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: ['LIVE', '1D', '7D', '1M', '3M', '6M', '1Y']
                      .map((period) {
                    final isSelected = period == 'LIVE';
                    return GestureDetector(
                      onTap: () => HapticFeedback.lightImpact(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF1A1F2E)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isSelected)
                              Container(
                                width: 6,
                                height: 6,
                                margin: const EdgeInsets.only(right: 4),
                                decoration: const BoxDecoration(
                                  color: Color(0xFF10B981),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            Text(
                              period,
                              style: TextStyle(
                                color:
                                    isSelected ? Colors.white : Colors.white54,
                                fontSize: 12,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(height: 20),

              // Action buttons
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    _buildSheetActionButton(
                      icon: Icons.download_rounded,
                      label: 'Receive',
                      color: const Color(0xFF10B981),
                      onTap: () {
                        print('🟢 Dashboard: Navigating to receive with coin: $symbol');
                        Navigator.pop(sheetContext);
                        parentContext.go('/receive', extra: {'coin': symbol});
                      },
                    ),
                    const SizedBox(width: 12),
                    _buildSheetActionButton(
                      icon: Icons.upload_rounded,
                      label: 'Send',
                      color: const Color(0xFFEF4444),
                      onTap: () {
                        print('🟢 Dashboard: Navigating to send with coin: $symbol');
                        Navigator.pop(sheetContext);
                        parentContext.go('/send', extra: {'coin': symbol});
                      },
                    ),
                    const SizedBox(width: 12),
                    _buildSheetActionButton(
                      icon: Icons.swap_horiz_rounded,
                      label: 'Swap',
                      color: const Color(0xFF8B5CF6),
                      onTap: () {
                        print('🟢 Dashboard: Navigating to swap with coin: $symbol');
                        Navigator.pop(sheetContext);
                        parentContext.go('/swap', extra: {'fromCoin': symbol});
                      },
                    ),
                    const SizedBox(width: 12),
                    _buildSheetActionButton(
                      icon: Icons.show_chart_rounded,
                      label: 'Chart',
                      color: const Color(0xFF3B82F6),
                      onTap: () {
                        print('🟢 Dashboard: Navigating to price chart for: $symbol');
                        Navigator.pop(sheetContext);
                        parentContext.go('/price-chart', extra: {
                          'coin': symbol,
                          'name': name,
                          'price': price,
                          'change': change,
                        });
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Activity section header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1F2E),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'ACTIVITY',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'ABOUT',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.4),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Transaction list - no Expanded needed since we're in SingleChildScrollView
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount:
                    coinTransactions.isEmpty ? 1 : coinTransactions.length,
                itemBuilder: (context, index) {
                    if (coinTransactions.isEmpty) {
                      return Container(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          children: [
                            Icon(
                              Icons.receipt_long_outlined,
                              size: 48,
                              color: Colors.white.withOpacity(0.2),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No transactions yet',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.4),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    final tx = coinTransactions[index];
                    final isReceived = tx.type == 'received';
                    final txDate = tx.timestamp;
                    final formattedDate =
                        '${txDate.hour}:${txDate.minute.toString().padLeft(2, '0')} ${txDate.hour >= 12 ? 'PM' : 'AM'}';

                    return GestureDetector(
                      onTap: () => _showTransactionDetailsSheet(
                        context, 
                        tx, 
                        color, 
                        symbol,
                        price,
                      ),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1F2E),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: isReceived
                                    ? const Color(0xFF10B981).withOpacity(0.1)
                                    : const Color(0xFFEF4444).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                isReceived ? Icons.south_west : Icons.north_east,
                                color: isReceived
                                    ? const Color(0xFF10B981)
                                    : const Color(0xFFEF4444),
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isReceived ? 'Received' : 'Sent',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    formattedDate,
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.5),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                              Text(
                                '${tx.amount.toStringAsFixed(8)}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                _formatCurrency(tx.amount * price),
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.5),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.chevron_right,
                            color: Colors.white.withOpacity(0.3),
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  );
                  },
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSheetActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1F2E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: color.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _getCoinIcon(String symbol, Color color) {
    IconData iconData;
    switch (symbol) {
      case 'BTC':
        iconData = Icons.currency_bitcoin;
        break;
      case 'ETH':
        iconData = Icons.diamond_outlined;
        break;
      case 'SOL':
        iconData = Icons.sunny;
        break;
      case 'BNB':
        iconData = Icons.hexagon_outlined;
        break;
      case 'XRP':
        iconData = Icons.water_drop_outlined;
        break;
      case 'DOGE':
        iconData = Icons.pets;
        break;
      case 'LTC':
        iconData = Icons.bolt;
        break;
      case 'USDT':
        iconData = Icons.attach_money;
        break;
      default:
        iconData = Icons.token;
    }

    return Icon(
      iconData,
      color: Colors.white,
      size: 24,
    );
  }
}

// Simple chart painter for coin detail sheet
class _SimpleChartPainter extends CustomPainter {
  final Color color;
  final bool isPositive;

  _SimpleChartPainter({
    required this.color,
    required this.isPositive,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Generate mock chart data points
    final random = math.Random(42);
    final points = <Offset>[];
    final baseY = size.height * 0.5;
    final amplitude = size.height * 0.3;

    for (int i = 0; i <= 50; i++) {
      final x = (i / 50) * size.width;
      double y;

      if (isPositive) {
        // Upward trend
        y = baseY - (i / 50) * amplitude + random.nextDouble() * 20 - 10;
      } else {
        // Downward trend
        y = baseY + (i / 50) * amplitude + random.nextDouble() * 20 - 10;
      }

      y = y.clamp(10.0, size.height - 10);
      points.add(Offset(x, y));
    }

    // Draw the line
    final path = Path();
    for (int i = 0; i < points.length; i++) {
      if (i == 0) {
        path.moveTo(points[i].dx, points[i].dy);
      } else {
        // Use bezier curves for smooth line
        final prev = points[i - 1];
        final curr = points[i];
        final controlX = (prev.dx + curr.dx) / 2;
        path.quadraticBezierTo(controlX, prev.dy, curr.dx, curr.dy);
      }
    }
    canvas.drawPath(path, paint);

    // Draw gradient fill below the line
    final fillPath = Path.from(path);
    fillPath.lineTo(size.width, size.height);
    fillPath.lineTo(0, size.height);
    fillPath.close();

    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        color.withOpacity(0.3),
        color.withOpacity(0.0),
      ],
    );

    final fillPaint = Paint()
      ..shader =
          gradient.createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawPath(fillPath, fillPaint);

    // Draw current price dot at the end
    final lastPoint = points.last;
    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawCircle(lastPoint, 4, dotPaint);

    // Draw glow around the dot
    final glowPaint = Paint()
      ..color = color.withOpacity(0.3)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(lastPoint, 8, glowPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Extension method to add transaction details sheet to the dashboard
extension TransactionDetailsSheet on _DashboardPageEnhancedState {
  void _showTransactionDetailsSheet(
    BuildContext context,
    Transaction tx,
    Color coinColor,
    String coinSymbol,
    double price,
  ) {
    final isReceived = tx.type == 'received';
    final typeColor = isReceived ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    
    HapticFeedback.mediumImpact();
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          decoration: const BoxDecoration(
            color: Color(0xFF0D1421),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      // Header with icon
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: typeColor.withOpacity(0.15),
                          shape: BoxShape.circle,
                          border: Border.all(color: coinColor, width: 3),
                        ),
                        child: Icon(
                          isReceived ? Icons.south_west : Icons.north_east,
                          color: typeColor,
                          size: 36,
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      // Transaction Type
                      Text(
                        isReceived ? 'Received' : 'Sent',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      
                      // Amount
                      Text(
                        '${isReceived ? '+' : '-'}${tx.amount.toStringAsFixed(8)} ${coinSymbol.split('-').first}',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: typeColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      
                      // USD Value
                      Text(
                        '\$${(tx.amount * price).toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.white.withOpacity(0.6),
                        ),
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Status Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: _getStatusColorForSheet(tx.status).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _getStatusColorForSheet(tx.status).withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              (tx.status == 'confirmed' || tx.status == 'completed' || tx.status == 'success')
                                  ? Icons.check_circle 
                                  : tx.status == 'pending' 
                                      ? Icons.hourglass_empty 
                                      : Icons.check_circle,
                              color: _getStatusColorForSheet(tx.status),
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              (tx.status == 'confirmed' || tx.status == 'completed' || tx.status == 'success') ? 'Confirmed' : 
                              tx.status == 'pending' ? 'Pending' : 
                              tx.status == 'failed' ? 'Failed' : 'Confirmed',
                              style: TextStyle(
                                color: _getStatusColorForSheet(tx.status),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Divider
                      Container(
                        height: 1,
                        color: Colors.white.withOpacity(0.1),
                      ),
                      
                      const SizedBox(height: 20),
                      
                      // Transaction Details
                      _buildDetailRowForSheet(
                        'Date & Time',
                        _formatDateTimeForSheet(tx.timestamp),
                      ),
                      _buildDetailRowForSheet('Network', coinSymbol),
                      if (tx.fee != null && tx.fee! > 0)
                        _buildDetailRowForSheet(
                          'Network Fee',
                          '${tx.fee!.toStringAsFixed(8)} ${coinSymbol.split('-').first}',
                        ),
                      
                      // Show From/To address based on transaction type
                      if (tx.type == 'sent' && tx.toAddress != null && tx.toAddress!.isNotEmpty)
                        _buildAddressRowForSheet('To', tx.toAddress!)
                      else if (tx.type == 'sent')
                        _buildAddressRowForSheet('To', tx.address),
                      
                      if (tx.type == 'received' && tx.fromAddress != null && tx.fromAddress!.isNotEmpty)
                        _buildAddressRowForSheet('From', tx.fromAddress!)
                      else if (tx.type == 'received')
                        _buildAddressRowForSheet('From', tx.address),
                      
                      // Transaction Hash
                      if (tx.txHash != null && tx.txHash!.isNotEmpty)
                        _buildTxHashRowForSheet(context, tx.txHash!, coinSymbol),
                      
                      if (tx.memo != null && tx.memo!.isNotEmpty)
                        _buildDetailRowForSheet('Memo', tx.memo!),
                      
                      const SizedBox(height: 24),
                      
                      // Action Buttons
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                final hash = tx.txHash ?? '';
                                if (hash.isNotEmpty) {
                                  Clipboard.setData(ClipboardData(text: hash));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: const Text('Transaction hash copied'),
                                      backgroundColor: coinColor,
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('No transaction hash available'),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(Icons.copy, size: 18),
                              label: const Text('Copy Hash'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: BorderSide(color: Colors.white.withOpacity(0.2)),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                final hash = tx.txHash ?? '';
                                if (hash.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('No transaction hash available'),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                  return;
                                }
                                
                                final explorerUrl = _getExplorerUrlForSheet(coinSymbol, hash);
                                if (explorerUrl != null) {
                                  final uri = Uri.parse(explorerUrl);
                                  if (await canLaunchUrl(uri)) {
                                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                                  } else {
                                    Clipboard.setData(ClipboardData(text: explorerUrl));
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Explorer URL copied to clipboard'),
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                    }
                                  }
                                }
                                Navigator.pop(context);
                              },
                              icon: const Icon(Icons.open_in_new, size: 18),
                              label: const Text('View Explorer'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: coinColor,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Close Button
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white.withOpacity(0.6),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('Close'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Color _getStatusColorForSheet(String status) {
    switch (status.toLowerCase()) {
      case 'confirmed':
      case 'completed':
      case 'success':
        return const Color(0xFF10B981);
      case 'pending':
        return const Color(0xFFF59E0B);
      case 'failed':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFF10B981); // Default to confirmed/green
    }
  }

  String _formatDateTimeForSheet(DateTime dt) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final hour = dt.hour > 12 ? dt.hour - 12 : dt.hour == 0 ? 12 : dt.hour;
    final amPm = dt.hour >= 12 ? 'PM' : 'AM';
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year} • $hour:${dt.minute.toString().padLeft(2, '0')} $amPm';
  }

  Widget _buildDetailRowForSheet(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressRowForSheet(String label, String address) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: address));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Address copied'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      address.length > 25
                          ? '${address.substring(0, 12)}...${address.substring(address.length - 10)}'
                          : address,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Icon(Icons.copy, size: 14, color: Colors.white.withOpacity(0.4)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTxHashRowForSheet(BuildContext context, String hash, String coin) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Transaction Hash',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: hash));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Transaction hash copied!'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.copy, size: 14, color: Color(0xFF3B82F6)),
                      SizedBox(width: 4),
                      Text(
                        'Copy',
                        style: TextStyle(
                          color: Color(0xFF3B82F6),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            hash,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              letterSpacing: 0.5,
              color: Colors.white.withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }

  String? _getExplorerUrlForSheet(String coin, String txHash) {
    final baseCoin = coin.split('-').first.toUpperCase();
    
    switch (baseCoin) {
      case 'BTC':
        return 'https://blockstream.info/tx/$txHash';
      case 'ETH':
        return 'https://etherscan.io/tx/$txHash';
      case 'BNB':
        return 'https://bscscan.com/tx/$txHash';
      case 'USDT':
        if (coin.contains('BEP20')) {
          return 'https://bscscan.com/tx/$txHash';
        } else if (coin.contains('TRC20')) {
          return 'https://tronscan.org/#/transaction/$txHash';
        }
        return 'https://etherscan.io/tx/$txHash';
      case 'SOL':
        return 'https://solscan.io/tx/$txHash';
      case 'XRP':
        return 'https://xrpscan.com/tx/$txHash';
      case 'TRX':
        return 'https://tronscan.org/#/transaction/$txHash';
      case 'LTC':
        return 'https://blockchair.com/litecoin/transaction/$txHash';
      case 'DOGE':
        return 'https://blockchair.com/dogecoin/transaction/$txHash';
      default:
        return null;
    }
  }
}
