import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dms_app/core/case_file_providers.dart';
import 'package:dms_app/core/session.dart';
import 'package:dms_app/models.dart';
import 'package:dms_app/screens/case_files_screen.dart';
import 'package:dms_app/widgets/custom_card.dart';
import 'package:dms_app/widgets/related_books_card.dart';
import 'package:dms_app/widgets/search_field.dart';
import 'package:dms_app/widgets/status_pill.dart';
import 'package:dms_app/widgets/task_badges.dart';

/// حرّاس وحدة **المعاملات** (ADR-045) — العقد والصلاحية والشارة والرسم.
void main() {
  // ─────────────────────── العقد ───────────────────────

  group('🔗 عقد المعاملة', () {
    test('يقرأ الأعضاء بنوعيهم', () {
      final d = CaseFileDetail.fromJson({
        'caseFileId': 3,
        'title': 'مناقصة المجاري',
        'createdAt': '2026-09-01T08:00:00',
        'hiddenCount': 2,
        'members': [
          {
            'kind': 'Incoming',
            'bookId': 1,
            'number': 'DEN-IN-2026-00001',
            'date': '2026-09-01T00:00:00',
            'subject': 'طلب',
            'status': 'InReview',
          },
          {
            'kind': 'Outgoing',
            'bookId': 9,
            'number': 'DEN-2026-00009',
            'date': '2026-09-10T00:00:00',
            'subject': 'ردّ',
            'status': 'Final',
          },
        ],
      });

      expect(d.members.length, 2);
      expect(d.members.first.kind, CaseMemberKind.incoming);
      expect(d.members.last.kind, CaseMemberKind.outgoing);
      expect(d.hiddenCount, 2);
    });

    test('⚠️ ومعاملةٌ فارغة لا تُسقط الشاشة', () {
      // 🔴 حالةٌ حقيقية: `POST /case-files` يُنهي بـ`Get`، والمعاملة لتوّها بلا أعضاء.
      final d = CaseFileDetail.fromJson({
        'caseFileId': 1,
        'title': 'جديدة',
        'createdAt': '2026-09-01T08:00:00',
      });
      expect(d.members, isEmpty);
      expect(d.hiddenCount, 0);
    });

    test('🔴 و`kind` يعبر بالصيغة التي يقبلها الخادم — لا بحروفٍ صغيرة', () {
      // العقد في الخادم `JsonStringEnumConverter` ⇒ `"Incoming"` لا `"incoming"`.
      // وإرسالُ الصيغة الخاطئة يردّ 400 **على طلبٍ يبدو سليماً**.
      expect(CaseMemberKind.incoming.wire, 'Incoming');
      expect(CaseMemberKind.outgoing.wire, 'Outgoing');
    });

    test('وقراءتُه متسامحة مع حالة الأحرف', () {
      expect(CaseMemberKindX.parse('Outgoing'), CaseMemberKind.outgoing);
      expect(CaseMemberKindX.parse('outgoing'), CaseMemberKind.outgoing);
      expect(CaseMemberKindX.parse(null), CaseMemberKind.incoming);
    });

    test('📅 تاريخُ الكتاب يومٌ تقويميّ لا لحظة', () {
      final m = CaseMember.fromJson({
        'kind': 'Incoming',
        'bookId': 1,
        'number': 'X',
        'date': '2026-09-01T00:00:00',
        'subject': 's',
        'status': 'New',
      });
      // تحويلُ يومٍ بالمنطقة الزمنية يُنقصه يوماً (ADR-032).
      expect(m.date.day, 1);
      expect(m.date.month, 9);
    });

    test('وشارةُ القائمة تعبر العقد — وغيابُها `null` لا صفر', () {
      // 🔴 **الحلقة التي تُنسى**: حقلٌ يُحفظ في القاعدة ولا يمرّ من النموذج يصل فارغاً دائماً.
      final withCase = IncomingListItem.fromJson({
        'incomingId': 1,
        'receivedDate': '2026-09-01T00:00:00',
        'subject': 's',
        'entityName': 'e',
        'status': 'New',
        'caseFileId': 7,
      });
      expect(withCase.caseFileId, 7);

      final without = IncomingListItem.fromJson({
        'incomingId': 2,
        'receivedDate': '2026-09-01T00:00:00',
        'subject': 's',
        'entityName': 'e',
        'status': 'New',
      });
      expect(without.caseFileId, isNull);

      final out = OutgoingListItem.fromJson({
        'outgoingId': 5,
        'date': '2026-09-01T00:00:00',
        'subject': 's',
        'entityName': 'e',
        'status': 'Final',
        'caseFileId': 7,
      });
      expect(out.caseFileId, 7);
    });
  });

  // ─────────────────────── الصلاحية ───────────────────────

  group('🔐 رؤية قسم المعاملات — أحد القسمين يكفي', () {
    SessionState sessionWith({required List<String> modules, String role = 'Employee'}) =>
        SessionState(
          loaded: true,
          activeCompanyId: 1,
          auth: AuthResult(
            accessToken: 't',
            accessExpires: DateTime.now().add(const Duration(hours: 1)),
            refreshToken: 'r',
            userId: 1,
            fullName: 'م',
            username: 'u',
            role: role,
            companyIds: const [1],
            mustChangePassword: false,
            companies: [CompanyAccess(companyId: 1, modules: modules)],
          ),
        );

    bool canSee(SessionState s) => s.hasModule('Incoming') || s.hasModule('Outgoing');

    test('مَن يملك الوارد وحده يراها', () {
      expect(canSee(sessionWith(modules: ['Incoming'])), isTrue);
    });

    test('🔴 ومَن يملك الصادر وحده يراها أيضاً', () {
      // ⚠️ هذا بالضبط ما يمنعه `[RequireModule(Incoming|Outgoing)]`: `HasModule` يفحص
      //    **كلَّ البتّات** فتعني «الاثنين معاً». ولهذا الحارس في الخدمة لا في السمة.
      expect(canSee(sessionWith(modules: ['Outgoing'])), isTrue);
    });

    test('ومَن لا يملك أيّاً منهما لا يراها', () {
      expect(canSee(sessionWith(modules: ['Archive', 'Reports'])), isFalse);
    });
  });

  // ─────────────────────── الشارة ───────────────────────

  group('🏷️ شارة المعاملة', () {
    Widget wrap(Widget child, {double width = 120}) => MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: Center(child: SizedBox(width: width, child: child))),
          ),
        );

    testWidgets('تغيب تماماً لمن لا معاملة له — لا مساحةَ محجوزة', (tester) async {
      await tester.pumpWidget(wrap(const CaseFileBadge(caseFileId: null)));
      expect(find.byIcon(Icons.account_tree_rounded), findsNothing);
    });

    testWidgets('وتظهر لمن له معاملة', (tester) async {
      await tester.pumpWidget(wrap(const CaseFileBadge(caseFileId: 4)));
      expect(find.byIcon(Icons.account_tree_rounded), findsOneWidget);
    });

    testWidgets('🔐 ولا تعرض عنوان المعاملة — المحجوب بالعدد لا بالتفصيل', (tester) async {
      await tester.pumpWidget(wrap(const CaseFileBadge(caseFileId: 4)));
      // لا نصَّ إطلاقاً في الشارة: العنوان قد يحمل موضوع كتابٍ محجوب.
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('🔴 والصفّ لا يفيض بها عند خليةٍ ضيّقة', (tester) async {
      // ⚠️ **نافذة الاختبار 800×600 افتراضاً** و`SizedBox` أوسع يُقصّ، فتُضبط النافذة
      //    ليصحّ القياس (قاعدة `coding-standards.md`).
      tester.view.physicalSize = const Size(400, 300);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(wrap(
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: const [
            CaseFileBadge(caseFileId: 4),
            SizedBox(width: 6),
            Flexible(child: StatusPill(status: 'InReview')),
          ],
        ),
        width: 96,
      ));
      expect(tester.takeException(), isNull, reason: 'فيض تخطيط في خلية الحالة');
    });

    testWidgets('🔒 والحارس له أسنان: التركيب بلا `Flexible` يفيض فعلاً', (tester) async {
      // بلا هذه الحالة يمرّ الحارس أعلاه ولو أُزيل `Flexible` — فحارسٌ لا يُرى فاشلاً
      // على العيب لا يُوثَق (قاعدة مسجَّلة).
      tester.view.physicalSize = const Size(400, 300);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(wrap(
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: const [
            CaseFileBadge(caseFileId: 4),
            SizedBox(width: 6),
            SizedBox(width: 300, child: StatusPill(status: 'InReview')),
          ],
        ),
        width: 96,
      ));
      expect(tester.takeException(), isNotNull,
          reason: 'لو لم يَعُد يفيض فقد تغيّرت الأحجام ⇒ أعِد تقييم الحاجة إلى Flexible');
    });
  });

  // ─────────────────────── ADR-042 ───────────────────────

  group('🧩 العدّاد دالّةٌ نقيّة لا مزوّدٌ مشتقّ (ADR-042)', () {
    test('يحسب من الحالة الواصلة', () {
      final v = caseFileCountOf(AsyncValue.data([
        CaseFileListItem(
            caseFileId: 1, title: 'أ', visibleCount: 2, hiddenCount: 0,
            createdAt: DateTime.utc(2026)),
        CaseFileListItem(
            caseFileId: 2, title: 'ب', visibleCount: 1, hiddenCount: 3,
            createdAt: DateTime.utc(2026)),
      ]));
      expect(v.value, 2);
    });

    test('ويمرّر التحميل كما هو بلا أن يُفلَش', () {
      // `whenData` يمرّر التحميل كما هو ولا يُفلَش — وهذا جوهر «الدالّة النقيّة»:
      // لا تنتظر ولا تشتقّ مزوّداً، فلا سلسلةَ `watch` تُبطَل أثناء البناء (ADR-042).
      expect(caseFileCountOf(const AsyncValue<List<CaseFileListItem>>.loading()).value,
          isNull);
    });
  });

  // ─────────────────────── التخطيط ───────────────────────

  group('📏 شاشة المعاملات تُرسم في الشاشات الضيّقة', () {
    // ⚠️ **حارسُ رسمٍ لا حارسُ فيض** — والفرق مقصود: ظننتُ أن عرضاً ثابتاً 380 داخل حشوةٍ
    //    32 يفيض تحت 444 بكسل، **فأثبت الحارس السلبيّ العكس**: `SizedBox` يلتزم بقيود أبيه
    //    فيُقصَر ولا يفيض. فأُزيل «العلاج» وبقي الحارس **بوصفه الصحيح**.
    // 🔑 وهذا نفعُ الحارس السلبيّ: لا يمنع العيبَ فحسب، بل يمنع **إصلاحَ ما ليس معطوباً**.
    for (final w in <double>[320, 380, 443, 444, 1200]) {
      testWidgets('حقل البحث يُرسم بلا استثناء عند $w بكسل', (tester) async {
        // ⚠️ **نافذة الاختبار 800×600 افتراضاً** و`SizedBox` أوسع يُقصّ (قاعدة المشروع).
        tester.view.physicalSize = Size(w, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(32),
                child: SizedBox(
                  width: kCaseSearchWidth,
                  child: DebouncedSearchField(hintText: 'بحث', onChanged: (_) {}),
                ),
              ),
            ),
          ),
        ));
        expect(tester.takeException(), isNull, reason: 'استثناء رسمٍ عند العرض $w');
      });
    }
  });

  // ─────────────────────── البطاقة ───────────────────────

  group('🃏 بطاقة الكتب المرتبطة داخل CustomCard', () {
    testWidgets('`ListTile` داخل البطاقة بلا استثناء — الجذر يُتيح السطح', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 600,
                child: CustomCard(
                  child: ListTile(
                    selected: true,
                    selectedTileColor: const Color(0x22FFFFFF),
                    title: const Text('كتاب'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
    });
  });

  // ═══════════ فيضُ صفّ العضو — بلاغُ المالك 2026-09-21 ═══════════
  //
  // 🔴 **فاض 19 بكسلاً** داخل بطاقةٍ عرضُها المتاح 203.2: الرقم والنوع والتاريخ في
  //    `Row` واحد. والعلاج `Wrap` لا `Flexible` — **لأن القصّ كان يقصّ رقم الكتاب**
  //    وهو هويّته.

  group('📏 صفُّ العضو لا يفيض', () {
    CaseFileDetail detail(String number, String subject) => CaseFileDetail(
          caseFileId: 1,
          title: 'معاملة',
          notes: null,
          createdAt: DateTime(2026, 9, 1),
          hiddenCount: 0,
          members: [
            CaseMember(
              kind: CaseMemberKind.incoming,
              bookId: 11,
              number: number,
              date: DateTime(2026, 9, 21),
              subject: subject,
              status: 'New',
            ),
            CaseMember(
              kind: CaseMemberKind.outgoing,
              bookId: 12,
              number: number,
              date: DateTime(2026, 12, 31),
              subject: subject,
              status: 'Final',
            ),
          ],
        );

    Future<void> pumpAt(WidgetTester tester, double width, CaseFileDetail d) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(ProviderScope(
        overrides: [
          relatedCaseProvider.overrideWith((ref, key) async => d),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RelatedBooksCard(
                kind: CaseMemberKind.incoming,
                bookId: 11,
                canManage: true,
                onRelate: () {},
                onOpen: (_) {},
                onOpenCase: (_) {},
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    // 🔴 **مقيسٌ لا مُدَّعى**: بـ`Row` تفيض المقاسات الأربعة كلُّها؛ وبـ`Wrap` لا تفيض.
    for (final w in <double>[340, 380, 440, 560]) {
      testWidgets('بلا فيضٍ عند عرض ${w.toInt()} بكسل — برقمٍ طويل',
          (tester) async {
        await pumpAt(tester, w,
            detail('DEN-IN-2026-00124', 'كتابٌ بموضوعٍ طويلٍ يمتدّ على أكثر من سطر'));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('⚠️ ورقمُ الكتاب **يظهر كاملاً** لا مقصوصاً — فهو هويّته',
        (tester) async {
      await pumpAt(tester, 340, detail('DEN-IN-2026-00124', 'موضوع'));
      // النصّ نفسه موجودٌ في الشجرة (عضوان بالرقم نفسه).
      expect(find.text('DEN-IN-2026-00124'), findsNWidgets(2));
    });

    testWidgets('✅ والنوع والتاريخ يظهران معه', (tester) async {
      await pumpAt(tester, 340, detail('DEN-2026-00001', 'موضوع'));
      expect(find.text('2026/09/21'), findsOneWidget);
      expect(find.text('2026/12/31'), findsOneWidget);
    });
  });
}
