using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Dms.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddPerCompanyPermissions : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // ⚠️ الترتيب مقصود: نُضيف الأعمدة الجديدة ← ننقل البيانات ← ثم نُسقط القديمة.
            //    السقالة المولَّدة كانت تُسقط أولاً فتمحو صلاحيات كل المستخدمين وأقسامهم.

            migrationBuilder.AddColumn<bool>(
                name: "CanApprove",
                table: "UserCompanies",
                type: "bit",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<bool>(
                name: "CanManageIncoming",
                table: "UserCompanies",
                type: "bit",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<int>(
                name: "DepartmentId",
                table: "UserCompanies",
                type: "int",
                nullable: true);

            // 127 = AppModule.All — مطابق للقيمة الافتراضية في الكيان (ADR-012).
            migrationBuilder.AddColumn<int>(
                name: "Modules",
                table: "UserCompanies",
                type: "int",
                nullable: false,
                defaultValue: 127);

            // ── ترحيل البيانات (ADR-017) ──
            // الصلاحيات والأقسام تُنسخ لكل شركات المستخدم (فيحتفظ بما كان يملكه في كلٍّ منها)،
            // أما القسم فيُنسخ **لصف الشركة الرئيسية وحده** لأن القسم يخصّ شركة واحدة بحكم
            // تعريفه، فنسخه لبقية الشركات يُنتج إسناداً لقسم من شركة أخرى.
            migrationBuilder.Sql(@"
                UPDATE uc SET
                    uc.Modules           = u.Modules,
                    uc.CanApprove        = u.CanApprove,
                    uc.CanManageIncoming = u.CanManageIncoming,
                    uc.DepartmentId      = CASE WHEN uc.CompanyId = u.CompanyId
                                                THEN u.DepartmentId ELSE NULL END
                FROM UserCompanies uc
                INNER JOIN Users u ON u.UserId = uc.UserId;");

            migrationBuilder.DropForeignKey(
                name: "FK_Users_Departments_DepartmentId",
                table: "Users");

            migrationBuilder.DropIndex(
                name: "IX_Users_DepartmentId",
                table: "Users");

            migrationBuilder.DropColumn(
                name: "CanApprove",
                table: "Users");

            migrationBuilder.DropColumn(
                name: "CanManageIncoming",
                table: "Users");

            migrationBuilder.DropColumn(
                name: "DepartmentId",
                table: "Users");

            migrationBuilder.DropColumn(
                name: "Modules",
                table: "Users");

            migrationBuilder.CreateIndex(
                name: "IX_UserCompanies_DepartmentId",
                table: "UserCompanies",
                column: "DepartmentId");

            migrationBuilder.AddForeignKey(
                name: "FK_UserCompanies_Departments_DepartmentId",
                table: "UserCompanies",
                column: "DepartmentId",
                principalTable: "Departments",
                principalColumn: "DepartmentId",
                onDelete: ReferentialAction.SetNull);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            // نفس المبدأ معكوساً: أضِف أعمدة Users ← أعِد البيانات ← ثم أسقِط أعمدة UserCompanies.
            // ⚠️ الرجوع **يفقد التنوّع بين الشركات** حتماً (العمود الواحد لا يسع قيمتين مختلفتين)؛
            //    نأخذ صفّ الشركة الرئيسية، وإن غاب فأول إسناد.
            migrationBuilder.AddColumn<bool>(
                name: "CanApprove",
                table: "Users",
                type: "bit",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<bool>(
                name: "CanManageIncoming",
                table: "Users",
                type: "bit",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<int>(
                name: "DepartmentId",
                table: "Users",
                type: "int",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "Modules",
                table: "Users",
                type: "int",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.CreateIndex(
                name: "IX_Users_DepartmentId",
                table: "Users",
                column: "DepartmentId");

            migrationBuilder.AddForeignKey(
                name: "FK_Users_Departments_DepartmentId",
                table: "Users",
                column: "DepartmentId",
                principalTable: "Departments",
                principalColumn: "DepartmentId",
                onDelete: ReferentialAction.SetNull);

            migrationBuilder.Sql(@"
                WITH pick AS (
                    SELECT uc.*, ROW_NUMBER() OVER (
                               PARTITION BY uc.UserId
                               ORDER BY CASE WHEN uc.CompanyId = u.CompanyId THEN 0 ELSE 1 END,
                                        uc.UserCompanyId) AS rn
                    FROM UserCompanies uc
                    INNER JOIN Users u ON u.UserId = uc.UserId
                )
                UPDATE u SET
                    u.Modules           = p.Modules,
                    u.CanApprove        = p.CanApprove,
                    u.CanManageIncoming = p.CanManageIncoming,
                    u.DepartmentId      = p.DepartmentId
                FROM Users u
                INNER JOIN pick p ON p.UserId = u.UserId AND p.rn = 1;");

            migrationBuilder.DropForeignKey(
                name: "FK_UserCompanies_Departments_DepartmentId",
                table: "UserCompanies");

            migrationBuilder.DropIndex(
                name: "IX_UserCompanies_DepartmentId",
                table: "UserCompanies");

            migrationBuilder.DropColumn(
                name: "CanApprove",
                table: "UserCompanies");

            migrationBuilder.DropColumn(
                name: "CanManageIncoming",
                table: "UserCompanies");

            migrationBuilder.DropColumn(
                name: "DepartmentId",
                table: "UserCompanies");

            migrationBuilder.DropColumn(
                name: "Modules",
                table: "UserCompanies");
        }
    }
}
