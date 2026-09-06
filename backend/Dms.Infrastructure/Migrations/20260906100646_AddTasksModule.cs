using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Dms.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddTasksModule : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<bool>(
                name: "CanManageTasks",
                table: "UserCompanies",
                type: "bit",
                nullable: false,
                defaultValue: false);

            migrationBuilder.CreateTable(
                name: "DmsTasks",
                columns: table => new
                {
                    TaskId = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    CompanyId = table.Column<int>(type: "int", nullable: false),
                    TaskNumber = table.Column<string>(type: "nvarchar(40)", maxLength: 40, nullable: true),
                    Year = table.Column<int>(type: "int", nullable: true),
                    SerialNo = table.Column<int>(type: "int", nullable: true),
                    Title = table.Column<string>(type: "nvarchar(500)", maxLength: 500, nullable: false),
                    Description = table.Column<string>(type: "nvarchar(max)", nullable: true),
                    TaskType = table.Column<int>(type: "int", nullable: false),
                    Priority = table.Column<int>(type: "int", nullable: false),
                    Status = table.Column<int>(type: "int", nullable: false),
                    ProgressPercent = table.Column<int>(type: "int", nullable: false),
                    DueDate = table.Column<DateTime>(type: "datetime2", nullable: false),
                    StartDate = table.Column<DateTime>(type: "datetime2", nullable: true),
                    CompletedDate = table.Column<DateTime>(type: "datetime2", nullable: true),
                    DepartmentId = table.Column<int>(type: "int", nullable: true),
                    AssignedToUserId = table.Column<int>(type: "int", nullable: true),
                    CreatedByUserId = table.Column<int>(type: "int", nullable: false),
                    RelatedIncomingId = table.Column<int>(type: "int", nullable: true),
                    RelatedOutgoingId = table.Column<int>(type: "int", nullable: true),
                    IsRecurring = table.Column<bool>(type: "bit", nullable: false),
                    RecurrencePattern = table.Column<int>(type: "int", nullable: true),
                    RecurrenceInterval = table.Column<int>(type: "int", nullable: true),
                    RecurrenceEndDate = table.Column<DateTime>(type: "datetime2", nullable: true),
                    ParentRecurringTaskId = table.Column<int>(type: "int", nullable: true),
                    LastEscalationLevel = table.Column<int>(type: "int", nullable: false),
                    LastEscalatedAt = table.Column<DateTime>(type: "datetime2", nullable: true),
                    DueSoonNotifiedAt = table.Column<DateTime>(type: "datetime2", nullable: true),
                    Notes = table.Column<string>(type: "nvarchar(max)", nullable: true),
                    RowVersion = table.Column<byte[]>(type: "rowversion", rowVersion: true, nullable: true),
                    IsDeleted = table.Column<bool>(type: "bit", nullable: false),
                    DeletedByUserId = table.Column<int>(type: "int", nullable: true),
                    DeletedAt = table.Column<DateTime>(type: "datetime2", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "datetime2", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "datetime2", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_DmsTasks", x => x.TaskId);
                    table.ForeignKey(
                        name: "FK_DmsTasks_Companies_CompanyId",
                        column: x => x.CompanyId,
                        principalTable: "Companies",
                        principalColumn: "CompanyId",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_DmsTasks_Departments_DepartmentId",
                        column: x => x.DepartmentId,
                        principalTable: "Departments",
                        principalColumn: "DepartmentId",
                        onDelete: ReferentialAction.SetNull);
                    table.ForeignKey(
                        name: "FK_DmsTasks_DmsTasks_ParentRecurringTaskId",
                        column: x => x.ParentRecurringTaskId,
                        principalTable: "DmsTasks",
                        principalColumn: "TaskId",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_DmsTasks_IncomingBooks_RelatedIncomingId",
                        column: x => x.RelatedIncomingId,
                        principalTable: "IncomingBooks",
                        principalColumn: "IncomingId",
                        onDelete: ReferentialAction.SetNull);
                    table.ForeignKey(
                        name: "FK_DmsTasks_OutgoingBooks_RelatedOutgoingId",
                        column: x => x.RelatedOutgoingId,
                        principalTable: "OutgoingBooks",
                        principalColumn: "OutgoingId",
                        onDelete: ReferentialAction.SetNull);
                    table.ForeignKey(
                        name: "FK_DmsTasks_Users_AssignedToUserId",
                        column: x => x.AssignedToUserId,
                        principalTable: "Users",
                        principalColumn: "UserId",
                        onDelete: ReferentialAction.SetNull);
                    table.ForeignKey(
                        name: "FK_DmsTasks_Users_CreatedByUserId",
                        column: x => x.CreatedByUserId,
                        principalTable: "Users",
                        principalColumn: "UserId",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "DmsTaskUpdates",
                columns: table => new
                {
                    UpdateId = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    TaskId = table.Column<int>(type: "int", nullable: false),
                    CompanyId = table.Column<int>(type: "int", nullable: false),
                    UpdateType = table.Column<int>(type: "int", nullable: false),
                    OldValue = table.Column<string>(type: "nvarchar(500)", maxLength: 500, nullable: true),
                    NewValue = table.Column<string>(type: "nvarchar(500)", maxLength: 500, nullable: true),
                    Comment = table.Column<string>(type: "nvarchar(2000)", maxLength: 2000, nullable: true),
                    Description = table.Column<string>(type: "nvarchar(1000)", maxLength: 1000, nullable: false),
                    UpdatedByUserId = table.Column<int>(type: "int", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "datetime2", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_DmsTaskUpdates", x => x.UpdateId);
                    table.ForeignKey(
                        name: "FK_DmsTaskUpdates_DmsTasks_TaskId",
                        column: x => x.TaskId,
                        principalTable: "DmsTasks",
                        principalColumn: "TaskId",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_DmsTaskUpdates_Users_UpdatedByUserId",
                        column: x => x.UpdatedByUserId,
                        principalTable: "Users",
                        principalColumn: "UserId",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "IX_DmsTasks_AssignedToUserId",
                table: "DmsTasks",
                column: "AssignedToUserId");

            migrationBuilder.CreateIndex(
                name: "IX_DmsTasks_CompanyId_AssignedToUserId",
                table: "DmsTasks",
                columns: new[] { "CompanyId", "AssignedToUserId" });

            migrationBuilder.CreateIndex(
                name: "IX_DmsTasks_CompanyId_DepartmentId",
                table: "DmsTasks",
                columns: new[] { "CompanyId", "DepartmentId" });

            migrationBuilder.CreateIndex(
                name: "IX_DmsTasks_CompanyId_Status_DueDate",
                table: "DmsTasks",
                columns: new[] { "CompanyId", "Status", "DueDate" });

            migrationBuilder.CreateIndex(
                name: "IX_DmsTasks_CompanyId_Year_SerialNo",
                table: "DmsTasks",
                columns: new[] { "CompanyId", "Year", "SerialNo" },
                unique: true,
                filter: "[SerialNo] IS NOT NULL");

            migrationBuilder.CreateIndex(
                name: "IX_DmsTasks_CreatedByUserId",
                table: "DmsTasks",
                column: "CreatedByUserId");

            migrationBuilder.CreateIndex(
                name: "IX_DmsTasks_DepartmentId",
                table: "DmsTasks",
                column: "DepartmentId");

            migrationBuilder.CreateIndex(
                name: "IX_DmsTasks_ParentRecurringTaskId_DueDate",
                table: "DmsTasks",
                columns: new[] { "ParentRecurringTaskId", "DueDate" },
                unique: true,
                filter: "[ParentRecurringTaskId] IS NOT NULL");

            migrationBuilder.CreateIndex(
                name: "IX_DmsTasks_RelatedIncomingId",
                table: "DmsTasks",
                column: "RelatedIncomingId");

            migrationBuilder.CreateIndex(
                name: "IX_DmsTasks_RelatedOutgoingId",
                table: "DmsTasks",
                column: "RelatedOutgoingId");

            migrationBuilder.CreateIndex(
                name: "IX_DmsTasks_TaskNumber",
                table: "DmsTasks",
                column: "TaskNumber",
                unique: true,
                filter: "[TaskNumber] IS NOT NULL");

            migrationBuilder.CreateIndex(
                name: "IX_DmsTaskUpdates_TaskId_UpdatedAt",
                table: "DmsTaskUpdates",
                columns: new[] { "TaskId", "UpdatedAt" });

            migrationBuilder.CreateIndex(
                name: "IX_DmsTaskUpdates_UpdatedByUserId",
                table: "DmsTaskUpdates",
                column: "UpdatedByUserId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "DmsTaskUpdates");

            migrationBuilder.DropTable(
                name: "DmsTasks");

            migrationBuilder.DropColumn(
                name: "CanManageTasks",
                table: "UserCompanies");
        }
    }
}
