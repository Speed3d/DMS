namespace Dms.Infrastructure.Auth;

public sealed class JwtSettings
{
    public const string Section = "Jwt";

    public string Issuer { get; set; } = "DmsApi";
    public string Audience { get; set; } = "DmsClients";
    public string SigningKey { get; set; } = string.Empty; // سرّي — من config/Key Vault
    public int AccessTokenMinutes { get; set; } = 60;
    public int RefreshTokenDays { get; set; } = 14;
}
