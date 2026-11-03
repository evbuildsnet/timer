import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'session.dart';

/// Persists the session and the one-time onboarding flag.
final class Store {
  Store._(this._prefs);

  static const _sessionKey = 'session.v1';
  static const _onboardedKey = 'onboarded.v1';

  final SharedPreferencesWithCache _prefs;

  static Future<Store> open() async => Store._(
    await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(
        allowList: {_sessionKey, _onboardedKey},
      ),
    ),
  );

  Session get session {
    final raw = _prefs.getString(_sessionKey);
    if (raw == null) return const Selecting(Session.defaultMinutes);
    try {
      return Session.fromJson(jsonDecode(raw));
    } on FormatException {
      return const Selecting(Session.defaultMinutes);
    }
  }

  set session(Session value) => _prefs.setString(_sessionKey, jsonEncode(value.toJson()));

  bool get onboarded => _prefs.getBool(_onboardedKey) ?? false;

  set onboarded(bool value) => _prefs.setBool(_onboardedKey, value);
}
