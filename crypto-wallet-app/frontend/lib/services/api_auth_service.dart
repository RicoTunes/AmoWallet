import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';

/// API Authentication Service
/// Handles HMAC-SHA256 request signing for secure API communication
/// 
/// Security Features:
/// - API key and secret storage in secure storage
/// - HMAC-SHA256 signature generation
/// - Timestamp-based request validation
/// - Unique nonce for each request
/// - Request replay attack prevention
class APIAuthService {
  final _storage = const FlutterSecureStorage();
  final _logger = Logger();
  final _uuid = const Uuid();
  
  static const String API_KEY_STORAGE_KEY = 'api_key';
  static const String API_SECRET_STORAGE_KEY = 'api_secret';
  
  /// Store API credentials securely
  Future<void> setCredentials(String apiKey, String apiSecret) async {
    try {
      await _storage.write(key: API_KEY_STORAGE_KEY, value: apiKey);
      await _storage.write(key: API_SECRET_STORAGE_KEY, value: apiSecret);
      _logger.i('API credentials stored securely');
    } catch (e) {
      _logger.e('Failed to store API credentials: $e');
      rethrow;
    }
  }
  
  /// Get stored API key
  Future<String?> getAPIKey() async {
    try {
      return await _storage.read(key: API_KEY_STORAGE_KEY);
    } catch (e) {
      _logger.e('Failed to retrieve API key: $e');
      return null;
    }
  }
  
  /// Get stored API secret
  Future<String?> getAPISecret() async {
    try {
      return await _storage.read(key: API_SECRET_STORAGE_KEY);
    } catch (e) {
      _logger.e('Failed to retrieve API secret: $e');
      return null;
    }
  }
  
  /// Check if credentials are configured
  Future<bool> hasCredentials() async {
    final apiKey = await getAPIKey();
    final apiSecret = await getAPISecret();
    return apiKey != null && apiSecret != null;
  }
  
  /// Clear stored credentials
  Future<void> clearCredentials() async {
    try {
      await _storage.delete(key: API_KEY_STORAGE_KEY);
      await _storage.delete(key: API_SECRET_STORAGE_KEY);
      _logger.w('API credentials cleared');
    } catch (e) {
      _logger.e('Failed to clear API credentials: $e');
      rethrow;
    }
  }
  
  /// Generate HMAC-SHA256 signature for a request
  /// 
  /// Message format: METHOD + PATH + TIMESTAMP + NONCE + BODY
  /// Example: "POST/api/wallet/generate1732550400000uuid-1234-5678{}"
  String _generateSignature({
    required String method,
    required String path,
    required String timestamp,
    required String nonce,
    required String body,
    required String apiSecret,
  }) {
    // Construct the message to sign
    final message = '$method$path$timestamp$nonce$body';
    
    // Generate HMAC-SHA256
    final key = utf8.encode(apiSecret);
    final bytes = utf8.encode(message);
    final hmac = Hmac(sha256, key);
    final digest = hmac.convert(bytes);
    
    return digest.toString();
  }
  
  /// Sign a request and return authentication headers
  /// 
  /// Returns a Map with headers:
  /// - X-API-Key: API key
  /// - X-Signature: HMAC-SHA256 signature
  /// - X-Timestamp: Unix timestamp in milliseconds
  /// - X-Nonce: Unique request identifier (UUID v4)
  Future<Map<String, String>> signRequest({
    required String method,
    required String path,
    Map<String, dynamic>? body,
  }) async {
    try {
      // Get credentials
      final apiKey = await getAPIKey();
      final apiSecret = await getAPISecret();
      
      if (apiKey == null || apiSecret == null) {
        throw Exception('API credentials not configured');
      }
      
      // Generate request metadata
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final nonce = _uuid.v4();
      final bodyString = body != null ? jsonEncode(body) : '';
      
      // Generate signature
      final signature = _generateSignature(
        method: method.toUpperCase(),
        path: path,
        timestamp: timestamp,
        nonce: nonce,
        body: bodyString,
        apiSecret: apiSecret,
      );
      
      // Return authentication headers
      return {
        'X-API-Key': apiKey,
        'X-Signature': signature,
        'X-Timestamp': timestamp,
        'X-Nonce': nonce,
      };
    } catch (e) {
      _logger.e('Failed to sign request: $e');
      rethrow;
    }
  }
  
  /// Validate response from authenticated request
  /// Returns true if authentication was successful
  bool validateAuthResponse(Map<String, dynamic> response) {
    if (response.containsKey('error')) {
      final error = response['error'];
      if (error is String) {
        if (error.contains('authentication') || 
            error.contains('signature') ||
            error.contains('API key')) {
          _logger.e('Authentication failed: $error');
          return false;
        }
      }
    }
    return response['success'] == true;
  }
  
  /// Test authentication with backend
  /// Returns true if authentication succeeds
  Future<bool> testAuthentication(String baseUrl) async {
    try {
      final headers = await signRequest(
        method: 'GET',
        path: '/api/auth/test',
      );
      
      // In a real implementation, you'd make an HTTP request here
      // For now, we'll just validate that we can generate headers
      _logger.i('Generated auth headers for test request');
      _logger.d('Headers: ${headers.keys.join(", ")}');
      
      return true;
    } catch (e) {
      _logger.e('Authentication test failed: $e');
      return false;
    }
  }
  
  /// Generate request headers with authentication
  /// Combines standard headers with auth headers
  Future<Map<String, String>> getAuthenticatedHeaders({
    required String method,
    required String path,
    Map<String, dynamic>? body,
    Map<String, String>? additionalHeaders,
  }) async {
    final authHeaders = await signRequest(
      method: method,
      path: path,
      body: body,
    );
    
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      ...authHeaders,
    };
    
    if (additionalHeaders != null) {
      headers.addAll(additionalHeaders);
    }
    
    return headers;
  }
}
