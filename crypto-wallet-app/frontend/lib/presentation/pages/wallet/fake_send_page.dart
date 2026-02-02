import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/fake_wallet_provider.dart';
import '../../../services/fake_wallet_service.dart';

/// Fake send page shown when in duress wallet mode
/// All transactions appear to process but do nothing
class FakeSendPage extends ConsumerStatefulWidget {
  const FakeSendPage({super.key});

  @override
  ConsumerState<FakeSendPage> createState() => _FakeSendPageState();
}

class _FakeSendPageState extends ConsumerState<FakeSendPage> {
  final FakeWalletService _fakeWalletService = FakeWalletService();
  
  String _selectedCoin = 'BTC';
  String _recipientAddress = '';
  String _amount = '';
  bool _isSending = false;

  final coins = [
    'BTC',
    'ETH',
    'BNB',
    'SOL',
    'TRX',
    'LTC',
    'XRP',
    'DOGE',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Send Crypto'),
        backgroundColor: const Color(0xFF1A1A1A),
      ),
      backgroundColor: Colors.grey[50],
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Select Coin
            Text(
              'Select Coin',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: DropdownButton<String>(
                value: _selectedCoin,
                isExpanded: true,
                underline: Container(),
                items: coins.map((coin) {
                  return DropdownMenuItem(
                    value: coin,
                    child: Text(coin),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedCoin = value);
                  }
                },
              ),
            ),
            const SizedBox(height: 24),
            // Available Balance (all 0.00)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber[200]!),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Available Balance',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  Text(
                    '0.00 $_selectedCoin (\$0.00)',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Recipient Address
            Text(
              'Recipient Address',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              onChanged: (value) => setState(() => _recipientAddress = value),
              decoration: InputDecoration(
                hintText: 'Enter recipient address',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 24),
            // Amount
            Text(
              'Amount',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              onChanged: (value) => setState(() => _amount = value),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: 'Enter amount',
                suffix: Text(_selectedCoin),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 32),
            // Send Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _amount.isNotEmpty && _recipientAddress.isNotEmpty
                    ? _sendFakeTransaction
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  disabledBackgroundColor: Colors.grey[300],
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isSending
                    ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                    : const Text(
                      'Send',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Send fake transaction (appears to work but does nothing)
  Future<void> _sendFakeTransaction() async {
    setState(() => _isSending = true);

    // Simulate network delay
    await Future.delayed(const Duration(seconds: 2));

    // Simulate fake transaction
    final tx = _fakeWalletService.simulateFakeTransaction(
      coin: _selectedCoin,
      amount: double.tryParse(_amount) ?? 0,
      toAddress: _recipientAddress,
    );

    setState(() => _isSending = false);

    // Show success message
    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Transaction Sent'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTransactionDetailRow('Coin', _selectedCoin),
              _buildTransactionDetailRow('Amount', '$_amount'),
              _buildTransactionDetailRow(
                'To Address',
                '${_recipientAddress.substring(0, 6)}...${_recipientAddress.substring(_recipientAddress.length - 4)}',
              ),
              _buildTransactionDetailRow('Transaction ID', tx.id),
              _buildTransactionDetailRow('Status', 'Confirmed'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );

      // Clear fields
      setState(() {
        _recipientAddress = '';
        _amount = '';
      });
    }
  }

  Widget _buildTransactionDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
