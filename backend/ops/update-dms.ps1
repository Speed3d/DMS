# ─────────────────────────────────────────────────────────────────────────────
# تحديث نظام DMS على السيرفر الداخلي — إجراء آمن بخطوات مرتّبة.
#
# التشغيل (كمسؤول على السيرفر):
#   powershell -File backend\ops\update-dms.ps1 -SourceDir <مجلد النشر الجديد>
#
# ما يفعله بالترتيب:
#   1) يتحقق من المتطلبات   2) نسخة احتياطية قبل أي لمس   3) إيقاف الخدمة
#   4) أرشفة النسخة الحالية 5) نسخ الملفات الجديدة        6) تطبيق migrations
#   7) تشغيل الخدمة         8) فحص صحّة
#
# Hint: أي فشل قبل الخطوة 5 يترك النظام كما هو. بعدها يمكن الرجوع بأرشيف الخطوة 4.
#       الملف بترميز UTF-8 with BOM ليقرأ PowerShell 5.1 العربية بشكل صحيح.
# ─────────────────────────────────────────────────────────────────────────────
param(
    [Parameter(Mandatory=$true)][string]$SourceDir,                       # مجلد الإصدار الجديد (ناتج dotnet publish)
    [string]$AppDir      = "C:\DMS\api",                                  # مجلد التشغيل على السيرفر
    [string]$ServiceName = "DmsApi",                                      # اسم خدمة ويندوز
    [string]$HealthUrl   = "http://localhost:5080/api/system/status",      # نقطة فحص الصحّة
    [switch]$SkipBackup                                                    # تخطّي النسخة (غير مستحسن)
)

$ErrorActionPreference = "Stop"
function Step($n, $m) { Write-Host "`n[$n] $m" -ForegroundColor Cyan }
function Ok($m)       { Write-Host "    ✔ $m" -ForegroundColor Green }
function Warn($m)     { Write-Host "    ! $m" -ForegroundColor Yellow }
function Die($m)      { Write-Host "`n✖ توقّف: $m" -ForegroundColor Red; exit 1 }

# ── 1) التحقق من المتطلبات ───────────────────────────────────────────────────
Step 1 "التحقق من المتطلبات"
if (-not (Test-Path $SourceDir)) { Die "مجلد المصدر غير موجود: $SourceDir" }
if (-not (Test-Path (Join-Path $SourceDir "Dms.Api.dll"))) { Die "مجلد المصدر لا يحوي Dms.Api.dll — هل نفّذت dotnet publish؟" }
if (-not (Test-Path $AppDir)) { Die "مجلد التطبيق غير موجود: $AppDir" }

$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if (-not $svc) { Die "الخدمة '$ServiceName' غير مسجّلة. راجع خطة النشر (المرحلة ب)." }
Ok "المصدر والوجهة والخدمة جاهزة"

# ⚠️ لا نستبدل ملف الأسرار إطلاقاً — يبقى ملف السيرفر كما هو.
$prodSettings = Join-Path $AppDir "appsettings.Production.json"
$hasProdSettings = Test-Path $prodSettings
if ($hasProdSettings) { Ok "ملف إعدادات الإنتاج موجود وسيُحافَظ عليه" } else { Warn "لا يوجد appsettings.Production.json في مجلد التطبيق" }

# ── 2) نسخة احتياطية قبل أي تغيير ────────────────────────────────────────────
Step 2 "نسخة احتياطية قبل التحديث"
if ($SkipBackup) {
    Warn "تم تخطّي النسخة الاحتياطية بناءً على طلبك (غير مستحسن)"
} else {
    try {
        # Hint: النسخة تُطلب من النظام نفسه وهو ما زال يعمل — أضمن من نسخ الملفات يدوياً.
        Write-Host "    (يتطلب أن يكون النظام يعمل — استخدم شاشة النسخ الاحتياطي إن فشل هذا)" -ForegroundColor DarkGray
        $probe = Invoke-RestMethod -Uri $HealthUrl -TimeoutSec 10
        Ok "النظام يستجيب — خذ نسخة يدوية من شاشة النسخ الاحتياطي الآن ثم تابع"
        Read-Host "    اضغط Enter بعد التأكد من وجود نسخة حديثة"
    } catch {
        Warn "النظام لا يستجيب — تابع فقط إن كنت متأكداً من وجود نسخة حديثة"
        Read-Host "    اضغط Enter للمتابعة أو Ctrl+C للإلغاء"
    }
}

# ── 3) إيقاف الخدمة ──────────────────────────────────────────────────────────
Step 3 "إيقاف الخدمة"
if ($svc.Status -eq "Running") {
    Stop-Service -Name $ServiceName -Force
    (Get-Service $ServiceName).WaitForStatus("Stopped", "00:01:00")
    Ok "توقّفت الخدمة"
} else { Ok "الخدمة متوقّفة أصلاً" }

# ── 4) أرشفة النسخة الحالية (نقطة رجوع) ──────────────────────────────────────
Step 4 "أرشفة الإصدار الحالي"
$archiveRoot = Join-Path (Split-Path $AppDir -Parent) "releases"
New-Item -ItemType Directory -Force -Path $archiveRoot | Out-Null
$archive = Join-Path $archiveRoot ("api-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
Copy-Item -Path $AppDir -Destination $archive -Recurse -Force
Ok "نسخة الرجوع: $archive"

# ── 5) نسخ الملفات الجديدة ───────────────────────────────────────────────────
Step 5 "نسخ ملفات الإصدار الجديد"
# Hint: /XF يستثني ملف الأسرار و /XD يستثني بيانات التشغيل (التخزين والنسخ) من الحذف.
$robo = robocopy $SourceDir $AppDir /MIR /NFL /NDL /NJH /NJS /NP `
        /XF "appsettings.Production.json" `
        /XD "App_Data" "logs"
if ($LASTEXITCODE -ge 8) { Die "فشل نسخ الملفات (robocopy=$LASTEXITCODE). ارجع من: $archive" }
Ok "نُسخت الملفات (الأسرار وبيانات التشغيل محفوظة)"

# ── 6) تطبيق تحديثات قاعدة البيانات ──────────────────────────────────────────
Step 6 "تطبيق migrations"
# Hint: التطبيق يطبّقها ذاتياً عند الإقلاع (DbSeeder.MigrateAndSeedAsync)،
#       فنكتفي بالتحقق بعد التشغيل بدل استدعاء dotnet ef (غير مثبّت على السيرفر غالباً).
Ok "ستُطبَّق تلقائياً عند إقلاع الخدمة"

# ── 7) تشغيل الخدمة ──────────────────────────────────────────────────────────
Step 7 "تشغيل الخدمة"
Start-Service -Name $ServiceName
(Get-Service $ServiceName).WaitForStatus("Running", "00:02:00")
Ok "الخدمة تعمل"

# ── 8) فحص الصحّة ────────────────────────────────────────────────────────────
Step 8 "فحص الصحّة"
$healthy = $false
foreach ($attempt in 1..12) {   # حتى دقيقة: الإقلاع الأول قد يطبّق migrations
    Start-Sleep -Seconds 5
    try {
        $r = Invoke-RestMethod -Uri $HealthUrl -TimeoutSec 10
        if ($null -ne $r) { $healthy = $true; break }
    } catch { Write-Host "    ...محاولة $attempt" -ForegroundColor DarkGray }
}

if ($healthy) {
    Ok "النظام يستجيب — التحديث اكتمل بنجاح"
    Write-Host "`n✔ تم التحديث. نقطة الرجوع محفوظة في: $archive" -ForegroundColor Green
} else {
    Write-Host "`n✖ النظام لا يستجيب بعد التحديث." -ForegroundColor Red
    Write-Host "  للرجوع للإصدار السابق:" -ForegroundColor Yellow
    Write-Host "    Stop-Service $ServiceName" -ForegroundColor Yellow
    Write-Host "    robocopy `"$archive`" `"$AppDir`" /MIR" -ForegroundColor Yellow
    Write-Host "    Start-Service $ServiceName" -ForegroundColor Yellow
    Write-Host "  وافحص السجلّ: Get-EventLog -LogName Application -Source '$ServiceName' -Newest 20" -ForegroundColor Yellow
    exit 1
}
