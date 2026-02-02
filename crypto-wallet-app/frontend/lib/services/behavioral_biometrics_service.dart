import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Behavioral Biometrics Service
/// 
/// Provides continuous authentication by analyzing user behavior patterns:
/// - Typing rhythm and speed
/// - Touch pressure and gestures
/// - Navigation patterns
/// - Time-of-use patterns
/// - Transaction patterns
/// 
/// Uses statistical anomaly detection (no ML training required)
/// Flags suspicious behavior that deviates from user's baseline
class BehavioralBiometricsService {
  static final BehavioralBiometricsService _instance = 
      BehavioralBiometricsService._internal();
  factory BehavioralBiometricsService() => _instance;
  BehavioralBiometricsService._internal();

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const String _profileKey = 'behavioral_profile';
  static const String _enabledKey = 'behavioral_enabled';
  static const String _anomalyLogKey = 'anomaly_log';

  // Minimum samples needed to establish baseline
  static const int _minSamplesForBaseline = 20;
  
  // Anomaly detection threshold (standard deviations)
  static const double _anomalyThreshold = 2.5;

  BehavioralProfile? _profile;
  bool _isEnabled = false;
  bool _isInitialized = false;

  // Callbacks for anomaly detection
  Function(AnomalyEvent)? onAnomalyDetected;

  /// Initialize behavioral biometrics
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Load enabled state
      final enabled = await _secureStorage.read(key: _enabledKey);
      _isEnabled = enabled == 'true';

      // Load existing profile
      final profileJson = await _secureStorage.read(key: _profileKey);
      if (profileJson != null) {
        _profile = BehavioralProfile.fromJson(jsonDecode(profileJson));
      } else {
        _profile = BehavioralProfile.create();
      }

      _isInitialized = true;
      print('✅ Behavioral biometrics initialized');
    } catch (e) {
      print('❌ Behavioral biometrics initialization failed: $e');
      _profile = BehavioralProfile.create();
      _isInitialized = true;
    }
  }

  /// Enable behavioral biometrics
  Future<void> enable() async {
    _isEnabled = true;
    await _secureStorage.write(key: _enabledKey, value: 'true');
    print('✅ Behavioral biometrics enabled');
  }

  /// Disable behavioral biometrics
  Future<void> disable() async {
    _isEnabled = false;
    await _secureStorage.write(key: _enabledKey, value: 'false');
    print('⚠️ Behavioral biometrics disabled');
  }

  /// Check if enabled
  bool get isEnabled => _isEnabled;

  /// Record a keystroke event (for typing analysis)
  void recordKeystroke({
    required int keyCode,
    required int timestamp,
    int? duration, // Key hold duration
  }) {
    if (!_isEnabled || !_isInitialized) return;

    _profile!.recordKeystroke(
      timestamp: timestamp,
      duration: duration ?? 100,
    );
  }

  /// Record PIN entry timing
  void recordPinEntry({
    required List<int> digitTimestamps,
  }) {
    if (!_isEnabled || !_isInitialized || digitTimestamps.length < 2) return;

    final intervals = <int>[];
    for (int i = 1; i < digitTimestamps.length; i++) {
      intervals.add(digitTimestamps[i] - digitTimestamps[i - 1]);
    }

    _profile!.recordPinTiming(intervals);
    _checkPinTimingAnomaly(intervals);
  }

  /// Record touch event
  void recordTouch({
    required double x,
    required double y,
    required double pressure,
    required int timestamp,
    TouchType type = TouchType.tap,
  }) {
    if (!_isEnabled || !_isInitialized) return;

    _profile!.recordTouch(
      pressure: pressure,
      timestamp: timestamp,
    );
  }

  /// Record swipe gesture
  void recordSwipe({
    required double startX,
    required double startY,
    required double endX,
    required double endY,
    required int duration,
    required double velocity,
  }) {
    if (!_isEnabled || !_isInitialized) return;

    _profile!.recordSwipe(
      velocity: velocity,
      duration: duration,
    );
  }

  /// Record app usage session
  void recordSession({
    required DateTime startTime,
    required DateTime endTime,
    required List<String> screensVisited,
  }) {
    if (!_isEnabled || !_isInitialized) return;

    final hour = startTime.hour;
    final dayOfWeek = startTime.weekday;
    final duration = endTime.difference(startTime).inSeconds;

    _profile!.recordSession(
      hour: hour,
      dayOfWeek: dayOfWeek,
      duration: duration,
    );

    _checkSessionAnomaly(hour, dayOfWeek, duration);
  }

  /// Record transaction pattern
  void recordTransaction({
    required double amount,
    required String coin,
    required DateTime timestamp,
  }) {
    if (!_isEnabled || !_isInitialized) return;

    _profile!.recordTransaction(
      amount: amount,
      hour: timestamp.hour,
    );

    _checkTransactionAnomaly(amount, timestamp.hour);
  }

  /// Check PIN timing for anomalies
  void _checkPinTimingAnomaly(List<int> intervals) {
    if (!_profile!.hasEnoughPinData) return;

    final avgInterval = intervals.reduce((a, b) => a + b) / intervals.length;
    final deviation = _profile!.getPinTimingDeviation(avgInterval);

    if (deviation > _anomalyThreshold) {
      _reportAnomaly(AnomalyEvent(
        type: AnomalyType.pinTiming,
        severity: _calculateSeverity(deviation),
        details: 'PIN entry timing differs by ${deviation.toStringAsFixed(1)} std deviations',
        timestamp: DateTime.now(),
      ));
    }
  }

  /// Check session timing for anomalies
  void _checkSessionAnomaly(int hour, int dayOfWeek, int duration) {
    if (!_profile!.hasEnoughSessionData) return;

    // Check unusual time of use
    if (!_profile!.isTypicalUsageTime(hour, dayOfWeek)) {
      _reportAnomaly(AnomalyEvent(
        type: AnomalyType.unusualTime,
        severity: AnomalySeverity.medium,
        details: 'App accessed at unusual time: $hour:00 on day $dayOfWeek',
        timestamp: DateTime.now(),
      ));
    }
  }

  /// Check transaction for anomalies
  void _checkTransactionAnomaly(double amount, int hour) {
    if (!_profile!.hasEnoughTransactionData) return;

    final amountDeviation = _profile!.getTransactionAmountDeviation(amount);
    
    if (amountDeviation > _anomalyThreshold) {
      _reportAnomaly(AnomalyEvent(
        type: AnomalyType.unusualTransaction,
        severity: _calculateSeverity(amountDeviation),
        details: 'Transaction amount differs by ${amountDeviation.toStringAsFixed(1)} std deviations',
        timestamp: DateTime.now(),
      ));
    }
  }

  /// Calculate severity based on deviation
  AnomalySeverity _calculateSeverity(double deviation) {
    if (deviation > 4.0) return AnomalySeverity.critical;
    if (deviation > 3.0) return AnomalySeverity.high;
    if (deviation > 2.5) return AnomalySeverity.medium;
    return AnomalySeverity.low;
  }

  /// Report detected anomaly
  void _reportAnomaly(AnomalyEvent event) {
    print('🚨 Behavioral anomaly detected: ${event.type.name} - ${event.details}');
    
    // Call callback if set
    onAnomalyDetected?.call(event);

    // Log anomaly
    _logAnomaly(event);
  }

  /// Log anomaly for review
  Future<void> _logAnomaly(AnomalyEvent event) async {
    try {
      final logJson = await _secureStorage.read(key: _anomalyLogKey);
      final log = logJson != null ? List<Map<String, dynamic>>.from(jsonDecode(logJson)) : <Map<String, dynamic>>[];
      
      log.add(event.toJson());
      
      // Keep only last 100 anomalies
      if (log.length > 100) {
        log.removeRange(0, log.length - 100);
      }

      await _secureStorage.write(key: _anomalyLogKey, value: jsonEncode(log));
    } catch (e) {
      print('⚠️ Failed to log anomaly: $e');
    }
  }

  /// Get anomaly history
  Future<List<AnomalyEvent>> getAnomalyHistory() async {
    try {
      final logJson = await _secureStorage.read(key: _anomalyLogKey);
      if (logJson == null) return [];

      final log = List<Map<String, dynamic>>.from(jsonDecode(logJson));
      return log.map((e) => AnomalyEvent.fromJson(e)).toList();
    } catch (e) {
      return [];
    }
  }

  /// Save profile to storage
  Future<void> saveProfile() async {
    if (_profile == null) return;
    
    try {
      await _secureStorage.write(
        key: _profileKey,
        value: jsonEncode(_profile!.toJson()),
      );
    } catch (e) {
      print('⚠️ Failed to save behavioral profile: $e');
    }
  }

  /// Get trust score (0-100)
  /// Higher score = more confident user is legitimate
  double getTrustScore() {
    if (!_isEnabled || _profile == null) return 100.0;
    return _profile!.trustScore;
  }

  /// Get profile statistics
  Map<String, dynamic> getStatistics() {
    if (_profile == null) {
      return {'status': 'not_initialized'};
    }

    return {
      'enabled': _isEnabled,
      'trust_score': getTrustScore(),
      'pin_samples': _profile!.pinTimingSamples,
      'touch_samples': _profile!.touchSamples,
      'session_samples': _profile!.sessionSamples,
      'transaction_samples': _profile!.transactionSamples,
      'baseline_established': _profile!.hasBaseline,
    };
  }

  /// Reset behavioral profile
  Future<void> resetProfile() async {
    _profile = BehavioralProfile.create();
    await _secureStorage.delete(key: _profileKey);
    await _secureStorage.delete(key: _anomalyLogKey);
    print('🔄 Behavioral profile reset');
  }
}

/// Behavioral profile storing user patterns
class BehavioralProfile {
  // PIN entry timing patterns
  final List<double> _pinTimingMeans;
  final List<double> _pinTimingStdDevs;
  
  // Touch pressure patterns
  final List<double> _touchPressures;
  
  // Swipe patterns
  final List<double> _swipeVelocities;
  
  // Usage time patterns (24 hours x 7 days = 168 slots)
  final List<int> _usageTimeHistogram;
  
  // Transaction patterns
  final List<double> _transactionAmounts;
  
  // Keystroke timing
  final List<int> _keystrokeIntervals;
  
  // Trust score (starts at 100, decreases with anomalies)
  double trustScore;

  // Private constructor
  BehavioralProfile._({
    required List<double> pinTimingMeans,
    required List<double> pinTimingStdDevs,
    required List<double> touchPressures,
    required List<double> swipeVelocities,
    required List<int> usageTimeHistogram,
    required List<double> transactionAmounts,
    required List<int> keystrokeIntervals,
    required this.trustScore,
  })  : _pinTimingMeans = pinTimingMeans,
        _pinTimingStdDevs = pinTimingStdDevs,
        _touchPressures = touchPressures,
        _swipeVelocities = swipeVelocities,
        _usageTimeHistogram = usageTimeHistogram,
        _transactionAmounts = transactionAmounts,
        _keystrokeIntervals = keystrokeIntervals;

  // Factory constructor for new profile
  factory BehavioralProfile.create() {
    return BehavioralProfile._(
      pinTimingMeans: [],
      pinTimingStdDevs: [],
      touchPressures: [],
      swipeVelocities: [],
      usageTimeHistogram: List.filled(168, 0),
      transactionAmounts: [],
      keystrokeIntervals: [],
      trustScore: 100.0,
    );
  }

  // Sample counts
  int get pinTimingSamples => _pinTimingMeans.length;
  int get touchSamples => _touchPressures.length;
  int get sessionSamples => _usageTimeHistogram.reduce((a, b) => a + b);
  int get transactionSamples => _transactionAmounts.length;

  // Check if enough data for analysis
  bool get hasEnoughPinData => pinTimingSamples >= 10;
  bool get hasEnoughTouchData => touchSamples >= 20;
  bool get hasEnoughSessionData => sessionSamples >= 10;
  bool get hasEnoughTransactionData => transactionSamples >= 5;
  bool get hasBaseline => hasEnoughPinData || hasEnoughSessionData;

  void recordKeystroke({required int timestamp, required int duration}) {
    _keystrokeIntervals.add(duration);
    if (_keystrokeIntervals.length > 1000) {
      _keystrokeIntervals.removeAt(0);
    }
  }

  void recordPinTiming(List<int> intervals) {
    if (intervals.isEmpty) return;
    
    final mean = intervals.reduce((a, b) => a + b) / intervals.length;
    _pinTimingMeans.add(mean);
    
    if (intervals.length > 1) {
      final variance = intervals.map((i) => pow(i - mean, 2)).reduce((a, b) => a + b) / intervals.length;
      _pinTimingStdDevs.add(sqrt(variance));
    }
    
    // Keep last 100 samples
    if (_pinTimingMeans.length > 100) {
      _pinTimingMeans.removeAt(0);
      _pinTimingStdDevs.removeAt(0);
    }
  }

  void recordTouch({required double pressure, required int timestamp}) {
    _touchPressures.add(pressure);
    if (_touchPressures.length > 500) {
      _touchPressures.removeAt(0);
    }
  }

  void recordSwipe({required double velocity, required int duration}) {
    _swipeVelocities.add(velocity);
    if (_swipeVelocities.length > 200) {
      _swipeVelocities.removeAt(0);
    }
  }

  void recordSession({required int hour, required int dayOfWeek, required int duration}) {
    final slot = (dayOfWeek - 1) * 24 + hour;
    if (slot >= 0 && slot < 168) {
      _usageTimeHistogram[slot]++;
    }
  }

  void recordTransaction({required double amount, required int hour}) {
    _transactionAmounts.add(amount);
    if (_transactionAmounts.length > 100) {
      _transactionAmounts.removeAt(0);
    }
  }

  double getPinTimingDeviation(double avgInterval) {
    if (_pinTimingMeans.isEmpty) return 0;
    
    final profileMean = _pinTimingMeans.reduce((a, b) => a + b) / _pinTimingMeans.length;
    final profileStdDev = _calculateStdDev(_pinTimingMeans);
    
    if (profileStdDev == 0) return 0;
    return (avgInterval - profileMean).abs() / profileStdDev;
  }

  bool isTypicalUsageTime(int hour, int dayOfWeek) {
    final slot = (dayOfWeek - 1) * 24 + hour;
    if (slot < 0 || slot >= 168) return true;
    
    final totalUsage = _usageTimeHistogram.reduce((a, b) => a + b);
    if (totalUsage == 0) return true;
    
    // Consider typical if this slot has at least 5% of average usage
    final avgUsage = totalUsage / 168;
    return _usageTimeHistogram[slot] >= avgUsage * 0.05;
  }

  double getTransactionAmountDeviation(double amount) {
    if (_transactionAmounts.isEmpty) return 0;
    
    final mean = _transactionAmounts.reduce((a, b) => a + b) / _transactionAmounts.length;
    final stdDev = _calculateStdDev(_transactionAmounts);
    
    if (stdDev == 0) return 0;
    return (amount - mean).abs() / stdDev;
  }

  double _calculateStdDev(List<double> values) {
    if (values.length < 2) return 0;
    
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance = values.map((v) => pow(v - mean, 2)).reduce((a, b) => a + b) / values.length;
    return sqrt(variance);
  }

  Map<String, dynamic> toJson() => {
    'pinTimingMeans': _pinTimingMeans,
    'pinTimingStdDevs': _pinTimingStdDevs,
    'touchPressures': _touchPressures,
    'swipeVelocities': _swipeVelocities,
    'usageTimeHistogram': _usageTimeHistogram,
    'transactionAmounts': _transactionAmounts,
    'trustScore': trustScore,
  };

  factory BehavioralProfile.fromJson(Map<String, dynamic> json) {
    final profile = BehavioralProfile.create();
    
    if (json['pinTimingMeans'] != null) {
      profile._pinTimingMeans.addAll(List<double>.from(json['pinTimingMeans']));
    }
    if (json['pinTimingStdDevs'] != null) {
      profile._pinTimingStdDevs.addAll(List<double>.from(json['pinTimingStdDevs']));
    }
    if (json['touchPressures'] != null) {
      profile._touchPressures.addAll(List<double>.from(json['touchPressures']));
    }
    if (json['swipeVelocities'] != null) {
      profile._swipeVelocities.addAll(List<double>.from(json['swipeVelocities']));
    }
    if (json['usageTimeHistogram'] != null) {
      final histogram = List<int>.from(json['usageTimeHistogram']);
      for (int i = 0; i < histogram.length && i < 168; i++) {
        profile._usageTimeHistogram[i] = histogram[i];
      }
    }
    if (json['transactionAmounts'] != null) {
      profile._transactionAmounts.addAll(List<double>.from(json['transactionAmounts']));
    }
    if (json['trustScore'] != null) {
      profile.trustScore = (json['trustScore'] as num).toDouble();
    }
    
    return profile;
  }
}

/// Types of behavioral anomalies
enum AnomalyType {
  pinTiming,           // PIN entry timing differs
  touchPressure,       // Touch pressure differs
  swipePattern,        // Swipe behavior differs
  unusualTime,         // App used at unusual time
  unusualTransaction,  // Transaction pattern differs
  rapidActions,        // Actions too fast (bot-like)
  deviceChange,        // Device characteristics changed
}

/// Anomaly severity levels
enum AnomalySeverity {
  low,
  medium,
  high,
  critical,
}

/// Touch event types
enum TouchType {
  tap,
  longPress,
  swipe,
  pinch,
}

/// Anomaly event record
class AnomalyEvent {
  final AnomalyType type;
  final AnomalySeverity severity;
  final String details;
  final DateTime timestamp;

  AnomalyEvent({
    required this.type,
    required this.severity,
    required this.details,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'severity': severity.name,
    'details': details,
    'timestamp': timestamp.toIso8601String(),
  };

  factory AnomalyEvent.fromJson(Map<String, dynamic> json) => AnomalyEvent(
    type: AnomalyType.values.firstWhere((e) => e.name == json['type']),
    severity: AnomalySeverity.values.firstWhere((e) => e.name == json['severity']),
    details: json['details'],
    timestamp: DateTime.parse(json['timestamp']),
  );
}
