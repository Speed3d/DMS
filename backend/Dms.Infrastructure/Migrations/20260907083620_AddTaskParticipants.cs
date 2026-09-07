using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Dms.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddTaskParticipants : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "DmsTaskParticipants",
                columns: table => new
                {
                    ParticipantId = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    TaskId = table.Column<int>(type: "int", nullable: false),
                    CompanyId = table.Column<int>(type: "int", nullable: false),
                    UserId = table.Column<int>(type: "int", nullable: true),
                    DepartmentId = table.Column<int>(type: "int", nullable: true),
                    AddedByUserId = table.Column<int>(type: "int", nullable: false),
                    AddedAt = table.Column<DateTime>(type: "datetime2", nullable: false),
                    Note = table.Column<string>(type: "nvarchar(500)", maxLength: 500, nullable: true),
                    IsRemoved = table.Column<bool>(type: "bit", nullable: false),
                    RemovedByUserId = table.Column<int>(type: "int", nullable: true),
                    RemovedAt = table.Column<DateTime>(type: "datetime2", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_DmsTaskParticipants", x => x.ParticipantId);
                    table.ForeignKey(
                        name: "FK_DmsTaskParticipants_Departments_DepartmentId",
                        column: x => x.DepartmentId,
                        principalTable: "Departments",
                        principalColumn: "DepartmentId",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_DmsTaskParticipants_DmsTasks_TaskId",
                        column: x => x.TaskId,
                        principalTable: "DmsTasks",
                        principalColumn: "TaskId",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_DmsTaskParticipants_Users_UserId",
                        column: x => x.UserId,
                        principalTable: "Users",
                        principalColumn: "UserId",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "IX_DmsTaskParticipants_CompanyId_DepartmentId",
                table: "DmsTaskParticipants",
                columns: new[] { "CompanyId", "DepartmentId" });

            migrationBuilder.CreateIndex(
                name: "IX_DmsTaskParticipants_CompanyId_UserId",
                table: "DmsTaskParticipants",
                columns: new[] { "CompanyId", "UserId" });

            migrationBuilder.CreateIndex(
                name: "IX_DmsTaskParticipants_DepartmentId",
                table: "DmsTaskParticipants",
                column: "DepartmentId");

            migrationBuilder.CreateIndex(
                name: "IX_DmsTaskParticipants_TaskId_DepartmentId",
                table: "DmsTaskParticipants",
                columns: new[] { "TaskId", "DepartmentId" },
                unique: true,
                filter: "[DepartmentId] IS NOT NULL AND [IsRemoved] = 0");

            migrationBuilder.CreateIndex(
                name: "IX_DmsTaskParticipants_TaskId_UserId",
                table: "DmsTaskParticipants",
                columns: new[] { "TaskId", "UserId" },
                unique: true,
                filter: "[UserId] IS NOT NULL AND [IsRemoved] = 0");

            migrationBuilder.CreateIndex(
                name: "IX_DmsTaskParticipants_UserId",
                table: "DmsTaskParticipants",
                column: "UserId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "DmsTaskParticipants");
        }
    }
}
