using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Dms.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddPayrollAmendments : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<bool>(
                name: "CanAmendPaidPayroll",
                table: "UserCompanies",
                type: "bit",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<int>(
                name: "AmendmentCount",
                table: "PayrollPeriods",
                type: "int",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<DateTime>(
                name: "LastAmendedAt",
                table: "PayrollPeriods",
                type: "datetime2",
                nullable: true);

            migrationBuilder.AddColumn<DateTime>(
                name: "ReceiptAcknowledgedAt",
                table: "PayrollEntries",
                type: "datetime2",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "CanAmendPaidPayroll",
                table: "UserCompanies");

            migrationBuilder.DropColumn(
                name: "AmendmentCount",
                table: "PayrollPeriods");

            migrationBuilder.DropColumn(
                name: "LastAmendedAt",
                table: "PayrollPeriods");

            migrationBuilder.DropColumn(
                name: "ReceiptAcknowledgedAt",
                table: "PayrollEntries");
        }
    }
}
