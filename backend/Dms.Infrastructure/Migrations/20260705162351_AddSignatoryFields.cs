using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Dms.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddSignatoryFields : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "SignatoryName",
                table: "OutgoingBooks",
                type: "nvarchar(max)",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "SignatoryTitle",
                table: "OutgoingBooks",
                type: "nvarchar(max)",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "DefaultSignatoryName",
                table: "Companies",
                type: "nvarchar(max)",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "DefaultSignatoryTitle",
                table: "Companies",
                type: "nvarchar(max)",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "SignatoryName",
                table: "OutgoingBooks");

            migrationBuilder.DropColumn(
                name: "SignatoryTitle",
                table: "OutgoingBooks");

            migrationBuilder.DropColumn(
                name: "DefaultSignatoryName",
                table: "Companies");

            migrationBuilder.DropColumn(
                name: "DefaultSignatoryTitle",
                table: "Companies");
        }
    }
}
