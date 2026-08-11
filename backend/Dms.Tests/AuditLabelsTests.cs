using System.Reflection;
using System.Text.RegularExpressions;
using Dms.Domain;
using Xunit;

namespace Dms.Tests;

/// <summary>
/// حرّاس ترجمة سجلّ التدقيق. مكتوبة لأن تقرير النشاط **يُقرأ بالعربية**، ومفتاحٌ بلا ترجمة
/// يمرّ صامتاً: لا خطأ بناء ولا استثناء — سطرٌ إنجليزيّ وسط تقريرٍ عربيّ فحسب.
/// </summary>
public class AuditLabelsTests
{
    [Fact]
    public void Action_TranslatesKnownKeys()
    {
        Assert.Equal("اعتماد", AuditLabels.Action("Approve"));
        Assert.Equal("إحالة إلى قسم", AuditLabels.Action("Forward"));
        Assert.Equal("تسديد رواتب", AuditLabels.Action("PayPayroll"));
    }

    [Fact]
    public void Entity_TranslatesKnownKeys()
    {
        Assert.Equal("كتاب صادر", AuditLabels.Entity("OutgoingBook"));
        Assert.Equal("أضبارة أرشيف", AuditLabels.Entity("ArchiveDoc"));
        Assert.Equal("إسناد موظف لشركة", AuditLabels.Entity("EmployeeCompany"));
    }

    // 🔴 **القاعدة الحاكمة: المجهول يُعرَض لا يُخفى.** سجلّ التدقيق سجلٌّ أمنيّ، وإبدالُ فعلٍ
    //    غير مترجَم بـ«غير معروف» **يحذف معلومةً** من تقريرٍ يُقرأ عند الاشتباه.
    [Theory]
    [InlineData("SomeNewActionAddedTomorrow")]
    [InlineData("خطأ_مطبعي")]
    public void Unknown_IsShownVerbatim_NeverHidden(string raw)
    {
        Assert.Equal(raw, AuditLabels.Action(raw));
        Assert.Equal(raw, AuditLabels.Entity(raw));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void Empty_BecomesDash_NotCrash(string? raw)
    {
        Assert.Equal("—", AuditLabels.Action(raw));
        Assert.Equal("—", AuditLabels.Entity(raw));
    }

    [Fact]
    public void EveryLabel_IsArabic_NotAnEnglishPlaceholder()
    {
        // ترجمةٌ منسوخة سهواً («Approve» = «Approve») تمرّ من كل الاختبارات أعلاه.
        foreach (var (key, label) in AuditLabels.Actions)
            Assert.True(Regex.IsMatch(label, @"\p{IsArabic}"), $"الفعل {key} بلا ترجمة عربية: {label}");
        foreach (var (key, label) in AuditLabels.Entities)
            Assert.True(Regex.IsMatch(label, @"\p{IsArabic}"), $"النوع {key} بلا ترجمة عربية: {label}");
    }

    [Fact]
    public void AttachmentOwnerTypes_AreCovered_BecauseServiceWritesEnumNames()
    {
        // ⚠️ `AttachmentService` يكتب `ownerType.ToString()` لا `nameof(كيان)` — فـ«Outgoing»
        //    و«OutgoingBook» **كلاهما يَرِد في السجلّ فعلاً**. نسيانُ صنفٍ منهما يُنتج تقريراً
        //    نصفُ سطوره عربيّ ونصفُه إنجليزيّ.
        foreach (var name in Enum.GetNames<OwnerType>())
            Assert.True(AuditLabels.Entities.ContainsKey(name), $"قيمة OwnerType بلا ترجمة: {name}");
    }

    // 🔴 **الحارس الذي يمنع تقادم القائمة:** يقرأ أسماء كيانات `Dms.Domain` الحقيقية ويطالب
    //    بترجمةٍ لكل ما يُسجَّل عليه تدقيق. كيانٌ جديد يُضاف غداً ويُسجَّل عليه `audit.Add`
    //    سيَظهر في التقرير بالإنجليزية — وهذا الاختبار يُنبّه **قبل** أن يراه المالك.
    [Fact]
    public void KnownAuditedEntities_HaveLabels()
    {
        string[] audited =
        [
            nameof(OutgoingBook), nameof(IncomingBook), nameof(ArchiveDoc), nameof(Company),
            nameof(Department), nameof(Entity), nameof(Template), nameof(DocumentType),
            nameof(ExchangeRate), nameof(User), nameof(ApprovalDelegation), nameof(BackupRecord),
            nameof(BackupSchedule), nameof(Employee), nameof(EmployeeCompany), nameof(EmployeeLeave),
            nameof(PayrollPeriod), nameof(PayrollEntry), nameof(HrSettings),
        ];

        foreach (var name in audited)
            Assert.True(AuditLabels.Entities.ContainsKey(name), $"كيانٌ يُسجَّل عليه تدقيق بلا ترجمة: {name}");
    }

    // ══════════ الفاعل الحقيقي في أحداث المصادقة ══════════
    //
    // 🔴 كشفه **التشغيل الحيّ** لا المراجعة: 188 سطر دخول في قاعدة العمل بـ`UserId = null`،
    //    فكان تقرير النشاط يعرض «—» في أكثر الأحداث دلالةً أمنياً.

    [Fact]
    public void Actor_PrefersUserId_WhenPresent()
    {
        // ولا يلتفت إلى EntityId ولو كان مختلفاً — الفاعل مَن نفّذ لا مَن وقع عليه الفعل.
        Assert.Equal(7, AuditLabels.ActorUserId(7, "User", "99"));
        Assert.Equal(7, AuditLabels.ActorUserId(7, "OutgoingBook", "12"));
    }

    [Fact]
    public void Actor_FallsBackToEntityId_ForAuthEvents()
    {
        Assert.Equal(5, AuditLabels.ActorUserId(null, "User", "5"));
    }

    [Theory]
    [InlineData("OutgoingBook", "12")]   // «حذف الكتاب 12» فاعلُه ليس الكتاب 12
    [InlineData("ArchiveDoc", "3")]
    [InlineData("Employee", "8")]
    public void Actor_NeverInfersFromNonUserEntities(string entityType, string entityId)
    {
        Assert.Null(AuditLabels.ActorUserId(null, entityType, entityId));
    }

    [Theory]
    [InlineData("User", null)]
    [InlineData("User", "")]
    [InlineData("User", "2026-08")]      // معرّف مركّب (كشوف الرواتب) لا رقم
    [InlineData(null, "5")]
    public void Actor_IsNull_WhenNotParsable(string? entityType, string? entityId)
    {
        Assert.Null(AuditLabels.ActorUserId(null, entityType, entityId));
    }

    [Fact]
    public void NoDuplicateLabels_WithinActions()
    {
        // فعلان بترجمةٍ واحدة يجعلان الفلترة تكذب على قارئها: يختار «حذف» فيصله نوعان.
        var dupes = AuditLabels.Actions.GroupBy(kv => kv.Value)
            .Where(g => g.Count() > 1)
            .Select(g => $"{g.Key} ⇐ {string.Join(" · ", g.Select(x => x.Key))}")
            .ToList();
        Assert.True(dupes.Count == 0, "ترجمات مكرّرة للأفعال: " + string.Join(" | ", dupes));
    }

    [Fact]
    public void DomainLayer_StaysPure_NoInfrastructureReference()
    {
        // الترجمة وُضعت في `Dms.Domain` لتكون **مُختبَرة** (Dms.Tests لا يرى Infrastructure).
        // هذا الحارس يمنع أن تُسحب معها تبعيةٌ تكسر تلك القاعدة لاحقاً.
        var referenced = typeof(AuditLabels).Assembly.GetReferencedAssemblies().Select(a => a.Name);
        Assert.DoesNotContain("Dms.Infrastructure", referenced);
        Assert.DoesNotContain("Microsoft.EntityFrameworkCore", referenced);
    }
}
