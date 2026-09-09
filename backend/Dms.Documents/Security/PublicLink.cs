using System.Buffers.Binary;
using System.Security.Cryptography;
using System.Text;

namespace Dms.Documents.Security;

/// <summary>
/// رمزُ الرابط العامّ المطبوع في الـQR — **معتِمٌ لا يحمل بياناتٍ تُفكّ**.
/// </summary>
/// <remarks>
/// <para>
/// 🔴 **لماذا رمزٌ معتِم لا حِملٌ موقَّع في الرابط؟** لأن الحِمل — مهما رُمِّز — **يُفكّ
/// بسطرٍ واحد**، فيظهر المبلغ الذي قرّر المالك ألّا يُعرَض. والرمز هنا **لا يحمل شيئاً**:
/// معرّفٌ وبصمة، والصفحةُ وحدها تُقرّر ما تُفصح عنه.
/// </para>
/// <para>
/// ⚠️ **وفائدةٌ ثانية عملية: الطول.** الرابط بهذا الرمز ~52 حرفاً، والحِمل الموقَّع كان
/// سيجعله ~200 — أي رمزاً أكثف بكثير على ورقةٍ مطبوعة بعرض 70 وحدة، **وكاميرا الهاتف
/// تتعثّر فيه**. والغرض كلُّه أن يُمسح من ورقة.
/// </para>
/// <para>
/// 🔑 **ولا سرَّ جديد يُدار**: المفتاح يُشتقّ بـHKDF من **مفتاح توقيع QR الخاص القائم**.
/// فيموت الرمز بموت المفتاح — وهو أصلاً «يُولَّد مرّةً واحدة قبل أول كتاب رسميّ».
/// </para>
/// <para>
/// ⚠️ **والرمز ثابتٌ لثبات المعرّف** — فالتعديل بعد الاعتماد **لا يُبطل الورقة المطبوعة**.
/// </para>
/// </remarks>
public static class PublicLink
{
    /// <summary>طول البصمة — 12 بايتاً (96 بت) تكفي لمنع التخمين وتُبقي الرمز قصيراً.</summary>
    private const int TagBytes = 12;

    /// <summary>الطول الكامل: معرّفٌ (4) + بصمة (12) = 16 بايتاً ⇒ 22 حرفاً بعد الترميز.</summary>
    private const int TokenBytes = sizeof(int) + TagBytes;

    /// <summary>سياقُ الاشتقاق — يفصل هذا المفتاح عن أي استعمالٍ آخر للمفتاح نفسه.</summary>
    private static readonly byte[] DerivationInfo =
        Encoding.UTF8.GetBytes("DMS-public-verify-link-v1");

    /// <summary>يُنشئ رمز الرابط العامّ لكتابٍ بمعرّفه.</summary>
    public static string CreateToken(int bookId, string privateKeyBase64)
    {
        if (bookId <= 0) throw new ArgumentOutOfRangeException(nameof(bookId));

        Span<byte> token = stackalloc byte[TokenBytes];
        BinaryPrimitives.WriteInt32BigEndian(token, bookId);
        ComputeTag(token[..sizeof(int)], privateKeyBase64, token[sizeof(int)..]);

        return Base64Url.Encode(token.ToArray());
    }

    /// <summary>
    /// يفكّ الرمز ويتحقّق من بصمته. <c>false</c> يعني **رمزاً مزوَّراً أو معطوباً**.
    /// </summary>
    /// <remarks>
    /// 🔐 **الفشل قبل أي استعلام** — فرمزٌ مزوَّر **لا يكشف إن كان الكتاب موجوداً**،
    /// ولا فرقَ في زمن الردّ بين رقمٍ قائمٍ وآخر لا وجود له.
    /// </remarks>
    public static bool TryParse(string? token, string privateKeyBase64, out int bookId)
    {
        bookId = 0;
        if (string.IsNullOrWhiteSpace(token)) return false;

        byte[] raw;
        try { raw = Base64Url.Decode(token); }
        catch { return false; }

        if (raw.Length != TokenBytes) return false;

        Span<byte> expected = stackalloc byte[TagBytes];
        try { ComputeTag(raw.AsSpan(0, sizeof(int)), privateKeyBase64, expected); }
        catch { return false; }

        // ⚠️ **مقارنةٌ ثابتة الزمن** — المقارنة العادية تُسرّب طول البادئة الصحيحة
        //    فتسمح ببناء بصمةٍ صالحة بايتاً بايتاً.
        if (!CryptographicOperations.FixedTimeEquals(raw.AsSpan(sizeof(int)), expected))
            return false;

        var id = BinaryPrimitives.ReadInt32BigEndian(raw);
        if (id <= 0) return false;

        bookId = id;
        return true;
    }

    private static void ComputeTag(ReadOnlySpan<byte> idBytes, string privateKeyBase64, Span<byte> tag)
    {
        var key = HKDF.DeriveKey(
            HashAlgorithmName.SHA256,
            ikm: Convert.FromBase64String(privateKeyBase64),
            outputLength: 32,
            salt: null,
            info: DerivationInfo);

        Span<byte> full = stackalloc byte[32];
        HMACSHA256.HashData(key, idBytes, full);
        full[..TagBytes].CopyTo(tag);
    }
}
