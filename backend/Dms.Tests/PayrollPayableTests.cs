using System.Linq.Expressions;
using Dms.Domain;
using Xunit;

/// <summary>
/// حرّاس قاعدة «ما تدفعه الشركة فعلاً» (ADR-028).
///
/// ⚠️ **سبب وجودها:** علَم «مدفوع من شركة أخرى» كان تجميلياً — يلوّن السطر ولا يمسّ رقماً،
/// فاحتُسب في قاعدة عمل المالك **3,680,000 د.ع** ضمن المدفوع في شهرين مُسدَّدين.
/// </summary>
public class PayrollPayableTests
{
    private static PayrollEntry Entry(PayrollPaymentStatus status, decimal iqd, bool deleted = false) =>
        new()
        {
            SnapshotName = "موظف",
            PaymentStatus = status,
            NetSalaryIqd = iqd,
            IsDeleted = deleted,
        };

    [Theory]
    [InlineData(PayrollPaymentStatus.Unpaid, true)]
    [InlineData(PayrollPaymentStatus.PaidByThisCompany, true)]
    [InlineData(PayrollPaymentStatus.ConfirmedByThisCompany, true)]
    [InlineData(PayrollPaymentStatus.PaidByOtherCompany, false)]
    public void المستثنى_واحدٌ_فقط(PayrollPaymentStatus status, bool included)
    {
        Assert.Equal(included, PayrollPayable.Includes(status));
    }

    /// <summary>
    /// 🔴 **الحارس الذي يمنع تباعد النسختين.** القاعدة مكتوبة مرّتين — دالّةً للذاكرة وشجرةَ
    /// تعبيرٍ لـEF — لأن EF لا تترجم استدعاء دالّة. ولو عُدِّلت إحداهما وحدها لاختلف ما
    /// يُعرض عمّا يُجمع في قاعدة البيانات **بلا أن يسقط شيء**.
    /// </summary>
    [Fact]
    public void شجرةُ_تعبير_EF_تطابق_الدالّة_على_كل_قيم_الحالة()
    {
        var compiled = PayrollPayable.Predicate.Compile();

        foreach (var status in Enum.GetValues<PayrollPaymentStatus>())
        {
            var entry = Entry(status, 100);
            Assert.Equal(PayrollPayable.Includes(status), compiled(entry));
        }
    }

    [Fact]
    public void الإجمالي_يستثني_المدفوع_من_شركة_أخرى()
    {
        var entries = new[]
        {
            Entry(PayrollPaymentStatus.Unpaid, 1_000_000),
            Entry(PayrollPaymentStatus.ConfirmedByThisCompany, 500_000),
            Entry(PayrollPaymentStatus.PaidByOtherCompany, 2_400_000),
        };

        Assert.Equal(1_500_000m, PayrollPayable.TotalIqd(entries));
        Assert.Equal(2_400_000m, PayrollPayable.ExcludedIqd(entries));
        Assert.Equal(2, PayrollPayable.Payable(entries).Count());
    }

    /// <summary>الحالة الحقيقية التي وقعت: الكشف كلّه راتبُ من صرفته شركةٌ أخرى.</summary>
    [Fact]
    public void كشفٌ_كلُّه_مدفوعٌ_من_الخارج_إجماليه_صفر()
    {
        var entries = new[] { Entry(PayrollPaymentStatus.PaidByOtherCompany, 1_280_000) };

        Assert.Equal(0m, PayrollPayable.TotalIqd(entries));
        Assert.Equal(1_280_000m, PayrollPayable.ExcludedIqd(entries));
        Assert.Empty(PayrollPayable.Payable(entries));
    }

    /// <summary>الحذف الناعم يُستثنى من الطرفين — لا من المدفوع وحده.</summary>
    [Fact]
    public void المحذوف_ناعماً_خارج_الإجمالي_وخارج_المستثنى()
    {
        var entries = new[]
        {
            Entry(PayrollPaymentStatus.Unpaid, 700_000, deleted: true),
            Entry(PayrollPaymentStatus.PaidByOtherCompany, 900_000, deleted: true),
            Entry(PayrollPaymentStatus.Unpaid, 300_000),
        };

        Assert.Equal(300_000m, PayrollPayable.TotalIqd(entries));
        Assert.Equal(0m, PayrollPayable.ExcludedIqd(entries));
    }

    /// <summary>
    /// ⚠️ **حارسٌ على الـenum نفسه:** أي حالةٍ جديدة تُضاف مستقبلاً يجب أن يقرّر كاتبُها
    /// هل تدخل في المدفوع أم لا — وهذا الاختبار يُسقطه حتى يفعل.
    /// </summary>
    [Fact]
    public void حالاتُ_الدفع_أربعٌ_معروفة_لا_خامسة_صامتة()
    {
        var known = new[]
        {
            PayrollPaymentStatus.Unpaid,
            PayrollPaymentStatus.PaidByThisCompany,
            PayrollPaymentStatus.PaidByOtherCompany,
            PayrollPaymentStatus.ConfirmedByThisCompany,
        };

        Assert.Equal(known.Length, Enum.GetValues<PayrollPaymentStatus>().Length);
        Assert.All(Enum.GetValues<PayrollPaymentStatus>(), s => Assert.Contains(s, known));
    }
}
