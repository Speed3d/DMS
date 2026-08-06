import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:dms_app/models.dart';

/// **عقد وحدة الموظفين والرواتب** — كل نموذج Dart يُختبر على **استجابةٍ حقيقية مُلتقَطة من
/// الخادم** (`app/test/fixtures/*.json`)، لا على جسمٍ مصنوع يدوياً.
///
/// ⚠️ **سبب وجود هذا الملف كلّه:** انهارت شاشة كشف الرواتب عند المالك بـ
/// `type 'String' is not a subtype of type 'Iterable<dynamic>'` لأن `byte[]` في
/// ASP.NET Core يُسلسَل **نصّاً بـbase64** (`"AAAAAAAApBE="`) لا مصفوفةَ أرقام —
/// وكنتُ افترضت المصفوفة. **واختباري السابق مرّ** لأنني كتبتُ عيّنته بيدي من الافتراض
/// نفسه، فصادق ظنّي لا الخادم.
///
/// > **القاعدة:** العيّنة تأتي من الخادم أو لا تأتي. واختبارٌ يصنع مدخلاته من فهم كاتبه
/// > يختبر فهمه لا نظامه.
///
/// **لتحديث العيّنات** بعد تغيير أي عقد: شغّل الخادم والتقطها بـ
/// `Invoke-WebRequest ... -OutFile app/test/fixtures/<name>.json` (بـ`-OutFile` تحديداً،
/// فهو يكتب البايتات الخام بلا فكّ ترميز يشوّه العربية).
void main() {
  dynamic fixture(String name) =>
      jsonDecode(File('test/fixtures/$name.json').readAsStringSync());

  test('كشف شهر كامل — بما فيه rowVersion بـbase64', () {
    final p = PayrollPeriodModel.fromJson(fixture('payroll_period'));

    // ⚠️ **لا تُثبَّت السنة برقم**: أيُّ شهرٍ التُقطت منه العيّنة تفصيلٌ عارض لا عقد،
    //    وتثبيتُه يُفشل الاختبار عند أول إعادة التقاطٍ من شهرٍ آخر — فشلاً **بلا عيبٍ في
    //    المنتج** يُغري بتعطيل الاختبار بدل إصلاحه. (حدث فعلاً عند تحديث العيّنات في
    //    الدفعة ٢.) الشرط الحقيقي: سنةٌ معقولة.
    expect(p.year, greaterThan(2000));
    expect(p.monthName, isNotEmpty);
    expect(p.workingDays, greaterThan(0));
    expect(p.entries, isNotEmpty);

    // 🔴 الحقل الذي أسقط الشاشة.
    expect(p.rowVersion, isA<String>());
    expect(p.rowVersion, isNotEmpty);

    final e = p.entries.first;
    expect(e.name, isNotEmpty);
    expect(e.netSalary, greaterThan(0));
    expect(e.paymentStatus, isNotEmpty);
  });

  test('قائمة الموظفين', () {
    final list = (fixture('employees') as List)
        .map((e) => EmployeeListItem.fromJson(e))
        .toList();
    expect(list, isNotEmpty);
    expect(list.first.fullName, isNotEmpty);
    expect(list.first.position, isNotEmpty);
    expect(list.first.hireDate, isA<DateTime>());
  });

  test('ملفّ الموظف مع إسناداته', () {
    final e = EmployeeDetail.fromJson(fixture('employee_detail'));
    expect(e.fullName, isNotEmpty);
    expect(e.companies, isNotEmpty);
    expect(e.employment!.baseSalary, greaterThan(0));
  });

  // ─────────── «إجمالي السنة» = المُسدَّد وحده (بلاغ المالك 2026-08-06) ───────────
  //
  // 🔴 **الحالة التي بلّغ عنها المالك حرفياً:** كانون الثاني 9,750,000 وشباط 11,762,000
  //    مُسدَّدان ⇒ المجموع 21,512,000. وكان التذييل يضيف آذار 11,925,000 ونيسان وأيار
  //    (1,200,000 لكلٍّ) وهي **مسودّات لم تُصرف**، فيَعِد بمبلغٍ لم يقع.
  group('جمع الأشهر يفصل المُسدَّد عن المسودّة', () {
    PayrollMonth m(int month, String? status, double total) => PayrollMonth(
          year: 2026, month: month, monthName: '$month',
          exists: status != null, status: status, employeeCount: 3, totalIqd: total);

    final months = [
      m(1, 'Paid', 9750000),
      m(2, 'Paid', 11762000),
      m(3, 'Draft', 11925000),
      m(4, 'Draft', 1200000),
      m(5, 'Draft', 1200000),
      m(6, null, 0), // شهرٌ لم يُنشأ أصلاً
    ];

    test('المُسدَّد = 21,512,000 بالضبط — بلا المسودّات', () {
      expect(PayrollMonth.paidTotal(months), 21512000);
    });

    test('والمسودّات رقمٌ مستقلّ = 14,325,000', () {
      expect(PayrollMonth.draftTotal(months), 14325000);
    });

    test('🔴 والمجموع الخام ليس أيّاً منهما — وهو ما كان يُعرض', () {
      final raw = months.fold<double>(0, (s, x) => s + x.totalIqd);
      expect(raw, 35837000);
      expect(raw, isNot(PayrollMonth.paidTotal(months)));
    });

    test('شهرٌ لم يُنشأ لا يدخل في المسودّات', () {
      expect(PayrollMonth.draftTotal([m(6, null, 0)]), 0);
    });

    test('وسنةٌ بلا تسديد: المُسدَّد صفر والمسودّات كاملة', () {
      final allDraft = [m(1, 'Draft', 500000), m(2, 'Draft', 700000)];
      expect(PayrollMonth.paidTotal(allDraft), 0);
      expect(PayrollMonth.draftTotal(allDraft), 1200000);
    });
  });

  test('بطاقة السنة تحمل المُسدَّد والمسودّة منفصلَين', () {
    final y = PayrollYear.fromJson({
      'year': 2026, 'monthsCreated': 5, 'monthsPaid': 2,
      'totalIqd': 21512000, 'draftTotalIqd': 14325000,
    });
    expect(y.totalIqd, 21512000);
    expect(y.draftTotalIqd, 14325000);
    expect(y.hasDraft, isTrue);

    // وخادمٌ أقدم بلا الحقل: صفرٌ لا انهيار.
    final old = PayrollYear.fromJson(
        {'year': 2025, 'monthsCreated': 1, 'monthsPaid': 1, 'totalIqd': 100});
    expect(old.draftTotalIqd, 0);
    expect(old.hasDraft, isFalse);
  });

  // ─────────── استثناء المدفوع خارجياً وبوّابة الحسم (ADR-028) ───────────
  //
  // 🔴 **العيّنتان من خادمٍ حيّ لكشفٍ فيه موظفةٌ صرفت لها شركةٌ أخرى.** والعطل الذي تحرسانه
  //    كلّف قاعدة عمل المالك 3,680,000 د.ع محسوبةً ضمن المدفوع في شهرين مُسدَّدين.
  test('الكشف يفصل «المستحقّ» عن «المستثنى» — والمجموع ليس واحداً', () {
    final p = PayrollPeriodModel.fromJson(fixture('payroll_period_excluded'));

    expect(p.totalIqd, 600000);
    expect(p.excludedIqd, 750000);
    expect(p.hasExcluded, isTrue);

    // 🔴 **الفرق هو بيت القصيد**: لو ساوى الإجمالي مجموعَ السطور لعاد العيب.
    final rawSum = p.entries.fold<double>(0, (a, e) => a + e.netSalaryIqd);
    expect(rawSum, greaterThan(p.totalIqd));
    expect(rawSum - p.totalIqd, p.excludedIqd);

    // ⚠️ **وصافي السطر المستثنى باقٍ** — معلومةٌ لا تُمحى (قرار المالك 2026-08-06).
    final excluded = p.entries.firstWhere((e) => e.paidElsewhere);
    expect(excluded.netSalaryIqd, 750000);
  });

  test('وكشفٌ بلا استثناء: excludedIqd صفر لا مفقود', () {
    final p = PayrollPeriodModel.fromJson(fixture('payroll_period'));
    expect(p.excludedIqd, 0);
    expect(p.hasExcluded, isFalse);
  });

  test('صفّ «يعمل في أكثر من شركة» يحمل قراره وحال الشركة الأخرى', () {
    final rows = (fixture('dual_company') as List)
        .map((e) => DualCompanyRow.fromJson(e))
        .toList();

    expect(rows, hasLength(1));
    final r = rows.first;
    expect(r.employeeName, isNotEmpty);
    expect(r.otherCompanyName, isNotEmpty);
    expect(r.otherHasPaid, isTrue, reason: 'الشركة الأخرى صرفت فعلاً في هذه العيّنة');
    expect(r.decision, 'PaidByOtherCompany');
    expect(r.needsDecision, isFalse);
    expect(r.isStale, isFalse);
    expect(r.blocksPayment, isFalse);
  });

  test('🔐 وحالتا المنع محسوبتان لا مقروءتين من الخادم وحده', () {
    final base = (fixture('dual_company') as List).first as Map<String, dynamic>;

    final pending = DualCompanyRow.fromJson({...base, 'needsDecision': true});
    expect(pending.blocksPayment, isTrue, reason: 'لم يُحسم ⇒ يمنع');

    final stale = DualCompanyRow.fromJson({...base, 'isStale': true});
    expect(stale.blocksPayment, isTrue, reason: 'قرارٌ تقادم ⇒ يمنع');

    // والشركة الأخرى لم تصرف ⇒ «صُرف من الخارج» غير مسموح، فيُخفى زرّه.
    final notPaid = DualCompanyRow.fromJson({...base, 'otherPaidAt': null});
    expect(notPaid.otherHasPaid, isFalse);
  });

  // ─────────── «يعمل أيضاً في» (ADR-027) ───────────
  //
  // 🔴 **عيّنتان لا واحدة**: الأولى لموظفٍ في شركتين والثانية لمن في واحدة. عيّنةُ الحالة
  //    المملوءة وحدها كانت ستترك «القائمة الفارغة» بلا حارس — وهي الحال الغالبة، وأولُ ما
  //    ينكسر لو غاب الحقل عن العقد يوماً.
  test('ملفّ موظفٍ يعمل في شركتين: otherCompanies تحمل الاسم والمعرّف', () {
    final e = EmployeeDetail.fromJson(fixture('employee_detail'));
    expect(e.otherCompanies, hasLength(1));
    expect(e.otherCompanies.first.companyId, greaterThan(0));
    expect(e.otherCompanies.first.name, isNotEmpty);

    // 🔐 وشروطُ عمله المعروضة **شركةٌ واحدة**: الأخرى يحجبها الفلتر العام (ADR-017).
    //    لو صارت `companies` تحمل اثنتين يوماً فذلك تسرّبُ راتبٍ لا توسعةُ حقل.
    expect(e.companies, hasLength(1));
  });

  test('وملفّ موظفٍ في شركة واحدة: otherCompanies فارغة لا مفقودة', () {
    final e = EmployeeDetail.fromJson(fixture('employee_detail_single'));
    expect(e.otherCompanies, isEmpty);
    expect(e.companies, hasLength(1));
  });

  test('وغيابُ الحقل أصلاً لا يُسقط التحويل (توكنٌ/خادمٌ أقدم)', () {
    final raw = Map<String, dynamic>.from(fixture('employee_detail') as Map)
      ..remove('otherCompanies');
    expect(EmployeeDetail.fromJson(raw).otherCompanies, isEmpty);
  });

  test('سجلّ الرواتب', () {
    final list = (fixture('salary_history') as List)
        .map((e) => SalaryHistoryItem.fromJson(e))
        .toList();
    expect(list, isNotEmpty);
    expect(list.first.monthName, isNotEmpty);
  });

  test('الإجازات', () {
    final list =
        (fixture('leaves') as List).map((e) => LeaveModel.fromJson(e)).toList();
    expect(list, isNotEmpty);
    expect(list.first.durationDays, greaterThan(0));
    expect(list.first.leaveTypeLabel, isNotEmpty);
  });

  test('سجلّ التغييرات', () {
    final list = (fixture('employee_log') as List)
        .map((e) => EmployeeLogItem.fromJson(e))
        .toList();
    expect(list, isNotEmpty);
    // الوصف نصٌّ عربي جاهز من الخادم — لا يُركَّب في العميل.
    expect(list.first.description, isNotEmpty);
    expect(list.first.changedAt, isA<DateTime>());
  });

  test('البحث بالهوية', () {
    final h = ExistingEmployeeHint.fromJson(fixture('lookup'));
    expect(h.fullName, isNotEmpty);
    expect(h.alreadyInThisCompany, isA<bool>());
  });

  test('سنوات الرواتب', () {
    final list = (fixture('payroll_years') as List)
        .map((e) => PayrollYear.fromJson(e))
        .toList();
    expect(list, isNotEmpty);
    expect(list.first.monthsCreated, greaterThan(0));
  });

  test('أشهر السنة — اثنا عشر دائماً', () {
    final list = (fixture('payroll_months') as List)
        .map((e) => PayrollMonth.fromJson(e))
        .toList();
    expect(list.length, 12);
    expect(list.first.monthName, isNotEmpty);
  });

  test('ملخّص الوحدة', () {
    final s = HrSummary.fromJson(fixture('hr_summary'));
    expect(s.activeEmployees, greaterThanOrEqualTo(0));
    expect(s.pendingLeaves, greaterThanOrEqualTo(0));
  });

  test('إعدادات الوحدة', () {
    final s = HrSettingsModel.fromJson(fixture('hr_settings'));
    expect(s.defaultWorkingDays, greaterThan(0));
    expect(s.endOfServiceRatio, isNotEmpty);
  });

  // ─────────────────── الدفعة ٢ من بلاغات fix03.md (2026-08-05) ───────────────────

  test('علَم «الأيام يدوية» جزءٌ من عقد السطر', () {
    // 🔴 وُلد من عيبٍ ماليّ: كانت الخدمة تستنتج «يدويّ» من `EligibleDays > 0` فتتجمّد
    //    الأيام بعد أول حساب. العلَم صريحٌ الآن، والعميل يقرؤه ليعرف أيَّ سطرٍ مثبَّت.
    final p = PayrollPeriodModel.fromJson(fixture('payroll_period'));
    final e = p.entries.first;
    expect(e.eligibleDaysIsManual, isA<bool>());
    expect(e.eligibleDaysIsManual, isFalse,
        reason: 'سطرٌ لم يثبّته أحد يجب أن يبقى محسوباً');
    expect(e.eligibleDays, greaterThan(0));
  });

  test('الإجازات المعلّقة تصل بأصحابها', () {
    // بلاغ المالك ٨: البطاقة كانت تعرض العدد وتنقل بلا دلالةٍ على **مَن** طلب.
    final list = (fixture('pending_leaves') as List)
        .map((e) => PendingLeave.fromJson(e))
        .toList();
    expect(list, isNotEmpty);

    final l = list.first;
    expect(l.employeeId, greaterThan(0), reason: 'بلا معرّف لا يمكن فتح ملفّ صاحبها');
    expect(l.employeeName, isNotEmpty);
    expect(l.leaveTypeLabel, isNotEmpty, reason: 'التسمية عربيةٌ جاهزة من الخادم');
    expect(l.durationDays, greaterThan(0));
    expect(l.toDate.isBefore(l.fromDate), isFalse);
  });

  test('مستمسكات الموظف — بأسماء ملفّات عربية', () {
    // بلاغ المالك ٧: النقطة كانت غائبة أصلاً رغم جهوز `OwnerType.Employee`.
    final list = (fixture('employee_attachments') as List)
        .map((e) => AttachmentModel.fromJson(e))
        .toList();
    expect(list, isNotEmpty);
    expect(list.any((a) => RegExp(r'[؀-ۿ]').hasMatch(a.fileName)), isTrue,
        reason: 'الاسم العربي هو الحالة الفعلية عند المالك، فيجب أن تُثبته العيّنة');
    expect(list.first.fileSize, greaterThan(0));
  });

  test('العربية في العيّنات سليمة — لا «????»', () {
    // حارسٌ على العيّنات نفسها: التقاطُها بطريقة تفكّ الترميز يشوّه العربية،
    // فتصير العيّنة توثيقاً كاذباً للعقد.
    //
    // 🔴 **يمسح المجلد كلَّه ولا يعدّ أسماءً (2026-08-06).** كانت قائمةً بخمسة أسماء، فكلُّ
    //    عيّنةٍ جديدة تُلتقَط تدخل **بلا حارس** ما لم يتذكّر كاتبُها إضافتها — وهو تذكُّرٌ
    //    لا يصحّ الاتّكال عليه. المجلد نفسه هو القائمة.
    final files = Directory('test/fixtures')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList();
    expect(files, isNotEmpty, reason: 'لم يُعثر على عيّنات — تحقّق من مسار التشغيل');

    for (final f in files) {
      final raw = f.readAsStringSync();
      expect(raw.contains('????'), isFalse,
          reason: 'العيّنة ${f.uri.pathSegments.last} مشوّهة الترميز');
    }
  });
}
