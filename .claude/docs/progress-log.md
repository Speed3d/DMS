# سجل التقدّم (Progress Log)

> يُحدَّث بعد كل خطوة مهمة (الأحدث أعلى). التواريخ ميلادية.

## 2026-07-22
- **وحدة الوارد — المرحلة ب (إكمال الوظائف الغائبة):**
  - **ب3 — الحقول الفارغة:** أُضيفت `GetDetailAsync` و`MovementLogData` إلى `IncomingService` فصارت الأسماء تُجهَّز في الخدمة (لا في الـ Controller الذي بقي محوّل DTO فقط، التزاماً بقاعدة المعمارية). الآن تُعبَّأ: `replyOutgoingNumber` (عبر `Include`) و`documentTypeName` و`receivedByUserName` و`performedByUserName` (بجلب دفعة واحدة تفادياً لـ N+1).
    - **اكتشاف:** الأسماء كانت تعود «—» لأن الـ Global Query Filter على `User` يستبعد السوبر أدمن (`CompanyId = NULL`) وقت وجود شركة فعّالة. حُلّ بـ `IgnoreQueryFilters()` **لجلب الاسم فقط** — تجاوز مقصود وموثّق في الكود (لا يُكشف سوى اسم مستخدم نفّذ إجراءً على كتاب يراه الطالب أصلاً).
  - **ب1 — المرفقات:** رفع وحذف من شاشة التفاصيل (كانت الدوال موجودة في `api_client` بلا أي مستدعٍ) + أيقونة حسب نوع الملف + إخفاء أزرار التعديل عن القارئ.
  - **ب2 — واجهة الربط بالصادر:** شاشة اختيار كاملة `_OutgoingPickerScreen` (لا حوار — تفادياً لخلل `disposed EngineFlutterView` مع حقول البحث على الويب) تعرض المعتمد فقط مع بحث، + زر فك الارتباط، وكلاهما للمدير فأعلى (مرآة لقاعدة الباك-إند).
  - **ب4 — الربط العكسي في الصادر:** حقلا `ReplyToIncomingId/ReplyToIncomingNumber` في `OutgoingDetail` (باك-إند + Flutter) + قسم في شاشة تفاصيل الصادر مع زر «فتح الكتاب الوارد».
  - **الاختبار:** سكربت E2E دائم في [`backend/e2e/incoming-e2e.ps1`](../../backend/e2e/incoming-e2e.ps1) — **61 تحقّقاً، صفر فشل**، قابل لإعادة التشغيل (يختار صادراً غير مرتبط). مهارة `verify-backend` حُدّثت للإشارة إليه.
  - **مؤجَّل:** ب5 (عارض PDF مدمج) — تحسين لا نقص وظيفي.
- **وحدة الوارد — المرحلة ج (تصلّب وأمان):**
  - **ج1:** أُزيلت `[AllowAnonymous]` ومعامل `token` (كان يُستقبل ويُهمَل) من تنزيل مرفقات الوارد. تحقّق حيّ: بلا توكن **401**، وبتوكن صالح **200**.
  - **ج2:** ضُبط `MaxRequestBodySize` و`MultipartBodyLengthLimit` على 55 ميغابايت في `Program.cs`. قبلها كان Kestrel يقطع عند ~28 ميغابايت بـ 413 غامض فيتعذّر تحقيق حد الـ 50 المعتمد. الهامش مقصود ليأتي الرفض من `AttachmentService` برسالة عربية. تحقّق حيّ: **35 م.ب ينجح** (كان يفشل)، و**51 م.ب يُرفض بـ 400** ورسالة «حجم الملف يتجاوز الحد المسموح (50 ميغابايت)».
  - **ج3 (قرار المالك — نُفِّذ):** سياسة التعديل صارت كما في الخطة — المؤرشف لا يُعدَّل مطلقاً · المدير فأعلى يصحّح في بقية الحالات (الأخطاء تُكتشف غالباً بعد الإحالة) · الموظف يعدّل كتابه ما دام (جديد) فقط. الواجهة تعكسها بتعطيل الزر مع سبب.
  - **تحقّق انحدار:** **65/65** على E2E بعد كل التغييرات.
- **وحدة الوارد — المرحلة د (التوثيق):** استُكمل [`data-model.md`](data-model.md) (كيانا `IncomingBook` و`MovementLog` + تحديث `Attachment` والحذف الناعم) و[`api-reference.md`](api-reference.md) (قسم `/api/incoming` كاملاً + الربط العكسي + الأقسام السبعة) و[`roadmap.md`](roadmap.md) (الوحدة مكتملة مع قائمة المؤجَّلات). بهذا صار التوثيق مطابقاً للواقع.

## 2026-07-21
- **مراجعة وحدة الوارد مقابل خطتها + المرحلة أ (الإصلاحات المانعة):** المرجع [`خطط/الخطة_التنفيذية_للوراد0.md`](../../خطط/الخطة_التنفيذية_للوراد0.md).
  - **التشخيص:** الوحدة كانت مبنية بالكامل (Domain/DB/Service/Controller/3 شاشات) وتبني نظيفة، لكن **لم تعمل قط** (`SELECT COUNT(*) FROM IncomingBooks = 0`) بسبب أربعة عيوب مانعة.
  - **إصلاح C1 (مانع):** تعارض قيم «طريقة الاستلام» — الواجهة كانت ترسل `Hand/Postal/WhatsApp` بينما enum الباك-إند `Manual/Mail/Email` ⇒ كل تسجيل وارد جديد يفشل بـ 400، وشاشة التعديل تتحطّم. وُحِّدت عبر ثوابت مشتركة في `models.dart` (`kReceiveMethods`/`kIncomingStatuses`/`kIncomingTransitions`) تُبنى منها كل القوائم المنسدلة.
  - **إصلاح C2 (سلامة بيانات):** `ChangeStatusAsync` كان يقبل **أي** انتقال (مؤرشف ← جديد مثلاً). أُضيفت مصفوفة الانتقالات + صلاحيات الدور (الأرشفة للمدير فأعلى؛ الموظف/القارئ: جديد ← قيد المراجعة فقط) + إلزام الملاحظة عند «تم الرد» يدوياً بلا ربط بصادر.
  - **إصلاح C3:** حراسة الحالة في `ForwardAsync` (كان يعيد المؤرشف لقيد المراجعة) و`LinkToOutgoingAsync` (منع الربط المزدوج من الطرفين) و`UnlinkFromOutgoingAsync` (كان يصمت بلا ربط، ويُنزل المغلق لقيد المراجعة).
  - **إصلاح C4:** حالة «مغلق» كانت مفقودة من كل الواجهة (الفلتر/حوار الحالة/`StatusPill`) ⇒ مسار «جديد ← مغلق ← مؤرشف» كان غير قابل للتنفيذ. أُضيفت، وحوار تغيير الحالة صار يعرض **الانتقالات المسموحة فقط** من الحالة الحالية، والأزرار غير المتاحة تُعطَّل مع tooltip يشرح السبب.
  - **معماري:** مصفوفة الانتقالات نُقلت إلى `Dms.Domain/IncomingWorkflow.cs` (منطق مجال نقي على نمط `RoleHierarchy`) — انظر ADR-013.
  - **إصلاح إضافي (اكتشفه الاختبار الحي — فقدان بيانات):** حركة «تسجيل الكتاب» كانت **تختفي من سجل الحركة نهائياً**. السبب: علاقة `MovementLog → IncomingBook` لم تكن مضبوطة في `AppDbContext`، فولّد EF عموداً شبحاً `IncomingBookIncomingId` وملأه عند الربط بخاصية التنقّل تاركاً `IncomingId = 0`، بينما الاستعلام يبحث بـ `IncomingId`. ضُبطت العلاقة صراحةً + migration `FixMovementLogRelation` يحذف العمود الشبح **بعد ترحيل البيانات** (استُعيدت 6 حركات مفقودة) ويضيف FK حقيقياً على `IncomingId`.
  - **تحقّق:** البناء 0/0 · `flutter analyze` نظيف · `flutter build web` ناجح · **55 اختبار وحدة** (+26 لمصفوفة الانتقالات) · **E2E حيّ على API فعلي: 44/44 + 14/14 لاختبار الربط** — يغطي: توليد الرقم `DEN-IN-2026-#####` · الانتقالات المسموحة والمرفوضة · الملاحظة الإلزامية · الإحالة · الربط/فك الربط مع الصادر المعتمد · منع الربط المزدوج · صلاحيات الموظف (403 للإغلاق/الرد/الربط/سجل الحركة، 404 لكتاب غيره) · البحث بكل المعاملات · المرفقات.
  - **مؤكَّد بالاختبار الحي (فجوات المرحلة ب):** `replyOutgoingNumber` و`receivedByUserName` و`documentTypeName` و`performedByUserName` تعود **فارغة** في أي طلب مستقل (تظهر فقط ضمن استجابة الربط بسبب change-tracking) — لأن `GetAsync` بلا `Include(ReplyOutgoing)` والقيم مثبّتة فارغة في الـ Controller.
  - **المتبقّي (المراحل ب/ج/د):** واجهة الربط بالصادر · رفع/حذف المرفقات · عارض PDF · الربط العكسي في الصادر · تعبئة `ReplyOutgoingNumber`/أسماء المستخدمين في سجل الحركة · حذف `[AllowAnonymous]` من تنزيل المرفقات · رفع حد جسم الطلب لـ 50MB · إزالة العمود الشبح `IncomingBookIncomingId` · استكمال `data-model`/`api-reference` واختبارات E2E.

## 2026-07-19
- **إصلاحات ملاحظات المالك (8 قضايا) — الخطة والتنفيذ:** المرجع [`docs/owner-feedback-fixes-plan.md`](owner-feedback-fixes-plan.md).
  - **الدفعة 1:** معاينة PDF داخلية (تفاصيل + تعديل مسودة) بدل التنزيل · إرسال `companyIds` عند تعديل المستخدم (كان مفقوداً) · نقطة/زر مسح صورة القالب · إخفاء زر «اعتماد» حسب `canApprove` الفعّال (حقل جديد في `OutgoingDetail`) · إبطال مزوّدات الصادر عند تبديل الشركة (يمنع إشعارات الشركة السابقة).
  - **الدفعة 2:** قراءة `font-size` (px/em) في `HtmlToQuestPdf` (اللون/المحاذاة كانا يعملان) · **تخزين Quill Delta** (`OutgoingBook.BodyJson` + migration `AddOutgoingBodyJson`) لاستعادة التنسيق الكامل عند تعديل المسودة/الإصدار (كان يُجرّد HTML لنص خام) · لوحة التحكم تحوّلت لمزوّد يُبطَّل بعد أي عملية + **إجمالي المعتمد فقط**.
  - **معماري:** مزوّدات الصادر المشتركة نُقلت لـ `lib/core/outgoing_providers.dart` (`outgoingListProvider`/`pendingDraftsProvider`/`outgoingCountProvider` + `invalidateOutgoing`) لتفادي دورات الاستيراد وتوحيد التحديث.
  - **نوع الخط (اكتمل):** وفّر المالك ملفات .ttf. ضُمّنت **Cairo/Arial/Times New Roman** (Regular+Bold) في `Dms.Documents` (csproj + `ArabicFonts`), وأُضيفت للقائمة/الخريطة في `HtmlToQuestPdf`, وقائمة الخطوط في محرّر Quill (`fontFamily.items`). محوّل vsc يُخرِج `font-family:<value>` تلقائياً. تحقّق: معاينة/اعتماد بكل الخطوط (PDF 261KB بلا تعطّل).
  - **تحقّق:** البناء 0/0 · `flutter analyze` نظيف · E2E خلفي (تعدد شركات، `canApprove`، مسح صورة، تخزين Delta، حجم/نوع الخط في PDF).
  - **الحالة:** **8/8 ملاحظات مُنجَزة.** لم يُجرَ commit بعد. (تحسين اختياري لاحق: تضمين الخطوط في `pubspec` لعرضها داخل المحرّر نفسه.)

## 2026-07-14
- **تدقيق شامل + المرحلة (أ) من الإصلاحات الأمنية:**
  - إنتاج تقرير تدقيق ومرجع كامل: [`docs/audit-and-fix-plan-2026-07-13.md`](audit-and-fix-plan-2026-07-13.md) (15 خطأ/ثغرة B1–B15 + خطة مراحل + قرارات المالك D1–D5 + ميزة الأقسام D4).
  - **سياق:** تعديلات المالك السابقة أدخلت «تعدد الشركات للمستخدم» (`UserCompany`/`AssignedCompanies`، claim `cids`) وخالفت ADR-006/008 وقواعد الأمان.
  - **نُفِّذت المرحلة (أ):**
    - **B3:** `reset-db` مقصور على بيئة التطوير (`SystemController` + `IWebHostEnvironment`).
    - **B1+B2+B6:** إعادة بناء حذف الشركة — تحقّق مسبق (يُمنع عند وجود كتاب معتمد أو أرشيف → 409)، `ExecutionStrategy`، تنظيف كل ملفات التخزين. التعطيل عبر مفتاح «نشط».
    - **B4:** استعادة عزل `User` عبر Global Query Filter يشمل `AssignedCompanies` + إزالة الفلاتر اليدوية «fail-open».
    - **B5-المصغّر:** إسناد الشركات حصراً للسوبر أدمن/رئيس الشركة، بلا مسح عند `CompanyIds=null`، + حارس «شركة واحدة على الأقل».
    - إصلاح تحذير سابق في `BackupService.cs` (متغيّر غير مستخدم) للحفاظ على بناء 0/0.
  - **تحقّق E2E على قاعدة اختبار معزولة:** 11/11 فحص ناجح (تعدد شركات + ترجمة فلتر العزل + العزل بعد التحديث + حارس الحذف 409/200 + reset-db في التطوير). البناء 0 أخطاء/0 تحذيرات.
  - **ثم نُفِّذت المرحلة (ب):**
    - **B10:** `GET /companies/{id}` يحترم `AllowedCompanyIds` (رئيس الشركة يفتح أي شركة مسموحة له لا النشطة فقط).
    - **B13:** التعديل بعد الاعتماد يحفظ الـ PDF بمفتاح جديد ثم ينظّف القديم (والجديد عند فشل التزامن) — لا تسريب.
    - **B16 (اكتُشف أثناء التحقق):** `ApproveAsync` كان يسرّب PDF يتيماً عند إعادة محاولة المعاملة (`storage.SaveAsync` داخل كتلة retry — شائع في Azure SQL). أُصلح بتنظيف نسخة المحاولة السابقة + تنظيف عند الفشل النهائي.
    - **تحقّق E2E:** رئيس شركة يفتح شركة مسموحة غير نشطة (200) ويُمنع من غير المسموحة (404)؛ اعتماد ⇒ PDF واحد؛ تعديل ⇒ PDF واحد (لا تسريب). البناء 0/0. (B5 كان قد اكتمل ضمن المرحلة أ.)
  - **ثم نُفِّذت المرحلة (ج) — تصليب الإنتاج:**
    - **B8:** CORS في الإنتاج يقتصر على `AllowedOrigins` (fail-closed، أُزيل fallback إلى AllowAnyOrigin) + مفتاح `AllowedOrigins` في `appsettings.json`.
    - **B9:** فحص أسرار عند الإقلاع في الإنتاج (SigningKey ≥ 32B + مفاتيح QR + connection string) ⇒ فشل سريع برسالة عربية.
    - **B7:** Interceptor في `api_client.dart` يجدّد التوكن تلقائياً عند 401 (تجديد مشترك + منع حلقة + `refreshAuth` يحفظ الشركة الفعّالة).
    - **تحقّق:** الإنتاج بلا أسرار يفشل فوراً؛ مع أسرار يُقلع؛ `flutter analyze` نظيف؛ عقد `/auth/refresh` مؤكّد (توكن جديد + تدوير + companyIds + إبطال القديم). البناء 0/0.
  - **ثم نُفِّذت المرحلة (د) — تنظيف وتوثيق:**
    - **B11:** حُذفت الـ migration الفارغة `AddUserCompanies` (السلسلة تنتهي بـ `AddCompanyLogoImageKey`؛ `has-pending-model-changes` = لا تغييرات).
    - **B12:** أُزيلت حيلة `-1` (علَم `bypassCompanySelection` بالواجهة + ثابت `NoCompanyId` بالباك-إند).
    - **B14:** حُذف `test_bug.dart` و`test_list.dart`.
    - **B15 + ADR-011:** تحديث `decisions.md` (ADR-011) و`data-model.md` و`api-reference.md` و`status-report.md` و`roadmap.md`.
  - **الخلاصة:** جميع بنود التدقيق **B1–B16 مُنجَزة**. البناء 0/0 و`flutter analyze` نظيف.
  - **ثم نُفِّذت ميزة صلاحيات الأقسام (D4):**
    - **الباك-إند:** `AppModule` (6 أقسام) + `User.Modules` (افتراضي All) + migration `AddUserModules` + claim `mods` + `ICurrentUser.AllowedModules/HasModule` (السوبر أدمن/الرئيس معفيان) + سِمة `[RequireModule]` على الصادر/الأرشيف/التقارير/المستخدمون/التفويضات/النسخ الاحتياطي + كتابات الشركات/القوالب (الإعدادات) + فحص القسم في `AttachmentService`. التحديد حصراً للسوبر أدمن/الرئيس (ADR-012).
    - **الواجهة:** `modules` في AuthResult/UserModel، إخفاء التنقّل حسب القسم (sidebar + home_shell بمؤشرات ثابتة)، ومربّعات اختيار الأقسام في نموذج المستخدم (للمانح).
    - **تحقّق E2E: 24/24** + **مراجعة عدائية (4 عدسات)** أُصلحت نتائجها الثلاث: (1) `_edit` بالواجهة لم يكن يرسل `modules` ← أُصلح، (2) لوحة التحكم/`topbar` تفشل لمن لا يملك «الصادر» ← حارس، (3) `AuditController` كان يسرّب بيانات كل الأقسام لمدير مقيّد ← قُصر على رئيس الشركة فأعلى (403 مُتحقَّق). البناء 0/0 + analyze نظيف.
  - **الحالة:** التدقيق (B1–B16) + ميزة الأقسام (D4) مكتملان ومُتحقَّق منهما. **غير مُودَع بعد** (بانتظار طلب المالك).

## 2026-07-01
- **UI Revamp — المرحلة الأولى (مكتمل):**
  - إنشاء خطة التحسين الشاملة بناءً على تصميم HTML/CSS المقترح وحفظها كخطة تنفيذية في مجلد المشروع `.claude/docs/ui-revamp-plan.md`.
  - تحديث `pubspec.yaml` وإضافة الحزم اللازمة: `fl_chart`, `flutter_quill`, `google_fonts`, `flutter_svg`. (مع حل تعارض إصدار `intl`).
  - إنشاء ملف `theme.dart` لتعريف الألوان الجديدة (الداكن والذهبي) و`ThemeData` المتوافق مع الوضعين الفاتح والداكن.
  - بناء المكونات المشتركة: `CustomCard` (للظلال العميقة) و `StatusPill` (علامات الحالة).
  - إعادة تصميم وتطوير `login_screen.dart` كلياً بنظام الشاشة المنقسمة (Split Screen) مع نصوص الترحيب، خلفية متدرجة، ومطابقة التصميم بنسبة 100%.
  - إعادة بناء `home_shell.dart` باستخدام `Sidebar` جانبي مخصص و `Topbar` علوي يحتوي على البحث والتبديل بين الوضع الليلي/النهاري وملف المستخدم.

- **UI Revamp — المرحلة الثانية (مكتمل):**
  - إضافة وتكوين حزمة `fl_chart` لإنشاء رسوم بيانية (LineChart) توضح نشاطات الصادر (مسودات ومعتمدة).
  - تطوير بطاقات الإحصائيات (Stats Cards) باستخدام تصميم الزجاج (Glassmorphism) مع الإضاءة بناءً على لون الحالة.
  - تصميم قسم "آخر النشاطات" باستخدام `StatusPill` وتنسيق جميل يتيح الوصول السريع.
  - إجراء فحص شامل باستخدام `flutter analyze` وحل جميع الـ Errors والـ Warnings (أكثر من 45 خطأ) لتصبح النتيجة `No issues found!`.
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
