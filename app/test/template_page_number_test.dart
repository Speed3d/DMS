import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dms_app/core/api_client.dart';
import 'package:dms_app/core/session.dart';
import 'package:dms_app/models.dart';
import 'package:dms_app/screens/template_edit_screen.dart';

/// موضع «صفحة X من Y» في القالب (بلاغ المالك 2026-10-05): يمين · وسط · يسار وإزاحةٌ بالمليمتر — تُرى على الورقة
/// المصغّرة وتُحفظ مع القالب.
void main() {
  late _Api api;

  Future<void> pump(WidgetTester tester, {TemplateModel? template}) async {
    tester.view.physicalSize = const Size(1600, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    api = _Api(template ?? _template());
    await tester.pumpWidget(ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(api)],
      child: const MaterialApp(
        locale: Locale('ar'),
        supportedLocales: [Locale('ar')],
        localizationsDelegates: [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: TemplateEditScreen(templateId: 5),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Rect preview(WidgetTester t) => t.getRect(find.byKey(const Key('pn-preview')));

  Finder segment(String label) => find.descendant(of: find.byKey(const Key('pn-align')), matching: find.text(label));

  testWidgets('قالبٌ قائم بلا إعداد ⟵ الوسط بلا إزاحة (السلوك السابق) · والمعاينة في منتصف الورقة', (tester) async {
    await pump(tester, template: _template(align: null));
    expect(tester.widget<SegmentedButton<String>>(find.byKey(const Key('pn-align'))).selected, {'center'});
    expect(find.text('إزاحة أفقية: بلا إزاحة'), findsOneWidget);
    final page = tester.getRect(find.ancestor(of: find.byKey(const Key('pn-preview')), matching: find.byType(Stack)).first);
    expect(preview(tester).center.dx, closeTo(page.center.dx, 1));
  });

  testWidgets('يمين ⟵ الرقم عند الهامش الأيمن · يسار ⟵ عند الأيسر · والإزاحة تحرّكه يميناً بالمليمتر', (tester) async {
    await pump(tester);
    final page = tester.getRect(find.ancestor(of: find.byKey(const Key('pn-preview')), matching: find.byType(Stack)).first);
    final pt = page.width / 595;

    await tester.tap(segment('يمين'));
    await tester.pump();
    expect(preview(tester).right, closeTo(page.right - 40 * pt, 1));

    await tester.tap(segment('يسار'));
    await tester.pump();
    final left = preview(tester).left;
    expect(left, closeTo(page.left + 40 * pt, 1));

    // سحب شريط الإزاحة يميناً ⟵ الرقم يتحرّك يميناً (الشريط من اليسار إلى اليمين كالصفحة)
    await tester.drag(find.byKey(const Key('pn-x')), const Offset(120, 0));
    await tester.pump();
    expect(preview(tester).left, greaterThan(left));
    expect(find.textContaining('مم يميناً'), findsOneWidget);
  });

  testWidgets('الحفظ يرسل الموضع والإزاحتين', (tester) async {
    await pump(tester, template: _template(align: 'left', x: 12, y: -4));
    expect(find.text('إزاحة أفقية: 12 مم يميناً'), findsOneWidget);
    expect(find.text('إزاحة عمودية: 4 مم للأسفل'), findsOneWidget);

    await tester.tap(segment('يمين'));
    await tester.pump();
    await tester.ensureVisible(find.text('حفظ'));
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    expect(api.saved?['pageNumberAlign'], 'right');
    expect(api.saved?['pageNumberOffsetX'], 12);
    expect(api.saved?['pageNumberOffsetY'], -4);
  });

  testWidgets('«إعادة إلى الوسط» تُرجع الموضع والإزاحتين', (tester) async {
    await pump(tester, template: _template(align: 'right', x: -30, y: 10));
    await tester.ensureVisible(find.byKey(const Key('pn-reset')));
    await tester.tap(find.byKey(const Key('pn-reset')));
    await tester.pump();
    expect(tester.widget<SegmentedButton<String>>(find.byKey(const Key('pn-align'))).selected, {'center'});
    expect(find.text('إزاحة أفقية: بلا إزاحة'), findsOneWidget);
    expect(find.text('إزاحة عمودية: بلا إزاحة'), findsOneWidget);
  });
}

TemplateModel _template({String? align = 'center', int x = 0, int y = 0}) => TemplateModel.fromJson({
      'templateId': 5,
      'companyId': 1,
      'name': 'القالب الرسمي',
      'watermarkOpacity': 8,
      'marginTop': 24,
      'marginRight': 40,
      'marginBottom': 24,
      'marginLeft': 40,
      'pageSize': 'A4',
      'fontFamily': 'Amiri',
      'isActive': true,
      if (align != null) 'pageNumberAlign': align,
      if (align != null) 'pageNumberOffsetX': x,
      if (align != null) 'pageNumberOffsetY': y,
    });

class _Api extends ApiClient {
  _Api(this.template) : super(baseUrl: 'http://test/api', token: () => 't', companyId: () => 1);
  final TemplateModel template;
  Map<String, dynamic>? saved;

  @override
  Future<TemplateModel> getTemplate(int id) async => template;

  @override
  Future<Uint8List?> getTemplateImage(int id, String kind) async => null;

  @override
  Future<TemplateModel> updateTemplate(int id, Map<String, dynamic> body) async {
    saved = body;
    return template;
  }
}
