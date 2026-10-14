import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:t_aidy/core/services/secure_session_storage.dart';

void main() {
  const legacyKey = 'sb-project-auth-token';
  late Map<String, String> secure;
  late SecureSessionStorage storage;

  setUp(() {
    secure = {};
    storage = SecureSessionStorage(
      legacyPreferencesKey: legacyKey,
      read: (key) async => secure[key],
      write: (key, value) async => secure[key] = value,
      delete: (key) async => secure.remove(key),
    );
  });

  test('a session stored in plaintext preferences is moved to secure storage', () async {
    SharedPreferences.setMockInitialValues({legacyKey: '{"access_token":"a"}'});

    await storage.initialize();

    expect(secure[SecureSessionStorage.sessionKey], '{"access_token":"a"}');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(legacyKey), isFalse);
    expect(await storage.accessToken(), '{"access_token":"a"}');
  });

  test('sessions are persisted and removed in secure storage only', () async {
    SharedPreferences.setMockInitialValues({});
    await storage.initialize();
    expect(await storage.hasAccessToken(), isFalse);

    await storage.persistSession('{"access_token":"b"}');
    expect(secure[SecureSessionStorage.sessionKey], '{"access_token":"b"}');
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    expect(await storage.hasAccessToken(), isTrue);

    await storage.removePersistedSession();
    expect(await storage.hasAccessToken(), isFalse);
  });
}
