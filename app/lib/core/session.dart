import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
    const secureStorage = FlutterSecureStorage();
    final raw = await secureStorage.read(key: _kAuth) ?? prefs.getString(_kAuth);
    AuthResult? auth;
    if (raw != null) {
      try {
        auth = AuthResult.fromJson(jsonDecode(raw));
      } catch (_) {}
    }
    final cidStr = await secureStorage.read(key: _kCompany);
    final cid = cidStr != null ? int.tryParse(cidStr) : prefs.getInt(_kCompany);
    state = SessionState(auth: auth, activeCompanyId: cid, loaded: true);
  }

  Future<void> setAuth(AuthResult auth) async {
    const secureStorage = FlutterSecureStorage();
    await secureStorage.write(key: _kAuth, value: jsonEncode(auth.toJson()));
    // المستخدم العادي: شركته من التوكن. السوبر أدمن: يختار لاحقاً.
    final cid = auth.companyId;
    if (cid != null) {
      await secureStorage.write(key: _kCompany, value: cid.toString());
    } else {
      await secureStorage.delete(key: _kCompany);
    }
    state = SessionState(auth: auth, activeCompanyId: cid, loaded: true);

    // تنظيف التخزين القديم غير المشفر (إن وجد)
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAuth);
    await prefs.remove(_kCompany);
  }

  Future<void> setActiveCompany(int companyId) async {
    const secureStorage = FlutterSecureStorage();
    await secureStorage.write(key: _kCompany, value: companyId.toString());
    state = state.copyWith(activeCompanyId: companyId);
  }

  Future<void> clearMustChange() async {
    final a = state.auth;
    if (a == null) return;
    final json = a.toJson()..['mustChangePassword'] = false;
    final updated = AuthResult.fromJson(json);
    const secureStorage = FlutterSecureStorage();
    await secureStorage.write(key: _kAuth, value: jsonEncode(updated.toJson()));
    state = state.copyWith(auth: updated);
  }

  Future<void> logout() async {
    const secureStorage = FlutterSecureStorage();
    await secureStorage.delete(key: _kAuth);
    await secureStorage.delete(key: _kCompany);
    
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
