import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../services/notification_service.dart';
import '../../services/transaction_service.dart';
import '../pages/transactions/transaction_detail_page.dart';

class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  final NotificationService _notificationService = NotificationService();
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _updateUnreadCount();
    _notificationService.addListener(_onNotificationsChanged);
  }

  @override
  void dispose() {
    _notificationService.removeListener(_onNotificationsChanged);
    super.dispose();
  }

  void _onNotificationsChanged(List<AppNotification> notifications) {
    if (mounted) {
      setState(() {
        _updateUnreadCount();
      });
    }
  }

  void _updateUnreadCount() {
    _unreadCount = _notificationService.unreadCount;
  }

  void _showNotificationPanel(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => NotificationPanel(
        onNavigateToHistory: () {
          Navigator.of(ctx).pop();
          context.go('/transactions');
        },
        onNavigateToTransaction: (String txHash) async {
          Navigator.of(ctx).pop(); // close the notification sheet
          // Look up the transaction by its hash
          try {
            final txService = TransactionService();
            final all = await txService.getAllTransactions();
            final matches = all.where(
              (t) => t.txHash == txHash || t.id == txHash,
            ).toList();
            if (matches.isNotEmpty && context.mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TransactionDetailPage(tx: matches.first),
                ),
              );
            } else if (context.mounted) {
              // No exact match — open the transactions list
              context.go('/transactions');
            }
          } catch (_) {
            // Fall back to transactions list if lookup fails
            if (context.mounted) context.go('/transactions');
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        IconButton(
          icon: const Icon(Icons.notifications_outlined),
          onPressed: () => _showNotificationPanel(context),
          tooltip: 'Notifications',
        ),
        if (_unreadCount > 0)
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(
                minWidth: 16,
                minHeight: 16,
              ),
              child: Text(
                _unreadCount > 99 ? '99+' : _unreadCount.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}

// ─── Notification Panel ───────────────────────────────────────────────────────

class NotificationPanel extends StatefulWidget {
  /// Called when the user taps a non-hash tx notification; navigates to history.
  final VoidCallback? onNavigateToHistory;

  /// Called when the user taps a notification that has a txHash.
  /// Receives the txHash so the caller can look up and show the detail page.
  final void Function(String txHash)? onNavigateToTransaction;

  const NotificationPanel({
    super.key,
    this.onNavigateToHistory,
    this.onNavigateToTransaction,
  });

  @override
  State<NotificationPanel> createState() => _NotificationPanelState();
}

class _NotificationPanelState extends State<NotificationPanel> {
  final NotificationService _notificationService = NotificationService();
  List<AppNotification> _notifications = [];

  @override
  void initState() {
    super.initState();
    _loadNotifications();
    _notificationService.addListener(_onNotificationsChanged);
  }

  @override
  void dispose() {
    _notificationService.removeListener(_onNotificationsChanged);
    super.dispose();
  }

  void _onNotificationsChanged(List<AppNotification> _) {
    if (mounted) setState(_loadNotifications);
  }

  void _loadNotifications() {
    _notifications = _notificationService.notifications;
  }

  // ─── helpers ──────────────────────────────────────────────────────────────

  IconData _iconFor(NotificationType type) {
    switch (type) {
      case NotificationType.incoming:
        return Icons.arrow_downward_rounded;
      case NotificationType.outgoing:
        return Icons.arrow_upward_rounded;
      case NotificationType.confirmed:
        return Icons.check_circle_rounded;
      case NotificationType.failed:
        return Icons.cancel_rounded;
      case NotificationType.success:
        return Icons.check_circle_rounded;
      case NotificationType.warning:
        return Icons.warning_rounded;
      case NotificationType.info:
        return Icons.info_rounded;
    }
  }

  Color _colorFor(NotificationType type) {
    switch (type) {
      case NotificationType.incoming:
        return Colors.blue;
      case NotificationType.outgoing:
        return Colors.orange;
      case NotificationType.confirmed:
        return Colors.green;
      case NotificationType.failed:
        return Colors.red;
      case NotificationType.success:
        return Colors.green;
      case NotificationType.warning:
        return Colors.orange;
      case NotificationType.info:
        return Colors.grey;
    }
  }

  /// Whether tapping this notification should open the transaction history.
  bool _isTxNotification(AppNotification n) =>
      n.type == NotificationType.incoming ||
      n.type == NotificationType.outgoing ||
      n.type == NotificationType.confirmed ||
      n.type == NotificationType.failed ||
      n.txHash != null;

  String _formatTimestamp(DateTime ts) {
    final diff = DateTime.now().difference(ts);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM dd').format(ts);
  }

  // ─── Status chip ──────────────────────────────────────────────────────────

  Widget _statusChip(TxStatus status) {
    late Color bg;
    late Color fg;
    late String label;
    late IconData icon;

    switch (status) {
      case TxStatus.pending:
        bg = Colors.orange.withOpacity(0.15);
        fg = Colors.orange;
        label = 'Pending';
        icon = Icons.hourglass_top_rounded;
        break;
      case TxStatus.confirmed:
        bg = Colors.green.withOpacity(0.15);
        fg = Colors.green;
        label = 'Confirmed';
        icon = Icons.check_rounded;
        break;
      case TxStatus.failed:
        bg = Colors.red.withOpacity(0.15);
        fg = Colors.red;
        label = 'Failed';
        icon = Icons.close_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: fg),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // ── handle bar ──────────────────────────────────────────────────
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // ── header ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Row(
              children: [
                const Icon(Icons.notifications_rounded, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Notifications',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (_notifications.any((n) => !n.isRead))
                  TextButton(
                    onPressed: () => _notificationService.markAllAsRead(),
                    child: const Text('Mark all read'),
                  ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Clear all',
                  onPressed: _confirmClearAll,
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // ── list ────────────────────────────────────────────────────────
          Expanded(
            child: _notifications.isEmpty
                ? _buildEmpty()
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _notifications.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 72),
                    itemBuilder: (ctx, index) =>
                        _buildItem(ctx, _notifications[index], scheme),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_none_rounded, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No notifications yet',
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
          const SizedBox(height: 6),
          Text(
            'Incoming & outgoing transactions\nwill appear here',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(
      BuildContext ctx, AppNotification n, ColorScheme scheme) {
    final isTx = _isTxNotification(n);
    final iconColor = _colorFor(n.type);

    return Dismissible(
      key: Key(n.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_rounded, color: Colors.white),
      ),
      onDismissed: (_) => _notificationService.clearNotification(n.id),
      child: InkWell(
        onTap: () {
          _notificationService.markAsRead(n.id);
          if (n.txHash != null && n.txHash!.isNotEmpty) {
            // Has a txHash → open transaction detail page
            widget.onNavigateToTransaction?.call(n.txHash!);
          } else if (isTx) {
            // Tx notification without a hash → open history list
            widget.onNavigateToHistory?.call();
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: n.isRead
              ? Colors.transparent
              : scheme.primary.withOpacity(0.05),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── coin icon circle ────────────────────────────────────
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(_iconFor(n.type), color: iconColor, size: 22),
              ),
              const SizedBox(width: 12),

              // ── content ─────────────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // title row
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            n.title,
                            style: TextStyle(
                              fontWeight:
                                  n.isRead ? FontWeight.normal : FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        // unread dot
                        if (!n.isRead)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(left: 6),
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // message
                    Text(
                      n.message,
                      style:
                          TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 6),

                    // bottom row: status chip + timestamp + tap hint
                    Row(
                      children: [
                        // only show status chip for tx notifications
                        if (isTx) ...[
                          _statusChip(n.txStatus),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          _formatTimestamp(n.timestamp),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[500],
                          ),
                        ),
                        const Spacer(),
                        // "View" hint for tx notifications
                        if (isTx)
                          Text(
                            n.txHash != null ? 'View details →' : 'View history →',
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.primary,
                              fontWeight: FontWeight.w500,
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
      ),
    );
  }

  void _confirmClearAll() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Notifications'),
        content: const Text('Are you sure you want to remove all notifications?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              _notificationService.clearAllNotifications();
              Navigator.pop(ctx);
            },
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }
}
