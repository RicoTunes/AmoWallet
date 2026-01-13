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
  
  /// HTTPS Certificate fingerprints for certificate pinning
  /// Generate fingerprint using:
  /// openssl x509 -in cert.pem -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | openssl enc -base64
  static const Map<String, List<String>> certificateFingerprints = {
    // Development (self-signed certificate)
    'localhost:3000': [
      'YOUR_DEV_CERTIFICATE_FINGERPRINT_HERE',
    ],
    
    // Production (Let's Encrypt certificate)
    'api.yourdomain.com': [
      'YOUR_PROD_CERTIFICATE_FINGERPRINT_HERE',
      // Include backup fingerprint for certificate rotation
      'YOUR_BACKUP_CERTIFICATE_FINGERPRINT_HERE',
    ],
  };
  
  /// Enable/disable certificate pinning
  /// IMPORTANT: Only enable when you have valid fingerprints configured
  static const bool enableCertificatePinning = false;
  
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
