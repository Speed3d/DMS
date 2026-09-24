<#
.SYNOPSIS
    08-trial-verify-final.ps1 - يُشغَّل على [ 🧪 حاسبة التجربة ] أو أي جهاز.
.DESCRIPTION
    الفحص الحاسم الشامل: يفحص الخدمات الثلاث، مواقع IIS، صلاحيات SQL،
    والاتصال الخارجي عبر الإنترنت والدومين، ويعرض قائمة التحقق الكاملة.
#>

param(
    [string]$Domain = "dms.nociraq.com"
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = "DMS Toolkit - 08 الفحص الحاسم الشامل"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  🎯 الفحص الحاسم الشامل لنظام DMS على: https://$Domain" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$score = 0
$total = 6

# 1. فحص الخدمات الثلاث
Write-Host "`n[1/6] فحص حالة الخدمات الثلاث (Cloudflared, DmsApi, W3SVC)..." -ForegroundColor Green
$svcs = Get-Service -Name "Cloudflared", "DmsApi", "W3SVC" -ErrorAction SilentlyContinue
$allRunning = $true

foreach ($s in $svcs) {
    $stat = $s.Status
    $sColor = if ($stat -eq 'Running') { 'Green' } else { 'Red' }
    Write-Host "  - خدمة $($s.Name): $stat ($startType)" -ForegroundColor $sColor
    if ($stat -ne 'Running') { $allRunning = $false }
}

if ($allRunning -and $svcs.Count -eq 3) {
    Write-Host "✔ الخدمات الثلاث تعمل جميعاً (Running)!" -ForegroundColor Green
    $score++
} else {
    Write-Host "🔴 إحدى الخدمات متوقفة أو مفقودة!" -ForegroundColor Red
}

# 2. فحص مواقع IIS
Write-Host "`n[2/6] فحص مواقع IIS وتنازع المنفذ 80..." -ForegroundColor Green
try {
    Import-Module WebAdministration -ErrorAction Stop
    $dmsSite = Get-Website -Name "DmsApp" -ErrorAction SilentlyContinue
    $defSite = Get-Website -Name "Default Web Site" -ErrorAction SilentlyContinue

    $dmsOk = ($dmsSite.State -eq 'Started' -and $dmsSite.serverAutoStart -eq $true)
    $defOk = ($defSite.State -eq 'Stopped' -and $defSite.serverAutoStart -eq $false)

    if ($dmsOk -and $defOk) {
        Write-Host "✔ موقع DmsApp يعمل (Started/True) والموقع الافتراضي معطل (Stopped/False) بنجاح!" -ForegroundColor Green
        $score++
    } else {
        Write-Host "⚠️ تحذير: DmsApp ($($dmsSite.State)) أو Default Web Site ($($defSite.State)) غير مطابق!" -ForegroundColor Yellow
    }
} catch {
    Write-Host "⚠️ تعذر فحص IIS: $($_.Exception.Message)" -ForegroundColor DarkYellow
}

# 3. فحص مسار تشغيل خدمة Cloudflared
Write-Host "`n[3/6] فحص مسار خدمة Cloudflared في السجل..." -ForegroundColor Green
$qc = sc.exe qc Cloudflared | Out-String
if ($qc -match 'tunnel run' -and $qc -match 'config\.yml') {
    Write-Host "✔ مسار الخدمة يمرر المعاملات الصحيحة وينتهي بـ tunnel run." -ForegroundColor Green
    $score++
} else {
    Write-Host "🔴 مسار الخدمة عارٍ ولا يحتوي على tunnel run! راجع علاج العطل 7." -ForegroundColor Red
}

# 4. فحص صلاحية NT AUTHORITY\SYSTEM في SQL
Write-Host "`n[4/6] فحص صلاحيات حساب النظام في SQL Server..." -ForegroundColor Green
try {
    $checkOut = sqlcmd -S . -Q "SELECT IS_SRVROLEMEMBER('sysadmin', 'NT AUTHORITY\SYSTEM');" -h -1
    if ($checkOut.Trim() -match '1') {
        Write-Host "✔ حساب NT AUTHORITY\SYSTEM يحمل صلاحية sysadmin (النتيجة: 1)." -ForegroundColor Green
        $score++
    } else {
        Write-Host "🔴 حساب NT AUTHORITY\SYSTEM ليس sysadmin! (النتيجة: 0)." -ForegroundColor Red
    }
} catch {
    Write-Host "⚠️ تعذر التحقق من SQL Server: $($_.Exception.Message)" -ForegroundColor DarkYellow
}

# 5. فحص الـ API عبر النفق والدومين
Write-Host "`n[5/6] فحص استجابة الـ API عبر الإنترنت: https://$Domain/api/system/status..." -ForegroundColor Green
try {
    $apiUrl = "https://$Domain/api/system/status"
    $apiRes = Invoke-RestMethod -Uri $apiUrl -TimeoutSec 10
    if ($apiRes) {
        Write-Host "✔ رد الـ API سليم عبر الدومين الخارجي (JSON)! الصيانة: $($apiRes.maintenance)" -ForegroundColor Green
        $score++
    }
} catch {
    Write-Host "⚠️ تعذر الاتصال بالـ API عبر الدومين: $($_.Exception.Message)" -ForegroundColor Red
}

# 6. فحص الواجهة عبر النفق والدومين
Write-Host "`n[6/6] فحص استجابة واجهة الويب: https://$Domain..." -ForegroundColor Green
try {
    $webUrl = "https://$Domain"
    $webRes = Invoke-WebRequest -Uri $webUrl -UseBasicParsing -TimeoutSec 10
    if ($webRes.StatusCode -eq 200 -and $webRes.Content -match 'flutter|main\.dart\.js') {
        Write-Host "✔ واجهة DMS فلاتر تعمل عبر الدومين العام بكفاءة!" -ForegroundColor Green
        $score++
    } else {
        Write-Host "⚠️ استجابت الواجهة ولكن المحتوى غير متوقع (كود: $($webRes.StatusCode))." -ForegroundColor Yellow
    }
} catch {
    Write-Host "⚠️ تعذر الاتصال بالواجهة عبر الدومين: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n==========================================================" -ForegroundColor Cyan
$resColor = if ($score -eq $total) { 'Green' } else { 'Yellow' }
Write-Host "  نتيجة الفحص الحاسم: $score من $total اختبارات ناجحة" -ForegroundColor $resColor
Write-Host "==========================================================" -ForegroundColor Cyan

Write-Host "`n📋 الخطوة الذهبية القادمة (جائزة التجربة):" -ForegroundColor Yellow
Write-Host "1. افتح https://$Domain من هاتف محمول على بيانات الجوال (4G/5G)." -ForegroundColor White
Write-Host "2. سجل الدخول بـ admin وغيّر كلمة المرور الأولى." -ForegroundColor White
Write-Host "3. أنشئ كتاباً تجريبياً واعتمده، ثم امسح ختم الـ QR بكاميرا الهاتف العادية للتأكد من صفحة التحقق." -ForegroundColor White
Write-Host "4. أعد تشغيل الحاسبة (Restart-Computer) وافحص الموقع دون لمس الجهاز للتأكد من بقاء الخدمات." -ForegroundColor White
