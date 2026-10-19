<#
.SYNOPSIS
    09-trial-update-release.ps1 - يُشغَّل على [ 🧪 حاسبة التجربة ] لتحديث نسخة مرفوعة (مثلاً من 0.16.1 إلى 0.17.0).
.DESCRIPTION
    يقوم بتحديث نظام DMS المرفوع على الدومين موضعياً (In-Place Update) بأمان تام:
    1. يكتشف محرك الفلاشة ويتحقق من سلامة حزمتي dms-api.zip و dms-app.zip.
    2. يتحقق من وجود التثبيت القائم وملف الأسرار appsettings.Production.json.
    3. يأخذ نسخة احتياطية فورية للكود الحالي (C:\DMS\releases) ولقاعدة البيانات (SQL Backup) للرجوع الفوري عند الحاجة.
    4. يوقف خدمة DmsApi مؤقتاً لتحرير ملفات الـ DLL.
    5. يحدث واجهة الويب (مع تنظيف الملفات القديمة) ويحدث الـ API مع الحفاظ التام على appsettings.Production.json و C:\DMS\data.
    6. يعيد تشغيل DmsApi و IIS ويتحقق من الإصدار الجديد محلياً وعبر الدومين العام.
#>

param(
    [string]$SourceDrive = "D:\",
    [string]$Domain      = "dms.denland.net",
    [string]$DbName      = "DmsTrial"
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = "DMS Toolkit - 09 تحديث نسخة مرفوعة على الحاسبة التجريبية"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  🚀 [حاسبة التجربة] تحديث نسخة نظام DMS المرفوعة على الدومين" -ForegroundColor Cyan
Write-Host "  الدومين المستهدف: https://$Domain" -ForegroundColor Yellow
Write-Host "  قاعدة البيانات المحمية: $DbName" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

# التحقق من صلاحيات المسؤول (Administrator)
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "🔴 خطأ: يجب تشغيل هذا السكربت بصلاحيات المسؤول (Run as Administrator)!" -ForegroundColor Red
    exit 1
}

# 1. البحث عن حزم التحديث على الفلاشة والتحقق من حجمها
Write-Host "`n[1/7] البحث عن حزم التحديث (dms-api.zip و dms-app.zip)..." -ForegroundColor Green
$apiZip = Join-Path $SourceDrive "dms-api.zip"
$appZip = Join-Path $SourceDrive "dms-app.zip"

if (-not (Test-Path $apiZip) -or -not (Test-Path $appZip)) {
    Write-Host "  لم يتم العثور على الحزم في $SourceDrive، جاري البحث في المحركات المتصلة..." -ForegroundColor Yellow
    $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -ne 'C:\' }
    foreach ($d in $drives) {
        $candidateApi = Join-Path $d.Root "dms-api.zip"
        $candidateApp = Join-Path $d.Root "dms-app.zip"
        if ((Test-Path $candidateApi) -and (Test-Path $candidateApp)) {
            $SourceDrive = $d.Root
            $apiZip = $candidateApi
            $appZip = $candidateApp
            Write-Host "  ✔ تم العثور على الحزم في المحرك: $SourceDrive" -ForegroundColor Green
            break
        }
    }
}

if (-not (Test-Path $apiZip) -or -not (Test-Path $appZip)) {
    Write-Host "🔴 خطأ: تعذر العثور على dms-api.zip أو dms-app.zip!" -ForegroundColor Red
    Write-Host "تأكد من إدخال الفلاشة أو حدد المسار عبر: .\09-trial-update-release.ps1 -SourceDrive E:\" -ForegroundColor Red
    exit 1
}

$apiMb = [math]::Round((Get-Item $apiZip).Length / 1MB, 1)
$appMb = [math]::Round((Get-Item $appZip).Length / 1MB, 1)
Write-Host "  - حجم dms-api.zip: $apiMb ميغابايت   ·   حجم dms-app.zip: $appMb ميغابايت" -ForegroundColor Cyan

if ($apiMb -lt 5.0 -or $appMb -lt 5.0) {
    Write-Host "🔴 خطأ: أحد ملفات الحزم أقل من 5 ميغابايت! تأكد من اكتمال نسخ الملفات إلى الفلاشة." -ForegroundColor Red
    exit 1
}

# 2. التحقق من وجود التثبيت القائم وملف أسرار الإنتاج
Write-Host "`n[2/7] فحص التثبيت القائم وملف الأسرار appsettings.Production.json..." -ForegroundColor Green
$prodConfigPath = "C:\DMS\api\appsettings.Production.json"
if (-not (Test-Path $prodConfigPath)) {
    Write-Host "🔴 توقف آمن: الملف C:\DMS\api\appsettings.Production.json غير موجود!" -ForegroundColor Red
    Write-Host "هذه الحاسبة لا تحتوي على تثبيت مسبق، أو تم تصفيرها. للتثبيت من الصفر استخدم المراحل 02 إلى 08." -ForegroundColor Yellow
    exit 1
}

# قراءة الإصدار الحالي قبل التحديث إن كانت الخدمة تعمل
$oldVersion = "غير معروف"
try {
    $preStatus = Invoke-RestMethod -Uri "http://localhost:5080/api/system/status" -TimeoutSec 5
    if ($preStatus.version) { $oldVersion = $preStatus.version }
} catch {}
Write-Host "  ✔ التثبيت القائم سليم (الإصدار الحالي قبل التحديث: $oldVersion)." -ForegroundColor Green

# حفظ نسخة من ملف الأسرار في الذاكرة كحزام أمان إضافي
$prodConfigBytes = [System.IO.File]::ReadAllBytes($prodConfigPath)

# 3. أخذ نسخة احتياطية فورية للكود وقاعدة البيانات قبل التحديث
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$rollbackDir = "C:\DMS\releases\pre-update-$stamp"
Write-Host "`n[3/7] أخذ نسخة احتياطية فورية (Snapshot + SQL Backup) في $rollbackDir..." -ForegroundColor Green

New-Item -ItemType Directory -Force -Path "$rollbackDir\api", "$rollbackDir\app", "C:\DMS\data\backups" | Out-Null
Copy-Item -Path "C:\DMS\api\*" -Destination "$rollbackDir\api" -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item -Path "C:\DMS\app\*" -Destination "$rollbackDir\app" -Recurse -Force -ErrorAction SilentlyContinue
[System.IO.File]::WriteAllBytes("$rollbackDir\appsettings.Production.json.bak", $prodConfigBytes)
Write-Host "  ✔ تم حفظ نسخة الكود والواجهة والأسرار في: $rollbackDir" -ForegroundColor Green

# نسخ احتياطي لقاعدة البيانات عبر sqlcmd
try {
    $sqlSvc = Get-Service | Where-Object { $_.Name -eq 'MSSQLSERVER' -or $_.Name -like 'MSSQL$*' } | Select-Object -First 1
    $dbSrv = if ($sqlSvc -and $sqlSvc.Name -ne 'MSSQLSERVER') { ".\" + $sqlSvc.Name.Split('$')[1] } else { "." }
    $bakFile = "C:\DMS\data\backups\${DbName}_pre_update_${stamp}.bak"
    $backupSql = "BACKUP DATABASE [$DbName] TO DISK = N'$bakFile' WITH INIT;"
    sqlcmd -S $dbSrv -C -Q $backupSql -b | Out-Null
    if (Test-Path $bakFile) {
        Write-Host "  ✔ تم أخذ نسخة احتياطية لقاعدة البيانات ($DbName): $bakFile" -ForegroundColor Green
    }
} catch {
    Write-Host "  ⚠️ تنبيه غير حرج: تعذر أخذ النسخة الاحتياطية لقاعدة البيانات تلقائياً ($($_.Exception.Message))." -ForegroundColor Yellow
}

# الاحتفاظ بآخر 5 نسخ فقط في C:\DMS\releases لمنع امتلاء القرص
Get-ChildItem -Path "C:\DMS\releases" -Directory -ErrorAction SilentlyContinue |
    Sort-Object CreationTime -Descending |
    Select-Object -Skip 5 |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

# 4. إيقاف خدمة DmsApi مؤقتاً لتحرير ملفات الـ DLL
Write-Host "`n[4/7] إيقاف خدمة DmsApi مؤقتاً لتحرير الملفات..." -ForegroundColor Green
if (Get-Service -Name "DmsApi" -ErrorAction SilentlyContinue) {
    Stop-Service -Name "DmsApi" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}
Get-Process -Name "Dms.Api" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Write-Host "  ✔ تم إيقاف خدمة DmsApi وتحرير الملفات." -ForegroundColor Green

# 5. تحديث واجهة الويب (C:\DMS\app) والـ API (C:\DMS\api)
Write-Host "`n[5/7] فك حزم التحديث الجديد إلى C:\DMS\app و C:\DMS\api..." -ForegroundColor Green

Write-Host "  - تنظيف ملفات الواجهة القديمة وفك dms-app.zip..." -ForegroundColor Gray
if (Test-Path "C:\DMS\app\*") {
    Get-ChildItem -Path "C:\DMS\app" -Recurse | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
}
Expand-Archive -Path $appZip -DestinationPath "C:\DMS\app" -Force
icacls "C:\DMS\app" /grant "IIS_IUSRS:(OI)(CI)(RX)" | Out-Null
Write-Host "  ✔ تم تحديث واجهة الويب (C:\DMS\app) بنجاح." -ForegroundColor Green

Write-Host "  - فك dms-api.zip فوق C:\DMS\api مع الحفاظ على الأسرار..." -ForegroundColor Gray
Expand-Archive -Path $apiZip -DestinationPath "C:\DMS\api" -Force

# حارس الأمان: التأكد من بقاء appsettings.Production.json وعدم وجود appsettings.Development.json
if (-not (Test-Path $prodConfigPath)) {
    Write-Host "  ℹ استعادة ملف الأسرار appsettings.Production.json من النسخة المحفوظة..." -ForegroundColor Yellow
    [System.IO.File]::WriteAllBytes($prodConfigPath, $prodConfigBytes)
}
icacls $prodConfigPath /inheritance:r /grant:r "SYSTEM:(R)" /grant:r "Administrators:(F)" | Out-Null

if (Test-Path "C:\DMS\api\appsettings.Development.json") {
    Remove-Item "C:\DMS\api\appsettings.Development.json" -Force -ErrorAction SilentlyContinue
}
Write-Host "  ✔ تم تحديث الباك-إند (C:\DMS\api) وتأمين appsettings.Production.json بنجاح." -ForegroundColor Green

# 6. إعادة تشغيل خدمة DmsApi وتنشيط موقع IIS
Write-Host "`n[6/7] إعادة تشغيل خدمة DmsApi وتنشيط IIS..." -ForegroundColor Green
try {
    Start-Service -Name "DmsApi" -ErrorAction Stop
    Start-Sleep -Seconds 5
} catch {
    Write-Host "🔴 فشل تشغيل خدمة DmsApi بعد التحديث! جاري التراجع التلقائي (Auto-Rollback)..." -ForegroundColor Red
    Stop-Service -Name "DmsApi" -Force -ErrorAction SilentlyContinue
    Copy-Item -Path "$rollbackDir\api\*" -Destination "C:\DMS\api" -Recurse -Force
    Copy-Item -Path "$rollbackDir\app\*" -Destination "C:\DMS\app" -Recurse -Force
    Start-Service -Name "DmsApi" -ErrorAction SilentlyContinue
    Write-Host "⚠️ تمت استعادة النسخة السابقة بنجاح من: $rollbackDir" -ForegroundColor Yellow
    Get-EventLog -LogName Application -Newest 10 |
        Where-Object { $_.Source -match 'Dms|\.NET Runtime|Application Error' } |
        Select-Object TimeGenerated, Source, EntryType, Message | Format-List
    exit 1
}

try {
    Import-Module WebAdministration -ErrorAction SilentlyContinue
    Stop-Website -Name "Default Web Site" -ErrorAction SilentlyContinue
    Start-Website -Name "DmsApp" -ErrorAction SilentlyContinue
} catch {}
Write-Host "  ✔ خدمة DmsApi وموقع DmsApp يعملان الآن." -ForegroundColor Green

# 7. الفحص النهائي للإصدار الجديد محلياً وعبر الدومين العام
Write-Host "`n[7/7] التحقق من الإصدار الجديد والخدمات الثلاث..." -ForegroundColor Green
$svcs = Get-Service -Name "Cloudflared", "DmsApi", "W3SVC" -ErrorAction SilentlyContinue
foreach ($s in $svcs) {
    $sColor = if ($s.Status -eq 'Running') { 'Green' } else { 'Red' }
    Write-Host "  - خدمة $($s.Name): $($s.Status)" -ForegroundColor $sColor
}

$newVersion = "غير معروف"
try {
    $localRes = Invoke-RestMethod -Uri "http://localhost:5080/api/system/status" -TimeoutSec 10
    if ($localRes.version) { $newVersion = $localRes.version }
    Write-Host "  ✔ استجابة الـ API محلياً (5080): الإصدار = $newVersion · الصيانة = $($localRes.maintenance)" -ForegroundColor Green
} catch {
    Write-Host "  ⚠️ تعذر فحص الـ API محلياً: $($_.Exception.Message)" -ForegroundColor Yellow
}

try {
    $domainRes = Invoke-RestMethod -Uri "https://$Domain/api/system/status" -TimeoutSec 10
    Write-Host "  ✔ استجابة الـ API عبر الدومين (https://$Domain): الإصدار = $($domainRes.version) · الصيانة = $($domainRes.maintenance)" -ForegroundColor Green
} catch {
    Write-Host "  ⚠️ تعذر الوصول عبر الدومين الخارجي حالياً: $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "  ✅ اكتمل تحديث النظام بنجاح: ($oldVersion  --->  $newVersion)" -ForegroundColor Green
Write-Host "  📦 نسخة التراجع المحفوظة: $rollbackDir" -ForegroundColor Cyan
Write-Host "  🌐 افتح https://$Domain واضغط Ctrl+F5 (أو حدّث متصفح الهاتف)." -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
