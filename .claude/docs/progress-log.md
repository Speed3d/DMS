# سجل التقدّم (Progress Log)

> يُحدَّث بعد كل خطوة مهمة (الأحدث أعلى). التواريخ ميلادية.

## 2026-06-30
- **Flutter App — وضع الأوفلاين (Offline Drafts):**
  - بناء ميزة المسودات المحلية لتطبيق الفلتر باستخدام قاعدة بيانات `Hive` لتتوافق مع نظام Windows.
  - إنشاء خدمة `local_storage.dart` لتخزين الجهات والقوالب كـ (Cache) وحفظ المسودات أوفلاين.
  - تعديل `api_client.dart` للتعرف على أخطاء الشبكة (`isNetworkError`).
  - تحديث `outgoing_form_screen.dart` لحفظ المسودة محلياً في حالة انقطاع الإنترنت.
  - بناء شاشة `offline_drafts_screen.dart` مع ميزة "مزامنة الكل" المتصلة آلياً بواجهة المستخدم عبر `ValueListenableBuilder`، وإضافتها للشريط الجانبي.

- **حالة المشروع:** إجراء بحث ودراسة شاملة للباك-إند وتطبيق الفلتر وملفات الوثائق، وتوثيق ذلك في تقرير حالة جديد `status-report.md`. نسبة الإنجاز تقدر بـ 90% للإصدار الأول.

## 2026-06-29
- **Phase 2 — النسخ الاحتياطي (مكتمل):**
  - كيانات `BackupRecord` + `BackupSchedule` (+ enums) + migration `AddBackup`.
  - `BackupService`: `BACKUP DATABASE` (.bak عبر اتصال SqlClient مستقل لتفادي استراتيجية إعادة المحاولة) + ضغط ملفات التخزين في ZIP واحد + سجلّ + جدولة (حساب NextRunAt) + تنزيل. `BackupScheduler` (BackgroundService) يشغّل المجدول. `AppPaths` (StorageRoot/BackupDir) مُسجّل في Program.
  - `BackupController` (SuperAdmin فقط): `/backup` (list) · `/backup/run` · `/backup/schedule` (GET/PUT) · `/backup/{id}/download`. + DTOs + حزمة `Microsoft.Extensions.Hosting.Abstractions`.
  - واجهة: `backup_screen` (جدولة + نسخة الآن + قائمة + تنزيل) + عنصر تنقّل للسوبر أدمن فقط.
  - تحقّق E2E: جدولة Daily، نسخة فورية **Success 4.5MB** تحوي `database.bak` (5.6MB) + 13 ملفاً، قائمة، تنزيل. `flutter analyze` نظيف + `build web`.

## 2026-06-28
- **Phase 2 — التقارير المالية (مكتمل):**
  - باك-إند: `FinancialReportPdf` (QuestPDF، جدول عربي) + `ExcelExporter` (OpenXML xlsx) في Dms.Documents + `ReportService` (يجمع الصادر المعتمد + الأرشيف بالدينار، تصفية تاريخ/جهة/مصدر، رؤية الموظف لعمله) + `ReportsController` (`/reports/financial` + `/pdf` + `/excel`) + DTOs.
  - واجهة: `reports_screen` (فلاتر فترة/جهة/مصدر → جدول + إجمالي بالدينار + تصدير PDF/Excel) + عنصر تنقّل «التقارير» + نماذج/دوال API.
  - تحقّق E2E: تقرير يجمع صادر (1,310,000) + أرشيف (2,620,000) = **3,930,000 د.ع**، فلتر الفترة يعمل، PDF 28KB + Excel xlsx صالحان. `flutter analyze` نظيف + `build web`.
- **إصلاح (توليد PDF):** `DocumentLayoutException` عند الاعتماد بقالب يحتوي صوراً مرفوعة — صورة الهيدر بنسبة أبعاد مختلفة عن الـ placeholder تجعل ارتفاع الهيدر يتجاوز المساحة مع `FitWidth`. الحل في `PdfGenerator`: ارتفاع مقيّد للهيدر (140) والفوتر (80) وحجم مقيّد للعلامة المائية (300×300) مع **`FitArea`** بدل `FitWidth` (يحافظ على النسبة ضمن المساحة لأي صورة). + تحسين `ExceptionMiddleware` لإظهار تفاصيل الخطأ (type/detail/stack) في بيئة Development فقط. تأكّد E2E: اعتماد بقالب بصور نجح + PDF 373KB.
- **إصلاح (الواجهة):** خطأ `setState() callback returned a Future` في 6 دوال `_reload` (settings: شركات/جهات/قوالب/أسعار صرف، users: مستخدمون/تفويضات) — كانت `setState(() => _f = future)` (الصيغة المختصرة تُرجع الـ Future). صُحّحت إلى كتلة `setState(() { _f = future; })`.
- **Phase 2 — الأرشيف (مكتمل):**
  - باك-إند: `ArchiveService` (CRUD + عزل شركة + حذف ناعم + حساب مالي + ترقيم `PREFIX-AR-YEAR-#####` داخل ExecutionStrategy/Transaction + بحث نصّي وبفترة) + `AttachmentService` (رفع/جلب/حذف عبر `IFileStorage`، تحقق نوع/حجم 25MB، تحقق مالك مع رؤية الموظف) + `DeleteAsync` للتخزين.
  - Controllers: `ArchiveController` (list/search/get/create/update/delete + مرفقات) + `AttachmentsController` (تنزيل/حذف) + DTOs.
  - واجهة Flutter: `archive_list_screen` (بحث + فلتر فترة) + `archive_form_screen` (إنشاء/تعديل) + `archive_detail_screen` (تفاصيل + مرفقات رفع/تنزيل/حذف عبر file_picker) + نماذج/دوال API + عنصر تنقّل «الأرشيف».
  - تحقّق: **E2E ناجح** (login مستخدم اختبار → إنشاء أرشيف DEN-AR-2026-00001 [5000$×1310=6,550,000] → بحث بكلمة+فترة → رفع مرفق 2009B → قائمة → تنزيل → حذف مرفق → حذف ناعم يختفي من البحث) + `flutter analyze` نظيف + `flutter build web`. أُضيف مستخدم اختبار `tester` للـ E2E (لأن كلمة مرور admin تغيّرت)، وأُضيف وضع `hash` للـ Spike.
- **استكمال واجهة Phase 1:**
  - **رفع صور القوالب:** إضافة حزمة `file_picker` + شاشة `TemplateEditScreen` (اسم/شفافية بمنزلق/هوامش/تفعيل + رفع ومعاينة صور هيدر/فوتر/علامة مائية عبر multipart). توسعة `TemplateModel` ودوال الـ API client (getTemplate/updateTemplate/uploadTemplateImage/getTemplateImage).
  - **التعديل بعد الاعتماد:** شاشة `OutgoingEditApprovedScreen` (تمرير RowVersion + ملاحظة) + زر في التفاصيل + عرض سجل الإصدارات (bottom sheet).
  - **إدارة المستخدمين والتفويض:** شاشة `UsersScreen` بتبويبين (مستخدمون/تفويضات) — إنشاء/تعديل/إعادة تعيين كلمة مرور حسب الهرمية، ومنح/إلغاء تفويض الاعتماد. عنصر تنقّل «المستخدمون» للمدير فأعلى. نماذج UserModel/DelegationModel/VersionModel + دوال API.
  - تحقّق: `flutter analyze` نظيف + `flutter build web` ناجح + فحص مسارات الـ API (401/415 = موجودة ومحمية). إصلاح توافق file_picker 11 (pickFiles ثابتة).
- **إصلاح (الواجهة):** استبدال `showDialog` في شاشة الإعدادات بشاشة كاملة (`_PromptPage`) — تفادي خلل محرّك Flutter Web `disposed EngineFlutterView` الذي يحدث مع الحقول النصّية داخل الحوارات. + ضبط المنفذ على 5080 في launchSettings + إسكات تحذير EF (User↔UserCompany) عبر ConfigureWarnings.
- **واجهة Flutter (العميل):** إنشاء تطبيق `app/` (Flutter + Riverpod + Dio) — عربي RTL: تسجيل دخول، تغيير كلمة مرور إجباري، اختيار شركة (سوبر أدمن)، لوحة تحكم، الصادر (قائمة/بحث/إنشاء/تفاصيل/اعتماد/تنزيل PDF/حذف)، الإعدادات (شركات/جهات/قوالب/أسعار صرف). منزّل ملفات عبر المنصّات. تحقّق: `flutter analyze` نظيف + `flutter build web` ناجح + `flutter test` ناجح. (Windows .exe يتطلب VS C++ workload.)
- **التوثيق:** إنشاء بنية `.claude/` كاملة — `CLAUDE.md` (جذر + .claude)، `rules/` (5 ملفات)، `docs/` (architecture, data-model, api-reference, decisions, roadmap, progress-log)، `skills/` (run-backend, add-migration, verify-backend)، `settings.json`، `.cache/`. تحديث `.gitignore`.
- **Phase 1 (مكتمل):** بناء الباك-إند الكامل:
  - مشاريع Domain/Infrastructure/Api + مراجع + حزم (EF 9.0.17، JwtBearer 9.0.17، BCrypt، Swashbuckle 7.2.0).
  - 16 كياناً + enums + منطق المجال (FinancialCalculator، RoleHierarchy، استثناءات).
  - `AppDbContext` بعزل صفّي + حذف ناعم + فهارس ترقيم فريدة + Counter مركّب.
  - الخدمات: PasswordHasher (BCrypt)، JwtTokenService، AuthService، NumberingService (UPDLOCK)، AuditService، OutgoingService، UserService، DelegationService، BookRenderer.
  - 11 Controller + DTOs + ExceptionMiddleware + HttpCurrentUser + JWT + Swagger + Seed.
  - Migration `InitialCreate` مطبّق على LocalDB.
  - إصلاح: تغليف معاملة الاعتماد بـ ExecutionStrategy (تعارض retry).
  - **13 اختبار E2E ناجح** (دخول→شركة→قالب→جهة→مسودّة→اعتماد→PDF→تعديل بعد اعتماد→إصدارات→تحقق QR→كشف تزوير→تدقيق).
- **الخطة:** تحديث `خطة-العمل.md` إلى الإصدار 2.2 (QuestPDF، Blob، تعدد شركات مختلط، ECDSA، Key Vault، اختبارات، Bootstrap، خطوط OFL…).
- **Phase 0 (مكتمل):** إثبات تقني — PDF عربي + QR موقّع + Word + تخزين. (مشروع `Dms.Spike`، مخرجات في `backend/output/`).

## الخطوة التالية
- بدء واجهة **Flutter Desktop** (انظر roadmap).
