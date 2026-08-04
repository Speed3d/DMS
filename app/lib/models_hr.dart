// نماذج وحدة الموظفين والرواتب (ADR-023 + ADR-024).
// يُعاد تصديرها من `models.dart` فيصل إليها كل من يستورده كالمعتاد.

/// أسماء الأشهر بالعربية — مرآةٌ لـ`PayrollCalculator.ArabicMonth` في الباك-إند.
const List<String> kArabicMonths = [
  'كانون الثاني', 'شباط', 'آذار', 'نيسان', 'أيار', 'حزيران',
  'تموز', 'آب', 'أيلول', 'تشرين الأول', 'تشرين الثاني', 'كانون الأول',
];

String arabicMonth(int month) =>
    month >= 1 && month <= 12 ? kArabicMonths[month - 1] : '$month';

/// صفّ في قائمة موظفي الشركة (يجمع الشخص وشروط عمله فيها).
class EmployeeListItem {
  final int employeeId;
  final int employeeCompanyId;
  final String fullName;
  final String? fullNameEn;
  final String? nationalId;
  final String? phone;
  final bool hasPhoto;
  final String position;
  final DateTime hireDate;
  final DateTime? terminationDate;
  final String salaryCurrency;
  final double baseSalary;
  final int displayOrder;
  final bool isActive;

  EmployeeListItem({
    required this.employeeId, required this.employeeCompanyId, required this.fullName,
    this.fullNameEn, this.nationalId, this.phone, required this.hasPhoto,
    required this.position, required this.hireDate, this.terminationDate,
    required this.salaryCurrency, required this.baseSalary,
    required this.displayOrder, required this.isActive,
  });

  /// منتهي الخدمة — يُميَّز بصرياً ولا يُدرَج في كشوف الشهور الجديدة.
  bool get isTerminated => terminationDate != null;

  factory EmployeeListItem.fromJson(Map<String, dynamic> j) => EmployeeListItem(
        employeeId: j['employeeId'],
        employeeCompanyId: j['employeeCompanyId'],
        fullName: j['fullName'] ?? '',
        fullNameEn: j['fullNameEn'],
        nationalId: j['nationalId'],
        phone: j['phone'],
        hasPhoto: j['hasPhoto'] ?? false,
        position: j['position'] ?? '',
        hireDate: DateTime.tryParse(j['hireDate'] ?? '') ?? DateTime.now(),
        terminationDate: DateTime.tryParse(j['terminationDate'] ?? ''),
        salaryCurrency: j['salaryCurrency'] ?? 'IQD',
        baseSalary: (j['baseSalary'] as num?)?.toDouble() ?? 0,
        displayOrder: j['displayOrder'] ?? 0,
        isActive: j['isActive'] ?? true,
      );
}

/// شروط عمل الموظف في شركة واحدة.
class EmploymentModel {
  final int employeeCompanyId;
  final int companyId;
  final String position;
  final String? positionEn;
  final DateTime hireDate;
  final DateTime? terminationDate;
  final String? terminationReason;
  final String? terminationNotes;
  final String salaryCurrency;
  final double baseSalary;
  final int displayOrder;
  final bool isActive;

  EmploymentModel({
    required this.employeeCompanyId, required this.companyId, required this.position,
    this.positionEn, required this.hireDate, this.terminationDate,
    this.terminationReason, this.terminationNotes,
    required this.salaryCurrency, required this.baseSalary,
    required this.displayOrder, required this.isActive,
  });

  factory EmploymentModel.fromJson(Map<String, dynamic> j) => EmploymentModel(
        employeeCompanyId: j['employeeCompanyId'],
        companyId: j['companyId'],
        position: j['position'] ?? '',
        positionEn: j['positionEn'],
        hireDate: DateTime.tryParse(j['hireDate'] ?? '') ?? DateTime.now(),
        terminationDate: DateTime.tryParse(j['terminationDate'] ?? ''),
        terminationReason: j['terminationReason'],
        terminationNotes: j['terminationNotes'],
        salaryCurrency: j['salaryCurrency'] ?? 'IQD',
        baseSalary: (j['baseSalary'] as num?)?.toDouble() ?? 0,
        displayOrder: j['displayOrder'] ?? 0,
        isActive: j['isActive'] ?? true,
      );
}

/// ملفّ الموظف الكامل.
///
/// ⚠️ `companies` تحمل **إسنادات الشركة الفعّالة وحدها** — الفلتر العام في الباك-إند يحجب
/// إسناداته في شركة أخرى، فلا يُكشف راتبه هناك.
class EmployeeDetail {
  final int employeeId;
  final String fullName;
  final String? fullNameEn;
  final String? nationalId;
  final String? phone;
  final String? address;
  final String? notes;
  final String receiptLanguage;
  final bool hasPhoto;
  final List<EmploymentModel> companies;

  EmployeeDetail({
    required this.employeeId, required this.fullName, this.fullNameEn,
    this.nationalId, this.phone, this.address, this.notes,
    required this.receiptLanguage, required this.hasPhoto, required this.companies,
  });

  EmploymentModel? get employment => companies.isNotEmpty ? companies.first : null;

  factory EmployeeDetail.fromJson(Map<String, dynamic> j) => EmployeeDetail(
        employeeId: j['employeeId'],
        fullName: j['fullName'] ?? '',
        fullNameEn: j['fullNameEn'],
        nationalId: j['nationalId'],
        phone: j['phone'],
        address: j['address'],
        notes: j['notes'],
        receiptLanguage: j['receiptLanguage'] ?? 'Arabic',
        hasPhoto: j['hasPhoto'] ?? false,
        companies: (j['companies'] as List? ?? [])
            .map((e) => EmploymentModel.fromJson(e)).toList(),
      );
}

class SalaryHistoryItem {
  final int year;
  final int month;
  final String monthName;
  final double netSalary;
  final String currency;
  final double netSalaryIqd;
  final String periodStatus;
  final String paymentStatus;

  SalaryHistoryItem({
    required this.year, required this.month, required this.monthName,
    required this.netSalary, required this.currency, required this.netSalaryIqd,
    required this.periodStatus, required this.paymentStatus,
  });

  factory SalaryHistoryItem.fromJson(Map<String, dynamic> j) => SalaryHistoryItem(
        year: j['year'], month: j['month'], monthName: j['monthName'] ?? '',
        netSalary: (j['netSalary'] as num?)?.toDouble() ?? 0,
        currency: j['currency'] ?? 'IQD',
        netSalaryIqd: (j['netSalaryIqd'] as num?)?.toDouble() ?? 0,
        periodStatus: j['periodStatus'] ?? 'Draft',
        paymentStatus: j['paymentStatus'] ?? 'Unpaid',
      );
}

/// نتيجة البحث برقم الهوية — **الاسم فقط**، لا راتب ولا اسم شركة أخرى.
class ExistingEmployeeHint {
  final int employeeId;
  final String fullName;
  final bool alreadyInThisCompany;
  ExistingEmployeeHint(this.employeeId, this.fullName, this.alreadyInThisCompany);
  factory ExistingEmployeeHint.fromJson(Map<String, dynamic> j) => ExistingEmployeeHint(
      j['employeeId'], j['fullName'] ?? '', j['alreadyInThisCompany'] ?? false);
}

class PayrollYear {
  final int year;
  final int monthsCreated;
  final int monthsPaid;
  final double totalIqd;
  PayrollYear(this.year, this.monthsCreated, this.monthsPaid, this.totalIqd);
  factory PayrollYear.fromJson(Map<String, dynamic> j) => PayrollYear(
      j['year'], j['monthsCreated'] ?? 0, j['monthsPaid'] ?? 0,
      (j['totalIqd'] as num?)?.toDouble() ?? 0);
}

class PayrollMonth {
  final int year;
  final int month;
  final String monthName;
  final bool exists;
  final String? status;
  final int employeeCount;
  final double totalIqd;

  PayrollMonth({
    required this.year, required this.month, required this.monthName,
    required this.exists, this.status, required this.employeeCount, required this.totalIqd,
  });

  bool get isPaid => status == 'Paid';

  factory PayrollMonth.fromJson(Map<String, dynamic> j) => PayrollMonth(
        year: j['year'], month: j['month'], monthName: j['monthName'] ?? '',
        exists: j['exists'] ?? false, status: j['status'],
        employeeCount: j['employeeCount'] ?? 0,
        totalIqd: (j['totalIqd'] as num?)?.toDouble() ?? 0,
      );
}

/// سطر راتب موظف في كشف شهر.
///
/// ⚠️ `netSalary` و`netSalaryIqd` **يحسبهما الخادم** — الواجهة تعرضهما ولا ترسلهما.
class PayrollEntryModel {
  final int entryId;
  final int employeeCompanyId;
  final int employeeId;
  final int displayOrder;
  final String name;
  final String position;
  final String currency;
  final double baseSalary;
  final int eligibleDays;
  final int absenceDays;
  final double? bonusAmount;
  final double? deductionAmount;
  final double absenceDeduction;
  final bool absenceDeductionIsManual;
  final double netSalary;
  final double netSalaryIqd;
  final String paymentStatus;
  final int? paidByCompanyId;
  final String? paidByCompanyName;
  final bool isNewHire;
  final bool isTerminated;
  final String? notes;

  PayrollEntryModel({
    required this.entryId, required this.employeeCompanyId, required this.employeeId,
    required this.displayOrder, required this.name, required this.position,
    required this.currency, required this.baseSalary, required this.eligibleDays,
    required this.absenceDays, this.bonusAmount, this.deductionAmount,
    required this.absenceDeduction, required this.absenceDeductionIsManual,
    required this.netSalary, required this.netSalaryIqd,
    required this.paymentStatus, this.paidByCompanyId, this.paidByCompanyName,
    required this.isNewHire, required this.isTerminated, this.notes,
  });

  bool get isUsd => currency == 'USD';
  bool get paidElsewhere => paymentStatus == 'PaidByOtherCompany';
  bool get paidHere => paymentStatus == 'PaidByThisCompany';

  factory PayrollEntryModel.fromJson(Map<String, dynamic> j) => PayrollEntryModel(
        entryId: j['entryId'],
        employeeCompanyId: j['employeeCompanyId'],
        employeeId: j['employeeId'] ?? 0,
        displayOrder: j['displayOrder'] ?? 0,
        name: j['name'] ?? '',
        position: j['position'] ?? '',
        currency: j['currency'] ?? 'IQD',
        baseSalary: (j['baseSalary'] as num?)?.toDouble() ?? 0,
        eligibleDays: j['eligibleDays'] ?? 0,
        absenceDays: j['absenceDays'] ?? 0,
        bonusAmount: (j['bonusAmount'] as num?)?.toDouble(),
        deductionAmount: (j['deductionAmount'] as num?)?.toDouble(),
        absenceDeduction: (j['absenceDeduction'] as num?)?.toDouble() ?? 0,
        absenceDeductionIsManual: j['absenceDeductionIsManual'] ?? false,
        netSalary: (j['netSalary'] as num?)?.toDouble() ?? 0,
        netSalaryIqd: (j['netSalaryIqd'] as num?)?.toDouble() ?? 0,
        paymentStatus: j['paymentStatus'] ?? 'Unpaid',
        paidByCompanyId: j['paidByCompanyId'],
        paidByCompanyName: j['paidByCompanyName'],
        isNewHire: j['isNewHire'] ?? false,
        isTerminated: j['isTerminated'] ?? false,
        notes: j['notes'],
      );
}

/// كشف شهر كامل.
///
/// ⚠️ `rowVersion` يُعاد كما هو مع كل كتابة — بدونه يمحو مستخدمٌ عملَ آخر صامتاً.
class PayrollPeriodModel {
  final int periodId;
  final int year;
  final int month;
  final String monthName;
  final String status;
  final double? exchangeRate;
  final String workingDaysMode;
  final int workingDays;
  final DateTime? paidAt;
  final int? outgoingBookId;
  final String? manualBookNumber;
  final String? notes;
  final List<int> rowVersion;
  final double totalIqd;
  final List<PayrollEntryModel> entries;

  PayrollPeriodModel({
    required this.periodId, required this.year, required this.month,
    required this.monthName, required this.status, this.exchangeRate,
    required this.workingDaysMode, required this.workingDays, this.paidAt,
    this.outgoingBookId, this.manualBookNumber, this.notes,
    required this.rowVersion, required this.totalIqd, required this.entries,
  });

  bool get isPaid => status == 'Paid';
  bool get isCalendarMode => workingDaysMode == 'Calendar';

  /// فيه رواتب بالدولار بلا سعر صرف ⇒ **التسديد مرفوض** والمعادل بالدينار صفرٌ مؤقّت.
  bool get needsExchangeRate =>
      entries.any((e) => e.isUsd) && (exchangeRate == null || exchangeRate! <= 0);

  factory PayrollPeriodModel.fromJson(Map<String, dynamic> j) => PayrollPeriodModel(
        periodId: j['periodId'],
        year: j['year'], month: j['month'], monthName: j['monthName'] ?? '',
        status: j['status'] ?? 'Draft',
        exchangeRate: (j['exchangeRate'] as num?)?.toDouble(),
        workingDaysMode: j['workingDaysMode'] ?? 'Fixed',
        workingDays: j['workingDays'] ?? 30,
        paidAt: DateTime.tryParse(j['paidAt'] ?? ''),
        outgoingBookId: j['outgoingBookId'],
        manualBookNumber: j['manualBookNumber'],
        notes: j['notes'],
        rowVersion: j['rowVersion'] != null ? List<int>.from(j['rowVersion']) : const [],
        totalIqd: (j['totalIqd'] as num?)?.toDouble() ?? 0,
        entries: (j['entries'] as List? ?? [])
            .map((e) => PayrollEntryModel.fromJson(e)).toList(),
      );
}

/// تنبيه «مدفوع من شركة أخرى» (ADR-024) — قراءة خالصة، والتعليم بقرار المستخدم لا تلقائياً.
class ExternalPaymentHint {
  final int entryId;
  final String employeeName;
  final int paidByCompanyId;
  final String paidByCompanyName;
  ExternalPaymentHint(
      this.entryId, this.employeeName, this.paidByCompanyId, this.paidByCompanyName);
  factory ExternalPaymentHint.fromJson(Map<String, dynamic> j) => ExternalPaymentHint(
      j['entryId'], j['employeeName'] ?? '', j['paidByCompanyId'], j['paidByCompanyName'] ?? '');
}

class HrSettingsModel {
  final String defaultWorkingDaysMode;
  final int defaultWorkingDays;
  HrSettingsModel(this.defaultWorkingDaysMode, this.defaultWorkingDays);
  factory HrSettingsModel.fromJson(Map<String, dynamic> j) =>
      HrSettingsModel(j['defaultWorkingDaysMode'] ?? 'Fixed', j['defaultWorkingDays'] ?? 30);
}

class HrSummary {
  final int activeEmployees;
  final double thisMonthTotalIqd;
  final double thisYearTotalIqd;
  final int unpaidMonths;
  HrSummary(this.activeEmployees, this.thisMonthTotalIqd, this.thisYearTotalIqd, this.unpaidMonths);
  factory HrSummary.fromJson(Map<String, dynamic> j) => HrSummary(
      j['activeEmployees'] ?? 0,
      (j['thisMonthTotalIqd'] as num?)?.toDouble() ?? 0,
      (j['thisYearTotalIqd'] as num?)?.toDouble() ?? 0,
      j['unpaidMonths'] ?? 0);
}
