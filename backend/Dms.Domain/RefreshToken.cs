namespace Dms.Domain;

/// <summary>رمز تحديث (يُخزَّن مجزّأً) لتجديد جلسة الدخول بأمان مع التدوير.</summary>
public class RefreshToken
{
    public int RefreshTokenId { get; set; }
    public int UserId { get; set; }
    public string TokenHash { get; set; } = string.Empty;
    public DateTime ExpiresAt { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? RevokedAt { get; set; }

    public bool IsActive => RevokedAt is null && DateTime.UtcNow < ExpiresAt;
}
