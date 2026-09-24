<#
.SYNOPSIS
    02-trial-unpack.ps1 - يُشغَّل على [ 🧪 حاسبة التجربة ] حصراً.
.DESCRIPTION
    يقوم بفك ضغط الحزم dms-api.zip و dms-app.zip من الفلاشة إلى C:\DMS\api و C:\DMS\app
    مع مراعاة تفريغ مجلد الواجهة وتجنب مسح أي أسرار موجودة.
#>

param(
    [string]$SourceDrive = "E:\"
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = "DMS Toolkit - 02 فك الحزم على حاسبة التجربة"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  🧪 [حاسبة التجربة] بدء فك حزم نظام DMS" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# البحث التلقائي عن الفلاشة إن لم يكن المسار E:\ موجوداً
$apiZip = Join-Path $SourceDrive "dms-api.zip"
$appZip = Join-Path $SourceDrive "dms-app.zip"

if (-not (Test-Path $apiZip) -or -not (Test-Path $appZip)) {
    Write-Host "لم يتم العثور على الحزم في $SourceDrive، جاري البحث في المحركات المتصلة..." -ForegroundColor Yellow
    $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -ne 'C:\' -and $_.Root -ne 'D:\' }
    foreach ($d in $drives) {
        $candidateApi = Join-Path $d.Root "dms-api.zip"
        $candidateApp = Join-Path $d.Root "dms-app.zip"
        if ((Test-Path $candidateApi) -and (Test-Path $candidateApp)) {
            $SourceDrive = $d.Root
            $apiZip = $candidateApi
            $appZip = $candidateApp
            Write-Host "✔ تم العثور على الحزم في المحرك: $SourceDrive" -ForegroundColor Green
            break
        }
    }
}

if (-not (Test-Path $apiZip) -or -not (Test-Path $appZip)) {
    Write-Host "🔴 خطأ: تعذر العثور على dms-api.zip أو dms-app.zip!" -ForegroundColor Red
    Write-Host "تأكد من إدخال الفلاشة أو حدد المسار عبر: .\02-trial-unpack.ps1 -SourceDrive F:\" -ForegroundColor Red
    exit 1
}

# 1. إنشاء المجلدات
Write-Host "`n[1/3] تجهيز مجلدات C:\DMS\api و C:\DMS\app..." -ForegroundColor Green
New-Item -ItemType Directory -Force -Path "C:\DMS\api", "C:\DMS\app" | Out-Null

# 2. تفريغ مجلد الواجهة قبل فك الضغط (لتجنب تراكم الملفات القديمة)
Write-Host "`n[2/3] فك ضغط واجهة الويب إلى C:\DMS\app..." -ForegroundColor Green
if (Test-Path "C:\DMS\app\*") {
    Write-Host "  - تفريغ ملفات الواجهة القديمة..." -ForegroundColor Gray
    Get-ChildItem -Path "C:\DMS\app" -Recurse | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
}
Expand-Archive -Path $appZip -DestinationPath "C:\DMS\app" -Force
Write-Host "✔ تم فك ضغط واجهة الويب بنجاح." -ForegroundColor Green

# 3. فك ضغط الباك إند
Write-Host "`n[3/3] فك ضغط الباك-إند إلى C:\DMS\api..." -ForegroundColor Green
Expand-Archive -Path $apiZip -DestinationPath "C:\DMS\api" -Force
Write-Host "✔ تم فك ضغط الباك-إند بنجاح." -ForegroundColor Green

# التحقق النهائي
$exeExists = Test-Path "C:\DMS\api\Dms.Api.exe"
$configExists = Test-Path "C:\DMS\app\web.config"

if ($exeExists -and $configExists) {
    Write-Host "`n==========================================================" -ForegroundColor Green
    Write-Host "  ✅ وصلت ملفات Dms.Api.exe و web.config بنجاح وجاهزة للمرحلة التالية!" -ForegroundColor Green
    Write-Host "==========================================================" -ForegroundColor Green
} else {
    Write-Host "🔴 تحذير: Dms.Api.exe أو web.config غير موجود بعد فك الضغط!" -ForegroundColor Red
    exit 1
}
