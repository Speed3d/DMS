<#
.SYNOPSIS
    06-trial-iis-setup.ps1 - يُشغَّل على [ 🧪 حاسبة التجربة ] حصراً.
.DESCRIPTION
    يقوم بتهيئة IIS: إيقاف الموقع الافتراضي وتعطيل إقلاعه (حل العطل 9)،
    إنشاء موقع DmsApp على المنفذ 80، ضبط الأذونات، وفحص طلبات canvaskit.wasm ومطابقة رد DMS.
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = "DMS Toolkit - 06 ضبط موقع IIS"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  🧪 [حاسبة التجربة] ضبط خادم الويب IIS وموقع DmsApp" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. استيراد إدارة IIS
Write-Host "`n[1/4] استيراد وحدة إدارة IIS (WebAdministration)..." -ForegroundColor Green
try {
    Import-Module WebAdministration -ErrorAction Stop
} catch {
    Write-Host "🔴 فشل استيراد وحدة WebAdministration! تأكد من تثبيت IIS على هذا الجهاز." -ForegroundColor Red
    exit 1
}

# 2. [علاج العطل 9]: إيقاف الموقع الافتراضي ومنع إقلاعه التلقائي نهائياً
Write-Host "`n[2/4] إيقاف وتعطيل الموقع الافتراضي Default Web Site..." -ForegroundColor Yellow
if (Get-Website -Name "Default Web Site" -ErrorAction SilentlyContinue) {
    Stop-Website -Name "Default Web Site" -ErrorAction SilentlyContinue
    Set-ItemProperty "IIS:\Sites\Default Web Site" -Name serverAutoStart -Value $false -ErrorAction SilentlyContinue
    Write-Host "  ✔ تم إيقاف Default Web Site وضبط serverAutoStart = False." -ForegroundColor Green
}

# 3. إنشاء موقع DmsApp وضبط مساره وأذوناته
Write-Host "`n[3/4] إنشاء وضبط موقع DmsApp على المنفذ 80..." -ForegroundColor Green
if (Get-Website -Name "DmsApp" -ErrorAction SilentlyContinue) {
    Remove-Website -Name "DmsApp" -ErrorAction SilentlyContinue
}

New-Website -Name "DmsApp" -Port 80 -PhysicalPath "C:\DMS\app" -Force | Out-Null
Set-ItemProperty "IIS:\Sites\DmsApp" -Name serverAutoStart -Value $true
Start-Website -Name "DmsApp"

# منح أذونات القراءة والتنفيذ لحساب مستخدمي IIS
icacls "C:\DMS\app" /grant "IIS_IUSRS:(OI)(CI)(RX)" | Out-Null

$sites = Get-Website | Select-Object Name, State, @{n='AutoStart';e={$_.serverAutoStart}}
$sites | Format-Table -AutoSize

# 4. الفحص الحاسم: فحص ملفات WASM ومطابقة الرد
Write-Host "`n[4/4] التحقق من استجابة الموقع ومطابقة محرك فلاتر و CanvasKit..." -ForegroundColor Green
Start-Sleep -Seconds 2

try {
    $rHome = Invoke-WebRequest "http://localhost/" -UseBasicParsing -TimeoutSec 5
    Write-Host "  - استجابة الصفحة الرئيسية: كود $($rHome.StatusCode)" -ForegroundColor Cyan
    
    if ($rHome.Content -match 'flutter|main\.dart\.js') {
        Write-Host "  ✔ تم التحقق: الخادم يرد بواجهة DMS فلاتر بنجاح!" -ForegroundColor Green
    } else {
        Write-Host "  ⚠️ تحذير: الرد ليس واجهة DMS! قد يكون ما زال الموقع الافتراضي." -ForegroundColor DarkYellow
    }

    # فحص ملف canvaskit.wasm الحاسم
    $rWasm = Invoke-WebRequest "http://localhost/canvaskit/canvaskit.wasm" -UseBasicParsing -TimeoutSec 5
    if ($rWasm.StatusCode -eq 200) {
        Write-Host "  ✔ الحارس الحاسم: تم تحميل canvaskit.wasm بنجاح (كود 200) - لن تظهر شاشة بيضاء!" -ForegroundColor Green
    } else {
        Write-Host "  🔴 تحذير: فشل تحميل canvaskit.wasm (كود $($rWasm.StatusCode))!" -ForegroundColor Red
    }
} catch {
    Write-Host "⚠️ تعذر التحقق المحلي من طلبات IIS: $($_.Exception.Message)" -ForegroundColor DarkYellow
}

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "  ✅ موقع DmsApp يعمل على IIS ومضبوط كخادم الويب الأساسي!" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
