using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Dms.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddBookReplies : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // ⚠️ **الترتيب هنا يدويّ ومقصود، ويخالف ما ولّدته السقالة.**
            //    السقالة تُسقط العمودين **قبل** إنشاء الجدول ⇒ نقل البيانات مستحيل
            //    (وهو درس ADR-017 وADR-018 نفسه: إنشاء ← نقل ← إسقاط).
            //    🔴 **وإعادة توليد هذه المهاجرة تمحو التحرير أدناه صامتاً.**

            // ① إسقاط المفتاحين القديمين **أولاً** — والأعمدة تبقى للنقل.
            //    🔴 **ولولا هذا لرفض SQL Server إنشاء الجدول بخطأ 1785**: مع بقاء
            //    `FK_IncomingBooks_OutgoingBooks_ReplyOutgoingId` يصير من `OutgoingBooks`
            //    إلى `BookReplies` **مساران** (مباشرٌ، وعبر `IncomingBooks`) وكلاهما تعاقبيّ.
            migrationBuilder.DropForeignKey(
                name: "FK_IncomingBooks_OutgoingBooks_ReplyOutgoingId",
                table: "IncomingBooks");

            migrationBuilder.DropForeignKey(
                name: "FK_OutgoingBooks_IncomingBooks_ReplyToIncomingId",
                table: "OutgoingBooks");

            // ② إنشاء الجدول الجديد
            migrationBuilder.CreateTable(
                name: "BookReplies",
                columns: table => new
                {
                    BookReplyId = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    IncomingId = table.Column<int>(type: "int", nullable: false),
                    OutgoingId = table.Column<int>(type: "int", nullable: false),
                    CompanyId = table.Column<int>(type: "int", nullable: false),
                    LinkedByUserId = table.Column<int>(type: "int", nullable: true),
                    LinkedAt = table.Column<DateTime>(type: "datetime2", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_BookReplies", x => x.BookReplyId);
                    table.ForeignKey(
                        name: "FK_BookReplies_IncomingBooks_IncomingId",
                        column: x => x.IncomingId,
                        principalTable: "IncomingBooks",
                        principalColumn: "IncomingId",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_BookReplies_OutgoingBooks_OutgoingId",
                        column: x => x.OutgoingId,
                        principalTable: "OutgoingBooks",
                        principalColumn: "OutgoingId",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_BookReplies_IncomingId_OutgoingId",
                table: "BookReplies",
                columns: new[] { "IncomingId", "OutgoingId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_BookReplies_OutgoingId",
                table: "BookReplies",
                column: "OutgoingId");

            // ③ نقل البيانات — **من الاتجاهين معاً**.
            //    ⚠️ العمودان **غير متطابقين فعلاً**: حذفُ الوارد كان يُفرغ جهة الصادر ويترك
            //       جهته، وحذفُ الصادر لا يُفرغ شيئاً. فقراءةُ جهةٍ واحدة تُفقد روابط حقيقية.
            //    🔴 و`CompanyId` **يُشتقّ** — وقيمةٌ خاطئة تجعل الفلتر العام يُخفي كلَّ
            //       الردود بعد النشر **بلا خطأٍ واحد** (فشلٌ مغلق).
            //    ⚠️ و`LinkedByUserId` يبقى `NULL`: لا فاعلَ تاريخياً، و`0` يخرق أيّ مفتاح.
            //    ⚠️ **والأزواج المتباينة الشركة تُستبعَد** لا تُنقل — رابطٌ عابرٌ للشركات
            //       كان خرقاً للعزل أصلاً، ونقلُه يُشرعنه.
            migrationBuilder.Sql(@"
                INSERT INTO BookReplies (IncomingId, OutgoingId, CompanyId, LinkedByUserId, LinkedAt)
                SELECT i.IncomingId, i.ReplyOutgoingId, i.CompanyId, NULL,
                       ISNULL(i.UpdatedAt, i.CreatedAt)
                FROM IncomingBooks i
                INNER JOIN OutgoingBooks o ON o.OutgoingId = i.ReplyOutgoingId
                WHERE i.ReplyOutgoingId IS NOT NULL
                  AND o.CompanyId = i.CompanyId;");

            migrationBuilder.Sql(@"
                INSERT INTO BookReplies (IncomingId, OutgoingId, CompanyId, LinkedByUserId, LinkedAt)
                SELECT o.ReplyToIncomingId, o.OutgoingId, o.CompanyId, NULL,
                       ISNULL(o.UpdatedAt, o.CreatedAt)
                FROM OutgoingBooks o
                INNER JOIN IncomingBooks i ON i.IncomingId = o.ReplyToIncomingId
                WHERE o.ReplyToIncomingId IS NOT NULL
                  AND i.CompanyId = o.CompanyId
                  AND NOT EXISTS (
                      SELECT 1 FROM BookReplies r
                      WHERE r.IncomingId = o.ReplyToIncomingId AND r.OutgoingId = o.OutgoingId);");

            // ④ الفهرسان **قبل** العمودين — SQL Server لا يُسقط الفهرس مع عموده.
            migrationBuilder.DropIndex(
                name: "IX_OutgoingBooks_ReplyToIncomingId",
                table: "OutgoingBooks");

            migrationBuilder.DropIndex(
                name: "IX_IncomingBooks_ReplyOutgoingId",
                table: "IncomingBooks");

            // ⑤ إسقاط العمودين
            migrationBuilder.DropColumn(
                name: "ReplyToIncomingId",
                table: "OutgoingBooks");

            migrationBuilder.DropColumn(
                name: "ReplyOutgoingId",
                table: "IncomingBooks");
        }

        /// <inheritdoc />
        /// <remarks>
        /// 🔴 **الرجوع مُتلِفٌ للبيانات ولا مفرّ**: عمودٌ واحد لا يسع ردَّين، فواردٌ له ردّان
        /// يحتفظ بأقدمهما وحده، وصادرٌ أجاب ثلاثة واردات يحتفظ بأقدمها. **وهذا مقصودٌ ومُعلَن**
        /// — الرجوع لإصلاح نشرٍ فاشل لا لتشغيلٍ طويل.
        /// ⚠️ **و`DropTable` أوّلاً** وإلا أعاد إنشاءُ المفتاحين القديمين خطأ 1785 مجدداً.
        /// </remarks>
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "ReplyToIncomingId",
                table: "OutgoingBooks",
                type: "int",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "ReplyOutgoingId",
                table: "IncomingBooks",
                type: "int",
                nullable: true);

            // نقلٌ عكسيّ: **الأقدم وحده** لكل طرف (MIN على لحظة الربط ثم على المعرّف).
            migrationBuilder.Sql(@"
                UPDATE i SET i.ReplyOutgoingId = x.OutgoingId
                FROM IncomingBooks i
                INNER JOIN (
                    SELECT r.IncomingId,
                           OutgoingId = (SELECT TOP 1 r2.OutgoingId FROM BookReplies r2
                                         WHERE r2.IncomingId = r.IncomingId
                                         ORDER BY r2.LinkedAt, r2.BookReplyId)
                    FROM BookReplies r GROUP BY r.IncomingId
                ) x ON x.IncomingId = i.IncomingId;");

            migrationBuilder.Sql(@"
                UPDATE o SET o.ReplyToIncomingId = x.IncomingId
                FROM OutgoingBooks o
                INNER JOIN (
                    SELECT r.OutgoingId,
                           IncomingId = (SELECT TOP 1 r2.IncomingId FROM BookReplies r2
                                         WHERE r2.OutgoingId = r.OutgoingId
                                         ORDER BY r2.LinkedAt, r2.BookReplyId)
                    FROM BookReplies r GROUP BY r.OutgoingId
                ) x ON x.OutgoingId = o.OutgoingId;");

            migrationBuilder.DropTable(
                name: "BookReplies");

            migrationBuilder.CreateIndex(
                name: "IX_OutgoingBooks_ReplyToIncomingId",
                table: "OutgoingBooks",
                column: "ReplyToIncomingId");

            migrationBuilder.CreateIndex(
                name: "IX_IncomingBooks_ReplyOutgoingId",
                table: "IncomingBooks",
                column: "ReplyOutgoingId");

            migrationBuilder.AddForeignKey(
                name: "FK_IncomingBooks_OutgoingBooks_ReplyOutgoingId",
                table: "IncomingBooks",
                column: "ReplyOutgoingId",
                principalTable: "OutgoingBooks",
                principalColumn: "OutgoingId",
                onDelete: ReferentialAction.SetNull);

            migrationBuilder.AddForeignKey(
                name: "FK_OutgoingBooks_IncomingBooks_ReplyToIncomingId",
                table: "OutgoingBooks",
                column: "ReplyToIncomingId",
                principalTable: "IncomingBooks",
                principalColumn: "IncomingId",
                onDelete: ReferentialAction.SetNull);
        }
    }
}
