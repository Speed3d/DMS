using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Dms.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class InitialCreate : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "ApprovalDelegations",
                columns: table => new
                {
                    DelegationId = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    CompanyId = table.Column<int>(type: "int", nullable: false),
                    FromUserId = table.Column<int>(type: "int", nullable: false),
                    ToUserId = table.Column<int>(type: "int", nullable: false),
                    StartDate = table.Column<DateTime>(type: "datetime2", nullable: false),
                    EndDate = table.Column<DateTime>(type: "datetime2", nullable: true),
                    IsActive = table.Column<bool>(type: "bit", nullable: false),
                    CreatedByUserId = table.Column<int>(type: "int", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "datetime2", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ApprovalDelegations", x => x.DelegationId);
                });

            migrationBuilder.CreateTable(
                name: "ArchiveDocs",
                columns: table => new
                {
                    ArchiveId = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    CompanyId = table.Column<int>(type: "int", nullable: false),
                    ArchiveNumber = table.Column<string>(type: "nvarchar(40)", maxLength: 40, nullable: false),
                    Title = table.Column<string>(type: "nvarchar(500)", maxLength: 500, nullable: false),
                    BookNumber = table.Column<string>(type: "nvarchar(max)", nullable: true),
                    BookDate = table.Column<DateTime>(type: "datetime2", nullable: true),
                    FromEntityId = table.Column<int>(type: "int", nullable: true),
                    ToEntityId = table.Column<int>(type: "int", nullable: true),
                    DocumentTypeId = table.Column<int>(type: "int", nullable: true),
                    Amount = table.Column<decimal>(type: "decimal(18,2)", precision: 18, scale: 2, nullable: true),
                    Currency = table.Column<int>(type: "int", nullable: true),
                    ExchangeRate = table.Column<decimal>(type: "decimal(18,4)", precision: 18, scale: 4, nullable: true),
                    AmountInIqd = table.Column<decimal>(type: "decimal(18,2)", precision: 18, scale: 2, nullable: true),
                    Keywords = table.Column<string>(type: "nvarchar(1000)", maxLength: 1000, nullable: true),
                    Notes = table.Column<string>(type: "nvarchar(max)", nullable: true),
                    CreatedByUserId = table.Column<int>(type: "int", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "datetime2", nullable: false),
                    IsDeleted = table.Column<bool>(type: "bit", nullable: false),
                    DeletedByUserId = table.Column<int>(type: "int", nullable: true),
                    DeletedAt = table.Column<DateTime>(type: "datetime2", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ArchiveDocs", x => x.ArchiveId);
                });

            migrationBuilder.CreateTable(
                name: "Attachments",
                columns: table => new
                {
                    AttachmentId = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    OwnerType = table.Column<int>(type: "int", nullable: false),
                    OwnerId = table.Column<int>(type: "int", nullable: false),
                    FileName = table.Column<string>(type: "nvarchar(300)", maxLength: 300, nullable: false),
                    BlobKey = table.Column<string>(type: "nvarchar(400)", maxLength: 400, nullable: false),
                    FileType = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: false),
                    FileSize = table.Column<long>(type: "bigint", nullable: false),
                    UploadedByUserId = table.Column<int>(type: "int", nullable: false),
                    UploadedAt = table.Column<DateTime>(type: "datetime2", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Attachments", x => x.AttachmentId);
                });

            migrationBuilder.CreateTable(
                name: "AuditLogs",
                columns: table => new
                {
                    LogId = table.Column<long>(type: "bigint", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    UserId = table.Column<int>(type: "int", nullable: true),
                    CompanyId = table.Column<int>(type: "int", nullable: true),
                    Action = table.Column<string>(type: "nvarchar(50)", maxLength: 50, nullable: false),
                    EntityType = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: false),
                    EntityId = table.Column<string>(type: "nvarchar(50)", maxLength: 50, nullable: true),
                    Details = table.Column<string>(type: "nvarchar(2000)", maxLength: 2000, nullable: true),
                    Timestamp = table.Column<DateTime>(type: "datetime2", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_AuditLogs", x => x.LogId);
                });

            migrationBuilder.CreateTable(
                name: "Companies",
                columns: table => new
                {
                    CompanyId = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    Name = table.Column<string>(type: "nvarchar(200)", maxLength: 200, nullable: false),
                    Prefix = table.Column<string>(type: "nvarchar(20)", maxLength: 20, nullable: false),
                    IsActive = table.Column<bool>(type: "bit", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "datetime2", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Companies", x => x.CompanyId);
                });

            migrationBuilder.CreateTable(
                name: "Counters",
                columns: table => new
                {
                    CompanyId = table.Column<int>(type: "int", nullable: false),
                    Year = table.Column<int>(type: "int", nullable: false),
                    Type = table.Column<string>(type: "nvarchar(20)", maxLength: 20, nullable: false),
                    LastNumber = table.Column<int>(type: "int", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Counters", x => new { x.CompanyId, x.Year, x.Type });
                });

            migrationBuilder.CreateTable(
                name: "DocumentTypes",
                columns: table => new
                {
                    DocumentTypeId = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    CompanyId = table.Column<int>(type: "int", nullable: false),
                    Name = table.Column<string>(type: "nvarchar(200)", maxLength: 200, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_DocumentTypes", x => x.DocumentTypeId);
                });

            migrationBuilder.CreateTable(
                name: "DocumentVersions",
                columns: table => new
                {
                    VersionId = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    DocType = table.Column<int>(type: "int", nullable: false),
                    DocId = table.Column<int>(type: "int", nullable: false),
                    VersionNo = table.Column<int>(type: "int", nullable: false),
                    SnapshotJson = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    ChangedByUserId = table.Column<int>(type: "int", nullable: false),
                    ChangedAt = table.Column<DateTime>(type: "datetime2", nullable: false),
                    ChangeNote = table.Column<string>(type: "nvarchar(max)", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_DocumentVersions", x => x.VersionId);
                });

            migrationBuilder.CreateTable(
                name: "Entities",
                columns: table => new
                {
                    EntityId = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    CompanyId = table.Column<int>(type: "int", nullable: false),
                    Name = table.Column<string>(type: "nvarchar(300)", maxLength: 300, nullable: false),
                    Kind = table.Column<int>(type: "int", nullable: false),
                    Notes = table.Column<string>(type: "nvarchar(max)", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Entities", x => x.EntityId);
                });

            migrationBuilder.CreateTable(
                name: "ExchangeRates",
                columns: table => new
                {
                    ExchangeRateId = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    Currency = table.Column<int>(type: "int", nullable: false),
                    Rate = table.Column<decimal>(type: "decimal(18,4)", precision: 18, scale: 4, nullable: false),
                    EffectiveDate = table.Column<DateTime>(type: "datetime2", nullable: false),
                    CreatedByUserId = table.Column<int>(type: "int", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "datetime2", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ExchangeRates", x => x.ExchangeRateId);
                });

            migrationBuilder.CreateTable(
                name: "RefreshTokens",
                columns: table => new
                {
                    RefreshTokenId = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    UserId = table.Column<int>(type: "int", nullable: false),
                    TokenHash = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: false),
                    ExpiresAt = table.Column<DateTime>(type: "datetime2", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "datetime2", nullable: false),
                    RevokedAt = table.Column<DateTime>(type: "datetime2", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_RefreshTokens", x => x.RefreshTokenId);
                });

            migrationBuilder.CreateTable(
                name: "Users",
                columns: table => new
                {
                    UserId = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    FullName = table.Column<string>(type: "nvarchar(200)", maxLength: 200, nullable: false),
                    Username = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: false),
                    PasswordHash = table.Column<string>(type: "nvarchar(200)", maxLength: 200, nullable: false),
                    Role = table.Column<int>(type: "int", nullable: false),
                    CompanyId = table.Column<int>(type: "int", nullable: true),
                    CanApprove = table.Column<bool>(type: "bit", nullable: false),
                    IsActive = table.Column<bool>(type: "bit", nullable: false),
                    MustChangePassword = table.Column<bool>(type: "bit", nullable: false),
                    FailedLoginCount = table.Column<int>(type: "int", nullable: false),
                    LockedUntil = table.Column<DateTime>(type: "datetime2", nullable: true),
                    CreatedByUserId = table.Column<int>(type: "int", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "datetime2", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Users", x => x.UserId);
                });

            migrationBuilder.CreateTable(
                name: "Templates",
                columns: table => new
                {
                    TemplateId = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    CompanyId = table.Column<int>(type: "int", nullable: false),
                    Name = table.Column<string>(type: "nvarchar(200)", maxLength: 200, nullable: false),
                    HeaderImageKey = table.Column<string>(type: "nvarchar(max)", nullable: true),
                    FooterImageKey = table.Column<string>(type: "nvarchar(max)", nullable: true),
                    WatermarkImageKey = table.Column<string>(type: "nvarchar(max)", nullable: true),
                    WatermarkOpacity = table.Column<int>(type: "int", nullable: false),
                    MarginTop = table.Column<int>(type: "int", nullable: false),
                    MarginRight = table.Column<int>(type: "int", nullable: false),
                    MarginBottom = table.Column<int>(type: "int", nullable: false),
                    MarginLeft = table.Column<int>(type: "int", nullable: false),
                    PageSize = table.Column<string>(type: "nvarchar(10)", maxLength: 10, nullable: false),
                    FontFamily = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: false),
                    IsActive = table.Column<bool>(type: "bit", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "datetime2", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "datetime2", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Templates", x => x.TemplateId);
                    table.ForeignKey(
                        name: "FK_Templates_Companies_CompanyId",
                        column: x => x.CompanyId,
                        principalTable: "Companies",
                        principalColumn: "CompanyId",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "UserCompanies",
                columns: table => new
                {
                    UserCompanyId = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    UserId = table.Column<int>(type: "int", nullable: false),
                    CompanyId = table.Column<int>(type: "int", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_UserCompanies", x => x.UserCompanyId);
                    table.ForeignKey(
                        name: "FK_UserCompanies_Users_UserId",
                        column: x => x.UserId,
                        principalTable: "Users",
                        principalColumn: "UserId",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "OutgoingBooks",
                columns: table => new
                {
                    OutgoingId = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    CompanyId = table.Column<int>(type: "int", nullable: false),
                    Number = table.Column<string>(type: "nvarchar(40)", maxLength: 40, nullable: true),
                    Year = table.Column<int>(type: "int", nullable: true),
                    SerialNo = table.Column<int>(type: "int", nullable: true),
                    Date = table.Column<DateTime>(type: "datetime2", nullable: false),
                    EntityId = table.Column<int>(type: "int", nullable: false),
                    Subject = table.Column<string>(type: "nvarchar(500)", maxLength: 500, nullable: false),
                    BodyHtml = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    TemplateId = table.Column<int>(type: "int", nullable: false),
                    Status = table.Column<int>(type: "int", nullable: false),
                    Amount = table.Column<decimal>(type: "decimal(18,2)", precision: 18, scale: 2, nullable: true),
                    Currency = table.Column<int>(type: "int", nullable: true),
                    ExchangeRate = table.Column<decimal>(type: "decimal(18,4)", precision: 18, scale: 4, nullable: true),
                    AmountInIqd = table.Column<decimal>(type: "decimal(18,2)", precision: 18, scale: 2, nullable: true),
                    QrContent = table.Column<string>(type: "nvarchar(max)", nullable: true),
                    QrSignature = table.Column<string>(type: "nvarchar(max)", nullable: true),
                    GeneratedPdfBlobKey = table.Column<string>(type: "nvarchar(max)", nullable: true),
                    CreatedByUserId = table.Column<int>(type: "int", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "datetime2", nullable: false),
                    ApprovedByUserId = table.Column<int>(type: "int", nullable: true),
                    ApprovedAt = table.Column<DateTime>(type: "datetime2", nullable: true),
                    UpdatedAt = table.Column<DateTime>(type: "datetime2", nullable: true),
                    IsDeleted = table.Column<bool>(type: "bit", nullable: false),
                    DeletedByUserId = table.Column<int>(type: "int", nullable: true),
                    DeletedAt = table.Column<DateTime>(type: "datetime2", nullable: true),
                    RowVersion = table.Column<byte[]>(type: "rowversion", rowVersion: true, nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_OutgoingBooks", x => x.OutgoingId);
                    table.ForeignKey(
                        name: "FK_OutgoingBooks_Entities_EntityId",
                        column: x => x.EntityId,
                        principalTable: "Entities",
                        principalColumn: "EntityId",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_OutgoingBooks_Templates_TemplateId",
                        column: x => x.TemplateId,
                        principalTable: "Templates",
                        principalColumn: "TemplateId",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "IX_ArchiveDocs_CompanyId_ArchiveNumber",
                table: "ArchiveDocs",
                columns: new[] { "CompanyId", "ArchiveNumber" });

            migrationBuilder.CreateIndex(
                name: "IX_Attachments_OwnerType_OwnerId",
                table: "Attachments",
                columns: new[] { "OwnerType", "OwnerId" });

            migrationBuilder.CreateIndex(
                name: "IX_AuditLogs_Timestamp",
                table: "AuditLogs",
                column: "Timestamp");

            migrationBuilder.CreateIndex(
                name: "IX_Companies_Prefix",
                table: "Companies",
                column: "Prefix",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_DocumentVersions_DocType_DocId_VersionNo",
                table: "DocumentVersions",
                columns: new[] { "DocType", "DocId", "VersionNo" });

            migrationBuilder.CreateIndex(
                name: "IX_Entities_CompanyId_Name",
                table: "Entities",
                columns: new[] { "CompanyId", "Name" });

            migrationBuilder.CreateIndex(
                name: "IX_ExchangeRates_Currency_EffectiveDate",
                table: "ExchangeRates",
                columns: new[] { "Currency", "EffectiveDate" });

            migrationBuilder.CreateIndex(
                name: "IX_OutgoingBooks_CompanyId_Year_SerialNo",
                table: "OutgoingBooks",
                columns: new[] { "CompanyId", "Year", "SerialNo" },
                unique: true,
                filter: "[SerialNo] IS NOT NULL");

            migrationBuilder.CreateIndex(
                name: "IX_OutgoingBooks_EntityId",
                table: "OutgoingBooks",
                column: "EntityId");

            migrationBuilder.CreateIndex(
                name: "IX_OutgoingBooks_Number",
                table: "OutgoingBooks",
                column: "Number",
                unique: true,
                filter: "[Number] IS NOT NULL");

            migrationBuilder.CreateIndex(
                name: "IX_OutgoingBooks_TemplateId",
                table: "OutgoingBooks",
                column: "TemplateId");

            migrationBuilder.CreateIndex(
                name: "IX_RefreshTokens_TokenHash",
                table: "RefreshTokens",
                column: "TokenHash");

            migrationBuilder.CreateIndex(
                name: "IX_Templates_CompanyId",
                table: "Templates",
                column: "CompanyId");

            migrationBuilder.CreateIndex(
                name: "IX_UserCompanies_UserId_CompanyId",
                table: "UserCompanies",
                columns: new[] { "UserId", "CompanyId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_Users_Username",
                table: "Users",
                column: "Username",
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "ApprovalDelegations");

            migrationBuilder.DropTable(
                name: "ArchiveDocs");

            migrationBuilder.DropTable(
                name: "Attachments");

            migrationBuilder.DropTable(
                name: "AuditLogs");

            migrationBuilder.DropTable(
                name: "Counters");

            migrationBuilder.DropTable(
                name: "DocumentTypes");

            migrationBuilder.DropTable(
                name: "DocumentVersions");

            migrationBuilder.DropTable(
                name: "ExchangeRates");

            migrationBuilder.DropTable(
                name: "OutgoingBooks");

            migrationBuilder.DropTable(
                name: "RefreshTokens");

            migrationBuilder.DropTable(
                name: "UserCompanies");

            migrationBuilder.DropTable(
                name: "Entities");

            migrationBuilder.DropTable(
                name: "Templates");

            migrationBuilder.DropTable(
                name: "Users");

            migrationBuilder.DropTable(
                name: "Companies");
        }
    }
}
