// ============================================================
//  session_controller.dart - who is logged in, and the saved token
//
//  The server uses one bearer token per account and only stores its
//  hash. The app keeps the plain token in shared_preferences so a
//  restart does not force another login.
// ============================================================

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user.dart';
import 'api_client.dart';
import 'api_exception.dart';

class SessionController extends ChangeNotifier {
  SessionController({required this.api, required this.prefs});

  static const String tokenKey = 'auth_token';

  final ApiClient api;

  /// Shared preferences are also used by ThemeController; the field is public
  /// so tests can inspect the saved token without a second lookup.
  final SharedPreferences prefs;

  User? _user;
  bool _restoring = true;

  User? get user => _user;
  bool get isLoggedIn => _user != null;
  bool get restoring => _restoring;

  /// Restores a saved token and validates it with /api/auth/me.
  /// An expired or unknown token is discarded.
  Future<void> restore() async {
    final saved = prefs.getString(tokenKey) ?? '';
    if (saved.isEmpty) {
      _restoring = false;
      notifyListeners();
      return;
    }

    api.token = saved;
    try {
      _user = await api.me();
    } on ApiException {
      api.token = null;
      await prefs.remove(tokenKey);
    } catch (_) {
      api.token = null;
    } finally {
      _restoring = false;
      notifyListeners();
    }
  }

  Future<void> login(String username, String password) async {
    final session = await api.login(username, password);
    await _store(session);
  }

  Future<void> signup(String username, String password) async {
    final session = await api.signup(username, password);
    await _store(session);
  }

  Future<void> logout() async {
    try {
      await api.logout();
    } on ApiException {
      // The token may already be invalid; logging out locally still works.
    }

    api.token = null;
    _user = null;
    await prefs.remove(tokenKey);
    notifyListeners();
  }

  Future<void> _store(AuthSession session) async {
    api.token = session.token;
    _user = session.user;
    await prefs.setString(tokenKey, session.token);
    notifyListeners();
  }
}
