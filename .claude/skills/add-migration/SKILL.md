---
name: add-migration
description: إنشاء وتطبيق EF Core migration لباك-إند DMS بعد تعديل الكيانات. استخدمها عند تغيير نموذج البيانات (إضافة/تعديل كيان أو خاصية) أو الحاجة لتحديث مخطط قاعدة البيانات.
---

# EF Core Migrations لـ DMS

أداة `dotnet-ef` مثبّتة عالمياً. الـ DbContext في `Dms.Infrastructure`؛ مشروع البدء `Dms.Api`. مصنع زمن التصميم: `AppDbContextFactory` (يستخدم LocalDB).

## إنشاء migration جديد
```powershell
Set-Location "D:\DMS\backend"
dotnet ef migrations add <اسم_واضح> -p Dms.Infrastructure -s Dms.Api
```

## تطبيقه على قاعدة البيانات
```powershell
dotnet ef database update -p Dms.Infrastructure -s Dms.Api
```
> الـ API يطبّق الـ migrations تلقائياً عند الإقلاع (`DbSeeder.MigrateAndSeedAsync`)، لكن طبّقه يدوياً للتحقق.

## قواعد مهمة
- **أوقِف الـ API أولاً** إن كان يعمل (يقفل ملفات الإخراج).
- إن لم يطابق اسم المفتاح اصطلاح `<Type>Id`، أضِف `HasKey` في `AppDbContext` قبل توليد الـ migration.
- لا تعدّل migration مطبّقاً؛ أنشئ migration جديداً.
- بعد التغيير: حدّث [`../../docs/data-model.md`](../../docs/data-model.md) و [`../../docs/progress-log.md`](../../docs/progress-log.md).

## التراجع/الحذف (قبل التطبيق)
```powershell
dotnet ef migrations remove -p Dms.Infrastructure -s Dms.Api
```
