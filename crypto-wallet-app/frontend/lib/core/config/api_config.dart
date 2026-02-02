import 'package:flutter/foundation.dart';
import 'environment.dart';

/// API Configuration for Flutter Frontend
/// Handles development, staging, and production API endpoints
class ApiConfig {
  /// Get the appropriate base URL based on environment
  /// Uses EnvironmentConfig which has your local IP configured
  static String get baseUrl {
    return EnvironmentConfig.apiBaseUrl;
  }
  
  /// API endpoints
  static const String healthEndpoint = '/health';
  static const String walletGenerateEndpoint = '/api/wallet/generate';
  static const String walletRestoreEndpoint = '/api/wallet/restore';
  static const String balanceEndpoint = '/api/blockchain/balance';
  static const String sendEndpoint = '/api/blockchain/send';
  static const String swapQuoteEndpoint = '/api/swap/quote';
  static const String swapBuildEndpoint = '/api/swap/build';
  
  /// Request timeout durations
  static const Duration connectTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 30);
  static const Duration sendTimeout = Duration(seconds: 30);
  
  /// HTTPS Certificate fingerprints for certificate pinning (SHA-256)
  /// Railway uses Let's Encrypt certificates - these are the ISRG Root X1 fingerprints
  /// Generate fingerprint: openssl x509 -in cert.pem -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | openssl enc -base64
  static const Map<String, List<String>> certificateFingerprints = {
    // Development - disabled pinning for local testing
    'localhost:3000': [],
    
    // Railway Production - Let's Encrypt ISRG Root X1 and X2 fingerprints
    'amowallet-backend-production.up.railway.app': [
      // ISRG Root X1 (primary)
      'C5+lpZ7tcVwmwQIMcRtPbsQtWLABXhQzejna0wHFr8M=',
      // ISRG Root X2 (backup - ECDSA)
      'diGVwiVYbubAI3RW4hB9xU8e/CH2GnkuvVFZE8zmgzI=',
      // Let's Encrypt E1 intermediate
      'J2/oqMTsdhFWW/n85tys6b4yDBtb6idZayIEBx7QTxA=',
      // Let's Encrypt R3 intermediate (backup)
      'jQJTbIh0grw0/1TkHSumWb+Fs0Ggogr621gT3PvPKG0=',
    ],
  };
  
  /// Enable/disable certificate pinning
  /// ENABLED for production beta - validates SSL certificates against known fingerprints
  static const bool enableCertificatePinning = true;
  
  /// Get full URL for an endpoint
  static String getUrl(String endpoint) {
    return '$baseUrl$endpoint';
  }
  
  /// Check if API is available
  static Future<bool> checkHealth() async {
    try {
      // This would typically use Dio or http to check the health endpoint
      // Implement actual health check logic in your HTTP service
      return true;
    } catch (e) {
      return false;
    }
  }
}
