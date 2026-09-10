import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:orderxpay_mobile/core/api_client.dart';

/// A request that never reaches the server at all (API not running, `adb
/// reverse` not forwarded on a physical device, no signal, DNS failure)
/// throws http.ClientException, not ApiException — every screen in the app
/// catches `on ApiException`, so before this was fixed, a network failure
/// propagated as an unhandled exception and the UI's only visible symptom
/// was a loading button quietly resetting to idle. This locks in the fix:
/// ApiClient must convert that into a catchable, user-facing ApiException,
/// while still letting a real HTTP error response through unchanged.
void main() {
  test('a network failure becomes a catchable ApiException with a clear message', () async {
    final client = ApiClient(
      client: MockClient((request) async => throw http.ClientException('Connection refused')),
    );

    await expectLater(
      () => client.post('/api/v1/public/otp/request', {'phone': '+233200553771'}),
      throwsA(
        isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 0)
            .having((e) => e.message, 'message', contains("Can't reach the server")),
      ),
    );
  });

  test('a real HTTP error response still throws its own ApiException unchanged', () async {
    final client = ApiClient(
      client: MockClient(
        (request) async => http.Response(jsonEncode({'error': 'phone not verified'}), 400),
      ),
    );

    await expectLater(
      () => client.post('/api/v1/public/otp/verify', {'phone': '+233200553771', 'code': '000000'}),
      throwsA(
        isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 400)
            .having((e) => e.message, 'message', 'phone not verified'),
      ),
    );
  });

  test('a successful response still decodes normally', () async {
    final client = ApiClient(
      client: MockClient((request) async => http.Response(jsonEncode({'dev_otp': '123456'}), 200)),
    );

    final res = await client.post('/api/v1/public/otp/request', {'phone': '+233200553771'});
    expect(res['dev_otp'], '123456');
  });
}
