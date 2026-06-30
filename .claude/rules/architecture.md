# قواعد: المعمارية

## الطبقات (اتجاه الاعتماد من الأعلى للأسفل)
```
Dms.Api  →  Dms.Infrastructure  →  Dms.Domain
                     ↘  Dms.Documents  ↗
```
- **Dms.Domain:** كيانات + enums + منطق نقي (حساب مالي، تسلسل هرمي، استثناءات). **بلا اعتماد على أي مشروع.**
- **Dms.Documents:** توليد PDF/Word/QR + تجريد التخزين. مستقل (يُستخدم من Infrastructure والـ Spike).
- **Dms.Infrastructure:** EF Core (`AppDbContext`) + الخدمات (Auth/Numbering/Audit/Outgoing/Users…). كل **منطق العمل هنا**.
- **Dms.Api:** عرض فقط — Controllers رفيعة، DTOs، JWT، DI، middleware، Seed. لا منطق عمل في الـ Controllers.

## قواعد الوضع
- منطق العمل → خدمة في Infrastructure، خلف واجهة `IXxxService`، مُسجّلة في `DependencyInjection.AddInfrastructure`.
- وصول البيانات عبر `AppDbContext` فقط. لا SQL خام إلا لضرورة (مثل قفل الترقيم `UPDLOCK`).
- توليد المستندات عبر `BookRenderer` (Infrastructure) الذي يستدعي `Dms.Documents`.
- **مبدأ الخطة:** كل منطق العمل في الباك-إند ليبقى العميل (Flutter/ويب/هاتف لاحقاً) رفيعاً.

## تعدد الشركات (Tenancy)
- العزل الصفّي عبر **Global Query Filter** على `CompanyId` في `AppDbContext`، يعتمد `ICurrentUser`.
- SuperAdmin بلا فلترة (يرى الكل)؛ يحدّد شركته الفعّالة بترويسة `X-Company-Id`.
- المستخدم العادي مقيّد بـ `CompanyId` من الـ JWT — لا يتجاوزه بترويسة.
- غير المصادَق (login) = بلا فلترة (للبحث عن المستخدم).

## توليد المستندات
- صور القالب من Blob (أو placeholder عند غيابها). العلامة المائية تُطبّق شفافيتها من `Template.WatermarkOpacity`.
- الـ QR يُولَّد ويُوقَّع عند الاعتماد فقط (يتطلب رقماً رسمياً). المتن نصّ حقيقي (قابل للبحث).
