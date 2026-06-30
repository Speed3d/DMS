namespace Dms.Infrastructure.Documents;

/// <summary>
/// مفاتيح توقيع الـ QR (ECDSA P-256) — Base64.
/// التطوير: من appsettings. الإنتاج: من Azure Key Vault.
/// </summary>
public sealed class QrSigningOptions
{
    public const string Section = "QrSigning";
    public string PrivateKeyBase64 { get; set; } = string.Empty;
    public string PublicKeyBase64 { get; set; } = string.Empty;
}
