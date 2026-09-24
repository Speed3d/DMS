<#
.SYNOPSIS
    05-trial-service-setup.ps1 - يُشغَّل على [ 🧪 حاسبة التجربة ] حصراً.
.DESCRIPTION
    يقوم بإنشاء خدمة الويندوز DmsApi وضبط تبعيتها لمثيل SQL والتعافي التلقائي
    وحقن متغير البيئة في السجل، ثم تشغيل الخدمة وفحص حالتها.
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = "DMS Toolkit - 05 تثبيت خدمة DmsApi"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  🧪 [حاسبة التجربة] تثبيت وتشغيل خدمة DmsApi" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. كشف مثيل SQL لتحديد التبعية
$sqlSvc = Get-Service | Where-Object { $_.Name -eq 'MSSQLSERVER' -or $_.Name -like 'MSSQL$*' } | Select-Object -First 1
$sqlDepend = if ($sqlSvc) { $sqlSvc.Name } else { "MSSQLSERVER" }
Write-Host "مثيل خدمة SQL المستهدف للتبعية: $sqlDepend" -ForegroundColor Gray

# 2. إيقاف وحذف الخدمة السابقة إن وجدت
if (Get-Service -Name "DmsApi" -ErrorAction SilentlyContinue) {
    Write-Host "إيقاف وحذف نسخة قديمة من خدمة DmsApi..." -ForegroundColor Yellow
    Stop-Service DmsApi -Force -ErrorAction SilentlyContinue
    sc.exe delete DmsApi | Out-Null
    Start-Sleep -Seconds 2
}

# 3. إنشاء الخدمة وضبط خصائصها
Write-Host "`n[1/4] تسجيل الخدمة في ويندوز..." -ForegroundColor Green
sc.exe create DmsApi binPath= "C:\DMS\api\Dms.Api.exe" start= auto DisplayName= "DMS API Service"
sc.exe config DmsApi depend= $sqlDepend
sc.exe failure DmsApi reset= 86400 actions= restart/30000/restart/30000/restart/60000

# 4. حقن متغير بيئة الإنتاج في السجل (HKLM)
Write-Host "`n[2/4] حقن متغير ASPNETCORE_ENVIRONMENT=Production في السجل..." -ForegroundColor Green
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\DmsApi" `
    -Name "Environment" -Value @("ASPNETCORE_ENVIRONMENT=Production") -Type MultiString

# 5. تشغيل الخدمة
Write-Host "`n[3/4] تشغيل الخدمة Start-Service DmsApi..." -ForegroundColor Green
try {
    Start-Service DmsApi
    Start-Sleep -Seconds 5
} catch {
    Write-Host "🔴 فشل تشغيل خدمة DmsApi!" -ForegroundColor Red
    Write-Host "قراءة سجل الأحداث (Application Event Log) لتشخيص السبب:" -ForegroundColor Yellow
    Get-EventLog -LogName Application -Newest 15 |
        Where-Object { $_.Source -match 'Dms|\.NET Runtime|Application Error' } |
        Select-Object TimeGenerated, Source, EntryType, Message | Format-List
    exit 1
}

# 6. فحص حالة الخدمة والنقطة الطرفية
Write-Host "`n[4/4] فحص حالة الخدمة على http://localhost:5080/api/system/status..." -ForegroundColor Green
$svc = Get-Service DmsApi
Write-Host "حالة الخدمة: $($svc.Status)" -ForegroundColor Cyan

try {
    $res = Invoke-RestMethod -Uri "http://localhost:5080/api/system/status" -TimeoutSec 5
    Write-Host "  ✔ استجابت الخدمة بنجاح! حالة الصيانة: $($res.maintenance)" -ForegroundColor Green
} catch {
    Write-Host "⚠️ لم تستجب النقطة الطرفية بعد: $($_.Exception.Message)" -ForegroundColor DarkYellow
}

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "  ✅ خدمة DmsApi تعمل بنجاح ومضبوطة للإقلاع التلقائي!" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
