import 'dart:async';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

/// Идентификатор веб-клиента OAuth из Google Cloud (см. docs/setup.md).
/// Передаётся при сборке: --dart-define=GOOGLE_SERVER_CLIENT_ID=...
const googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

class NotSignedInException implements Exception {
  @override
  String toString() => 'Не выполнен вход в Google';
}

/// Вход через Google с доступом только к файлам, созданным приложением.
class GoogleAuth {
  static const scopes = ['https://www.googleapis.com/auth/drive.file'];

  GoogleSignInAccount? _user;
  Future<void>? _initialized;
  final _changes = StreamController<void>.broadcast();

  String? get email => _user?.email;
  bool get isConfigured => googleServerClientId.isNotEmpty;

  /// Срабатывает при входе и выходе.
  Stream<void> get changes => _changes.stream;

  Future<void> _init() => _initialized ??= () async {
        final signIn = GoogleSignIn.instance;
        await signIn.initialize(serverClientId: googleServerClientId);
        signIn.authenticationEvents.listen((event) {
          _user = switch (event) {
            GoogleSignInAuthenticationEventSignIn() => event.user,
            GoogleSignInAuthenticationEventSignOut() => null,
          };
          _changes.add(null);
        }, onError: (Object _) {});
      }();

  /// Вход без участия пользователя, если он уже входил раньше.
  Future<bool> signInSilently() async {
    if (!isConfigured) return false;
    try {
      await _init();
      _user = await GoogleSignIn.instance.attemptLightweightAuthentication() ??
          _user;
    } on GoogleSignInException {
      return false;
    }
    return _user != null;
  }

  /// Вход по нажатию кнопки: выбор аккаунта и согласие на доступ.
  Future<bool> signIn() async {
    await _init();
    _user = await GoogleSignIn.instance.authenticate(scopeHint: scopes);
    await _user!.authorizationClient.authorizeScopes(scopes);
    _changes.add(null);
    return true;
  }

  Future<void> signOut() async {
    await _init();
    await GoogleSignIn.instance.signOut();
    _user = null;
    _changes.add(null);
  }

  /// HTTP-клиент со свежим токеном. Токен живёт около часа,
  /// поэтому клиент запрашивается заново перед каждой синхронизацией.
  Future<http.Client> client() async {
    final user = _user;
    if (user == null) throw NotSignedInException();
    final authorization =
        await user.authorizationClient.authorizationForScopes(scopes);
    if (authorization == null) throw NotSignedInException();
    return authorization.authClient(scopes: scopes);
  }
}
