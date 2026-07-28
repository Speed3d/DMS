using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Dms.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddArchiveDepartmentAndUnarchive : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "DepartmentId",
                table: "ArchiveDocs",
                type: "int",
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_ArchiveDocs_CompanyId_DepartmentId",
                table: "ArchiveDocs",
                columns: new[] { "CompanyId", "DepartmentId" });

            migrationBuilder.CreateIndex(
                name: "IX_ArchiveDocs_DepartmentId",
                table: "ArchiveDocs",
                column: "DepartmentId");

            migrationBuilder.AddForeignKey(
                name: "FK_ArchiveDocs_Departments_DepartmentId",
                table: "ArchiveDocs",
                column: "DepartmentId",
                principalTable: "Departments",
                principalColumn: "DepartmentId",
                onDelete: ReferentialAction.SetNull);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_ArchiveDocs_Departments_DepartmentId",
                table: "ArchiveDocs");

            migrationBuilder.DropIndex(
                name: "IX_ArchiveDocs_CompanyId_DepartmentId",
                table: "ArchiveDocs");

            migrationBuilder.DropIndex(
                name: "IX_ArchiveDocs_DepartmentId",
                table: "ArchiveDocs");

            migrationBuilder.DropColumn(
                name: "DepartmentId",
                table: "ArchiveDocs");
        }
    }
}
