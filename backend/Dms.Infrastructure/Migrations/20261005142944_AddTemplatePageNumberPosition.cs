using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Dms.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddTemplatePageNumberPosition : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "PageNumberAlign",
                table: "Templates",
                type: "nvarchar(10)",
                maxLength: 10,
                nullable: false,
                defaultValue: "center");

            migrationBuilder.AddColumn<int>(
                name: "PageNumberOffsetX",
                table: "Templates",
                type: "int",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<int>(
                name: "PageNumberOffsetY",
                table: "Templates",
                type: "int",
                nullable: false,
                defaultValue: 0);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "PageNumberAlign",
                table: "Templates");

            migrationBuilder.DropColumn(
                name: "PageNumberOffsetX",
                table: "Templates");

            migrationBuilder.DropColumn(
                name: "PageNumberOffsetY",
                table: "Templates");
        }
    }
}
