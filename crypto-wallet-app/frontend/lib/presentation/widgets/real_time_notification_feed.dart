import 'package:flutter/material.dart';
import 'dart:async';
import '../../../models/transaction_model.dart';
import '../../../services/transaction_service.dart';
import '../../../services/price_conversion_service.dart';

/// Real-time notification feed showing pending transactions and status updates
class RealTimeNotificationFeed extends StatefulWidget {
  final int maxNotifications;
  final Duration refreshInterval;

  const RealTimeNotificationFeed({
    super.key,
    this.maxNotifications = 5,
    this.refreshInterval = const Duration(seconds: 10),
  });

  @override
  State<RealTimeNotificationFeed> createState() =>
      _RealTimeNotificationFeedState();
}

class _RealTimeNotificationFeedState extends State<RealTimeNotificationFeed> {
  final TransactionService _transactionService = TransactionService();
  final PriceConversionService _priceService = PriceConversionService();
  
  late Timer _refreshTimer;
  List<Transaction> _notifications = [];
  final bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
    _refreshTimer = Timer.periodic(widget.refreshInterval, (_) => _loadNotifications());
  }

  @override
  void dispose() {
    _refreshTimer.cancel();
    super.dispose();
  }

  Future<void> _loadNotifications() async {
    try {
      final allTransactions = await _transactionService.getAllTransactions();
      
      // Sort by date descending and get pending/recent ones
      allTransactions.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      
      final notifications = allTransactions.where((tx) {
        // Show pending, recently completed, and swaps
        return tx.status == 'pending' ||
               tx.status == 'completed' ||
               tx.type == 'swap' ||
               DateTime.now().difference(tx.timestamp).inMinutes < 5;
      }).toList();

      if (mounted) {
        setState(() {
          _notifications = notifications.take(widget.maxNotifications).toList();
        });
      }
    } catch (e) {
      print('Error loading notifications: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_notifications.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Center(
          child: Text(
            'No recent activity',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 14,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.notifications_active, color: Colors.blue.shade600, size: 18),
              const SizedBox(width: 8),
              Text(
                'Live Activity',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
              const Spacer(),
              if (_notifications.any((n) => n.status == 'pending'))
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${_notifications.where((n) => n.status == 'pending').length} Pending',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange.shade700,
                    ),
                  ),
                ),
            ],
          ),
        ),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _notifications.length,
          itemBuilder: (context, index) => _NotificationCard(
            transaction: _notifications[index],
            priceService: _priceService,
            index: index,
          ),
        ),
      ],
    );
  }
}

class _NotificationCard extends StatefulWidget {
  final Transaction transaction;
  final PriceConversionService priceService;
  final int index;

  const _NotificationCard({
    required this.transaction,
    required this.priceService,
    required this.index,
  });

  @override
  State<_NotificationCard> createState() => _NotificationCardState();
}

class _NotificationCardState extends State<_NotificationCard> {
  late Future<double> _usdValueFuture;

  @override
  void initState() {
    super.initState();
    _usdValueFuture = widget.priceService.convertToUSD(
      widget.transaction.coin,
      widget.transaction.amount,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tx = widget.transaction;
    final isSwap = tx.type == 'swap';
    final isSent = tx.type == 'sent';
    final isPending = tx.status == 'pending';
    final isCompleted = tx.status == 'completed';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _getBorderColor(tx.status, tx.type),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.08),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Status indicator bar on left
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(
              width: 4,
              decoration: BoxDecoration(
                color: _getStatusColor(tx.status),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(10),
                  bottomLeft: Radius.circular(10),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                // Main content row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Transaction icon
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _getIconBackgroundColor(tx),
                      ),
                      child: Center(
                        child: Icon(
                          _getTransactionIcon(tx),
                          color: _getIconColor(tx),
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Transaction details
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getTransactionLabel(tx),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _getTransactionSubtitle(tx),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Amount and status
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        FutureBuilder<double>(
                          future: _usdValueFuture,
                          builder: (context, snapshot) {
                            final usdValue = snapshot.data ?? 0.0;
                            return Text(
                              widget.priceService.formatUSD(usdValue),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: isSent ? Colors.red.shade600 : Colors.green.shade600,
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 2),
                        // Status badge
                        if (isPending)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 6,
                                  height: 6,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                    valueColor: AlwaysStoppedAnimation(Colors.orange.shade700),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Pending',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.orange.shade700,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else if (isCompleted)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.shade100,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              'Completed',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Colors.green.shade700,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                // Expand to show more details if pending
                if (isPending) ...[
                  const SizedBox(height: 10),
                  const Divider(height: 1),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 14,
                          color: Colors.orange.shade700,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Waiting for blockchain confirmation...',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.orange.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'completed':
        return Colors.green;
      case 'failed':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Color _getBorderColor(String status, String type) {
    if (status == 'pending') return Colors.orange.shade200;
    if (status == 'completed') return Colors.green.shade200;
    return Colors.grey.shade200;
  }

  IconData _getTransactionIcon(Transaction tx) {
    if (tx.type == 'swap') return Icons.swap_horiz;
    if (tx.type == 'sent') return Icons.arrow_upward;
    if (tx.type == 'received') return Icons.arrow_downward;
    return Icons.account_balance_wallet;
  }

  Color _getIconColor(Transaction tx) {
    if (tx.type == 'swap') return Colors.purple.shade600;
    if (tx.type == 'sent') return Colors.red.shade600;
    if (tx.type == 'received') return Colors.green.shade600;
    return Colors.blue.shade600;
  }

  Color _getIconBackgroundColor(Transaction tx) {
    if (tx.type == 'swap') return Colors.purple.shade100;
    if (tx.type == 'sent') return Colors.red.shade100;
    if (tx.type == 'received') return Colors.green.shade100;
    return Colors.blue.shade100;
  }

  String _getTransactionLabel(Transaction tx) {
    if (tx.type == 'swap') return 'Swap ${tx.coin}';
    if (tx.type == 'sent') return 'Send ${tx.coin}';
    if (tx.type == 'received') return 'Receive ${tx.coin}';
    return 'Transaction';
  }

  String _getTransactionSubtitle(Transaction tx) {
    final timeAgo = _getTimeAgo(tx.timestamp);
    if (tx.status == 'pending') {
      return 'Processing • $timeAgo';
    }
    return '${tx.address.substring(0, 8)}... • $timeAgo';
  }

  String _getTimeAgo(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inSeconds < 60) return 'just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    return '${difference.inDays}d ago';
  }
}
