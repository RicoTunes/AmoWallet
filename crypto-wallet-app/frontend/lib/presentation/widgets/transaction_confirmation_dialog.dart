import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TransactionConfirmationDialog extends StatelessWidget {
  final String recipientAddress;
  final String amount;
  final String coin;
  final String? networkFee;
  final String? estimatedTotal;
  final VoidCallback onConfirm;
  final VoidCallback? onCancel;

  const TransactionConfirmationDialog({
    super.key,
    required this.recipientAddress,
    required this.amount,
    required this.coin,
    this.networkFee,
    this.estimatedTotal,
    required this.onConfirm,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: Colors.orange,
          ),
          const SizedBox(width: 8),
          const Text('Confirm Transaction'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Please review the transaction details carefully. This action cannot be undone.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 24),
            _buildDetailRow(
              context,
              'Recipient Address',
              recipientAddress,
              isAddress: true,
            ),
            const Divider(height: 24),
            _buildDetailRow(
              context,
              'Amount',
              '$amount $coin',
              highlight: true,
            ),
            if (networkFee != null) ...[
              const Divider(height: 24),
              _buildDetailRow(
                context,
                'Network Fee',
                networkFee!,
              ),
            ],
            if (estimatedTotal != null) ...[
              const Divider(height: 24),
              _buildDetailRow(
                context,
                'Total',
                estimatedTotal!,
                highlight: true,
              ),
            ],
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.error.withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 20,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Double-check the recipient address. Transactions cannot be reversed.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.error,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(false);
            onCancel?.call();
          },
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop(true);
            onConfirm();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
          ),
          child: const Text('Confirm & Send'),
        ),
      ],
    );
  }

  Widget _buildDetailRow(
    BuildContext context,
    String label,
    String value, {
    bool highlight = false,
    bool isAddress = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                value,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
                      fontSize: highlight ? 18 : 14,
                    ),
                maxLines: isAddress ? 2 : 1,
                overflow: isAddress ? TextOverflow.ellipsis : TextOverflow.fade,
              ),
            ),
            if (isAddress)
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                tooltip: 'Copy address',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: value));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Address copied to clipboard'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
          ],
        ),
      ],
    );
  }
}

class SwapConfirmationDialog extends StatelessWidget {
  final String fromCoin;
  final String toCoin;
  final String fromAmount;
  final String toAmount;
  final String? exchangeRate;
  final String? networkFee;
  final String? slippage;
  final String? actualSendAmount; // Amount after gas deduction
  final String? gasFeeAmount; // Gas fee in ETH
  final String? recipientReceives; // What recipient gets
  final VoidCallback onConfirm;
  final VoidCallback? onCancel;

  const SwapConfirmationDialog({
    super.key,
    required this.fromCoin,
    required this.toCoin,
    required this.fromAmount,
    required this.toAmount,
    this.exchangeRate,
    this.networkFee,
    this.slippage,
    this.actualSendAmount,
    this.gasFeeAmount,
    this.recipientReceives,
    required this.onConfirm,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final showGasDeduction = gasFeeAmount != null && actualSendAmount != null;
    
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.swap_horiz,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          const Text('Confirm Swap'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Please review the swap details carefully.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 24),
            _buildSwapRow(context),
            const Divider(height: 24),
            
            // Gas Fee Deduction Breakdown (for ETH swaps)
            if (showGasDeduction) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.local_gas_station, size: 18, color: Colors.orange),
                        const SizedBox(width: 8),
                        Text(
                          'Gas Fee Breakdown',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildBreakdownRow(context, 'You entered:', '$fromAmount $fromCoin'),
                    const SizedBox(height: 6),
                    _buildBreakdownRow(context, 'Gas fee (deducted):', '-$gasFeeAmount $fromCoin', isDeduction: true),
                    const Divider(height: 16),
                    _buildBreakdownRow(context, 'Amount swapped:', '$actualSendAmount $fromCoin', isBold: true),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            
            if (exchangeRate != null)
              _buildDetailRow(context, 'Exchange Rate', exchangeRate!),
            if (networkFee != null && !showGasDeduction) ...[
              const SizedBox(height: 12),
              _buildDetailRow(context, 'Network Fee', networkFee!),
            ],
            if (slippage != null) ...[
              const SizedBox(height: 12),
              _buildDetailRow(context, 'Max Slippage', slippage!),
            ],
            
            // Recipient Receives Section
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.account_balance_wallet, size: 18, color: Colors.green),
                      const SizedBox(width: 8),
                      Text(
                        'You Receive:',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${recipientReceives ?? toAmount} $toCoin',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade700,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'The final amount may vary slightly due to market conditions.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(false);
            onCancel?.call();
          },
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop(true);
            onConfirm();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
          ),
          child: const Text('Confirm Swap'),
        ),
      ],
    );
  }

  Widget _buildSwapRow(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            children: [
              Text(
                'From',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              Text(
                fromCoin,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                fromAmount,
                style: Theme.of(context).textTheme.bodyLarge,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Icon(
            Icons.arrow_forward,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        Expanded(
          child: Column(
            children: [
              Text(
                'To',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              Text(
                toCoin,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                toAmount,
                style: Theme.of(context).textTheme.bodyLarge,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(BuildContext context, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ),
      ],
    );
  }
  
  Widget _buildBreakdownRow(BuildContext context, String label, String value, {bool isDeduction = false, bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey.shade700,
              ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
                color: isDeduction ? Colors.red.shade600 : (isBold ? Colors.black : Colors.grey.shade800),
              ),
        ),
      ],
    );
  }
}
