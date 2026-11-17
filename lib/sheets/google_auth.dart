import 'dart:async';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../data/stores.dart';

/// Идентификатор веб-клиента OAuth из Google Cloud (см. docs/setup.md).
/// Передаётся при сборке: --dart-define=GOOGLE_SERVER_CLIENT_ID=...
const googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

class NotSignedInException implements Exception {
  @override
  String toString() => 'Не выполнен вход в Google';
}

/// Вход через Google с доступом только к файлам, созданным приложением.
class GoogleAuth {
  GoogleAuth(this._meta);

  static const scopes = ['https://www.googleapis.com/auth/drive.file'];
  static const _emailKey = 'google_email';

  /// Почта хранится на телефоне: по ней при запуске понятно, что вход
  /// уже был, и окно выбора аккаунта не показывается.
  final MetaStore _meta;
  String? _email;
  Future<void>? _initialized;
  final _changes = StreamController<void>.broadcast();

  String? get email => _email;
  bool get isConfigured => googleServerClientId.isNotEmpty;

  /// Срабатывает при входе и выходе.
  Stream<void> get changes => _changes.stream;

  Future<void> _init() => _initialized ??= () async {
        final signIn = GoogleSignIn.instance;
        await signIn.initialize(serverClientId: googleServerClientId);
        signIn.authenticationEvents.listen((event) {
          _email = switch (event) {
            GoogleSignInAuthenticationEventSignIn() => event.user.email,
            GoogleSignInAuthenticationEventSignOut() => null,
          };
          _changes.add(null);
        }, onError: (Object _) {});
      }();

  /// Вход без участия пользователя, если он уже входил раньше и дал доступ.
  /// Никаких окон не показывает: без сохранённого входа просто вернёт false.
  Future<bool> signInSilently() async {
    if (!isConfigured) return false;
    try {
      final saved = await _meta.get(_emailKey);
      if (saved == null || saved.isEmpty) return false;
      await _init();
      final authorization = await GoogleSignIn.instance.authorizationClient
          .authorizationForScopes(scopes);
      if (authorization == null) return false;
      _email = saved;
    } on GoogleSignInException {
      return false;
    }
    _changes.add(null);
    return true;
  }

  /// Вход по нажатию кнопки: выбор аккаунта и согласие на доступ.
  Future<bool> signIn() async {
    await _init();
    try {
      final user =
          await GoogleSignIn.instance.authenticate(scopeHint: scopes);
      await user.authorizationClient.authorizeScopes(scopes);
      _email = user.email;
      await _meta.set(_emailKey, user.email);
    } on GoogleSignInException catch (e) {
      // Пользователь закрыл окно выбора аккаунта — это не ошибка.
      if (e.code == GoogleSignInExceptionCode.canceled) return false;
      rethrow;
    }
    _changes.add(null);
    return true;
  }

  Future<void> signOut() async {
    await _init();
    await GoogleSignIn.instance.signOut();
    _email = null;
    await _meta.set(_emailKey, null);
    _changes.add(null);
  }

  /// HTTP-клиент со свежим токеном. Токен живёт около часа,
  /// поэтому клиент запрашивается заново перед каждой синхронизацией.
  Future<http.Client> client() async {
    if (_email == null) throw NotSignedInException();
    await _init();
    final authorization = await GoogleSignIn.instance.authorizationClient
        .authorizationForScopes(scopes);
    if (authorization == null) throw NotSignedInException();
    return authorization.authClient(scopes: scopes);
  }
}
