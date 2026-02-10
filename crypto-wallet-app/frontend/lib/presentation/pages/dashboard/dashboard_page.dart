import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/price_service.dart';
import '../../../services/wallet_service.dart';
import '../../../services/notification_service.dart';
import '../../../services/transaction_service.dart';
import '../../../services/preload_service.dart';
import '../../../services/incoming_tx_monitor.dart';
import '../../../models/transaction_model.dart';
import '../../widgets/notification_bell.dart';
import '../../widgets/live_price_chart.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  final PriceService _priceService = PriceService();
  final WalletService _walletService = WalletService();
  final NotificationService _notificationService = NotificationService();
  final TransactionService _transactionService = TransactionService();
  final PreloadService _preloadService = PreloadService();
  final IncomingTxMonitor _incomingTxMonitor = IncomingTxMonitor();
  
  Timer? _debounceTimer;
  DateTime? _lastLoadTime;
  static const _minLoadInterval = Duration(seconds: 5); // Minimum 5 seconds between loads
  
  Map<String, Map<String, dynamic>> _priceData = {};
  Map<String, double> _balances = {}; // Store balances
  Map<String, double> _pendingBalances = {}; // Store pending (unconfirmed) balances
  double _totalPortfolioValue = 0.0;
  double _totalPendingValue = 0.0;
  List<Transaction> _recentTransactions = [];
  bool _isLoading = true;
  bool _refreshing = false;
  String? _errorMessage;
  static bool _hasShownWelcome = false; // Track if welcome notification was shown

  @override
  void initState() {
    super.initState();
    // Load cached data first for instant display
    _loadCachedData().then((_) {
      // Then load fresh data in background
      _loadDashboardData();
    });
    
    // Preload swap data in background for instant swap page load
    _preloadService.preloadSwapData();
    
    // Start monitoring for incoming transactions
    _incomingTxMonitor.startMonitoring();
    
    // Show welcome notification only once per app session
    if (!_hasShownWelcome) {
      _hasShownWelcome = true;
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          _notificationService.showNotification(
            title: 'Welcome to CryptoWallet Pro!',
            message: 'Your wallet is ready to use. Start by adding funds.',
            type: NotificationType.info,
          );
        }
      });
    }
  }

  /// Load cached data for instant display
  Future<void> _loadCachedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedBalances = prefs.getString('cached_balances');
      final cachedPrices = prefs.getString('cached_prices');
      final cachedTotal = prefs.getDouble('cached_total_value');
      
      if (cachedBalances != null && cachedPrices != null && mounted) {
        final balances = Map<String, double>.from(
          (jsonDecode(cachedBalances) as Map).map((k, v) => MapEntry(k.toString(), (v as num).toDouble()))
        );
        final prices = Map<String, Map<String, dynamic>>.from(
          (jsonDecode(cachedPrices) as Map).map((k, v) => MapEntry(k.toString(), Map<String, dynamic>.from(v)))
        );
        
        setState(() {
          _balances = balances;
          _priceData = prices;
          _totalPortfolioValue = cachedTotal ?? 0.0;
          _isLoading = false; // Show cached data immediately
        });
        print('📦 Loaded cached dashboard data');
      }
    } catch (e) {
      print('⚠️ Could not load cached data: $e');
    }
  }

  /// Save data to cache for next app launch
  Future<void> _saveCachedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_balances', jsonEncode(_balances));
      await prefs.setString('cached_prices', jsonEncode(_priceData));
      await prefs.setDouble('cached_total_value', _totalPortfolioValue);
      print('💾 Saved dashboard data to cache');
    } catch (e) {
      print('⚠️ Could not save cached data: $e');
    }
  }

  Future<void> _loadDashboardData() async {
    // Debounce: prevent loading if called too soon
    if (_lastLoadTime != null) {
      final timeSinceLastLoad = DateTime.now().difference(_lastLoadTime!);
      if (timeSinceLastLoad < _minLoadInterval) {
        debugPrint('⏱️ Dashboard load debounced (${timeSinceLastLoad.inSeconds}s < ${_minLoadInterval.inSeconds}s)');
        return;
      }
    }
    
    _lastLoadTime = DateTime.now();
    
    // Only show loading if we don't have cached data
    if (mounted && _balances.isEmpty) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }
    
    try {
      // Load real-time prices with multiple fallbacks
      final symbols = ['BTC', 'ETH', 'BNB', 'SOL', 'XRP', 'DOGE', 'LTC', 'USDT', 'USDC', 'MATIC'];
      Map<String, Map<String, dynamic>> prices = {};
      
      try {
        prices = await _priceService.getPrices(symbols);
        print('✅ Loaded ${prices.length} prices successfully');
      } catch (e) {
        print('⚠️ Price service failed: $e');
        // Use cached prices if available
        if (_priceData.isNotEmpty) {
          prices = _priceData;
          print('📦 Using cached prices');
        }
      }
      
      // Load portfolio data (uses real wallet balances)
      final portfolioData = await _loadPortfolioData(prices);
      
      // Load recent transactions (top 5)
      List<Transaction> recentTxs = [];
      try {
        final allTransactions = await _transactionService.getAllTransactions();
        recentTxs = allTransactions.take(5).toList();
      } catch (e) {
        print('⚠️ Failed to load transactions: $e');
      }
      
      // Calculate pending balances from unconfirmed incoming transactions
      final pendingBalances = <String, double>{};
      double totalPendingValue = 0.0;
      
      for (final tx in recentTxs) {
        if (tx.isPending && tx.isReceived) {
          final coin = tx.coin;
          pendingBalances[coin] = (pendingBalances[coin] ?? 0.0) + tx.amount;
          
          // Calculate USD value
          if (prices.containsKey(coin)) {
            totalPendingValue += tx.amount * (prices[coin]?['price'] ?? 0.0);
          }
        }
      }
      
      if (mounted) {
        setState(() {
          if (prices.isNotEmpty) {
            _priceData = prices;
          }
          _balances = portfolioData['balances']; // Store balances
          _pendingBalances = pendingBalances;
          _totalPortfolioValue = portfolioData['totalValue'];
          _totalPendingValue = totalPendingValue;
          _recentTransactions = recentTxs;
          _isLoading = false;
          _errorMessage = null;
        });
        
        // Save to cache for next app launch
        _saveCachedData();
      }
    } catch (e) {
      print('❌ Dashboard load failed: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          // Only show error if we have no cached data
          if (_priceData.isEmpty && _balances.isEmpty) {
            _errorMessage = e.toString();
          }
        });
      }
    }
  }

  Future<Map<String, dynamic>> _loadPortfolioData(Map<String, Map<String, dynamic>> priceData) async {
    // Get real balances from wallet service
    try {
      final realBalances = await _walletService.getBalances();
      
      double totalValue = 0.0;
      realBalances.forEach((symbol, balance) {
        final coinPrice = priceData[symbol];
        if (coinPrice != null && coinPrice['price'] != null && balance > 0) {
          totalValue += balance * (coinPrice['price'] as double);
        }
      });
      
      return {
        'balances': realBalances,
        'totalValue': totalValue,
      };
    } catch (e) {
      // If wallet service fails, return empty portfolio
      return {
        'balances': <String, double>{},
        'totalValue': 0.0,
      };
    }
  }

  Future<void> _refreshData() async {
    setState(() {
      _refreshing = true;
    });
    
    await _loadDashboardData();
    
    // Reset incoming tx monitor's known balances to avoid false alerts after manual refresh
    await _incomingTxMonitor.resetBalances();
    
    setState(() {
      _refreshing = false;
    });
  }

  // Loading skeleton widget
  Widget _buildLoadingSkeleton({required double height, required double width}) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: _ShimmerEffect(
          child: Container(
            color: Colors.white.withOpacity(0.2),
          ),
        ),
      ),
    );
  }

  String _formatCurrency(double amount) {
    // Format with commas for thousands separator
    final formatter = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    String formattedAmount = amount.toStringAsFixed(2).replaceAllMapped(
      formatter,
      (Match m) => '${m[1]},',
    );
    return '\$$formattedAmount';
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    
    if (diff.inMinutes < 1) {
      return 'Just now';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inDays < 1) {
      return '${diff.inHours}h ago';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // Exit the app instead of going back to onboarding
        SystemNavigator.pop();
        return false;
      },
      child: Scaffold(
        body: SafeArea(
          child: RefreshIndicator(
          onRefresh: _refreshData,
          child: Column(
            children: [
              // === MAIN CONTENT: Scrollable + Takes Available Space ===
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppConstants.defaultPadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header with notification bell
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Welcome Back',
                                style: AppTheme.bodyMedium.copyWith(
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 4),
                            ],
                          ),
                          const NotificationBell(),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // Total Portfolio Value Card - Clean design
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Total Portfolio Value',
                                  style: AppTheme.titleMedium.copyWith(
                                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                _refreshing
                                    ? SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: Theme.of(context).colorScheme.primary,
                                        ),
                                      )
                                    : Icon(
                                        Icons.account_balance_wallet_rounded,
                                        color: Theme.of(context).colorScheme.primary,
                                        size: 24,
                                      ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _formatCurrency(_totalPortfolioValue),
                              style: AppTheme.headlineLarge.copyWith(
                                color: Theme.of(context).colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            // Show pending balance if any
                            if (_totalPendingValue > 0) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Icon(
                                    Icons.hourglass_empty,
                                    size: 16,
                                    color: Colors.orange,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Pending: ${_formatCurrency(_totalPendingValue)}',
                                    style: AppTheme.bodyMedium.copyWith(
                                      color: Colors.orange,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 16),
                            _isLoading
                                ? Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(16.0),
                                      child: CircularProgressIndicator(
                                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                                      ),
                                    ),
                                  )
                                : _errorMessage != null
                                    ? Center(
                                        child: Column(
                                          children: [
                                            const Icon(Icons.error_outline, color: Colors.red, size: 32),
                                            const SizedBox(height: 8),
                                            Text(
                                              'Unable to fetch prices',
                                              style: TextStyle(color: Theme.of(context).colorScheme.error),
                                            ),
                                            TextButton(
                                              onPressed: _loadDashboardData,
                                              child: const Text('Retry'),
                                            ),
                                          ],
                                        ),
                                      )
                                    : SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        child: Row(
                                          children: _buildBalanceDisplays(context),
                                        ),
                                      ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Quick Actions
                      Text(
                        'Quick Actions',
                        style: AppTheme.titleMedium.copyWith(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Action Cards - Responsive grid
                      LayoutBuilder(
                        builder: (context, constraints) {
                          return GridView.count(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 1.5,
                            children: [
                          _buildActionCard(
                            context,
                            icon: Icons.swap_horiz_rounded,
                            title: 'Swap',
                            subtitle: 'Exchange tokens',
                            color: AppTheme.primaryColor,
                            onTap: () {
                              context.go('/swap');
                            },
                          ),
                          _buildActionCard(
                            context,
                            icon: Icons.send_rounded,
                            title: 'Send',
                            subtitle: 'Transfer funds',
                            color: AppTheme.secondaryColor,
                            onTap: () {
                              context.go('/send');
                            },
                          ),
                          _buildActionCard(
                            context,
                            icon: Icons.download_rounded,
                            title: 'Receive',
                            subtitle: 'Get crypto',
                            color: AppTheme.accentColor,
                            onTap: () {
                              context.go('/receive');
                            },
                          ),
                          _buildActionCard(
                            context,
                            icon: Icons.history_rounded,
                            title: 'History',
                            subtitle: 'Transactions',
                            color: AppTheme.successColor,
                            onTap: () {
                              context.go('/transactions');
                            },
                          ),
                          _buildActionCard(
                            context,
                            icon: Icons.account_balance_wallet_rounded,
                            title: 'My Coins',
                            subtitle: 'View portfolio',
                            color: Colors.teal,
                            onTap: () {
                              context.go('/coins');
                            },
                          ),
                          _buildActionCard(
                            context,
                            icon: Icons.security_rounded,
                            title: 'Multi-Sig',
                            subtitle: 'Manage wallet',
                            color: Colors.deepPurple,
                            onTap: () {
                              context.push('/multisig-management');
                            },
                          ),
                          _buildActionCard(
                            context,
                            icon: Icons.add_moderator_rounded,
                            title: 'Create Multi-Sig',
                            subtitle: 'New wallet',
                            color: Colors.indigo,
                            onTap: () {
                              context.push('/create-multisig');
                            },
                          ),
                        ],
                      );
                        },
                      ),

                      const SizedBox(height: 32),

                      // Recent Activity Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Recent Activity',
                            style: AppTheme.titleMedium.copyWith(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              context.go('/transactions');
                            },
                            child: const Text('View All'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Recent Activity List or Empty State
                      _isLoading
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32.0),
                                child: CircularProgressIndicator(),
                              ),
                            )
                          : _recentTransactions.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.receipt_long,
                                    size: 64,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withAlpha((0.3 * 255).round()),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No Recent Activity',
                                    style: AppTheme.titleMedium.copyWith(
                                      color: Theme.of(context).colorScheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Your transactions will appear here',
                                    style: AppTheme.bodyMedium.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withAlpha((0.6 * 255).round()),
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _recentTransactions.length,
                              itemBuilder: (context, index) {
                                final tx = _recentTransactions[index];
                                final isReceived = tx.type == 'received';
                                
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.surface,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: ListTile(
                                    leading: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: isReceived
                                            ? Colors.green.withOpacity(0.1)
                                            : Colors.red.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(
                                        isReceived ? Icons.arrow_downward : Icons.arrow_upward,
                                        color: isReceived ? Colors.green : Colors.red,
                                        size: 20,
                                      ),
                                    ),
                                    title: Text(
                                      '${isReceived ? "Received" : "Sent"} ${tx.coin}',
                                      style: AppTheme.bodyLarge.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: Theme.of(context).colorScheme.onSurface,
                                      ),
                                    ),
                                    subtitle: Text(
                                      _formatDate(tx.timestamp),
                                      style: AppTheme.bodySmall.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withAlpha((0.6 * 255).round()),
                                      ),
                                    ),
                                    trailing: Text(
                                      '${isReceived ? "+" : "-"}${tx.amount.toStringAsFixed(8)} ${tx.coin}',
                                      style: AppTheme.bodyLarge.copyWith(
                                        color: isReceived ? Colors.green : Colors.red,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    onTap: () {
                                      context.go('/transactions');
                                    },
                                  ),
                                );
                              },
                            ),

                      // Extra bottom padding so content isn't hidden under bottom nav
                      const SizedBox(height: 120),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      // Optional: Add bottom navigation bar here if needed
      // bottomNavigationBar: YourBottomNavBar(),
      ),
    );
  }

  // Build balance displays showing coins user actually owns
  List<Widget> _buildBalanceDisplays(BuildContext context) {
    final widgets = <Widget>[];
    
    // Get coins with balance > 0, sorted by USD value
    final coinsWithBalance = _balances.entries
        .where((e) => e.value > 0)
        .toList()
      ..sort((a, b) {
        final aValue = a.value * (_priceData[a.key]?['price'] ?? 0);
        final bValue = b.value * (_priceData[b.key]?['price'] ?? 0);
        return bValue.compareTo(aValue);
      });
    
    if (coinsWithBalance.isEmpty) {
      // Show market prices if no balances
      return [
        _buildCoinPriceDisplay(
          context,
          symbol: 'BTC',
          price: _formatCurrency(_priceData['BTC']?['price'] ?? 0),
          change: _priceData['BTC']?['change24h'] ?? 0.0,
        ),
        const SizedBox(width: 16),
        _buildCoinPriceDisplay(
          context,
          symbol: 'ETH',
          price: _formatCurrency(_priceData['ETH']?['price'] ?? 0),
          change: _priceData['ETH']?['change24h'] ?? 0.0,
        ),
        const SizedBox(width: 16),
        _buildCoinPriceDisplay(
          context,
          symbol: 'BNB',
          price: _formatCurrency(_priceData['BNB']?['price'] ?? 0),
          change: _priceData['BNB']?['change24h'] ?? 0.0,
        ),
      ];
    }
    
    // Show coins with balance (top 4)
    for (int i = 0; i < coinsWithBalance.length && i < 4; i++) {
      final coin = coinsWithBalance[i];
      final balance = coin.value;
      final price = _priceData[coin.key]?['price'] ?? 0.0;
      final usdValue = balance * price;
      final change = _priceData[coin.key]?['change24h'] ?? 0.0;
      
      if (i > 0) widgets.add(const SizedBox(width: 16));
      
      widgets.add(
        _buildCoinBalanceDisplay(
          context,
          symbol: coin.key,
          balance: balance,
          usdValue: usdValue,
          change: change,
        ),
      );
    }
    
    return widgets;
  }

  // Display a coin with its balance and USD value
  Widget _buildCoinBalanceDisplay(
    BuildContext context, {
    required String symbol,
    required double balance,
    required double usdValue,
    required double change,
  }) {
    // Format balance based on coin type
    String formattedBalance;
    if (symbol == 'USDT' || symbol == 'USDC' || symbol == 'DAI') {
      formattedBalance = '${balance.toStringAsFixed(2)} $symbol';
    } else if (balance < 0.0001) {
      formattedBalance = '${balance.toStringAsFixed(8)} $symbol';
    } else if (balance < 1) {
      formattedBalance = '${balance.toStringAsFixed(6)} $symbol';
    } else {
      formattedBalance = '${balance.toStringAsFixed(4)} $symbol';
    }
    
    return GestureDetector(
      onTap: () {
        _showCoinDetailsBottomSheet(context, symbol);
      },
      child: SizedBox(
        width: 110,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  symbol,
                  style: AppTheme.bodySmall.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer.withOpacity(0.8),
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(width: 4),
                if (change != 0.0)
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          change > 0 ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                          color: change > 0 ? Colors.lightGreen : Colors.redAccent,
                          size: 14,
                        ),
                        Flexible(
                          child: Text(
                            '${change > 0 ? '+' : ''}${change.toStringAsFixed(1)}%',
                            style: AppTheme.bodySmall.copyWith(
                              color: change > 0 ? Colors.lightGreen : Colors.redAccent,
                              fontWeight: FontWeight.w500,
                              fontSize: 9,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              _formatCurrency(usdValue),
              style: AppTheme.bodyMedium.copyWith(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              formattedBalance,
              style: AppTheme.bodySmall.copyWith(
                color: Theme.of(context).colorScheme.onPrimaryContainer.withOpacity(0.6),
                fontSize: 9,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  void _showCoinDetailsBottomSheet(BuildContext context, String symbol) {
    // Find the coin in our balances
    final coinBalance = _balances[symbol] ?? 0.0;
    final priceInfo = _priceData[symbol];
    final currentPrice = priceInfo?['price'] ?? 0.0;
    final change = priceInfo?['change24h'] ?? 0.0;
    final usdValue = coinBalance * currentPrice;

    // Get coin color based on symbol
    Color coinColor = _getCoinColor(symbol);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (BuildContext context, ScrollController scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0D1421),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: Column(
              children: [
                // Handle
                Container(
                  margin: const EdgeInsets.only(top: 8, bottom: 16),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                
                // Coin header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: coinColor.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          _getCoinIcon(symbol),
                          color: coinColor,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _getCoinName(symbol),
                              style: AppTheme.titleLarge.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              symbol,
                              style: AppTheme.bodyMedium.copyWith(
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '\$${currentPrice.toStringAsFixed(2)}',
                            style: AppTheme.titleLarge.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${change > 0 ? '+' : ''}${change.toStringAsFixed(2)}%',
                            style: AppTheme.bodyMedium.copyWith(
                              color: change >= 0 ? Colors.lightGreen : Colors.red,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Balance info
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1F2E),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Your Balance',
                              style: AppTheme.bodyMedium.copyWith(
                                color: Colors.white70,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${coinBalance.toStringAsFixed(8)} $symbol',
                              style: AppTheme.titleLarge.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'USD Value',
                              style: AppTheme.bodyMedium.copyWith(
                                color: Colors.white70,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _formatCurrency(usdValue),
                              style: AppTheme.titleLarge.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Live chart
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    height: 200,
                    child: LivePriceChart(
                      coinSymbol: symbol,
                      chartColor: coinColor,
                      initialPrice: currentPrice,
                      change24h: change,
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Action buttons
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            context.push('/send', extra: {'initialCoin': symbol});
                          },
                          icon: const Icon(Icons.send_rounded, size: 18),
                          label: const Text('Send'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: coinColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            context.push('/receive', extra: {'initialCoin': symbol});
                          },
                          icon: const Icon(Icons.qr_code_rounded, size: 18),
                          label: const Text('Receive'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1A1F2E),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            side: BorderSide(color: coinColor),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
  }

  // Helper methods for coin details
  Color _getCoinColor(String symbol) {
    switch (symbol.toUpperCase()) {
      case 'BTC':
        return const Color(0xFFF7931A); // Bitcoin orange
      case 'ETH':
        return const Color(0xFF627EEA); // Ethereum blue
      case 'BNB':
        return const Color(0xFFF3BA2F); // BNB yellow
      case 'SOL':
        return const Color(0xFF00FFA3); // Solana green
      case 'USDT':
        return const Color(0xFF26A17B); // Tether green
      case 'XRP':
        return const Color(0xFF00AAE4); // Ripple blue
      case 'DOGE':
        return const Color(0xFFC2A633); // Doge yellow
      case 'LTC':
        return const Color(0xFFBFBBBB); // Litecoin gray
      case 'ADA':
        return const Color(0xFF0033AD); // Cardano blue
      case 'DOT':
        return const Color(0xFFE6007A); // Polkadot pink
      default:
        return const Color(0xFF8B5CF6); // Default purple
    }
  }

  IconData _getCoinIcon(String symbol) {
    switch (symbol.toUpperCase()) {
      case 'BTC':
        return Icons.currency_bitcoin;
      case 'ETH':
        return Icons.diamond_outlined;
      case 'BNB':
        return Icons.hexagon_outlined;
      case 'SOL':
        return Icons.sunny;
      case 'USDT':
      case 'USDC':
        return Icons.attach_money;
      case 'XRP':
        return Icons.water_drop_outlined;
      case 'DOGE':
        return Icons.pets;
      case 'LTC':
        return Icons.bolt;
      case 'ADA':
        return Icons.auto_graph;
      case 'DOT':
        return Icons.linear_scale;
      default:
        return Icons.circle;
    }
  }

  String _getCoinName(String symbol) {
    switch (symbol.toUpperCase()) {
      case 'BTC':
        return 'Bitcoin';
      case 'ETH':
        return 'Ethereum';
      case 'BNB':
        return 'BNB';
      case 'SOL':
        return 'Solana';
      case 'USDT':
        return 'Tether';
      case 'XRP':
        return 'XRP';
      case 'DOGE':
        return 'Dogecoin';
      case 'LTC':
        return 'Litecoin';
      case 'ADA':
        return 'Cardano';
      case 'DOT':
        return 'Polkadot';
      default:
        return symbol;
    }
  }

  Widget _buildCoinPriceDisplay(
    BuildContext context, {
    required String symbol,
    required String price,
    required double change,
  }) {
    return SizedBox(
      width: 100,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                symbol,
                style: AppTheme.bodySmall.copyWith(
                  color: Theme.of(context).colorScheme.onPrimaryContainer.withOpacity(0.8),
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
              const SizedBox(width: 4),
              if (change != 0.0)
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        change > 0 ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                        color: change > 0 ? Colors.lightGreen : Colors.redAccent,
                        size: 14,
                      ),
                      Flexible(
                        child: Text(
                          '${change > 0 ? '+' : ''}${change.toStringAsFixed(1)}%',
                          style: AppTheme.bodySmall.copyWith(
                            color: change > 0 ? Colors.lightGreen : Colors.redAccent,
                            fontWeight: FontWeight.w500,
                            fontSize: 9,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            price,
            style: AppTheme.bodyMedium.copyWith(
              color: Theme.of(context).colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: 20,
                ),
              ),
              const SizedBox(height: 6),
              Flexible(
                child: Text(
                  title,
                  style: AppTheme.titleSmall.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Flexible(
                child: Text(
                  subtitle,
                  style: AppTheme.bodySmall.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Shimmer effect widget for loading state
class _ShimmerEffect extends StatefulWidget {
  final Widget child;

  const _ShimmerEffect({required this.child});

  @override
  State<_ShimmerEffect> createState() => _ShimmerEffectState();
}

class _ShimmerEffectState extends State<_ShimmerEffect>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    
    _animation = Tween<double>(begin: -2, end: 2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: const [
                Colors.transparent,
                Colors.white38,
                Colors.transparent,
              ],
              stops: [
                (_animation.value - 0.3).clamp(0.0, 1.0),
                _animation.value.clamp(0.0, 1.0),
                (_animation.value + 0.3).clamp(0.0, 1.0),
              ],
            ).createShader(bounds);
          },
          child: widget.child,
        );
      },
    );
  }
}
