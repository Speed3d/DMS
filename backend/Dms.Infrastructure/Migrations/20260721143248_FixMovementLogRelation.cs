using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Dms.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class FixMovementLogRelation : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // ترحيل البيانات قبل حذف العمود الشبح:
            // حركات أُنشئت عبر خاصية التنقّل كان EF يملأ لها IncomingBookIncomingId ويترك IncomingId = 0
            // (فتختفي من سجل الحركة). نُعيد ربطها بالمعرّف الصحيح.
            migrationBuilder.Sql(@"
                UPDATE [MovementLogs]
                SET [IncomingId] = [IncomingBookIncomingId]
                WHERE [IncomingBookIncomingId] IS NOT NULL AND ([IncomingId] = 0 OR [IncomingId] IS NULL);");

            // حذف أي حركات يتيمة لا تشير لكتاب موجود (وإلا فشل قيد المفتاح الأجنبي أدناه).
            migrationBuilder.Sql(@"
                DELETE FROM [MovementLogs]
                WHERE NOT EXISTS (SELECT 1 FROM [IncomingBooks] b WHERE b.[IncomingId] = [MovementLogs].[IncomingId]);");

            migrationBuilder.DropForeignKey(
                name: "FK_MovementLogs_IncomingBooks_IncomingBookIncomingId",
                table: "MovementLogs");

            migrationBuilder.DropIndex(
                name: "IX_MovementLogs_IncomingBookIncomingId",
                table: "MovementLogs");

            migrationBuilder.DropColumn(
                name: "IncomingBookIncomingId",
                table: "MovementLogs");

            migrationBuilder.AddForeignKey(
                name: "FK_MovementLogs_IncomingBooks_IncomingId",
                table: "MovementLogs",
                column: "IncomingId",
                principalTable: "IncomingBooks",
                principalColumn: "IncomingId",
                onDelete: ReferentialAction.Cascade);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_MovementLogs_IncomingBooks_IncomingId",
                table: "MovementLogs");

            migrationBuilder.AddColumn<int>(
                name: "IncomingBookIncomingId",
                table: "MovementLogs",
                type: "int",
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_MovementLogs_IncomingBookIncomingId",
                table: "MovementLogs",
                column: "IncomingBookIncomingId");

            migrationBuilder.AddForeignKey(
                name: "FK_MovementLogs_IncomingBooks_IncomingBookIncomingId",
                table: "MovementLogs",
                column: "IncomingBookIncomingId",
                principalTable: "IncomingBooks",
                principalColumn: "IncomingId");
        }
    }
}
