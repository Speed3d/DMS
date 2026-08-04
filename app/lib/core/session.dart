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

  /// دخل النظام بلا شركة فعّالة (نظام فارغ — للسوبر أدمن لإنشاء أول شركة).
  /// يتيح تجاوز شاشة اختيار الشركة دون إرسال معرّف شركة زائف.
  final bool bypassCompanySelection;

  const SessionState({this.auth, this.activeCompanyId, this.loaded = false, this.bypassCompanySelection = false});

  bool get isLoggedIn => auth != null;

  /// الشركة الفعّالة — **مقيّدة بشركات المستخدم الحالي**.
  ///
  /// ⚠️ `activeCompanyId` محفوظ على الجهاز، فقد يبقى من مستخدم سابق (سوبر أدمن اختار شركة
  /// ثم دخل موظفٌ لا يملكها). كان يُمرَّر كما هو في ترويسة `X-Company-Id`، فتعود القوائم
  /// فارغة بلا أي رسالة — لأن صلاحيات الشركة الخاطئة **تفشل مغلقةً** (ADR-017).
  /// نتجاهله هنا إن لم يكن ضمن شركات المستخدم بدل أن نُسلّمه للخادم.
  int? get effectiveCompanyId {
    // السوبر أدمن غير مقيّد بقائمة شركات (قائمته فارغة أصلاً) — يختار أيّها شاء.
    if (auth?.isSuperAdmin == true) return activeCompanyId;

    final allowed = auth?.companyIds ?? const <int>[];
    if (activeCompanyId != null && allowed.contains(activeCompanyId)) return activeCompanyId;
    return allowed.isNotEmpty ? allowed.first : null;
  }
  bool get needsCompanySelection =>
      auth != null && (auth!.companyIds.length > 1 || auth!.isSuperAdmin) && activeCompanyId == null && !bypassCompanySelection;

  // ── الصلاحيات تخصّ **الشركة الفعّالة** (ADR-017) ──
  // Hint: مركزيّتها هنا تمنع أن تنسى شاشةٌ تمريرَ الشركة فتعرض قسماً لا يملكه المستخدم فيها.

  /// أقسام النظام المسموحة في الشركة الفعّالة (المعفَون يرون الكل).
  List<String> get modules => auth?.modulesIn(effectiveCompanyId) ?? const [];

  bool hasModule(String module) => auth?.hasModule(module, effectiveCompanyId) ?? false;

  /// صلاحية اعتماد الصادر في الشركة الفعّالة.
  bool get canApprove => auth?.canApproveIn(effectiveCompanyId) ?? false;

  /// صلاحية **إدارة** الموظفين والرواتب في الشركة الفعّالة (ADR-023).
  ///
  /// قسم `HR` يفتح الرؤية وهذا يفتح الكتابة — فمن يراه بلا هذا العلَم يقرأ ولا يحرّر.
  bool get canManageHr => auth?.canManageHrIn(effectiveCompanyId) ?? false;

  /// هل تظهر وحدة الموظفين والرواتب أصلاً؟ (القسم **مع** الدور — مرآةٌ لـ`[RequireHrModule]`)
  ///
  /// ⚠️ الحدّان معاً لا أحدهما: الباك-إند يرفض بـ403 من كان دونه المدير مهما مُنح من أقسام،
  /// وإظهار بندٍ في الشريط يقود إلى شاشة تردّ 403 أسوأ من إخفائه.
  bool get canSeeHr =>
      hasModule('HR') &&
      const ['SuperAdmin', 'President', 'Manager'].contains(auth?.role);

  SessionState copyWith({AuthResult? auth, int? activeCompanyId, bool? loaded, bool? bypassCompanySelection, bool clearAuth = false, bool clearCompany = false}) =>
      SessionState(
        auth: clearAuth ? null : (auth ?? this.auth),
        activeCompanyId: clearCompany ? null : (activeCompanyId ?? this.activeCompanyId),
        loaded: loaded ?? this.loaded,
        bypassCompanySelection: bypassCompanySelection ?? this.bypassCompanySelection,
      );
}

class SessionNotifier extends Notifier<SessionState> {
  /// هل استُبدلت الجلسة (دخول/خروج) بينما كان `_load` ما زال يقرأ التخزين؟
  ///
  /// Hint: `_load` غير مُنتظَر في `build`، وكان يكتب الحالة عند انتهائه **بلا شرط** —
  /// فإن سجّل المستخدم دخوله قبل أن يقرأ التخزين، عاد `_load` بقيمٍ قديمة (أو `null`)
  /// و**مسح الجلسة الجديدة**. وهذا ما جعل أول دخول يبدو فارغاً ثم يعمل بعد إعادة الدخول.
  bool _sessionReplaced = false;

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

    // لا نكتب فوق جلسة أُنشئت بعد أن بدأت القراءة — نكتفي بوسم التحميل منتهياً.
    if (_sessionReplaced) {
      state = state.copyWith(loaded: true);
      return;
    }
    state = SessionState(auth: auth, activeCompanyId: cid, loaded: true);
  }

  Future<void> setAuth(AuthResult auth) async {
    _sessionReplaced = true;
    const secureStorage = FlutterSecureStorage();
    await secureStorage.write(key: _kAuth, value: jsonEncode(auth.toJson()));
    // إذا لم يكن لديه شركات، cid = null
    final cid = auth.companyIds.isNotEmpty ? auth.companyIds.first : null;
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

  /// تحديث الجلسة بعد تجديد التوكن تلقائياً — يحفظ التوكن الجديد (وقائمة الشركات المحدّثة)
  /// مع **الإبقاء على الشركة الفعّالة المختارة** (لا يُعاد ضبطها كما في setAuth).
  Future<void> refreshAuth(AuthResult auth) async {
    const secureStorage = FlutterSecureStorage();
    await secureStorage.write(key: _kAuth, value: jsonEncode(auth.toJson()));
    state = state.copyWith(auth: auth);
  }

  Future<void> setActiveCompany(int companyId) async {
    const secureStorage = FlutterSecureStorage();
    await secureStorage.write(key: _kCompany, value: companyId.toString());
    state = state.copyWith(activeCompanyId: companyId, bypassCompanySelection: false);
  }

  /// دخول بلا شركة (نظام فارغ) — يتجاوز شاشة الاختيار ليتمكّن السوبر أدمن من إنشاء أول شركة.
  void enterWithoutCompany() {
    state = state.copyWith(bypassCompanySelection: true);
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
    _sessionReplaced = true;
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
      refreshToken: () => ref.read(sessionProvider).auth?.refreshToken,
      onRefreshed: (auth) => ref.read(sessionProvider.notifier).refreshAuth(auth),
      onRefreshFailed: () => ref.read(sessionProvider.notifier).logout(),
    ));
