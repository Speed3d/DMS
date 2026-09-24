using System.Text.RegularExpressions;

namespace Dms.Domain;

/// <summary>
/// طلبُ إنشاءٍ أرسله العميل بمفتاحٍ فريد — **يمنع أن يُنشأ الكتاب نفسه مرّتين** (ADR-051).
/// </summary>
/// <remarks>
/// 🔴 **السيناريو الذي يحرسه:** يضغط الموظف «حفظ» فيصل الطلب ويُنشأ الكتاب، **ثم ينقطع
/// الاتصال قبل أن يعود الردّ**. فتبقى المسوّدة عنده بحالة «لم تُرسَل»، ويضغط «إرسال» بعد
/// عودة الاتصال — **فيُنشأ كتابٌ ثانٍ برقمٍ ثانٍ**. والمفتاح يجعل الطلب الثاني يعيد الأوّل.
///
/// ⚠️ **بلا مفتاحٍ أجنبيّ نحو الشركة عمداً** — حذفُ الشركة يمحو صفوفها صراحةً، ولا نريد
/// قيداً يُسقط الحذف. و<c>CompanyId</c> للعزل الصفّيّ وحده.
/// ⚠️ **وحذفُه فعليّ** بعد 30 يوماً — إيصالٌ تقنيّ لا سجلٌّ مؤسَّسيّ (السجلّ في <c>AuditLog</c>).
/// </remarks>
public class ClientRequest
{
    public long ClientRequestId { get; set; }

    /// <summary>صاحب الطلب — **المفتاح فريدٌ لكل مستخدم** لا للنظام، فلا يصطدم مستخدمان.</summary>
    public int UserId { get; set; }

    public int CompanyId { get; set; }

    /// <summary>ما يولّده العميل (معرّف المسوّدة + اللاحقة).</summary>
    public string Key { get; set; } = string.Empty;

    /// <summary>نوع ما أُنشئ — مفتاحٌ واحد لا يخدم نوعين.</summary>
    public string EntityType { get; set; } = string.Empty;

    /// <summary><c>null</c> ⇒ الإنشاء جارٍ (أو انقطع في منتصفه).</summary>
    public int? EntityId { get; set; }

    public DateTime CreatedAt { get; set; }
}

/// <summary>قواعد مفتاح منع التكرار — نقيّةٌ تُختبر.</summary>
public static class IdempotencyKey
{
    public const string HeaderName = "Idempotency-Key";
    public const int MaxLength = 80;

    /// <summary>
    /// حجزٌ بلا نتيجةٍ أقدمُ من هذا يُعدّ **منقطعاً** (سقط الخادم في منتصف الإنشاء) فيُعاد.
    /// </summary>
    public static readonly TimeSpan StaleReservation = TimeSpan.FromMinutes(2);

    /// <summary>المفتاح يُحفظ في التنظيف بعد هذه المدّة.</summary>
    public static readonly TimeSpan Retention = TimeSpan.FromDays(30);

    private static readonly Regex Allowed = new("^[A-Za-z0-9:_-]+$", RegexOptions.Compiled);

    /// <summary>
    /// ينظّف المفتاح — <c>null</c> إن غاب (فيجري الإنشاء كالمعتاد بلا حماية)، ويرمي إن كان مشوَّهاً.
    /// </summary>
    public static string? Normalize(string? raw)
    {
        var k = raw?.Trim();
        if (string.IsNullOrEmpty(k)) return null;
        if (k.Length > MaxLength || !Allowed.IsMatch(k))
            throw new ValidationException("مفتاح منع التكرار غير صالح.");
        return k;
    }
}
