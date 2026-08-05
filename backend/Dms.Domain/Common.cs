namespace Dms.Domain;

// ---------------------------------------------------------------------------
// استثناءات المجال — تُترجَم إلى أكواد HTTP في الـ middleware.
// ---------------------------------------------------------------------------
public abstract class DomainException(string message) : Exception(message);

/// <summary>طلب غير صالح / خرق قاعدة عمل (400).</summary>
public sealed class ValidationException(string message) : DomainException(message);

/// <summary>غير موجود (404).</summary>
public sealed class NotFoundException(string message) : DomainException(message);

/// <summary>ممنوع — صلاحية غير كافية (403).</summary>
public sealed class ForbiddenException(string message) : DomainException(message);

/// <summary>تعارض حالة (409) — مثل تعديل نسخة قديمة أو رقم مكرر.</summary>
public sealed class ConflictException(string message) : DomainException(message);

// ---------------------------------------------------------------------------
// حساب المعادل بالدينار العراقي (يُجمَّد على الكتاب لحظة الإنشاء/الاعتماد).
// ---------------------------------------------------------------------------
public static class FinancialCalculator
{
    /// <summary>
    /// إذا العملة دولار → المبلغ × سعر الصرف (إلزامي)؛ إذا دينار → المبلغ مباشرة.
    /// يرمي ValidationException عند نقص سعر الصرف للدولار.
    /// </summary>
    public static decimal? ComputeIqd(decimal? amount, Currency? currency, decimal? rate)
    {
        if (amount is null) return null;
        if (currency is null)
            throw new ValidationException("العملة مطلوبة عند إدخال مبلغ.");

        if (currency == Currency.USD)
        {
            if (rate is null or <= 0)
                throw new ValidationException("سعر الصرف إلزامي وموجب عند اختيار الدولار.");
            return decimal.Round(amount.Value * rate.Value, 2);
        }
        return decimal.Round(amount.Value, 2);
    }
}

// ---------------------------------------------------------------------------
// التسلسل الهرمي للأدوار: كل مستوى يدير المستويات الأدنى منه فقط.
// ---------------------------------------------------------------------------
public static class RoleHierarchy
{
    /// <summary>هل يستطيع <paramref name="actor"/> إدارة مستخدم بدور <paramref name="target"/>؟ (الأدنى فقط)</summary>
    public static bool CanManage(UserRole actor, UserRole target) => (int)actor < (int)target;

    /// <summary>المدير فأعلى يملك صلاحية الاعتماد افتراضياً.</summary>
    public static bool IsManagerOrAbove(UserRole role) => (int)role <= (int)UserRole.Manager;

    /// <summary>رئيس الشركة فأعلى (لإدارة الشركات/الترقيم).</summary>
    public static bool IsPresidentOrAbove(UserRole role) => (int)role <= (int)UserRole.President;

    /// <summary>الموظف فأعلى — أي دورٍ عدا **القارئ** (ADR-025).</summary>
    /// <remarks>
    /// حدُّ وحدتَي الموظفين والرواتب بعد فتحهما لمن دون المدير (قرار المالك 2026-08-05).
    /// ⚠️ **والقارئ يبقى محجوباً بالدور لا بالإعداد:** دورُه اطّلاعٌ لا معالجة
    /// (<c>rules/security.md</c>)، والرواتب أحسّ بيانات في النظام — فمنحُها له سهواً من
    /// شاشة المستخدمين كان يكشف رواتب الشركة كلها لمن لا يملك حتى الإحالة.
    /// </remarks>
    public static bool IsEmployeeOrAbove(UserRole role) => role != UserRole.Reader;
}
