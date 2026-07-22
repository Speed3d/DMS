using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Dms.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddIncomingModule : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "ReplyToIncomingId",
                table: "OutgoingBooks",
                type: "int",
                nullable: true);

            migrationBuilder.CreateTable(
                name: "IncomingBooks",
                columns: table => new
                {
                    IncomingId = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    CompanyId = table.Column<int>(type: "int", nullable: false),
                    IncomingNumber = table.Column<string>(type: "nvarchar(40)", maxLength: 40, nullable: true),
                    Year = table.Column<int>(type: "int", nullable: true),
                    SerialNo = table.Column<int>(type: "int", nullable: true),
                    ExternalNumber = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: true),
                    ExternalDate = table.Column<DateTime>(type: "datetime2", nullable: true),
                    ReceivedDate = table.Column<DateTime>(type: "datetime2", nullable: false),
                    ReceivedTime = table.Column<TimeSpan>(type: "time", nullable: true),
                    EntityId = table.Column<int>(type: "int", nullable: false),
                    Subject = table.Column<string>(type: "nvarchar(500)", maxLength: 500, nullable: false),
                    DocumentTypeId = table.Column<int>(type: "int", nullable: true),
                    ReceiveMethod = table.Column<int>(type: "int", nullable: false),
                    ReceivedByUserId = table.Column<int>(type: "int", nullable: false),
                    Status = table.Column<int>(type: "int", nullable: false),
                    FolderName = table.Column<string>(type: "nvarchar(200)", maxLength: 200, nullable: true),
                    LastAction = table.Column<string>(type: "nvarchar(500)", maxLength: 500, nullable: true),
                    Keywords = table.Column<string>(type: "nvarchar(1000)", maxLength: 1000, nullable: true),
                    Notes = table.Column<string>(type: "nvarchar(max)", nullable: true),
                    Amount = table.Column<decimal>(type: "decimal(18,2)", precision: 18, scale: 2, nullable: true),
                    Currency = table.Column<int>(type: "int", nullable: true),
                    ExchangeRate = table.Column<decimal>(type: "decimal(18,4)", precision: 18, scale: 4, nullable: true),
                    AmountInIqd = table.Column<decimal>(type: "decimal(18,2)", precision: 18, scale: 2, nullable: true),
                    ReplyOutgoingId = table.Column<int>(type: "int", nullable: true),
                    CreatedByUserId = table.Column<int>(type: "int", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "datetime2", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "datetime2", nullable: true),
                    IsDeleted = table.Column<bool>(type: "bit", nullable: false),
                    DeletedByUserId = table.Column<int>(type: "int", nullable: true),
                    DeletedAt = table.Column<DateTime>(type: "datetime2", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_IncomingBooks", x => x.IncomingId);
                    table.ForeignKey(
                        name: "FK_IncomingBooks_Entities_EntityId",
                        column: x => x.EntityId,
                        principalTable: "Entities",
                        principalColumn: "EntityId",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_IncomingBooks_OutgoingBooks_ReplyOutgoingId",
                        column: x => x.ReplyOutgoingId,
                        principalTable: "OutgoingBooks",
                        principalColumn: "OutgoingId",
                        onDelete: ReferentialAction.SetNull);
                });

            migrationBuilder.CreateTable(
                name: "MovementLogs",
                columns: table => new
                {
                    MovementId = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    IncomingId = table.Column<int>(type: "int", nullable: false),
                    CompanyId = table.Column<int>(type: "int", nullable: false),
                    Action = table.Column<string>(type: "nvarchar(50)", maxLength: 50, nullable: false),
                    Description = table.Column<string>(type: "nvarchar(500)", maxLength: 500, nullable: false),
                    FromDepartment = table.Column<string>(type: "nvarchar(200)", maxLength: 200, nullable: true),
                    ToDepartment = table.Column<string>(type: "nvarchar(200)", maxLength: 200, nullable: true),
                    PerformedByUserId = table.Column<int>(type: "int", nullable: false),
                    PerformedAt = table.Column<DateTime>(type: "datetime2", nullable: false),
                    IncomingBookIncomingId = table.Column<int>(type: "int", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_MovementLogs", x => x.MovementId);
                    table.ForeignKey(
                        name: "FK_MovementLogs_IncomingBooks_IncomingBookIncomingId",
                        column: x => x.IncomingBookIncomingId,
                        principalTable: "IncomingBooks",
                        principalColumn: "IncomingId");
                });

            migrationBuilder.CreateIndex(
                name: "IX_OutgoingBooks_ReplyToIncomingId",
                table: "OutgoingBooks",
                column: "ReplyToIncomingId");

            migrationBuilder.CreateIndex(
                name: "IX_IncomingBooks_CompanyId_Year_SerialNo",
                table: "IncomingBooks",
                columns: new[] { "CompanyId", "Year", "SerialNo" },
                unique: true,
                filter: "[Year] IS NOT NULL AND [SerialNo] IS NOT NULL");

            migrationBuilder.CreateIndex(
                name: "IX_IncomingBooks_EntityId",
                table: "IncomingBooks",
                column: "EntityId");

            migrationBuilder.CreateIndex(
                name: "IX_IncomingBooks_IncomingNumber",
                table: "IncomingBooks",
                column: "IncomingNumber",
                unique: true,
                filter: "[IncomingNumber] IS NOT NULL");

            migrationBuilder.CreateIndex(
                name: "IX_IncomingBooks_ReceivedDate",
                table: "IncomingBooks",
                column: "ReceivedDate");

            migrationBuilder.CreateIndex(
                name: "IX_IncomingBooks_ReplyOutgoingId",
                table: "IncomingBooks",
                column: "ReplyOutgoingId");

            migrationBuilder.CreateIndex(
                name: "IX_IncomingBooks_Status",
                table: "IncomingBooks",
                column: "Status");

            migrationBuilder.CreateIndex(
                name: "IX_MovementLogs_IncomingBookIncomingId",
                table: "MovementLogs",
                column: "IncomingBookIncomingId");

            migrationBuilder.CreateIndex(
                name: "IX_MovementLogs_IncomingId",
                table: "MovementLogs",
                column: "IncomingId");

            migrationBuilder.CreateIndex(
                name: "IX_MovementLogs_PerformedAt",
                table: "MovementLogs",
                column: "PerformedAt");

            migrationBuilder.AddForeignKey(
                name: "FK_OutgoingBooks_IncomingBooks_ReplyToIncomingId",
                table: "OutgoingBooks",
                column: "ReplyToIncomingId",
                principalTable: "IncomingBooks",
                principalColumn: "IncomingId",
                onDelete: ReferentialAction.SetNull);

            // إضافة الصلاحية الجديدة (الوارد) للمستخدمين الذين يملكون الصلاحيات الكاملة مسبقاً (All = 63) لتصبح (All = 127)
            migrationBuilder.Sql("UPDATE Users SET Modules = 127 WHERE Modules = 63;");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_OutgoingBooks_IncomingBooks_ReplyToIncomingId",
                table: "OutgoingBooks");

            migrationBuilder.DropTable(
                name: "MovementLogs");

            migrationBuilder.DropTable(
                name: "IncomingBooks");

            migrationBuilder.DropIndex(
                name: "IX_OutgoingBooks_ReplyToIncomingId",
                table: "OutgoingBooks");

            migrationBuilder.DropColumn(
                name: "ReplyToIncomingId",
                table: "OutgoingBooks");

            // التراجع عن صلاحية الوارد وإعادتها لـ 63
            migrationBuilder.Sql("UPDATE Users SET Modules = 63 WHERE Modules = 127;");
        }
    }
}
