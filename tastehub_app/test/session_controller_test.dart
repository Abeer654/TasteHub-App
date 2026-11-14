import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tastehub_app/services/session_controller.dart';

import 'support/api_fixtures.dart';

Future<SharedPreferences> _prefs([
  Map<String, Object> values = const {},
]) async {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

void main() {
  test('starts logged out when no token was saved', () async {
    final prefs = await _prefs();
    final session = SessionController(api: fakeApiClient(), prefs: prefs);

    await session.restore();

    expect(session.restoring, isFalse);
    expect(session.isLoggedIn, isFalse);
    expect(session.user, isNull);
  });

  test('restores a saved token and validates it with the server', () async {
    final prefs = await _prefs({'auth_token': 'test-token-guest'});
    final api = fakeApiClient();
    final session = SessionController(api: api, prefs: prefs);

    await session.restore();

    expect(session.isLoggedIn, isTrue);
    expect(session.user?.username, 'guest');
    expect(api.token, 'test-token-guest');
  });

  test('discards a stale token', () async {
    final prefs = await _prefs({'auth_token': 'expired-token'});
    final api = fakeApiClient();
    final session = SessionController(api: api, prefs: prefs);

    await session.restore();

    expect(session.isLoggedIn, isFalse);
    expect(api.token, isNull);
    expect(prefs.getString(SessionController.tokenKey), isNull);
  });

  test('login saves the token and logout removes it', () async {
    final prefs = await _prefs();
    final api = fakeApiClient();
    final session = SessionController(api: api, prefs: prefs);

    await session.login('junaid', 'tastehub');

    expect(session.user?.id, 1);
    expect(prefs.getString(SessionController.tokenKey), 'test-token-junaid');
    expect(api.token, 'test-token-junaid');

    await session.logout();

    expect(session.isLoggedIn, isFalse);
    expect(prefs.getString(SessionController.tokenKey), isNull);
    expect(api.token, isNull);
  });
}
