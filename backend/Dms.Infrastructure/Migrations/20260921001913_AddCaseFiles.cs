using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Dms.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddCaseFiles : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "CaseFileId",
                table: "OutgoingBooks",
                type: "int",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "CaseFileId",
                table: "IncomingBooks",
                type: "int",
                nullable: true);

            migrationBuilder.CreateTable(
                name: "CaseFiles",
                columns: table => new
                {
                    CaseFileId = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    CompanyId = table.Column<int>(type: "int", nullable: false),
                    Title = table.Column<string>(type: "nvarchar(200)", maxLength: 200, nullable: false),
                    Notes = table.Column<string>(type: "nvarchar(1000)", maxLength: 1000, nullable: true),
                    CreatedByUserId = table.Column<int>(type: "int", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "datetime2", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "datetime2", nullable: true),
                    RowVersion = table.Column<byte[]>(type: "rowversion", rowVersion: true, nullable: true),
                    IsDeleted = table.Column<bool>(type: "bit", nullable: false),
                    DeletedByUserId = table.Column<int>(type: "int", nullable: true),
                    DeletedAt = table.Column<DateTime>(type: "datetime2", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_CaseFiles", x => x.CaseFileId);
                });

            migrationBuilder.CreateIndex(
                name: "IX_OutgoingBooks_CaseFileId",
                table: "OutgoingBooks",
                column: "CaseFileId");

            migrationBuilder.CreateIndex(
                name: "IX_IncomingBooks_CaseFileId",
                table: "IncomingBooks",
                column: "CaseFileId");

            migrationBuilder.CreateIndex(
                name: "IX_CaseFiles_CompanyId_Title",
                table: "CaseFiles",
                columns: new[] { "CompanyId", "Title" });

            migrationBuilder.AddForeignKey(
                name: "FK_IncomingBooks_CaseFiles_CaseFileId",
                table: "IncomingBooks",
                column: "CaseFileId",
                principalTable: "CaseFiles",
                principalColumn: "CaseFileId",
                onDelete: ReferentialAction.SetNull);

            migrationBuilder.AddForeignKey(
                name: "FK_OutgoingBooks_CaseFiles_CaseFileId",
                table: "OutgoingBooks",
                column: "CaseFileId",
                principalTable: "CaseFiles",
                principalColumn: "CaseFileId",
                onDelete: ReferentialAction.SetNull);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_IncomingBooks_CaseFiles_CaseFileId",
                table: "IncomingBooks");

            migrationBuilder.DropForeignKey(
                name: "FK_OutgoingBooks_CaseFiles_CaseFileId",
                table: "OutgoingBooks");

            migrationBuilder.DropTable(
                name: "CaseFiles");

            migrationBuilder.DropIndex(
                name: "IX_OutgoingBooks_CaseFileId",
                table: "OutgoingBooks");

            migrationBuilder.DropIndex(
                name: "IX_IncomingBooks_CaseFileId",
                table: "IncomingBooks");

            migrationBuilder.DropColumn(
                name: "CaseFileId",
                table: "OutgoingBooks");

            migrationBuilder.DropColumn(
                name: "CaseFileId",
                table: "IncomingBooks");
        }
    }
}
