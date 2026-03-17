import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import '../../../core/providers/theme_provider.dart';
import '../../../services/price_service.dart';
import '../../../services/wallet_service.dart';
import '../../../services/transaction_service.dart';
import '../../../services/preload_service.dart';

import '../../../services/notification_service.dart';
import '../../../services/incoming_tx_watcher_service.dart';
import '../../../services/blockchain_service.dart';
import '../../../models/transaction_model.dart';
import '../../widgets/portfolio_chart_widget.dart';
import '../../widgets/animated_number.dart';
import '../transactions/transaction_detail_page.dart';

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
  final TransactionService _transactionService = TransactionService();
  final PreloadService _preloadService = PreloadService();
  final NotificationService _notificationService = NotificationService();

  // Animation controllers
  late AnimationController _logoAnimationController;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _coinSpinController;

  Map<String, Map<String, dynamic>> _priceData = {};
  Map<String, double> _balances = {};
  double _totalPortfolioValue = 0.0;
  List<Transaction> _recentTransactions = [];
  bool _isLoading = true;
  bool _isSheetOpen = false; // Prevent multiple bottom sheets
  Set<String> _favorites = {'BTC', 'ETH'}; // Default favorites
  bool _balanceHidden = false; // Toggle to hide/show balance
  double _totalReceived = 0.0;
  double _totalSent = 0.0;
  double _totalSwapped = 0.0;

  // Auto-refresh timer & price change tracking
  Timer? _autoRefreshTimer;
  Map<String, double> _previousPrices = {};
  Set<String> _changedCoins = {};

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

    // Spin animation for coin icons when prices change
    _coinSpinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _loadCachedBalances().then((_) => _loadDashboardData());
    _preloadService.preloadSwapData();
    _loadFavorites();

    // Listen for notification changes so badge updates in real time
    _notificationService.addListener(_onNotificationsChanged);

    // Auto-refresh prices every 10 minutes
    _autoRefreshTimer = Timer.periodic(
      const Duration(minutes: 10),
      (_) => _loadDashboardData(),
    );
  }

  @override
  void dispose() {
    _logoAnimationController.dispose();
    _pulseController.dispose();
    _coinSpinController.dispose();
    _autoRefreshTimer?.cancel();
    _notificationService.removeListener(_onNotificationsChanged);
    super.dispose();
  }

  void _onNotificationsChanged(List<AppNotification> _) {
    if (mounted) setState(() {});
  }

  /// Load last-known balances instantly from SharedPreferences so the UI
  /// never shows blank while the network fetch is in progress.
  Future<void> _loadCachedBalances() async {
    try {
      // Ensure persisted prices are loaded into PriceService memory before
      // we try to compute the portfolio total.
      await _priceService.loadFromDisk();

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('dashboard_cached_balances');
      if (raw != null && raw.isNotEmpty) {
        final Map<String, dynamic> decoded = jsonDecode(raw);
        final cached = decoded.map((k, v) => MapEntry(k, (v as num).toDouble()));
        if (mounted && cached.isNotEmpty) {
          // Use the now-loaded persisted prices to compute a real total
          final cachedPrices = _priceService.getCachedPrices();
          double totalValue = 0.0;
          cached.forEach((symbol, balance) {
            final coinPrice = cachedPrices[symbol] ?? _priceData[symbol];
            final price = (coinPrice?['price'] as double?) ?? 0.0;
            if (balance > 0 && price > 0) totalValue += balance * price;
          });
          setState(() {
            _balances = Map.from(cached);
            // Only override total if we got a real non-zero value
            if (totalValue > 0) _totalPortfolioValue = totalValue;
            // Seed _priceData with cached prices so coin tiles show values immediately
            if (_priceData.isEmpty && cachedPrices.isNotEmpty) {
              _priceData = Map.from(cachedPrices);
            }
          });
          debugPrint('📦 Loaded ${cached.length} cached balances, total \$${totalValue.toStringAsFixed(2)}');
        }
      }
    } catch (e) {
      debugPrint('⚠️ Could not load cached balances: $e');
    }
  }

  Future<void> _saveCachedBalances(Map<String, double> balances) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(balances);
      await prefs.setString('dashboard_cached_balances', encoded);
    } catch (e) {
      debugPrint('⚠️ Could not save cached balances: $e');
    }
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
        'USDT',
        'TRX',
      ];
      
      // OPTIMIZED: Fetch prices, balances, and transactions in PARALLEL
      print('🚀 Starting parallel data fetch...');
      final startTime = DateTime.now();
      
      final results = await Future.wait([
        _priceService.getPrices(symbols).timeout(
          const Duration(seconds: 20),
          onTimeout: () {
            print('⏱️ Price fetch timeout - using cached/fallback');
            return <String, Map<String, dynamic>>{};
          },
        ),
        _walletService.getBalances().timeout(
          const Duration(seconds: 20),
          onTimeout: () {
            debugPrint('⏱️ Balance fetch timeout - keeping existing balances');
            return <String, double>{}; // empty => merge will keep existing
          },
        ),
        _transactionService.getAllTransactions().timeout(
          const Duration(seconds: 8),
          onTimeout: () => <Transaction>[],
        ),
      ]);
      
      final fetchTime = DateTime.now().difference(startTime).inMilliseconds;
      print('⚡ Parallel fetch completed in ${fetchTime}ms');
      
      final prices = results[0] as Map<String, Map<String, dynamic>>;
      final freshBalances = results[1] as Map<String, double>;
      final allTx = results[2] as List<Transaction>;
      
      debugPrint('📈 Loaded prices for ${prices.length} symbols');
      debugPrint('💰 Fresh balances from network: $freshBalances');

      // MERGE: start with existing cached values, update only coins that returned data.
      // This means a rate-limited or timed-out coin keeps its last-known value.
      final mergedBalances = Map<String, double>.from(_balances);
      if (freshBalances.isNotEmpty) {
        freshBalances.forEach((coin, balance) {
          mergedBalances[coin] = balance; // 0.0 is valid (empty wallet)
        });
      }

      // Apply pending deductions: if we recently sent a coin and the blockchain
      // hasn't confirmed yet, the on-chain balance is still the old (higher)
      // value. Keep the optimistic (lower) balance until the chain catches up.
      try {
        final prefs = await SharedPreferences.getInstance();
        final pendingRaw = prefs.getString('pending_deductions') ?? '[]';
        final pending = List<Map<String, dynamic>>.from(jsonDecode(pendingRaw));
        final now = DateTime.now().millisecondsSinceEpoch;
        final kept = <Map<String, dynamic>>[];
        for (final d in pending) {
          final coin = d['coin'] as String;
          final deduction = (d['amount'] as num).toDouble();
          final preSend = (d['preSendBalance'] as num).toDouble();
          final ts = d['timestamp'] as int;
          // Expire after 5 minutes
          if (now - ts > 5 * 60 * 1000) continue;
          final realBal = mergedBalances[coin] ?? 0.0;
          // If real balance is still >= pre-send (chain hasn't caught up), apply deduction
          if (realBal >= preSend - 0.000001) {
            mergedBalances[coin] = (realBal - deduction).clamp(0.0, double.infinity);
            kept.add(d);
            debugPrint('⏳ Pending deduction applied: $coin -$deduction (chain still shows $realBal)');
          }
          // If real balance is already lower, chain caught up — drop deduction
        }
        await prefs.setString('pending_deductions', jsonEncode(kept));
      } catch (e) {
        debugPrint('⚠️ Pending deduction check failed: $e');
      }

      double totalValue = 0.0;
      
      // Use real prices if available, otherwise fall back to previously cached _priceData.
      final effectivePrices = prices.isNotEmpty ? prices : _priceData;

      mergedBalances.forEach((symbol, balance) {
        final coinPrice = effectivePrices[symbol];
        final price = (coinPrice?['price'] as double?) ?? 0.0;
        if (balance > 0 && price > 0) {
          final value = balance * price;
          totalValue += value;
          debugPrint('💵 $symbol: $balance @ \$${price.toStringAsFixed(2)} = \$${value.toStringAsFixed(2)}');
        }
      });

      if (mounted) {
        // Detect which coins had price changes for spin animation
        if (prices.isNotEmpty && _previousPrices.isNotEmpty) {
          final newChanged = <String>{};
          for (final symbol in prices.keys) {
            final newPrice = (prices[symbol]?['price'] as double?) ?? 0.0;
            final oldPrice = _previousPrices[symbol] ?? 0.0;
            if (oldPrice > 0 && newPrice > 0 && (newPrice - oldPrice).abs() / oldPrice > 0.0001) {
              newChanged.add(symbol);
            }
          }
          if (newChanged.isNotEmpty) {
            _changedCoins = newChanged;
            _coinSpinController.forward(from: 0).then((_) {
              if (mounted) setState(() => _changedCoins = {});
            });
          }
        }

        // Save current prices for next comparison
        if (prices.isNotEmpty) {
          _previousPrices = {};
          for (final e in prices.entries) {
            _previousPrices[e.key] = (e.value['price'] as double?) ?? 0.0;
          }
        }

        setState(() {
          _priceData = prices.isNotEmpty ? prices : _priceData;
          _balances = mergedBalances;
          _totalPortfolioValue = totalValue;
          _recentTransactions = allTx.take(5).toList();
          _isLoading = false;
          // Compute received / sent / swapped totals from transaction history
          double tRcv = 0, tSnt = 0, tSwp = 0;
          for (final tx in allTx) {
            final coinPrice = (effectivePrices[tx.coin]?['price'] as double?) ?? 0.0;
            final usdVal = tx.amount.abs() * coinPrice;
            if (tx.isReceived) {
              tRcv += usdVal;
            } else if (tx.isSent) {
              tSnt += usdVal;
            } else if (tx.isSwap) {
              tSwp += usdVal;
            }
          }
          _totalReceived = tRcv;
          _totalSent = tSnt;
          _totalSwapped = tSwp;
        });
        debugPrint('✅ Dashboard updated: ${_balances.length} balances, total \$${totalValue.toStringAsFixed(2)}');
        // Persist to disk so we restore them instantly next time
        _saveCachedBalances(mergedBalances);
      }
    } catch (e) {
      print('❌ Dashboard load error: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
  
  Future<void> _refreshData() async {
    HapticFeedback.mediumImpact();
    await _loadDashboardData();
    // Also check for new incoming transactions immediately
    IncomingTxWatcherService().pollNow();
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
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: Row(
        children: [
          // App name / logo
          Text(
            'AmoWallet',
            style: TextStyle(
              color: textColor,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const Spacer(),
          // Right icons
          _buildIconButton(Icons.search_rounded, () {
            _showSearchSheet();
          }, cardColor, textColor),
          const SizedBox(width: 10),
          _buildNotificationButton(cardColor, textColor),
          const SizedBox(width: 10),
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
          // Notification badge — only show when unread notifications exist
          if (_notificationService.unreadCount > 0)
            Positioned(
              right: 4,
              top: 4,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: cardColor,
                    width: 1.5,
                  ),
                ),
                child: Center(
                  child: Text(
                    _notificationService.unreadCount > 9 ? '9+' : '${_notificationService.unreadCount}',
                    style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
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
    // Mark all as read when user opens the panel
    _notificationService.markAllAsRead();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        final notifs = _notificationService.notifications;
        return Container(
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
                    onPressed: () {
                      _notificationService.clearAllNotifications();
                      Navigator.pop(context);
                    },
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
              child: notifs.isEmpty
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
                      itemCount: notifs.length,
                      itemBuilder: (context, index) {
                        final n = notifs[index];
                        final isReceived = n.type == NotificationType.incoming;
                        final isFailed = n.type == NotificationType.failed;
                        final isConfirmed = n.type == NotificationType.confirmed ||
                            n.txStatus == TxStatus.confirmed;

                        Color iconColor = isReceived
                            ? const Color(0xFF10B981)
                            : isFailed
                                ? const Color(0xFFEF4444)
                                : isConfirmed
                                    ? const Color(0xFF3B82F6)
                                    : const Color(0xFFF59E0B);

                        IconData iconData = isReceived
                            ? Icons.south_west
                            : isFailed
                                ? Icons.error_outline
                                : isConfirmed
                                    ? Icons.check_circle_outline
                                    : Icons.north_east;

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
                                  color: iconColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  iconData,
                                  color: iconColor,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      n.title,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      n.message,
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.5),
                                        fontSize: 12,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                _formatTimeAgo(n.timestamp),
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
      );
      },
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [const Color(0xFF1E1B4B), const Color(0xFF1A1F2E)]
                : [const Color(0xFFF5F3FF), Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: const Color(0xFF8B5CF6).withOpacity(0.15),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF8B5CF6).withOpacity(isDark ? 0.12 : 0.06),
              blurRadius: 40,
              spreadRadius: -8,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          children: [
            // ── Top section with balance ──
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
              child: Column(
                children: [
                  // Greeting + eye toggle
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFF10B981),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Portfolio Value',
                            style: TextStyle(
                              color: subtextColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          setState(() => _balanceHidden = !_balanceHidden);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: textColor.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            _balanceHidden ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                            color: subtextColor,
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Main Balance
                  _isLoading
                      ? Container(
                          height: 52,
                          width: 200,
                          decoration: BoxDecoration(
                            color: textColor.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(14),
                          ),
                        )
                      : _balanceHidden
                          ? Text(
                              '\u2022\u2022\u2022\u2022\u2022\u2022',
                              style: TextStyle(
                                color: textColor,
                                fontSize: 44,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 6,
                              ),
                            )
                          : AnimatedCurrencyNumber(
                              value: _totalPortfolioValue,
                              formatter: (v) =>
                                  v > 0 ? _formatCurrency(v) : '\$0.00',
                              style: TextStyle(
                                color: textColor,
                                fontSize: 44,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -1.5,
                              ),
                              duration: const Duration(milliseconds: 900),
                              textAlign: TextAlign.start,
                            ),
                  const SizedBox(height: 10),
                  // Percentage chip
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.trending_up_rounded,
                            color: Color(0xFF10B981), size: 14),
                        const SizedBox(width: 4),
                        Text(
                          _totalPortfolioValue > 0 ? '+2.4% today' : 'Start investing',
                          style: const TextStyle(
                            color: Color(0xFF10B981),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // ── Quick Stats Row ──
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withOpacity(0.04)
                    : Colors.black.withOpacity(0.03),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _buildQuickStat(
                      icon: Icons.south_west_rounded,
                      label: 'Received',
                      value: _balanceHidden ? '\u2022\u2022\u2022' : _formatCompactUsd(_totalReceived),
                      color: const Color(0xFF10B981),
                      textColor: textColor,
                      subtextColor: subtextColor,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.transparent, textColor.withOpacity(0.1), Colors.transparent],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                  Expanded(
                    child: _buildQuickStat(
                      icon: Icons.north_east_rounded,
                      label: 'Sent',
                      value: _balanceHidden ? '\u2022\u2022\u2022' : _formatCompactUsd(_totalSent),
                      color: const Color(0xFFEF4444),
                      textColor: textColor,
                      subtextColor: subtextColor,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.transparent, textColor.withOpacity(0.1), Colors.transparent],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                  Expanded(
                    child: _buildQuickStat(
                      icon: Icons.swap_horiz_rounded,
                      label: 'Swapped',
                      value: _balanceHidden ? '\u2022\u2022\u2022' : _formatCompactUsd(_totalSwapped),
                      color: const Color(0xFF8B5CF6),
                      textColor: textColor,
                      subtextColor: subtextColor,
                    ),
                  ),
                ],
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
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            color: textColor,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: subtextColor,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  String _formatCompactUsd(double amount) {
    if (amount >= 1000000) return '\$${(amount / 1000000).toStringAsFixed(1)}M';
    if (amount >= 1000) return '\$${(amount / 1000).toStringAsFixed(1)}K';
    if (amount >= 1) return '\$${amount.toStringAsFixed(2)}';
    if (amount > 0) return '\$${amount.toStringAsFixed(2)}';
    return '\$0';
  }

  Widget _buildActionButtons(bool isDark, Color cardColor, Color textColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: Row(
        children: [
          // Receive button
          Expanded(
            child: _buildActionBtn(
              onTap: () => context.go('/receive'),
              icon: Icons.south_west_rounded,
              label: 'Receive',
              color: const Color(0xFF10B981),
              isDark: isDark,
              cardColor: cardColor,
              textColor: textColor,
            ),
          ),
          const SizedBox(width: 10),
          // Send button
          Expanded(
            child: _buildActionBtn(
              onTap: () => context.go('/send'),
              icon: Icons.north_east_rounded,
              label: 'Send',
              color: const Color(0xFFEF4444),
              isDark: isDark,
              cardColor: cardColor,
              textColor: textColor,
            ),
          ),
          const SizedBox(width: 10),
          // Swap button
          Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                context.go('/swap');
              },
              child: Container(
                height: 54,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF8B5CF6), Color(0xFF7C3AED)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF8B5CF6).withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.swap_horiz_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 6),
                    Text('Swap',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBtn({
    required VoidCallback onTap,
    required IconData icon,
    required String label,
    required Color color,
    required bool isDark,
    required Color cardColor,
    required Color textColor,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        height: 54,
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.25)),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    color: textColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildCoinList(
      bool isDark, Color cardColor, Color textColor, Color subtextColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'My Assets',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    _showPortfolioCharts();
                  },
                  child: Text(
                    'Analytics',
                    style: TextStyle(
                      color: const Color(0xFF8B5CF6),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ..._allCoins.map((coin) {
            return _buildCoinTile(coin, cardColor, textColor, subtextColor);
          }),
        ],
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

            // Coin icon — spins when price changes on auto-refresh
            AnimatedBuilder(
              animation: _coinSpinController,
              builder: (context, child) {
                final shouldSpin = _changedCoins.contains(symbol);
                return Transform.rotate(
                  angle: shouldSpin ? _coinSpinController.value * 2 * math.pi : 0,
                  child: child,
                );
              },
              child: Container(
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
            ), // close AnimatedBuilder
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
                      AnimatedCurrencyNumber(
                        value: price,
                        formatter: _formatPrice,
                        style: TextStyle(
                          color: subtextColor,
                          fontSize: 13,
                        ),
                        duration: const Duration(milliseconds: 700),
                        textAlign: TextAlign.start,
                      ),
                      if (change != 0) ...[
                        const SizedBox(width: 8),
                        RollingDigitText(
                          text:
                              '${isPositive ? '+' : ''}${change.toStringAsFixed(1)}%',
                          style: TextStyle(
                            color: isPositive
                                ? const Color(0xFF10B981)
                                : const Color(0xFFEF4444),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                          duration: const Duration(milliseconds: 500),
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
    // Prevent multiple sheets from opening
    if (_isSheetOpen) return;
    _isSheetOpen = true;
    
    final symbol = coin['symbol'] as String;
    final name = coin['name'] as String;
    final color = coin['color'] as Color;

    final priceInfo = _priceData[symbol];
    final price = priceInfo?['price'] as double? ?? 0.0;
    final change = priceInfo?['change24h'] as double? ?? 0.0;
    final balance = _balances[symbol] ?? 0.0;
    final usdValue = balance * price;
    final isPositive = change >= 0;

    // Get locally stored transactions for this coin (immediately available)
    List<Transaction> localTransactions =
        _recentTransactions.where((tx) => tx.coin == symbol).toList();

    // Store parent context for navigation after sheet closes
    final parentContext = context;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _CoinDetailSheetContent(
        symbol: symbol,
        name: name,
        color: color,
        price: price,
        change: change,
        balance: balance,
        usdValue: usdValue,
        isPositive: isPositive,
        localTransactions: localTransactions,
        walletService: _walletService,
        parentContext: parentContext,
        formatPrice: _formatPrice,
        formatCurrency: _formatCurrency,
        getCoinIcon: _getCoinIcon,
        showTransactionDetailsSheet: _showTransactionDetailsSheet,
      ),
    ).whenComplete(() {
      _isSheetOpen = false;
    });
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

// Animated chart widget for coin detail sheet
class _AnimatedChartWidget extends StatefulWidget {
  final Color color;
  final bool isPositive;
  final double price;
  final double change;

  const _AnimatedChartWidget({
    required this.color,
    required this.isPositive,
    required this.price,
    required this.change,
  });

  @override
  State<_AnimatedChartWidget> createState() => _AnimatedChartWidgetState();
}

class _AnimatedChartWidgetState extends State<_AnimatedChartWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    _animation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return CustomPaint(
          size: const Size(double.infinity, 120),
          painter: _AnimatedChartPainter(
            color: widget.color,
            isPositive: widget.isPositive,
            animationValue: _animation.value,
            price: widget.price,
            change: widget.change,
          ),
        );
      },
    );
  }
}

// Animated chart painter for smooth transitions
class _AnimatedChartPainter extends CustomPainter {
  final Color color;
  final bool isPositive;
  final double animationValue;
  final double price;
  final double change;

  _AnimatedChartPainter({
    required this.color,
    required this.isPositive,
    required this.animationValue,
    required this.price,
    required this.change,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Generate chart data points based on price and change
    final random = math.Random(42);
    final points = <Offset>[];
    final baseY = size.height * 0.5;
    final amplitude = size.height * 0.3;
    final priceVariation = (change / 100.0).clamp(-0.5, 0.5);

    for (int i = 0; i <= 50; i++) {
      final x = (i / 50) * size.width;
      double y;

      if (isPositive) {
        // Upward trend
        y = baseY -
            (i / 50) * amplitude * (1 + priceVariation) +
            random.nextDouble() * 15 -
            7.5;
      } else {
        // Downward trend
        y = baseY +
            (i / 50) * amplitude * (1 + priceVariation.abs()) +
            random.nextDouble() * 15 -
            7.5;
      }

      y = y.clamp(10.0, size.height - 10);
      points.add(Offset(x, y));
    }

    // Apply animation to points
    final animatedPoints = points
        .asMap()
        .entries
        .map((entry) {
          final idx = entry.key;
          final point = entry.value;
          final progress = idx / points.length;
          if (progress <= animationValue) {
            return point;
          } else {
            // Interpolate between starting and ending position
            final startY = size.height * 0.5;
            final ratio = (animationValue / progress).clamp(0, 1);
            return Offset(point.dx, startY + (point.dy - startY) * ratio);
          }
        })
        .toList();

    // Draw the animated line
    final path = Path();
    for (int i = 0; i < animatedPoints.length; i++) {
      if (i == 0) {
        path.moveTo(animatedPoints[i].dx, animatedPoints[i].dy);
      } else {
        final prev = animatedPoints[i - 1];
        final curr = animatedPoints[i];
        final controlX = (prev.dx + curr.dx) / 2;
        path.quadraticBezierTo(controlX, prev.dy, curr.dx, curr.dy);
      }
    }
    canvas.drawPath(path, paint);

    // Draw gradient fill
    final fillPath = Path.from(path);
    fillPath.lineTo(size.width, size.height);
    fillPath.lineTo(0, size.height);
    fillPath.close();

    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        color.withOpacity(0.3 * animationValue),
        color.withOpacity(0.0),
      ],
    );

    final fillPaint = Paint()
      ..shader =
          gradient.createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fillPath, fillPaint);

    // Draw animated current price dot
    if (animatedPoints.isNotEmpty) {
      final lastPoint = animatedPoints.last;
      final dotPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;

      canvas.drawCircle(lastPoint, 4 * animationValue, dotPaint);

      final glowPaint = Paint()
        ..color = color.withOpacity(0.3 * animationValue)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(lastPoint, 8 * animationValue, glowPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
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
// Separate StatefulWidget for coin detail sheet - loads transactions asynchronously
class _CoinDetailSheetContent extends StatefulWidget {
  final String symbol;
  final String name;
  final Color color;
  final double price;
  final double change;
  final double balance;
  final double usdValue;
  final bool isPositive;
  final List<Transaction> localTransactions;
  final WalletService walletService;
  final BuildContext parentContext;
  final String Function(double) formatPrice;
  final String Function(double) formatCurrency;
  final Widget Function(String, Color) getCoinIcon;
  final void Function(BuildContext, Transaction, Color, String, double) showTransactionDetailsSheet;

  const _CoinDetailSheetContent({
    required this.symbol,
    required this.name,
    required this.color,
    required this.price,
    required this.change,
    required this.balance,
    required this.usdValue,
    required this.isPositive,
    required this.localTransactions,
    required this.walletService,
    required this.parentContext,
    required this.formatPrice,
    required this.formatCurrency,
    required this.getCoinIcon,
    required this.showTransactionDetailsSheet,
  });

  @override
  State<_CoinDetailSheetContent> createState() => _CoinDetailSheetContentState();
}

class _CoinDetailSheetContentState extends State<_CoinDetailSheetContent> {
  List<Transaction> _transactions = [];
  bool _isLoadingTransactions = true;
  double _realBalance = 0.0;
  double _realUsdValue = 0.0;
  bool _isLoadingBalance = true;
  bool _balanceUpdated = false;

  @override
  void initState() {
    super.initState();
    _transactions = List.from(widget.localTransactions);
    _realBalance = widget.balance;
    _realUsdValue = widget.usdValue;
    _loadBlockchainTransactions();
    _loadRealBalance();
  }

  Future<void> _loadBlockchainTransactions() async {
    try {
      final storedAddresses = await widget.walletService.getStoredAddresses(widget.symbol);
      final address = storedAddresses.isNotEmpty ? storedAddresses.first : null;
      
      if (address != null && address.isNotEmpty) {
        final blockchainService = BlockchainService();
        final blockchainTx = await blockchainService.getTransactionHistory(widget.symbol, address);
        
        final newTransactions = <Transaction>[];
        for (final tx in blockchainTx) {
          final txHash = tx['hash']?.toString() ?? '';
          if (txHash.isEmpty) continue;

          final rawAmount = (tx['amount'] as num?)?.toDouble() ?? 0.0;
          final amount = rawAmount.abs();

          String txType = (tx['type'] ?? 'unknown').toString().toLowerCase();
          final fromAddr = (tx['fromAddress'] ?? '').toString().toLowerCase();
          final toAddr   = (tx['toAddress']   ?? '').toString().toLowerCase();
          final addrLower = (address ?? '').toLowerCase();

          // Resolve direction: explicit > address comparison > amount sign
          if (txType == 'received') {
            // keep
          } else if (txType == 'sent') {
            // keep
          } else if (toAddr.isNotEmpty && toAddr == addrLower && fromAddr != addrLower) {
            txType = 'received';
          } else if (fromAddr.isNotEmpty && fromAddr == addrLower) {
            txType = 'sent';
          } else if (rawAmount < 0) {
            txType = 'sent';
          } else if (rawAmount > 0) {
            txType = 'received';
          } else {
            txType = 'sent';
          }

          final newTx = Transaction(
            id: txHash,
            txHash: txHash,
            coin: widget.symbol,
            type: txType,
            amount: amount,
            address: txType == 'received'
                ? (tx['fromAddress'] ?? 'Unknown')
                : (tx['toAddress'] ?? 'Unknown'),
            fromAddress: tx['fromAddress']?.toString(),
            toAddress: tx['toAddress']?.toString(),
            timestamp: DateTime.fromMillisecondsSinceEpoch(
              ((tx['timestamp'] as int?) ?? 0) * 1000
            ),
            status: (tx['confirmations'] ?? 0) > 0 ? 'confirmed' : 'pending',
            confirmations: tx['confirmations'] ?? 0,
          );

          // Replace existing entry if blockchain has a definitive type (not unknown).
          // This fixes the bug where a locally-stored 'sent' copy would block a
          // blockchain-confirmed 'received' transaction from showing.
          final existingIdx = _transactions.indexWhere((t) => t.txHash == txHash);
          if (existingIdx >= 0) {
            final existing = _transactions[existingIdx];
            if (existing.type != txType && (txType == 'received' || txType == 'sent')) {
              // Blockchain has authoritative type — replace
              newTransactions.add(newTx);
              _transactions.removeAt(existingIdx);
            }
            // else already correct — skip duplicate
          } else {
            newTransactions.add(newTx);
          }
        }
        
        if (mounted) {
          setState(() {
            _transactions.addAll(newTransactions);
            _transactions.sort((a, b) => b.timestamp.compareTo(a.timestamp));
            _isLoadingTransactions = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoadingTransactions = false;
          });
        }
      }
    } catch (e) {
      print('Error fetching blockchain transactions: $e');
      if (mounted) {
        setState(() {
          _isLoadingTransactions = false;
        });
      }
    }
  }
  
  /// Load real balance from blockchain (like Exodus wallet)
  Future<void> _loadRealBalance() async {
    try {
      final storedAddresses = await widget.walletService.getStoredAddresses(widget.symbol);
      final address = storedAddresses.isNotEmpty ? storedAddresses.first : null;
      
      if (address != null && address.isNotEmpty) {
        print('DEBUG: Fetching real balance for ${widget.symbol} at $address');
        final blockchainService = BlockchainService();
        final realBalance = await blockchainService.getBalance(widget.symbol, address);
        
        // Calculate USD value using current price
        final realUsdValue = realBalance * widget.price;
        
        if (mounted) {
          setState(() {
            _realBalance = realBalance;
            _realUsdValue = realUsdValue;
            _isLoadingBalance = false;
            _balanceUpdated = true;
          });
          
          // Animate the balance update (like YouTube subscriber counter)
          _animateBalanceUpdate();
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoadingBalance = false;
          });
        }
      }
    } catch (e) {
      print('ERROR: Failed to fetch real balance: $e');
      // Keep showing cached balance (like Exodus does when offline)
      if (mounted) {
        setState(() {
          _isLoadingBalance = false;
        });
      }
    }
  }
  
  /// Animate balance update like YouTube subscriber counter
  void _animateBalanceUpdate() {
    // This would typically use an animation controller
    // For now, we just update the state which will trigger a rebuild
    // In a real implementation, you would animate the number change
    print('DEBUG: Balance updated to ${_realBalance.toStringAsFixed(8)} ${widget.symbol}');
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
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
            color: widget.color.withOpacity(0.3),
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
                      widget.color.withOpacity(0.2),
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
                          colors: [widget.color, widget.color.withOpacity(0.7)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: widget.color.withOpacity(0.4),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Center(
                        child: widget.getCoinIcon(widget.symbol, widget.color),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Price
                    AnimatedCurrencyNumber(
                      value: widget.price,
                      formatter: widget.formatPrice,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                      ),
                      duration: const Duration(milliseconds: 800),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),

                    // Name and change
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          widget.name,
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
                            color: widget.isPositive
                                ? const Color(0xFF10B981).withOpacity(0.2)
                                : const Color(0xFFEF4444).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${widget.isPositive ? '+' : ''}${widget.change.toStringAsFixed(2)}%',
                            style: TextStyle(
                              color: widget.isPositive
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
                        _isLoadingBalance
                            ? SizedBox(
                                width: 80,
                                height: 24,
                                child: Center(
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: widget.color,
                                    ),
                                  ),
                                ),
                              )
                            : AnimatedCurrencyNumber(
                                value: _realBalance,
                                formatter: (v) => v.toStringAsFixed(8),
                                style: TextStyle(
                                  color: _balanceUpdated
                                      ? const Color(0xFF10B981)
                                      : widget.color,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                                duration: const Duration(milliseconds: 900),
                                textAlign: TextAlign.center,
                              ),
                        const SizedBox(height: 4),
                        Text(
                          widget.symbol,
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
                        _isLoadingBalance
                            ? SizedBox(
                                width: 80,
                                height: 24,
                                child: Center(
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: widget.color,
                                    ),
                                  ),
                                ),
                              )
                            : AnimatedCurrencyNumber(
                                value: _realUsdValue,
                                formatter: widget.formatCurrency,
                                style: TextStyle(
                                  color: _balanceUpdated
                                      ? const Color(0xFF10B981)
                                      : Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                                duration: const Duration(milliseconds: 900),
                                textAlign: TextAlign.center,
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

              // Time period selector - REMOVED (was using mock data)

              const SizedBox(height: 20),

              // Action buttons
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    _buildActionButton(
                      icon: Icons.download_rounded,
                      label: 'Receive',
                      color: const Color(0xFF10B981),
                      onTap: () {
                        Navigator.pop(context);
                        widget.parentContext.go('/receive', extra: {'coin': widget.symbol});
                      },
                    ),
                    const SizedBox(width: 12),
                    _buildActionButton(
                      icon: Icons.upload_rounded,
                      label: 'Send',
                      color: const Color(0xFFEF4444),
                      onTap: () {
                        Navigator.pop(context);
                        widget.parentContext.go('/send', extra: {'coin': widget.symbol});
                      },
                    ),
                    const SizedBox(width: 12),
                    _buildActionButton(
                      icon: Icons.swap_horiz_rounded,
                      label: 'Swap',
                      color: const Color(0xFF8B5CF6),
                      onTap: () {
                        Navigator.pop(context);
                        widget.parentContext.go('/swap', extra: {'fromCoin': widget.symbol});
                      },
                    ),
                    const SizedBox(width: 12),
                    _buildActionButton(
                      icon: Icons.show_chart_rounded,
                      label: 'Chart',
                      color: const Color(0xFF3B82F6),
                      onTap: () {
                        Navigator.pop(context);
                        widget.parentContext.go('/price-chart', extra: {
                          'coin': widget.symbol,
                          'name': widget.name,
                          'price': widget.price,
                          'change': widget.change,
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
                    const Spacer(),
                    // Loading indicator while fetching transactions
                    if (_isLoadingTransactions)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white54),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Transaction list
              _buildTransactionList(),
              
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTransactionList() {
    if (_transactions.isEmpty && _isLoadingTransactions) {
      return Container(
        padding: const EdgeInsets.all(32),
        child: const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white54),
          ),
        ),
      );
    }

    if (_transactions.isEmpty) {
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

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: _transactions.length,
      itemBuilder: (context, index) {
        final tx = _transactions[index];
        final isReceived = tx.type == 'received';
        final txDate = tx.timestamp;
        final formattedDate =
            '${txDate.hour}:${txDate.minute.toString().padLeft(2, '0')} ${txDate.hour >= 12 ? 'PM' : 'AM'}';

        return GestureDetector(
          onTap: () => widget.showTransactionDetailsSheet(
            context, 
            tx, 
            widget.color, 
            widget.symbol,
            widget.price,
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
                      tx.amount.toStringAsFixed(8),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      widget.formatCurrency(tx.amount * widget.price),
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
    );
  }

  Widget _buildActionButton({
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
}