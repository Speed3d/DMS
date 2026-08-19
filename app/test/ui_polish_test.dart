import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dms_app/core/profile_providers.dart';
import 'package:dms_app/core/session.dart';
import 'package:dms_app/models.dart';
import 'package:dms_app/widgets/password_field.dart';
import 'package:dms_app/widgets/search_field.dart';
import 'package:dms_app/widgets/topbar.dart';

/// حرّاس الدفعة **ب** من ملاحظات المالك (2026-08-20):
/// البحث الحيّ · إظهار كلمة المرور · الشريط العلوي.
///
/// 🔴 **كلاهما منطقٌ في ودجةٍ مشتركة لا في ثلاث شاشات** — فالحارس هنا يحرس الشاشات
/// الثلاث معاً، وأيّ شاشةٍ تستعمل الودجة ترث سلوكاً مُثبَتاً.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: child),
          ),
        ),
      );

  // ══════════════════ البحث الحيّ ══════════════════

  group('🔍 البحث الحيّ — بلا Enter، وبلا إغراق الخادم', () {
    testWidgets('🔴 لا يبحث عند أول حرف مباشرةً — بل بعد سكونٍ قصير', (tester) async {
      final calls = <String>[];
      await pump(tester, DebouncedSearchField(
        hintText: 'ابحث', onChanged: calls.add,
        debounce: const Duration(milliseconds: 200)));

      await tester.enterText(find.byType(TextField), 'D');
      await tester.pump(const Duration(milliseconds: 50));
      // ⚠️ **بيت الفائدة**: بلا مهلة يصير «DEN-IN-2026» اثني عشر طلباً للخادم.
      expect(calls, isEmpty, reason: 'بحثَ قبل أن يسكن المستخدم');

      await tester.pump(const Duration(milliseconds: 250));
      expect(calls, ['D'], reason: 'لم يبحث بعد السكون');
    });

    testWidgets('🔴 والكتابة المتتابعة تُنتج طلباً واحداً لا طلباً لكل حرف',
        (tester) async {
      final calls = <String>[];
      await pump(tester, DebouncedSearchField(
        hintText: 'ابحث', onChanged: calls.add,
        debounce: const Duration(milliseconds: 200)));

      for (final t in ['D', 'DE', 'DEN', 'DEN-']) {
        await tester.enterText(find.byType(TextField), t);
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(calls, isEmpty);

      await tester.pump(const Duration(milliseconds: 250));
      expect(calls, ['DEN-'], reason: 'يجب أن يصل آخر نصٍّ فقط، مرّةً واحدة');
    });

    testWidgets('Enter يبحث فوراً بلا انتظار — ولا يُكرّر بعده', (tester) async {
      final calls = <String>[];
      await pump(tester, DebouncedSearchField(
        hintText: 'ابحث', onChanged: calls.add,
        debounce: const Duration(milliseconds: 200)));

      await tester.enterText(find.byType(TextField), '90');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(calls, ['90'], reason: 'Enter لم يبحث فوراً');

      // ⚠️ والمؤقّت المعلّق يُلغى — وإلا وقع طلبٌ ثانٍ بالنصّ نفسه بعد المهلة.
      await tester.pump(const Duration(milliseconds: 300));
      expect(calls, ['90'], reason: 'تكرّر الطلب بعد Enter');
    });

    testWidgets('🔴 ونصٌّ لم يتغيّر لا يُعيد الجلب', (tester) async {
      final calls = <String>[];
      await pump(tester, DebouncedSearchField(
        hintText: 'ابحث', onChanged: calls.add,
        debounce: const Duration(milliseconds: 100)));

      await tester.enterText(find.byType(TextField), 'ن');
      await tester.pump(const Duration(milliseconds: 150));
      await tester.enterText(find.byType(TextField), 'ن');
      await tester.pump(const Duration(milliseconds: 150));
      expect(calls, ['ن'], reason: 'أعاد الجلب بنصٍّ لم يتغيّر');
    });

    testWidgets('زرّ المسح يظهر عند الكتابة ويعيد القائمة فوراً', (tester) async {
      final calls = <String>[];
      await pump(tester, DebouncedSearchField(
        hintText: 'ابحث', onChanged: calls.add,
        debounce: const Duration(milliseconds: 100)));

      expect(find.byTooltip('مسح البحث'), findsNothing);
      await tester.enterText(find.byType(TextField), 'شيء');
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.byTooltip('مسح البحث'), findsOneWidget);

      await tester.tap(find.byTooltip('مسح البحث'));
      await tester.pump();
      expect(calls.last, '', reason: 'المسح لم يُعد القائمة كاملةً');
    });

    testWidgets('🔴 والمتحكّم الخارجيّ يحمل النصّ — فالشاشة تقرأه عند الجلب',
        (tester) async {
      // الشاشات تجلب بـ`_search.text`، فلو لم يصل النصّ إلى المتحكّم لبحثت بفراغ.
      final controller = TextEditingController();
      await pump(tester, DebouncedSearchField(
        controller: controller, hintText: 'ابحث', onChanged: (_) {},
        debounce: const Duration(milliseconds: 50)));

      await tester.enterText(find.byType(TextField), 'DEN-IN-2026-00090');
      await tester.pump(const Duration(milliseconds: 100));
      expect(controller.text, 'DEN-IN-2026-00090');
    });

    testWidgets('⚠️ ولا ينهار إن أُزيلت الشاشة والمؤقّت معلّق', (tester) async {
      final calls = <String>[];
      await pump(tester, DebouncedSearchField(
        hintText: 'ابحث', onChanged: calls.add,
        debounce: const Duration(milliseconds: 200)));

      await tester.enterText(find.byType(TextField), 'x');
      await tester.pump(const Duration(milliseconds: 50));
      await pump(tester, const SizedBox()); // إزالة الحقل والمؤقّت معلّق
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(calls, isEmpty, reason: 'نُودي بعد الإزالة');
    });
  });

  // ══════════════════ إظهار كلمة المرور ══════════════════

  group('👁️ كلمة المرور تُعرض بطلب صاحبها', () {
    testWidgets('🔴 مخفيّةٌ افتراضاً — ولا تُحفظ رغبة الإظهار', (tester) async {
      await pump(tester, PasswordField(
          controller: TextEditingController(), labelText: 'كلمة المرور'));

      expect(tester.widget<TextField>(find.byType(TextField)).obscureText, isTrue);
      expect(find.byTooltip('إظهار كلمة المرور'), findsOneWidget);
    });

    testWidgets('🔴 والضغط يُظهرها ثم يُخفيها', (tester) async {
      await pump(tester, PasswordField(
          controller: TextEditingController(), labelText: 'كلمة المرور'));

      await tester.tap(find.byTooltip('إظهار كلمة المرور'));
      await tester.pump();
      expect(tester.widget<TextField>(find.byType(TextField)).obscureText, isFalse,
          reason: 'الزرّ لم يُظهر شيئاً');
      expect(find.byTooltip('إخفاء كلمة المرور'), findsOneWidget);

      await tester.tap(find.byTooltip('إخفاء كلمة المرور'));
      await tester.pump();
      expect(tester.widget<TextField>(find.byType(TextField)).obscureText, isTrue);
    });

    testWidgets('⚠️ بلا اقتراحاتٍ ولا تصحيحٍ تلقائيّ على كلمة المرور',
        (tester) async {
      await pump(tester, PasswordField(
          controller: TextEditingController(), labelText: 'كلمة المرور'));
      final f = tester.widget<TextField>(find.byType(TextField));
      expect(f.autocorrect, isFalse);
      expect(f.enableSuggestions, isFalse);
    });

    testWidgets('يحترم الزخرفة الممرَّرة ويحقن زرّ العين فيها', (tester) async {
      // شاشة الدخول تمرّر زخرفةً خاصّة — ولو استبدلناها لفقدت هويّتها البصرية.
      await pump(tester, PasswordField(
        controller: TextEditingController(),
        decoration: const InputDecoration(
            hintText: 'اكتب كلمتك', prefixIcon: Icon(Icons.lock_outline)),
      ));
      expect(find.text('اكتب كلمتك'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(find.byTooltip('إظهار كلمة المرور'), findsOneWidget);
    });
  });

  // ══════════════════ الشريط العلوي ══════════════════

  group('🧭 الشريط العلوي', () {
    late BuildContext? tapped;
    Future<void> pumpTopbar(
      WidgetTester tester, {
      Uint8List? photo,
      double width = 1400,
    }) async {
      tapped = null;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sessionProvider.overrideWith(() => _FixedSession(_session())),
          myPhotoProvider.overrideWith((ref) async => photo),
        ],
        child: MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SizedBox(
                width: width,
                child: Topbar(
                  title: 'الرئيسية',
                  subtitle: 'وصف',
                  onMenuTap: () {},
                  onProfileTap: (ctx) => tapped = ctx,
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('🗑️ لا حقل بحثٍ في الشريط العلوي', (tester) async {
      await pumpTopbar(tester);
      // كان حقلاً يُكتب فيه ولا يبحث — حذفُه هو الإصلاح (بلاغ المالك).
      expect(find.text('ابحث في الكتب، الأرشيف...'), findsNothing);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('🖼️ يعرض صورة المستخدم حين توجد', (tester) async {
      // بكسلٌ واحد صالح — يكفي لإثبات أن المسار يصل ويُرسم.
      final png = Uint8List.fromList([
        0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A,0x00,0x00,0x00,0x0D,0x49,0x48,0x44,0x52,
        0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x01,0x08,0x06,0x00,0x00,0x00,0x1F,0x15,0xC4,
        0x89,0x00,0x00,0x00,0x0D,0x49,0x44,0x41,0x54,0x78,0x9C,0x63,0xF8,0xCF,0xC0,0x00,
        0x00,0x03,0x01,0x01,0x00,0x18,0xDD,0x8D,0xB0,0x00,0x00,0x00,0x00,0x49,0x45,0x4E,
        0x44,0xAE,0x42,0x60,0x82,
      ]);
      await pumpTopbar(tester, photo: png);
      // 🔴 حرفُ الاسم يختفي حين تحضر الصورة — وإلا ظهرا معاً.
      expect(find.text('س'), findsNothing);
    });

    testWidgets('🔤 ويعود للحرف الأول لمن لا صورةَ له', (tester) async {
      await pumpTopbar(tester, photo: null);
      expect(find.text('س'), findsOneWidget);
    });

    testWidgets('🔴 والضغط يُمرّر **سياق الزرّ** — وعليه تُرسى القائمة',
        (tester) async {
      // بلاغ المالك: القائمة كانت تُفتح في الجهة المعاكسة لأن موضعها أرقامٌ ثابتة.
      // الحارس هنا يثبت أن السياق الواصل **هو سياق الزرّ فعلاً** لا سياق الشاشة:
      // مستطيلُه يطابق مستطيل بطاقة المستخدم.
      await pumpTopbar(tester);
      expect(tapped, isNull, reason: 'نُودي قبل الضغط');

      await tester.tap(find.text('سنان أياد'));
      await tester.pump();

      final ctx = tapped;
      expect(ctx, isNotNull, reason: 'لم يصل سياقٌ أصلاً');

      final box = ctx!.findRenderObject() as RenderBox?;
      expect(box, isNotNull, reason: 'السياق بلا كائن رسم — لا يصلح مرسًى');
      final rect = box!.localToGlobal(Offset.zero) & box.size;
      expect(rect.width > 0 && rect.height > 0, isTrue);
      // وفي واجهةٍ من اليمين لليسار تقع بطاقة المستخدم في **النصف الأيسر** من الشريط.
      expect(rect.center.dx < 1400 / 2, isTrue,
          reason: 'المرسى ليس عند بطاقة المستخدم: $rect');
    });
  });
}

SessionState _session() => SessionState(
      loaded: true,
      activeCompanyId: 1,
      auth: AuthResult(
        accessToken: 't',
        accessExpires: DateTime.now().add(const Duration(hours: 1)),
        refreshToken: 'r',
        userId: 7,
        fullName: 'سنان أياد',
        username: 'sinan',
        role: 'Employee',
        companyIds: const [1],
        mustChangePassword: false,
        companies: [CompanyAccess(companyId: 1, modules: const [])],
      ),
    );

class _FixedSession extends SessionNotifier {
  _FixedSession(this._state);
  final SessionState _state;
  @override
  SessionState build() => _state;
}
