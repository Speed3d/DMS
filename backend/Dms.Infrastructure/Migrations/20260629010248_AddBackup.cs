using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Dms.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddBackup : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "BackupRecords",
                columns: table => new
                {
                    BackupRecordId = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    CreatedAt = table.Column<DateTime>(type: "datetime2", nullable: false),
                    CreatedByUserId = table.Column<int>(type: "int", nullable: true),
                    FileName = table.Column<string>(type: "nvarchar(200)", maxLength: 200, nullable: false),
                    SizeBytes = table.Column<long>(type: "bigint", nullable: false),
                    Type = table.Column<int>(type: "int", nullable: false),
                    Status = table.Column<int>(type: "int", nullable: false),
                    Note = table.Column<string>(type: "nvarchar(1000)", maxLength: 1000, nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_BackupRecords", x => x.BackupRecordId);
                });

            migrationBuilder.CreateTable(
                name: "BackupSchedules",
                columns: table => new
                {
                    BackupScheduleId = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    Frequency = table.Column<int>(type: "int", nullable: false),
                    Enabled = table.Column<bool>(type: "bit", nullable: false),
                    Hour = table.Column<int>(type: "int", nullable: false),
                    LastRunAt = table.Column<DateTime>(type: "datetime2", nullable: true),
                    NextRunAt = table.Column<DateTime>(type: "datetime2", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_BackupSchedules", x => x.BackupScheduleId);
                });

            migrationBuilder.CreateIndex(
                name: "IX_BackupRecords_CreatedAt",
                table: "BackupRecords",
                column: "CreatedAt");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "BackupRecords");

            migrationBuilder.DropTable(
                name: "BackupSchedules");
        }
    }
}
