using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using System.Text.Json.Serialization;
using Dms.Api.Auth;
using Dms.Api.Middleware;
using Dms.Api.Seeding;
using Dms.Documents.Storage;
using Dms.Infrastructure;
using Dms.Infrastructure.Auth;
using Dms.Infrastructure.Services;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.IdentityModel.Tokens;
using Microsoft.OpenApi.Models;

var builder = WebApplication.CreateBuilder(args);

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
    p.AllowAnyOrigin().AllowAnyHeader().AllowAnyMethod()));

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
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}
app.UseCors("all");
app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();

// ----- تهيئة قاعدة البيانات + Seed -----
await DbSeeder.MigrateAndSeedAsync(app.Services, app.Configuration,
    app.Services.GetRequiredService<ILogger<Program>>());

app.Run();

public partial class Program; // لإتاحة اختبارات التكامل لاحقاً
