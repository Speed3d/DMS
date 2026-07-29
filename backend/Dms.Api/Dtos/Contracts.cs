using Dms.Domain;
using Dms.Infrastructure.Auth;

namespace Dms.Api.Dtos;

// ----------------- Auth -----------------
public sealed record LoginRequest(string Username, string Password);
public sealed record RefreshRequest(string RefreshToken);
public sealed record ChangePasswordRequest(string CurrentPassword, string NewPassword);
public sealed record AuthResponse(
    string AccessToken, DateTime AccessExpires, string RefreshToken,
    int UserId, string FullName, string Username, UserRole Role,
    List<int> CompanyIds, bool MustChangePassword, List<CompanyAccess> Companies);
/// <summary>`canApprove` و`modules` هنا تخصّ **الشركة الفعّالة** للطلب (ADR-017).</summary>
public sealed record MeResponse(
    int UserId, string FullName, string Username, UserRole Role, List<int> CompanyIds,
    bool CanApprove, List<string> Modules, int? DepartmentId, bool CanManageIncoming,
    bool CanViewAllIncoming = false);

// ----------------- Company -----------------
public sealed record CompanyRequest(string Name, string Prefix, bool IsActive, string? DefaultSignatoryName = null, string? DefaultSignatoryTitle = null);
public sealed record CompanyResponse(int CompanyId, string Name, string Prefix, bool IsActive, string? DefaultSignatoryName, string? DefaultSignatoryTitle, string? LogoImageKey);

// ----------------- Template -----------------
public sealed record TemplateRequest(
    int? CompanyId, string Name, int WatermarkOpacity,
    int MarginTop, int MarginRight, int MarginBottom, int MarginLeft,
    string PageSize, string FontFamily, bool IsActive);
public sealed record TemplateResponse(
    int TemplateId, int CompanyId, string Name, int WatermarkOpacity,
    int MarginTop, int MarginRight, int MarginBottom, int MarginLeft,
    string PageSize, string FontFamily, bool IsActive,
    bool HasHeader, bool HasFooter, bool HasWatermark);

// ----------------- Entity / DocumentType / ExchangeRate -----------------
public sealed record EntityRequest(int? CompanyId, string Name, EntityKind Kind, string? Notes);
public sealed record EntityResponse(int EntityId, int CompanyId, string Name, EntityKind Kind, string? Notes);

public sealed record DocumentTypeRequest(int? CompanyId, string Name);
public sealed record DocumentTypeResponse(int DocumentTypeId, int CompanyId, string Name);

public sealed record DepartmentRequest(int? CompanyId, string Name, bool IsActive = true);
public sealed record DepartmentResponse(int DepartmentId, int CompanyId, string Name, bool IsActive);

public sealed record ExchangeRateRequest(Currency Currency, decimal Rate, DateTime EffectiveDate);
public sealed record ExchangeRateResponse(int ExchangeRateId, Currency Currency, decimal Rate, DateTime EffectiveDate);

// ----------------- Users / Delegations -----------------
/// <summary>صلاحيات المستخدم وقسمه في شركة واحدة (ADR-017).</summary>
public sealed record UserCompanyDto(
    int CompanyId, List<string>? Modules = null, int? DepartmentId = null,
    bool CanApprove = false, bool CanManageIncoming = false, bool CanViewAllIncoming = false);

public sealed record CreateUserRequest(
    string FullName, string Username, string Password, UserRole Role, List<UserCompanyDto>? Companies);
public sealed record UpdateUserRequest(
    string FullName, UserRole Role, List<UserCompanyDto>? Companies, bool IsActive);
public sealed record ResetPasswordRequest(string NewPassword);
public sealed record UserResponse(
    int UserId, string FullName, string Username, UserRole Role, List<int> CompanyIds,
    bool IsActive, bool MustChangePassword, List<UserCompanyDto> Companies);

public sealed record CreateDelegationRequest(int ToUserId, DateTime StartDate, DateTime? EndDate);
public sealed record DelegationResponse(int DelegationId, int FromUserId, int ToUserId, DateTime StartDate, DateTime? EndDate, bool IsActive);

// ----------------- Outgoing -----------------
public sealed record CreateOutgoingRequest(
    int? CompanyId, int EntityId, int? TemplateId, DateTime Date,
    string? HeaderPhrase, string? SignatoryName, string? SignatoryTitle, string Subject, string BodyHtml,
    decimal? Amount, Currency? Currency, decimal? ExchangeRate, string? BodyJson = null);

public sealed record UpdateOutgoingRequest(
    int EntityId, int? TemplateId, DateTime Date,
    string? HeaderPhrase, string? SignatoryName, string? SignatoryTitle, string Subject, string BodyHtml,
    decimal? Amount, Currency? Currency, decimal? ExchangeRate, string? BodyJson = null);

public sealed record EditApprovedRequest(
    int EntityId, int? TemplateId, DateTime Date,
    string? HeaderPhrase, string? SignatoryName, string? SignatoryTitle, string Subject, string BodyHtml,
    decimal? Amount, Currency? Currency, decimal? ExchangeRate,
    string RowVersion, string? ChangeNote, string? BodyJson = null);

public sealed record OutgoingListItem(
    int OutgoingId, string? Number, DateTime Date, string Subject,
    string EntityName, BookStatus Status, decimal? AmountInIqd, DateTime CreatedAt);

public sealed record OutgoingDetail(
    int OutgoingId, int CompanyId, string? Number, int? Year, int? SerialNo, DateTime Date,
    int EntityId, string EntityName, int? TemplateId, string? HeaderPhrase, string? SignatoryName, string? SignatoryTitle, string Subject, string BodyHtml,
    BookStatus Status, decimal? Amount, Currency? Currency, decimal? ExchangeRate, decimal? AmountInIqd,
    string? QrContent, bool HasPdf, int? ApprovedByUserId, DateTime? ApprovedAt,
    DateTime CreatedAt, DateTime? UpdatedAt, string RowVersion, bool CanApprove, string? BodyJson,
    // الربط العكسي: الكتاب الوارد الذي يردّ عليه هذا الصادر (إن وُجد)
    int? ReplyToIncomingId = null, string? ReplyToIncomingNumber = null);

public sealed record VersionResponse(int VersionNo, DateTime ChangedAt, int ChangedByUserId, string? ChangeNote);

// ----------------- Incoming -----------------
public sealed record CreateIncomingRequest(
    int? CompanyId, string? ExternalNumber, DateTime? ExternalDate,
    DateTime ReceivedDate, TimeSpan? ReceivedTime, int EntityId,
    string Subject, int? DocumentTypeId, ReceiveMethod ReceiveMethod,
    string? Keywords, string? Notes,
    decimal? Amount, Currency? Currency, decimal? ExchangeRate);

public sealed record UpdateIncomingRequest(
    string? ExternalNumber, DateTime? ExternalDate,
    DateTime ReceivedDate, TimeSpan? ReceivedTime, int EntityId,
    string Subject, int? DocumentTypeId, ReceiveMethod ReceiveMethod,
    string? Keywords, string? Notes,
    decimal? Amount, Currency? Currency, decimal? ExchangeRate);

public sealed record ChangeStatusRequest(IncomingStatus Status, string? Note);
/// <summary>إحالة لقسم واحد أو أكثر، بملاحظة لكل قسم وملاحظة عامة اختيارية (ADR-018).</summary>
public sealed record ForwardRequest(List<ForwardTargetDto> Departments, string? GeneralNote = null);
public sealed record ForwardTargetDto(int DepartmentId, string? Note = null);

/// <summary>قسم مُحال إليه الكتاب مع ملاحظته ومَن أحاله (ADR-018).</summary>
public sealed record IncomingAssignmentDto(
    int DepartmentId, string Name, string? Note, string AssignedByUserName, DateTime AssignedAt);

public sealed record IncomingListItem(
    int IncomingId, string? IncomingNumber, string? ExternalNumber,
    DateTime ReceivedDate, string Subject, string EntityName,
    IncomingStatus Status, List<string> DepartmentNames, decimal? AmountInIqd);

public sealed record IncomingDetail(
    int IncomingId, int CompanyId, string? IncomingNumber, int? Year, int? SerialNo,
    string? ExternalNumber, DateTime? ExternalDate,
    DateTime ReceivedDate, TimeSpan? ReceivedTime, int EntityId, string EntityName,
    string Subject, int? DocumentTypeId, string? DocumentTypeName,
    ReceiveMethod ReceiveMethod, int ReceivedByUserId, string ReceivedByUserName,
    IncomingStatus Status, List<IncomingAssignmentDto> Departments, string? LastAction, string? Keywords, string? Notes,
    decimal? Amount, Currency? Currency, decimal? ExchangeRate, decimal? AmountInIqd,
    int? ReplyOutgoingId, string? ReplyOutgoingNumber, DateTime CreatedAt);

public sealed record MovementLogItem(
    int MovementId, string Action, string Description,
    string? FromDepartment, string? ToDepartment,
    string PerformedByUserName, DateTime PerformedAt);

// ----------------- Archive -----------------
public sealed record ArchiveRequest(
    int? CompanyId, string Title, string? BookNumber, DateTime? BookDate,
    int? FromEntityId, int? ToEntityId, int? DocumentTypeId,
    decimal? Amount, Currency? Currency, decimal? ExchangeRate,
    string? Keywords, string? Notes, string? BodyHtml,
    int? DepartmentId = null);

public sealed record ArchiveListItem(
    int ArchiveId, string ArchiveNumber, string Title, string? BookNumber,
    DateTime? BookDate, int? DocumentTypeId, decimal? AmountInIqd, DateTime CreatedAt);

/// <summary>مصدر الصفّ في عدسة الأرشيف — يحدّد أي شاشة تُفتح عند النقر.</summary>
public enum ArchiveSource { Incoming, Paper }

/// <summary>نتيجة استيراد ملف واحد ضمن دفعة.</summary>
public sealed record BulkImportRow(string FileName, bool Ok, int? ArchiveId, string? Number, string? Title, bool NeedsTitle, string? Error);

/// <summary>حصيلة استيراد دفعة أرشيف ورقي.</summary>
/// <remarks>
/// ⚠️ **الفشل جزئي لا كلّي عمداً:** ملفٌ تالف أو بامتداد ممنوع لا يُبطل الدفعة كلها —
/// وإلا صار على المالك أن يعثر على الملف المخالف بين مئة ملف ويُعيد الرفع من الصفر.
/// كل صفّ يحمل نتيجته، و<see cref="NeedTitleCount"/> يقول له كم صفّاً يحتاج عنواناً.
/// </remarks>
public sealed record BulkImportResult(
    int Total, int Created, int Failed, int NeedTitleCount, List<BulkImportRow> Rows);

/// <summary>
/// صفٌّ في **عدسة الأرشيف**: عرض موحّد يجمع الوارد المؤرشف والأضابير الورقية القديمة.
/// </summary>
/// <remarks>
/// ⚠️ الكتاب الوارد **لا يُنقل ولا يُنسخ** عند الأرشفة — يبقى `IncomingBook` واحداً برقمه
/// الرسمي ومرفقاته وسجل حركته وربطه بالصادر. الأرشيف **عدسة قراءة** فوقه لا صندوق يبتلعه؛
/// فالنقل كان سيمنح الكتاب رقمين رسميين ويُنشئ نسختين من الحقيقة ويقطع شبكة مراجعه.
///
/// <see cref="DepartmentNames"/> قد تكون **فارغة**: الإحالة متاحة في حالتَي «جديد/قيد
/// المراجعة» فقط، فمسار (جديد ← مغلق ← مؤرشف) يُنتج كتاباً بلا قسم — وهذا واقع أغلب
/// المؤرشف في البيانات الحالية، لا حالة نادرة. ولهذا **المحور الأساسي للعرض السنة/الشهر
/// والقسم فلتر ثانوي**.
/// </remarks>
public sealed record ArchiveLensItem(
    ArchiveSource Source,
    int Id,
    string Number,
    string Title,
    DateTime ArchivedAt,
    int Year,
    int Month,
    string? EntityName,
    string? DocumentTypeName,
    List<string> DepartmentNames,
    string? Note);

public sealed record ArchiveDetail(
    int ArchiveId, int CompanyId, string ArchiveNumber, string Title, string? BookNumber, DateTime? BookDate,
    int? FromEntityId, int? ToEntityId, int? DocumentTypeId,
    decimal? Amount, Currency? Currency, decimal? ExchangeRate, decimal? AmountInIqd,
    string? Keywords, string? Notes, string? BodyHtml, DateTime CreatedAt,
    // Hint: الاسم يُحلّ في الخادم (كما في IncomingDetail) ليبقى العميل رفيعاً — كانت شاشة
    //       التفاصيل تعرض «مستند ذو نوع #3» لأن المعرّف وحده كان يصل إليها.
    string? DocumentTypeName = null,
    int? DepartmentId = null,
    string? DepartmentName = null);

public sealed record AttachmentResponse(int AttachmentId, string FileName, string FileType, long FileSize, DateTime UploadedAt);

// ----------------- Reports -----------------
public sealed record FinancialRowDto(string Source, string Number, DateTime Date, string EntityName, decimal? Amount, Currency? Currency, decimal? AmountInIqd);
public sealed record FinancialReportDto(DateTime? From, DateTime? To, List<FinancialRowDto> Rows, decimal TotalIqd, int Count);
public sealed record ActivityRowDto(DateTime Timestamp, int? UserId, string UserName, string Action, string EntityType, string? EntityId, string? Details);

// ----------------- Backup -----------------
public sealed record BackupRecordDto(int BackupRecordId, DateTime CreatedAt, int? CreatedByUserId, string FileName, long SizeBytes, BackupType Type, BackupScope Scope, RetentionCategory Category, BackupStatus Status, string? Note);

/// <summary>
/// تغطية النسخ الاحتياطي — عمر آخر نسخة **كاملة** ومدى إلحاح أخذ واحدة جديدة.
/// </summary>
/// <remarks>
/// المجدولة صارت «قاعدة فقط» فهي لا تحمي المرفقات؛ الحماية من نسخة كاملة يدوية.
/// <paramref name="Urgency"/>: <c>Ok</c> · <c>Soon</c> (٣ أيام) · <c>Urgent</c> (يوم/يومان) ·
/// <c>Overdue</c> (تجاوزت الحدّ **أو لم تُؤخذ قط**).
/// </remarks>
public sealed record BackupCoverageDto(
    DateTime? LastFullBackupAt, int? DaysSinceFullBackup, int MaxAgeDays, string Urgency, string Message);

/// <summary>مسار المرآة — يُدخله المالك في كل مرة، **بلا افتراض** (قراره).</summary>
public sealed record MirrorRequest(string TargetPath);

/// <summary>استعادة من مرآة — تتطلب كلمة التأكيد نفسها («استعادة»).</summary>
public sealed record MirrorRestoreRequest(string SourcePath, string Confirmation);
public sealed record BackupScheduleDto(BackupFrequency Frequency, bool Enabled, int Hour, DateTime? LastRunAt, DateTime? NextRunAt);
public sealed record UpdateBackupScheduleRequest(BackupFrequency Frequency, bool Enabled, int Hour);
public sealed record RestoreBackupRequest(string Confirmation);

// ----------------- Audit / Verify -----------------
public sealed record AuditResponse(long LogId, int? UserId, string Action, string EntityType, string? EntityId, string? Details, DateTime Timestamp);
public sealed record VerifyResponse(bool IsValid, string Message, string? Number, string? Date, string? Entity, string? AmountInIqd, bool FoundInDb);
