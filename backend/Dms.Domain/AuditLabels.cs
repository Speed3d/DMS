namespace Dms.Domain;

/// <summary>
/// ترجمة مفردات سجلّ التدقيق إلى عربية يقرأها المالك — الأفعال وأنواع الكيانات.
/// </summary>
/// <remarks>
/// 🔴 **لماذا في طبقة المجال لا في الخدمة؟** لأنها منطقٌ نقيّ بلا قاعدة بيانات، و<c>Dms.Tests</c>
/// يرجع <c>Dms.Domain</c> و<c>Dms.Documents</c> فقط — فوضعُها هنا يجعلها **مُختبَرة**، ووضعُها
/// في <c>ReportService</c> يجعلها خارج مرمى أي اختبار (درس D9 المسجَّل في خطة وحدة المهام).
///
/// 🔴 **والمجهول يُعرَض كما هو لا يُخفى ولا يُستبدل بـ«غير معروف»**: سجلّ التدقيق سجلٌّ أمنيّ،
/// وإخفاءُ فعلٍ لأن مترجمَه غائب **يحذف معلومةً من تقرير أمني**. فعلٌ جديد يظهر بالإنجليزية
/// حتى تُضاف ترجمته — ناقصُ الأناقة خيرٌ من ناقص الحقيقة.
///
/// ⚠️ **القائمتان مستخرَجتان من مواضع <c>audit.Add(...)</c> الفعلية في المستودع** (18 ملفاً)،
/// لا من التخمين. وحارسٌ في <c>AuditLabelsTests</c> يُثبت أن كل مفتاح يترجَم فعلاً.
/// </remarks>
public static class AuditLabels
{
    /// <summary>الأفعال المعروفة ← عربيّتها. المفتاح هو ما يُكتب في <c>AuditLog.Action</c>.</summary>
    public static readonly IReadOnlyDictionary<string, string> Actions = new Dictionary<string, string>(StringComparer.Ordinal)
    {
        // ── عام ──
        ["Create"] = "إنشاء",
        ["Update"] = "تعديل",
        ["Delete"] = "حذف",
        ["Link"] = "ربط",
        ["Unlink"] = "فكّ ربط",

        // ── الصادر ──
        ["Approve"] = "اعتماد",
        ["EditApproved"] = "تعديل بعد الاعتماد",

        // ── الوارد ──
        ["ChangeStatus"] = "تغيير حالة",
        ["Forward"] = "إحالة إلى قسم",

        // ── المرفقات ──
        ["AddAttachment"] = "إضافة مرفق",
        ["DeleteAttachment"] = "حذف مرفق",
        ["UploadImage"] = "رفع صورة",
        ["DeleteImage"] = "حذف صورة",
        ["UploadLogo"] = "رفع شعار",
        ["SetPhoto"] = "تعيين صورة موظف",
        // ⚠️ **مفصولٌ عن `SetPhoto` عمداً (ADR-035)**: قارئ السجلّ يحتاج أن يميّز صورةً
        //    وضعتها شؤون الموظفين من صورةٍ وضعها صاحبها بنفسه.
        ["SetOwnPhoto"] = "تغيير صورته الشخصية",

        // ── حسم الإجازات من الكشف (ADR-036) ──
        // ⚠️ **فعلان لا واحد**: «طُبّق» أنقص مالاً و«صُرف النظر» لم يمسّه — وقارئ
        //    السجلّ يحتاج التفريق بينهما لا مجرّد معرفة أن أحداً بتّ.
        ["ApplyLeaveDeduction"] = "حسم إجازة من كشف الرواتب",
        ["WaiveLeaveDeduction"] = "صرف النظر عن حسم إجازة",

        // ── المستخدمون والمصادقة ──
        ["Login"] = "تسجيل دخول",
        ["LoginLocked"] = "قفل حساب بعد محاولات فاشلة",
        ["ChangePassword"] = "تغيير كلمة المرور",
        ["ResetPassword"] = "إعادة تعيين كلمة المرور",
        ["Delegate"] = "منح تفويض اعتماد",
        ["RevokeDelegation"] = "إلغاء تفويض اعتماد",

        // ── التحقق العامّ من الكتب (ADR-043) ──
        // 🔴 **فاعلُهما مجهولٌ عمداً**: المتحقِّق جهةٌ خارجية بلا حساب، فيُكتب السطر بلا
        //    `UserId` — سابقةُ سطور الدخول نفسها. وقيمةُ السطر أنه **يجعل كل وصولٍ مرئياً**.
        ["VerifyScan"] = "فحص كتاب برمز التحقق",
        ["PublicPdfDownload"] = "تنزيل كتاب من صفحة التحقق",

        // ── النسخ الاحتياطي ──
        ["Backup"] = "نسخة احتياطية",
        ["BackupSchedule"] = "ضبط جدولة النسخ",
        ["DeleteBackup"] = "حذف نسخة احتياطية",
        ["Restore"] = "استعادة نسخة",
        ["Mirror"] = "مرآة إلى قرص خارجي",
        ["RestoreMirror"] = "استعادة من المرآة",

        // ── الموظفون ──
        ["Terminate"] = "إنهاء خدمة",
        ["UnlinkEmployee"] = "فكّ إسناد موظف عن شركة",
        ["ReadEmploymentTemplate"] = "قراءة قالب شروط العمل",
        ["CreateLeave"] = "تسجيل إجازة",
        ["ReviewLeave"] = "البتّ في إجازة",
        ["DeleteLeave"] = "حذف إجازة",

        // ── الرواتب ──
        ["GeneratePayroll"] = "توليد كشف رواتب",
        ["SavePayroll"] = "حفظ كشف رواتب",
        ["PayPayroll"] = "تسديد رواتب",
        ["UpdatePayrollSettings"] = "تعديل إعدادات الكشف",
        ["AmendPaidPayroll"] = "تعديل شهر مُسدَّد",
        ["ConfirmExternalPayment"] = "تعليم: مدفوع من شركة أخرى",
        ["ConfirmPayHere"] = "حسم: يُصرف من هذه الشركة",
        ["AcknowledgeReceipt"] = "إقرار باستلام إيصال",
    };

    /// <summary>أنواع الكيانات المعروفة ← عربيّتها. المفتاح هو ما يُكتب في <c>AuditLog.EntityType</c>.</summary>
    /// <remarks>
    /// ⚠️ يشمل قيم <c>OwnerType</c> لأن <c>AttachmentService</c> يكتب <c>ownerType.ToString()</c>
    /// لا <c>nameof(كيان)</c> — فـ«Outgoing» و«OutgoingBook» **كلاهما يَرِد فعلاً**.
    /// </remarks>
    public static readonly IReadOnlyDictionary<string, string> Entities = new Dictionary<string, string>(StringComparer.Ordinal)
    {
        ["OutgoingBook"] = "كتاب صادر",
        ["IncomingBook"] = "كتاب وارد",
        ["ArchiveDoc"] = "أضبارة أرشيف",
        ["Company"] = "شركة",
        ["Department"] = "قسم",
        ["Entity"] = "جهة",
        ["Template"] = "قالب",
        ["DocumentType"] = "نوع مستند",
        ["ExchangeRate"] = "سعر صرف",
        ["User"] = "مستخدم",
        ["ApprovalDelegation"] = "تفويض اعتماد",
        ["BackupRecord"] = "نسخة احتياطية",
        ["BackupSchedule"] = "جدولة النسخ",
        ["Employee"] = "موظف",
        ["EmployeeCompany"] = "إسناد موظف لشركة",
        ["EmployeeLeave"] = "إجازة",
        ["PayrollPeriod"] = "كشف رواتب",
        ["PayrollEntry"] = "سطر راتب",
        ["HrSettings"] = "إعدادات الموظفين والرواتب",

        ["DmsTask"] = "مهمة",

        // قيم OwnerType كما يكتبها AttachmentService
        ["Outgoing"] = "كتاب صادر",
        ["Incoming"] = "كتاب وارد",
        ["Archive"] = "أضبارة أرشيف",
        ["Task"] = "مهمة",
    };

    /// <summary>عربيّة الفعل، أو الفعل نفسه إن لم يُعرف (لا يُخفى أبداً).</summary>
    public static string Action(string? action)
        => string.IsNullOrWhiteSpace(action) ? "—"
         : Actions.TryGetValue(action, out var label) ? label : action;

    /// <summary>عربيّة نوع الكيان، أو النوع نفسه إن لم يُعرف (لا يُخفى أبداً).</summary>
    public static string Entity(string? entityType)
        => string.IsNullOrWhiteSpace(entityType) ? "—"
         : Entities.TryGetValue(entityType, out var label) ? label : entityType;

    /// <summary>نوع الكيان الذي تُكتب عليه أحداث المصادقة — الفاعل فيها يسكن <c>EntityId</c>.</summary>
    public const string UserEntityType = "User";

    /// <summary>
    /// **الفاعل الحقيقي** لسطر تدقيق: <c>UserId</c> إن وُجد، وإلا صاحبُ الحدث في أحداث المصادقة.
    /// </summary>
    /// <remarks>
    /// 🔴 **لماذا يلزم هذا أصلاً؟** لأن <c>AuditService</c> يكتب <c>UserId = current.UserId</c>،
    /// و**عند تسجيل الدخول لا مستخدمَ مصادَقاً بعد** — فكل أحداث الدخول تُكتب بـ<c>UserId = null</c>
    /// والفاعل في <c>EntityId</c>. النتيجة قبل هذا الإصلاح: تقرير النشاط يعرض «—» في
    /// **أكثر الأحداث دلالةً أمنياً** (188 سطراً في قاعدة العمل عند أول قياس)، أي أن سؤال
    /// «مَن دخل؟» — وهو أول ما يُسأل عند الاشتباه — لم يكن له جواب.
    ///
    /// ⚠️ **والفلترة بالمستخدم تتبع القاعدة نفسها** في <c>ReportService.FilteredLogs</c>، وإلا
    /// عُرض سطرٌ باسم فلانٍ ثم اختفى حين يُفلتَر بفلان — وتناقضٌ كهذا يُفقد التقريرَ ثقتَه كلَّها.
    ///
    /// ⚠️ **ولا نستنتج الفاعل من `EntityId` لغير أحداث المستخدمين**: «حذف الكتاب 12» فاعلُه
    /// ليس الكتاب 12. الشرط <c>EntityType == "User"</c> ليس تفصيلاً بل هو كلُّ الأمان هنا.
    /// </remarks>
    public static int? ActorUserId(int? userId, string? entityType, string? entityId)
    {
        if (userId is not null) return userId;
        if (!string.Equals(entityType, UserEntityType, StringComparison.Ordinal)) return null;
        return int.TryParse(entityId, out var id) ? id : null;
    }
}
