# DMS App — واجهة Flutter (العميل)

عميل سطح المكتب/الويب لنظام إدارة الوثائق، يتصل بالـ API (`Dms.Api`). مبني بـ **Flutter + Riverpod**، عربي RTL بالكامل.

## البنية
```
lib/
├── main.dart                 # نقطة الدخول + بوابة المصادقة (RTL)
├── models.dart               # نماذج البيانات (DTOs)
├── core/
│   ├── api_client.dart       # عميل Dio + إرفاق JWT/X-Company-Id + ترجمة الأخطاء
│   ├── session.dart          # حالة الجلسة (Riverpod Notifier) + حفظ التوكن + apiClientProvider
│   └── downloader*.dart      # تنزيل ملفات عبر المنصّات (web/desktop)
└── screens/
    ├── login_screen.dart · change_password_screen.dart · company_select_screen.dart
    ├── home_shell.dart · dashboard_screen.dart
    ├── outgoing_list_screen.dart · outgoing_form_screen.dart · outgoing_detail_screen.dart
    ├── outgoing_edit_approved_screen.dart  # تعديل بعد الاعتماد (+ سجل إصدارات)
    ├── archive_list_screen.dart · archive_form_screen.dart · archive_detail_screen.dart  # الأرشيف + المرفقات + بحث بفترة
    ├── reports_screen.dart                  # التقرير المالي (فلاتر + إجمالي بالدينار + تصدير PDF/Excel)
    ├── backup_screen.dart                   # النسخ الاحتياطي (سوبر أدمن: جدولة + نسخة الآن + قائمة + تنزيل)
    ├── template_edit_screen.dart           # تعديل قالب + رفع صور (هيدر/فوتر/علامة)
    ├── users_screen.dart                    # المستخدمون + التفويضات (للمدير فأعلى)
    └── settings_screen.dart                # شركات/جهات/قوالب/أسعار صرف
```

## الإعداد
1. شغّل الـ API أولاً (`D:\DMS\backend` → `dotnet run --project Dms.Api`).
2. عدّل عنوان الـ API إن لزم في `lib/core/session.dart` → `kApiBaseUrl` (افتراضي `http://localhost:5080/api`).

## التشغيل
```bash
cd D:\DMS\app
flutter run -d chrome      # ويب (جاهز فوراً)
flutter run -d windows     # سطح المكتب (يتطلب VS workload أدناه)
```

### بناء سطح المكتب (Windows .exe)
يتطلب لمرة واحدة تثبيت حزمة Visual Studio **"Desktop development with C++"** (تشمل: C++ CMake tools و Windows 10 SDK)، ثم:
```bash
flutter build windows
```
> الكود نفسه يعمل على ويب وسطح المكتب بلا تغيير — فقط هدف البناء يختلف.

## التحقق
- `flutter analyze` → بلا مشاكل.
- `flutter build web` → يبني الحزمة بنجاح.
- `flutter test` → اختبار الإقلاع ناجح.

## أول دخول
`admin` / `Admin@12345` (سيُطلب تغيير كلمة المرور). السوبر أدمن يختار الشركة الفعّالة بعد الدخول.
