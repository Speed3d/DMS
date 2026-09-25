---
name: verify-backend
description: تشغيل اختبار التدفق الشامل (E2E) لباك-إند DMS عبر الـ API الحيّ للتأكد من سلامة دورات الصادر والوارد والنسخ/الاستعادة. استخدمها بعد تغييرات مهمة في الباك-إند أو للتحقق من أن النظام يعمل end-to-end.
---

# اختبار E2E لباك-إند DMS

**ثمانية عشر سكربتاً في `backend/e2e/`** (ومعها `bootstrap-e2e` أوّلاً) — آخرُ تشغيلٍ كامل **2026-09-25 على قاعدةٍ جديدة (`DmsE2E_Batch7`)، صفر فشل في كلٍّ — المجموع 944** (+1 للتهيئة).
النجاح في كلٍّ = `فشل: 0` ورمز خروج 0.

## 🔴 القواعد الثلاث قبل أيّ تشغيل

1. **لا على `DmsDb` أبداً.** `dotnet run` **يطبّق المهاجرات على أيّ قاعدةٍ يقلع عليها بلا سؤال**،
   والسكربتات تُنشئ وتحذف (وسكربت النسخ **يستعيد القاعدة كلَّها**). وكلمة مرور `admin` في
   `DmsDb` غُيّرت. ⇒ **الخادم يُقلع على قاعدةٍ جديدة** تُبذر فيها `admin` / `Admin@12345`:

   ```bash
   cd backend && ConnectionStrings__Default='Server=.;Database=DmsE2E_New;Integrated Security=true;MultipleActiveResultSets=true;TrustServerCertificate=True' ASPNETCORE_URLS='http://localhost:5091' ASPNETCORE_ENVIRONMENT=Development SystemControl__StateFile="$TEMP/dms-e2e-state.json" dotnet run --project Dms.Api --no-launch-profile
   ```
   ⚠️ **`--no-launch-profile` إلزاميّ** — وإلا تجاهل `launchSettings.json` قيمةَ `ASPNETCORE_URLS` وربط 5080.
   وانتظر حتى يردّ `GET http://localhost:5091/api/system/status` قبل أوّل سكربت.
   ⚠️ **وإن شُغّل الخادم من مجلدٍ لا تكتب فيه خدمة SQL** (مجلد مؤقت) فأضِف `Backup__Dir` إلى مجلدٍ تصله —
   وإلا فشلت النسخة قبل حذف الشركة **فأُلغي الحذف** (الحارس يعمل، والسكربت يسقط). **وخادم المالك على 5080
   يقفل `Dms.Api\bin`**: ابنِ للاختبار إلى مجلدٍ آخر (`dotnet build Dms.Api -o <مجلد>`) وشغّل `dotnet Dms.Api.dll` منه.

2. **الترتيب إلزاميّ على القاعدة الجديدة** — السكربتات تفترض أن **أوّل شركتين أبجدياً** شركتاها:

   `bootstrap` **أوّلاً** (ADR-052) ← `review-fixes` (يُنشئ الشركتين) ← `isolation` ← `multi-company` ←
   `departments` ← `incoming` ← `hr` ← `profile` ← `reports` ← `tasks` ← `case-files` ← `verify` ←
   `gaps` ← `version` ← `lockdown` ← `drafts` ← `password-change` ← `backup-upload` ← `backup-restore` **أخيراً**

   🔑 **على قاعدةٍ مستعملة سقطت سبعةُ سكربتات بلا عيبٍ في الكود** (2026-09-23) — التقطت شركاتِ
   اختبارٍ أخرى فلم تجد مستخدميها، ثم رُفض إنشاؤهم لأن أسماءهم موجودة (409). **الحَكَم قاعدةٌ جديدة.**

3. **ترميز UTF-8 with BOM** لملفات PowerShell العربية وإلا فشل التحليل في PS 5.1. ولقراءة المخرجات
   بلا تشويه: `[Console]::OutputEncoding=[Text.Encoding]::UTF8` داخل العملية نفسها.

## الأوامر — بالترتيب (المنفذ 5091 والقاعدة الجديدة)

⚠️ **المعاملات تختلف بين السكربتات** — انسخها كما هي:

```powershell
$B='http://localhost:5091/api'; $P='Admin@12345'
$DB='Server=.;Database=DmsE2E_New;Integrated Security=true;TrustServerCertificate=True'
$STATE="$env:TEMP\dms-e2e-state.json"   # نفسُه في SystemControl__StateFile عند تشغيل الخادم
.\e2e\bootstrap-e2e.ps1      -AdminPwd $P -Base $B             # 🔴 أوّلاً دائماً (G19): يفعّل المدير المبذور بكلمته نفسها
.\e2e\review-fixes-e2e.ps1   -AdminPwd $P -Base $B -Db $DB     # -Db إلزاميّ: يعدّ الصفوف اليتيمة من القاعدة نفسها
.\e2e\isolation-e2e.ps1      -AdminPwd $P -Base $B
.\e2e\multi-company-e2e.ps1  -AdminPwd $P -Base $B
.\e2e\departments-e2e.ps1    -AdminPwd $P -Base $B
.\e2e\incoming-e2e.ps1       -AdminPwd $P -BaseUrl $B          # + -EmployeeUser emp_leg -EmployeePwd Emp@12345new لجزء الموظف
.\e2e\hr-e2e.ps1             -AdminPwd $P -Base $B
.\e2e\profile-e2e.ps1        -AdminPwd $P -Base $B
.\e2e\reports-e2e.ps1        -AdminPwd $P -Base $B             # + -EmployeeUser emp_leg -EmployeePwd Emp@12345new لجزء الموظف
.\e2e\tasks-e2e.ps1          -AdminPwd $P -Base $B
.\e2e\case-files-e2e.ps1     -AdminPwd $P -Base $B
.\e2e\verify-e2e.ps1         -AdminPwd $P -Base $B -Root 'http://localhost:5091'
.\e2e\gaps-e2e.ps1           -AdminPwd $P -Base $B -Db $DB     # G20/G22 (ADR-053): يكتب علَماً «قديماً» في القاعدة مباشرةً
.\e2e\version-e2e.ps1        -AdminPwd $P -Base $B -Db $DB     # ADR-054: الإصدار = ملف VERSION · لا يُكشف للمجهول · سطر تدقيقٍ واحد
.\e2e\lockdown-e2e.ps1       -AdminPwd $P -Base $B -Db $DB -StateFile $STATE -ApiDll (Resolve-Path Dms.Api\bin\Debug\net9.0\Dms.Api.dll)
.\e2e\drafts-e2e.ps1         -AdminPwd $P -Base $B -Db $DB     # يعدّ الصفوف من القاعدة (منع التكرار)
.\e2e\password-change-e2e.ps1 -AdminPwd $P -Base $B -Db $DB    # G19: الكلمة المؤقتة يفرضها الخادم
.\e2e\backup-upload-e2e.ps1 -AdminPwd $P -Base $B             # ADR-055: رفعُ نسخةٍ من الجهاز ثم استعادتها — تدميريّ
.\e2e\backup-restore-e2e.ps1 -AdminPwd $P -BaseUrl $B          # تدميري: يستعيد القاعدة — أخيراً دائماً
```

🔐 **G19 (ADR-052): المدير المبذور وكلُّ مستخدمٍ يُنشأ يحملان «يجب تغيير كلمة المرور»، والخادم يحجب به
كلَّ شيء.** ⇒ `bootstrap-e2e` أوّلاً، والسكربتات التي تُنشئ مستخدمين تفعّلهم بـ`_activate.ps1`
(`Enable-TempPassword` — دورتان تُبقيان الكلمة ثابتة). **سكربتٌ جديد يُنشئ مستخدماً يفعل الشيء نفسه.**

⚠️ **ولا تُشغّل الخادم من مجلدٍ لا تكتب فيه خدمة SQL** (كالمجلد المؤقت): النسخة تفشل بـ«Access is
denied» **فيُلغى حذف الشركة والاستعادة** (سلوكٌ صحيح). عندها اضبط `Backup__Dir` إلى
`D:\DMS\backend\Dms.Api\App_Data\Backups`.

🔴 **`lockdown-e2e` يوقف النظام فعلاً** — فالخادم يُشغَّل **بملفّ حالةٍ منفصل**:
`SystemControl__StateFile=<مسارٌ مؤقت>` (وهو `$STATE` أعلاه). **بدونه يُكتب الملفّ بجوار مجلد التخزين
المشترك فيُوقَف خادمُ التطوير على `DmsDb` معه.** والسكربت يُطفئ الإيقاف في آخره (`finally`).
و`-StateFile`/`-ApiDll` اختياريّان: بدونهما يُتخطّى اختبار أمر الطوارئ على السيرفر.

## ما يغطّيه كلٌّ — وآخر تشغيل

| السكربت | التحقّقات | آخر تشغيل | يغطّي |
|---|---|---|---|
| `bootstrap` | **1** | 2026-09-25 | 🔴 **أوّلاً دائماً (ADR-052)**: يُخرج المدير المبذور من «يجب التغيير» بكلمته نفسها |
| `review-fixes` | **46** | 2026-09-25 | **ADR-048**: تعديل المدير/الرئيس لا يُسقط إسناداً ولا يصفّر أقساماً · المستمسكات والإيصالات بعلَم الكتابة · حذف الشركة بلا يتيمٍ في 24 جدولاً (يقرأ القاعدة) — وحذفُها **عمليةٌ خلفية** (ADR-049) · **G23 (ADR-053): رقمُ «سيُمحى» في البيان = صفوف القاعدة** |
| `isolation` | **59** | 2026-09-25 | العزل **بالمعرّف** عبر الوحدات · **12 اعتماداً متزامناً** بأرقامٍ متمايزة · عزل الإشعارات (ADR-046) · **التعطيل ثم الحذف** (ADR-047) خلفياً |
| `multi-company` | **26** | 2026-09-25 | موظفٌ في شركتين بصلاحياتٍ وأقسامٍ مختلفة (ADR-017) — نفس التوكن يُحجب في شركةٍ ويمرّ في أخرى |
| `departments` | **22** | 2026-09-25 | الإحالة **متعددة وتراكمية** · مَن أحال يبقى يرى · يُنشئ `emp_fin`/`emp_leg` |
| `incoming` | **66** (77 مع `-EmployeeUser`) | 2026-09-25 (66) · 2026-08-11 (77) | دورة الوارد كاملة + رؤية الصادر بالقسم (ADR-030) |
| `hr` | **180** | 2026-09-25 | الرواتب والإجازات والمستمسكات وبوّابة الحسم وتعديل المُسدَّد |
| `profile` | **58** | 2026-09-25 | البروفايل (ADR-033/035): يرى راتبه وحده · صورته · إجازته الذاتية |
| `reports` | **45** (55 مع `-EmployeeUser`) | 2026-09-25 (45) · 2026-08-11 (55) | النشاط والتفصيليان بحدٍّ مزدوج — 🟢 **يقرأ ولا يكتب** |
| `tasks` | **164** | 2026-09-25 | وحدة المهام كاملةً + الخدمة الخلفية (لا تُعيد إشعاراً ولا تكاثر) |
| `case-files` | **32** | 2026-09-25 | المعاملات والربط كثيرٌ إلى كثير (ADR-045) |
| `verify` | **22** | 2026-09-25 | صفحة التحقق العامّة `/v/{token}` (ADR-043/044) |
| `gaps` | **36** | 2026-09-25 | **ADR-053**: الردّ المرتبط لمن لا يملك قسمه **بالعدد** (ولا يتسرّب الرقم من الردّ ولا سجلّ الحركة ولا الإشعار) · القارئ لا يعتمد ولا يدير الوارد **ولو حمل العلَم في القاعدة** · التفويض إلى قارئ 400 |
| `version` | **12** | 2026-09-25 | **ADR-054**: إصدار الخادم = ملف `VERSION` · **لا يُكشف للمجهول** (`/status` بلا `version` · `/about` 401) · `commit` ولحظة البناء · آخر مهاجرة في الكود = المطبَّق · **سطر تدقيقٍ واحد** للإقلاع بالإصدار |
| `lockdown` | **59** | 2026-09-25 | **ADR-050**: السوبر أدمن وحده يتصفّح · الدخول 503 **بلا عدّ** والخاطئ يُحسب · التجديد بلا تدوير · `/v/*` يعمل · الشريط للمصادَق · **الاستعادة لا تُنهي الإيقاف** · أمر الطوارئ على السيرفر يسري والخادم يعمل (يقرأ القاعدة) |
| `drafts` | **24** | 2026-09-25 | **ADR-051**: `Idempotency-Key` — المفتاح نفسه يعيد الكيان (جهة · صادر · وارد · مهمة) وصفٌّ واحد في القاعدة · بلا مفتاح كما كان · لكل مستخدم · لا يخدم نوعين · الفشل لا يحجز · **خمسة طلباتٍ متزامنة فعلاً ⇒ كتابٌ واحد** |
| `password-change` | **22** | 2026-09-25 | **G19 (ADR-052)**: رمزُ الكلمة المؤقتة 403 عدا التغيير · الجديدة تختلف · التغيير يعيد رمزاً ويُبطل تجديد الأجهزة الأخرى · إعادةُ تعيين المدير تُنهي الجلسات |
| `backup-upload` | **30** | 2026-09-25 | **ADR-055**: نسخةٌ تُنزَّل ثم **تُرفع بقطع** (الترتيب · الإعادة · الإلغاء · معرّفٌ سداسيّ) · الرفض (بلا `database.bak` · إصدارٌ أحدث · مهاجرةٌ من المستقبل) · رسالة المرآة · **والاستعادة تُعيد القاعدة فعلاً** — تدميريّ |
| `backup-restore` | **41** | 2026-09-25 | نسخ ← حذف ← **استعادة** ← الكتاب يعود · المرآة · **البدء يردّ 202 فوراً** · **التنزيل تدفّقٌ كامل بالبايت** · عمليةٌ مجهولة 404 (ADR-049) |

**المجموع (تشغيلٌ واحد 2026-09-25 على `DmsE2E_Batch7`): 944** = 46 + 59 + 26 + 22 + 66 + 180 + 58 + 45 + 164 + 32 + 22 + 36 + 12 + 59 + 24 + 22 + 30 + 41 (+1 للتهيئة). ومع `-EmployeeUser` في `incoming` و`reports`: **965**. **والرقم نفسه في `status-report.md` §1 و§7 — يُعاد جمعُه لا يُورَّث.**

🔴 **ويُطلب من ويندوز منعُ السكون ما دام التشغيل قائماً** (`SetThreadExecutionState(0x80000001)` في أوّل السكربت الجامع) — نام الجهاز مرّةً أثناء استعادة `lockdown` فبقيت القاعدة المؤقتة `RESTORING` وتوالت إخفاقاتٌ بلا عيبٍ في الكود (2026-09-24).

## ⚙️ العمليات الخلفية (ADR-049) — ما تغيّر في العقد

`POST /backup/run` · `/backup/mirror` · `/backup/mirror/restore` · `/backup/{id}/restore` ·
`DELETE /companies/{id}` **تردّ 202** بجسم `JobResponse` (`id` · `state` · `stage` · `percent` · `message` · `result`)،
ثم تُسأل `GET /api/system/jobs/{id}` حتى `state != Running`. **وأثناء الاستعادة تردّ 503** — فيُسأل
`/api/system/status` حتى `maintenance=false` ثم تُستأنف. والفحوص الرخيصة (تأكيد · مسار · موانع) تعود 400/404/409 **فوراً**.
الدالّة الجاهزة `WaitJob` في `backup-restore-e2e.ps1` و`isolation-e2e.ps1` و`review-fixes-e2e.ps1`.

## ملاحظات

- **الـAPI لا يعمل من داخل worktree**: `appsettings.Development.json` مستبعَد من git. شغّل من `D:\DMS`.
- **إيقاف الخادم بعد الانتهاء**:
  `Get-NetTCPConnection -LocalPort 5091 -State Listen | % { Stop-Process -Id $_.OwningProcess -Force }`
- قواعد التجريب القديمة (`DmsReviewScratch` · `DmsJobsScratch*` · `DmsTaskScratch` · `DmsCaseScratch` ·
  `DmsCompScratch` …) بيانات اختبار فقط — تُحذف متى شئت، **ولا يُعاد استعمالها حكَماً**.
