import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistent key for duress mode - survives app restarts
const _kDuressModeActiveKey = 'duress_mode_permanently_active';

/// State for fake wallet mode (decoy wallet for duress PIN)
class FakeWalletState {
  final bool isActive;
  final bool isDuressMode; // true if activated by duress PIN

  const FakeWalletState({
    this.isActive = false,
    this.isDuressMode = false,
  });

  FakeWalletState copyWith({
    bool? isActive,
    bool? isDuressMode,
  }) =>
      FakeWalletState(
        isActive: isActive ?? this.isActive,
        isDuressMode: isDuressMode ?? this.isDuressMode,
      );
}

/// Notifier for managing fake wallet state
/// Duress mode is PERSISTENT - once activated, it survives app restarts
/// until the app is uninstalled and reinstalled.
class FakeWalletNotifier extends StateNotifier<FakeWalletState> {
  FakeWalletNotifier() : super(const FakeWalletState()) {
    _restorePersistedState();
  }

  /// Restore persisted duress mode on app restart
  Future<void> _restorePersistedState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isActive = prefs.getBool(_kDuressModeActiveKey) ?? false;
      if (isActive) {
        state = state.copyWith(isActive: true, isDuressMode: true);
        debugPrint('🎭 Duress mode restored from persistent storage');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to restore duress state: $e');
    }
  }

  /// Activate fake wallet mode (triggered by duress PIN detection)
  /// Persists to storage so it survives app restarts.
  Future<void> activateFakeWallet() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kDuressModeActiveKey, true);
      debugPrint('🎭 Duress mode PERSISTENTLY activated');
    } catch (e) {
      debugPrint('⚠️ Failed to persist duress activation: $e');
    }
    state = state.copyWith(isActive: true, isDuressMode: true);
  }

  /// Deactivate fake wallet - only possible by clearing persistent storage
  /// (i.e., app uninstall/reinstall clears SharedPreferences)
  Future<void> deactivateFakeWallet() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kDuressModeActiveKey);
    } catch (e) {
      debugPrint('⚠️ Failed to clear duress state: $e');
    }
    state = state.copyWith(isActive: false, isDuressMode: false);
  }

  /// Check if currently in fake wallet mode
  bool isInFakeWallet() => state.isActive;

  /// Get current fake wallet state
  FakeWalletState getState() => state;
}

/// Provider for fake wallet state management
final fakeWalletProvider =
    StateNotifierProvider<FakeWalletNotifier, FakeWalletState>((ref) {
  return FakeWalletNotifier();
});
