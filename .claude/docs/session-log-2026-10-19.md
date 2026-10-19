# سجلّ الجلسة — 2026-10-19: تجاوب متصفّح الهاتف · المحادثة الفورية وشارة التعليقات في المهام (ADR-063 — الإصدار `0.17.0`)

> **ابدأ من هنا في الجلسة القادمة.** ما طُلب · كيف نُفّذ · ما وقع بصدق · كيف يُتحقَّق · وما بقي.

## 1) تجاوب متصفّح الهاتف (`Mobile Browser Responsiveness`)
- **بلاغ المالك بعد فتح النظام من متصفّح الهاتف**:
  1. في الوضع العمودي للهاتف (`Portrait`) لا تظهر أزرار الشريط العلوي (`Topbar`) بالكامل ولا تظهر إلا عند تدوير الهاتف أفقياً (`Landscape`).
  2. القائمة الجانبية (`Sidebar`) عند فتحها على الهاتف يصعب إغلاقها أو الرجوع منها وتزاحم محتوى الصفحة.
  3. طلب المالك مراجعة جميع الشاشات لضمان عملها بأفضل صورة على كلٍّ من الهاتف والحاسوب دون أيّ تأثيرٍ سلبيّ على تصميم سطح المكتب.
- **التنفيذ**:
  - **`Topbar` (`app/lib/widgets/topbar.dart`) + `BackupAlertIcon` (`app/lib/widgets/backup_alert.dart`)**:
    - إظهار جميع أزرار الشريط العلوي (التحقق من QR · الوارد المعلّق · تنبيه النسخ للسوبر أدمن · جرس الإشعارات · مسودّات الصادر) في الوضع العمودي للهاتف بحجمٍ مدمج (`compact: isSmall`, `34×34`) مع إخفاء التاريخ الطويل واسم المستخدم النصيّ ودور المستخدم على الشاشات الضيقة والاكتفاء بالأفاتار لفتح قائمة الحساب.
    - بعد تجربة المالك وتصغير الصفحة إلى عرضٍ ضيّق جدّاً (~`317px`) ظهر `RenderFlex overflowed by 2.4 pixels` في `Topbar` ⟵ عولج بضبط الهوامش الداخلية (`padding` متدرّج عند `< 380px`) وتصغير الفجوات وحجم الأفاتار ولفّ عنوان القسم بـ`Expanded` مع `TextOverflow.ellipsis` وإخفاء العنوان الفرعي عند `< 480px`.
  - **`Sidebar` (`app/lib/widgets/sidebar.dart`) + `HomeShell` (`app/lib/screens/home_shell.dart`)**:
    - على الشاشات `< 900px` تتحوّل القائمة الجانبية إلى **درجٍ عائم (`Overlay Drawer`)** داخل `Stack` مع طبقة تظليل معتمة (`GestureDetector` + `ColoredBox` scrim) وزرّ إغلاق واضح (`✕`) في رأس القائمة، وتُغلق تلقائياً عند اختيار أيّ قسم أو فتح مسودّاتي أو تسجيل الخروج أو تدوير الشاشة أو الضغط على زرّ الرجوع (`PopScope`).
    - على شاشات الحاسوب (`>= 900px`) بقي التخطيط الأفقي الثابت كما كان حرفياً دون أيّ تغيير.
  - **تجاوب الشاشات الفرعية**:
    - ضبط الهوامش (`padding: 12` على الهاتف بدل `24`) وأشرطة الفلاتر في `dashboard_screen.dart` · `outgoing_list_screen.dart` · `incoming_list_screen.dart` · `archive_list_screen.dart` · `employee_list_screen.dart` · `case_files_screen.dart`.
    - تغليف جدول `users_screen.dart` بـ`SingleChildScrollView(scrollDirection: Axis.horizontal)` مع `ConstrainedBox` لمنع انضغاط الأعمدة الثمانية على الهاتف.
    - تحويل بطاقة تغطية النسخ في `backup_screen.dart` إلى تخطيطٍ عموديّ متجاوب على الشاشات `< 640px`.

## 2) المحادثة الفورية داخل تبويب «التعليقات» في المهام (`Live Task Comments`)
- **بلاغ المالك**: عند إرسال تعليقٍ بين مستخدمين داخل مهمة، لا يظهر التعليق مباشرةً لدى الطرف الآخر (بل ولا يظهر أحياناً للمرسل إلا بعد الرجوع خطوةً للوراء والدخول مرّةً أخرى)، والمطلوب أن تعمل التعليقات كمحادثةٍ مستمرّةٍ طبيعية أثناء العمل.
- **التنفيذ (`app/lib/screens/task_detail_screen.dart`)**:
  - إضافة مؤقّت استقصاءٍ خفيف في الخلفية (`_pollUpdates` كل **3 ثوانٍ** ما دامت `TaskDetailScreen` مفتوحة، ويُلغى فور الخروج في `dispose()`).
  - تفعيل `skipLoadingOnRefresh: true` و`skipLoadingOnReload: true` و`skipError: true` على `ref.watch(taskDetailProvider)` حتى يتحدّث المحتوى بهدوءٍ تامّ دون إظهار دائرة التحميل أو وميض الشاشة.
  - عزل قائمة التعليقات داخل `Consumer` مستقلّ مع الاحتفاظ بـ`_commentComposer` خارج إعادة البناء حتى **لا تنقطع كتابة المستخدم ولا يفقد حقلُ الإدخال تركيزه** لحظة وصول تعليقٍ جديد.
  - إضافة `ScrollController` (`_commentsScrollController`) للتمرير التلقائي السلس إلى آخر تعليق عند إرسال تعليقٍ جديد أو وصول تعليقٍ من الطرف الآخر.

## 3) شارة المحادثات غير المقروءة على كروت المهام (`TaskUnreadCommentsBadge`)
- **طلب المالك**: إظهار إشعارٍ على كل كارت بداخل قسم المهام حتى يعرف المستخدم أن هناك محادثةً لم تُفتح بعد.
- **التنفيذ**:
  - الاستفادة من البنية القائمة في الخادم (`TaskService.AddCommentAsync` يُنشئ إشعاراً بـ`Category = "Task"` و`EntityType = "DmsTask"` و`EntityId = task.TaskId` وعنوان `تعليقٌ جديد على مهمة` لكل مستلِمٍ في المهمة عدا المرسل) — **بلا أيّ تغييرٍ في الباك-إند أو قاعدة البيانات**.
  - إضافة `unreadTaskNotificationsProvider` ودالّة نقيّة `unreadTaskCommentCountsOf` في `app/lib/core/task_providers.dart`.
  - إضافة ودجة `TaskUnreadCommentsBadge` في `app/lib/widgets/task_badges.dart` باللون الذهبي وأيقونة `mark_chat_unread_rounded` (تظهر الكاملة في `TaskListScreen` والمدمجة في `TaskBoardScreen`، وتختفي تماماً عند الصفر).
  - تحديثٌ صامت كل **5 ثوانٍ** في `TaskListScreen` و`TaskBoardScreen` لظهور الشارة تلقائياً عند وصول تعليق جديد.
  - عند النقر على كارت مهمة يحمل تعليقاتٍ غير مقروءة، تفتح `TaskDetailScreen` **مباشرةً على تبويب «التعليقات» (`initialTab: 1`)**، وتقوم `_markTaskNotificationsRead()` بوسم إشعارات تلك المهمة كمقروءة تلقائياً فيختفي التنبيه من الكارت ومن الجرس العلوي.

## 4) ما وقع بصدق (دروسٌ تقنية وحرّاس)
1. 🔴 **حارس `provider_resume_test.dart` (ADR-042)**: منع تعريف مزوّدٍ متزامن (`Provider.autoDispose`) يشتقّ من `ref.watch(...)` في `lib/core/task_providers.dart`، ومنع `await ref.watch(...future)` في الشاشات ⟵ استُبدل المزوّد المشتقّ بدالّةٍ نقيّة `unreadTaskCommentCountsOf(AsyncValue<List<NotificationModel>>)` تُستدعى في `build`.
2. 🔴 **درس «الجرس يستطلع في اختبارٍ بلا خادم» في `task_board_test.dart`**: بعد ربط `TaskBoardScreen` بـ`unreadTaskNotificationsProvider`، استدعى الاختبار `api.notifications()` على `_BoardApi` الذي لم يكن يتجاوزها، فذهب الطلب إلى `Dio` وترك مؤقّتاً صفريّاً معلّقاً (`Pending timers`) ⟵ أُضيف تجاوز `notifications()` في `_BoardApi` ليعيد `NotificationPage.empty` بلا شبكة.

## 5) كيف يُتحقَّق
- `flutter analyze`: **0 أخطاء / 0 تحذيرات**.
- اختبارات الواجهة (`flutter test`): **811 / 811** (+6 اختبارات جديدة في `ui_polish_test.dart` و`sidebar_header_test.dart` و`tasks_ui_test.dart`).
- اختبارات الوحدة (`dotnet test`): **844 / 844**.
- الإصدار في `VERSION` و`app/pubspec.yaml`: **`0.17.0`**.
