import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../services/transaction_service.dart';
import '../../../services/notification_service.dart';
import '../../../models/transaction_model.dart';
import 'transaction_detail_page.dart';

class TransactionsPageEnhanced extends ConsumerStatefulWidget {
  const TransactionsPageEnhanced({super.key});

  @override
  ConsumerState<TransactionsPageEnhanced> createState() => _TransactionsPageEnhancedState();
}

class _TransactionsPageEnhancedState extends ConsumerState<TransactionsPageEnhanced>
    with SingleTickerProviderStateMixin {
  final TransactionService _transactionService = TransactionService();
  final NotificationService _notificationService = NotificationService();
  
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  
  List<Transaction> _transactions = [];
  bool _loading = true;
  String _filterType = 'all';
  String _searchQuery = '';
  String _selectedCoin = 'All';

  // Available coins for filter
  final List<String> _availableCoins = ['All', 'BTC', 'ETH', 'BNB', 'SOL', 'XRP', 'TRX', 'LTC', 'DOGE', 'USDT'];

  // Coin colors
  final Map<String, Color> _coinColors = {
    'BTC': const Color(0xFFF7931A),
    'ETH': const Color(0xFF627EEA),
    'BNB': const Color(0xFFF0B90B),
    'USDT': const Color(0xFF26A17B),
    'USDT-ERC20': const Color(0xFF26A17B),
    'USDT-BEP20': const Color(0xFF26A17B),
    'SOL': const Color(0xFF9945FF),
    'XRP': const Color(0xFF23292F),
    'TRX': const Color(0xFFEB0029),
    'LTC': const Color(0xFFBFBBBB),
    'DOGE': const Color(0xFFC2A633),
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadTransactions();
    // Auto-refresh when new notifications arrive (incoming tx, confirmation)
    _notificationService.addListener(_onNotificationUpdate);
  }

  @override
  void dispose() {
    _notificationService.removeListener(_onNotificationUpdate);
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onNotificationUpdate(List<AppNotification> _) {
    // Silently refresh transactions whenever a new notification fires
    // (covers incoming tx detected + confirmation updates)
    if (mounted) _silentRefresh();
  }

  Future<void> _silentRefresh() async {
    try {
      final allTransactions = await _transactionService.getAllTransactions();
      if (mounted) {
        setState(() {
          _transactions = allTransactions;
        });
      }
    } catch (_) {}
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      setState(() {
        switch (_tabController.index) {
          case 0:
            _filterType = 'all';
            break;
          case 1:
            _filterType = 'sent';
            break;
          case 2:
            _filterType = 'received';
            break;
          case 3:
            _filterType = 'swap';
            break;
        }
      });
    }
  }

  Future<void> _loadTransactions() async {
    setState(() => _loading = true);
    try {
      await _transactionService.clearOldTestTransactions();
      final allTransactions = await _transactionService.getAllTransactions();
      
      // Debug: Check which coins have transactions
      final coinCounts = <String, int>{};
      for (final tx in allTransactions) {
        final coin = tx.coin.split('-').first.toUpperCase();
        coinCounts[coin] = (coinCounts[coin] ?? 0) + 1;
      }
      print('DEBUG: Transaction counts by coin: $coinCounts');
      print('DEBUG: Total transactions loaded: ${allTransactions.length}');
      
      setState(() {
        _transactions = allTransactions;
        _loading = false;
      });
    } catch (e) {
      print('DEBUG: Error loading transactions: $e');
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load transactions: $e')),
        );
      }
    }
  }

  /// Pull-to-refresh handler with feedback
  Future<void> _refreshTransactions() async {
    HapticFeedback.mediumImpact();
    try {
      await _transactionService.clearOldTestTransactions();
      final allTransactions = await _transactionService.getAllTransactions();
      
      setState(() {
        _transactions = allTransactions;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text('${allTransactions.length} transactions loaded'),
              ],
            ),
            backgroundColor: const Color(0xFF1A1A2E),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to refresh: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  List<Transaction> get _filteredTransactions {
    List<Transaction> filtered = _transactions;

    // Filter by coin
    if (_selectedCoin != 'All') {
      filtered = filtered.where((tx) {
        final coinBase = tx.coin.split('-').first.toUpperCase();
        final selectedUpper = _selectedCoin.toUpperCase();
        return coinBase == selectedUpper || tx.coin.toUpperCase() == selectedUpper;
      }).toList();
    }

    if (_filterType != 'all') {
      filtered = filtered.where((tx) => tx.type == _filterType).toList();
    }

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((tx) {
        return tx.coin.toLowerCase().contains(query) ||
               tx.address.toLowerCase().contains(query) ||
               (tx.memo?.toLowerCase().contains(query) ?? false) ||
               tx.amount.toString().contains(query);
      }).toList();
    }

    // Sort by date (newest first)
    filtered.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return filtered;
  }

  Map<String, List<Transaction>> _groupByDate(List<Transaction> transactions) {
    final grouped = <String, List<Transaction>>{};
    
    for (final tx in transactions) {
      final date = DateFormat('MMMM d, yyyy').format(tx.timestamp);
      if (!grouped.containsKey(date)) {
        grouped[date] = [];
      }
      grouped[date]!.add(tx);
    }
    
    return grouped;
  }

  Color _getCoinColor(String coin) {
    final baseCoin = coin.split('-').first.toUpperCase();
    return _coinColors[baseCoin] ?? _coinColors[coin] ?? Colors.grey;
  }

  IconData _getTypeIcon(String type) {
    switch (type) {
      case 'sent':
        return Icons.arrow_upward;
      case 'received':
        return Icons.arrow_downward;
      case 'swap':
        return Icons.swap_horiz;
      default:
        return Icons.receipt;
    }
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'sent':
        return Colors.red;
      case 'received':
        return Colors.green;
      case 'swap':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return 'Pending';
      case 'confirmed':
      case 'completed':
      case 'success':
        return 'Confirmed';
      case 'failed':
        return 'Failed';
      default:
        return 'Confirmed';
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'confirmed':
      case 'completed':
      case 'success':
        return Colors.green;
      case 'failed':
        return Colors.red;
      default:
        return Colors.green;
    }
  }

  Widget _buildCoinFilterDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.3)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedCoin,
          icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 20),
          dropdownColor: const Color(0xFF1A1A2E),
          style: const TextStyle(color: Colors.white, fontSize: 14),
          isDense: true,
          items: _availableCoins.map((String coin) {
            return DropdownMenuItem<String>(
              value: coin,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (coin != 'All')
                    Container(
                      width: 18,
                      height: 18,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: _getCoinColor(coin),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Center(
                        child: Text(
                          coin[0],
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    )
                  else
                    Container(
                      width: 18,
                      height: 18,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.all_inclusive, color: Colors.white, size: 12),
                    ),
                  Text(coin),
                ],
              ),
            );
          }).toList(),
          onChanged: (String? newValue) {
            if (newValue != null) {
              setState(() {
                _selectedCoin = newValue;
              });
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            // App Bar
            SliverAppBar(
              expandedHeight: 160,
              floating: false,
              pinned: true,
              backgroundColor: const Color(0xFF1A1A2E),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => context.go('/dashboard'),
              ),
              actions: [
                _buildCoinFilterDropdown(),
                const SizedBox(width: 8),
              ],
              title: innerBoxIsScrolled
                  ? const Text(
                      'Transactions',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    )
                  : null,
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
                    ),
                  ),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 60, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Transaction History',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${_transactions.length} transactions',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: Container(
                  color: const Color(0xFF1A1A2E),
                  child: TabBar(
                    controller: _tabController,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white54,
                    indicatorColor: Colors.blue,
                    indicatorWeight: 3,
                    tabs: const [
                      Tab(text: 'All'),
                      Tab(text: 'Sent'),
                      Tab(text: 'Received'),
                      Tab(text: 'Swaps'),
                    ],
                  ),
                ),
              ),
            ),
          ];
        },
        body: Column(
          children: [
            // Search Bar
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.white,
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _searchQuery = value),
                decoration: InputDecoration(
                  hintText: 'Search transactions...',
                  hintStyle: TextStyle(color: Colors.grey[400]),
                  prefixIcon: Icon(Icons.search, color: Colors.grey[400]),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear, color: Colors.grey[400]),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.grey[100],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),

            // Transaction List
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _refreshTransactions,
                      color: const Color(0xFF1A1A2E),
                      backgroundColor: Colors.white,
                      displacement: 40,
                      strokeWidth: 3,
                      child: _filteredTransactions.isEmpty
                          ? _buildEmptyState()
                          : _buildTransactionList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    // Wrap in ListView to enable pull-to-refresh even when empty
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.5,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.receipt_long_outlined,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  _searchQuery.isNotEmpty
                      ? 'No matching transactions'
                      : 'No transactions yet',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _searchQuery.isNotEmpty
                      ? 'Try a different search term'
                      : 'Pull down to refresh',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[500],
                  ),
                ),
                const SizedBox(height: 24),
                if (_searchQuery.isEmpty)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildQuickAction('Send', Icons.arrow_upward, Colors.red, '/send'),
                      const SizedBox(width: 16),
                      _buildQuickAction('Receive', Icons.arrow_downward, Colors.green, '/receive'),
                      const SizedBox(width: 16),
                      _buildQuickAction('Swap', Icons.swap_horiz, Colors.blue, '/swap'),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickAction(String label, IconData icon, Color color, String route) {
    return GestureDetector(
      onTap: () => context.go(route),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionList() {
    final grouped = _groupByDate(_filteredTransactions);
    
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: grouped.length,
      itemBuilder: (context, index) {
        final date = grouped.keys.elementAt(index);
        final transactions = grouped[date]!;
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                date,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            // Transactions for this date
            ...transactions.map((tx) => _buildTransactionCard(tx)),
          ],
        );
      },
    );
  }

  Widget _buildTransactionCard(Transaction tx) {
    final coinColor = _getCoinColor(tx.coin);
    final typeColor = _getTypeColor(tx.type);
    final isOutgoing = tx.type == 'sent';
    
    return GestureDetector(
      onTap: () => _showTransactionDetails(tx),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Type icon with coin color ring
            Stack(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: typeColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                    border: Border.all(color: coinColor, width: 2),
                  ),
                  child: Icon(
                    _getTypeIcon(tx.type),
                    color: typeColor,
                    size: 22,
                  ),
                ),
                // Coin badge
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: coinColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Text(
                      tx.coin.split('-').first.substring(0, 1),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            
            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        tx.type == 'swap' 
                            ? 'Swap' 
                            : (isOutgoing ? 'Sent' : 'Received'),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        '${isOutgoing ? '-' : '+'}${tx.amount.toStringAsFixed(6)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: isOutgoing ? Colors.red : Colors.green,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatAddress(tx.address),
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      ),
                      Text(
                        tx.coin.split('-').first,
                        style: TextStyle(
                          color: coinColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        DateFormat('HH:mm').format(tx.timestamp),
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 11,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _getStatusColor(tx.status).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _getStatusText(tx.status),
                          style: TextStyle(
                            color: _getStatusColor(tx.status),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatAddress(String address) {
    if (address.length > 20) {
      return '${address.substring(0, 8)}...${address.substring(address.length - 6)}';
    }
    return address;
  }

  void _showTransactionDetails(Transaction tx) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TransactionDetailPage(tx: tx),
      ),
    );
  }


}
