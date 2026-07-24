using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Dms.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddBackupScopeAndRetention : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "Category",
                table: "BackupRecords",
                type: "int",
                nullable: false,
                defaultValue: 0);

            // النسخ القديمة (قبل هذا الحقل) كانت جميعها كاملة ⇒ الافتراض Full(1) حتى لا تُصنَّف خطأً كـ«قاعدة فقط».
            migrationBuilder.AddColumn<int>(
                name: "Scope",
                table: "BackupRecords",
                type: "int",
                nullable: false,
                defaultValue: 1);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "Category",
                table: "BackupRecords");

            migrationBuilder.DropColumn(
                name: "Scope",
                table: "BackupRecords");
        }
    }
}
