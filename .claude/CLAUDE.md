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

> ### 📍 **[`docs/status-report.md`](docs/status-report.md) — اقرأه أولاً**
> المرجع الحيّ لحالة المشروع: أين وصلنا · حالة كل وحدة · الفجوات المفتوحة · ما تبقّى بالأولوية.
> يُحدَّث بعد كل دفعة عمل، فلا تعتمد على الملخص أدناه إن تعارضا.

**بإيجاز (2026-07-22):** ✅ Phase 0/1/2 مكتملة — ثماني وحدات تعمل: الصادر · **الوارد** · الأرشيف · المستخدمون والصلاحيات · التقارير المالية · النسخ الاحتياطي · وضع دون اتصال · الأمان والتدقيق. البناء 0/0، و55 اختبار وحدة، و65 تحقّق E2E.
⏳ **التالي — Phase 3 (النشر والتسليم):** الاستضافة · استعادة النسخة الاحتياطية · مثبّت ويندوز · نقل الأسرار لخزنة مفاتيح · اختبارات العزل والتزامن.

> التفصيل: [`docs/progress-log.md`](docs/progress-log.md) · خارطة الطريق: [`docs/roadmap.md`](docs/roadmap.md).

## 6) قاعدة التوثيق المستمر
**بعد كل خطوة مهمة (ميزة/قرار/إصلاح):** حدّث [`docs/progress-log.md`](docs/progress-log.md)، وعند تغيّر المعمارية/البيانات/الـ API/القرارات حدّث الملف المعني في `docs/`. راجع [`rules/workflow.md`](rules/workflow.md).
