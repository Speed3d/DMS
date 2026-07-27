# المعمارية (Architecture)

## نظرة عامة
عميل رفيع (Flutter) ← HTTPS (REST + JWT) ← **ASP.NET Core API مركزي** ← SQL Server + تخزين على القرص. كل منطق العمل في الباك-إند.

```
[Flutter]──HTTPS/JWT──> [Cloudflare Tunnel] ──> [Dms.Api] ──> [Dms.Infrastructure] ──> SQL Server
                         (ADR-016، صفر منافذ)      │                  │
                                                   │                  └─> IFileStorage (قرص السيرفر)
                                                   └─> [Dms.Documents] (QuestPDF / OpenXML / QR ECDSA)
```

## الطبقات
| المشروع | المسؤولية | يعتمد على |
|---|---|---|
| `Dms.Domain` | كيانات، enums، منطق نقي (`FinancialCalculator`، `RoleHierarchy`، `IncomingWorkflow`، `BackupRetention`)، استثناءات المجال | — |
| `Dms.Documents` | توليد PDF (QuestPDF) + Word (OpenXML) + توقيع/تحقق QR (ECDSA P-256) + `IFileStorage` + صور placeholder | — |
| `Dms.Infrastructure` | `AppDbContext`، الخدمات، التهيئة، مصنع التصميم | Domain, Documents |
| `Dms.Api` | Controllers، DTOs، JWT، Swagger، middleware، Seed، `ICurrentUser` | Infrastructure, Domain, Documents |
| `Dms.Spike` | إثبات تقني لـ Phase 0 | Documents |

## تدفّق الطلب
1. الطلب يحمل `Authorization: Bearer <JWT>` (+ `X-Company-Id` للسوبر أدمن).
2. `HttpCurrentUser` يشتق المستخدم/الدور/الشركة من الـ claims.
3. `AppDbContext` يُنشأ scoped ويضبط فلتر الشركة من `ICurrentUser`.
4. الـ Controller يستدعي خدمة؛ الخدمة تطبّق قواعد العمل والصلاحيات.
5. الأخطاء تُرمى كاستثناءات مجال → `ExceptionMiddleware` يحوّلها لأكواد HTTP + JSON.

## المصادقة
- `AuthService.LoginAsync`: تحقق BCrypt + قفل بعد فشل + إصدار `TokenPair` (Access JWT + Refresh مجزّأ).
- `RefreshAsync`: تدوير الرمز (إبطال القديم + إصدار جديد).
- **claims التوكن (`DmsClaims`) — سبعة:**

| Claim | المعنى | المصدر |
|---|---|---|
| `uid` | معرّف المستخدم | — |
| `role` | الدور (+ `ClaimTypes.Role` لـ `[Authorize(Roles=…)]`) | — |
| `cids` | قائمة معرّفات الشركات المسموحة (**جمع**) | ADR-011 |
| `approve` | صلاحية اعتماد الصادر — **خريطة لكل شركة** | ADR-017 |
| `mods` | bitmask أقسام النظام — **خريطة لكل شركة** | ADR-012 · ADR-017 |
| `inc_mng` | صلاحية إدارة حالات الوارد — **خريطة لكل شركة** | ADR-017 |
| `dept` | قسم عمل المستخدم — **خريطة لكل شركة** (الشركات ذات القسم فقط) | ADR-017 |

**الأربعة الأخيرة خرائط بصيغة `شركة:قيمة,شركة:قيمة`** (مثال `mods` = `1:63,2:127`)، يفكّها
`Dms.Domain/PerCompanyClaim.cs` وينتقي `HttpCurrentUser` قيمة **الشركة الفعّالة**. شركة خارج
الخريطة ⇒ لا صلاحية ولا قسم (**فشل مغلق**).

> **لماذا في التوكن لا في القاعدة؟** لأن `AppDbContext` يعتمد على `ICurrentUser`، فلو احتاج
> `ICurrentUser` قاعدةَ البيانات لصار الاعتماد **دائرياً**. هذا القيد هو ما حسم التصميم (ADR-017).

## تعدد الشركات (Row-level)
- فلتر عام: `(!_filterByCompany || x.CompanyId == _companyId) [&& !IsDeleted]`.
- **استثناء `User`:** الفلتر يشمل الشركات المُسندة أيضاً — `CompanyId == cid || AssignedCompanies.Any(c => c.CompanyId == cid)` (ADR-011).
- SuperAdmin بلا شركة فعّالة → بلا فلترة. غير المصادَق → بلا فلترة (لتسجيل الدخول).
- ⚠️ **درس متكرر:** الفلتر يستبعد السوبر أدمن (`CompanyId = NULL`) وقت وجود شركة فعّالة — فأي جلب **لاسم مستخدم للعرض** يحتاج `IgnoreQueryFilters()` (تجاوز مقصود وموثّق في الكود).

## توليد المستند (عند الاعتماد)
1. `OutgoingService.ApproveAsync` داخل `ExecutionStrategy + Transaction`.
2. `NumberingService.NextSerialAsync` (قفل `UPDLOCK`) → تسلسل آمن، رقم `PREFIX-YEAR-00001`.
3. `BookRenderer.RenderPdfAsync`: يبني الصور (Blob/placeholder) + يوقّع QR (ECDSA) + ينشئ PDF (QuestPDF).
4. حفظ PDF في `IFileStorage` → `GeneratedPdfBlobKey`. تخزين `QrContent`/`QrSignature`.

## أداء توليد المستندات
- صور القالب (ترويسة · تذييل · علامة مائية بعد تطبيق الشفافية) تُخزَّن مؤقتاً في
  `TemplateAssetCache` (**singleton** — `BookRenderer` scoped فلا يصلح لحملها).
- **آمن بلا إبطال يدوي:** مفتاح التخزين يحمل `Guid` فريداً لكل رفع، فالصورة الجديدة تُنتج
  مفتاحاً جديداً والمدخل القديم لا يُستعلَم عنه. الشفافية تدخل في مفتاح العلامة المائية.
- **قياس:** توليد معاينة 2115 ⇒ **1495 مللي**. الباقي هو تخطيط QuestPDF وتضمين الخطوط العربية،
  ولهذا بقيت المعاينة **بتحديث عند الطلب** لا تلقائياً.

## التعديل بعد الاعتماد
- لقطة JSON للنسخة الحالية في `DocumentVersions` (VersionNo تصاعدي) + تزامن متفائل (`RowVersion`) + إعادة توليد PDF/QR. الرقم يبقى ثابتاً.

## دورة حياة الوارد والأقسام
- **الحالات** تتغيّر عبر **مصفوفة مغلقة** في `Dms.Domain/IncomingWorkflow.cs` (ADR-013) — لا انتقال خارجها.
- **الإحالة** تُسنِد الكتاب إلى **قسم واحد أو أكثر** عبر جدول `IncomingAssignment` (ADR-018 — حلّ محلّ عمود `DepartmentId` المفرد). تراكمية: تُضيف ولا تُزيح.
- **قاعدة الرؤية** في `IncomingService.Query` — الموظف/القارئ يرى ثلاثة أنواع:
  ① ما استلمه · ② ما أُحيل **لقسمه** (ADR-015 — وهذا ما يجعل الإحالة إسناداً لا نصّاً) · ③ **ما أحاله هو بنفسه** (ADR-018 — قاعدة متابعة: لا يختفي من قائمته عملٌ باشره).

## وضع الصيانة (أثناء استعادة نسخة — ADR-014)
- `IMaintenanceState` + `MaintenanceMiddleware`: أثناء الاستعادة تُرفض كل الطلبات بـ **503**، عدا `GET /api/system/status` الذي يبقى مجيباً ليعرف العميل متى عاد النظام.
- بعد `RESTORE` تلزم ثلاث خطوات وإلا فشلت أول كتابة: `ClearAllPools()` ← `MigrateAsync()` ← `ChangeTracker.Clear()`.

## الإنتاج (سيرفر داخلي — ADR-016)
- **لا Azure:** `LocalFileStorage` يبقى كما هو (قرص السيرفر)، ومفاتيح JWT/QR تُولَّد على السيرفر وتُحمى بـ BitLocker + NTFS بدل Key Vault.
- الـAPI **خدمة ويندوز** (`UseWindowsService`)، والوصول عبر **Cloudflare Tunnel** (HTTPS تلقائي، صفر منافذ مفتوحة).
- تجريد `IFileStorage` يبقى قائماً — لو عاد قرار السحابة يوماً، يكفي تطبيق جديد للواجهة بلا تغيير في الخدمات.
