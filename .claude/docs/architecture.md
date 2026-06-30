# المعمارية (Architecture)

## نظرة عامة
عميل سطح مكتب (Flutter Desktop) ← HTTPS (REST + JWT) ← **ASP.NET Core API مركزي** ← SQL Server + تخزين Blob. كل منطق العمل في الباك-إند؛ العميل رفيع.

```
[Flutter Desktop]──HTTPS/JWT──> [Dms.Api] ──> [Dms.Infrastructure] ──> SQL Server
                                    │                  │
                                    │                  └─> IFileStorage (Blob/محلي)
                                    └─> [Dms.Documents] (QuestPDF / OpenXML / QR ECDSA)
```

## الطبقات
| المشروع | المسؤولية | يعتمد على |
|---|---|---|
| `Dms.Domain` | كيانات، enums، منطق نقي (FinancialCalculator، RoleHierarchy)، استثناءات المجال | — |
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
- claims: `uid`, `role`, `cid` (شركة)، `approve`. `ClaimTypes.Role` مضاف لـ `[Authorize(Roles=...)]`.

## تعدد الشركات (Row-level)
- فلتر عام: `(!_filterByCompany || x.CompanyId == _companyId) [&& !IsDeleted]`.
- SuperAdmin بلا شركة فعّالة → بلا فلترة. غير المصادَق → بلا فلترة (لتسجيل الدخول).

## توليد المستند (عند الاعتماد)
1. `OutgoingService.ApproveAsync` داخل `ExecutionStrategy + Transaction`.
2. `NumberingService.NextSerialAsync` (قفل `UPDLOCK`) → تسلسل آمن، رقم `PREFIX-YEAR-00001`.
3. `BookRenderer.RenderPdfAsync`: يبني الصور (Blob/placeholder) + يوقّع QR (ECDSA) + ينشئ PDF (QuestPDF).
4. حفظ PDF في `IFileStorage` → `GeneratedPdfBlobKey`. تخزين `QrContent`/`QrSignature`.

## التعديل بعد الاعتماد
- لقطة JSON للنسخة الحالية في `DocumentVersions` (VersionNo تصاعدي) + تزامن متفائل (`RowVersion`) + إعادة توليد PDF/QR. الرقم يبقى ثابتاً.

## ملاحظات الإنتاج
- استبدال `LocalFileStorage` بتطبيق Azure Blob (نفس الواجهة).
- نقل مفاتيح JWT/QR إلى Key Vault. تفعيل App Insights + HTTPS.
