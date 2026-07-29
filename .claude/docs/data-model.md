# نموذج البيانات (Data Model)

> المصدر: `Dms.Domain`. مُطبّق عبر migration `InitialCreate` على SQL Server.

## الكيانات

### Company
`CompanyId, Name, Prefix (فريد), IsActive, CreatedAt` — شركة. `Prefix` يدخل في رقم الكتاب.

### Template
`TemplateId, CompanyId→Company, Name, HeaderImageKey?, FooterImageKey?, WatermarkImageKey?, WatermarkOpacity(0-100), Margin{Top,Right,Bottom,Left}, PageSize, FontFamily, IsActive, CreatedAt, UpdatedAt` — قالب بالصور (مفاتيح Blob).

### User / UserCompany (تعدد الشركات — ADR-011 · صلاحيات لكل شركة — ADR-017)
- `User`: `UserId, FullName, Username (فريد), PasswordHash, Role(enum), CompanyId? (الشركة **الرئيسية** — دورها افتراضٌ عند غياب ترويسة `X-Company-Id` فقط), IsActive, MustChangePassword, FailedLoginCount, LockedUntil?, CreatedByUserId?, CreatedAt, AssignedCompanies (تنقّل)`.
- `UserCompany`: `UserCompanyId, UserId, CompanyId, Modules (`AppModule` bitmask، افتراضي All — ADR-012), DepartmentId?→Department (SetNull), CanApprove, CanManageIncoming` — إسناد المستخدم لشركة **وحاملُ صلاحياته وقسمه فيها**. فريد على `(UserId, CompanyId)`. الربط صلاحية للسوبر أدمن/رئيس الشركة، ولكل مستخدم غير سوبر أدمن شركة واحدة على الأقل.
  - ⚠️ **الحقول الأربعة كانت على `User`** (قيمة واحدة تسري على كل الشركات) وانتقلت في migration `AddPerCompanyPermissions` (ADR-017). الآن يمكن للموظف أن يدير الصادر والوارد في شركة، والصادر والتقارير في أخرى، ويكون في «المالية» هنا و«الإدارة» هناك.
  - **السوبر أدمن ورئيس الشركة معفيان** من تقييد الأقسام (وصول كامل في كل شركاتهم)؛ والسوبر أدمن قد يكون **بلا إسناد أصلاً**.

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
`IncomingId, CompanyId, IncomingNumber?, Year?, SerialNo?, ExternalNumber?, ExternalDate?, ReceivedDate, ReceivedTime?, EntityId→Entity (الجهة المرسِلة), Subject, DocumentTypeId?, ReceiveMethod(Manual/Mail/Email), ReceivedByUserId, Status(New/InReview/Replied/Closed/Archived), LastAction?, Keywords?, Notes?, Amount?(18,2), Currency?, ExchangeRate?(18,4), AmountInIqd?(18,2), ReplyOutgoingId?→OutgoingBook, CreatedByUserId, CreatedAt, UpdatedAt?, IsDeleted, DeletedByUserId?, DeletedAt?`.
- **الترقيم فوري عند الإنشاء** (بخلاف الصادر الذي يترقّم عند الاعتماد): `{Prefix}-IN-{Year}-{Serial:D5}` عبر `NumberingService` بنوع عدّاد `"Incoming"` — فكل كتاب وارد سجل رسمي منذ لحظته.
- فهارس فريدة: `(CompanyId, Year, SerialNo)` و`IncomingNumber` (حيث ليست null). فهارس بحث: `EntityId`, `Status`, `ReceivedDate`.
- **دورة الحياة:** مصفوفة مغلقة في `Dms.Domain/IncomingWorkflow.cs` (ADR-013) — جديد ← (قيد المراجعة | مغلق) · قيد المراجعة ← (تم الرد | مغلق) · تم الرد ← مغلق · مغلق ← مؤرشف · **مؤرشف نهائي**.
- **الربط بالصادر:** ثنائي الاتجاه — `IncomingBook.ReplyOutgoingId` ↔ `OutgoingBook.ReplyToIncomingId` (علاقة واحد‑لواحد، `SetNull` عند الحذف).
- **الإحالة والرؤية (ADR-018):** الإسناد صار **جدولاً مستقلاً** لا عموداً — انظر `IncomingAssignment` أدناه. الموظف/القارئ يرى: كتبه **+ كتب قسمه + ما أحاله بنفسه**.
- ⚠️ **أُسقط عمودا `DepartmentId` و`FolderName`** في migration `AddMultiDepartmentAssignments` (2026-07-27) بعد **نقل** إسناداتهما إلى الجدول الجديد. `FolderName` كان نسخة مُسطَّحة من اسم القسم فقد آخر معنى لها بتعدّد الأقسام.

### IncomingAssignment (إسناد الوارد لقسم — ADR-018)
`IncomingAssignmentId, IncomingId→IncomingBook (Cascade), DepartmentId→Department (Restrict), Note?(1000), AssignedByUserId, AssignedAt`.
- **فهرس فريد على `(IncomingId, DepartmentId)`** — إعادة الإحالة لقسم موجود تُحدّث ملاحظته ولا تُنشئ صفّاً ثانياً.
- **بلا `CompanyId`:** العزل يأتي من الأب `IncomingBook` المفلتَر بالشركة، ومعرّفات الأقسام فريدة عالمياً — فلا مسار تسرّب.
- `Restrict` على القسم مقصود: حذف قسم محال إليه كتب **يُرفض** (رسالة صريحة: «عطّله بدل حذفه»).
- `AssignedByUserId` ليس للسجل فقط — عليه تقوم قاعدة **«مَن أحال يبقى يرى»**.

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
- `BackupRecord`: `BackupRecordId, CreatedAt, CreatedByUserId?, FileName, SizeBytes, Type(Manual/Scheduled), Scope(DbOnly/Full), Category(Manual/Daily/Weekly/Monthly), Status(Success/Failed), Note?`. سياسة الاحتفاظ (جد/أب/ابن، 7/4/12/20) والتصنيف التلقائي في `Dms.Domain/Backup.cs` — ADR-014.
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
**السلسلة الحالية — 18 migration** (بالترتيب):

| # | Migration | ما أضافه |
|---|---|---|
| 1 | `InitialCreate` | كل الجداول الأساسية (يشمل `UserCompany`) |
| 2 | `AddBackup` | `BackupRecord` + `BackupSchedule` |
| 3 | `AddArchiveBodyHtml` | متن الأرشيف |
| 4 | `AddHeaderPhraseToOutgoingBook` | عبارة الترويسة |
| 5 | `AddSignatoryFields` | حقول الموقّع |
| 6 | `MakeTemplateNullable` | القالب صار اختيارياً |
| 7 | `AddCompanyLogoImageKey` | شعار الشركة |
| 8 | `AddUserModules` | عمود `Modules` (افتراضي **63** = الأقسام الستة وقتها) — ADR-012 |
| 9 | `AddOutgoingBodyJson` | `BodyJson` (Quill Delta) لاستعادة التنسيق عند التعديل |
| 10 | `AddIncomingModule` | جدولا `IncomingBooks` و`MovementLogs` + الربط العكسي. **ورقّى `Modules` من 63 إلى 127** للمستخدمين الكاملين (إضافة قسم الوارد) |
| 11 | `FixMovementLogRelation` | حذف العمود الشبح `IncomingBookIncomingId` **بعد ترحيل البيانات** + FK حقيقي على `IncomingId` |
| 12 | `AddBackupScopeAndRetention` | `Scope` + `Category` (الصفوف القديمة `Scope=Full`) — ADR-014 |
| 13 | `AddDepartments` | جدول `Departments` + `User.DepartmentId` + `User.CanManageIncoming` + `IncomingBook.DepartmentId` — ADR-015 |
| 14 | `AddPerCompanyPermissions` | نقل `Modules`/`DepartmentId`/`CanApprove`/`CanManageIncoming` من `Users` إلى `UserCompanies` — ADR-017. ⚠️ **الترتيب داخلها مقصود** (إضافة ← نقل ← إسقاط)؛ السقالة المولَّدة كانت تُسقط أولاً فتمحو صلاحيات الجميع |
| 15 | `AddMultiDepartmentAssignments` | جدول `IncomingAssignment` (كتاب ↔ عدّة أقسام) + **إسقاط** `IncomingBooks.DepartmentId` و`FolderName` — ADR-018. ⚠️ **الترتيب مقصود** (إنشاء ← **نقل الإسنادات القائمة** ← إسقاط) — نفس درس ADR-017. طُبِّقت على `DmsDb` بتاريخ 2026-07-27 وتحقُّق النقل تمّ فعلياً |
| 16 | `AddDocumentTypeUniqueIndex` | فهرس فريد `(CompanyId, Name)` على `DocumentTypes` + **بذر 8 أنواع افتراضية للشركات القائمة**. ⚠️ **البذر في المهاجرة لا في بذر الإقلاع** عمداً: الإقلاع يعمل كل تشغيل فيُعيد ما حذفه المالك؛ والمهاجرة مرّة واحدة. والفهرس **قبل** الإدراج ليفشل فوراً لو كان ثمّة تكرار سابق. طُبِّقت 2026-07-28 (شركتان × 8 أنواع) |
| 17 | `AddArchiveDepartmentAndUnarchive` | `ArchiveDoc.DepartmentId` **اختياري** + فهرس `(CompanyId, DepartmentId)` + FK بـ`SetNull` — ADR-021. ⚠️ العلاقة مضبوطة صراحةً (EF يولّد عموداً شبحاً إن تُركت ضمنية — حدث في `MovementLog`)، و`SetNull` مقصود: حذف قسم لا يجوز أن يمحو أضبارة بل يتركها «بلا قسم». **إضافة بحتة**. طُبِّقت 2026-07-28 |
| 18 | `AddCanViewAllIncoming` | `UserCompany.CanViewAllIncoming` (`bit`، افتراضه `false`) — ADR-022. **إضافة بحتة** ⇒ لا يتغيّر سلوك أي مستخدم قائم. طُبِّقت 2026-07-29 |

> **ملاحظات:**
> - تعدد الشركات (ADR-011) لم يتطلّب migration (جدول `UserCompany` أُنشئ في `InitialCreate`، وتغيير الـ Query Filter لا يمسّ السكيمة).
> - `AppModule.All` صار **127** (سبعة أقسام) بعد إضافة `Incoming`. من يقرأ الرقم 63 في migration رقم 8 فذلك هو تعريف `All` وقتها؛ الترقية تمّت في migration رقم 10 فلا يوجد مستخدم عالق بلا صلاحية الوارد.
