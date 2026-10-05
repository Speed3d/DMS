using Dms.Documents.Images;
using Dms.Documents.Models;
using Dms.Documents.Pdf;
using Dms.Documents.Security;
using Dms.Domain.BookTables;
using Dms.Infrastructure.Documents;
using Xunit;

namespace Dms.Tests;

/// <summary>
/// 🔴 **لا صفحةَ أخيرة فيها التوقيع وحده** (بلاغ المالك 2026-10-05): مسحٌ لأطوالٍ من النصّ والجداول كان يُخرج في نمط
/// «الأخيرة وحدها» **33 حالةً من 112** صفحتُها الأخيرة بلا نصّ. والحارس يقيس من الرسم نفسه (صفحة نهاية المتن مقابل
/// عدد الصفحات). ومع <c>DMS_SWEEP_OUT</c> تُكتب الملفات لفحصها بالعين أو بـPyMuPDF.
/// </summary>
public class SignaturePageTests
{
    private static readonly DocumentAssets Assets = new(PlaceholderImages.CreateHeader(), PlaceholderImages.CreateFooter(),
        PlaceholderImages.CreateWatermark(), QrSigner.CreateQrPng("https://dms.example/v/test"));

    private const string Para =
        "<p>هذا نصٌّ تجريبيّ في متن الكتاب يمتدّ على سطرٍ أو أكثر ليملأ الصفحة ويختبر انتقال المحتوى بين الصفحات عند تغيير موضع التوقيع.</p>";

    private static BookDocument Book(int paras, int rows, PrintSignatureMode mode)
    {
        var list = new List<TableRow> { T.R(T.C("ت"), T.C("المادة"), T.C("السعر")) };
        for (var i = 1; i <= rows; i++) list.Add(T.R(T.C($"{i}"), T.C("مادة"), T.C("1,000")));
        var t1 = T.Table(3, 1, [.. list]);
        var t2 = T.Table(2, 1, T.R(T.C("أ"), T.C("ب")), T.R(T.C("1"), T.C("2")), T.R(T.C("3"), T.C("4")));
        var body = string.Concat(Enumerable.Repeat(Para, paras)) + T.Tag(t1) + Para + T.Tag(t2) + Para;
        return new BookDocument
        {
            CompanyName = "شركة", Number = "DEN-2026-00007", Date = new DateOnly(2026, 10, 4), Entity = "جهة",
            Subject = "اختبار", Body = body, SignatoryName = "المدير", SignatoryTitle = "المدير المفوض",
            Tables = BookTablePrintMapper.Map(body), SignatureMode = mode, PageNumbers = true,
            PrintEntity = true, PrintSubject = true,
        };
    }

    public static TheoryData<int> Paras => new() { 0, 2 };

    /// <summary>أطوالٌ وقعت فيها الصفحة الفارغة قبل العلاج (المسح الكامل 1–28 مرّ مرّةً بصفر حالة — ويطول ثلاث دقائق).</summary>
    private static readonly int[] Rows = [3, 5, 7, 9, 11, 26, 28];

    [Theory]
    [MemberData(nameof(Paras))]
    public void LastPageMode_NeverLeavesTheSignatureAlone_AndNeverAddsAPage(int paras)
    {
        var dir = Environment.GetEnvironmentVariable("DMS_SWEEP_OUT");
        var gen = new PdfGenerator();
        foreach (var rows in Rows)
        {
            var last = gen.Render(Book(paras, rows, PrintSignatureMode.LastPage), Assets);
            var every = gen.Render(Book(paras, rows, PrintSignatureMode.EveryPage), Assets);
            Assert.False(PrintPageRules.SignatureAlone(last.BodyEndPage, last.TotalPages),
                $"فقرات {paras} · صفوف {rows}: المتن ينتهي في {last.BodyEndPage} والصفحات {last.TotalPages}");
            Assert.True(last.TotalPages <= every.TotalPages,
                $"فقرات {paras} · صفوف {rows}: التفريغ لا يزيد الصفحات ({last.TotalPages} مقابل {every.TotalPages})");
            if (!string.IsNullOrEmpty(dir))
            {
                Directory.CreateDirectory(dir);
                File.WriteAllBytes(Path.Combine(dir, $"p{paras}_r{rows:00}_LastPage.pdf"), last.Pdf);
            }
        }
    }

    [Fact]
    public void Probe_ReportsTheBodyEndPage_AndTheTotal()
    {
        var r = new PdfGenerator().Render(Book(0, 60, PrintSignatureMode.EveryPage), Assets);
        Assert.True(r.TotalPages > 1);
        Assert.Equal(r.TotalPages, r.BodyEndPage);   // الحجز في كل صفحة ⟵ المتن يصل إلى الأخيرة
    }

    [Theory]
    [InlineData(0, 0, false)]   // لم يُقَس
    [InlineData(2, 2, false)]
    [InlineData(2, 3, true)]
    public void SignatureAlone_Rule(int bodyEnd, int total, bool alone)
        => Assert.Equal(alone, PrintPageRules.SignatureAlone(bodyEnd, total));
}
