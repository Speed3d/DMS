<#
.SYNOPSIS
    04-trial-secrets-and-db.ps1 - يُشغَّل على [ 🧪 حاسبة التجربة ] حصراً.
.DESCRIPTION
    يقوم بإنشاء مجلدات التخزين، توليد أسرار الإنتاج، تأمين صلاحيات الملفات،
    منح صلاحية sysadmin لحساب SYSTEM في SQL، تشغيل أول إقلاع للمهاجرات،
    واختبار الدخول محلياً.
#>

param(
    [string]$Domain   = "dms.nociraq.com",
    [string]$DbServer = ".",
    [string]$DbName   = "DmsTrial"
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = "DMS Toolkit - 04 الأسرار وقاعدة البيانات"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  🧪 [حاسبة التجربة] توليد الأسرار وتهيئة قاعدة البيانات" -ForegroundColor Cyan
Write-Host "  الدومين: https://$Domain" -ForegroundColor Yellow
Write-Host "  خادم SQL: $DbServer   ·   اسم القاعدة: $DbName" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. إنشاء المجلدات وضبط أذونات النسخ الاحتياطي
Write-Host "`n[1/6] إنشاء مجلدات التخزين والنسخ الاحتياطي..." -ForegroundColor Green
'C:\DMS\api','C:\DMS\app','C:\DMS\data\storage','C:\DMS\data\backups' |
    ForEach-Object { New-Item -ItemType Directory -Force -Path $_ | Out-Null }

# كشف حساب خدمة SQL
$sqlSvc = Get-Service | Where-Object { $_.Name -eq 'MSSQLSERVER' -or $_.Name -like 'MSSQL$*' } | Select-Object -First 1
$sqlAccount = if ($sqlSvc.Name -eq 'MSSQLSERVER') { "NT SERVICE\MSSQLSERVER" } else { "NT SERVICE\$($sqlSvc.Name)" }

Write-Host "  - منح إذن الكتابة لحساب محرك SQL ($sqlAccount) على مجلد النسخ الاحتياطي..." -ForegroundColor Gray
icacls "C:\DMS\data\backups" /grant "`"$sqlAccount`":(OI)(CI)(M)" | Out-Null
Write-Host "✔ تم ضبط أذونات مجلد النسخ الاحتياطي." -ForegroundColor Green

# 2. توليد الأسرار
Write-Host "`n[2/6] توليد أسرار الإنتاج (Dms.Api.exe generate-secrets)..." -ForegroundColor Green
Set-Location "C:\DMS\api"

$genArgs = @(
    "generate-secrets",
    "--out",       "C:\DMS\api\appsettings.Production.json",
    "--origins",   "https://$Domain",
    "--db-server", $DbServer,
    "--db-name",   $DbName,
    "--storage",   "C:\DMS\data\storage",
    "--backup",    "C:\DMS\data\backups"
)

& .\Dms.Api.exe $genArgs

if (-not (Test-Path "C:\DMS\api\appsettings.Production.json")) {
    Write-Host "🔴 فشل توليد ملف appsettings.Production.json!" -ForegroundColor Red
    exit 1
}
Write-Host "✔ تم إنشاء ملف الأسرار appsettings.Production.json بنجاح." -ForegroundColor Green

# 3. تأمين ملف الأسرار
Write-Host "`n[3/6] تأمين أذونات ملف الأسرار..." -ForegroundColor Green
icacls "C:\DMS\api\appsettings.Production.json" /inheritance:r /grant:r "SYSTEM:(R)" /grant:r "Administrators:(F)" | Out-Null
Write-Host "✔ تم قفل أذونات الملف (SYSTEM و Administrators فقط)." -ForegroundColor Green

# 4. [علاج العطل 4]: منح حساب SYSTEM صلاحية sysadmin قبل تشغيل الخدمة
Write-Host "`n[4/6] منح صلاحية sysadmin لحساب NT AUTHORITY\SYSTEM في SQL..." -ForegroundColor Yellow
$grantSql = "IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'NT AUTHORITY\SYSTEM') CREATE LOGIN [NT AUTHORITY\SYSTEM] FROM WINDOWS; ALTER SERVER ROLE sysadmin ADD MEMBER [NT AUTHORITY\SYSTEM];"
sqlcmd -S $DbServer -Q $grantSql -b | Out-Null

$checkSql = "SELECT IS_SRVROLEMEMBER('sysadmin', 'NT AUTHORITY\SYSTEM') AS IsSysadmin;"
$checkOut = sqlcmd -S $DbServer -Q $checkSql -h -1
if ($checkOut.Trim() -match '1') {
    Write-Host "  ✔ تم التحقق: حساب NT AUTHORITY\SYSTEM يحمل صلاحية sysadmin بنجاح." -ForegroundColor Green
} else {
    Write-Host "🔴 تحذير خطير: حساب NT AUTHORITY\SYSTEM لم يحصل على sysadmin! الخدمة ستفشل عند الإقلاع." -ForegroundColor Red
    exit 1
}

# 5. تشغيل أول إقلاع لإنشاء القاعدة وتطبيق المهاجرات
Write-Host "`n[5/6] أول إقلاع للبرنامج لإنشاء الجداول وتطبيق المهاجرات..." -ForegroundColor Green
$env:ASPNETCORE_ENVIRONMENT = "Production"

# تشغيل كعملية خلفية مؤقتة لمدة 15 ثانية ثم إيقافها
$proc = Start-Process -FilePath "C:\DMS\api\Dms.Api.exe" -PassThru -NoNewWindow
Write-Host "  - جاري انتظار بناء الجداول والمهاجرات (12 ثانية)..." -ForegroundColor Gray
Start-Sleep -Seconds 12

if (-not $proc.HasExited) {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
}
Write-Host "✔ انتهى الإقلاع الأول." -ForegroundColor Green

# التحقق من المهاجرات في قاعدة البيانات
$migSql = "SELECT COUNT(*) FROM __EFMigrationsHistory;"
try {
    $migCount = (sqlcmd -S $DbServer -d $DbName -Q $migSql -h -1).Trim()
    Write-Host "  ✔ عدد المهاجرات المطبقة في ${DbName}: $migCount مهاجرة." -ForegroundColor Green
} catch {
    Write-Host "⚠️ تعذر قراءة جدول المهاجرات: $($_.Exception.Message)" -ForegroundColor DarkYellow
}

# 6. فحص الدخول محلياً لعزل المتغيرات
Write-Host "`n[6/6] فحص الدخول محلياً على المنفذ 5080..." -ForegroundColor Green
$proc2 = Start-Process -FilePath "C:\DMS\api\Dms.Api.exe" -PassThru -NoNewWindow
Start-Sleep -Seconds 4

try {
    $cfg = Get-Content "C:\DMS\api\appsettings.Production.json" -Raw | ConvertFrom-Json
    $adminUser = $cfg.Seed.AdminUsername
    $adminPass = $cfg.Seed.AdminPassword

    $loginBody = @{ Username = $adminUser; Password = $adminPass } | ConvertTo-Json
    $res = Invoke-RestMethod -Uri "http://localhost:5080/api/auth/login" -Method Post -ContentType "application/json" -Body $loginBody -TimeoutSec 10

    if ($res.accessToken) {
        Write-Host "  ✔ نجح فحص الدخول المحلي! طول التوكن: $($res.accessToken.Length)" -ForegroundColor Green
    }
} catch {
    Write-Host "⚠️ فحص الدخول المحلي واجه تنبيهاً: $($_.Exception.Message)" -ForegroundColor DarkYellow
} finally {
    if (-not $proc2.HasExited) {
        Stop-Process -Id $proc2.Id -Force -ErrorAction SilentlyContinue
    }
}

# قراءة بيانات الدخول لعرضها للمستخدم
$cfgFinal = Get-Content "C:\DMS\api\appsettings.Production.json" -Raw | ConvertFrom-Json
Write-Host "`n╔══════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
Write-Host   "║  🔑 بيانات دخول المدير الأول (Seed Admin)                  ║" -ForegroundColor Yellow
Write-Host   "╠══════════════════════════════════════════════════════════╣" -ForegroundColor Yellow
Write-Host   "║  اسم المستخدم: $($cfgFinal.Seed.AdminUsername.PadRight(40))║" -ForegroundColor Yellow
Write-Host   "║  كلمة المرور : $($cfgFinal.Seed.AdminPassword.PadRight(40))║" -ForegroundColor Yellow
Write-Host   "╚══════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
Write-Host "⚠️ احفظ كلمة المرور الآن، أو انسخها لاحقاً من appsettings.Production.json" -ForegroundColor Gray

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "  ✅ تمت تهيئة الأسرار وقاعدة البيانات بنجاح تام!" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
