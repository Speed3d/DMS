# نموذج البيانات (Data Model)

> المصدر: `Dms.Domain`. مُطبّق عبر migration `InitialCreate` على SQL Server.

## الكيانات

### Company
`CompanyId, Name, Prefix (فريد), IsActive, CreatedAt` — شركة. `Prefix` يدخل في رقم الكتاب.

### Template
`TemplateId, CompanyId→Company, Name, HeaderImageKey?, FooterImageKey?, WatermarkImageKey?, WatermarkOpacity(0-100), Margin{Top,Right,Bottom,Left}, PageSize, FontFamily, IsActive, CreatedAt, UpdatedAt` — قالب بالصور (مفاتيح Blob).

### User / UserCompany
- `User`: `UserId, FullName, Username (فريد), PasswordHash, Role(enum), CompanyId?, CanApprove, IsActive, MustChangePassword, FailedLoginCount, LockedUntil?, CreatedByUserId?, CreatedAt`.
- `UserCompany`: `UserCompanyId, UserId, CompanyId` — شركات إضافية لرئيس الشركة (فريد على UserId+CompanyId).

### RefreshToken
`RefreshTokenId, UserId, TokenHash (مجزّأ), ExpiresAt, CreatedAt, RevokedAt?`.

### ApprovalDelegation
`DelegationId, CompanyId, FromUserId, ToUserId, StartDate, EndDate? (null=دائم), IsActive, CreatedByUserId, CreatedAt`.

### Entity (الجهة) / DocumentType
- `Entity`: `EntityId, CompanyId, Name, Kind(Outgoing/Incoming/Both), Notes?`.
- `DocumentType`: `DocumentTypeId, CompanyId, Name`.

### ExchangeRate (عام، بلا عزل شركة)
`ExchangeRateId, Currency, Rate(18,4), EffectiveDate, CreatedByUserId, CreatedAt`.

### OutgoingBook (الصادر)
`OutgoingId, CompanyId, Number?, Year?, SerialNo?, Date, EntityId→Entity, Subject, BodyHtml, TemplateId→Template, Status(Draft/Final), Amount?(18,2), Currency?, ExchangeRate?(18,4), AmountInIqd?(18,2), QrContent?, QrSignature?, GeneratedPdfBlobKey?, CreatedByUserId, CreatedAt, ApprovedByUserId?, ApprovedAt?, UpdatedAt?, IsDeleted, DeletedByUserId?, DeletedAt?, RowVersion`.
- فهارس فريدة: `(CompanyId, Year, SerialNo)` و `Number` (حيث ليست null).

### ArchiveDoc (Phase 2 — الكيان جاهز)
`ArchiveId, CompanyId, ArchiveNumber, Title, BookNumber?, BookDate?, FromEntityId?, ToEntityId?, DocumentTypeId?, Amount?, Currency?, ExchangeRate?, AmountInIqd?, Keywords?, Notes?, CreatedByUserId, CreatedAt, IsDeleted, DeletedBy/At?`.

### Attachment / DocumentVersion
- `Attachment`: `AttachmentId, OwnerType(Outgoing/Archive), OwnerId, FileName, BlobKey, FileType, FileSize, UploadedByUserId, UploadedAt`.
- `DocumentVersion`: `VersionId, DocType, DocId, VersionNo, SnapshotJson, ChangedByUserId, ChangedAt, ChangeNote?`.

### BackupRecord / BackupSchedule (نظامي — بلا عزل شركة)
- `BackupRecord`: `BackupRecordId, CreatedAt, CreatedByUserId?, FileName, SizeBytes, Type(Manual/Scheduled), Status(Success/Failed), Note?`.
- `BackupSchedule` (صفّ مفرد): `BackupScheduleId, Frequency(Off/Daily/Weekly), Enabled, Hour(0-23), LastRunAt?, NextRunAt?`.

### Counter / AuditLog
- `Counter`: مفتاح مركّب `(CompanyId, Year, Type)` + `LastNumber` — ترقيم آمن.
- `AuditLog`: `LogId, UserId?, CompanyId?, Action, EntityType, EntityId?, Details?, Timestamp`.

## قواعد عرضية
- **عزل الشركة:** فلتر عام على كل كيان له `CompanyId`.
- **الحذف الناعم:** `OutgoingBook` و `ArchiveDoc` (مع DeletedBy/At) — مُدمج في الفلتر العام.
- **المعادل بالدينار:** `AmountInIqd = USD ? Amount×Rate : Amount` (يُجمَّد لحظة الإنشاء/الاعتماد).
- **enums** تُخزَّن كـ int؛ تُسلسَل كنصوص في الـ API (JsonStringEnumConverter).

## Migrations
```bash
dotnet ef migrations add <Name> -p Dms.Infrastructure -s Dms.Api
dotnet ef database update      -p Dms.Infrastructure -s Dms.Api
```
المطبّق حالياً: `InitialCreate`.
