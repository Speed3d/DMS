# DMS Backend — نظام إدارة الوثائق (Phase 1)

باك-إند نظام إدارة الوثائق لشركة «أرض العرين / DEN LAND». مبني على **ASP.NET Core (.NET 9) + EF Core + SQL Server**، بمعمارية نظيفة.

## المشاريع
| المشروع | الدور |
|---|---|
| `Dms.Domain` | الكيانات والـ enums ومنطق المجال (الحساب المالي، التسلسل الهرمي). |
| `Dms.Documents` | توليد PDF (QuestPDF) وWord (OpenXML) وتوقيع QR (ECDSA P-256) وتجريد التخزين. |
| `Dms.Infrastructure` | EF Core (`AppDbContext`) + الخدمات (المصادقة، الترقيم، التدقيق، الصادر، المستخدمون). |
| `Dms.Api` | الـ Controllers + DTOs + JWT + Swagger + التهيئة و Seed. |
| `Dms.Spike` | اختبار تقني لـ Phase 0 (PDF/QR/Word). `dotnet run --project Dms.Spike`. |

## المتطلبات
- .NET SDK 9 (مثبّت عبر `global.json`).
- SQL Server LocalDB (أو عدّل سلسلة الاتصال في `appsettings.json`).

## التشغيل
```bash
cd D:\DMS\backend
dotnet run --project Dms.Api
```
- يطبّق الـ Migrations تلقائياً وينشئ أول SuperAdmin إن لم يوجد.
- Swagger: `http://localhost:<port>/swagger` (في بيئة Development).
- **أول دخول:** `admin` / `Admin@12345` — غيّر كلمة المرور فوراً (`MustChangePassword`).

## الأسرار (تطوير)
`appsettings.Development.json` يحوي مفتاح JWT ومفاتيح توقيع QR (ECDSA). **غير مُدرج في git.** في الإنتاج تُنقل إلى **Azure Key Vault**.

## تعدد الشركات
- المستخدم العادي مقيّد بشركته (claim).
- **SuperAdmin** يرى كل الشركات؛ لتحديد شركة فعّالة للعمليات أرسل ترويسة `X-Company-Id: <id>`.

## أبرز نقاط النهاية
- `POST /api/auth/login` · `/auth/refresh` · `/auth/change-password`
- `GET/POST/PUT /api/companies` · `/templates` (+ رفع صور) · `/entities` · `/document-types` · `/exchange-rates`
- `GET/POST/PUT /api/users` · `/delegations`
- `GET/POST/PUT /api/outgoing` · `POST /api/outgoing/{id}/approve` · `PUT /api/outgoing/{id}/edit-approved` · `GET /api/outgoing/{id}/{pdf|word|versions}`
- `GET /api/audit` · `POST /api/verify` (عام — تحقق QR)

## قاعدة البيانات / Migrations
```bash
dotnet ef migrations add <Name> -p Dms.Infrastructure -s Dms.Api
dotnet ef database update      -p Dms.Infrastructure -s Dms.Api
```
