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
public sealed class BookRenderer(IFileStorage storage, IOptions<QrSigningOptions> qrOptions, TemplateAssetCache assets)
{
    private readonly QrSigningOptions _qr = qrOptions.Value;
    private readonly PdfGenerator _pdf = new();
    private readonly WordExporter _word = new();

    public async Task<PdfRenderResult> RenderPdfAsync(
        OutgoingBook book, Template template, Entity entity, Company company, bool isPreview = false, CancellationToken ct = default)
    {
        var model = ToModel(book, entity, company);

        // توقيع محتوى الـ QR (يتطلب رقماً رسمياً — متاح بعد الاعتماد)
        string qrContent = string.Empty;
        string signature = string.Empty;
        byte[]? qrPng = null;

        if (!isPreview)
        {
            qrContent = QrSigner.CreateQrContent(model, _qr.PrivateKeyBase64);
            signature = qrContent[(qrContent.LastIndexOf('|') + 1)..];
            qrPng = QrSigner.CreateQrPng(qrContent);
        }

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
        HeaderPhrase = book.HeaderPhrase,
        SignatoryName = book.SignatoryName,
        SignatoryTitle = book.SignatoryTitle,
        Subject = book.Subject,
        Body = book.BodyHtml ?? "",
        Amount = book.Amount,
        Currency = book.Currency?.ToString(),
        ExchangeRate = book.ExchangeRate,
    };

    // Hint: صور القالب ثابتة، فتُخزَّن مؤقتاً بمفتاح التخزين نفسه — وهو يحمل Guid فريداً لكل
    // رفع، فيُبطل نفسه تلقائياً عند تحديث الصورة (انظر TemplateAssetCache).

    private Task<byte[]> LoadOrPlaceholderAsync(string? key, Func<byte[]> placeholder, CancellationToken ct)
        => key is null
            ? Task.FromResult(placeholder())
            : assets.GetOrAddAsync(key, async () =>
                await storage.ExistsAsync(key, ct) ? await storage.ReadAsync(key, ct) : placeholder());

    private Task<byte[]> LoadWatermarkAsync(Template template, CancellationToken ct)
    {
        var key = template.WatermarkImageKey;
        if (key is null)
            return Task.FromResult(PlaceholderImages.CreateWatermark(template.WatermarkOpacity));

        // الشفافية جزء من الناتج المُعالَج، فتدخل في المفتاح: تغييرها وحدها يُنتج صورة مختلفة.
        return assets.GetOrAddAsync($"{key}|op{template.WatermarkOpacity}", async () =>
            await storage.ExistsAsync(key, ct)
                ? ImageOps.ApplyOpacity(await storage.ReadAsync(key, ct), template.WatermarkOpacity)
                : PlaceholderImages.CreateWatermark(template.WatermarkOpacity));
    }
}
