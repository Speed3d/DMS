using Dms.Documents.Images;
using Dms.Documents.Models;
using Dms.Documents.Pdf;
using Dms.Documents.Security;
using Dms.Documents.Storage;
using Dms.Documents.Word;
using Dms.Domain;
using Microsoft.Extensions.Options;

namespace Dms.Infrastructure.Documents;

public sealed record PdfRenderResult(byte[] Pdf, string QrContent, string QrSignature);

/// <summary>
/// يحوّل كتاباً صادراً (مجال) إلى PDF/Word: يبني صور القالب، يوقّع الـ QR، ويولّد الملفات.
/// </summary>
public sealed class BookRenderer(IFileStorage storage, IOptions<QrSigningOptions> qrOptions)
{
    private readonly QrSigningOptions _qr = qrOptions.Value;
    private readonly PdfGenerator _pdf = new();
    private readonly WordExporter _word = new();

    public async Task<PdfRenderResult> RenderPdfAsync(
        OutgoingBook book, Template template, Entity entity, Company company, CancellationToken ct = default)
    {
        var model = ToModel(book, entity, company);

        // توقيع محتوى الـ QR (يتطلب رقماً رسمياً — متاح بعد الاعتماد)
        var qrContent = QrSigner.CreateQrContent(model, _qr.PrivateKeyBase64);
        var signature = qrContent[(qrContent.LastIndexOf('|') + 1)..];
        var qrPng = QrSigner.CreateQrPng(qrContent);

        var assets = new DocumentAssets(
            Header: await LoadOrPlaceholderAsync(template.HeaderImageKey, () => PlaceholderImages.CreateHeader(), ct),
            Footer: await LoadOrPlaceholderAsync(template.FooterImageKey, () => PlaceholderImages.CreateFooter(), ct),
            Watermark: await LoadWatermarkAsync(template, ct),
            QrPng: qrPng);

        var pdf = _pdf.Generate(model, assets);
        return new PdfRenderResult(pdf, qrContent, signature);
    }

    public byte[] RenderWord(OutgoingBook book, Entity entity, Company company)
        => _word.Generate(ToModel(book, entity, company));

    private static BookDocument ToModel(OutgoingBook book, Entity entity, Company company) => new()
    {
        CompanyName = company.Name,
        Number = book.Number ?? "(مسودّة)",
        Date = DateOnly.FromDateTime(book.Date),
        Entity = entity.Name,
        Subject = book.Subject,
        Body = book.BodyHtml,
        Amount = book.Amount,
        Currency = book.Currency?.ToString(),
        ExchangeRate = book.ExchangeRate,
    };

    private async Task<byte[]> LoadOrPlaceholderAsync(string? key, Func<byte[]> placeholder, CancellationToken ct)
        => key is not null && await storage.ExistsAsync(key, ct)
            ? await storage.ReadAsync(key, ct)
            : placeholder();

    private async Task<byte[]> LoadWatermarkAsync(Template template, CancellationToken ct)
    {
        if (template.WatermarkImageKey is not null && await storage.ExistsAsync(template.WatermarkImageKey, ct))
            return ImageOps.ApplyOpacity(await storage.ReadAsync(template.WatermarkImageKey, ct), template.WatermarkOpacity);

        // العلامة البديلة تُبنى بالشفافية مباشرةً
        return PlaceholderImages.CreateWatermark(template.WatermarkOpacity);
    }
}
