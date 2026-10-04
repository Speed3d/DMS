namespace Dms.Domain.BookTables;

/// <summary>
/// «ماذا تغيّر في الجداول؟» — لسجلّ حركة الصادر (ADR-057، قرار المالك: تفاصيل كاملة).
/// </summary>
/// <remarks>
/// 📐 **سطرٌ لكل جدول** («الجدول 2: أُضيف 3 صفوف · حُذف صفّ · تغيّرت 7 خلايا»)، ثم **أوّل عشر خلايا** بالقديم
/// والجديد («البند 3 — السعر الكلي: 1,000,000 ⟵ 1,250,000») ثم «و40 غيرها» — فاتورةٌ تتغيّر فيها خمسون خلية
/// لا تُغرق السجلّ.
/// <para>
/// 🔑 **المطابقة بالمعرّفات لا بالمواضع**: إدراجُ صفٍّ في أعلى الجدول لا يجعل كلَّ ما تحته «متغيّراً».
/// واسمُ الصفّ من عمود الترقيم، واسمُ العمود من صفّ العناوين — كما يقرؤهما الإنسان.
/// </para>
/// </remarks>
public static class BookTableDiff
{
    public const int MaxListedCells = 10;
    private const int MaxValueChars = 60;

    public sealed record Result(IReadOnlyList<string> Summaries, IReadOnlyList<string> CellChanges, int More)
    {
        public bool Any => Summaries.Count > 0;

        /// <summary>نصّ التفاصيل لسجلّ الحركة — أسطرٌ متتالية، أو <c>null</c> إن لم يتغيّر شيء.</summary>
        public string? Details => !Any ? null
            : string.Join("\n", Summaries.Concat(CellChanges).Concat(More > 0 ? [$"و{More} غيرها"] : []));
    }

    public static Result Describe(string? beforeHtml, string? afterHtml)
    {
        var before = SafeRead(beforeHtml);
        var after = SafeRead(afterHtml);
        var summaries = new List<string>();
        var cells = new List<string>();
        var more = 0;
        var many = after.Count > 1 || before.Count > 1;

        for (var i = 0; i < after.Count; i++)
        {
            var a = after[i];
            var n = i + 1;
            var b = before.FirstOrDefault(x => x.Id == a.Id);
            if (b is null)
            {
                summaries.Add($"أُضيف الجدول {n} ({Count(a.Cols.Count, "عمود", "عمودان", "أعمدة", "عموداً")} × {Count(a.Rows.Count, "صفّ", "صفّان", "صفوف", "صفّاً")})");
                continue;
            }

            var parts = new List<string>();
            var addedRows = a.Rows.Count(r => b.Rows.All(x => x.Id != r.Id));
            var removedRows = b.Rows.Count(r => a.Rows.All(x => x.Id != r.Id));
            var addedCols = a.Cols.Count(c => b.Cols.All(x => x.Id != c.Id));
            var removedCols = b.Cols.Count(c => a.Cols.All(x => x.Id != c.Id));
            if (addedRows > 0) parts.Add($"أُضيف {Count(addedRows, "صفّ", "صفّان", "صفوف", "صفّاً")}");
            if (removedRows > 0) parts.Add($"حُذف {Count(removedRows, "صفّ", "صفّان", "صفوف", "صفّاً")}");
            if (addedCols > 0) parts.Add($"أُضيف {Count(addedCols, "عمود", "عمودان", "أعمدة", "عموداً")}");
            if (removedCols > 0) parts.Add($"حُذف {Count(removedCols, "عمود", "عمودان", "أعمدة", "عموداً")}");

            int textChanged = 0, styleChanged = 0;
            var mergeChanged = false;
            for (var r = 0; r < a.Rows.Count; r++)
            {
                var br = b.Rows.FirstOrDefault(x => x.Id == a.Rows[r].Id);
                if (br is null) continue;
                for (var c = 0; c < a.Cols.Count; c++)
                {
                    var bc = b.Cols.FindIndex(x => x.Id == a.Cols[c].Id);
                    if (bc < 0 || c >= a.Rows[r].Cells.Count || bc >= br.Cells.Count) continue;
                    var ac = a.Rows[r].Cells[c];
                    var old = br.Cells[bc];
                    if (ac is null || old is null)
                    {
                        if ((ac is null) != (old is null)) mergeChanged = true;
                        continue;
                    }
                    if (ac.RowSpan != old.RowSpan || ac.ColSpan != old.ColSpan) mergeChanged = true;

                    var at = BookTableCodec.PlainText(ac.Html);
                    var bt = BookTableCodec.PlainText(old.Html);
                    if (at != bt)
                    {
                        textChanged++;
                        if (cells.Count < MaxListedCells)
                            cells.Add($"{(many ? $"الجدول {n} · " : "")}{RowLabel(a, r)} — {ColLabel(a, c)}: {Show(bt)} ⟵ {Show(at)}");
                        else more++;
                    }
                    else if (ac.Html != old.Html || ac.Bg != old.Bg || ac.VAlign != old.VAlign
                             || !Equals(ac.Formula, old.Formula) || !Equals(ac.Words, old.Words))
                        styleChanged++;
                }
            }

            if (textChanged > 0) parts.Add($"تغيّرت {Count(textChanged, "خلية", "خليتان", "خلايا", "خلية")}");
            if (styleChanged > 0) parts.Add($"تنسيق {Count(styleChanged, "خلية", "خليتين", "خلايا", "خلية")}");
            if (mergeChanged) parts.Add("دمج الخلايا");
            if (ShapeChanged(b, a)) parts.Add("شكل الجدول");
            if (parts.Count > 0) summaries.Add($"الجدول {n}: {string.Join(" · ", parts)}");
        }

        for (var i = 0; i < before.Count; i++)
            if (after.All(x => x.Id != before[i].Id))
                summaries.Add($"حُذف الجدول {i + 1}");

        return new Result(summaries, cells, more);
    }

    private static IReadOnlyList<BookTable> SafeRead(string? html)
    {
        try { return BookTableCodec.ReadAll(html); }
        catch (ValidationException) { return []; }   // متنٌ قديمٌ تالف لا يُفشل السجلّ
    }

    private static bool ShapeChanged(BookTable b, BookTable a) =>
        b.Dir != a.Dir || b.WidthPct != a.WidthPct || b.Align != a.Align || b.Border != a.Border
        || b.HeaderRows != a.HeaderRows || b.RepeatHeader != a.RepeatHeader || b.NumberingCol != a.NumberingCol
        || b.Cols.Where(c => a.Cols.Any(x => x.Id == c.Id)).Any(c => a.Cols.First(x => x.Id == c.Id).Weight != c.Weight);

    private static string RowLabel(BookTable t, int r)
    {
        if (r < t.HeaderRows) return "العناوين";
        if (t.NumberingCol is { } nc && nc < t.Rows[r].Cells.Count && t.Rows[r].Cells[nc] is { } cell)
        {
            var v = BookTableCodec.PlainText(cell.Html);
            if (v.Length > 0) return $"البند {Truncate(v, 12)}";
        }
        return $"الصفّ {r + 1}";
    }

    private static string ColLabel(BookTable t, int c)
    {
        if (t.HeaderRows > 0)
            for (var col = c; col >= 0; col--)   // العنوان قد يكون خليةً مدموجةً تبدأ قبل هذا العمود
                if (t.Rows[0].Cells.Count > col && t.Rows[0].Cells[col] is { } h && col + h.ColSpan > c)
                {
                    var v = BookTableCodec.PlainText(h.Html);
                    if (v.Length > 0) return Truncate(v, 30);
                    break;
                }
        return $"العمود {c + 1}";
    }

    private static string Show(string v) => v.Length == 0 ? "(فارغ)" : Truncate(v, MaxValueChars);

    private static string Truncate(string v, int max) => v.Length <= max ? v : v[..max] + "…";

    /// <summary>العدد والمعدود: ١ «صفّ» · ٢ «صفّان» · ٣–١٠ «3 صفوف» · وما سواها «12 صفّاً».</summary>
    internal static string Count(int n, string one, string two, string plural, string many) => n switch
    {
        1 => one,
        2 => two,
        _ => $"{n} {(n % 100 is >= 3 and <= 10 ? plural : many)}",
    };
}
