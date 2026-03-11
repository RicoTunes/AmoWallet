import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/transaction_model.dart';
import '../../../services/transaction_service.dart';
import '../../../services/price_conversion_service.dart';
import '../../../services/wallet_service.dart';

class TransactionsPage extends ConsumerStatefulWidget {
  const TransactionsPage({super.key});

  @override
  ConsumerState<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends ConsumerState<TransactionsPage> {
  final TransactionService _transactionService = TransactionService();
  final PriceConversionService _priceService = PriceConversionService();
  final WalletService _walletService = WalletService();
  List<Transaction> _transactions = [];
  bool _loading = true;
  String _filterType = 'all'; // 'all', 'sent', 'received', 'swap'
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  Future<void> _loadTransactions() async {
    setState(() => _loading = true);
    try {
      // Clean up old test transactions first (keep only last 7 days)
      await _transactionService.clearOldTestTransactions();
      
      final allTransactions = await _transactionService.getAllTransactions();
      setState(() {
        _transactions = allTransactions;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load transactions: $e')),
      );
    }
  }

  List<Transaction> get _filteredTransactions {
    List<Transaction> filtered = _transactions;

    // Apply type filter
    if (_filterType != 'all') {
      filtered = filtered.where((tx) => tx.type == _filterType).toList();
    }

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((tx) {
        return tx.coin.toLowerCase().contains(query) ||
               tx.address.toLowerCase().contains(query) ||
               (tx.memo?.toLowerCase().contains(query) ?? false) ||
               tx.amount.toString().contains(query);
      }).toList();
    }

    return filtered;
  }

  /// Show swap history dialog with real swap transactions
  void _showSwapHistory() async {
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final swapHistory = await _walletService.getSwapHistory();
      if (mounted) Navigator.pop(context); // Close loading

      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) {
          return DraggableScrollableSheet(
            initialChildSize: 0.7,
            minChildSize: 0.4,
            maxChildSize: 0.9,
            expand: false,
            builder: (_, scrollController) {
              return Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle bar
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    // Title
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.swap_horiz, color: Colors.blue, size: 24),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Swap History',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        Text(
                          '${swapHistory.length} swaps',
                          style: TextStyle(color: Colors.grey[600], fontSize: 14),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    // Swap list
                    Expanded(
                      child: swapHistory.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.swap_horiz, size: 64, color: Colors.grey[300]),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No swap history yet',
                                    style: TextStyle(color: Colors.grey[600], fontSize: 16),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Your completed swaps will appear here',
                                    style: TextStyle(color: Colors.grey[400], fontSize: 14),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              controller: scrollController,
                              itemCount: swapHistory.length,
                              itemBuilder: (ctx, index) {
                                final swap = swapHistory[index];
                                final fromCoin = swap['fromCoin'] ?? 'Unknown';
                                final toCoin = swap['toCoin'] ?? 'Unknown';
                                final fromAmount = swap['fromAmount'] ?? 0.0;
                                final toAmount = swap['toAmount'] ?? 0.0;
                                final fee = swap['fee'] ?? 0.0;
                                final timestamp = swap['timestamp'] ?? '';
                                
                                // Parse timestamp
                                String formattedDate = 'Unknown date';
                                try {
                                  final dt = DateTime.parse(timestamp);
                                  formattedDate = '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                                } catch (_) {}

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.withOpacity(0.05),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: Colors.grey.withOpacity(0.1)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Swap direction
                                      Row(
                                        children: [
                                          _buildCoinBadge(fromCoin),
                                          const SizedBox(width: 8),
                                          const Icon(Icons.arrow_forward, size: 16, color: Colors.grey),
                                          const SizedBox(width: 8),
                                          _buildCoinBadge(toCoin),
                                          const Spacer(),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.green.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: const Text(
                                              'Completed',
                                              style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.w600),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      // Amounts
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text('Sent', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                                              Text(
                                                '-${_formatAmount(fromAmount)} $fromCoin',
                                                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
                                              ),
                                            ],
                                          ),
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            children: [
                                              Text('Received', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                                              Text(
                                                '+${_formatAmount(toAmount)} $toCoin',
                                                style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w600),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      // Fee and date
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            'Fee: ${_formatAmount(fee)} $fromCoin',
                                            style: TextStyle(color: Colors.grey[500], fontSize: 12),
                                          ),
                                          Text(
                                            formattedDate,
                                            style: TextStyle(color: Colors.grey[500], fontSize: 12),
                                          ),
                                        ],
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
        },
      );
    } catch (e) {
      if (mounted) Navigator.pop(context); // Close loading
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load swap history: $e')),
        );
      }
    }
  }

  Widget _buildCoinBadge(String coin) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _getCoinColor(coin).withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        coin,
        style: TextStyle(
          color: _getCoinColor(coin),
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
    );
  }

  Color _getCoinColor(String coin) {
    switch (coin.toUpperCase()) {
      case 'BTC': return Colors.orange;
      case 'ETH': return Colors.blue;
      case 'USDT': return Colors.green;
      case 'BNB': return Colors.amber;
      case 'SOL': return Colors.purple;
      case 'XRP': return Colors.blueGrey;
      case 'DOGE': return Colors.brown;
      case 'LTC': return Colors.grey;
      default: return Colors.blue;
    }
  }

  String _formatAmount(dynamic amount) {
    if (amount is double) {
      if (amount < 0.0001) return amount.toStringAsFixed(8);
      if (amount < 1) return amount.toStringAsFixed(6);
      return amount.toStringAsFixed(4);
    }
    return amount.toString();
  }

  void _showFilterBottomSheet() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Filter Transactions',
                style: AppTheme.titleMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              ...['all', 'sent', 'received', 'swap'].map((type) {
                return ListTile(
                  leading: Radio<String>(
                    value: type,
                    groupValue: _filterType,
                    onChanged: (value) {
                      setState(() => _filterType = value!);
                      Navigator.pop(context);
                    },
                  ),
                  title: Text(
                    type == 'all' ? 'All Transactions' :
                    type == 'sent' ? 'Sent Only' :
                    type == 'received' ? 'Received Only' : 'Swap Only',
                    style: AppTheme.bodyMedium,
                  ),
                  onTap: () {
                    setState(() => _filterType = type);
                    Navigator.pop(context);
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  void _showTransactionDetails(Transaction transaction) {
    // Debug: Check address values
    print('Transaction Details - isSwap: ${transaction.isSwap}, fromAddress: ${transaction.fromAddress}, toAddress: ${transaction.toAddress}');
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Transaction Details',
                    style: AppTheme.titleMedium.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              // Transaction Type
              _buildDetailRow('Type', transaction.type.toUpperCase()),
              const SizedBox(height: 8),
              
              // Swap details if it's a swap
              if (transaction.isSwap) ...[
                _buildDetailRow(
                  'Swap Details',
                  '${transaction.fromAmount} ${transaction.fromCoin} → ${transaction.toAmount} ${transaction.toCoin}'
                ),
                const SizedBox(height: 8),
                if (transaction.exchangeRate != null)
                  _buildDetailRow(
                    'Exchange Rate',
                    '1 ${transaction.fromCoin} = ${transaction.exchangeRate!.toStringAsFixed(6)} ${transaction.toCoin}'
                  ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 8),
              
              // Coin
              _buildDetailRow('Coin', transaction.coin),
              const SizedBox(height: 8),
              
              // Amount
              _buildDetailRow(
                'Amount', 
                '${transaction.displayAmount.abs()} ${transaction.coin}',
              ),
              const SizedBox(height: 8),
              
              // From Address (Sender)
              if (!transaction.isSwap && transaction.fromAddress != null)
                _buildDetailRow(
                  'From Address',
                  transaction.fromAddress!,
                ),
              if (!transaction.isSwap && transaction.fromAddress != null)
                const SizedBox(height: 8),
              
              // To Address (Receiver)
              if (!transaction.isSwap && transaction.toAddress != null)
                _buildDetailRow(
                  'To Address',
                  transaction.toAddress!,
                ),
              if (!transaction.isSwap && transaction.toAddress != null)
                const SizedBox(height: 8),
              
              // Date & Time
              _buildDetailRow(
                'Date & Time',
                '${transaction.timestamp.toLocal()}',
              ),
              const SizedBox(height: 8),
              
              // Status
              _buildDetailRow('Status', transaction.status.toUpperCase()),
              const SizedBox(height: 8),
              
              // Confirmations (for pending/unconfirmed transactions)
              if (transaction.confirmations != null) ...[
                _buildDetailRow(
                  'Confirmations',
                  transaction.isPending 
                    ? '⏳ ${transaction.confirmations}/6 (Pending)' 
                    : '✅ ${transaction.confirmations} (Confirmed)',
                ),
                const SizedBox(height: 8),
              ],
              
              // Transaction Hash
              if (transaction.txHash != null) ...[
                _buildDetailRow('Transaction Hash', transaction.txHash!),
                const SizedBox(height: 8),
              ],
              
              // Fee
              if (transaction.fee != null) ...[
                _buildDetailRow('Fee', '${transaction.fee} ${transaction.coin}'),
                const SizedBox(height: 8),
              ],
              
              // Memo
              if (transaction.memo != null) ...[
                _buildDetailRow('Memo', transaction.memo!),
                const SizedBox(height: 8),
              ],
              
              const SizedBox(height: 24),
              
              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _copyToClipboard(transaction.displayAddress);
                      },
                      child: const Text('Copy Address'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        context.go('/send', extra: {
                          'coin': transaction.coin,
                          'address': transaction.displayAddress,
                        });
                      },
                      child: Text(transaction.isSent ? 'Send Again' : 'Send'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: AppTheme.bodyMedium.copyWith(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface.withAlpha(180),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: AppTheme.bodyMedium,
          ),
        ),
      ],
    );
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BackButtonListener(
      onBackButtonPressed: () async {
        context.go('/dashboard');
        return true;
      },
      child: PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) {
          context.go('/dashboard');
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/dashboard'),
          ),
          title: const Text('Transaction History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            onPressed: _showSwapHistory,
            tooltip: 'Swap History',
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterBottomSheet,
            tooltip: 'Filter',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadTransactions,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(AppConstants.defaultPadding),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search transactions...',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value);
              },
            ),
          ),

          // Filter Chips
          SizedBox(
            height: 50,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _buildFilterChip('All', 'all'),
                const SizedBox(width: 8),
                _buildFilterChip('Sent', 'sent'),
                const SizedBox(width: 8),
                _buildFilterChip('Received', 'received'),
                const SizedBox(width: 8),
                _buildFilterChip('Swap', 'swap'),
              ],
            ),
          ),

          // Transaction Count
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_filteredTransactions.length} transactions',
                  style: AppTheme.bodyMedium.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withAlpha(150),
                  ),
                ),
                if (_filterType != 'all')
                  TextButton(
                    onPressed: () => setState(() => _filterType = 'all'),
                    child: const Text('Clear Filter'),
                  ),
              ],
            ),
          ),

          // Transactions List
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filteredTransactions.isEmpty
                    ? _buildEmptyState()
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _filteredTransactions.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final transaction = _filteredTransactions[index];
                          return _buildTransactionCard(transaction);
                        },
                      ),
          ),
        ],
      ),
    ),
    ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _filterType == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() => _filterType = value);
      },
    );
  }

  Widget _buildTransactionCard(Transaction transaction) {
    return GestureDetector(
      onTap: () => _showTransactionDetails(transaction),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Icon
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: transaction.isSent
                      ? Colors.red.withAlpha(30)
                      : transaction.isReceived
                          ? Colors.green.withAlpha(30)
                          : Colors.blue.withAlpha(30),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  transaction.isSent
                      ? Icons.arrow_upward
                      : transaction.isReceived
                          ? Icons.arrow_downward
                          : Icons.swap_horiz,
                  color: transaction.isSent
                      ? Colors.red
                      : transaction.isReceived
                          ? Colors.green
                          : Colors.blue,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              // Content - Expanded to take remaining space
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    Text(
                      transaction.isSwap
                          ? 'Swap: ${transaction.fromCoin} → ${transaction.toCoin}'
                          : '${transaction.displayLabel} ${transaction.displayAddress.length > 8 ? transaction.displayAddress.substring(0, 8) : transaction.displayAddress}...',
                      style: AppTheme.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // Amount text with crypto value
                    Text(
                      transaction.isSwap
                          ? '${transaction.fromAmount} ${transaction.fromCoin} → ${transaction.toAmount} ${transaction.toCoin}'
                          : '${transaction.amount} ${transaction.coin}',
                      style: AppTheme.bodyMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // USD value
                    const SizedBox(height: 2),
                    FutureBuilder<double>(
                      future: _priceService.convertToUSD(
                        transaction.isSwap ? (transaction.fromCoin ?? transaction.coin) : transaction.coin,
                        transaction.isSwap ? (transaction.fromAmount ?? 0.0) : transaction.amount,
                      ),
                      builder: (context, snapshot) {
                        final usdValue = snapshot.data ?? 0.0;
                        return Text(
                          _priceService.formatUSD(usdValue),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        );
                      },
                    ),
                    // PENDING badge on separate line if needed
                    if (transaction.isPending) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.withAlpha(30),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.orange, width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.hourglass_empty, size: 10, color: Colors.orange),
                            const SizedBox(width: 3),
                            Text(
                              'PENDING',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    // Date
                    Text(
                      _formatDate(transaction.timestamp),
                      style: AppTheme.bodySmall.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withAlpha(150),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Amount on right - fixed width
              SizedBox(
                width: 70,
                child: Text(
                  transaction.isSwap
                      ? '+${transaction.toAmount}'
                      : transaction.isSent
                          ? '-${transaction.amount}'
                          : '+${transaction.amount}',
                  style: AppTheme.bodyLarge.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: transaction.isSwap
                        ? Colors.blue
                        : transaction.isSent
                            ? Colors.red
                            : Colors.green,
                  ),
                  textAlign: TextAlign.right,
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

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.receipt_long,
            size: 64,
            color: Theme.of(context).colorScheme.onSurface.withAlpha(100),
          ),
          const SizedBox(height: 16),
          Text(
            'No Transactions Found',
            style: AppTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            _filterType == 'all'
                ? 'Your transaction history will appear here'
                : _filterType == 'swap'
                    ? 'No swap transactions found'
                    : 'No $_filterType transactions found',
            style: AppTheme.bodyMedium.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withAlpha(150),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => context.go('/send'),
            child: const Text('Send Your First Transaction'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final transactionDate = DateTime(date.year, date.month, date.day);

    if (transactionDate == today) {
      return 'Today, ${_formatTime(date)}';
    } else if (transactionDate == yesterday) {
      return 'Yesterday, ${_formatTime(date)}';
    } else {
      return '${date.month}/${date.day}/${date.year}, ${_formatTime(date)}';
    }
  }

  String _formatTime(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}