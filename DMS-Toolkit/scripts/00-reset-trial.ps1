<#
.SYNOPSIS
    00-reset-trial.ps1 - تصفير الحاسبة التجريبية بالكامل وإعادتها لحالتها النظيفة.
.DESCRIPTION
    يقوم بحذف خدمات DmsApi و Cloudflared، وإعادة ضبط IIS، وحذف قاعدة DmsTrial، وحذف C:\DMS،
    وإزالة شهادات النفق المحلية لتجهيز الجهاز لإعادة التجربة من الصفر 100%.
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = "DMS Toolkit - 00 تصفير الحاسبة التجريبية"

Write-Host "==========================================================" -ForegroundColor Yellow
Write-Host "  ⚠️  بدء تصفير الحاسبة التجريبية لنظام DMS وإعادتها للنظافة التامة" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Yellow

$confirm = Read-Host "هل أنت متأكد من رغبتك في حذف خدمات DMS وموقع IIS وقاعدة DmsTrial؟ (اكتب y للمتابعة)"
if ($confirm -ne 'y' -and $confirm -ne 'Y') {
    Write-Host "تم إلغاء عملية التصفير." -ForegroundColor Gray
    exit
}

# 1. إيقاف وحذف خدمة DmsApi
Write-Host "`n[1/5] إيقاف وحذف خدمة DmsApi..." -ForegroundColor Cyan
if (Get-Service -Name "DmsApi" -ErrorAction SilentlyContinue) {
    Stop-Service DmsApi -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    sc.exe delete DmsApi | Out-Null
    Write-Host "  ✔ تم حذف خدمة DmsApi بنجاح." -ForegroundColor Green
} else {
    Write-Host "  ℹ خدمة DmsApi غير موجودة بالفعل." -ForegroundColor Gray
}

# 2. إيقاف وحذف خدمة Cloudflared
Write-Host "`n[2/5] إيقاف وحذف خدمة Cloudflared..." -ForegroundColor Cyan
if (Get-Service -Name "Cloudflared" -ErrorAction SilentlyContinue) {
    Stop-Service Cloudflared -Force -ErrorAction SilentlyContinue
    Get-Process cloudflared -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2
    sc.exe delete Cloudflared | Out-Null
    Write-Host "  ✔ تم حذف خدمة Cloudflared بنجاح." -ForegroundColor Green
} else {
    Write-Host "  ℹ خدمة Cloudflared غير موجودة بالفعل." -ForegroundColor Gray
}

# 3. إعادة ضبط IIS
Write-Host "`n[3/5] إعادة ضبط مواقع IIS..." -ForegroundColor Cyan
try {
    Import-Module WebAdministration -ErrorAction Stop
    if (Get-Website -Name "DmsApp" -ErrorAction SilentlyContinue) {
        Stop-Website -Name "DmsApp" -ErrorAction SilentlyContinue
        Remove-Website -Name "DmsApp" -ErrorAction SilentlyContinue
        Write-Host "  ✔ تم حذف موقع DmsApp من IIS." -ForegroundColor Green
    }
    
    if (Get-Website -Name "Default Web Site" -ErrorAction SilentlyContinue) {
        Set-ItemProperty "IIS:\Sites\Default Web Site" -Name serverAutoStart -Value $true -ErrorAction SilentlyContinue
        Start-Website -Name "Default Web Site" -ErrorAction SilentlyContinue
        Write-Host "  ✔ تم استعادة وتشغيل Default Web Site وضبط الإقلاع التلقائي." -ForegroundColor Green
    }
} catch {
    Write-Host "  ⚠️ تعذر استيراد وحدة WebAdministration أو فحص IIS: $($_.Exception.Message)" -ForegroundColor DarkYellow
}

# 4. حذف قاعدة البيانات التجريبية DmsTrial
Write-Host "`n[4/5] حذف قاعدة البيانات DmsTrial في SQL Server..." -ForegroundColor Cyan
try {
    $dropSql = "IF EXISTS (SELECT name FROM sys.databases WHERE name = 'DmsTrial') BEGIN ALTER DATABASE DmsTrial SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE DmsTrial; END"
    sqlcmd -S . -Q $dropSql -b
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✔ تم حذف قاعدة البيانات DmsTrial إن وجدت بنجاح." -ForegroundColor Green
    } else {
        Write-Host "  ⚠️ فشل أمر sqlcmd، تحقق من تشغيل خدمة SQL Server." -ForegroundColor DarkYellow
    }
} catch {
    Write-Host "  ⚠️ حدث خطأ أثناء تشغيل sqlcmd: $($_.Exception.Message)" -ForegroundColor Red
}

# 5. حذف مجلد النظام C:\DMS وتنظيف النفق المحلي
Write-Host "`n[5/5] حذف مجلد C:\DMS وتنظيف إعدادات النفق..." -ForegroundColor Cyan
if (Test-Path "C:\DMS") {
    Remove-Item -Path "C:\DMS" -Recurse -Force -ErrorAction SilentlyContinue
    if (-not (Test-Path "C:\DMS")) {
        Write-Host "  ✔ تم حذف المجلد C:\DMS بالكامل." -ForegroundColor Green
    } else {
        Write-Host "  ⚠️ بعض الملفات في C:\DMS قيد الاستخدام، أغلق البرامج وأعد تشغيل السكربت." -ForegroundColor DarkYellow
    }
} else {
    Write-Host "  ℹ المجلد C:\DMS غير موجود." -ForegroundColor Gray
}

# تنظيف إعدادات النفق لـ SYSTEM
$sysCf = "C:\Windows\System32\config\systemprofile\.cloudflared"
if (Test-Path $sysCf) {
    Remove-Item -Path $sysCf -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  ✔ تم تنظيف مجلد نفق SYSTEM." -ForegroundColor Green
}

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "  ✅ اكتملت عملية التصفير بنجاح! الحاسبة نظيفة وجاهزة تماماً." -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
