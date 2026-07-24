namespace Dms.Infrastructure.Services;

/// <summary>
/// حالة وضع الصيانة (singleton في الذاكرة).
/// Hint: أثناء استعادة نسخة احتياطية تُؤخذ قاعدة البيانات إلى وضع مستخدم-واحد (SINGLE_USER)،
/// فيجب رفض كل طلبات الـ API الجديدة بـ 503 حتى لا تتعارض اتصالاتها مع عملية الاستعادة.
/// الطلب الذي بدأ الاستعادة يكون قد اجتاز الـ middleware قبل تفعيل الوضع، فلا يتأثر.
/// </summary>
public interface IMaintenanceState
{
    bool IsActive { get; }
    string? Reason { get; }
    DateTime? SinceUtc { get; }

    /// <summary>يدخل وضع الصيانة. Hint: استدعِه قبل أي عملية تحتاج وصولاً حصرياً لقاعدة البيانات.</summary>
    void Enter(string reason);

    /// <summary>يخرج من وضع الصيانة. Hint: يجب استدعاؤه دائماً في finally حتى لا يبقى النظام مقفلاً.</summary>
    void Exit();
}

public sealed class MaintenanceState : IMaintenanceState
{
    private volatile bool _active;
    private string? _reason;
    private DateTime? _since;

    public bool IsActive => _active;
    public string? Reason => _reason;
    public DateTime? SinceUtc => _since;

    public void Enter(string reason)
    {
        _reason = reason;
        _since = DateTime.UtcNow;
        _active = true;
    }

    public void Exit()
    {
        _active = false;
        _reason = null;
        _since = null;
    }
}
