# نموذج البيانات (Data Model)

> المصدر: `Dms.Domain`. مُطبّق عبر migration `InitialCreate` على SQL Server.

## الكيانات

### Company
`CompanyId, Name, Prefix (فريد), IsActive, CreatedAt` — شركة. `Prefix` يدخل في رقم الكتاب.

### Template
`TemplateId, CompanyId→Company, Name, HeaderImageKey?, FooterImageKey?, WatermarkImageKey?, WatermarkOpacity(0-100), Margin{Top,Right,Bottom,Left}, PageSize, FontFamily, IsActive, CreatedAt, UpdatedAt` — قالب بالصور (مفاتيح Blob).

### User / UserCompany (تعدد الشركات — ADR-011)
- `User`: `UserId, FullName, Username (فريد), PasswordHash, Role(enum), CompanyId? (الشركة **الرئيسية**), CanApprove, CanManageIncoming (إدارة حالات الوارد — ADR-015), DepartmentId?→Department (مكان العمل), Modules (`AppModule` bitmask، افتراضي All — صلاحيات الأقسام، ADR-012), IsActive, MustChangePassword, FailedLoginCount, LockedUntil?, CreatedByUserId?, CreatedAt, AssignedCompanies (تنقّل)`.
- `UserCompany`: `UserCompanyId, UserId, CompanyId` — إسناد المستخدم لشركة (فريد على UserId+CompanyId). المستخدم قد يُربط بشركة أو عدّة شركات؛ الربط صلاحية للسوبر أدمن/رئيس الشركة، ولكل مستخدم غير سوبر أدمن شركة واحدة على الأقل.

### RefreshToken
`RefreshTokenId, UserId, TokenHash (مجزّأ), ExpiresAt, CreatedAt, RevokedAt?`.

### ApprovalDelegation
`DelegationId, CompanyId, FromUserId, ToUserId, StartDate, EndDate? (null=دائم), IsActive, CreatedByUserId, CreatedAt`.

### Entity (الجهة) / DocumentType / Department
- `Entity`: `EntityId, CompanyId, Name, Kind(Outgoing/Incoming/Both), Notes?`.
- `DocumentType`: `DocumentTypeId, CompanyId, Name`.
- `Department` (ADR-015): `DepartmentId, CompanyId, Name, IsActive, CreatedAt`. فهرس فريد `(CompanyId, Name)`. وجهة إحالة الوارد ومكان عمل الموظف. الحذف محروس (يُرفض إن كان محالاً إليه كتب واردة).

### ExchangeRate (عام، بلا عزل شركة)
`ExchangeRateId, Currency, Rate(18,4), EffectiveDate, CreatedByUserId, CreatedAt`.

### OutgoingBook (الصادر)
`OutgoingId, CompanyId, Number?, Year?, SerialNo?, Date, EntityId→Entity, Subject, BodyHtml, TemplateId→Template, Status(Draft/Final), Amount?(18,2), Currency?, ExchangeRate?(18,4), AmountInIqd?(18,2), QrContent?, QrSignature?, GeneratedPdfBlobKey?, CreatedByUserId, CreatedAt, ApprovedByUserId?, ApprovedAt?, UpdatedAt?, IsDeleted, DeletedByUserId?, DeletedAt?, RowVersion`.
- فهارس فريدة: `(CompanyId, Year, SerialNo)` و `Number` (حيث ليست null).

### IncomingBook (الوارد)
`IncomingId, CompanyId, IncomingNumber?, Year?, SerialNo?, ExternalNumber?, ExternalDate?, ReceivedDate, ReceivedTime?, EntityId→Entity (الجهة المرسِلة), Subject, DocumentTypeId?, ReceiveMethod(Manual/Mail/Email), ReceivedByUserId, Status(New/InReview/Replied/Closed/Archived), DepartmentId?→Department (القسم المحال إليه — ADR-015), FolderName? (مهجور — نص القسم القديم، للتوافق فقط), LastAction?, Keywords?, Notes?, Amount?(18,2), Currency?, ExchangeRate?(18,4), AmountInIqd?(18,2), ReplyOutgoingId?→OutgoingBook, CreatedByUserId, CreatedAt, UpdatedAt?, IsDeleted, DeletedByUserId?, DeletedAt?`.
- **الترقيم فوري عند الإنشاء** (بخلاف الصادر الذي يترقّم عند الاعتماد): `{Prefix}-IN-{Year}-{Serial:D5}` عبر `NumberingService` بنوع عدّاد `"Incoming"` — فكل كتاب وارد سجل رسمي منذ لحظته.
- فهارس فريدة: `(CompanyId, Year, SerialNo)` و`IncomingNumber` (حيث ليست null). فهارس بحث: `EntityId`, `Status`, `ReceivedDate`.
- **دورة الحياة:** مصفوفة مغلقة في `Dms.Domain/IncomingWorkflow.cs` (ADR-013) — جديد ← (قيد المراجعة | مغلق) · قيد المراجعة ← (تم الرد | مغلق) · تم الرد ← مغلق · مغلق ← مؤرشف · **مؤرشف نهائي**.
- **الربط بالصادر:** ثنائي الاتجاه — `IncomingBook.ReplyOutgoingId` ↔ `OutgoingBook.ReplyToIncomingId` (علاقة واحد‑لواحد، `SetNull` عند الحذف).
- **الإحالة والرؤية (ADR-015):** الإحالة تُسنِد الكتاب لقسم (`DepartmentId`)، والموظف/القارئ يرى كتبه **+ كتب قسمه**. `SetNull` عند حذف القسم.

### MovementLog (سجل حركة الوارد)
`MovementId, IncomingId→IncomingBook (Cascade), CompanyId, Action, Description, FromDepartment?, ToDepartment?, PerformedByUserId, PerformedAt`.
- مستقل عن `AuditLog` العام: يوثّق دورة حياة الكتاب تشغيلياً (Registered/StatusChanged/Forwarded/LinkedToOutgoing/UnlinkedFromOutgoing/Updated) ويُعرض Timeline في شاشة التفاصيل للسوبر أدمن ورئيس الشركة فقط.
- الوصف يُخزَّن بالعربية جاهزاً؛ اسم المنفّذ يُجلب عند العرض لا يُخزَّن.

### ArchiveDoc (Phase 2 — الكيان جاهز)
`ArchiveId, CompanyId, ArchiveNumber, Title, BookNumber?, BookDate?, FromEntityId?, ToEntityId?, DocumentTypeId?, Amount?, Currency?, ExchangeRate?, AmountInIqd?, Keywords?, Notes?, CreatedByUserId, CreatedAt, IsDeleted, DeletedBy/At?`.

### Attachment / DocumentVersion
- `Attachment`: `AttachmentId, OwnerType(Outgoing/Archive/Incoming), OwnerId, FileName, BlobKey, FileType, FileSize, UploadedByUserId, UploadedAt`. الحد 50 ميغابايت، والصيغ: PDF/JPG/JPEG/PNG/DOCX/XLSX/ZIP/DWG.
- `DocumentVersion`: `VersionId, DocType, DocId, VersionNo, SnapshotJson, ChangedByUserId, ChangedAt, ChangeNote?`.

### BackupRecord / BackupSchedule (نظامي — بلا عزل شركة)
- `BackupRecord`: `BackupRecordId, CreatedAt, CreatedByUserId?, FileName, SizeBytes, Type(Manual/Scheduled), Status(Success/Failed), Note?`.
- `BackupRecord`: `BackupRecordId, CreatedAt, CreatedByUserId?, FileName, SizeBytes, Type(Manual/Scheduled), Scope(DbOnly/Full), Category(Manual/Daily/Weekly/Monthly), Status(Success/Failed), Note?`. سياسة الاحتفاظ (جد/أب/ابن) في `Dms.Domain/Backup.cs` — ADR-014.
- `BackupSchedule` (صفّ مفرد): `BackupScheduleId, Frequency(Off/Daily/Weekly), Enabled, Hour(0-23), LastRunAt?, NextRunAt?`.

### Counter / AuditLog
- `Counter`: مفتاح مركّب `(CompanyId, Year, Type)` + `LastNumber` — ترقيم آمن.
- `AuditLog`: `LogId, UserId?, CompanyId?, Action, EntityType, EntityId?, Details?, Timestamp`.

## قواعد عرضية
- **عزل الشركة:** Global Query Filter على كل كيان له `CompanyId`. لكيان `User` الفلتر يشمل الشركات المُسندة أيضاً: `CompanyId == cid || AssignedCompanies.Any(c => c.CompanyId == cid)` (fail-closed: بلا شركة قابلة للتحديد ⇒ لا يرى شيئاً).
- **الحذف الناعم:** `OutgoingBook` و `ArchiveDoc` و `IncomingBook` (مع DeletedBy/At) — مُدمج في الفلتر العام.
- **المعادل بالدينار:** `AmountInIqd = USD ? Amount×Rate : Amount` (يُجمَّد لحظة الإنشاء/الاعتماد).
- **enums** تُخزَّن كـ int؛ تُسلسَل كنصوص في الـ API (JsonStringEnumConverter).

## Migrations
```bash
dotnet ef migrations add <Name> -p Dms.Infrastructure -s Dms.Api
dotnet ef database update      -p Dms.Infrastructure -s Dms.Api
```
السلسلة الحالية: `InitialCreate` → `AddBackup` → `AddArchiveBodyHtml` → `AddHeaderPhraseToOutgoingBook` → `AddSignatoryFields` → `MakeTemplateNullable` → `AddCompanyLogoImageKey` → `AddUserModules` (عمود `Modules`، افتراضي 63=All).
> ملاحظة: تعدد الشركات (ADR-011) لم يتطلّب migration (جدول `UserCompany` أُنشئ في `InitialCreate`، وتغيير الـ Query Filter لا يمسّ السكيمة).
