namespace Dms.Domain;

/// <summary>
/// كتاب صادر. يبدأ مسودّة بلا رقم؛ عند الاعتماد يأخذ رقماً رسمياً + PDF + QR موقّع ويُقفل.
/// التعديل بعد الاعتماد للمدير فأعلى مع حفظ إصدار وإعادة توليد PDF/QR.
/// </summary>
public class OutgoingBook
{
    public int OutgoingId { get; set; }
    public int CompanyId { get; set; }

    // الترقيم الرسمي (يُملأ عند الاعتماد فقط)
    public string? Number { get; set; }     // DEN-2026-00124
    public int? Year { get; set; }          // سنة الاعتماد
    public int? SerialNo { get; set; }      // التسلسل ضمن (الشركة + السنة)

    public DateTime Date { get; set; }      // تاريخ الكتاب
    public int EntityId { get; set; }       // الجهة المستلمة
    public string Subject { get; set; } = string.Empty;
    public string? HeaderPhrase { get; set; } // حقل اختياري (إلى، أمر إداري، إلخ)
    public string? SignatoryName { get; set; } // اسم الموقّع
    public string? SignatoryTitle { get; set; } // عنوان الموقّع الوظيفي
    public string BodyHtml { get; set; } = string.Empty;

    /// <summary>محتوى المحرر كـ Quill Delta (JSON) — مصدر التحرير لاستعادة التنسيق بدقة تامة. (HTML للطباعة.)</summary>
    public string? BodyJson { get; set; }

    public int? TemplateId { get; set; }
    public BookStatus Status { get; set; } = BookStatus.Draft;

    /// <summary>نوع الكتاب (كتاب رسمي · فاتورة · عرض سعر …) — تصنيفٌ للفلترة والعرض (ADR-057).</summary>
    /// <remarks>
    /// ⚠️ **اختياريّ عمداً** في القاعدة: الكتب السابقة للميزة أُسندت إلى «كتاب رسمي» بالمهاجرة، والعلاقة
    /// الاختيارية تُقرأ بـ<c>LEFT JOIN</c> — فلا يحذف الفلترُ العامّ على الأنواع الكتابَ من القائمة (درس ADR-034).
    /// </remarks>
    public int? OutgoingBookTypeId { get; set; }
    public OutgoingBookType? OutgoingBookType { get; set; }

    // ── خيارات الطباعة لكل كتاب (ADR-057) — الجهة والموضوع يبقيان مسجَّلَين، والخيار يتحكّم في طباعتهما وحدها ──
    /// <summary>طباعة سطر الجهة.</summary>
    public bool PrintEntity { get; set; } = true;
    /// <summary>طباعة سطر «الموضوع / …».</summary>
    public bool PrintSubject { get; set; } = true;
    /// <summary>«صفحة 1 من 5» أسفل كل صفحة (ولا ترقيم في الكتاب ذي الصفحة الواحدة).</summary>
    public bool PageNumbers { get; set; } = true;
    /// <summary>في أيّ صفحاتٍ يُطبع التوقيع والختم.</summary>
    public SignaturePlacement SignaturePlacement { get; set; } = SignaturePlacement.LastPage;

    // الحقول المالية
    public decimal? Amount { get; set; }
    public Currency? Currency { get; set; }
    public decimal? ExchangeRate { get; set; }
    public decimal? AmountInIqd { get; set; }   // مُجمَّد لحظة الإنشاء/الاعتماد

    // QR موقّع + الـ PDF المولّد
    public string? QrContent { get; set; }      // المحتوى الموقّع الكامل المطبوع في الـ QR
    public string? QrSignature { get; set; }    // التوقيع وحده (للأرشفة/المراجعة)
    public string? GeneratedPdfBlobKey { get; set; }

    public int CreatedByUserId { get; set; }
    public DateTime CreatedAt { get; set; }
    public int? ApprovedByUserId { get; set; }
    public DateTime? ApprovedAt { get; set; }
    public DateTime? UpdatedAt { get; set; }

    // حذف ناعم
    public bool IsDeleted { get; set; }
    public int? DeletedByUserId { get; set; }
    public DateTime? DeletedAt { get; set; }

    /// <summary>الكتب الواردة التي يردّ عليها هذا الصادر — **واحدٌ أو أكثر** (ADR-045).</summary>
    /// <remarks>
    /// ⚠️ **حلّ محلّ `ReplyToIncomingId` المفرد**: كتابٌ صادرٌ واحد يُجيب عدّة واردات عن
    /// القضية نفسها، وعمودٌ واحد كان يترك البقيّة **بلا ردٍّ مسجَّل**.
    /// </remarks>
    public ICollection<BookReply> RepliesTo { get; set; } = new List<BookReply>();

    /// <summary>المعاملة التي ينتمي إليها هذا الكتاب — **واحدةٌ أو لا شيء** (ADR-045).</summary>
    public int? CaseFileId { get; set; }

    /// <summary>للتزامن المتفائل عند التعديل بعد الاعتماد.</summary>
    public byte[]? RowVersion { get; set; }

    public Entity? Entity { get; set; }
    public Template? Template { get; set; }
}
