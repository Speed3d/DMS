# دليل مشروع DMS (Claude Project Guide)

نظام إدارة وثائق إلكتروني لشركة **«أرض العرين للتجارة والمقاولات» (DEN LAND)** — متعدد الشركات، سحابي، عميل سطح مكتب يتصل بـ API مركزي.

## 1) المرجع الأساسي
- **خطة العمل الكاملة:** [`خطة-العمل.md`](../خطة-العمل.md) (الإصدار 2.2 — معتمدة ومُراجَعة تقنياً). هي مصدر الحقيقة للنطاق والقرارات.
- **توثيق التنفيذ:** مجلد [`.claude/docs/`](docs/).

## 2) التقنيات المعتمدة (Tech Stack)
| الطبقة | التقنية |
|---|---|
| الباك-إند | ASP.NET Core Web API (.NET 9) + EF Core 9 |
| قاعدة البيانات | SQL Server (محلياً LocalDB، إنتاجاً Azure SQL) |
| توليد PDF | **QuestPDF** (أصلي، RTL، بلا متصفح) |
| تصدير Word | **OpenXML** (DocumentFormat.OpenXml) |
| توقيع QR | **ECDSA P-256** (مفاتيح في Key Vault بالإنتاج) |
| المصادقة | JWT + Refresh + BCrypt |
| التخزين | تجريد `IFileStorage` (محلي تطويراً، **Azure Blob** إنتاجاً) |
| الواجهة | Flutter Desktop (Windows) — قيد الإنشاء |
| الخط العربي | Amiri (OFL) مضمّن |

> القرارات التقنية الكاملة مع مبرراتها: [`docs/decisions.md`](docs/decisions.md).

## 3) بنية المستودع
```
D:\DMS\
├── خطة-العمل.md            # الخطة المعتمدة (v2.2)
├── CLAUDE.md               # يُحمَّل تلقائياً (يستورد هذا الملف + القواعد)
├── .claude\                # توثيق + قواعد + مهارات + إعدادات
│   ├── CLAUDE.md  rules\  docs\  skills\  .cache\  settings.json
├── backend\                # حل الباك-إند (.NET)
│   ├── Dms.Domain          # الكيانات + enums + منطق المجال
│   ├── Dms.Documents       # PDF/Word/QR/التخزين
│   ├── Dms.Infrastructure  # EF Core + الخدمات
│   ├── Dms.Api             # Controllers + JWT + Swagger + Seed
│   └── Dms.Spike           # اختبار Phase 0 التقني
└── app\                    # واجهة Flutter (العميل) — Riverpod + Dio، عربي RTL
```

## 4) أوامر سريعة
```bash
cd D:\DMS\backend
dotnet build Dms.sln                                   # بناء الكل
dotnet run --project Dms.Api                           # تشغيل الـ API (+ Swagger في Development)
dotnet ef migrations add <Name> -p Dms.Infrastructure -s Dms.Api
dotnet ef database update      -p Dms.Infrastructure -s Dms.Api
dotnet run --project Dms.Spike                         # اختبار توليد PDF/QR/Word
```
- أول دخول: `admin` / `Admin@12345` (إجباري تغييرها).
- الأسرار (JWT + مفاتيح QR) في `backend/Dms.Api/appsettings.Development.json` (غير مُدرج في git).

## 5) الحالة الحالية
- ✅ **Phase 0** — التحقق التقني (PDF عربي + QR موقّع + Word).
- ✅ **Phase 1** — باك-إند MVP للصادر (مصادقة/أدوار/شركات/قوالب/دورة حياة الصادر/تدقيق/تحقق) — اجتاز 13 اختبار E2E.
- ✅ **واجهة Flutter (Phase 1 مكتملة)** — `app/` متصلة بالـ API: دخول/لوحة/صادر (إنشاء/اعتماد/PDF/تعديل بعد الاعتماد/إصدارات)/إعدادات/رفع صور القوالب/إدارة المستخدمين والتفويض. تحقّق: analyze + build web + test. (Windows .exe يتطلب VS C++ workload.)
- ⏳ **التالي** — Phase 2: الأرشيف (الكيانات جاهزة) + التقارير المالية + النسخ الاحتياطي + وضع دون اتصال + النشر على Azure.

> التفصيل والتحديث المستمر: [`docs/roadmap.md`](docs/roadmap.md) و [`docs/progress-log.md`](docs/progress-log.md).

## 6) قاعدة التوثيق المستمر
**بعد كل خطوة مهمة (ميزة/قرار/إصلاح):** حدّث [`docs/progress-log.md`](docs/progress-log.md)، وعند تغيّر المعمارية/البيانات/الـ API/القرارات حدّث الملف المعني في `docs/`. راجع [`rules/workflow.md`](rules/workflow.md).
