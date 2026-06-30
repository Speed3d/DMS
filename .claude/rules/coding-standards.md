# قواعد: أسلوب الكود

## عام
- **C# حديث** (.NET 9): primary constructors، records للـ DTOs والمدخلات، `file-scoped namespaces`، nullable مُفعّل.
- استهدف **net9.0** في كل المشاريع (مثبّت عبر `global.json`). لا ترفع لـ net10 إلا بقرار صريح (يكسر توافق حزم EF/ASP.NET المثبتة).
- لا تحذيرات: البناء يجب أن يبقى **0 errors / 0 warnings**.

## اللغة والتعليقات
- **التعليقات والرسائل الموجّهة للمستخدم بالعربية** (مطابقة لطبيعة المشروع).
- أسماء الرموز (classes/methods/properties) بالإنجليزية القياسية.
- رسائل الأخطاء (`DomainException`) بالعربية الواضحة — تظهر للمستخدم النهائي.

## التسمية
- الكيانات: مفرد (`OutgoingBook`)، الـ DbSet: جمع (`OutgoingBooks`).
- الخدمات: `IXxxService` + `XxxService`. المدخلات: `XxxInput` (records). عقود الـ API: `XxxRequest`/`XxxResponse`.
- مفتاح أساسي صريح بـ `HasKey` إن لم يطابق الاسم اصطلاح `<Type>Id`.

## الأنماط
- استخدم استثناءات المجال (`ValidationException`/`NotFoundException`/`ForbiddenException`/`ConflictException`) — تُترجَم تلقائياً لأكواد HTTP عبر `ExceptionMiddleware`.
- العمليات غير المتزامنة `async`/`await` مع `CancellationToken` تُمرَّر حتى الـ DB.
- لا تُرجِع الكيانات مباشرةً من الـ Controllers — استخدم DTOs.
- المبالغ: `decimal` بدقة `(18,2)`؛ أسعار الصرف `(18,4)`.

## EF Core
- أي عملية تتضمّن `BeginTransaction` **يجب** أن تُغلَّف بـ `CreateExecutionStrategy().ExecuteAsync(...)` (لأن `EnableRetryOnFailure` مُفعّل).
- لا تُعطّل الـ Global Query Filters إلا عمداً وبوعي أمني (`IgnoreQueryFilters`).
