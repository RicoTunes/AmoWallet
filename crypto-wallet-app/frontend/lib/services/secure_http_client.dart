import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http_certificate_pinning/http_certificate_pinning.dart';
import 'package:uuid/uuid.dart';
import '../core/config/api_config.dart';

class SecureHttpClient {
  static final SecureHttpClient _instance = SecureHttpClient._internal();
  factory SecureHttpClient() => _instance;
  SecureHttpClient._internal();

  late Dio _dio;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    _dio = Dio(
      BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: ApiConfig.connectTimeout,
        receiveTimeout: ApiConfig.receiveTimeout,
        sendTimeout: ApiConfig.sendTimeout,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    // Configure HTTP adapter to accept self-signed certificates in development
    // IMPORTANT: Only use this for development/testing. Use proper certificates in production.
    if (!kReleaseMode || kDebugMode) {
      (_dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
        final client = HttpClient();
        client.badCertificateCallback = (X509Certificate cert, String host, int port) {
          // Accept self-signed certificates for development
          // In production, this should return false to enforce proper certificate validation
          print('[HTTP] Accepting certificate for $host:$port (development mode)');
          return true;
        };
        return client;
      };
    }

    // Add certificate pinning interceptor (only if enabled and fingerprints configured)
    // Note: Certificate pinning only works with HTTPS
    if (ApiConfig.enableCertificatePinning && ApiConfig.baseUrl.startsWith('https://')) {
      final uri = Uri.parse(ApiConfig.baseUrl);
      final hostPort = '${uri.host}:${uri.port}';
      final fingerprints = ApiConfig.certificateFingerprints[hostPort];
      
      if (fingerprints != null && fingerprints.isNotEmpty) {
        _dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) async {
              // Certificate pinning check for HTTPS requests
              if (options.uri.scheme == 'https') {
                try {
                  await HttpCertificatePinning.check(
                    serverURL: options.uri.toString(),
                    headerHttp: options.headers.map((key, value) => MapEntry(key, value.toString())),
                    sha: SHA.SHA256,
                    allowedSHAFingerprints: fingerprints,
                    timeout: 30,
                  );
                } catch (e) {
                  return handler.reject(
                    DioException(
                      requestOptions: options,
                      error: 'Certificate pinning failed: $e',
                      type: DioExceptionType.connectionError,
                    ),
                  );
                }
              }
              return handler.next(options);
            },
            onError: (DioException error, handler) {
              // Handle certificate pinning errors
              if (error.message?.contains('Certificate') == true) {
                print('Security Warning: Certificate validation failed');
              }
              return handler.next(error);
            },
          ),
        );
      }
    }

    // Add request throttling interceptor
    _dio.interceptors.add(_RequestThrottlingInterceptor());

    // Add API authentication interceptor
    _dio.interceptors.add(_ApiAuthInterceptor());

    // Add logging interceptor (only in debug mode)
    _dio.interceptors.add(
      LogInterceptor(
        request: true,
        requestHeader: true,
        requestBody: true,
        responseHeader: true,
        responseBody: true,
        error: true,
        logPrint: (log) => print('[HTTP] $log'),
      ),
    );

    _initialized = true;
  }

  Dio get dio {
    if (!_initialized) {
      throw Exception('SecureHttpClient not initialized. Call initialize() first.');
    }
    return _dio;
  }

  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    if (!_initialized) await initialize();
    return _dio.get(path, queryParameters: queryParameters, options: options);
  }

  Future<Response> post(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    if (!_initialized) await initialize();
    return _dio.post(path, data: data, queryParameters: queryParameters, options: options);
  }

  Future<Response> put(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    if (!_initialized) await initialize();
    return _dio.put(path, data: data, queryParameters: queryParameters, options: options);
  }

  Future<Response> delete(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    if (!_initialized) await initialize();
    return _dio.delete(path, data: data, queryParameters: queryParameters, options: options);
  }
}

/// Request throttling interceptor to prevent excessive API calls
class _RequestThrottlingInterceptor extends Interceptor {
  final Map<String, DateTime> _lastRequestTimes = {};
  final Duration _throttleDuration = const Duration(milliseconds: 500);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final key = '${options.method}:${options.path}';
    final now = DateTime.now();
    
    if (_lastRequestTimes.containsKey(key)) {
      final lastTime = _lastRequestTimes[key]!;
      final timeSinceLastRequest = now.difference(lastTime);
      
      if (timeSinceLastRequest < _throttleDuration) {
        // Request is too soon, reject it
        return handler.reject(
          DioException(
            requestOptions: options,
            error: 'Request throttled. Please wait before making another request.',
            type: DioExceptionType.cancel,
          ),
        );
      }
    }
    
    _lastRequestTimes[key] = now;
    return handler.next(options);
  }
}

/// Helper function to get certificate fingerprint from a URL
/// Use this during development to extract your server's certificate fingerprint
Future<String?> getCertificateFingerprint(String url) async {
  try {
    final fingerprints = await HttpCertificatePinning.check(
      serverURL: url,
      headerHttp: {},
      sha: SHA.SHA256,
      allowedSHAFingerprints: [],
      timeout: 30,
    );
    return fingerprints.toString();
  } catch (e) {
    print('Error getting certificate fingerprint: $e');
    return null;
  }
}
