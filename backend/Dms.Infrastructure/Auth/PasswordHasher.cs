namespace Dms.Infrastructure.Auth;

/// <summary>تجزئة كلمات المرور بـ BCrypt (مع salt تلقائي).</summary>
public interface IPasswordHasher
{
    string Hash(string password);
    bool Verify(string password, string hash);
}

public sealed class BCryptPasswordHasher : IPasswordHasher
{
    public string Hash(string password) => BCrypt.Net.BCrypt.HashPassword(password, workFactor: 12);

    public bool Verify(string password, string hash)
    {
        try { return BCrypt.Net.BCrypt.Verify(password, hash); }
        catch { return false; }
    }
}
