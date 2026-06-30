using Dms.Infrastructure.Services;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace Dms.Infrastructure.Persistence;

/// <summary>
/// مصنع زمن التصميم — يستخدمه dotnet-ef لإنشاء الـ Migrations دون تشغيل الـ API.
/// (سلسلة الاتصال هنا للتصميم فقط؛ التشغيل الفعلي يقرأ من appsettings.)
/// </summary>
public sealed class AppDbContextFactory : IDesignTimeDbContextFactory<AppDbContext>
{
    public AppDbContext CreateDbContext(string[] args)
    {
        const string conn =
            @"Server=(localdb)\MSSQLLocalDB;Database=DmsDb;Trusted_Connection=True;" +
            "MultipleActiveResultSets=true;TrustServerCertificate=True";

        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlServer(conn)
            .Options;

        return new AppDbContext(options, new SystemUser());
    }
}
