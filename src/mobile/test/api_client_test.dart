import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:orderxpay_mobile/core/api_client.dart';
import 'package:orderxpay_mobile/core/session.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A request that never reaches the server at all (API not running, `adb
/// reverse` not forwarded on a physical device, no signal, DNS failure)
/// throws http.ClientException, not ApiException — every screen in the app
/// catches `on ApiException`, so before this was fixed, a network failure
/// propagated as an unhandled exception and the UI's only visible symptom
/// was a loading button quietly resetting to idle. This locks in the fix:
/// ApiClient must convert that into a catchable, user-facing ApiException,
/// while still letting a real HTTP error response through unchanged.
void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    Session.instance.token = null;
    Session.instance.merchantId = null;
  });

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

  test('createStaff normalizes the phone and defaults email to empty', () async {
    late String sentBody;
    final client = ApiClient(
      client: MockClient((request) async {
        sentBody = request.body;
        return http.Response(jsonEncode({'id': 's1'}), 201);
      }),
    );

    await client.createStaff(
      'm1',
      name: 'Ama Boateng',
      phone: '024 000 0000', // trunk 0 + spaces — how a merchant actually types it
      password: 'hunter222',
    );

    final decoded = jsonDecode(sentBody) as Map<String, dynamic>;
    expect(decoded['phone'], '+233240000000'); // matches what login will send
    expect(decoded['email'], '');
    expect(decoded['role'], 'staff');
  });

  test('resetPassword posts to the reset-password endpoint without a code or token', () async {
    late String sentPath;
    late String sentBody;
    final client = ApiClient(
      client: MockClient((request) async {
        sentPath = request.url.path;
        sentBody = request.body;
        return http.Response(jsonEncode({'reset': true}), 200);
      }),
    );

    final res = await client.resetPassword('+233244123456', 'NewSecret1');

    expect(sentPath, '/api/v1/public/auth/reset-password');
    final decoded = jsonDecode(sentBody) as Map<String, dynamic>;
    expect(decoded['phone'], '+233244123456');
    expect(decoded['new_password'], 'NewSecret1');
    expect(decoded.containsKey('code'), false); // the code was already spent by verifyOtp
    expect(res['reset'], true);
  });

  test('a plain-text error body no longer crashes _decode with a FormatException', () async {
    // Fiber's auth middleware serves "token has expired" as plain text.
    final client = ApiClient(
      client: MockClient((request) async => http.Response('service unavailable', 503)),
    );

    await expectLater(
      () => client.get('/api/v1/public/something'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 503)
            .having((e) => e.message, 'message', 'service unavailable'),
      ),
    );
  });

  test('a 401 on an authenticated route clears the session and reports it as expired', () async {
    Session.instance.token = 'stale-token';
    Session.instance.merchantId = 'm1';
    final client = ApiClient(
      client: MockClient((request) async => http.Response('token has expired', 401)),
    );

    await expectLater(
      () => client.listStaff('m1'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 401)
            .having((e) => e.message, 'message', contains('session has expired')),
      ),
    );
    expect(Session.instance.token, isNull, reason: 'the dead session should be cleared');
  });

  test('a 401 on a public route is NOT treated as session expiry', () async {
    Session.instance.token = 'some-token'; // e.g. a stale token still in memory
    final client = ApiClient(
      client: MockClient(
        (request) async => http.Response(jsonEncode({'error': 'invalid credentials'}), 401),
      ),
    );

    await expectLater(
      () => client.post('/api/v1/public/auth/login', {'phone': '+233200553771', 'password': 'wrong'}),
      throwsA(
        isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 401)
            .having((e) => e.message, 'message', 'invalid credentials'),
      ),
    );
    expect(Session.instance.token, 'some-token', reason: 'a login 401 must not clear the session');
  });
}
