import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

/// Service for managing API authentication with the backend
/// Implements HMAC-SHA256 request signing for secure communication
class ApiAuthService {
  static final ApiAuthService _instance = ApiAuthService._internal();
  factory ApiAuthService() => _instance;
  ApiAuthService._internal();

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const String _apiKeyKey = 'api_key';
  static const String _apiSecretKey = 'api_secret';

  String? _cachedApiKey;
  String? _cachedApiSecret;

  /// Get the stored API key
  Future<String?> getApiKey() async {
    _cachedApiKey ??= await _storage.read(key: _apiKeyKey);
    return _cachedApiKey;
  }

  /// Get the stored API secret
  Future<String?> getApiSecret() async {
    _cachedApiSecret ??= await _storage.read(key: _apiSecretKey);
    return _cachedApiSecret;
  }

  /// Check if API credentials are stored
  Future<bool> hasCredentials() async {
    final apiKey = await getApiKey();
    final apiSecret = await getApiSecret();
    return apiKey != null && apiSecret != null;
  }

  /// Store API credentials
  Future<void> storeCredentials(String apiKey, String apiSecret) async {
    await _storage.write(key: _apiKeyKey, value: apiKey);
    await _storage.write(key: _apiSecretKey, value: apiSecret);
    _cachedApiKey = apiKey;
    _cachedApiSecret = apiSecret;
  }

  /// Clear stored credentials
  Future<void> clearCredentials() async {
    await _storage.delete(key: _apiKeyKey);
    await _storage.delete(key: _apiSecretKey);
    _cachedApiKey = null;
    _cachedApiSecret = null;
  }

  /// Generate a new API key pair from the backend
  Future<Map<String, String>?> generateNewApiKey(String baseUrl) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/keys/generate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'description': 'AmoWallet Mobile App'}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final apiKey = data['data']['apiKey'] as String;
          final apiSecret = data['data']['apiSecret'] as String;
          
          // Store the credentials
          await storeCredentials(apiKey, apiSecret);
          
          return {
            'apiKey': apiKey,
            'apiSecret': apiSecret,
          };
        }
      }
      return null;
    } catch (e) {
      print('Error generating API key: $e');
      return null;
    }
  }

  /// Generate authentication headers for a request
  Future<Map<String, String>> getAuthHeaders({
    required String method,
    required String path,
    String body = '',
  }) async {
    final apiKey = await getApiKey();
    final apiSecret = await getApiSecret();

    if (apiKey == null || apiSecret == null) {
      // Return empty headers if no credentials (for unauthenticated endpoints)
      return {};
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final nonce = const Uuid().v4();

    // Create the message to sign (same format as backend expects)
    final message = '$method$path$timestamp$nonce$body';

    // Generate HMAC-SHA256 signature
    final hmac = Hmac(sha256, utf8.encode(apiSecret));
    final digest = hmac.convert(utf8.encode(message));
    final signature = digest.toString();

    return {
      'X-API-Key': apiKey,
      'X-Signature': signature,
      'X-Timestamp': timestamp,
      'X-Nonce': nonce,
      'Content-Type': 'application/json',
    };
  }

  /// Make an authenticated GET request
  Future<http.Response> authenticatedGet(String url) async {
    final uri = Uri.parse(url);
    final headers = await getAuthHeaders(
      method: 'GET',
      path: uri.path,
    );
    
    return http.get(uri, headers: headers);
  }

  /// Make an authenticated POST request
  Future<http.Response> authenticatedPost(String url, {Map<String, dynamic>? body}) async {
    final uri = Uri.parse(url);
    final bodyString = body != null ? jsonEncode(body) : '';
    final headers = await getAuthHeaders(
      method: 'POST',
      path: uri.path,
      body: bodyString,
    );
    
    return http.post(uri, headers: headers, body: bodyString);
  }

  /// Make an authenticated PUT request
  Future<http.Response> authenticatedPut(String url, {Map<String, dynamic>? body}) async {
    final uri = Uri.parse(url);
    final bodyString = body != null ? jsonEncode(body) : '';
    final headers = await getAuthHeaders(
      method: 'PUT',
      path: uri.path,
      body: bodyString,
    );
    
    return http.put(uri, headers: headers, body: bodyString);
  }

  /// Make an authenticated DELETE request
  Future<http.Response> authenticatedDelete(String url) async {
    final uri = Uri.parse(url);
    final headers = await getAuthHeaders(
      method: 'DELETE',
      path: uri.path,
    );
    
    return http.delete(uri, headers: headers);
  }

  /// Initialize API credentials if not already stored
  Future<bool> ensureCredentials(String baseUrl) async {
    if (await hasCredentials()) {
      return true;
    }
    
    final credentials = await generateNewApiKey(baseUrl);
    return credentials != null;
  }
}
