import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models.dart';
import 'api_client.dart';

/// عنوان الـ API. عدّله حسب بيئة النشر.
const String kApiBaseUrl = 'http://localhost:5080/api';

class SessionState {
  final AuthResult? auth;
  final int? activeCompanyId;
  final bool loaded;
  const SessionState({this.auth, this.activeCompanyId, this.loaded = false});

  bool get isLoggedIn => auth != null;
  int? get effectiveCompanyId => activeCompanyId ?? auth?.companyId;
  bool get needsCompanySelection =>
      auth != null && auth!.isSuperAdmin && activeCompanyId == null;

  SessionState copyWith({AuthResult? auth, int? activeCompanyId, bool? loaded, bool clearAuth = false, bool clearCompany = false}) =>
      SessionState(
        auth: clearAuth ? null : (auth ?? this.auth),
        activeCompanyId: clearCompany ? null : (activeCompanyId ?? this.activeCompanyId),
        loaded: loaded ?? this.loaded,
      );
}

class SessionNotifier extends Notifier<SessionState> {
  @override
  SessionState build() {
    _load();
    return const SessionState();
  }

  static const _kAuth = 'auth';
  static const _kCompany = 'activeCompanyId';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kAuth);
    AuthResult? auth;
    if (raw != null) {
      try {
        auth = AuthResult.fromJson(jsonDecode(raw));
      } catch (_) {}
    }
    final cid = prefs.getInt(_kCompany);
    state = SessionState(auth: auth, activeCompanyId: cid, loaded: true);
  }

  Future<void> setAuth(AuthResult auth) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAuth, jsonEncode(auth.toJson()));
    // المستخدم العادي: شركته من التوكن. السوبر أدمن: يختار لاحقاً.
    final cid = auth.companyId;
    if (cid != null) {
      await prefs.setInt(_kCompany, cid);
    } else {
      await prefs.remove(_kCompany);
    }
    state = SessionState(auth: auth, activeCompanyId: cid, loaded: true);
  }

  Future<void> setActiveCompany(int companyId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kCompany, companyId);
    state = state.copyWith(activeCompanyId: companyId);
  }

  Future<void> clearMustChange() async {
    final a = state.auth;
    if (a == null) return;
    final json = a.toJson()..['mustChangePassword'] = false;
    final updated = AuthResult.fromJson(json);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAuth, jsonEncode(updated.toJson()));
    state = state.copyWith(auth: updated);
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAuth);
    await prefs.remove(_kCompany);
    state = const SessionState(loaded: true);
  }
}

final sessionProvider =
    NotifierProvider<SessionNotifier, SessionState>(SessionNotifier.new);

/// عميل الـ API — يقرأ التوكن والشركة الفعّالة من الجلسة عند كل طلب.
final apiClientProvider = Provider<ApiClient>((ref) => ApiClient(
      baseUrl: kApiBaseUrl,
      token: () => ref.read(sessionProvider).auth?.accessToken,
      companyId: () => ref.read(sessionProvider).effectiveCompanyId,
    ));
