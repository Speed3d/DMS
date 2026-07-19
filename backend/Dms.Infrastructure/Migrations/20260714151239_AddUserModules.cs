using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Dms.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddUserModules : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // 63 = AppModule.All — المستخدمون الحاليون يحتفظون بكامل الوصول (توافق خلفي).
            migrationBuilder.AddColumn<int>(
                name: "Modules",
                table: "Users",
                type: "int",
                nullable: false,
                defaultValue: 63);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "Modules",
                table: "Users");
        }
    }
}
