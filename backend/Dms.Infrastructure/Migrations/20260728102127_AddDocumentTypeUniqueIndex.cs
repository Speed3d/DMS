using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Dms.Infrastructure.Migrations
{
    /// <summary>
    /// اسم نوع المستند فريد داخل الشركة + بذر الأنواع الافتراضية للشركات القائمة.
    /// </summary>
    /// <remarks>
    /// ⚠️ **البذر جزء من المهاجرة لا من بذر الإقلاع** عمداً: بذر الإقلاع يعمل مع كل تشغيل،
    /// فلو أدرج «كل شركة بلا أنواع» لأعاد الأنواع التي حذفها المالك عمداً في كل مرّة.
    /// المهاجرة تعمل **مرّة واحدة** وتُسجَّل في `__EFMigrationsHistory` — وهذا هو السلوك
    /// الصحيح لتعبئة لمرّة واحدة. الشركات الجديدة تُبذَر من `CompaniesController.Create`.
    ///
    /// **الترتيب مقصود:** الفهرس الفريد **قبل** الإدراج، ليفشل الإدراج فوراً لو كان في القاعدة
    /// تكرارٌ سابق بدل أن يمرّ صامتاً. والإدراج مشروط بـ`NOT EXISTS` مزدوج: لا يمسّ شركةً
    /// تملك أنواعاً أصلاً (فلا نحشر أسماءنا في قائمة نظّمها المالك)، ولا يُكرّر اسماً موجوداً.
    /// </remarks>
    public partial class AddDocumentTypeUniqueIndex : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateIndex(
                name: "IX_DocumentTypes_CompanyId_Name",
                table: "DocumentTypes",
                columns: new[] { "CompanyId", "Name" },
                unique: true);

            migrationBuilder.Sql("""
                INSERT INTO DocumentTypes (CompanyId, Name)
                SELECT c.CompanyId, t.Name
                FROM Companies c
                CROSS JOIN (VALUES
                    (N'كتاب رسمي'), (N'فاتورة'), (N'عقد'), (N'مخطّط'),
                    (N'طلب عرض سعر'), (N'تقرير'), (N'شكوى'), (N'أخرى')
                ) AS t(Name)
                WHERE NOT EXISTS (SELECT 1 FROM DocumentTypes d WHERE d.CompanyId = c.CompanyId)
                  AND NOT EXISTS (SELECT 1 FROM DocumentTypes d2
                                  WHERE d2.CompanyId = c.CompanyId AND d2.Name = t.Name);
                """);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            // لا نحذف الأنواع المبذورة: قد تكون كتبٌ ربطت نفسها بها بعد الترقية،
            // وحذفها يكسر تلك المراجع. التراجع يقتصر على الفهرس.
            migrationBuilder.DropIndex(
                name: "IX_DocumentTypes_CompanyId_Name",
                table: "DocumentTypes");
        }
    }
}
