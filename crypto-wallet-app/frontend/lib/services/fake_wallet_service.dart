import 'package:logger/logger.dart';

/// Represents fake wallet data shown during duress PIN mode
class FakeWalletData {
  final String walletName;
  final Map<String, double> balances; // All showing 0.00
  final List<FakeTransaction> transactions;

  FakeWalletData({
    this.walletName = 'Decoy Wallet',
    this.balances = const {
      'BTC': 0.0,
      'ETH': 0.0,
      'BNB': 0.0,
      'SOL': 0.0,
      'TRX': 0.0,
      'LTC': 0.0,
      'DOGE': 0.0,
      'XRP': 0.0,
    },
    this.transactions = const [],
  });
}

/// Fake transaction that appears to have been sent
class FakeTransaction {
  final String id;
  final String coin;
  final double amount;
  final String toAddress;
  final DateTime timestamp;
  final String status; // 'pending', 'completed', 'failed'

  FakeTransaction({
    required this.id,
    required this.coin,
    required this.amount,
    required this.toAddress,
    required this.timestamp,
    this.status = 'pending',
  });
}

/// Service for managing fake wallet behavior in duress PIN mode
class FakeWalletService {
  final Logger _logger;

  FakeWalletService({Logger? logger}) : _logger = logger ?? Logger();

  /// Get default fake wallet data (empty with all 0 balances)
  FakeWalletData getFakeWalletData() {
    _logger.i('Loading fake wallet data - all balances set to 0.00');
    return FakeWalletData();
  }

  /// Simulate a fake transaction (appears to send but does nothing)
  FakeTransaction simulateFakeTransaction({
    required String coin,
    required double amount,
    required String toAddress,
  }) {
    final tx = FakeTransaction(
      id: 'fake_${DateTime.now().millisecondsSinceEpoch}',
      coin: coin,
      amount: amount,
      toAddress: toAddress,
      timestamp: DateTime.now(),
      status: 'completed',
    );

    _logger.i(
      'Fake transaction simulated: $coin $amount to $toAddress (ID: ${tx.id})',
    );
    return tx;
  }

  /// Simulate fake balance update (returns 0)
  Future<double> simulateFakeBalance(String coin) async {
    _logger.i('Fake balance check: $coin - returning 0.00');
    // Simulate network delay to make it look real
    await Future.delayed(const Duration(milliseconds: 500));
    return 0.0;
  }

  /// Simulate fake transaction history retrieval
  Future<List<FakeTransaction>> simulateFakeTransactionHistory(String coin) async {
    _logger.i('Fake transaction history: $coin - returning empty list');
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 400));
    return [];
  }

  /// Check if an address is valid for fake transaction (always returns true to not raise suspicion)
  bool validateFakeAddress(String address) {
    _logger.i('Validating fake address: $address');
    // Always return true to not raise suspicion that something is wrong
    return true;
  }

  /// Simulate checking for incoming payments (fake wallet never receives)
  Future<bool> checkFakeIncomingPayments(String coin) async {
    _logger.i('Checking for fake incoming payments: $coin');
    await Future.delayed(const Duration(milliseconds: 300));
    return false;
  }
}
