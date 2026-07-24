using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Nodes;
using Dms.Documents.Security;

namespace Dms.Api.Ops;

/// <summary>
/// توليد ملف أسرار الإنتاج (JWT + مفاتيح توقيع QR) — يُشغَّل مرة واحدة على السيرفر.
///
/// الاستخدام:
///   Dms.Api.exe generate-secrets --out C:\DMS\api\appsettings.Production.json --origins https://dms.example.com
///
/// Hint: وُضع داخل الـ API لا في سكربت PowerShell لأن توليد ECDSA P-256 يتطلب واجهات .NET Core
///       (ExportPkcs8PrivateKey) غير المتوفّرة في PowerShell 5.1 المرافق لويندوز. والـ exe موجود
///       على السيرفر أصلاً، فلا يحتاج المالك تثبيت أي أدوات إضافية.
///
/// ⚠️ تغيير مفتاح توقيع QR لاحقاً **يُبطل التحقق من كل الكتب الموقّعة سابقاً** —
///    ولّده مرة واحدة قبل أول كتاب رسمي واحتفظ بنسخة آمنة منه خارج السيرفر.
/// </summary>
public static class SecretsGenerator
{
    public static int Run(string[] args)
    {
        var opts = Parse(args);
        if (!opts.TryGetValue("out", out var outFile) || string.IsNullOrWhiteSpace(outFile))
        {
            Console.Error.WriteLine("الاستخدام: Dms.Api.exe generate-secrets --out <مسار appsettings.Production.json> [--origins https://…] [--db-server .] [--db-name DmsDb] [--storage <مسار>] [--backup <مسار>] [--force]");
            return 1;
        }

        var force = opts.ContainsKey("force");
        if (File.Exists(outFile) && !force)
        {
            Console.Error.WriteLine($"✖ الملف موجود مسبقاً: {outFile}");
            Console.Error.WriteLine("  الكتابة فوقه تُبدّل مفاتيح التوقيع وتُبطل التحقق من الكتب السابقة.");
            Console.Error.WriteLine("  إن كنت متأكداً، أضِف --force بعد أخذ نسخة من الملف الحالي.");
            return 1;
        }

        var dbServer = opts.GetValueOrDefault("db-server", ".");
        var dbName = opts.GetValueOrDefault("db-name", "DmsDb");
        var origins = opts.GetValueOrDefault("origins", "");
        var storage = opts.GetValueOrDefault("storage", @"C:\DMS\data\storage");
        var backup = opts.GetValueOrDefault("backup", @"C:\DMS\data\backups");

        Console.WriteLine("توليد أسرار الإنتاج...");

        // مفتاح JWT: 64 بايت عشوائي (الحد الأدنى الذي يفرضه الإقلاع هو 32 بايت لـ HMAC-SHA256).
        var jwtBytes = RandomNumberGenerator.GetBytes(64);
        var jwtKey = Convert.ToBase64String(jwtBytes);
        Console.WriteLine("  ✔ مفتاح JWT (64 بايت)");

        // زوج مفاتيح QR — نفس المولّد الذي يستخدمه التوقيع والتحقق، فلا احتمال لعدم التطابق.
        var (privateKey, publicKey) = QrSigner.GenerateKeyPair();
        Console.WriteLine("  ✔ زوج مفاتيح QR (ECDSA P-256)");

        var json = new JsonObject
        {
            ["ConnectionStrings"] = new JsonObject
            {
                ["Default"] = $"Server={dbServer};Database={dbName};Integrated Security=true;MultipleActiveResultSets=true;TrustServerCertificate=True",
            },
            ["Jwt"] = new JsonObject { ["SigningKey"] = jwtKey },
            ["QrSigning"] = new JsonObject
            {
                ["PrivateKeyBase64"] = privateKey,
                ["PublicKeyBase64"] = publicKey,
            },
            ["Storage"] = new JsonObject { ["LocalRoot"] = storage },
            ["Backup"] = new JsonObject { ["Dir"] = backup },
            ["AllowedOrigins"] = origins,
        };

        // Hint: أداة تشغيل يستعملها المالك — نُظهر سبباً واضحاً بدل تعطّل خام عند مشاكل الصلاحيات/المسار.
        try
        {
            var dir = Path.GetDirectoryName(Path.GetFullPath(outFile));
            if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
            File.WriteAllText(outFile, json.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
        }
        catch (UnauthorizedAccessException)
        {
            Console.Error.WriteLine($"✖ لا تملك صلاحية الكتابة في: {outFile}");
            Console.Error.WriteLine("  شغّل نافذة الأوامر «كمسؤول» (Run as administrator) وأعد المحاولة.");
            return 1;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"✖ تعذّرت كتابة الملف: {ex.Message}");
            return 1;
        }

        Console.WriteLine($"\n✔ كُتب الملف: {outFile}");
        Console.WriteLine($"""

            الخطوات التالية (مهمة):
              1) خُذ نسخة من هذا الملف واحفظها في مكان آمن **خارج السيرفر**.
                 (لو تعطّل الجهاز وفُقد مفتاح QR، لن يمكن التحقق من الكتب القديمة.)
              2) شدّد صلاحيات الملف على حساب الخدمة فقط:
                 icacls "{outFile}" /inheritance:r /grant:r "SYSTEM:(R)" /grant:r "Administrators:(F)"
              3) تأكّد أن BitLocker مفعّل على القرص.
              4) اضبط AllowedOrigins على دومين النظام قبل التشغيل
                 (الإنتاج يفشل مغلقاً: بلا تهيئة = لا أصل مسموح).
            """);
        return 0;
    }

    /// <summary>يحلّل وسائط بصيغة --key value أو --flag (Hint: بسيط عمداً — أداة تشغيل لا واجهة عامة).</summary>
    private static Dictionary<string, string> Parse(string[] args)
    {
        var map = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        for (var i = 0; i < args.Length; i++)
        {
            if (!args[i].StartsWith("--", StringComparison.Ordinal)) continue;
            var key = args[i][2..];
            var hasValue = i + 1 < args.Length && !args[i + 1].StartsWith("--", StringComparison.Ordinal);
            map[key] = hasValue ? args[++i] : "true";
        }
        return map;
    }
}
