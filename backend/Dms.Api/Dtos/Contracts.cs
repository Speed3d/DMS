using Dms.Domain;

namespace Dms.Api.Dtos;

// ----------------- Auth -----------------
public sealed record LoginRequest(string Username, string Password);
public sealed record RefreshRequest(string RefreshToken);
public sealed record ChangePasswordRequest(string CurrentPassword, string NewPassword);
public sealed record AuthResponse(
    string AccessToken, DateTime AccessExpires, string RefreshToken,
    int UserId, string FullName, string Username, UserRole Role,
    List<int> CompanyIds, bool CanApprove, bool MustChangePassword, List<string> Modules);
public sealed record MeResponse(int UserId, string FullName, string Username, UserRole Role, List<int> CompanyIds, bool CanApprove, List<string> Modules);

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
public sealed record CreateUserRequest(string FullName, string Username, string Password, UserRole Role, List<int>? CompanyIds, bool CanApprove, List<string>? Modules = null,
    bool CanManageIncoming = false, int? DepartmentId = null);
public sealed record UpdateUserRequest(string FullName, UserRole Role, List<int>? CompanyIds, bool IsActive, bool CanApprove, List<string>? Modules = null,
    bool CanManageIncoming = false, int? DepartmentId = null);
public sealed record ResetPasswordRequest(string NewPassword);
public sealed record UserResponse(int UserId, string FullName, string Username, UserRole Role, List<int> CompanyIds, bool CanApprove, bool IsActive, bool MustChangePassword, List<string> Modules,
    bool CanManageIncoming, int? DepartmentId);

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
    string? FolderName, string? Keywords, string? Notes,
    decimal? Amount, Currency? Currency, decimal? ExchangeRate);

public sealed record UpdateIncomingRequest(
    string? ExternalNumber, DateTime? ExternalDate,
    DateTime ReceivedDate, TimeSpan? ReceivedTime, int EntityId,
    string Subject, int? DocumentTypeId, ReceiveMethod ReceiveMethod,
    string? FolderName, string? Keywords, string? Notes,
    decimal? Amount, Currency? Currency, decimal? ExchangeRate);

public sealed record ChangeStatusRequest(IncomingStatus Status, string? Note);
public sealed record ForwardRequest(int DepartmentId, string? Note);

public sealed record IncomingListItem(
    int IncomingId, string? IncomingNumber, string? ExternalNumber,
    DateTime ReceivedDate, string Subject, string EntityName,
    IncomingStatus Status, int? DepartmentId, string? DepartmentName, decimal? AmountInIqd);

public sealed record IncomingDetail(
    int IncomingId, int CompanyId, string? IncomingNumber, int? Year, int? SerialNo,
    string? ExternalNumber, DateTime? ExternalDate,
    DateTime ReceivedDate, TimeSpan? ReceivedTime, int EntityId, string EntityName,
    string Subject, int? DocumentTypeId, string? DocumentTypeName,
    ReceiveMethod ReceiveMethod, int ReceivedByUserId, string ReceivedByUserName,
    IncomingStatus Status, int? DepartmentId, string? DepartmentName, string? LastAction, string? Keywords, string? Notes,
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
    string? Keywords, string? Notes, string? BodyHtml);

public sealed record ArchiveListItem(
    int ArchiveId, string ArchiveNumber, string Title, string? BookNumber,
    DateTime? BookDate, int? DocumentTypeId, decimal? AmountInIqd, DateTime CreatedAt);

public sealed record ArchiveDetail(
    int ArchiveId, int CompanyId, string ArchiveNumber, string Title, string? BookNumber, DateTime? BookDate,
    int? FromEntityId, int? ToEntityId, int? DocumentTypeId,
    decimal? Amount, Currency? Currency, decimal? ExchangeRate, decimal? AmountInIqd,
    string? Keywords, string? Notes, string? BodyHtml, DateTime CreatedAt);

public sealed record AttachmentResponse(int AttachmentId, string FileName, string FileType, long FileSize, DateTime UploadedAt);

// ----------------- Reports -----------------
public sealed record FinancialRowDto(string Source, string Number, DateTime Date, string EntityName, decimal? Amount, Currency? Currency, decimal? AmountInIqd);
public sealed record FinancialReportDto(DateTime? From, DateTime? To, List<FinancialRowDto> Rows, decimal TotalIqd, int Count);
public sealed record ActivityRowDto(DateTime Timestamp, int? UserId, string UserName, string Action, string EntityType, string? EntityId, string? Details);

// ----------------- Backup -----------------
public sealed record BackupRecordDto(int BackupRecordId, DateTime CreatedAt, int? CreatedByUserId, string FileName, long SizeBytes, BackupType Type, BackupScope Scope, RetentionCategory Category, BackupStatus Status, string? Note);
public sealed record BackupScheduleDto(BackupFrequency Frequency, bool Enabled, int Hour, DateTime? LastRunAt, DateTime? NextRunAt);
public sealed record UpdateBackupScheduleRequest(BackupFrequency Frequency, bool Enabled, int Hour);
public sealed record RestoreBackupRequest(string Confirmation);

// ----------------- Audit / Verify -----------------
public sealed record AuditResponse(long LogId, int? UserId, string Action, string EntityType, string? EntityId, string? Details, DateTime Timestamp);
public sealed record VerifyResponse(bool IsValid, string Message, string? Number, string? Date, string? Entity, string? AmountInIqd, bool FoundInDb);
