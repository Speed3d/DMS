using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Dms.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddOutgoingBookTypesAndPrintOptions : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "Details",
                table: "OutgoingMovements",
                type: "nvarchar(max)",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "OutgoingBookTypeId",
                table: "OutgoingBooks",
                type: "int",
                nullable: true);

            migrationBuilder.AddColumn<bool>(
                name: "PageNumbers",
                table: "OutgoingBooks",
                type: "bit",
                nullable: false,
                defaultValue: true);

            migrationBuilder.AddColumn<bool>(
                name: "PrintEntity",
                table: "OutgoingBooks",
                type: "bit",
                nullable: false,
                defaultValue: true);

            migrationBuilder.AddColumn<bool>(
                name: "PrintSubject",
                table: "OutgoingBooks",
                type: "bit",
                nullable: false,
                defaultValue: true);

            migrationBuilder.AddColumn<int>(
                name: "SignaturePlacement",
                table: "OutgoingBooks",
                type: "int",
                nullable: false,
                defaultValue: 0);

            // الكتب القائمة طُبعت والتوقيع والختم في كل صفحة — تبقى كذلك (EveryPage = 2)، والجديدة «الأخيرة» (0).
            migrationBuilder.Sql("UPDATE OutgoingBooks SET SignaturePlacement = 2;");

            migrationBuilder.CreateTable(
                name: "OutgoingBookTypes",
                columns: table => new
                {
                    OutgoingBookTypeId = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    CompanyId = table.Column<int>(type: "int", nullable: false),
                    Name = table.Column<string>(type: "nvarchar(200)", maxLength: 200, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_OutgoingBookTypes", x => x.OutgoingBookTypeId);
                });

            migrationBuilder.CreateIndex(
                name: "IX_OutgoingBooks_OutgoingBookTypeId",
                table: "OutgoingBooks",
                column: "OutgoingBookTypeId");

            migrationBuilder.CreateIndex(
                name: "IX_OutgoingBookTypes_CompanyId_Name",
                table: "OutgoingBookTypes",
                columns: new[] { "CompanyId", "Name" },
                unique: true);

            // أنواع الصادر الافتراضية لكل شركةٍ قائمة (DefaultOutgoingBookTypes) — والجديدة تُبذر عند إنشائها.
            migrationBuilder.Sql(@"
INSERT INTO OutgoingBookTypes (CompanyId, Name)
SELECT c.CompanyId, n.Name
FROM Companies c
CROSS JOIN (VALUES (1, N'كتاب رسمي'), (2, N'فاتورة'), (3, N'عرض سعر')) AS n(Ord, Name)
ORDER BY c.CompanyId, n.Ord;");

            // كل كتابٍ قائم ⟵ «كتاب رسمي» في شركته (قرار المالك: النوع الافتراضي).
            migrationBuilder.Sql(@"
UPDATE b SET b.OutgoingBookTypeId = t.OutgoingBookTypeId
FROM OutgoingBooks b
JOIN OutgoingBookTypes t ON t.CompanyId = b.CompanyId AND t.Name = N'كتاب رسمي';");

            migrationBuilder.AddForeignKey(
                name: "FK_OutgoingBooks_OutgoingBookTypes_OutgoingBookTypeId",
                table: "OutgoingBooks",
                column: "OutgoingBookTypeId",
                principalTable: "OutgoingBookTypes",
                principalColumn: "OutgoingBookTypeId",
                onDelete: ReferentialAction.Restrict);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_OutgoingBooks_OutgoingBookTypes_OutgoingBookTypeId",
                table: "OutgoingBooks");

            migrationBuilder.DropTable(
                name: "OutgoingBookTypes");

            migrationBuilder.DropIndex(
                name: "IX_OutgoingBooks_OutgoingBookTypeId",
                table: "OutgoingBooks");

            migrationBuilder.DropColumn(
                name: "Details",
                table: "OutgoingMovements");

            migrationBuilder.DropColumn(
                name: "OutgoingBookTypeId",
                table: "OutgoingBooks");

            migrationBuilder.DropColumn(
                name: "PageNumbers",
                table: "OutgoingBooks");

            migrationBuilder.DropColumn(
                name: "PrintEntity",
                table: "OutgoingBooks");

            migrationBuilder.DropColumn(
                name: "PrintSubject",
                table: "OutgoingBooks");

            migrationBuilder.DropColumn(
                name: "SignaturePlacement",
                table: "OutgoingBooks");
        }
    }
}
