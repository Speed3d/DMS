// حرّاس حذف الشركة الآمن (ADR-047).
//
// 🔴 **وُلدت كلُّها من حادثةٍ وقعت 2026-09-21**: حوارٌ أحمر عامّ بلا رقمٍ واحد، وزرُّ «نعم»
//    يجاور زرّاً آخر أحمر يصفّر القاعدة — فضُغط الخطأ مكان الصواب.
//
// ⚠️ **وهذه تُشغّل الحوار الحقيقيّ لا نسخةً منه** — ولهذا عُمِّم `DeleteCompanyDialog`:
//    حارسٌ يختبر نسخةً مكتوبةً بيده **يحرس النسخة لا المنتج** (درسُ `DevSigningKeysTests`).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dms_app/models.dart';
import 'package:dms_app/screens/company_edit_screen.dart';

CompanyDeletePreview _preview({
  String name = 'شركة التجربة',
  bool canDelete = true,
  String blockReason = 'None',
  String? blockMessage,
  int liveOutgoing = 0,
  int deletedOutgoing = 0,
  int archive = 0,
  int employees = 0,
}) =>
    CompanyDeletePreview(
      companyId: 7,
      name: name,
      prefix: 'TST',
      isActive: false,
      liveOutgoing: liveOutgoing,
      deletedOutgoing: deletedOutgoing,
      liveIncoming: 0,
      deletedIncoming: 0,
      archive: archive,
      employees: employees,
      tasks: 0,
      caseFiles: 0,
      users: 0,
      soleCompanyUsers: 0,
      departments: 0,
      entities: 0,
      templates: 0,
      willBeErased: liveOutgoing + deletedOutgoing + archive + employees,
      canDelete: canDelete,
      blockReason: blockReason,
      blockMessage: blockMessage,
    );

Future<String?> _open(WidgetTester tester, CompanyDeletePreview p) async {
  String? result;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (ctx) => ElevatedButton(
          onPressed: () async {
            result = await showDialog<String>(
              context: ctx,
              builder: (_) => DeleteCompanyDialog(preview: p),
            );
          },
          child: const Text('افتح'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('افتح'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  group('📋 البيان — «لا تحذف ما لا تراه»', () {
    testWidgets('🔴 يعرض الأرقام الحقيقية لا تحذيراً عامّاً', (tester) async {
      await _open(tester, _preview(liveOutgoing: 2, deletedOutgoing: 3, employees: 1));

      expect(find.text('ما سيُمحى نهائياً'), findsOneWidget);
      expect(find.text('صادر'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('صادر محذوف'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('موظفون مُسنَدون'), findsOneWidget);
    });

    testWidgets('⚠️ وما فيه صفرٌ لا يُذكر — فلا يغرق البيان في أسطرٍ فارغة', (tester) async {
      await _open(tester, _preview(liveOutgoing: 1));

      expect(find.text('صادر'), findsOneWidget);
      expect(find.text('أرشيف'), findsNothing);
      expect(find.text('مهام'), findsNothing);
      expect(find.text('معاملات'), findsNothing);
    });

    testWidgets('✅ وشركةٌ فارغة تُقال فارغةً صراحةً', (tester) async {
      await _open(tester, _preview());
      expect(find.text('لا سجلّات — الشركة فارغة.'), findsOneWidget);
    });

    testWidgets('🗄️ ويُعلَن أن نسخةً ستُؤخذ قبل الحذف', (tester) async {
      await _open(tester, _preview());
      expect(find.textContaining('نسخةٌ احتياطية كاملة قبل الحذف'), findsOneWidget);
    });
  });

  group('🔐 التأكيد بالكتابة — لا زرٌّ أحمر', () {
    testWidgets('🔴 الزرّ معطَّلٌ قبل كتابة الاسم', (tester) async {
      await _open(tester, _preview());

      final btn = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'احذف نهائياً'));
      expect(btn.onPressed, isNull);
    });

    testWidgets('🔴 ويبقى معطَّلاً باسمٍ قريبٍ لا مطابق', (tester) async {
      await _open(tester, _preview(name: 'شركة التجربة'));

      await tester.enterText(find.byType(TextField), 'شركة');
      await tester.pump();

      final btn = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'احذف نهائياً'));
      expect(btn.onPressed, isNull);
    });

    testWidgets('✅ ويُفعَّل عند المطابقة الحرفية', (tester) async {
      await _open(tester, _preview(name: 'شركة التجربة'));

      await tester.enterText(find.byType(TextField), 'شركة التجربة');
      await tester.pump();

      final btn = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'احذف نهائياً'));
      expect(btn.onPressed, isNotNull);
    });

    testWidgets('⚠️ ومسافةٌ لاصقة من اللصق لا تُفشل اسماً صحيحاً', (tester) async {
      // مستخدمٌ ينسخ الاسم المعروض قد يلتقط مسافةً — ورفضُه حينها يجعله يظنّ أنه أخطأ.
      await _open(tester, _preview(name: 'شركة التجربة'));

      await tester.enterText(find.byType(TextField), '  شركة التجربة  ');
      await tester.pump();

      final btn = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'احذف نهائياً'));
      expect(btn.onPressed, isNotNull);
    });
  });

  group('⛔ حين يمنع الخادم', () {
    testWidgets('🔴 تُعرض رسالةُ المنع ولا يُطلب تأكيد', (tester) async {
      await _open(tester, _preview(
        canDelete: false,
        blockReason: 'StillEnabled',
        blockMessage: 'عطّل «شركة التجربة» أولاً ثم احذفها.',
        liveOutgoing: 1,
      ));

      expect(find.textContaining('عطّل'), findsOneWidget);
      // 🔑 **لا حقلَ كتابةٍ أصلاً**: طلبُ التأكيد قبل الجواز يجعل المستخدم يكتب ثم يُرفض.
      expect(find.byType(TextField), findsNothing);

      final btn = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'احذف نهائياً'));
      expect(btn.onPressed, isNull);
    });

    testWidgets('⚠️ والبيان يظهر معها — فيعرف ما يمنعه', (tester) async {
      await _open(tester, _preview(
        canDelete: false, blockReason: 'HasLiveRecords',
        blockMessage: 'تحوي سجلّات', liveOutgoing: 4));

      expect(find.text('صادر'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
    });
  });

  group('📦 عقد `CompanyDeletePreview`', () {
    test('🔴 يُقرأ من الخادم — و`canDelete` الافتراضي **false** لا true', () {
      // 🔑 **فشلٌ مغلق**: ردٌّ ناقص يجب أن يمنع الحذف لا أن يسمح به.
      final p = CompanyDeletePreview.fromJson({'companyId': 3, 'name': 'س'});
      expect(p.canDelete, isFalse);
      expect(p.willBeErased, 0);
      expect(p.rows, isEmpty);
    });

    test('✅ ويُرتّب الأسطر بإسقاط الأصفار', () {
      final p = CompanyDeletePreview.fromJson({
        'companyId': 3, 'name': 'س', 'liveOutgoing': 2, 'archive': 0, 'tasks': 5,
      });
      expect(p.rows.map((r) => r.$1), ['صادر', 'مهام']);
      expect(p.rows.map((r) => r.$2), [2, 5]);
    });
  });
}
