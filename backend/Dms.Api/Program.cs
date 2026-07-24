using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using System.Text.Json.Serialization;
using Dms.Api.Auth;
using Dms.Api.Middleware;
using Dms.Api.Ops;
using Dms.Api.Seeding;
using Dms.Documents.Storage;
using Dms.Infrastructure;
using Dms.Infrastructure.Auth;
using Dms.Infrastructure.Services;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Http.Features;
using Microsoft.IdentityModel.Tokens;
using Microsoft.OpenApi.Models;

// وضع أدوات التشغيل: توليد أسرار الإنتاج ثم الخروج (لا يُقلع الخادم).
// Hint: يُستدعى مرة واحدة على السيرفر — Dms.Api.exe generate-secrets --out <مسار>
if (args.Length > 0 && args[0].Equals("generate-secrets", StringComparison.OrdinalIgnoreCase))
    return SecretsGenerator.Run(args);

var builder = WebApplication.CreateBuilder(args);

// تشغيل كخدمة ويندوز على السيرفر (تبدأ مع الإقلاع وتتعافى من التعطّل تلقائياً).
// Hint: عديم الأثر عند التشغيل العادي بـ dotnet run — يُفعَّل فقط حين يستضيف مدير خدمات ويندوز العملية.
//       التسجيل: sc.exe create DmsApi binPath= "<مسار>\Dms.Api.exe" start= auto
builder.Host.UseWindowsService(o => o.ServiceName = "DMS API");

// حدود حجم الطلب: المرفق الأقصى 50 ميغابايت (AttachmentService) + هامش لترويسات multipart.
// Hint: بدون هذا يقطع Kestrel الطلب عند ~28 ميغابايت بـ 413 غامض قبل وصوله للخدمة،
// فيتعذّر تحقيق حد الـ 50 ميغابايت. الهامش يجعل الرفض يأتي من الخدمة برسالة عربية واضحة.
const long MaxUploadBytes = 55 * 1024 * 1024;
builder.WebHost.ConfigureKestrel(o => o.Limits.MaxRequestBodySize = MaxUploadBytes);
builder.Services.Configure<FormOptions>(o => o.MultipartBodyLengthLimit = MaxUploadBytes);

// ----- الخدمات -----
builder.Services.AddControllers().AddJsonOptions(o =>
    o.JsonSerializerOptions.Converters.Add(new JsonStringEnumConverter()));

builder.Services.AddInfrastructure(builder.Configuration);
builder.Services.AddHttpContextAccessor();
builder.Services.AddScoped<ICurrentUser, HttpCurrentUser>();

// تخزين الملفات: محلي للتطوير (يُستبدَل بـ Azure Blob في الإنتاج)
var storageRoot = builder.Configuration["Storage:LocalRoot"];
if (string.IsNullOrWhiteSpace(storageRoot))
    storageRoot = Path.Combine(builder.Environment.ContentRootPath, "App_Data", "storage");
builder.Services.AddSingleton<IFileStorage>(new LocalFileStorage(storageRoot));

// مسارات النظام (تخزين + نسخ احتياطي)
var backupDir = builder.Configuration["Backup:Dir"];
if (string.IsNullOrWhiteSpace(backupDir))
    backupDir = Path.Combine(builder.Environment.ContentRootPath, "App_Data", "Backups");
builder.Services.AddSingleton(new AppPaths(storageRoot, backupDir));

// ----- المصادقة JWT -----
var jwt = builder.Configuration.GetSection(JwtSettings.Section).Get<JwtSettings>() ?? new JwtSettings();

// فشل سريع: في الإنتاج يجب أن تكون الأسرار مُهيّأة صحيحةً (بيئة/Key Vault) قبل التشغيل.
if (!builder.Environment.IsDevelopment())
{
    var missing = new List<string>();
    if (string.IsNullOrWhiteSpace(jwt.SigningKey) || Encoding.UTF8.GetByteCount(jwt.SigningKey) < 32)
        missing.Add("Jwt:SigningKey (≥ 32 بايت لـ HMAC-SHA256)");
    if (string.IsNullOrWhiteSpace(builder.Configuration["QrSigning:PrivateKeyBase64"]))
        missing.Add("QrSigning:PrivateKeyBase64");
    if (string.IsNullOrWhiteSpace(builder.Configuration["QrSigning:PublicKeyBase64"]))
        missing.Add("QrSigning:PublicKeyBase64");
    if (string.IsNullOrWhiteSpace(builder.Configuration.GetConnectionString("Default")))
        missing.Add("ConnectionStrings:Default");
    if (missing.Count > 0)
        throw new InvalidOperationException(
            "أسرار الإنتاج ناقصة أو غير صالحة: " + string.Join("، ", missing) +
            ". هيّئها عبر متغيّرات البيئة أو Azure Key Vault قبل التشغيل.");
}

JwtSecurityTokenHandler.DefaultMapInboundClaims = false;
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(o =>
    {
        o.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidIssuer = jwt.Issuer,
            ValidateAudience = true,
            ValidAudience = jwt.Audience,
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwt.SigningKey)),
            ValidateLifetime = true,
            ClockSkew = TimeSpan.FromSeconds(30),
            RoleClaimType = ClaimTypes.Role,
            NameClaimType = ClaimTypes.Name,
        };
    });
builder.Services.AddAuthorization();

builder.Services.AddCors(o => o.AddPolicy("all", p =>
{
    if (builder.Environment.IsDevelopment())
    {
        p.AllowAnyOrigin().AllowAnyHeader().AllowAnyMethod();
    }
    else
    {
        // الإنتاج: يُسمح فقط بالأصول المُهيّأة صراحةً في `AllowedOrigins` (مفصولة بـ ;).
        // بلا تهيئة ⇒ لا أصل مسموح (fail-closed) — لا نعود لـ AllowAnyOrigin.
        var allowedOrigins = builder.Configuration["AllowedOrigins"]?.Split(';', StringSplitOptions.RemoveEmptyEntries) ?? [];
        p.WithOrigins(allowedOrigins).AllowAnyHeader().AllowAnyMethod();
    }
}));

// ----- Swagger مع دعم Bearer -----
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new OpenApiInfo { Title = "DMS API", Version = "v1" });
    var scheme = new OpenApiSecurityScheme
    {
        Name = "Authorization",
        Type = SecuritySchemeType.Http,
        Scheme = "bearer",
        BearerFormat = "JWT",
        In = ParameterLocation.Header,
        Reference = new OpenApiReference { Type = ReferenceType.SecurityScheme, Id = "Bearer" }
    };
    c.AddSecurityDefinition("Bearer", scheme);
    c.AddSecurityRequirement(new OpenApiSecurityRequirement { [scheme] = Array.Empty<string>() });
});

var app = builder.Build();

// ----- الـ Pipeline -----
app.UseMiddleware<ExceptionMiddleware>();
// يجب أن يسبق المصادقة: يرفض الطلبات بـ 503 أثناء الصيانة (الاستعادة) قبل لمس قاعدة البيانات.
app.UseMiddleware<MaintenanceMiddleware>();
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}
else
{
    app.UseHttpsRedirection();
}
app.UseCors("all");
app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();

// ----- تهيئة قاعدة البيانات + Seed -----
await DbSeeder.MigrateAndSeedAsync(app.Services, app.Configuration,
    app.Services.GetRequiredService<ILogger<Program>>());

app.Run();
return 0; // لازم لأن وضع أدوات التشغيل أعلاه يُرجع رمز خروج

public partial class Program; // لإتاحة اختبارات التكامل لاحقاً
