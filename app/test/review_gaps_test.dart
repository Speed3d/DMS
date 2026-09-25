import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dms_app/models.dart';
import 'package:dms_app/screens/login_screen.dart';
import 'package:dms_app/widgets/hidden_replies_note.dart';

import 'support/quiet_status.dart';

/// حرّاس فجوات المراجعة وزرّ «نسيت كلمة المرور» (ADR-053).
void main() {
  // ───────────────────────── G20: المحجوب بالعدد ─────────────────────────
  group('G20 — الردود المحجوبة تُعلَن بالعدد', () {
    test('النصّ يذكر العدد والنوع ولا شيء غيرهما', () {
      expect(hiddenRepliesText(1, outgoing: true), 'وكتابٌ صادر واحد مرتبطٌ خارج صلاحيتك.');
      expect(hiddenRepliesText(2, outgoing: false), 'وكتابان واردان مرتبطان خارج صلاحيتك.');
      expect(hiddenRepliesText(5, outgoing: true), 'و5 كتبٍ صادرة مرتبطة خارج صلاحيتك.');
    });

    testWidgets('لا سطرَ إن لم يُحجب شيء', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: HiddenRepliesNote(count: 0, outgoing: true))));
      expect(find.byIcon(Icons.lock_outline_rounded), findsNothing);
    });

    test('الواردُ المُجاب بردٍّ محجوب **مُجابٌ** — فلا تُطلب ملاحظة «تم الرد» كأنه بلا ردّ', () {
      // 🔴 كانت الشاشة تسأل `replies.isEmpty` — وردٌّ لا يراه الطالب ما زال ردّاً.
      final d = IncomingDetail.fromJson({
        'incomingId': 1, 'companyId': 1, 'entityId': 1, 'receivedDate': '2026-09-24',
        'createdAt': '2026-09-24T10:00:00Z', 'replies': [], 'hiddenRepliesCount': 1,
      });
      expect(d.replies, isEmpty);
      expect(d.hasReplies, isTrue);
    });

    test('العقد يقرأ الحقل في الجهتين — وغيابُه صفرٌ لا انهيار', () {
      final out = OutgoingDetail.fromJson({
        'outgoingId': 1, 'companyId': 1, 'entityId': 1, 'templateId': 1, 'date': '2026-09-24',
        'hiddenRepliesCount': 3,
      });
      expect(out.hiddenRepliesCount, 3);
      final old = OutgoingDetail.fromJson(
          {'outgoingId': 1, 'companyId': 1, 'entityId': 1, 'templateId': 1, 'date': '2026-09-24'});
      expect(old.hiddenRepliesCount, 0);
    });
  });

  // ───────────────────────── G23: البيان ─────────────────────────
  test('G23 — المحذوف ناعماً في كل نوعٍ يظهر في البيان', () {
    final p = CompanyDeletePreview.fromJson({
      'companyId': 9, 'name': 'س', 'deletedArchive': 2, 'deletedTasks': 3,
      'deletedCaseFiles': 4, 'deletedEmployees': 5, 'canDelete': true, 'blockReason': 'None',
    });
    final labels = {for (final r in p.rows) r.$1: r.$2};
    expect(labels['أرشيف محذوف'], 2);
    expect(labels['مهام محذوفة'], 3);
    expect(labels['معاملات محذوفة'], 4);
    expect(labels['إسنادات موظفين مفكوكة'], 5);
    // ⚠️ وكلُّها بعلامة «محذوف» (الأيقونة المختلفة في الحوار).
    expect(p.rows.where((r) => r.$3).length, 4);
  });

  // ───────────────────────── «نسيت كلمة المرور» ─────────────────────────
  testWidgets('«نسيت كلمة المرور» يفتح الشرح — لم يعُد زرّاً بلا وظيفة', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [quietSystemStatus],
      child: const MaterialApp(
        home: Directionality(textDirection: TextDirection.rtl, child: LoginScreen()),
      ),
    ));
    await tester.pump();

    await tester.tap(find.byKey(const Key('forgot-password')));
    await tester.pumpAndSettle();

    expect(find.textContaining('تواصل مع مدير النظام'), findsOneWidget);
    await tester.tap(find.text('حسناً'));
    await tester.pumpAndSettle();
    expect(find.textContaining('تواصل مع مدير النظام'), findsNothing);
  });

  testWidgets('سطر «تذكّرني / نسيت كلمة المرور» لا يفيض على هاتف', (tester) async {
    // ⚠️ كان يفيض 31 بكسلاً — كشفه الحارس أعلاه. وعرض الهاتف هو الأضيق.
    for (final width in [360.0, 390.0, 1400.0]) {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(ProviderScope(
        overrides: [quietSystemStatus],
        child: const MaterialApp(
          home: Directionality(textDirection: TextDirection.rtl, child: LoginScreen()),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'عرض $width');
      expect(find.byKey(const Key('forgot-password')), findsOneWidget);
    }
    tester.view.reset();
  });
}
