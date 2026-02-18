/// Environment configuration for the Crypto Wallet App
/// Supports development, staging, and production environments
library;

enum Environment {
  development,
  staging,
  production,
}

class EnvironmentConfig {
  static Environment _currentEnvironment = Environment.development;
  
  /// Get current environment
  static Environment get current => _currentEnvironment;
  
  /// Set the environment (call this in main.dart before runApp)
  static void setEnvironment(Environment env) {
    _currentEnvironment = env;
  }
  
  /// Check if running in production
  static bool get isProduction => _currentEnvironment == Environment.production;
  
  /// Check if running in development
  static bool get isDevelopment => _currentEnvironment == Environment.development;
  
  /// Check if running in staging
  static bool get isStaging => _currentEnvironment == Environment.staging;
  
  /// Railway production URL
  static const String _productionUrl = 'https://amowallet-backend-production.up.railway.app';
  
  /// Get the API base URL for current environment
  static String get apiBaseUrl {
    switch (_currentEnvironment) {
      case Environment.development:
        // Use localhost for web/Chrome testing, network IP for mobile
        return 'http://localhost:3000'; // HTTP for local dev testing
      case Environment.staging:
        return _productionUrl; // Use Railway for staging
      case Environment.production:
        return _productionUrl; // Railway production URL
    }
  }
  
  /// Get WebSocket URL for current environment
  static String get wsBaseUrl {
    switch (_currentEnvironment) {
      case Environment.development:
        return 'ws://localhost:3000';
      case Environment.staging:
        return 'wss://amowallet-backend-production.up.railway.app';
      case Environment.production:
        return 'wss://amowallet-backend-production.up.railway.app';
    }
  }
  
  /// Whether to enable certificate pinning
  static bool get enableCertificatePinning {
    return false; // Disable for now until real server is setup
  }
  
  /// Whether to enable debug logging
  static bool get enableDebugLogging {
    return _currentEnvironment != Environment.production;
  }
  
  /// App name suffix for different environments
  static String get appNameSuffix {
    switch (_currentEnvironment) {
      case Environment.development:
        return ' (Dev)';
      case Environment.staging:
        return ' (Staging)';
      case Environment.production:
        return '';
    }
  }
}
