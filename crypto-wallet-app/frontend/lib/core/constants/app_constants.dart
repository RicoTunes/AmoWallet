class AppConstants {
  static const String appName = 'CryptoWallet Pro';
  static const String appVersion = '1.0.0';
  static const String appDescription = 'Professional Multi-Chain Crypto Wallet';

  // API Configuration
  static const String baseUrl = 'http://localhost:3000';
  static const String apiBaseUrl = '$baseUrl/api';
  static const String wsUrl = 'ws://localhost:3000';

  // Network RPC URLs
  static const Map<String, String> rpcUrls = {
    'ethereum': 'https://mainnet.infura.io/v3/YOUR_INFURA_KEY',
    'bsc': 'https://bsc-dataseed1.binance.org/',
    'tron': 'https://api.trongrid.io',
  };

  // Supported Networks
  static const List<String> supportedNetworks = [
    'ethereum',
    'bsc',
    'tron',
  ];

  // Default Tokens
  static const Map<String, List<String>> defaultTokens = {
    'ethereum': ['ETH', 'USDT', 'USDC', 'WBTC', 'DAI'],
    'bsc': ['BNB', 'BUSD', 'USDT', 'USDC', 'CAKE'],
    'tron': ['TRX', 'USDT', 'USDC', 'JST', 'SUN'],
  };

  // Fee Structure
  static const Map<String, dynamic> feeStructure = {
    'instant_swap': {
      'tiers': [
        {'min': 100, 'max': 500, 'rate': 0.005},
        {'min': 1000, 'max': 4999, 'rate': 0.003},
        {'min': 5000, 'max': 9999, 'rate': 0.002},
        {'min': 10000, 'max': 84999, 'rate': 0.0008},
        {'min': 85000, 'max': 100000, 'rate': 0.0008, 'minFee': 100},
        {'min': 100001, 'rate': 0.0008},
      ],
    },
    'spot_trading': {
      'tiers': [
        {'min': 0, 'max': 50000, 'rate': 0.001},
        {'min': 50000, 'max': 100000, 'rate': 0.001, 'minFee': 100},
        {'min': 100001, 'rate': 0.0008},
      ],
    },
  };

  // Security Constants
  static const int pinMaxLength = 6;
  static const int mnemonicWordCount = 12;
  static const int maxLoginAttempts = 5;
  static const Duration sessionTimeout = Duration(hours: 24);

  // UI Constants
  static const double defaultPadding = 16.0;
  static const double defaultBorderRadius = 12.0;
  static const double cardElevation = 2.0;
  static const Duration animationDuration = Duration(milliseconds: 300);

  // Storage Keys
  static const String storageWalletKey = 'wallet_data';
  static const String storagePinHashKey = 'pin_hash';
  static const String storageBiometricEnabledKey = 'biometric_enabled';
  static const String storageThemeModeKey = 'theme_mode';
  static const String storageLanguageKey = 'language';
}