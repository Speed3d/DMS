# سجل القرارات التقنية (ADR)

قرارات مهمة مع مبرراتها. الأحدث أعلى.

## ADR-010 — النسخ الاحتياطي: BACKUP DATABASE + ZIP محلي
**القرار:** النسخة = `BACKUP DATABASE` (.bak) عبر اتصال `SqlConnection` مستقل (خارج EF/استراتيجية إعادة المحاولة) + ضغط ملفات التخزين في أرشيف ZIP واحد بمجلد `App_Data/Backups`. جدولة عبر `BackupScheduler` (BackgroundService).
**لماذا:** موثوق ومحلي بلا اعتماد خارجي؛ `BACKUP` لا يعمل داخل معاملة فاستُخدم اتصال مستقل. رفع OneDrive عبر Microsoft Graph مؤجَّل (يكفي التنزيل اليدوي حالياً)؛ في Azure تُستخدم النسخ التلقائية + bacpac.

## ADR-009 — تقييد إنشاء الشركات بـ SuperAdmin
**القرار:** إنشاء الشركات ورموز الترقيم = SuperAdmin فقط (التعديل لرئيس الشركة فأعلى).
**لماذا:** منح كل مدير صلاحية إنشاء شركات/ترقيم (كما في المصفوفة الأصلية) خطر أمني. تشديد مقصود.

## ADR-008 — تغليف المعاملات بـ ExecutionStrategy
**القرار:** كل `BeginTransaction` يُغلّف بـ `CreateExecutionStrategy().ExecuteAsync`.
**لماذا:** `EnableRetryOnFailure` (لمرونة Azure SQL) يمنع المعاملات اليدوية بدون استراتيجية. اكتُشف أثناء اختبار الاعتماد.

## ADR-007 — تثبيت net9.0 + EF/ASP.NET 9.0.x
**القرار:** كل المشاريع net9.0 (global.json يثبّت SDK 9)، حزم EF/ASP.NET/JwtBearer مثبّتة على 9.0.17، Swashbuckle 7.2.0.
**لماذا:** EF/ASP.NET 10 و Swashbuckle 10 (Microsoft.OpenApi 2.x) تكسر التوافق مع net9. اخترنا الاستقرار.

## ADR-006 — تعدد الشركات المختلط + عزل صفّي
**القرار:** `CompanyId` على المستخدم + Global Query Filter. SuperAdmin يرى الكل (ترويسة X-Company-Id)، الباقي مقيّد.
**لماذا:** يطابق قرار الخطة 2.2؛ يفرض العزل في الباك-إند لا الواجهة.

## ADR-005 — توقيع QR بـ ECDSA P-256 + Key Vault
**القرار:** ECDSA P-256 بدل RSA؛ المفاتيح في appsettings تطويراً و Key Vault إنتاجاً.
**لماذا:** توقيع أصغر يناسب سعة الـ QR؛ غير قابل للتزوير. أُثبت في Phase 0.

## ADR-004 — Azure Blob Storage حصرياً (تجريد IFileStorage)
**القرار:** كل الملفات على Blob؛ DB يحفظ المفتاح فقط. تطويراً: `LocalFileStorage`.
**لماذا:** قرص App Service غير موثوق للتوسّع. التجريد يسمح بالتبديل بلا تغيير كود.

## ADR-003 — تصدير Word بـ OpenXML
**القرار:** DocumentFormat.OpenXml بدل LibreOffice headless.
**لماذا:** بلا أدوات خارجية/مشاكل استضافة. أُثبت في Phase 0.

## ADR-002 — توليد PDF بـ QuestPDF
**القرار:** QuestPDF (أصلي، RTL، HarfBuzz) بدل PuppeteerSharp/Chromium.
**لماذا:** Chromium يفشل على Azure App Service (Windows)؛ QuestPDF مستقل عن الاستضافة. أُثبت في Phase 0 (عربية سليمة).

## ADR-001 — خط Amiri (OFL)
**القرار:** Amiri بدل Sakkal Majalla.
**لماذا:** مفتوح الترخيص، قابل للتضمين في PDF على السيرفر بلا قيود.
