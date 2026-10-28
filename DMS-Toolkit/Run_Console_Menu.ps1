<#
.SYNOPSIS
    Run_Console_Menu.ps1 - القائمة التفاعلية السريعة لتشغيل أي مرحلة بنقرة واحدة.
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# التحقق من صلاحيات المسؤول والترقية التلقائية إن لزم
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "جاري إعادة فتح القائمة بصلاحيات المسؤول (Administrator)..." -ForegroundColor Yellow
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

$Host.UI.RawUI.WindowTitle = "DMS Deployment Toolkit - القائمة التفاعلية (Administrator)"

function Show-Menu {
    Clear-Host
    Write-Host "========================================================================" -ForegroundColor Cyan
    Write-Host "         🚀 القائمة التفاعلية السريعة — حزمة نشر نظام DMS             " -ForegroundColor White
    Write-Host "========================================================================" -ForegroundColor Cyan
    Write-Host "  [0] 🔄 تصفير الحاسبة التجريبية بالكامل (00-reset-trial.ps1)" -ForegroundColor Yellow
    Write-Host "------------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  [1] 💻 [جهاز التطوير] بناء وحزم النظام (01-dev-build-and-pack.ps1)" -ForegroundColor Blue
    Write-Host "------------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  [2] 🧪 [حاسبة التجربة] فك الحزم من الفلاشة (02-trial-unpack.ps1)" -ForegroundColor Cyan
    Write-Host "  [3] 🧪 [حاسبة التجربة] الفحص المسبق والمسبار (03-trial-preflight.ps1)" -ForegroundColor Cyan
    Write-Host "  [4] 🧪 [حاسبة التجربة] الأسرار وقاعدة البيانات (04-trial-secrets-and-db.ps1)" -ForegroundColor Cyan
    Write-Host "  [5] 🧪 [حاسبة التجربة] تثبيت خدمة DmsApi (05-trial-service-setup.ps1)" -ForegroundColor Cyan
    Write-Host "  [6] 🧪 [حاسبة التجربة] إعداد موقع IIS وفحص WASM (06-trial-iis-setup.ps1)" -ForegroundColor Cyan
    Write-Host "  [7] 🧪 [حاسبة التجربة] تثبيت نفق Cloudflare كخدمة (07-trial-tunnel-setup.ps1)" -ForegroundColor Cyan
    Write-Host "  [8] 🎯 [فحص شامل] الفحص الحاسم النهائي (08-trial-verify-final.ps1)" -ForegroundColor Green
    Write-Host "------------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  [9] 🚀 [تحديث إصدار] تحديث نسخة مرفوعة بأمان (09-trial-update-release.ps1)" -ForegroundColor Green
    Write-Host "  [10] 🔐 [تحديث النفق] تحديث cloudflared بأمان (10-trial-cloudflared-update.ps1)" -ForegroundColor Green
    Write-Host "------------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  [H] 🌐 فتح الكتالوج الرسومي في المتصفح (DMS_Deploy_Wizard.html)" -ForegroundColor Magenta
    Write-Host "  [Q] 🚪 خروج" -ForegroundColor Gray
    Write-Host "========================================================================" -ForegroundColor Cyan
}

do {
    Show-Menu
    $choice = Read-Host "اختر رقم المرحلة التي تريد تشغيلها"
    $scriptsDir = "$PSScriptRoot\scripts"
    
    switch ($choice.ToUpper()) {
        "0" { powershell -ExecutionPolicy Bypass -File "$scriptsDir\00-reset-trial.ps1" }
        "1" { powershell -ExecutionPolicy Bypass -File "$scriptsDir\01-dev-build-and-pack.ps1" }
        "2" { powershell -ExecutionPolicy Bypass -File "$scriptsDir\02-trial-unpack.ps1" }
        "3" { powershell -ExecutionPolicy Bypass -File "$scriptsDir\03-trial-preflight.ps1" }
        "4" { powershell -ExecutionPolicy Bypass -File "$scriptsDir\04-trial-secrets-and-db.ps1" }
        "5" { powershell -ExecutionPolicy Bypass -File "$scriptsDir\05-trial-service-setup.ps1" }
        "6" { powershell -ExecutionPolicy Bypass -File "$scriptsDir\06-trial-iis-setup.ps1" }
        "7" { powershell -ExecutionPolicy Bypass -File "$scriptsDir\07-trial-tunnel-setup.ps1" }
        "8" { powershell -ExecutionPolicy Bypass -File "$scriptsDir\08-trial-verify-final.ps1" }
        "9" { powershell -ExecutionPolicy Bypass -File "$scriptsDir\09-trial-update-release.ps1" }
        "10" { powershell -ExecutionPolicy Bypass -File "$scriptsDir\10-trial-cloudflared-update.ps1" }
        "H" { Start-Process "$PSScriptRoot\DMS_Deploy_Wizard.html" }
        "Q" { break }
        default { Write-Host "خيار غير صالح! اضغط Enter..." -ForegroundColor Red }
    }
    
    if ($choice.ToUpper() -ne "Q") {
        Write-Host "`nاضغط Enter للعودة إلى القائمة الرئيسية..." -ForegroundColor DarkGray
        $null = Read-Host
    }
} while ($choice.ToUpper() -ne "Q")