// نماذج البيانات (DTOs) المطابقة لعقود الـ API.

// نماذج وحدة الموظفين والرواتب في ملف مستقلّ (الملف هنا تجاوز الألف سطر)، وتُعاد
// تصديرها فيصل إليها كل من يستورد `models.dart` كالمعتاد بلا استيراد ثانٍ.
export 'models_hr.dart';

class AuthResult {
  final String accessToken;
  final DateTime accessExpires;
  final String refreshToken;
  final int userId;
  final String fullName;
  final String username;
  final String role;
  final List<int> companyIds;
  final bool mustChangePassword;

  /// وصول المستخدم **في كل شركة على حدة** (ADR-017) — تحتاجه القائمة الجانبية لتتبدّل
  /// مع تبديل الشركة بلا إعادة دخول.
  final List<CompanyAccess> companies;

  AuthResult({
    required this.accessToken,
    required this.accessExpires,
    required this.refreshToken,
    required this.userId,
    required this.fullName,
    required this.username,
    required this.role,
    required this.companyIds,
    required this.mustChangePassword,
    required this.companies,
  });

  bool get isSuperAdmin => role == 'SuperAdmin';

  /// الأدوار المعفاة من تقييد الأقسام — وصول كامل في كل شركاتها (مرآة لقاعدة الباك-إند).
  bool get _isExempt => role == 'SuperAdmin' || role == 'President';

  CompanyAccess? accessIn(int? companyId) {
    if (companyId == null) return null;
    for (final c in companies) {
      if (c.companyId == companyId) return c;
    }
    return null;
  }

  /// أقسام النظام المسموحة في الشركة الفعّالة.
  ///
  /// Hint: المعفَون يرون كل شيء حتى لو كانوا بلا إسناد أصلاً (السوبر أدمن قد يكون بلا شركة).
  List<String> modulesIn(int? companyId) {
    if (_isExempt) return kAllModules;
    return accessIn(companyId)?.modules ?? const [];
  }

  /// هل يملك المستخدم صلاحية الوصول للقسم في الشركة الفعّالة؟
  bool hasModule(String module, int? companyId) => modulesIn(companyId).contains(module);

  /// صلاحية اعتماد الصادر في الشركة الفعّالة.
  bool canApproveIn(int? companyId) => _isExempt || (accessIn(companyId)?.canApprove ?? false);

  /// صلاحية **كتابة** بطاقات الموظفين في الشركة الفعّالة (ADR-025).
  ///
  /// المعفَون (سوبر أدمن/رئيس) يملكونها بحكم دورهم — نظير ما يفعله `HttpCurrentUser`
  /// في الباك-إند، فالسوبر أدمن قد يكون بلا إسناد لأي شركة أصلاً.
  bool canManageEmployeesIn(int? companyId) =>
      _isExempt || (accessIn(companyId)?.canManageEmployees ?? false);

  /// صلاحية **كتابة** كشوف الرواتب — علَمٌ مستقلّ (ADR-025).
  bool canManagePayrollIn(int? companyId) =>
      _isExempt || (accessIn(companyId)?.canManagePayroll ?? false);

  factory AuthResult.fromJson(Map<String, dynamic> j) => AuthResult(
        accessToken: j['accessToken'],
        accessExpires: DateTime.tryParse(j['accessExpires'] ?? '') ?? DateTime.now(),
        refreshToken: j['refreshToken'],
        userId: j['userId'],
        fullName: j['fullName'] ?? '',
        username: j['username'] ?? '',
        role: j['role'] ?? 'Reader',
        companyIds: j['companyIds'] != null ? List<int>.from(j['companyIds']) : [],
        mustChangePassword: j['mustChangePassword'] ?? false,
        companies: j['companies'] != null
            ? (j['companies'] as List).map((e) => CompanyAccess.fromJson(e)).toList()
            : const [],
      );

  Map<String, dynamic> toJson() => {
        'accessToken': accessToken,
        'accessExpires': accessExpires.toIso8601String(),
        'refreshToken': refreshToken,
        'userId': userId,
        'fullName': fullName,
        'username': username,
        'role': role,
        'companyIds': companyIds,
        'mustChangePassword': mustChangePassword,
        'companies': companies.map((c) => c.toJson()).toList(),
      };
}

/// أقسام النظام الثمانية — مصدر واحد بدل تكرار القائمة في الشاشات.
///
/// ⚠️ **مرآةٌ لمصفوفة `AppModuleExtensions.Individual` في الباك-إند** — قسمٌ ناقص هنا لا يظهر
/// مربّعه في شاشة المستخدمين، فتموت صلاحيته بصمت (نمط «ميزة بلا مدخل»).
const List<String> kAllModules = [
  'Outgoing', 'Incoming', 'Archive', 'Reports', 'Users', 'Settings', 'Backup',
  'Employees', 'Payroll',
];

const Map<String, String> kModuleLabels = {
  'Outgoing': 'الصادر',
  'Incoming': 'الوارد',
  'Archive': 'الأرشيف',
  'Reports': 'التقارير',
  'Users': 'المستخدمون',
  'Settings': 'الإعدادات',
  'Backup': 'النسخ الاحتياطي',
  'Employees': 'الموظفون',
  'Payroll': 'الرواتب',
};

class Company {
  final int companyId;
  final String name;
  final String prefix;
  final bool isActive;
  final String? defaultSignatoryName;
  final String? defaultSignatoryTitle;
  final String? logoImageKey;

  const Company({
    required this.companyId,
    required this.name,
    required this.prefix,
    required this.isActive,
    this.defaultSignatoryName,
    this.defaultSignatoryTitle,
    this.logoImageKey,
  });

  factory Company.fromJson(Map<String, dynamic> json) => Company(
        companyId: json['companyId'],
        name: json['name'] ?? '',
        prefix: json['prefix'] ?? '',
        isActive: json['isActive'] ?? true,
        defaultSignatoryName: json['defaultSignatoryName'],
        defaultSignatoryTitle: json['defaultSignatoryTitle'],
        logoImageKey: json['logoImageKey'],
      );
}

class EntityModel {
  final int entityId;
  final int companyId;
  final String name;
  final String kind;
  final String? notes;
  EntityModel(this.entityId, this.companyId, this.name, this.kind, this.notes);
  factory EntityModel.fromJson(Map<String, dynamic> j) => EntityModel(
      j['entityId'], j['companyId'], j['name'] ?? '', j['kind'] ?? 'Both', j['notes']);
  Map<String, dynamic> toJson() => {
        'entityId': entityId,
        'companyId': companyId,
        'name': name,
        'kind': kind,
        'notes': notes,
      };
}

class TemplateModel {
  final int templateId;
  final int companyId;
  final String name;
  final int watermarkOpacity;
  final int marginTop, marginRight, marginBottom, marginLeft;
  final String pageSize;
  final String fontFamily;
  final bool isActive;
  final bool hasHeader, hasFooter, hasWatermark;
  TemplateModel({
    required this.templateId,
    required this.companyId,
    required this.name,
    required this.watermarkOpacity,
    required this.marginTop,
    required this.marginRight,
    required this.marginBottom,
    required this.marginLeft,
    required this.pageSize,
    required this.fontFamily,
    required this.isActive,
    required this.hasHeader,
    required this.hasFooter,
    required this.hasWatermark,
  });
  factory TemplateModel.fromJson(Map<String, dynamic> j) => TemplateModel(
        templateId: j['templateId'],
        companyId: j['companyId'],
        name: j['name'] ?? '',
        watermarkOpacity: j['watermarkOpacity'] ?? 10,
        marginTop: j['marginTop'] ?? 24,
        marginRight: j['marginRight'] ?? 40,
        marginBottom: j['marginBottom'] ?? 24,
        marginLeft: j['marginLeft'] ?? 40,
        pageSize: j['pageSize'] ?? 'A4',
        fontFamily: j['fontFamily'] ?? 'Amiri',
        isActive: j['isActive'] ?? true,
        hasHeader: j['hasHeader'] ?? false,
        hasFooter: j['hasFooter'] ?? false,
        hasWatermark: j['hasWatermark'] ?? false,
      );
  Map<String, dynamic> toJson() => {
        'templateId': templateId,
        'companyId': companyId,
        'name': name,
        'watermarkOpacity': watermarkOpacity,
        'marginTop': marginTop,
        'marginRight': marginRight,
        'marginBottom': marginBottom,
        'marginLeft': marginLeft,
        'pageSize': pageSize,
        'fontFamily': fontFamily,
        'isActive': isActive,
        'hasHeader': hasHeader,
        'hasFooter': hasFooter,
        'hasWatermark': hasWatermark,
      };
}

class ExchangeRateModel {
  final int exchangeRateId;
  final String currency;
  final num rate;
  final DateTime effectiveDate;
  ExchangeRateModel(this.exchangeRateId, this.currency, this.rate, this.effectiveDate);
  factory ExchangeRateModel.fromJson(Map<String, dynamic> j) => ExchangeRateModel(
      j['exchangeRateId'], j['currency'] ?? 'USD', j['rate'] ?? 0,
      DateTime.tryParse(j['effectiveDate'] ?? '') ?? DateTime.now());
}

class UserModel {
  final int userId;
  final String fullName;
  final String username;
  final String role;
  final List<int> companyIds;
  final bool isActive;
  final bool mustChangePassword;

  /// صلاحيات المستخدم وقسمه **في كل شركة على حدة** (ADR-017).
  final List<CompanyAccess> companies;

  UserModel({
    required this.userId,
    required this.fullName,
    required this.username,
    required this.role,
    required this.companyIds,
    required this.isActive,
    required this.mustChangePassword,
    required this.companies,
  });

  /// وصول المستخدم في شركة بعينها، أو `null` إن لم يكن مُسنَداً لها.
  CompanyAccess? accessIn(int? companyId) {
    if (companyId == null) return null;
    for (final c in companies) {
      if (c.companyId == companyId) return c;
    }
    return null;
  }

  factory UserModel.fromJson(Map<String, dynamic> j) => UserModel(
        userId: j['userId'],
        fullName: j['fullName'] ?? '',
        username: j['username'] ?? '',
        role: j['role'] ?? 'Reader',
        companyIds: j['companyIds'] != null ? List<int>.from(j['companyIds']) : [],
        isActive: j['isActive'] ?? true,
        mustChangePassword: j['mustChangePassword'] ?? false,
        companies: j['companies'] != null
            ? (j['companies'] as List).map((e) => CompanyAccess.fromJson(e)).toList()
            : const [],
      );
}

/// صلاحيات المستخدم وقسمه في شركة واحدة (ADR-017).
///
/// Hint: كانت هذه القيم واحدة تسري على كل شركات المستخدم، فتعذّر أن يدير الصادر في شركة
/// والتقارير في أخرى، أو أن يكون في «المالية» هنا و«الإدارة» هناك.
class CompanyAccess {
  final int companyId;
  final List<String> modules;
  final int? departmentId;
  final bool canApprove;
  final bool canManageIncoming;

  /// **يرى كل الوارد والأرشيف في هذه الشركة — متجاوزاً حدود القسم.**
  ///
  /// ⚠️ استثناء مقصود لا توسعة عامة: تُلغي عزل الأقسام لمن تُمنح له. **قراءة خالصة**
  /// — الإحالة وتغيير الحالة تبقيان محكومتين بـ[canManageIncoming].
  final bool canViewAllIncoming;

  /// **يدير بطاقات الموظفين في هذه الشركة** (ADR-025).
  ///
  /// قسم `Employees` يفتح **الرؤية**، وهذا العلَم يفتح **الكتابة**.
  final bool canManageEmployees;

  /// **يدير كشوف الرواتب في هذه الشركة** — علَمٌ مستقلّ (ADR-025).
  ///
  /// ⚠️ مفصولٌ عن [canManageEmployees] عمداً: مَن يُدخل بيانات الموظفين ليس بالضرورة
  /// مَن يصرف رواتبهم.
  final bool canManagePayroll;

  const CompanyAccess({
    required this.companyId,
    required this.modules,
    this.departmentId,
    this.canApprove = false,
    this.canManageIncoming = false,
    this.canViewAllIncoming = false,
    this.canManageEmployees = false,
    this.canManagePayroll = false,
  });

  factory CompanyAccess.fromJson(Map<String, dynamic> j) => CompanyAccess(
        companyId: j['companyId'],
        modules: j['modules'] != null ? List<String>.from(j['modules']) : const [],
        departmentId: j['departmentId'],
        canApprove: j['canApprove'] ?? false,
        canManageIncoming: j['canManageIncoming'] ?? false,
        canViewAllIncoming: j['canViewAllIncoming'] ?? false,
        canManageEmployees: j['canManageEmployees'] ?? false,
        canManagePayroll: j['canManagePayroll'] ?? false,
      );

  Map<String, dynamic> toJson() => {
        'companyId': companyId,
        'modules': modules,
        'departmentId': departmentId,
        'canApprove': canApprove,
        'canManageIncoming': canManageIncoming,
        'canViewAllIncoming': canViewAllIncoming,
        'canManageEmployees': canManageEmployees,
        'canManagePayroll': canManagePayroll,
      };

  CompanyAccess copyWith({
    List<String>? modules,
    int? departmentId,
    bool clearDepartment = false,
    bool? canApprove,
    bool? canManageIncoming,
    bool? canViewAllIncoming,
    bool? canManageEmployees,
    bool? canManagePayroll,
  }) =>
      CompanyAccess(
        companyId: companyId,
        modules: modules ?? this.modules,
        departmentId: clearDepartment ? null : (departmentId ?? this.departmentId),
        canApprove: canApprove ?? this.canApprove,
        canManageIncoming: canManageIncoming ?? this.canManageIncoming,
        canViewAllIncoming: canViewAllIncoming ?? this.canViewAllIncoming,
        canManageEmployees: canManageEmployees ?? this.canManageEmployees,
        canManagePayroll: canManagePayroll ?? this.canManagePayroll,
      );
}

/// قسم داخل الشركة (وجهة إحالة الوارد ومكان عمل الموظف).
class DepartmentModel {
  final int departmentId;
  final int companyId;
  final String name;
  final bool isActive;
  DepartmentModel(this.departmentId, this.companyId, this.name, this.isActive);
  factory DepartmentModel.fromJson(Map<String, dynamic> j) => DepartmentModel(
      j['departmentId'], j['companyId'], j['name'] ?? '', j['isActive'] ?? true);
}

class DelegationModel {
  final int delegationId;
  final int fromUserId;
  final int toUserId;
  final DateTime startDate;
  final DateTime? endDate;
  final bool isActive;
  DelegationModel(this.delegationId, this.fromUserId, this.toUserId, this.startDate,
      this.endDate, this.isActive);
  factory DelegationModel.fromJson(Map<String, dynamic> j) => DelegationModel(
        j['delegationId'], j['fromUserId'], j['toUserId'],
        DateTime.tryParse(j['startDate'] ?? '') ?? DateTime.now(),
        j['endDate'] == null ? null : DateTime.tryParse(j['endDate']),
        j['isActive'] ?? true,
      );
}

class OutgoingListItem {
  final int outgoingId;
  final String? number;
  final DateTime date;
  final String subject;
  final String entityName;
  final String status;
  final num? amountInIqd;
  OutgoingListItem(this.outgoingId, this.number, this.date, this.subject,
      this.entityName, this.status, this.amountInIqd);
  factory OutgoingListItem.fromJson(Map<String, dynamic> j) => OutgoingListItem(
        j['outgoingId'],
        j['number'],
        DateTime.tryParse(j['date'] ?? '') ?? DateTime.now(),
        j['subject'] ?? '',
        j['entityName'] ?? '',
        j['status'] ?? 'Draft',
        j['amountInIqd'],
      );
}

class BackupScheduleModel {
  final String frequency; // Off/Daily/Weekly
  final bool enabled;
  final int hour;
  final DateTime? lastRunAt;
  final DateTime? nextRunAt;
  BackupScheduleModel(this.frequency, this.enabled, this.hour, this.lastRunAt, this.nextRunAt);
  factory BackupScheduleModel.fromJson(Map<String, dynamic> j) => BackupScheduleModel(
        j['frequency'] ?? 'Off', j['enabled'] ?? false, j['hour'] ?? 2,
        j['lastRunAt'] != null ? DateTime.tryParse(j['lastRunAt']) : null,
        j['nextRunAt'] != null ? DateTime.tryParse(j['nextRunAt']) : null);
}

/// كلمة التأكيد المطلوبة لاستعادة نسخة احتياطية.
/// Hint: يجب أن تطابق `BackupService.RestoreConfirmation` في الباك-إند حرفياً وإلا رُفض الطلب بـ 400.
const String kRestoreConfirmation = 'استعادة';

/// الاسم العربي لنطاق النسخة (ماذا تتضمّن).
String backupScopeLabel(String scope) => switch (scope) {
      'DbOnly' => 'قاعدة البيانات فقط',
      'Full' => 'كاملة (قاعدة + ملفات)',
      _ => scope,
    };

/// الاسم العربي لتصنيف الاحتفاظ.
String backupCategoryLabel(String category) => switch (category) {
      'Manual' => 'يدوية',
      'Daily' => 'يومية',
      'Weekly' => 'أسبوعية',
      'Monthly' => 'شهرية',
      _ => category,
    };

class BackupRecordModel {
  final int id;
  final DateTime createdAt;
  final String fileName;
  final int sizeBytes;
  final String type;
  /// نطاق النسخة: DbOnly / Full (Hint: اليومية المجدولة قاعدة فقط — أخفّ للرفع السحابي).
  final String scope;
  /// تصنيف الاحتفاظ: Manual / Daily / Weekly / Monthly.
  final String category;
  final String status;
  final String? note;
  BackupRecordModel(this.id, this.createdAt, this.fileName, this.sizeBytes, this.type,
      this.scope, this.category, this.status, this.note);
  factory BackupRecordModel.fromJson(Map<String, dynamic> j) => BackupRecordModel(
        j['backupRecordId'], DateTime.tryParse(j['createdAt'] ?? '') ?? DateTime.now(),
        j['fileName'] ?? '', j['sizeBytes'] ?? 0, j['type'] ?? 'Manual',
        j['scope'] ?? 'Full', j['category'] ?? 'Manual',
        j['status'] ?? 'Success', j['note']);
}

class FinancialRow {
  final String source;
  final String number;
  final DateTime date;
  final String entityName;
  final num? amount;
  final String? currency;
  final num? amountInIqd;
  FinancialRow(this.source, this.number, this.date, this.entityName, this.amount, this.currency, this.amountInIqd);
  factory FinancialRow.fromJson(Map<String, dynamic> j) => FinancialRow(
        j['source'] ?? '', j['number'] ?? '',
        DateTime.tryParse(j['date'] ?? '') ?? DateTime.now(),
        j['entityName'] ?? '', j['amount'], j['currency'], j['amountInIqd']);
}

class FinancialReport {
  final List<FinancialRow> rows;
  final num totalIqd;
  final int count;
  FinancialReport(this.rows, this.totalIqd, this.count);
  factory FinancialReport.fromJson(Map<String, dynamic> j) => FinancialReport(
        ((j['rows'] ?? []) as List).map((e) => FinancialRow.fromJson(e)).toList(),
        j['totalIqd'] ?? 0, j['count'] ?? 0);
}

class ArchiveListItem {
  final int archiveId;
  final String archiveNumber;
  final String title;
  final String? bookNumber;
  final DateTime? bookDate;
  final num? amountInIqd;
  final DateTime createdAt;
  ArchiveListItem(this.archiveId, this.archiveNumber, this.title, this.bookNumber,
      this.bookDate, this.amountInIqd, this.createdAt);
  factory ArchiveListItem.fromJson(Map<String, dynamic> j) => ArchiveListItem(
        j['archiveId'], j['archiveNumber'] ?? '', j['title'] ?? '', j['bookNumber'],
        j['bookDate'] == null ? null : DateTime.tryParse(j['bookDate']),
        j['amountInIqd'],
        DateTime.tryParse(j['createdAt'] ?? '') ?? DateTime.now(),
      );
}

class ArchiveDetail {
  final int archiveId;
  final String archiveNumber;
  final String title;
  final String? bookNumber;
  final DateTime? bookDate;
  final int? fromEntityId, toEntityId, documentTypeId;
  final num? amount;
  final String? currency;
  final num? exchangeRate;
  final num? amountInIqd;
  final String? keywords, notes, bodyHtml;
  /// اسم نوع المستند كما يحلّه الخادم — بدونه كانت الشاشة تعرض «مستند ذو نوع #3».
  final String? documentTypeName;
  /// القسم الذي تخصّه الأضبارة — اختياري (يحدّد من يراها ويُفلتَر به في الأرشيف).
  final int? departmentId;
  ArchiveDetail({
    required this.archiveId, required this.archiveNumber, required this.title,
    required this.bookNumber, required this.bookDate,
    required this.fromEntityId, required this.toEntityId, required this.documentTypeId,
    required this.amount, required this.currency, required this.exchangeRate, required this.amountInIqd,
    required this.keywords, required this.notes, required this.bodyHtml,
    this.documentTypeName,
    this.departmentId,
  });
  factory ArchiveDetail.fromJson(Map<String, dynamic> j) => ArchiveDetail(
        archiveId: j['archiveId'], archiveNumber: j['archiveNumber'] ?? '', title: j['title'] ?? '',
        bookNumber: j['bookNumber'],
        bookDate: j['bookDate'] == null ? null : DateTime.tryParse(j['bookDate']),
        fromEntityId: j['fromEntityId'], toEntityId: j['toEntityId'], documentTypeId: j['documentTypeId'],
        amount: j['amount'], currency: j['currency'], exchangeRate: j['exchangeRate'], amountInIqd: j['amountInIqd'],
        keywords: j['keywords'], notes: j['notes'], bodyHtml: j['bodyHtml'],
        documentTypeName: j['documentTypeName'],
        departmentId: j['departmentId'],
      );
}

/// صفٌّ في **عدسة الأرشيف** — عرض موحّد يجمع الوارد المؤرشف والأضابير الورقية.
///
/// ⚠️ الكتاب المؤرشف **لا يُنقل ولا يُنسخ**؛ يبقى كتاباً وارداً برقمه ومرفقاته وسجل
/// حركته، والأرشيف عدسةُ قراءة فوقه. لذلك [source] يحدّد أي شاشة تُفتح عند النقر.
class ArchiveLensItem {
  /// 'Incoming' = كتاب وارد مؤرشف · 'Paper' = أضبارة ورقية قديمة.
  final String source;
  final int id;
  final String number;
  final String title;
  final DateTime archivedAt;
  final int year, month;
  final String? entityName, documentTypeName, note;

  /// قد تكون **فارغة**: الإحالة متاحة في «جديد/قيد المراجعة» فقط، فكتابٌ مرّ
  /// (جديد ← مغلق ← مؤرشف) لا قسم له — وهذا واقع أغلب المؤرشف لا حالة نادرة.
  final List<String> departmentNames;

  ArchiveLensItem({
    required this.source, required this.id, required this.number, required this.title,
    required this.archivedAt, required this.year, required this.month,
    required this.departmentNames,
    this.entityName, this.documentTypeName, this.note,
  });

  bool get isIncoming => source == 'Incoming';

  factory ArchiveLensItem.fromJson(Map<String, dynamic> j) => ArchiveLensItem(
        source: j['source']?.toString() ?? 'Paper',
        id: j['id'],
        number: j['number'] ?? '—',
        title: j['title'] ?? '',
        archivedAt: DateTime.tryParse(j['archivedAt'] ?? '') ?? DateTime.now(),
        year: j['year'] ?? 0,
        month: j['month'] ?? 0,
        entityName: j['entityName'],
        documentTypeName: j['documentTypeName'],
        departmentNames:
            j['departmentNames'] != null ? List<String>.from(j['departmentNames']) : const [],
        note: j['note'],
      );
}

/// نتيجة استيراد ملف واحد ضمن دفعة أرشيف.
class BulkImportRow {
  final String fileName;
  final bool ok;
  final int? archiveId;
  final String? number, title, error;

  /// اسم الملف كان بلا معنى (`IMG_0234`) — يحتاج عنواناً يدوياً لاحقاً.
  final bool needsTitle;

  BulkImportRow({
    required this.fileName, required this.ok, required this.needsTitle,
    this.archiveId, this.number, this.title, this.error,
  });

  factory BulkImportRow.fromJson(Map<String, dynamic> j) => BulkImportRow(
        fileName: j['fileName'] ?? '',
        ok: j['ok'] ?? false,
        needsTitle: j['needsTitle'] ?? false,
        archiveId: j['archiveId'],
        number: j['number'],
        title: j['title'],
        error: j['error'],
      );
}

/// حصيلة استيراد دفعة — **الفشل جزئي**: ملف تالف لا يُبطل الدفعة كلها.
class BulkImportResult {
  final int total, created, failed, needTitleCount;
  final List<BulkImportRow> rows;

  BulkImportResult({
    required this.total, required this.created, required this.failed,
    required this.needTitleCount, required this.rows,
  });

  factory BulkImportResult.fromJson(Map<String, dynamic> j) => BulkImportResult(
        total: j['total'] ?? 0,
        created: j['created'] ?? 0,
        failed: j['failed'] ?? 0,
        needTitleCount: j['needTitleCount'] ?? 0,
        rows: (j['rows'] as List? ?? []).map((e) => BulkImportRow.fromJson(e)).toList(),
      );
}

/// تغطية النسخ الاحتياطي — عمر آخر نسخة **كاملة** ومدى إلحاح أخذ واحدة.
class BackupCoverage {
  final DateTime? lastFullBackupAt;
  final int? daysSince;
  final int maxAgeDays;

  /// `Ok` · `Soon` · `Urgent` · `Overdue` — وتصاعدها يُحدّد لون التنبيه.
  final String urgency;
  final String message;

  BackupCoverage({
    required this.urgency, required this.message, required this.maxAgeDays,
    this.lastFullBackupAt, this.daysSince,
  });

  bool get isOk => urgency == 'Ok';
  bool get isOverdue => urgency == 'Overdue';

  factory BackupCoverage.fromJson(Map<String, dynamic> j) => BackupCoverage(
        urgency: j['urgency'] ?? 'Overdue',
        message: j['message'] ?? '',
        maxAgeDays: j['maxAgeDays'] ?? 30,
        lastFullBackupAt: j['lastFullBackupAt'] == null ? null : DateTime.tryParse(j['lastFullBackupAt']),
        daysSince: j['daysSinceFullBackup'],
      );
}

/// حصيلة تشغيل المرآة.
class MirrorResult {
  final String targetPath;
  final int copied, skipped;
  final num copiedBytes, totalBytes;
  final bool databaseOk;
  final String? note;

  MirrorResult({
    required this.targetPath, required this.copied, required this.skipped,
    required this.copiedBytes, required this.totalBytes, required this.databaseOk, this.note,
  });

  factory MirrorResult.fromJson(Map<String, dynamic> j) => MirrorResult(
        targetPath: j['targetPath'] ?? '',
        copied: j['copied'] ?? 0,
        skipped: j['skipped'] ?? 0,
        copiedBytes: j['copiedBytes'] ?? 0,
        totalBytes: j['totalBytes'] ?? 0,
        databaseOk: j['databaseOk'] ?? false,
        note: j['note'],
      );
}

class AttachmentModel {
  final int attachmentId;
  final String fileName;
  final String fileType;
  final int fileSize;
  final DateTime uploadedAt;
  AttachmentModel(this.attachmentId, this.fileName, this.fileType, this.fileSize, this.uploadedAt);
  factory AttachmentModel.fromJson(Map<String, dynamic> j) => AttachmentModel(
        j['attachmentId'], j['fileName'] ?? '', j['fileType'] ?? '', j['fileSize'] ?? 0,
        DateTime.tryParse(j['uploadedAt'] ?? '') ?? DateTime.now());
}

class DocumentTypeModel {
  final int documentTypeId;
  final int companyId;
  final String name;
  DocumentTypeModel(this.documentTypeId, this.companyId, this.name);
  factory DocumentTypeModel.fromJson(Map<String, dynamic> j) =>
      DocumentTypeModel(j['documentTypeId'], j['companyId'], j['name'] ?? '');
}

class VersionModel {
  final int versionNo;
  final DateTime changedAt;
  final int changedByUserId;
  final String? changeNote;
  VersionModel(this.versionNo, this.changedAt, this.changedByUserId, this.changeNote);
  factory VersionModel.fromJson(Map<String, dynamic> j) => VersionModel(
        j['versionNo'], DateTime.tryParse(j['changedAt'] ?? '') ?? DateTime.now(),
        j['changedByUserId'] ?? 0, j['changeNote']);
}

class OutgoingDetail {
  final int outgoingId;
  final int companyId;
  final String? number;
  final DateTime date;
  final int entityId;
  final String entityName;
  final int templateId;
  final String? headerPhrase;
  final String? signatoryName;
  final String? signatoryTitle;
  final String subject;
  final String bodyHtml;
  final String status;
  final num? amount;
  final String? currency;
  final num? exchangeRate;
  final num? amountInIqd;
  final String? qrContent;
  final bool hasPdf;
  final String rowVersion;
  final bool canApprove;
  final String? bodyJson;
  /// الكتاب الوارد الذي يردّ عليه هذا الصادر (Hint: الربط العكسي — يُعرض في شاشة التفاصيل).
  final int? replyToIncomingId;
  final String? replyToIncomingNumber;
  OutgoingDetail({
    required this.outgoingId,
    required this.companyId,
    required this.number,
    required this.date,
    required this.entityId,
    required this.entityName,
    required this.templateId,
    required this.headerPhrase,
    required this.signatoryName,
    required this.signatoryTitle,
    required this.subject,
    required this.bodyHtml,
    required this.status,
    required this.amount,
    required this.currency,
    required this.exchangeRate,
    required this.amountInIqd,
    required this.qrContent,
    required this.hasPdf,
    required this.rowVersion,
    this.canApprove = false,
    this.bodyJson,
    this.replyToIncomingId,
    this.replyToIncomingNumber,
  });
  bool get isFinal => status == 'Final';
  factory OutgoingDetail.fromJson(Map<String, dynamic> j) => OutgoingDetail(
        outgoingId: j['outgoingId'],
        companyId: j['companyId'],
        number: j['number'],
        date: DateTime.tryParse(j['date'] ?? '') ?? DateTime.now(),
        entityId: j['entityId'],
        entityName: j['entityName'] ?? '',
        templateId: j['templateId'],
        headerPhrase: j['headerPhrase'],
        signatoryName: j['signatoryName'],
        signatoryTitle: j['signatoryTitle'],
        subject: j['subject'] ?? '',
        bodyHtml: j['bodyHtml'] ?? '',
        status: j['status'] ?? 'Draft',
        amount: j['amount'],
        currency: j['currency'],
        exchangeRate: j['exchangeRate'],
        amountInIqd: j['amountInIqd'],
        qrContent: j['qrContent'],
        hasPdf: j['hasPdf'] ?? false,
        rowVersion: j['rowVersion'] ?? '',
        canApprove: j['canApprove'] ?? false,
        bodyJson: j['bodyJson'],
        replyToIncomingId: j['replyToIncomingId'],
        replyToIncomingNumber: j['replyToIncomingNumber'],
      );
}

// ──────────────────── ثوابت الوارد (مرآة لـ enums الباك-إند) ────────────────────

/// طرق استلام الكتاب الوارد.
/// Hint: المفاتيح تطابق حرفياً enum `ReceiveMethod` في الباك-إند — أي اختلاف يجعل الحفظ يفشل بـ 400.
const Map<String, String> kReceiveMethods = {
  'Manual': 'تسليم باليد',
  'Mail': 'بريد عادي',
  'Email': 'بريد إلكتروني',
};

/// طريقة الاستلام الافتراضية عند تسجيل كتاب جديد.
const String kDefaultReceiveMethod = 'Manual';

/// حالات الكتاب الوارد.
/// Hint: المفاتيح تطابق حرفياً enum `IncomingStatus` في الباك-إند.
const Map<String, String> kIncomingStatuses = {
  'New': 'جديد',
  'InReview': 'قيد المراجعة',
  'Replied': 'تم الرد',
  'Closed': 'مغلق',
  'Archived': 'مؤرشف',
};

/// الانتقالات المسموحة بين الحالات.
/// Hint: نسخة مطابقة لمصفوفة `AllowedTransitions` في `IncomingService` بالباك-إند —
/// تُستخدم لعرض الخيارات المتاحة فقط بدل ترك المستخدم يصطدم برسالة رفض من الخادم.
/// مرآة لمصفوفة الانتقالات في الباك-إند (`IncomingWorkflow.Transitions`).
///
/// ⚠️ **الباك-إند هو مصدر الحقيقة** — هذه نسخة للعرض فقط تُحدَّد أي أزرار تظهر.
/// أي تعديل هنا بلا تعديل هناك يُنتج زرّاً يفشل عند الضغط، والعكس يُخفي إجراءً مسموحاً.
const Map<String, List<String>> kIncomingTransitions = {
  'New': ['InReview', 'Closed'],
  'InReview': ['Replied', 'Closed'],
  'Replied': ['Closed'],
  'Closed': ['Archived'],
  // فكّ الأرشفة — للمدير فأعلى بسبب إلزامي (قرار المالك 2026-07-28، يُعدّل ADR-013).
  'Archived': ['Closed'],
};

/// الاسم العربي للحالة (Hint: يعيد المفتاح نفسه إن كانت الحالة غير معروفة بدل إظهار فراغ).
String incomingStatusLabel(String status) => kIncomingStatuses[status] ?? status;

/// الاسم العربي لطريقة الاستلام.
String receiveMethodLabel(String method) => kReceiveMethods[method] ?? method;

class IncomingListItem {
  final int incomingId;
  final String? incomingNumber;
  final String? externalNumber;
  final DateTime receivedDate;
  final String subject;
  final String entityName;
  final String status;

  /// أسماء الأقسام المُحال إليها الكتاب — قد تكون أكثر من واحد (ADR-018).
  final List<String> departmentNames;
  final num? amountInIqd;

  IncomingListItem({
    required this.incomingId,
    required this.incomingNumber,
    required this.externalNumber,
    required this.receivedDate,
    required this.subject,
    required this.entityName,
    required this.status,
    required this.departmentNames,
    required this.amountInIqd,
  });

  factory IncomingListItem.fromJson(Map<String, dynamic> j) => IncomingListItem(
        incomingId: j['incomingId'],
        incomingNumber: j['incomingNumber'],
        externalNumber: j['externalNumber'],
        receivedDate: DateTime.tryParse(j['receivedDate'] ?? '') ?? DateTime.now(),
        subject: j['subject'] ?? '',
        entityName: j['entityName'] ?? '',
        status: j['status'] ?? 'New',
        departmentNames:
            j['departmentNames'] != null ? List<String>.from(j['departmentNames']) : const [],
        amountInIqd: j['amountInIqd'],
      );
}

/// إسناد كتاب وارد إلى قسم — بملاحظته الخاصة ومَن أحاله ومتى (ADR-018).
class IncomingAssignment {
  final int departmentId;
  final String name;
  final String? note;
  final String assignedByUserName;
  final DateTime assignedAt;

  const IncomingAssignment({
    required this.departmentId,
    required this.name,
    this.note,
    required this.assignedByUserName,
    required this.assignedAt,
  });

  factory IncomingAssignment.fromJson(Map<String, dynamic> j) => IncomingAssignment(
        departmentId: j['departmentId'],
        name: j['name'] ?? '—',
        note: j['note'],
        assignedByUserName: j['assignedByUserName'] ?? '—',
        assignedAt: DateTime.tryParse(j['assignedAt'] ?? '') ?? DateTime.now(),
      );
}

class IncomingDetail {
  final int incomingId;
  final int companyId;
  final String? incomingNumber;
  final int? year;
  final int? serialNo;
  final String? externalNumber;
  final DateTime? externalDate;
  final DateTime receivedDate;
  final String? receivedTime;
  final int entityId;
  final String entityName;
  final String subject;
  final int? documentTypeId;
  final String? documentTypeName;
  final String receiveMethod;
  final int receivedByUserId;
  final String receivedByUserName;
  final String status;

  /// الأقسام المُحال إليها مع ملاحظة كل قسم ومَن أحاله (ADR-018).
  final List<IncomingAssignment> departments;
  final String? lastAction;
  final String? keywords;
  final String? notes;
  final num? amount;
  final String? currency;
  final num? exchangeRate;
  final num? amountInIqd;
  final int? replyOutgoingId;
  final String? replyOutgoingNumber;
  final DateTime createdAt;

  IncomingDetail({
    required this.incomingId, required this.companyId, this.incomingNumber, this.year, this.serialNo,
    this.externalNumber, this.externalDate, required this.receivedDate, this.receivedTime,
    required this.entityId, required this.entityName, required this.subject, this.documentTypeId, this.documentTypeName,
    required this.receiveMethod, required this.receivedByUserId, required this.receivedByUserName,
    required this.status, this.departments = const [], this.lastAction, this.keywords, this.notes,
    this.amount, this.currency, this.exchangeRate, this.amountInIqd,
    this.replyOutgoingId, this.replyOutgoingNumber, required this.createdAt,
  });

  factory IncomingDetail.fromJson(Map<String, dynamic> j) => IncomingDetail(
        incomingId: j['incomingId'],
        companyId: j['companyId'],
        incomingNumber: j['incomingNumber'],
        year: j['year'],
        serialNo: j['serialNo'],
        externalNumber: j['externalNumber'],
        externalDate: j['externalDate'] != null ? DateTime.tryParse(j['externalDate']) : null,
        receivedDate: DateTime.tryParse(j['receivedDate'] ?? '') ?? DateTime.now(),
        receivedTime: j['receivedTime'],
        entityId: j['entityId'],
        entityName: j['entityName'] ?? '',
        subject: j['subject'] ?? '',
        documentTypeId: j['documentTypeId'],
        documentTypeName: j['documentTypeName'],
        receiveMethod: j['receiveMethod'] ?? kDefaultReceiveMethod,
        receivedByUserId: j['receivedByUserId'] ?? 0,
        receivedByUserName: j['receivedByUserName'] ?? '',
        status: j['status'] ?? 'New',
        departments: j['departments'] != null
            ? (j['departments'] as List).map((e) => IncomingAssignment.fromJson(e)).toList()
            : const [],
        lastAction: j['lastAction'],
        keywords: j['keywords'],
        notes: j['notes'],
        amount: j['amount'],
        currency: j['currency'],
        exchangeRate: j['exchangeRate'],
        amountInIqd: j['amountInIqd'],
        replyOutgoingId: j['replyOutgoingId'],
        replyOutgoingNumber: j['replyOutgoingNumber'],
        createdAt: DateTime.tryParse(j['createdAt'] ?? '') ?? DateTime.now(),
      );
}

class MovementLogItem {
  final int movementId;
  final String action;
  final String description;
  final String? fromDepartment;
  final String? toDepartment;
  final String performedByUserName;
  final DateTime performedAt;

  MovementLogItem({
    required this.movementId, required this.action, required this.description,
    this.fromDepartment, this.toDepartment,
    required this.performedByUserName, required this.performedAt,
  });

  factory MovementLogItem.fromJson(Map<String, dynamic> j) => MovementLogItem(
        movementId: j['movementId'],
        action: j['action'] ?? '',
        description: j['description'] ?? '',
        fromDepartment: j['fromDepartment'],
        toDepartment: j['toDepartment'],
        performedByUserName: j['performedByUserName'] ?? '',
        performedAt: DateTime.tryParse(j['performedAt'] ?? '') ?? DateTime.now(),
      );
}
