import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/transaction_model.dart';

class TransactionDetailPage extends StatelessWidget {
  final Transaction tx;

  const TransactionDetailPage({super.key, required this.tx});

  // ─── Color / icon helpers ───────────────────────────────────────────────

  static const Map<String, Color> _coinColors = {
    'BTC':      Color(0xFFF7931A),
    'ETH':      Color(0xFF627EEA),
    'BNB':      Color(0xFFF0B90B),
    'USDT':     Color(0xFF26A17B),
    'USDT-ERC20': Color(0xFF26A17B),
    'USDT-BEP20': Color(0xFF26A17B),
    'SOL':      Color(0xFF9945FF),
    'XRP':      Color(0xFF23292F),
    'TRX':      Color(0xFFEB0029),
    'LTC':      Color(0xFFBFBBBB),
    'DOGE':     Color(0xFFC2A633),
  };

  Color get _coinColor {
    final base = tx.coin.split('-').first.toUpperCase();
    return _coinColors[base] ?? _coinColors[tx.coin] ?? Colors.grey;
  }

  Color get _typeColor {
    switch (tx.type) {
      case 'sent':     return Colors.red;
      case 'received': return Colors.green;
      case 'swap':     return Colors.blue;
      default:         return Colors.grey;
    }
  }

  IconData get _typeIcon {
    switch (tx.type) {
      case 'sent':     return Icons.arrow_upward;
      case 'received': return Icons.arrow_downward;
      case 'swap':     return Icons.swap_horiz;
      default:         return Icons.receipt;
    }
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':   return Colors.orange;
      case 'confirmed':
      case 'completed':
      case 'success':   return Colors.green;
      case 'failed':    return Colors.red;
      default:          return Colors.green;
    }
  }

  String _statusText(String status) {
    switch (status.toLowerCase()) {
      case 'pending':   return 'Pending';
      case 'confirmed':
      case 'completed':
      case 'success':   return 'Confirmed';
      case 'failed':    return 'Failed';
      default:          return 'Confirmed';
    }
  }

  String? _explorerUrl(String coin, String txHash) {
    final base = coin.split('-').first.toUpperCase();
    switch (base) {
      case 'BTC':  return 'https://blockstream.info/tx/$txHash';
      case 'ETH':  return 'https://etherscan.io/tx/$txHash';
      case 'BNB':  return 'https://bscscan.com/tx/$txHash';
      case 'USDT':
        if (coin.contains('BEP20')) return 'https://bscscan.com/tx/$txHash';
        if (coin.contains('TRC20')) return 'https://tronscan.org/#/transaction/$txHash';
        return 'https://etherscan.io/tx/$txHash';
      case 'SOL':  return 'https://solscan.io/tx/$txHash';
      case 'XRP':  return 'https://xrpscan.com/tx/$txHash';
      case 'TRX':  return 'https://tronscan.org/#/transaction/$txHash';
      case 'LTC':  return 'https://blockchair.com/litecoin/transaction/$txHash';
      case 'DOGE': return 'https://blockchair.com/dogecoin/transaction/$txHash';
      default:     return null;
    }
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final coinColor   = _coinColor;
    final typeColor   = _typeColor;
    final statusColor = _statusColor(tx.status);
    final statusText  = _statusText(tx.status);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        foregroundColor: Colors.white,
        title: const Text('Transaction Details'),
        elevation: 0,
      ),
      body: Column(
        children: [
          // ── Scrollable content ─────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 8),
              child: Column(
                children: [
                  // Header icon
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: typeColor.withOpacity(0.1),
                      shape: BoxShape.circle,
                      border: Border.all(color: coinColor, width: 3),
                    ),
                    child: Icon(_typeIcon, color: typeColor, size: 32),
                  ),
                  const SizedBox(height: 16),

                  // Type label
                  Text(
                    tx.type == 'swap'
                        ? 'Swap'
                        : (tx.type == 'sent' ? 'Sent' : 'Received'),
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),

                  // Amount
                  Text(
                    '${tx.type == 'sent' ? '-' : '+'}${tx.amount.toStringAsFixed(8)} ${tx.coin.split('-').first}',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: tx.type == 'sent' ? Colors.red : Colors.green,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Status chip
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          tx.status == 'pending'
                              ? Icons.hourglass_empty
                              : tx.status == 'failed'
                                  ? Icons.cancel
                                  : Icons.check_circle,
                          color: statusColor,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          statusText,
                          style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),

                  // ── Detail rows ─────────────────────────────────────────
                  _detailRow(context, 'Date',
                      DateFormat('MMM d, yyyy • HH:mm').format(tx.timestamp)),
                  _detailRow(context, 'Network', tx.coin),
                  if (tx.fee != null && tx.fee! > 0)
                    _detailRow(context, 'Fee',
                        '${tx.fee!.toStringAsFixed(8)} ${tx.coin.split('-').first}'),

                  // From (always shown for sent; shown when available for received)
                  if (tx.type == 'sent') ...[
                    _detailRow(
                      context,
                      'From',
                      (tx.fromAddress != null && tx.fromAddress!.isNotEmpty)
                          ? tx.fromAddress!
                          : tx.address,
                      isAddress: true,
                    ),
                    _detailRow(
                      context,
                      'To',
                      (tx.toAddress != null && tx.toAddress!.isNotEmpty)
                          ? tx.toAddress!
                          : tx.address,
                      isAddress: true,
                    ),
                  ],
                  if (tx.type == 'received') ...[
                    _detailRow(
                      context,
                      'From',
                      (tx.fromAddress != null && tx.fromAddress!.isNotEmpty)
                          ? tx.fromAddress!
                          : tx.address,
                      isAddress: true,
                    ),
                  ],
                  if (tx.type == 'swap') ...[
                    if (tx.fromCoin != null)
                      _detailRow(context, 'From Coin', tx.fromCoin!),
                    if (tx.toCoin != null)
                      _detailRow(context, 'To Coin', tx.toCoin!),
                  ],

                  if (tx.txHash != null && tx.txHash!.isNotEmpty)
                    _hashRow(context, 'Tx Hash', tx.txHash!),
                  if (tx.memo != null && tx.memo!.isNotEmpty)
                    _detailRow(context, 'Memo', tx.memo!),

                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),

          // ── Sticky action buttons ────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 12,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      final hash = tx.txHash ?? '';
                      if (hash.isNotEmpty) {
                        Clipboard.setData(ClipboardData(text: hash));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Transaction hash copied')),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('No transaction hash available')),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy Hash'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
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
                              content: Text('No transaction hash available')),
                        );
                        return;
                      }
                      final url = _explorerUrl(tx.coin, hash);
                      if (url == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Explorer not available for this coin')),
                        );
                        return;
                      }
                      final uri = Uri.parse(url);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri,
                            mode: LaunchMode.externalApplication);
                      } else {
                        Clipboard.setData(ClipboardData(text: url));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content:
                                    Text('Explorer URL copied to clipboard')),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('View Explorer'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: coinColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Row widgets ────────────────────────────────────────────────────────

  Widget _detailRow(BuildContext context, String label, String value,
      {bool isAddress = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey[500], fontSize: 14),
            ),
          ),
          Expanded(
            child: isAddress
                ? GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: value));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('$label copied')),
                      );
                    },
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            value.length > 30
                                ? '${value.substring(0, 15)}...${value.substring(value.length - 10)}'
                                : value,
                            style: const TextStyle(
                                fontFamily: 'monospace', fontSize: 13),
                          ),
                        ),
                        Icon(Icons.copy, size: 16, color: Colors.grey[400]),
                      ],
                    ),
                  )
                : Text(
                    value,
                    style: const TextStyle(
                        fontWeight: FontWeight.w500, fontSize: 14),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _hashRow(BuildContext context, String label, String hash) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                    fontWeight: FontWeight.w500),
              ),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: hash));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Transaction hash copied!')),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.copy, size: 14, color: Colors.blue[700]),
                      const SizedBox(width: 4),
                      Text(
                        'Copy',
                        style: TextStyle(
                            color: Colors.blue[700],
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
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
            style: const TextStyle(
                fontFamily: 'monospace', fontSize: 11, letterSpacing: 0.5),
          ),
        ],
      ),
    );
  }
}
