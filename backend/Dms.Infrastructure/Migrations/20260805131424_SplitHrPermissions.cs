using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Dms.Infrastructure.Migrations
{
    /// <summary>
    /// فصل صلاحية «الموظفون والرواتب» الواحدة إلى صلاحيتين (ADR-025).
    /// </summary>
    /// <remarks>
    /// 🔴 **مرتّبة يدوياً: إنشاء ← نقل بيانات ← إسقاط.**
    /// سقالة EF اقترحت **إعادة تسمية** <c>CanManageHR</c> إلى <c>CanManagePayroll</c> وإضافةَ
    /// <c>CanManageEmployees</c> بافتراض <c>false</c> — فيربح صاحبُ الصلاحية القديمة الرواتب
    /// و**يفقد بطاقات الموظفين صامتاً**. وهو نظير الخطأ الذي وقع في ADR-017 وADR-018 معاً
    /// (السقالة تُسقط قبل النقل فتمحو البيانات)، ولذلك تنصّ قاعدة `rules/workflow.md` على
    /// ترتيب عمليات نقل الأعمدة يدوياً.
    ///
    /// ⚠️ **وبتّ الأقسام يُنقل كذلك لا الأعلام وحدها:** <c>HR = 128</c> صار
    /// <c>Employees = 128</c> (القيمة محفوظة فلا يحتاج نقلاً)، و<c>Payroll = 256</c> **بتٌّ
    /// جديد** لا يملكه أحد. فبلا السطر الذي يضيفه، يفقد كلُّ من كان يرى الرواتب رؤيتَها.
    /// </remarks>
    public partial class SplitHrPermissions : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // ── ١) إنشاء العمودين الجديدين ──
            migrationBuilder.AddColumn<bool>(
                name: "CanManageEmployees",
                table: "UserCompanies",
                type: "bit",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<bool>(
                name: "CanManagePayroll",
                table: "UserCompanies",
                type: "bit",
                nullable: false,
                defaultValue: false);

            // ── ٢) نقل البيانات ──
            // مَن كان يملك الصلاحية الواحدة يملك الاثنتين: الفصل يُضيّق ما يُمنح **مستقبلاً**
            // ولا يسحب صلاحيةً قائمة من أحد. سحبُها قرارٌ إداريّ يتّخذه المالك من الشاشة.
            migrationBuilder.Sql(@"
UPDATE [UserCompanies]
   SET [CanManageEmployees] = [CanManageHR],
       [CanManagePayroll]   = [CanManageHR];");

            // ومَن كان يملك قسم HR (البتّ 128) يملك الآن القسمين — بإضافة البتّ 256.
            migrationBuilder.Sql(@"
UPDATE [UserCompanies]
   SET [Modules] = [Modules] | 256
 WHERE ([Modules] & 128) = 128
   AND ([Modules] & 256) = 0;");

            // ── ٣) إسقاط العمود القديم بعد نقل ما فيه ──
            migrationBuilder.DropColumn(
                name: "CanManageHR",
                table: "UserCompanies");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<bool>(
                name: "CanManageHR",
                table: "UserCompanies",
                type: "bit",
                nullable: false,
                defaultValue: false);

            // الرجوع يجمع الصلاحيتين في واحدة (أيّهما يكفي) — فلا يُفقد أحدٌ وصولاً كان يملكه.
            migrationBuilder.Sql(@"
UPDATE [UserCompanies]
   SET [CanManageHR] = CASE WHEN [CanManageEmployees] = 1 OR [CanManagePayroll] = 1
                            THEN 1 ELSE 0 END;");

            // وإزالة بتّ الرواتب الذي لا وجود له في المخطّط القديم.
            migrationBuilder.Sql(@"
UPDATE [UserCompanies]
   SET [Modules] = [Modules] & ~256
 WHERE ([Modules] & 256) = 256;");

            migrationBuilder.DropColumn(name: "CanManageEmployees", table: "UserCompanies");
            migrationBuilder.DropColumn(name: "CanManagePayroll", table: "UserCompanies");
        }
    }
}
