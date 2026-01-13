import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logger/logger.dart';

/// Service for enforcing daily spending limits
/// Tracks all outgoing transactions and enforces $10M daily limit
class SpendingLimitService {
  static final SpendingLimitService _instance = SpendingLimitService._internal();
  factory SpendingLimitService() => _instance;
  SpendingLimitService._internal();

  final Logger _logger = Logger();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  // Daily spending limit in USD: $10,000,000
  static const double DAILY_LIMIT_USD = 10000000.0;
  
  // Storage keys
  static const String DAILY_SPENDING_KEY = 'daily_spending';
  static const String LAST_RESET_KEY = 'last_spending_reset';
  
  // Cache for quick access
  double? _cachedSpending;

  /// Check if a transaction would exceed daily limit
  /// Returns true if transaction is allowed, false if it exceeds limit
  Future<bool> canSendTransaction(double amountUSD) async {
    try {
      await _checkAndResetIfNeeded();
      
      final currentSpending = await getCurrentSpending();
      final newTotal = currentSpending + amountUSD;
      
      if (newTotal > DAILY_LIMIT_USD) {
        _logger.w('Transaction of \$$amountUSD would exceed daily limit. Current: \$$currentSpending, Limit: \$$DAILY_LIMIT_USD');
        return false;
      }
      
      return true;
    } catch (e) {
      _logger.e('Error checking spending limit: $e');
      // In case of error, allow the transaction but log it
      return true;
    }
  }

  /// Record a transaction spend (call this AFTER transaction succeeds)
  Future<void> recordTransaction(double amountUSD) async {
    try {
      await _checkAndResetIfNeeded();
      
      final currentSpending = await getCurrentSpending();
      final newSpending = currentSpending + amountUSD;
      
      await _storage.write(
        key: DAILY_SPENDING_KEY,
        value: newSpending.toString(),
      );
      
      _cachedSpending = newSpending;
      
      _logger.i('Recorded transaction: \$$amountUSD. Daily total: \$$newSpending / \$$DAILY_LIMIT_USD');
    } catch (e) {
      _logger.e('Error recording transaction: $e');
    }
  }

  /// Get current daily spending in USD
  Future<double> getCurrentSpending() async {
    try {
      if (_cachedSpending != null) {
        return _cachedSpending!;
      }
      
      await _checkAndResetIfNeeded();
      
      final spendingStr = await _storage.read(key: DAILY_SPENDING_KEY);
      final spending = spendingStr != null ? double.tryParse(spendingStr) ?? 0.0 : 0.0;
      
      _cachedSpending = spending;
      return spending;
    } catch (e) {
      _logger.e('Error getting current spending: $e');
      return 0.0;
    }
  }

  /// Get remaining daily limit in USD
  Future<double> getRemainingLimit() async {
    final currentSpending = await getCurrentSpending();
    return DAILY_LIMIT_USD - currentSpending;
  }

  /// Get spending limit utilization percentage (0-100)
  Future<double> getUtilizationPercentage() async {
    final currentSpending = await getCurrentSpending();
    return (currentSpending / DAILY_LIMIT_USD) * 100;
  }

  /// Check if it's a new day and reset if needed
  Future<void> _checkAndResetIfNeeded() async {
    try {
      final lastResetStr = await _storage.read(key: LAST_RESET_KEY);
      final today = DateTime.now().toUtc();
      final todayDate = DateTime.utc(today.year, today.month, today.day);
      
      if (lastResetStr == null) {
        // First time - initialize
        await _resetSpending(todayDate);
        return;
      }
      
      final lastReset = DateTime.tryParse(lastResetStr);
      if (lastReset == null) {
        await _resetSpending(todayDate);
        return;
      }
      
      // Check if it's a new day
      final lastResetDate = DateTime.utc(lastReset.year, lastReset.month, lastReset.day);
      if (todayDate.isAfter(lastResetDate)) {
        await _resetSpending(todayDate);
        _logger.i('Daily spending limit reset for new day: $todayDate');
      }
    } catch (e) {
      _logger.e('Error checking reset date: $e');
    }
  }

  /// Reset spending for a new day
  Future<void> _resetSpending(DateTime date) async {
    await _storage.write(key: DAILY_SPENDING_KEY, value: '0.0');
    await _storage.write(key: LAST_RESET_KEY, value: date.toIso8601String());
    _cachedSpending = 0.0;
  }

  /// Get time until next reset (in hours)
  Future<Duration> getTimeUntilReset() async {
    try {
      final lastResetStr = await _storage.read(key: LAST_RESET_KEY);
      if (lastResetStr == null) {
        return Duration.zero;
      }
      
      final lastReset = DateTime.tryParse(lastResetStr);
      if (lastReset == null) {
        return Duration.zero;
      }
      
      final now = DateTime.now().toUtc();
      final lastResetDate = DateTime.utc(lastReset.year, lastReset.month, lastReset.day);
      final nextReset = lastResetDate.add(const Duration(days: 1));
      
      return nextReset.difference(now);
    } catch (e) {
      _logger.e('Error getting time until reset: $e');
      return Duration.zero;
    }
  }

  /// Get daily spending history (for UI display)
  Future<Map<String, dynamic>> getSpendingSummary() async {
    final currentSpending = await getCurrentSpending();
    final remainingLimit = await getRemainingLimit();
    final utilizationPercent = await getUtilizationPercentage();
    final timeUntilReset = await getTimeUntilReset();
    
    return {
      'dailyLimit': DAILY_LIMIT_USD,
      'currentSpending': currentSpending,
      'remainingLimit': remainingLimit,
      'utilizationPercent': utilizationPercent,
      'timeUntilResetHours': timeUntilReset.inHours,
      'timeUntilResetMinutes': timeUntilReset.inMinutes % 60,
      'isNearLimit': utilizationPercent >= 80,
      'isAtLimit': utilizationPercent >= 95,
    };
  }

  /// Manually reset spending (for testing or admin purposes)
  Future<void> manualReset() async {
    final today = DateTime.now().toUtc();
    final todayDate = DateTime.utc(today.year, today.month, today.day);
    await _resetSpending(todayDate);
    _logger.i('Manual spending reset performed');
  }

  /// Get transaction validation result with details
  Future<SpendingValidationResult> validateTransaction(double amountUSD) async {
    try {
      await _checkAndResetIfNeeded();
      
      final currentSpending = await getCurrentSpending();
      final newTotal = currentSpending + amountUSD;
      final remaining = DAILY_LIMIT_USD - currentSpending;
      
      if (newTotal > DAILY_LIMIT_USD) {
        return SpendingValidationResult(
          isAllowed: false,
          currentSpending: currentSpending,
          dailyLimit: DAILY_LIMIT_USD,
          remainingLimit: remaining,
          attemptedAmount: amountUSD,
          excessAmount: newTotal - DAILY_LIMIT_USD,
          message: 'Transaction exceeds daily spending limit',
        );
      }
      
      // Check if close to limit (within 10%)
      final utilizationPercent = (newTotal / DAILY_LIMIT_USD) * 100;
      String? warningMessage;
      
      if (utilizationPercent >= 90) {
        warningMessage = 'Warning: You will have used ${utilizationPercent.toStringAsFixed(1)}% of your daily limit';
      } else if (utilizationPercent >= 80) {
        warningMessage = 'Notice: You will have used ${utilizationPercent.toStringAsFixed(1)}% of your daily limit';
      }
      
      return SpendingValidationResult(
        isAllowed: true,
        currentSpending: currentSpending,
        dailyLimit: DAILY_LIMIT_USD,
        remainingLimit: remaining - amountUSD,
        attemptedAmount: amountUSD,
        excessAmount: 0,
        message: warningMessage ?? 'Transaction allowed',
        isWarning: warningMessage != null,
      );
    } catch (e) {
      _logger.e('Error validating transaction: $e');
      return SpendingValidationResult(
        isAllowed: true,
        currentSpending: 0,
        dailyLimit: DAILY_LIMIT_USD,
        remainingLimit: DAILY_LIMIT_USD,
        attemptedAmount: amountUSD,
        excessAmount: 0,
        message: 'Error checking limit - transaction allowed',
        isWarning: true,
      );
    }
  }

  /// Clear all spending data (use with caution)
  Future<void> clearAllData() async {
    await _storage.delete(key: DAILY_SPENDING_KEY);
    await _storage.delete(key: LAST_RESET_KEY);
    _cachedSpending = null;
    _logger.w('All spending limit data cleared');
  }
}

/// Result of spending limit validation
class SpendingValidationResult {
  final bool isAllowed;
  final double currentSpending;
  final double dailyLimit;
  final double remainingLimit;
  final double attemptedAmount;
  final double excessAmount;
  final String message;
  final bool isWarning;

  SpendingValidationResult({
    required this.isAllowed,
    required this.currentSpending,
    required this.dailyLimit,
    required this.remainingLimit,
    required this.attemptedAmount,
    required this.excessAmount,
    required this.message,
    this.isWarning = false,
  });

  @override
  String toString() {
    return 'SpendingValidationResult(allowed: $isAllowed, current: \$$currentSpending, limit: \$$dailyLimit, message: $message)';
  }
}
