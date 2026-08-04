using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Dms.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddHrLeavesAndEndOfService : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<decimal>(
                name: "EndOfServiceAmount",
                table: "PayrollEntries",
                type: "decimal(18,2)",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "EndOfServiceCustomDays",
                table: "HrSettings",
                type: "int",
                nullable: true);

            migrationBuilder.AddColumn<bool>(
                name: "EndOfServiceEnabled",
                table: "HrSettings",
                type: "bit",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<int>(
                name: "EndOfServiceRatio",
                table: "HrSettings",
                type: "int",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.CreateTable(
                name: "EmployeeLeaves",
                columns: table => new
                {
                    LeaveId = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    EmployeeCompanyId = table.Column<int>(type: "int", nullable: false),
                    CompanyId = table.Column<int>(type: "int", nullable: false),
                    LeaveType = table.Column<int>(type: "int", nullable: false),
                    FromDate = table.Column<DateTime>(type: "datetime2", nullable: false),
                    ToDate = table.Column<DateTime>(type: "datetime2", nullable: false),
                    DurationDays = table.Column<int>(type: "int", nullable: false),
                    RequiresApproval = table.Column<bool>(type: "bit", nullable: false),
                    Status = table.Column<int>(type: "int", nullable: false),
                    DeductFromSalary = table.Column<bool>(type: "bit", nullable: false),
                    Notes = table.Column<string>(type: "nvarchar(1000)", maxLength: 1000, nullable: true),
                    CreatedByUserId = table.Column<int>(type: "int", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "datetime2", nullable: false),
                    ReviewedByUserId = table.Column<int>(type: "int", nullable: true),
                    ReviewedAt = table.Column<DateTime>(type: "datetime2", nullable: true),
                    ReviewNotes = table.Column<string>(type: "nvarchar(500)", maxLength: 500, nullable: true),
                    IsDeleted = table.Column<bool>(type: "bit", nullable: false),
                    DeletedByUserId = table.Column<int>(type: "int", nullable: true),
                    DeletedAt = table.Column<DateTime>(type: "datetime2", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_EmployeeLeaves", x => x.LeaveId);
                    table.ForeignKey(
                        name: "FK_EmployeeLeaves_EmployeeCompanies_EmployeeCompanyId",
                        column: x => x.EmployeeCompanyId,
                        principalTable: "EmployeeCompanies",
                        principalColumn: "EmployeeCompanyId",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "EmployeeLogs",
                columns: table => new
                {
                    LogId = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    EmployeeCompanyId = table.Column<int>(type: "int", nullable: false),
                    CompanyId = table.Column<int>(type: "int", nullable: false),
                    ChangeType = table.Column<int>(type: "int", nullable: false),
                    Description = table.Column<string>(type: "nvarchar(1000)", maxLength: 1000, nullable: false),
                    OldValue = table.Column<string>(type: "nvarchar(500)", maxLength: 500, nullable: true),
                    NewValue = table.Column<string>(type: "nvarchar(500)", maxLength: 500, nullable: true),
                    ChangedByUserId = table.Column<int>(type: "int", nullable: false),
                    ChangedAt = table.Column<DateTime>(type: "datetime2", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_EmployeeLogs", x => x.LogId);
                    table.ForeignKey(
                        name: "FK_EmployeeLogs_EmployeeCompanies_EmployeeCompanyId",
                        column: x => x.EmployeeCompanyId,
                        principalTable: "EmployeeCompanies",
                        principalColumn: "EmployeeCompanyId",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_EmployeeLeaves_CompanyId_Status",
                table: "EmployeeLeaves",
                columns: new[] { "CompanyId", "Status" });

            migrationBuilder.CreateIndex(
                name: "IX_EmployeeLeaves_EmployeeCompanyId_FromDate",
                table: "EmployeeLeaves",
                columns: new[] { "EmployeeCompanyId", "FromDate" });

            migrationBuilder.CreateIndex(
                name: "IX_EmployeeLogs_EmployeeCompanyId_ChangedAt",
                table: "EmployeeLogs",
                columns: new[] { "EmployeeCompanyId", "ChangedAt" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "EmployeeLeaves");

            migrationBuilder.DropTable(
                name: "EmployeeLogs");

            migrationBuilder.DropColumn(
                name: "EndOfServiceAmount",
                table: "PayrollEntries");

            migrationBuilder.DropColumn(
                name: "EndOfServiceCustomDays",
                table: "HrSettings");

            migrationBuilder.DropColumn(
                name: "EndOfServiceEnabled",
                table: "HrSettings");

            migrationBuilder.DropColumn(
                name: "EndOfServiceRatio",
                table: "HrSettings");
        }
    }
}
