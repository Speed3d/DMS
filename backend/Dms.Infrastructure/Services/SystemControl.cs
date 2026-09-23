using System.Text.Json;
using System.Text.Json.Serialization;
using Dms.Domain;
using Microsoft.Extensions.Logging;

namespace Dms.Infrastructure.Services;

/// <summary>حالة إيقاف النظام عن المستخدمين (ADR-050).</summary>
public sealed record LockdownState(bool Active, string? Message, DateTime? SinceUtc, int? ByUserId, string? ByName)
{
    public static readonly LockdownState Off = new(false, null, null, null, null);
}

/// <summary>حالة شريط الإعلان العلويّ (ADR-050) — مستقلٌّ عن الإيقاف بقرار المالك.</summary>
public sealed record AnnouncementState(bool Visible, string? Text, AnnouncementKind Kind, DateTime? UpdatedAtUtc)
{
    public static readonly AnnouncementState Hidden = new(false, null, AnnouncementKind.Info, null);
}

/// <summary>تغيّرٌ في الإيقاف لم يأتِ من الـAPI (أمر الطوارئ على السيرفر) — ليُدوَّن في التدقيق.</summary>
public sealed record ExternalLockdownChange(LockdownState Before, LockdownState After);

/// <summary>
/// إيقاف النظام وشريط الإعلان — **حالةٌ في ملفّ على قرص السيرفر** (ADR-050).
/// </summary>
/// <remarks>
/// 🔴 **لماذا ملفٌّ لا ذاكرة ولا قاعدة؟**
/// <list type="bullet">
/// <item>**الذاكرة تزول بإعادة التشغيل** — والتحديث نفسه إعادةُ تشغيل، فيعود النظام مفتوحاً
///   للجميع قبل أن يفحص المالك التحديث. (هذا عيبُ <see cref="IMaintenanceState"/> لو استُعمل هنا.)</item>
/// <item>**القاعدة تستبدلها الاستعادة** — فتُلغي الإيقاف أو تُعيد إيقافاً قديماً.</item>
/// <item>**أمرُ الطوارئ على السيرفر يكتبه** ولو كانت القاعدة معطّلة.</item>
/// </list>
/// ⚠️ **ملفٌّ تالف يفشل مغلقاً**: يُعدّ النظام موقوفاً — ولا يُحتجز أحدٌ خارجه لأن السوبر أدمن
/// يدخل دائماً، فيُصلحه بحفظٍ من الإعدادات.
/// </remarks>
public interface ISystemControl
{
    LockdownState Lockdown { get; }
    AnnouncementState Announcement { get; }

    /// <summary>مسار الملفّ — للسجلّ وللتشخيص.</summary>
    string FilePath { get; }

    IReadOnlyList<string> SavedTexts(SavedTextKind kind);

    /// <summary>يوقف النظام أو يشغّله. الرسالة **مطلوبةٌ عند الإيقاف**.</summary>
    LockdownState SetLockdown(bool active, string? message, int? byUserId, string? byName);

    /// <summary>يُظهر الشريط أو يُخفيه. النصّ **مطلوبٌ عند الإظهار**، ويبقى محفوظاً عند الإخفاء.</summary>
    AnnouncementState SetAnnouncement(bool visible, string? text, AnnouncementKind kind);

    /// <summary>يحفظ نصّاً للاستعمال لاحقاً (بلا تكرار). يعيد القائمة بعد الإضافة.</summary>
    IReadOnlyList<string> AddSavedText(SavedTextKind kind, string text);

    /// <summary>يحذف نصّاً محفوظاً. يعيد <c>false</c> إن لم يوجد.</summary>
    bool RemoveSavedText(SavedTextKind kind, string text);

    /// <summary>
    /// يعيد قراءة الملفّ **إن تغيّر من خارج هذه العملية** — يُنادى دورياً من المراقب.
    /// </summary>
    /// <returns>تغيّرُ الإيقاف إن وقع، وإلا <c>null</c>.</returns>
    ExternalLockdownChange? ReloadIfChangedExternally();
}

public sealed class SystemControl : ISystemControl
{
    private static readonly JsonSerializerOptions Json = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        Converters = { new JsonStringEnumConverter() },
        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    private readonly object _gate = new();
    private readonly ILogger<SystemControl>? _logger;
    private Document _doc;
    private DateTime? _lastSeenWriteUtc;

    public string FilePath { get; }

    public SystemControl(string filePath, ILogger<SystemControl>? logger = null)
    {
        FilePath = filePath;
        _logger = logger;
        _doc = Load(out _lastSeenWriteUtc);
    }

    public LockdownState Lockdown { get { lock (_gate) return _doc.Lockdown; } }
    public AnnouncementState Announcement { get { lock (_gate) return _doc.Announcement; } }

    public IReadOnlyList<string> SavedTexts(SavedTextKind kind)
    {
        lock (_gate) return [.. ListOf(_doc, kind)];
    }

    public LockdownState SetLockdown(bool active, string? message, int? byUserId, string? byName)
    {
        var text = SystemAccess.NormalizeText(message, required: active, "نصّ رسالة الإيقاف");
        lock (_gate)
        {
            var next = active
                ? new LockdownState(true, text,
                    // إعادةُ حفظٍ والنظام موقوف (تعديل الرسالة) لا تُصفّر مدّة الإيقاف.
                    _doc.Lockdown.Active ? _doc.Lockdown.SinceUtc : DateTime.UtcNow,
                    byUserId, byName)
                : LockdownState.Off;
            Save(_doc with { Lockdown = next });
            return next;
        }
    }

    public AnnouncementState SetAnnouncement(bool visible, string? text, AnnouncementKind kind)
    {
        var t = SystemAccess.NormalizeText(text, required: visible, "نصّ الشريط");
        if (!Enum.IsDefined(kind)) throw new ValidationException("نوع الشريط غير معروف.");
        lock (_gate)
        {
            // ⚠️ **الإخفاء لا يمحو النصّ** — فيُعاد إظهارُه بضغطةٍ واحدة.
            var next = new AnnouncementState(visible, t ?? _doc.Announcement.Text, kind, DateTime.UtcNow);
            Save(_doc with { Announcement = next });
            return next;
        }
    }

    public IReadOnlyList<string> AddSavedText(SavedTextKind kind, string text)
    {
        var t = SystemAccess.NormalizeText(text, required: true, "النصّ")!;
        lock (_gate)
        {
            var list = ListOf(_doc, kind);
            if (list.Contains(t)) return [.. list];
            if (list.Count >= SystemAccess.MaxSavedTexts)
                throw new ValidationException($"بلغت النصوص المحفوظة حدّها ({SystemAccess.MaxSavedTexts}). احذف نصّاً قديماً أولاً.");
            var updated = new List<string>(list) { t };
            Save(WithList(_doc, kind, updated));
            return updated;
        }
    }

    public bool RemoveSavedText(SavedTextKind kind, string text)
    {
        lock (_gate)
        {
            var list = ListOf(_doc, kind);
            var updated = list.Where(x => x != text).ToList();
            if (updated.Count == list.Count) return false;
            Save(WithList(_doc, kind, updated));
            return true;
        }
    }

    public ExternalLockdownChange? ReloadIfChangedExternally()
    {
        lock (_gate)
        {
            var stamp = WriteStamp();
            if (stamp == _lastSeenWriteUtc) return null;

            var before = _doc.Lockdown;
            _doc = Load(out _lastSeenWriteUtc);
            var after = _doc.Lockdown;
            _logger?.LogInformation("أُعيدت قراءة ملفّ حالة النظام بعد تغيّره من الخارج: {Path}", FilePath);
            return before.Active != after.Active || before.Message != after.Message
                ? new ExternalLockdownChange(before, after)
                : null;
        }
    }

    // ───────────────────────── الملفّ ─────────────────────────

    private DateTime? WriteStamp()
        => File.Exists(FilePath) ? File.GetLastWriteTimeUtc(FilePath) : null;

    private Document Load(out DateTime? stamp)
    {
        stamp = WriteStamp();
        if (stamp is null) return Document.Empty;
        try
        {
            var doc = JsonSerializer.Deserialize<Document>(File.ReadAllText(FilePath), Json)
                ?? throw new JsonException("ملفٌّ فارغ");
            return doc.Normalized();
        }
        catch (Exception ex) when (ex is JsonException or IOException or UnauthorizedAccessException or NotSupportedException)
        {
            // 🔴 **يفشل مغلقاً**: لا نعرف أكان النظام موقوفاً — فنفترض أنه كذلك.
            _logger?.LogError(ex, "تعذّرت قراءة ملفّ حالة النظام {Path} — يُعدّ النظام موقوفاً حتى يُحفظ من الإعدادات.", FilePath);
            return Document.Empty with
            {
                Lockdown = new LockdownState(true, SystemAccess.DefaultLockdownMessage, DateTime.UtcNow, null, null),
            };
        }
    }

    /// <summary>كتابةٌ ذرّية: ملفٌّ مؤقت ثم استبدال — فلا يقرأ أحدٌ نصفَ ملفّ.</summary>
    private void Save(Document doc)
    {
        var dir = Path.GetDirectoryName(FilePath);
        if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);

        var tmp = FilePath + ".tmp";
        File.WriteAllText(tmp, JsonSerializer.Serialize(doc, Json));
        File.Move(tmp, FilePath, overwrite: true);

        _doc = doc;
        _lastSeenWriteUtc = WriteStamp();
    }

    private static List<string> ListOf(Document d, SavedTextKind kind)
        => kind == SavedTextKind.Lockdown ? d.SavedLockdownTexts : d.SavedAnnouncementTexts;

    private static Document WithList(Document d, SavedTextKind kind, List<string> list)
        => kind == SavedTextKind.Lockdown ? d with { SavedLockdownTexts = list } : d with { SavedAnnouncementTexts = list };

    /// <summary>شكل الملفّ على القرص.</summary>
    private sealed record Document(
        LockdownState Lockdown,
        AnnouncementState Announcement,
        List<string> SavedLockdownTexts,
        List<string> SavedAnnouncementTexts)
    {
        public static readonly Document Empty = new(LockdownState.Off, AnnouncementState.Hidden, [], []);

        /// <summary>ملفٌّ كُتب يدوياً قد تنقصه حقول — نملؤها ولا نسقط.</summary>
        public Document Normalized() => new(
            Lockdown ?? LockdownState.Off,
            Announcement ?? AnnouncementState.Hidden,
            SavedLockdownTexts ?? [],
            SavedAnnouncementTexts ?? []);
    }
}
