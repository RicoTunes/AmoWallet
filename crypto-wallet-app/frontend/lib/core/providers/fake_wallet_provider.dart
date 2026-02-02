import 'package:flutter_riverpod/flutter_riverpod.dart';

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
class FakeWalletNotifier extends StateNotifier<FakeWalletState> {
  FakeWalletNotifier() : super(const FakeWalletState());

  /// Activate fake wallet mode (triggered by duress PIN detection)
  void activateFakeWallet() {
    state = state.copyWith(
      isActive: true,
      isDuressMode: true,
    );
  }

  /// Deactivate fake wallet and return to real wallet
  void deactivateFakeWallet() {
    state = state.copyWith(
      isActive: false,
      isDuressMode: false,
    );
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
