import 'package:flutter/services.dart';

/// Input Validation Utilities
/// Provides real-time validation for all user input forms
/// 
/// Features:
/// - Address format validation for each blockchain
/// - Amount validation (positive, max decimals, within balance)
/// - Memo field validation (length, allowed characters)
/// - Real-time feedback in forms
/// - Form submission prevention if invalid

class InputValidator {
  
  /// Validate blockchain address format
  static String? validateAddress(String? value, String chain) {
    if (value == null || value.trim().isEmpty) {
      return 'Address is required';
    }
    
    final address = value.trim();
    
    switch (chain.toUpperCase()) {
      case 'BTC':
        // BTC: starts with 1, 3, or bc1, length 26-64
        if (!RegExp(r'^(1|3|bc1)[a-zA-Z0-9]{25,63}$').hasMatch(address)) {
          return 'Invalid Bitcoin address format';
        }
        break;
      
      case 'ETH':
      case 'BNB':
      case 'USDT-ERC20':
      case 'USDT-BEP20':
        // ETH/BNB: 0x followed by 40 hex characters
        if (!RegExp(r'^0x[a-fA-F0-9]{40}$').hasMatch(address)) {
          return 'Invalid Ethereum/BSC address format';
        }
        break;
      
      case 'TRX':
      case 'USDT-TRC20':
        // TRX: starts with T, length 34
        if (!RegExp(r'^T[a-zA-Z0-9]{33}$').hasMatch(address)) {
          return 'Invalid Tron address format';
        }
        break;
      
      case 'XRP':
        // XRP: starts with r, length 25-35
        if (!RegExp(r'^r[a-zA-Z0-9]{24,34}$').hasMatch(address)) {
          return 'Invalid Ripple address format';
        }
        break;
      
      case 'SOL':
        // SOL: base58, length 32-44
        if (!RegExp(r'^[1-9A-HJ-NP-Za-km-z]{32,44}$').hasMatch(address)) {
          return 'Invalid Solana address format';
        }
        break;
      
      case 'LTC':
        // LTC: starts with L, M, or ltc1
        if (!RegExp(r'^(L|M|ltc1)[a-zA-Z0-9]{25,63}$').hasMatch(address)) {
          return 'Invalid Litecoin address format';
        }
        break;
      
      case 'DOGE':
        // DOGE: starts with D or A
        if (!RegExp(r'^(D|A)[a-zA-Z0-9]{33}$').hasMatch(address)) {
          return 'Invalid Dogecoin address format';
        }
        break;
      
      default:
        // Generic validation: length 26-64
        if (address.length < 26 || address.length > 64) {
          return 'Invalid address format';
        }
    }
    
    return null; // Valid
  }
  
  /// Validate amount
  static String? validateAmount(
    String? value, {
    required double maxAmount,
    int maxDecimals = 8,
    double minAmount = 0.00000001,
  }) {
    if (value == null || value.trim().isEmpty) {
      return 'Amount is required';
    }
    
    final amount = double.tryParse(value.trim());
    
    if (amount == null) {
      return 'Invalid amount format';
    }
    
    if (amount <= 0) {
      return 'Amount must be greater than 0';
    }
    
    if (amount < minAmount) {
      return 'Amount must be at least $minAmount';
    }
    
    if (amount > maxAmount) {
      return 'Amount exceeds maximum ($maxAmount)';
    }
    
    // Check decimal places
    final parts = value.split('.');
    if (parts.length > 1 && parts[1].length > maxDecimals) {
      return 'Maximum $maxDecimals decimal places allowed';
    }
    
    return null; // Valid
  }
  
  /// Validate memo field
  static String? validateMemo(String? value, {int maxLength = 256}) {
    if (value == null || value.isEmpty) {
      return null; // Memo is optional
    }
    
    if (value.length > maxLength) {
      return 'Memo must not exceed $maxLength characters';
    }
    
    // Check for control characters
    if (RegExp(r'[\x00-\x1F\x7F-\x9F]').hasMatch(value)) {
      return 'Memo contains invalid characters';
    }
    
    return null; // Valid
  }
  
  /// Validate private key
  static String? validatePrivateKey(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Private key is required';
    }
    
    final key = value.trim();
    
    // Most private keys are 64 hex characters
    if (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(key)) {
      return 'Invalid private key format (must be 64 hex characters)';
    }
    
    return null; // Valid
  }
  
  /// Validate mnemonic phrase
  static String? validateMnemonic(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Mnemonic phrase is required';
    }
    
    final words = value.trim().split(RegExp(r'\s+'));
    
    if (![12, 15, 18, 21, 24].contains(words.length)) {
      return 'Mnemonic must be 12, 15, 18, 21, or 24 words';
    }
    
    // Check if all words are lowercase alphanumeric
    for (final word in words) {
      if (!RegExp(r'^[a-z]+$').hasMatch(word)) {
        return 'Mnemonic words must be lowercase letters only';
      }
    }
    
    return null; // Valid
  }
  
  /// Validate PIN code
  static String? validatePIN(String? value, {int length = 6}) {
    if (value == null || value.isEmpty) {
      return 'PIN is required';
    }
    
    if (value.length != length) {
      return 'PIN must be $length digits';
    }
    
    if (!RegExp(r'^\d+$').hasMatch(value)) {
      return 'PIN must contain only digits';
    }
    
    return null; // Valid
  }
  
  /// Validate email (for notifications/backup)
  static String? validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null; // Email is optional
    }
    
    final email = value.trim();
    
    if (!RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$').hasMatch(email)) {
      return 'Invalid email format';
    }
    
    return null; // Valid
  }
  
  /// Validate password strength
  static String? validatePassword(String? value, {int minLength = 8}) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }
    
    if (value.length < minLength) {
      return 'Password must be at least $minLength characters';
    }
    
    // Check for at least one uppercase, one lowercase, one digit
    if (!RegExp(r'[A-Z]').hasMatch(value)) {
      return 'Password must contain at least one uppercase letter';
    }
    
    if (!RegExp(r'[a-z]').hasMatch(value)) {
      return 'Password must contain at least one lowercase letter';
    }
    
    if (!RegExp(r'\d').hasMatch(value)) {
      return 'Password must contain at least one digit';
    }
    
    return null; // Valid
  }
  
  /// Validate transaction hash
  static String? validateTxHash(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Transaction hash is required';
    }
    
    final hash = value.trim();
    
    // Most tx hashes are 64 hex characters
    if (!RegExp(r'^(0x)?[a-fA-F0-9]{64}$').hasMatch(hash)) {
      return 'Invalid transaction hash format';
    }
    
    return null; // Valid
  }
  
  /// Create a TextInputFormatter for amounts
  static List<TextInputFormatter> amountFormatters({int maxDecimals = 8}) {
    return [
      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
      _DecimalTextInputFormatter(decimalRange: maxDecimals),
    ];
  }
  
  /// Create a TextInputFormatter for addresses (alphanumeric only)
  static List<TextInputFormatter> addressFormatters() {
    return [
      FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
    ];
  }
  
  /// Create a TextInputFormatter for hex input (private keys, tx hashes)
  static List<TextInputFormatter> hexFormatters() {
    return [
      FilteringTextInputFormatter.allow(RegExp(r'[a-fA-F0-9]')),
    ];
  }
  
  /// Create a TextInputFormatter for PIN codes (digits only)
  static List<TextInputFormatter> pinFormatters({int maxLength = 6}) {
    return [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(maxLength),
    ];
  }
}

/// Custom TextInputFormatter to limit decimal places
class _DecimalTextInputFormatter extends TextInputFormatter {
  final int decimalRange;

  _DecimalTextInputFormatter({required this.decimalRange});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }

    // Check if contains decimal point
    if (newValue.text.contains('.')) {
      final parts = newValue.text.split('.');
      
      // Only one decimal point allowed
      if (parts.length > 2) {
        return oldValue;
      }
      
      // Check decimal places
      if (parts.length == 2 && parts[1].length > decimalRange) {
        return oldValue;
      }
    }

    return newValue;
  }
}

/// Extension methods for String validation
extension StringValidation on String? {
  bool get isValidAddress => this != null && this!.trim().isNotEmpty && this!.length >= 26;
  bool get isValidAmount => double.tryParse(this ?? '0') != null && double.parse(this!) > 0;
  bool get isValidMemo => this == null || this!.length <= 256;
}
