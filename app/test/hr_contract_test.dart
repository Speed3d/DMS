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
    for (final name in [
      'payroll_period', 'employees', 'employee_log',
      'pending_leaves', 'employee_attachments',
    ]) {
      final raw = File('test/fixtures/$name.json').readAsStringSync();
      expect(raw.contains('????'), isFalse, reason: 'العيّنة $name مشوّهة الترميز');
    }
  });
}
