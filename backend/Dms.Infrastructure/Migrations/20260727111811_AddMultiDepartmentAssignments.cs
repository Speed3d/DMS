using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Dms.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddMultiDepartmentAssignments : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // ⚠️ الترتيب مقصود: يُنشأ الجدول ← تُنقل الإسنادات المفردة ← ثم تُسقط الأعمدة.
            //    السقالة المولَّدة كانت تُسقط أولاً فتمحو قسمَ كل كتاب وارد. ورغم أن المالك
            //    اختار تصفير الوارد الآن، تبقى المهاجرة صحيحة لو طُبّقت على نسخة قديمة
            //    مُستعادة — وهو درس ADR-017 نفسه.
            migrationBuilder.CreateTable(
                name: "IncomingAssignment",
                columns: table => new
                {
                    IncomingAssignmentId = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    IncomingId = table.Column<int>(type: "int", nullable: false),
                    DepartmentId = table.Column<int>(type: "int", nullable: false),
                    Note = table.Column<string>(type: "nvarchar(1000)", maxLength: 1000, nullable: true),
                    AssignedByUserId = table.Column<int>(type: "int", nullable: false),
                    AssignedAt = table.Column<DateTime>(type: "datetime2", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_IncomingAssignment", x => x.IncomingAssignmentId);
                    table.ForeignKey(
                        name: "FK_IncomingAssignment_Departments_DepartmentId",
                        column: x => x.DepartmentId,
                        principalTable: "Departments",
                        principalColumn: "DepartmentId",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_IncomingAssignment_IncomingBooks_IncomingId",
                        column: x => x.IncomingId,
                        principalTable: "IncomingBooks",
                        principalColumn: "IncomingId",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_IncomingAssignment_DepartmentId",
                table: "IncomingAssignment",
                column: "DepartmentId");

            migrationBuilder.CreateIndex(
                name: "IX_IncomingAssignment_IncomingId_DepartmentId",
                table: "IncomingAssignment",
                columns: new[] { "IncomingId", "DepartmentId" },
                unique: true);

            // نقل الإسناد المفرد القديم إلى الجدول الجديد قبل إسقاط العمود.
            // مَن أحال غير مُسجَّل في النموذج القديم، فنستعمل مُنشئ الكتاب وتاريخ آخر تحديث.
            migrationBuilder.Sql(@"
                INSERT INTO IncomingAssignment (IncomingId, DepartmentId, Note, AssignedByUserId, AssignedAt)
                SELECT b.IncomingId, b.DepartmentId, NULL, b.CreatedByUserId,
                       ISNULL(b.UpdatedAt, b.CreatedAt)
                FROM IncomingBooks b
                WHERE b.DepartmentId IS NOT NULL;");

            migrationBuilder.DropForeignKey(
                name: "FK_IncomingBooks_Departments_DepartmentId",
                table: "IncomingBooks");

            migrationBuilder.DropIndex(
                name: "IX_IncomingBooks_DepartmentId",
                table: "IncomingBooks");

            migrationBuilder.DropColumn(
                name: "DepartmentId",
                table: "IncomingBooks");

            // FolderName: نصّ القسم القديم قبل ADR-015 — فقد آخر معنى له بعد تعدّد الأقسام.
            migrationBuilder.DropColumn(
                name: "FolderName",
                table: "IncomingBooks");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "IncomingAssignment");

            migrationBuilder.AddColumn<int>(
                name: "DepartmentId",
                table: "IncomingBooks",
                type: "int",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "FolderName",
                table: "IncomingBooks",
                type: "nvarchar(200)",
                maxLength: 200,
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_IncomingBooks_DepartmentId",
                table: "IncomingBooks",
                column: "DepartmentId");

            migrationBuilder.AddForeignKey(
                name: "FK_IncomingBooks_Departments_DepartmentId",
                table: "IncomingBooks",
                column: "DepartmentId",
                principalTable: "Departments",
                principalColumn: "DepartmentId",
                onDelete: ReferentialAction.SetNull);
        }
    }
}
