using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Dms.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class FilterOutgoingUniqueIndexesByIsDeleted : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_OutgoingBooks_CompanyId_Year_SerialNo",
                table: "OutgoingBooks");

            migrationBuilder.DropIndex(
                name: "IX_OutgoingBooks_Number",
                table: "OutgoingBooks");

            migrationBuilder.CreateIndex(
                name: "IX_OutgoingBooks_CompanyId_Year_SerialNo",
                table: "OutgoingBooks",
                columns: new[] { "CompanyId", "Year", "SerialNo" },
                unique: true,
                filter: "[SerialNo] IS NOT NULL AND [IsDeleted] = 0");

            migrationBuilder.CreateIndex(
                name: "IX_OutgoingBooks_Number",
                table: "OutgoingBooks",
                column: "Number",
                unique: true,
                filter: "[Number] IS NOT NULL AND [IsDeleted] = 0");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_OutgoingBooks_CompanyId_Year_SerialNo",
                table: "OutgoingBooks");

            migrationBuilder.DropIndex(
                name: "IX_OutgoingBooks_Number",
                table: "OutgoingBooks");

            migrationBuilder.CreateIndex(
                name: "IX_OutgoingBooks_CompanyId_Year_SerialNo",
                table: "OutgoingBooks",
                columns: new[] { "CompanyId", "Year", "SerialNo" },
                unique: true,
                filter: "[SerialNo] IS NOT NULL");

            migrationBuilder.CreateIndex(
                name: "IX_OutgoingBooks_Number",
                table: "OutgoingBooks",
                column: "Number",
                unique: true,
                filter: "[Number] IS NOT NULL");
        }
    }
}
