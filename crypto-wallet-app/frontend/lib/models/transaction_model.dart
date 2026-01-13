
class Transaction {
  final String id;
  final String type; // 'sent', 'received', or 'swap'
  final String coin;
  final double amount;
  final String address;
  final String? fromAddress;
  final String? toAddress;
  final String? txHash;
  final DateTime timestamp;
  final String status; // 'pending', 'completed', 'failed'
  final double? fee;
  final String? memo;
  final int? confirmations;
  final bool isPending; // True for unconfirmed transactions
  // Swap-specific fields
  final String? fromCoin;
  final String? toCoin;
  final double? fromAmount;
  final double? toAmount;
  final double? exchangeRate;

  Transaction({
    required this.id,
    required this.type,
    required this.coin,
    required this.amount,
    required this.address,
    this.fromAddress,
    this.toAddress,
    this.txHash,
    required this.timestamp,
    this.status = 'completed',
    this.fee,
    this.memo,
    this.confirmations,
    this.isPending = false,
    // Swap-specific fields
    this.fromCoin,
    this.toCoin,
    this.fromAmount,
    this.toAmount,
    this.exchangeRate,
  });

  // Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'coin': coin,
      'amount': amount,
      'address': address,
      'fromAddress': fromAddress,
      'toAddress': toAddress,
      'txHash': txHash,
      'timestamp': timestamp.toIso8601String(),
      'status': status,
      'fee': fee,
      'memo': memo,
      'confirmations': confirmations,
      'isPending': isPending,
      // Swap-specific fields
      'fromCoin': fromCoin,
      'toCoin': toCoin,
      'fromAmount': fromAmount,
      'toAmount': toAmount,
      'exchangeRate': exchangeRate,
    };
  }

  // Create from JSON
  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      id: json['id'] ?? '',
      type: json['type'] ?? '',
      coin: json['coin'] ?? '',
      amount: (json['amount'] is int ? json['amount'].toDouble() : json['amount']) ?? 0.0,
      address: json['address'] ?? '',
      fromAddress: json['fromAddress'],
      toAddress: json['toAddress'],
      txHash: json['txHash'],
      timestamp: DateTime.parse(json['timestamp'] ?? DateTime.now().toIso8601String()),
      status: json['status'] ?? 'completed',
      fee: json['fee'] != null ? (json['fee'] is int ? json['fee'].toDouble() : json['fee']) : null,
      memo: json['memo'],
      confirmations: json['confirmations'],
      isPending: json['isPending'] ?? false,
      // Swap-specific fields
      fromCoin: json['fromCoin'],
      toCoin: json['toCoin'],
      fromAmount: json['fromAmount'] != null ? (json['fromAmount'] is int ? json['fromAmount'].toDouble() : json['fromAmount']) : null,
      toAmount: json['toAmount'] != null ? (json['toAmount'] is int ? json['toAmount'].toDouble() : json['toAmount']) : null,
      exchangeRate: json['exchangeRate'] != null ? (json['exchangeRate'] is int ? json['exchangeRate'].toDouble() : json['exchangeRate']) : null,
    );
  }

  // Generate a unique ID
  static String generateId() {
    return 'tx_${DateTime.now().millisecondsSinceEpoch}_${_generateRandomString(6)}';
  }

  static String _generateRandomString(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = DateTime.now().microsecondsSinceEpoch;
    final result = StringBuffer();
    for (var i = 0; i < length; i++) {
      result.write(chars[(random + i) % chars.length]);
    }
    return result.toString();
  }

  // Helper methods
  bool get isSent => type == 'sent';
  bool get isReceived => type == 'received';
  bool get isSwap => type == 'swap';
  bool get isUnconfirmed => isPending || status == 'pending';
  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';

  // Get display amount (positive for received, negative for sent)
  double get displayAmount {
    return isSent ? -amount : amount;
  }

  // Get display address based on type
  String get displayAddress {
    if (isSent) {
      return toAddress ?? address;
    } else if (isReceived) {
      return fromAddress ?? address;
    } else {
      return 'Swap';
    }
  }

  // Get display label
  String get displayLabel {
    if (isSent) return 'Sent to';
    if (isReceived) return 'Received from';
    return 'Swapped';
  }

  // Get display amount for swap transactions
  String get displaySwapAmount {
    if (isSwap && fromCoin != null && toCoin != null && fromAmount != null && toAmount != null) {
      return '$fromAmount $fromCoin → $toAmount $toCoin';
    }
    return '$amount $coin';
  }

  // Get status color
  String get statusColor {
    switch (status) {
      case 'completed':
        return isSent ? 'sent' : 'received';
      case 'pending':
        return 'pending';
      case 'failed':
        return 'failed';
      default:
        return 'pending';
    }
  }
}