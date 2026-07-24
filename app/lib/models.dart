// نماذج البيانات (DTOs) المطابقة لعقود الـ API.

class AuthResult {
  final String accessToken;
  final DateTime accessExpires;
  final String refreshToken;
  final int userId;
  final String fullName;
  final String username;
  final String role;
  final List<int> companyIds;
  final bool canApprove;
  final bool mustChangePassword;

  /// أقسام النظام المسموح للمستخدم بالوصول إليها (السوبر أدمن/الرئيس = الكل).
  final List<String> modules;

  AuthResult({
    required this.accessToken,
    required this.accessExpires,
    required this.refreshToken,
    required this.userId,
    required this.fullName,
    required this.username,
    required this.role,
    required this.companyIds,
    required this.canApprove,
    required this.mustChangePassword,
    required this.modules,
  });

  bool get isSuperAdmin => role == 'SuperAdmin';

  /// هل يملك المستخدم صلاحية الوصول للقسم؟
  bool hasModule(String module) => modules.contains(module);

  factory AuthResult.fromJson(Map<String, dynamic> j) => AuthResult(
        accessToken: j['accessToken'],
        accessExpires: DateTime.tryParse(j['accessExpires'] ?? '') ?? DateTime.now(),
        refreshToken: j['refreshToken'],
        userId: j['userId'],
        fullName: j['fullName'] ?? '',
        username: j['username'] ?? '',
        role: j['role'] ?? 'Reader',
        companyIds: j['companyIds'] != null ? List<int>.from(j['companyIds']) : [],
        canApprove: j['canApprove'] ?? false,
        mustChangePassword: j['mustChangePassword'] ?? false,
        modules: j['modules'] != null ? List<String>.from(j['modules']) : const [],
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
        'canApprove': canApprove,
        'mustChangePassword': mustChangePassword,
        'modules': modules,
      };
}

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
  final bool canApprove;
  final bool isActive;
  final bool mustChangePassword;
  final List<String> modules;

  UserModel({
    required this.userId,
    required this.fullName,
    required this.username,
    required this.role,
    required this.companyIds,
    required this.canApprove,
    required this.isActive,
    required this.mustChangePassword,
    required this.modules,
  });

  factory UserModel.fromJson(Map<String, dynamic> j) => UserModel(
        userId: j['userId'],
        fullName: j['fullName'] ?? '',
        username: j['username'] ?? '',
        role: j['role'] ?? 'Reader',
        companyIds: j['companyIds'] != null ? List<int>.from(j['companyIds']) : [],
        canApprove: j['canApprove'] ?? false,
        isActive: j['isActive'] ?? true,
        mustChangePassword: j['mustChangePassword'] ?? false,
        modules: j['modules'] != null ? List<String>.from(j['modules']) : const [],
      );
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
  ArchiveDetail({
    required this.archiveId, required this.archiveNumber, required this.title,
    required this.bookNumber, required this.bookDate,
    required this.fromEntityId, required this.toEntityId, required this.documentTypeId,
    required this.amount, required this.currency, required this.exchangeRate, required this.amountInIqd,
    required this.keywords, required this.notes, required this.bodyHtml,
  });
  factory ArchiveDetail.fromJson(Map<String, dynamic> j) => ArchiveDetail(
        archiveId: j['archiveId'], archiveNumber: j['archiveNumber'] ?? '', title: j['title'] ?? '',
        bookNumber: j['bookNumber'],
        bookDate: j['bookDate'] == null ? null : DateTime.tryParse(j['bookDate']),
        fromEntityId: j['fromEntityId'], toEntityId: j['toEntityId'], documentTypeId: j['documentTypeId'],
        amount: j['amount'], currency: j['currency'], exchangeRate: j['exchangeRate'], amountInIqd: j['amountInIqd'],
        keywords: j['keywords'], notes: j['notes'], bodyHtml: j['bodyHtml'],
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
const Map<String, List<String>> kIncomingTransitions = {
  'New': ['InReview', 'Closed'],
  'InReview': ['Replied', 'Closed'],
  'Replied': ['Closed'],
  'Closed': ['Archived'],
  'Archived': <String>[],
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
  final String? folderName;
  final num? amountInIqd;

  IncomingListItem({
    required this.incomingId,
    required this.incomingNumber,
    required this.externalNumber,
    required this.receivedDate,
    required this.subject,
    required this.entityName,
    required this.status,
    required this.folderName,
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
        folderName: j['folderName'],
        amountInIqd: j['amountInIqd'],
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
  final String? folderName;
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
    required this.status, this.folderName, this.lastAction, this.keywords, this.notes,
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
        folderName: j['folderName'],
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
