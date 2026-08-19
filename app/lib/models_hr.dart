// نماذج وحدة الموظفين والرواتب (ADR-023 + ADR-024).
// يُعاد تصديرها من `models.dart` فيصل إليها كل من يستورده كالمعتاد.

// 🔴 **استيرادٌ عكسيّ مقصود** (ADR-033): `models.dart` يُعيد تصدير هذا الملف، وهذا يستورد
//    منه `parseInstant` وحدها. ودورةُ المكتبات مشروعةٌ في Dart، والبديل — نسخُ الدالّة —
//    هو بالضبط ما جعل هذا الملف يفوت إصلاحَ ADR-032 كلَّه.
import 'models.dart' show parseInstant;

/// جسم استجابة ككائن، أو `null` إن كان **غائباً بأي صورة**.
///
/// ⚠️ **«لا شيء» يصل بصورتين لا صورة واحدة:** حين يردّ الخادم `Ok(null)` — كما في
/// «كشف هذا الشهر لم يُنشأ بعد» و«لا موظف بهذا الرقم» — يُنتج ASP.NET Core
/// **`204 No Content` بجسمٍ فارغ**، فيسلّم Dio **نصّاً فارغاً `''` لا `null`**.
/// وفحصُ `data == null` وحده كان يمرّ فوقه ثم ينهار التحويل بـ
/// `type 'String' is not a subtype of type 'Map<String, dynamic>'` — فتسقط شاشة
/// كشف الرواتب كلها **قبل أن يظهر زرّ «توليد كشف الشهر»** الذي يصحّح الحال.
/// (بلاغ المالك 2026-08-04 — أول شهر يُفتح في نظام بلا كشوف.)
Map<String, dynamic>? jsonObjectOrNull(dynamic data) =>
    data is Map<String, dynamic> ? data : null;

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

/// شركة أخرى يعمل فيها الموظف — **الاسم فقط** (ADR-027).
///
/// ⚠️ لا راتب ولا صفة: المكشوف **واقعةُ العمل** لا **شروطه**. ولو حملت هذه الفئة راتباً
/// يوماً فذلك خرقٌ لـADR-017 لا توسعةُ حقل.
class OtherCompanyRef {
  final int companyId;
  final String name;
  const OtherCompanyRef({required this.companyId, required this.name});

  factory OtherCompanyRef.fromJson(Map<String, dynamic> j) => OtherCompanyRef(
        companyId: j['companyId'] ?? 0,
        name: j['name'] ?? '',
      );
}

/// ملفّ الموظف الكامل.
///
/// ⚠️ `companies` تحمل **إسنادات الشركة الفعّالة وحدها** — الفلتر العام في الباك-إند يحجب
/// إسناداته في شركة أخرى، فلا يُكشف راتبه هناك. و`otherCompanies` **أسماؤها** لا شروطُها.
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

  /// الشركات الأخرى التي يعمل فيها — تُعرض في بطاقته ليُرى أثرُ الإسناد (ADR-027).
  final List<OtherCompanyRef> otherCompanies;

  /// حساب النظام المربوط بالبطاقة — `null` إن لم تُربط (ADR-033).
  final int? userId;

  /// اسمُ ذلك الحساب — يُعرض ليعرف من يفكّ الربط **عمَّن** يفكّه.
  final String? username;

  EmployeeDetail({
    required this.employeeId, required this.fullName, this.fullNameEn,
    this.nationalId, this.phone, this.address, this.notes,
    required this.receiptLanguage, required this.hasPhoto, required this.companies,
    this.otherCompanies = const [],
    this.userId, this.username,
  });

  /// هل تُفتح لصاحب البطاقة نافذةُ بروفايل؟ (ADR-033)
  bool get isLinkedToUser => userId != null;

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
        otherCompanies: (j['otherCompanies'] as List? ?? [])
            .map((e) => OtherCompanyRef.fromJson(e)).toList(),
        userId: j['userId'],
        username: j['username'],
      );
}

class SalaryHistoryItem {
  /// معرّف سطر الراتب — **لازمٌ لرفع إيصال الاستلام الموقَّع** وعرضه (بلاغ المالك ٦).
  final int entryId;

  final int year;
  final int month;
  final String monthName;
  final double netSalary;
  final String currency;
  final double netSalaryIqd;
  final String periodStatus;
  final String paymentStatus;

  /// عدد الإيصالات الموقَّعة المرفوعة لهذا الشهر.
  final int signedReceiptCount;

  SalaryHistoryItem({
    required this.entryId,
    required this.year, required this.month, required this.monthName,
    required this.netSalary, required this.currency, required this.netSalaryIqd,
    required this.periodStatus, required this.paymentStatus,
    this.signedReceiptCount = 0,
  });

  factory SalaryHistoryItem.fromJson(Map<String, dynamic> j) => SalaryHistoryItem(
        entryId: j['entryId'] ?? 0,
        signedReceiptCount: j['signedReceiptCount'] ?? 0,
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

  /// 🔴 **ما صُرف فعلاً** — أشهرٌ مُسدَّدة فقط (بلاغ المالك 2026-08-06).
  final double totalIqd;

  /// ما ينتظر التسديد في المسودّات — **رقمٌ منفصل لا مطروح ولا مجموع**.
  final double draftTotalIqd;

  PayrollYear(this.year, this.monthsCreated, this.monthsPaid, this.totalIqd,
      {this.draftTotalIqd = 0});

  bool get hasDraft => draftTotalIqd > 0;

  factory PayrollYear.fromJson(Map<String, dynamic> j) => PayrollYear(
      j['year'], j['monthsCreated'] ?? 0, j['monthsPaid'] ?? 0,
      (j['totalIqd'] as num?)?.toDouble() ?? 0,
      draftTotalIqd: (j['draftTotalIqd'] as num?)?.toDouble() ?? 0);
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

  /// 🔴 **قاعدةٌ واحدة لجمع الأشهر** (بلاغ المالك 2026-08-06).
  ///
  /// شاشة الأشهر كانت تجمع الاثني عشر شهراً بلا تمييز، فيقول تذييلُها «إجمالي السنة»
  /// عن مبلغٍ نصفُه مسودّاتٌ لم تُصرف. ووضعُ القاعدة هنا — لا في الشاشة — يجعل أي
  /// عارضٍ جديد يسأل عنها بدل أن يُعيد اختراعها ناقصةً (درس المواضع الثمانية في ADR-028).
  static double paidTotal(Iterable<PayrollMonth> months) =>
      months.where((m) => m.isPaid).fold(0.0, (s, m) => s + m.totalIqd);

  /// ما في المسودّات — ينتظر التسديد.
  static double draftTotal(Iterable<PayrollMonth> months) =>
      months.where((m) => m.exists && !m.isPaid).fold(0.0, (s, m) => s + m.totalIqd);

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

  /// هل ثُبِّتت الأيام يدوياً؟ إن كانت `false` فالخادم يُعيد حسابها في كل حفظ.
  final bool eligibleDaysIsManual;

  final int absenceDays;
  final double? bonusAmount;
  final double? deductionAmount;
  final double absenceDeduction;
  final bool absenceDeductionIsManual;

  /// مكافأة نهاية الخدمة — تُضاف في شهر الإنهاء وحده وبقرار المستخدم.
  final double? endOfServiceAmount;

  final double netSalary;
  final double netSalaryIqd;
  final String paymentStatus;
  final int? paidByCompanyId;
  final String? paidByCompanyName;
  final bool isNewHire;
  final bool isTerminated;
  final String? notes;

  /// عدد إيصالات الاستلام **الموقَّعة المرفوعة** لهذا السطر (بلاغ المالك ٦).
  final int signedReceiptCount;

  /// إيصالٌ رُفع **قبل** آخر تعديلٍ للشهر ولم يُبَتّ فيه — يحتاج «قبول» أو «رفض» (ADR-026).
  final bool receiptIsStale;

  PayrollEntryModel({
    required this.entryId, required this.employeeCompanyId, required this.employeeId,
    required this.displayOrder, required this.name, required this.position,
    required this.currency, required this.baseSalary, required this.eligibleDays,
    this.eligibleDaysIsManual = false,
    required this.absenceDays, this.bonusAmount, this.deductionAmount,
    required this.absenceDeduction, required this.absenceDeductionIsManual,
    this.endOfServiceAmount,
    required this.netSalary, required this.netSalaryIqd,
    required this.paymentStatus, this.paidByCompanyId, this.paidByCompanyName,
    required this.isNewHire, required this.isTerminated, this.notes,
    this.signedReceiptCount = 0, this.receiptIsStale = false,
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
        eligibleDaysIsManual: j['eligibleDaysIsManual'] ?? false,
        absenceDays: j['absenceDays'] ?? 0,
        bonusAmount: (j['bonusAmount'] as num?)?.toDouble(),
        deductionAmount: (j['deductionAmount'] as num?)?.toDouble(),
        absenceDeduction: (j['absenceDeduction'] as num?)?.toDouble() ?? 0,
        absenceDeductionIsManual: j['absenceDeductionIsManual'] ?? false,
        endOfServiceAmount: (j['endOfServiceAmount'] as num?)?.toDouble(),
        netSalary: (j['netSalary'] as num?)?.toDouble() ?? 0,
        netSalaryIqd: (j['netSalaryIqd'] as num?)?.toDouble() ?? 0,
        paymentStatus: j['paymentStatus'] ?? 'Unpaid',
        paidByCompanyId: j['paidByCompanyId'],
        paidByCompanyName: j['paidByCompanyName'],
        signedReceiptCount: j['signedReceiptCount'] ?? 0,
        receiptIsStale: j['receiptIsStale'] ?? false,
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

  /// بصمة التزامن المتفائل — **نصٌّ مبهم يُعاد كما جاء**.
  ///
  /// ⚠️ **`byte[]` في ASP.NET Core يُسلسَل نصّاً بـbase64 لا مصفوفةَ أرقام** (مثل
  /// `"AAAAAAAApBE="`). كانت هنا `List<int>` فانهار التحويل بـ
  /// `type 'String' is not a subtype of type 'Iterable<dynamic>'` وسقطت الشاشة.
  /// ولا تُفكَّك ولا تُفسَّر: تُقرأ وتُعاد كما هي، و`System.Text.Json` يفكّها إلى
  /// `byte[]` على الخادم. (بلاغ المالك 2026-08-04.)
  final String rowVersion;

  /// 🔴 **ما تدفعه الشركة فعلاً** — بعد استثناء ما صرفته شركةٌ أخرى (ADR-028).
  final double totalIqd;

  /// المستثنى لأن شركةً أخرى صرفته — **يُعرض بجانب الإجمالي ولا يُطرح صامتاً**.
  final double excludedIqd;

  final List<PayrollEntryModel> entries;

  /// وقت آخر تعديلٍ **بعد التسديد** — `null` إن لم يُعدَّل قطّ (ADR-026).
  final DateTime? lastAmendedAt;

  /// عدد التعديلات بعد التسديد.
  final int amendmentCount;

  /// هل يملك المستخدمُ الحاليّ تعديلَ هذا الشهر بعد تسديده؟ (لإظهار الزرّ أو إخفائه)
  final bool canAmend;

  /// هل عُدِّل الشهر بعد تسديده؟
  bool get isAmended => amendmentCount > 0;

  PayrollPeriodModel({
    required this.periodId, required this.year, required this.month,
    required this.monthName, required this.status, this.exchangeRate,
    required this.workingDaysMode, required this.workingDays, this.paidAt,
    this.outgoingBookId, this.manualBookNumber, this.notes,
    this.lastAmendedAt, this.amendmentCount = 0, this.canAmend = false,
    required this.rowVersion, required this.totalIqd, required this.entries,
    this.excludedIqd = 0,
  });

  /// هل استُثني شيء؟ (يُظهر سطر «مستثنى» بجانب الإجمالي)
  bool get hasExcluded => excludedIqd > 0;

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
        paidAt: j['paidAt'] == null ? null : parseInstant(j['paidAt']),
        outgoingBookId: j['outgoingBookId'],
        manualBookNumber: j['manualBookNumber'],
        notes: j['notes'],
        rowVersion: j['rowVersion'] as String? ?? '',
        totalIqd: (j['totalIqd'] as num?)?.toDouble() ?? 0,
        excludedIqd: (j['excludedIqd'] as num?)?.toDouble() ?? 0,
        entries: (j['entries'] as List? ?? [])
            .map((e) => PayrollEntryModel.fromJson(e)).toList(),
        lastAmendedAt: j['lastAmendedAt'] == null ? null : parseInstant(j['lastAmendedAt']),
        amendmentCount: j['amendmentCount'] ?? 0,
        canAmend: j['canAmend'] ?? false,
      );
}

/// قيدٌ في سجلّ تعديلات شهرٍ مُسدَّد (ADR-026) — يُعرض ولا يُعدَّل.
class PayrollAmendment {
  final int versionNo;
  final String reason;
  final String changedBy;
  final DateTime changedAt;
  PayrollAmendment(this.versionNo, this.reason, this.changedBy, this.changedAt);
  factory PayrollAmendment.fromJson(Map<String, dynamic> j) => PayrollAmendment(
        j['versionNo'] ?? 0,
        j['reason'] ?? '',
        j['changedBy'] ?? '',
        parseInstant(j['changedAt']),
      );
}

/// إيصال استلامٍ موقَّع مرفوع لسطر راتب (بلاغ المالك ٦).
class SignedReceipt {
  final int attachmentId;
  final String fileName;
  final int fileSize;
  final DateTime uploadedAt;
  SignedReceipt(this.attachmentId, this.fileName, this.fileSize, this.uploadedAt);
  factory SignedReceipt.fromJson(Map<String, dynamic> j) => SignedReceipt(
        j['attachmentId'], j['fileName'] ?? '', j['fileSize'] ?? 0,
        parseInstant(j['uploadedAt']),
      );
}

/// تنبيه «مدفوع من شركة أخرى» (ADR-024) — قراءة خالصة، والتعليم بقرار المستخدم لا تلقائياً.
class ExternalPaymentHint {
  final int entryId;
  final String employeeName;
  final int paidByCompanyId;
  final String paidByCompanyName;

  /// تاريخ صرف **الشركة الأخرى** — لا تاريخ الاطّلاع. قد يغيب لو سُدِّد هناك بلا تاريخ.
  final DateTime? paidAt;

  ExternalPaymentHint(
      this.entryId, this.employeeName, this.paidByCompanyId, this.paidByCompanyName,
      {this.paidAt});

  factory ExternalPaymentHint.fromJson(Map<String, dynamic> j) => ExternalPaymentHint(
      j['entryId'], j['employeeName'] ?? '', j['paidByCompanyId'], j['paidByCompanyName'] ?? '',
      paidAt: j['paidAt'] == null ? null : parseInstant(j['paidAt']));
}

/// شروط عمل الموظف في شركةٍ أخرى — **قالبُ تعبئةٍ عند الإسناد** (ADR-028).
///
/// ⚠️ **بلا تاريخ تعيين عمداً** (قرار المالك 2026-08-06): تاريخ التعيين في الشركة الثانية هو
/// تاريخ **بدء العمل فيها** لا المنقول عن الأولى.
class EmploymentTemplate {
  final String position;
  final String? positionEn;
  final String salaryCurrency;
  final double baseSalary;

  /// اسم الشركة التي جاءت منها هذه الشروط — يُعرض ليعرف المستخدم مصدر الأرقام.
  final String sourceCompanyName;

  EmploymentTemplate({
    required this.position,
    this.positionEn,
    required this.salaryCurrency,
    required this.baseSalary,
    required this.sourceCompanyName,
  });

  factory EmploymentTemplate.fromJson(Map<String, dynamic> j) => EmploymentTemplate(
        position: j['position'] ?? '',
        positionEn: j['positionEn'],
        salaryCurrency: j['salaryCurrency'] ?? 'IQD',
        baseSalary: (j['baseSalary'] as num?)?.toDouble() ?? 0,
        sourceCompanyName: j['sourceCompanyName'] ?? '',
      );
}

/// موظفٌ في الكشف **يعمل في أكثر من شركة** — وحالُ قراره (ADR-028).
///
/// 🔴 **أوسع من [ExternalPaymentHint] عمداً:** تلك تكشف مَن **صُرف له** فعلاً، فتترك باباً
/// مفتوحاً — لو لم تكن الشركة الأخرى قد سدّدت بعد فلا تنبيه، **فتدفع الشركتان معاً**.
/// وهذه تُلزم بالحسم قبل التسديد أياً كانت حال الأخرى.
class DualCompanyRow {
  final int entryId;
  final String employeeName;
  final int otherCompanyId;
  final String otherCompanyName;

  /// تاريخ صرف الشركة الأخرى — `null` تعني **أنها لم تسدّد بعد**.
  final DateTime? otherPaidAt;

  /// حالة الدفع المخزَّنة: `Unpaid` تعني «لم يُحسم».
  final String decision;

  final bool needsDecision;

  /// حُسم «يُصرف من هنا» ثم صرفت الأخرى بعده — قرارٌ تقادم فيجب إعادة حسمه.
  final bool isStale;

  DualCompanyRow({
    required this.entryId,
    required this.employeeName,
    required this.otherCompanyId,
    required this.otherCompanyName,
    required this.otherPaidAt,
    required this.decision,
    required this.needsDecision,
    required this.isStale,
  });

  /// هل صرفت الشركة الأخرى فعلاً؟ **يحكم أيّ القرارَين مسموح**: بلا صرفٍ هناك لا يجوز
  /// تعليم «صُرف من الخارج» — فذلك ادّعاءٌ على واقعةٍ لم تقع.
  bool get otherHasPaid => otherPaidAt != null;

  /// يحتاج تدخّلاً قبل التسديد (لم يُحسم، أو حُسم وتقادم).
  bool get blocksPayment => needsDecision || isStale;

  factory DualCompanyRow.fromJson(Map<String, dynamic> j) => DualCompanyRow(
        entryId: j['entryId'],
        employeeName: j['employeeName'] ?? '',
        otherCompanyId: j['otherCompanyId'] ?? 0,
        otherCompanyName: j['otherCompanyName'] ?? '',
        otherPaidAt: j['otherPaidAt'] == null ? null : parseInstant(j['otherPaidAt']),
        decision: j['decision'] ?? 'Unpaid',
        needsDecision: j['needsDecision'] ?? false,
        isStale: j['isStale'] ?? false,
      );
}

/// إجازةٌ معلّقة مع صاحبها — تجيب «مَن ينتظر؟» بدل «كم ينتظر؟».
class PendingLeave {
  final int leaveId;
  final int employeeId;
  final String employeeName;
  final String position;
  final String leaveTypeLabel;
  final DateTime fromDate;
  final DateTime toDate;
  final int durationDays;
  final bool deductFromSalary;
  final String? notes;

  /// طلبها الموظف بنفسه — **فقرارُ الحسم ينتظر المراجع** (ADR-033).
  final bool isSelfRequested;

  PendingLeave({
    required this.leaveId, required this.employeeId, required this.employeeName,
    required this.position, required this.leaveTypeLabel,
    required this.fromDate, required this.toDate, required this.durationDays,
    required this.deductFromSalary, this.notes,
    this.isSelfRequested = false,
  });

  factory PendingLeave.fromJson(Map<String, dynamic> j) => PendingLeave(
        leaveId: j['leaveId'],
        employeeId: j['employeeId'] ?? 0,
        employeeName: j['employeeName'] ?? '',
        position: j['position'] ?? '',
        leaveTypeLabel: j['leaveTypeLabel'] ?? '',
        fromDate: DateTime.tryParse(j['fromDate'] ?? '') ?? DateTime.now(),
        toDate: DateTime.tryParse(j['toDate'] ?? '') ?? DateTime.now(),
        durationDays: j['durationDays'] ?? 0,
        deductFromSalary: j['deductFromSalary'] ?? false,
        notes: j['notes'],
        isSelfRequested: j['isSelfRequested'] ?? false,
      );
}

class HrSettingsModel {
  final String defaultWorkingDaysMode;
  final int defaultWorkingDays;
  final bool endOfServiceEnabled;
  final String endOfServiceRatio;
  final int? endOfServiceCustomDays;

  HrSettingsModel(
    this.defaultWorkingDaysMode,
    this.defaultWorkingDays, {
    this.endOfServiceEnabled = false,
    this.endOfServiceRatio = 'MonthPerYear',
    this.endOfServiceCustomDays,
  });

  factory HrSettingsModel.fromJson(Map<String, dynamic> j) => HrSettingsModel(
        j['defaultWorkingDaysMode'] ?? 'Fixed',
        j['defaultWorkingDays'] ?? 30,
        endOfServiceEnabled: j['endOfServiceEnabled'] ?? false,
        endOfServiceRatio: j['endOfServiceRatio'] ?? 'MonthPerYear',
        endOfServiceCustomDays: j['endOfServiceCustomDays'],
      );
}

/// ملخّص الوحدتين للوحة التحكم — **كل حقلٍ قد يكون `null`** (ADR-025).
///
/// ⚠️ `null` تعني «**لا تملك هذا القسم**» لا «صفر»، والخادم يُفرغ ما لا يخصّ الطالب.
/// و`?? 0` هنا كانت ستُعيد إنتاج **الصفر الكاذب** الذي تفاداه الخادمُ عمداً: يقرأ صاحبُ
/// قسم الموظفين «رواتب هذا الشهر: 0» فيفهم أن الشركة لم تصرف شيئاً، والحقيقة أنه لا يراها.
/// **معلومة ناقصة أهون من معلومة كاذبة** — وهو الدرس نفسه الذي كلّف لوحة التحكم قبل ADR-017.
class HrSummary {
  final int? activeEmployees;
  final double? thisMonthTotalIqd;
  final double? thisYearTotalIqd;
  final int? unpaidMonths;
  final int? pendingLeaves;
  HrSummary(this.activeEmployees, this.thisMonthTotalIqd, this.thisYearTotalIqd,
      this.unpaidMonths, this.pendingLeaves);
  factory HrSummary.fromJson(Map<String, dynamic> j) => HrSummary(
      j['activeEmployees'],
      (j['thisMonthTotalIqd'] as num?)?.toDouble(),
      (j['thisYearTotalIqd'] as num?)?.toDouble(),
      j['unpaidMonths'],
      j['pendingLeaves']);
}

// ═══════════ الإجازات وسجلّ التغييرات ونهاية الخدمة (الدفعة ٢) ═══════════

/// أنواع الإجازات — مرآةٌ لـ`LeaveType` في الباك-إند.
const Map<String, String> kLeaveTypes = {
  'Annual': 'اعتيادية',
  'Sick': 'مرضية',
  'Administrative': 'إدارية',
  'Unpaid': 'بلا راتب',
  'Other': 'أخرى',
};

class LeaveModel {
  final int leaveId;
  final String leaveType;
  final String leaveTypeLabel;
  final DateTime fromDate;
  final DateTime toDate;
  final int durationDays;
  final bool requiresApproval;
  final String status;
  final bool deductFromSalary;
  final String? notes;
  final DateTime createdAt;
  final DateTime? reviewedAt;
  final String? reviewNotes;

  /// طلبها الموظف بنفسه من بروفايله؟ (ADR-033)
  ///
  /// ⚠️ **يعني أن قرار الحسم لم يُتَّخذ بعد** — الطلب الذاتيّ يصل بلا قرار، والمراجع
  /// يبتّ فيه عند الموافقة. وسطرٌ سجّله كاتب الشؤون يأتي بقراره معه.
  final bool isSelfRequested;

  LeaveModel({
    required this.leaveId, required this.leaveType, required this.leaveTypeLabel,
    required this.fromDate, required this.toDate, required this.durationDays,
    required this.requiresApproval, required this.status, required this.deductFromSalary,
    this.notes, required this.createdAt, this.reviewedAt, this.reviewNotes,
    this.isSelfRequested = false,
  });

  bool get isPending => status == 'Pending';
  bool get isApproved => status == 'Approved';
  bool get isRejected => status == 'Rejected';

  factory LeaveModel.fromJson(Map<String, dynamic> j) => LeaveModel(
        leaveId: j['leaveId'],
        leaveType: j['leaveType'] ?? 'Other',
        leaveTypeLabel: j['leaveTypeLabel'] ?? '',
        fromDate: DateTime.tryParse(j['fromDate'] ?? '') ?? DateTime.now(),
        toDate: DateTime.tryParse(j['toDate'] ?? '') ?? DateTime.now(),
        durationDays: j['durationDays'] ?? 0,
        requiresApproval: j['requiresApproval'] ?? false,
        status: j['status'] ?? 'Approved',
        deductFromSalary: j['deductFromSalary'] ?? false,
        notes: j['notes'],
        createdAt: parseInstant(j['createdAt']),
        reviewedAt: j['reviewedAt'] == null ? null : parseInstant(j['reviewedAt']),
        reviewNotes: j['reviewNotes'],
        isSelfRequested: j['isSelfRequested'] ?? false,
      );
}

/// سطر في سجلّ تغييرات الموظف — الوصف نصٌّ عربي جاهز من الخادم.
class EmployeeLogItem {
  final int logId;
  final String changeType;
  final String description;
  final String? oldValue;
  final String? newValue;
  final DateTime changedAt;

  EmployeeLogItem({
    required this.logId, required this.changeType, required this.description,
    this.oldValue, this.newValue, required this.changedAt,
  });

  factory EmployeeLogItem.fromJson(Map<String, dynamic> j) => EmployeeLogItem(
        logId: j['logId'],
        changeType: j['changeType'] ?? 'Other',
        description: j['description'] ?? '',
        oldValue: j['oldValue'],
        newValue: j['newValue'],
        changedAt: parseInstant(j['changedAt']),
      );
}

/// مكافأة نهاية خدمة **مقترَحة** — لا تُطبَّق حتى يحفظها المستخدم.
class EndOfServiceSuggestion {
  final int entryId;
  final String employeeName;
  final double amount;
  final String currency;
  final double yearsServed;
  final int daysPerYear;

  EndOfServiceSuggestion(this.entryId, this.employeeName, this.amount, this.currency,
      this.yearsServed, this.daysPerYear);

  factory EndOfServiceSuggestion.fromJson(Map<String, dynamic> j) => EndOfServiceSuggestion(
        j['entryId'],
        j['employeeName'] ?? '',
        (j['amount'] as num?)?.toDouble() ?? 0,
        j['currency'] ?? 'IQD',
        (j['yearsServed'] as num?)?.toDouble() ?? 0,
        j['daysPerYear'] ?? 0,
      );
}

// ═══════════════════ البروفايل الشخصي (ADR-033) ═══════════════════

/// هويّتي كما أراها — **قراءةٌ خالصة**.
///
/// 🔴 **لا حقلَ تحريرٍ واحد هنا** (قرار المالك 2026-08-10): الاسم — الحسابيّ والرسميّ —
/// يبقى بيد السوبر أدمن ورئيس الشركة وصاحب صلاحية إدارة الموظفين. الاسمُ في الكتب
/// الرسمية والإيصالات وسجلّ التدقيق، وتغييرُه بيد صاحبه يفصل ما وُقّع باسمٍ عمّن يحمله.
class MyProfile {
  final int userId;
  final String fullName;
  final String username;
  final String role;
  final String? companyName;
  final String? departmentName;

  /// بطاقة الموظف المربوطة — `null` لمن لا بطاقةَ له (سوبر أدمن · لم يُربط بعد).
  final int? employeeId;
  final String? employeeFullName;
  final String? employeeFullNameEn;
  final String? position;
  final DateTime? hireDate;
  final String? nationalId;
  final String? phone;
  final String? address;
  final bool hasPhoto;

  MyProfile({
    required this.userId, required this.fullName, required this.username,
    required this.role, this.companyName, this.departmentName,
    this.employeeId, this.employeeFullName, this.employeeFullNameEn,
    this.position, this.hireDate, this.nationalId, this.phone, this.address,
    this.hasPhoto = false,
  });

  /// تبويبا الإجازات والرواتب يظهران بهذا وحده — ولا يُسألان عن قسمٍ ولا دور.
  bool get isLinkedToEmployee => employeeId != null;

  /// ⚠️ `hireDate` **تاريخٌ تقويميّ لا لحظة** — يُقرأ بـ`tryParse` عمداً (ADR-032).
  factory MyProfile.fromJson(Map<String, dynamic> j) => MyProfile(
        userId: j['userId'] ?? 0,
        fullName: j['fullName'] ?? '',
        username: j['username'] ?? '',
        role: j['role'] ?? 'Reader',
        companyName: j['companyName'],
        departmentName: j['departmentName'],
        employeeId: j['employeeId'],
        employeeFullName: j['employeeFullName'],
        employeeFullNameEn: j['employeeFullNameEn'],
        position: j['position'],
        hireDate: DateTime.tryParse(j['hireDate'] ?? ''),
        nationalId: j['nationalId'],
        phone: j['phone'],
        address: j['address'],
        hasPhoto: j['hasPhoto'] ?? false,
      );
}

/// شهرٌ من رواتبي — **مُسدَّدٌ حصراً**، وبتفصيلٍ يُفهم منه الرقم لا برقمٍ مجرَّد.
class MyPayslip {
  final int periodId;
  final int year;
  final int month;
  final String monthLabel;
  final double baseSalary;
  final int eligibleDays;
  final int workingDays;
  final int absenceDays;
  final double absenceDeduction;
  final double? bonusAmount;
  final double? deductionAmount;
  final double netSalary;
  final double netSalaryIqd;
  final String currency;
  final String paymentStatus;
  final String paymentStatusLabel;
  final DateTime? paidAt;

  MyPayslip({
    required this.periodId, required this.year, required this.month,
    required this.monthLabel, required this.baseSalary, required this.eligibleDays,
    required this.workingDays, required this.absenceDays, required this.absenceDeduction,
    this.bonusAmount, this.deductionAmount,
    required this.netSalary, required this.netSalaryIqd, required this.currency,
    required this.paymentStatus, required this.paymentStatusLabel, this.paidAt,
  });

  /// صرفته شركةٌ أخرى ⇒ يُعرض بحالته ولا إيصالَ له من هنا (ADR-028).
  bool get paidByOtherCompany => paymentStatus == 'PaidByOtherCompany';

  factory MyPayslip.fromJson(Map<String, dynamic> j) => MyPayslip(
        periodId: j['periodId'] ?? 0,
        year: j['year'] ?? 0,
        month: j['month'] ?? 0,
        monthLabel: j['monthLabel'] ?? '',
        baseSalary: (j['baseSalary'] as num?)?.toDouble() ?? 0,
        eligibleDays: j['eligibleDays'] ?? 0,
        workingDays: j['workingDays'] ?? 0,
        absenceDays: j['absenceDays'] ?? 0,
        absenceDeduction: (j['absenceDeduction'] as num?)?.toDouble() ?? 0,
        bonusAmount: (j['bonusAmount'] as num?)?.toDouble(),
        deductionAmount: (j['deductionAmount'] as num?)?.toDouble(),
        netSalary: (j['netSalary'] as num?)?.toDouble() ?? 0,
        netSalaryIqd: (j['netSalaryIqd'] as num?)?.toDouble() ?? 0,
        currency: j['currency'] ?? 'IQD',
        paymentStatus: j['paymentStatus'] ?? 'Unpaid',
        paymentStatusLabel: j['paymentStatusLabel'] ?? '',
        paidAt: j['paidAt'] == null ? null : parseInstant(j['paidAt']),
      );
}

/// حسابٌ صالح للربط ببطاقة موظف (ADR-033).
class LinkableUser {
  final int userId;
  final String fullName;
  final String username;
  final String role;

  LinkableUser(this.userId, this.fullName, this.username, this.role);

  factory LinkableUser.fromJson(Map<String, dynamic> j) => LinkableUser(
        j['userId'] ?? 0, j['fullName'] ?? '', j['username'] ?? '', j['role'] ?? 'Reader');
}
