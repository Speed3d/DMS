<#
.SYNOPSIS
    01-dev-build-and-pack.ps1 - يُشغَّل على [ 💻 جهاز التطوير ] حصراً.
.DESCRIPTION
    يقوم ببناء الباك-إند (Dms.Api) والواجهة (Flutter Web) مع ربط الدومين المخبوز داخل JS،
    والتحقق الصارم من الحراس الثلاثة، ثم ضغط الحزمتين والتحقق من حجمهما.
#>

param(
    [string]$Domain = "dms.nociraq.com",
    [string]$OutputDir = "D:\DMS-نشر",
    [string]$TempPublish = "C:\temp\dms-publish"
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = "DMS Toolkit - 01 بناء وحزم جهاز التطوير"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  💻 [جهاز التطوير] بدء بناء وحزم نظام DMS" -ForegroundColor Cyan
Write-Host "  الدومين المخبوز: https://$Domain" -ForegroundColor Yellow
Write-Host "  مجلد الإخراج: $OutputDir" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

# التحقق من أننا في جهاز التطوير
if (-not (Test-Path "D:\DMS\backend") -or -not (Test-Path "D:\DMS\app")) {
    Write-Host "🔴 خطأ فادح: مسارات كود المصدر D:\DMS\backend أو D:\DMS\app غير موجودة!" -ForegroundColor Red
    Write-Host "تأكد من تشغيل هذا السكربت على جهاز التطوير وليس حاسبة التجربة." -ForegroundColor Red
    exit 1
}

# 1. بناء الباك-إند
Write-Host "`n[1/5] بناء الباك-إند (.NET Core API)..." -ForegroundColor Green
Set-Location "D:\DMS\backend"
dotnet publish Dms.Api -c Release -r win-x64 --self-contained false -o "$TempPublish"
if ($LASTEXITCODE -ne 0) {
    Write-Host "🔴 فشل بناء الباك-إند! توقف العمل." -ForegroundColor Red
    exit 1
}
Write-Host "✔ تم بناء الباك-إند بنجاح إلى: $TempPublish" -ForegroundColor Green

# 2. بناء الواجهة مع الدومين المخبوز
Write-Host "`n[2/5] بناء واجهة الويب (Flutter Web) مع الدومين المخبوز..." -ForegroundColor Green
Set-Location "D:\DMS\app"
$apiBase = "https://$Domain/api"
flutter build web --release "--dart-define=API_BASE_URL=$apiBase"
if ($LASTEXITCODE -ne 0) {
    Write-Host "🔴 فشل بناء واجهة فلاتر! توقف العمل." -ForegroundColor Red
    exit 1
}
Write-Host "✔ تم بناء الواجهة بنجاح." -ForegroundColor Green

# 3. فحص الحراس الصارمة
Write-Host "`n[3/5] فحص الحراس الصارمة لمنع التسريب والخلل المعماري..." -ForegroundColor Yellow

# حارس 1: التحقق من وجود الدومين داخل main.dart.js
$jsPath = "D:\DMS\app\build\web\main.dart.js"
$pattern = [regex]::Escape($Domain)
$hasDomain = Select-String -Path $jsPath -Pattern $pattern -Quiet
if (-not $hasDomain) {
    Write-Host "🔴 الحارس 1 فشل: الدومين ($Domain) غير مخبوز داخل main.dart.js!" -ForegroundColor Red
    Write-Host "لا تنشر هذه النسخة، لأن تصحيح العنوان على السيرفر لاحقاً لا يجدي نفعاً." -ForegroundColor Red
    exit 1
} else {
    Write-Host "  ✔ الحارس 1 سليم: الدومين مخبوز بنجاح داخل الكود المترجم." -ForegroundColor Green
}

# حارس 2: التحقق من وجود سكربت التحديث
$hasUpdateScript = Test-Path "$TempPublish\ops\update-dms.ps1"
if (-not $hasUpdateScript) {
    Write-Host "🔴 الحارس 2 فشل: سكربت التحديث update-dms.ps1 مفقود من الحزمة!" -ForegroundColor Red
    exit 1
} else {
    Write-Host "  ✔ الحارس 2 سليم: سكربت التحديث موجود داخل الحزمة." -ForegroundColor Green
}

# حارس 3: التحقق من عدم تسريب إعدادات التطوير
$hasDevSettings = Test-Path "$TempPublish\appsettings.Development.json"
if ($hasDevSettings) {
    Write-Host "🔴 الحارس 3 فشل خطير: ملف appsettings.Development.json تسرب إلى حزمة النشر!" -ForegroundColor Red
    Write-Host "وجود هذا الملف يسرّب مفاتيح JWT ويفتح الـ Swagger ونقطة تصفير القاعدة في الإنتاج!" -ForegroundColor Red
    exit 1
} else {
    Write-Host "  ✔ الحارس 3 سليم (False): لم يتسرب ملف التطوير." -ForegroundColor Green
}

# 4. ضغط الحزم
Write-Host "`n[4/5] ضغط الحزم إلى مجلد النشر..." -ForegroundColor Green
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$apiZip = "$OutputDir\dms-api.zip"
$appZip = "$OutputDir\dms-app.zip"

Write-Host "  - ضغط الباك إند إلى $apiZip..."
Compress-Archive -Path "$TempPublish\*" -DestinationPath $apiZip -Force

Write-Host "  - ضغط الواجهة إلى $appZip..."
Compress-Archive -Path "D:\DMS\app\build\web\*" -DestinationPath $appZip -Force

# نسخ سكربتات التجربة المساعدة إلى مجلد النشر
if (Test-Path "D:\DMS\DMS-Toolkit\scripts\03-trial-preflight.ps1") {
    Copy-Item "D:\DMS\DMS-Toolkit\scripts\03-trial-preflight.ps1" "$OutputDir\" -Force
}

# 5. التحقق من أحجام الملفات
Write-Host "`n[5/5] فحص أحجام الحزم الناتجة..." -ForegroundColor Green
$apiItem = Get-Item $apiZip
$appItem = Get-Item $appZip

$apiMb = [math]::Round($apiItem.Length / 1MB, 1)
$appMb = [math]::Round($appItem.Length / 1MB, 1)

Write-Host "  - حجم dms-api.zip: $apiMb ميغابايت" -ForegroundColor Cyan
Write-Host "  - حجم dms-app.zip: $appMb ميغابايت" -ForegroundColor Cyan

if ($apiMb -lt 5.0 -or $appMb -lt 5.0) {
    Write-Host "🔴 خطأ في الحجم: أحد الملفات أقل من 5 ميغابايت! المجلد المصدر قد يكون فارغاً أو حدث انقطاع." -ForegroundColor Red
    exit 1
}

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "  ✅ تم البناء والحزم بنجاح تام!" -ForegroundColor Green
Write-Host "  انقل الآن محتويات $OutputDir (الملفين dms-api.zip و dms-app.zip) إلى الفلاشة." -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
