import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import 'session.dart';

/// الشركة الفعّالة — اسمُها وشعارُها (ADR-017).
///
/// 🔴 **نُقل من `home_shell.dart` إلى `core/`** (2026-09-09) لأن **القائمة الجانبية** صارت
/// تقرؤه كذلك: صدرُها يعرض اسم الشركة وشعارها لا اسم النظام. وبقاؤه في الشاشة كان يعني
/// أن يستورد `sidebar.dart` قشرتَه — **والقشرة تستورد القائمة أصلاً**، فتنشأ حلقة.
///
/// ⚠️ **ويُبطَل عند تبديل الشركة** (`home_shell` يفعل ذلك صراحةً) فيتبدّل الصدر والشريط
/// العلوي معاً — **مصدرٌ واحد لا مصدران يتباعدان**.
final activeCompanyProvider = FutureProvider.autoDispose<Company?>((ref) async {
  final api = ref.watch(apiClientProvider);
  final session = ref.watch(sessionProvider);
  if (session.effectiveCompanyId == null) return null;
  try {
    final companies = await api.companies();
    return companies
        .where((c) => c.companyId == session.effectiveCompanyId)
        .firstOrNull;
  } catch (_) {
    return null;
  }
});

/// رابط شعار الشركة الفعّالة — `null` لمن لا شعارَ لها.
///
/// ⚠️ **مشتقٌّ متزامن**: مزوّدٌ غير متزامن يراقب نظيره يُبطل نفسه، ولو وقع ذلك أثناء
/// استئناف اشتراكٍ موقوف في طور البناء **سقط الرسم** (العلّة المعالجة في
/// `profile_providers.dart`، وحارسُها في `test/provider_resume_test.dart`).
String? companyLogoUrl(Company? c) =>
    (c != null && c.logoImageKey != null && c.logoImageKey!.isNotEmpty)
        ? '$kApiBaseUrl/companies/${c.companyId}/logo'
        : null;
