import 'dart:convert';
import 'package:http/http.dart' as http;
import 'config.dart';

class ApiException implements Exception {
  ApiException(this.statusCode, this.message);
  final int statusCode;
  final String message;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// Thin wrapper around the Go API (src/api). Auth token attachment is a
/// TODO — depends on the OTP sign-in flow (Section 4.1), not yet built on
/// either side.
class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static final Uri _base = Uri.parse(AppConfig.apiBaseUrl);

  Future<Map<String, dynamic>> get(String path) async {
    final res = await _client.get(_base.resolve(path));
    return _decode(res);
  }

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final res = await _client.post(
      _base.resolve(path),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    return _decode(res);
  }

  Map<String, dynamic> _decode(http.Response res) {
    if (res.statusCode >= 400) {
      final body = res.body.isNotEmpty
          ? jsonDecode(res.body) as Map<String, dynamic>
          : <String, dynamic>{};
      throw ApiException(
        res.statusCode,
        body['error']?.toString() ?? res.reasonPhrase ?? 'request failed',
      );
    }
    if (res.body.isEmpty) return const {};
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}
