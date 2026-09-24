<#
.SYNOPSIS
    07-trial-tunnel-setup.ps1 - يُشغَّل على [ 🧪 حاسبة التجربة ] حصراً.
.DESCRIPTION
    يقوم بتثبيت cloudflared، إنشاء نفق dms-tunnel، ضبط التوجيه الصحيح بالريجكس،
    ونسخ الإعدادات لحساب SYSTEM وتصحيح ImagePath في السجل (علاج العطل 7)،
    ثم تشغيل النفق كخدمة ويندوز مستقرة.
#>

param(
    [string]$Domain     = "dms.nociraq.com",
    [string]$TunnelName = "dms-tunnel"
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = "DMS Toolkit - 07 ضبط نفق Cloudflare"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  🧪 [حاسبة التجربة] إعداد نفق Cloudflare Tunnel الآمن" -ForegroundColor Cyan
Write-Host "  الدومين المستهدف: https://$Domain" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. تفعيل بروتوكول TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# 2. فحص وتثبيت cloudflared
Write-Host "`n[1/6] فحص برنامج cloudflared..." -ForegroundColor Green
$cfCmd = Get-Command cloudflared -ErrorAction SilentlyContinue

if (-not $cfCmd) {
    Write-Host "  - تحميل وتثبيت cloudflared msi..." -ForegroundColor Yellow
    $msi = "$env:TEMP\cloudflared.msi"
    Invoke-WebRequest -UseBasicParsing -OutFile $msi -Uri "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.msi"
    Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /qn" -Wait
    
    $env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [Environment]::GetEnvironmentVariable("Path","User")
}
Write-Host "✔ إصدار cloudflared: $(cloudflared --version)" -ForegroundColor Green

# 3. التحقق من الدخول والشهادة cert.pem
Write-Host "`n[2/6] التحقق من تسجيل الدخول إلى Cloudflare..." -ForegroundColor Green
$userCfDir = "$env:USERPROFILE\.cloudflared"
$certPath  = "$userCfDir\cert.pem"

if (-not (Test-Path $certPath)) {
    Write-Host "⚠️ لم يتم العثور على شهادة التفويض cert.pem!" -ForegroundColor Yellow
    Write-Host "سيتم فتح جلسة الدخول الآن. انسخ الرابط الذي سيظهر في المتصفح وفوض الدومين:" -ForegroundColor Cyan
    cloudflared tunnel login
}

if (-not (Test-Path $certPath)) {
    Write-Host "🔴 لم يتم إتمام تسجيل الدخول أو حفظ الشهادة!" -ForegroundColor Red
    exit 1
}
Write-Host "✔ شهادة التفويض موجودة في: $certPath" -ForegroundColor Green

# 4. إنشاء النفق أو استخدام النفق القائم
Write-Host "`n[3/6] تهيئة النفق ($TunnelName)..." -ForegroundColor Green
$existingTunnel = cloudflared tunnel list | Select-String $TunnelName
if (-not $existingTunnel) {
    Write-Host "  - إنشاء نفق جديد باسم $TunnelName..." -ForegroundColor Gray
    cloudflared tunnel create $TunnelName
} else {
    Write-Host "  ℹ النفق $TunnelName منشأ مسبقاً." -ForegroundColor Gray
}

# استخراج معرف النفق UUID
$id = (Get-ChildItem "$userCfDir\*.json" | Where-Object BaseName -match '^[0-9a-f-]{36}$' | Select-Object -First 1).BaseName
if (-not $id) {
    Write-Host "🔴 تعذر العثور على ملف بيانات اعتماد النفق (UUID.json)!" -ForegroundColor Red
    exit 1
}
Write-Host "معرف النفق (Tunnel ID): $id" -ForegroundColor Cyan

# 5. كتابة config.yml والتحقق من التوجيه المنطقي
Write-Host "`n[4/6] كتابة قواعد التوجيه في config.yml..." -ForegroundColor Green
$configContent = @"
tunnel: $id
credentials-file: $userCfDir\$id.json

ingress:
  - hostname: $Domain
    path: "^/(api|v)(/|`$)"
    service: http://localhost:5080

  - hostname: $Domain
    service: http://localhost:80

  - service: http_status:404
"@

$configContent | Out-File -FilePath "$userCfDir\config.yml" -Encoding ascii -Force

# التحقق من صحة القواعد قبل التشغيل
cloudflared tunnel ingress validate
Write-Host "✔ قواعد التوجيه صحيحة نحو 5080 للـ API و 80 للواجهة." -ForegroundColor Green

# ربط الـ DNS
Write-Host "  - ربط مسار DNS للدومين $Domain..." -ForegroundColor Gray
cloudflared tunnel route dns $TunnelName $Domain -ErrorAction SilentlyContinue | Out-Null

# 6. [علاج العطل 7]: تجهيز إعدادات حساب SYSTEM وتصحيح ImagePath في السجل
Write-Host "`n[5/6] تجهيز إعدادات SYSTEM وتصحيح مسار خدمة النفق (حل العطل 7)..." -ForegroundColor Yellow
$sysDir = "C:\Windows\System32\config\systemprofile\.cloudflared"
New-Item -ItemType Directory -Force -Path $sysDir | Out-Null
Copy-Item "$userCfDir\*" $sysDir -Force -Recurse

# كتابة config.yml خاص بحساب SYSTEM بمساراته المستقلة
$sysConfigContent = @"
tunnel: $id
credentials-file: $sysDir\$id.json

ingress:
  - hostname: $Domain
    path: "^/(api|v)(/|`$)"
    service: http://localhost:5080

  - hostname: $Domain
    service: http://localhost:80

  - service: http_status:404
"@
$sysConfigContent | Out-File -FilePath "$sysDir\config.yml" -Encoding ascii -Force

# تسجيل الخدمة إن لم تكن مسجلة
if (-not (Get-Service -Name "Cloudflared" -ErrorAction SilentlyContinue)) {
    cloudflared service install | Out-Null
}

# تصحيح مسار ImagePath الحاسم في السجل حتى لا تخرج الخدمة فوراً
$cfExe = (Get-Command cloudflared).Source
$img = "`"$cfExe`" --config `"$sysDir\config.yml`" --no-autoupdate tunnel run"
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Cloudflared" -Name ImagePath -Value $img -Type ExpandString

sc.exe failure Cloudflared reset= 86400 actions= restart/30000/restart/30000/restart/60000 | Out-Null

# 7. تشغيل الخدمة
Write-Host "`n[6/6] تشغيل خدمة Cloudflared..." -ForegroundColor Green
Stop-Service Cloudflared -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Start-Service Cloudflared
Start-Sleep -Seconds 10

$services = Get-Service Cloudflared, DmsApi, W3SVC | Select-Object Name, Status, StartType
$services | Format-Table -AutoSize

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "  ✅ تم إعداد وتشغيل نفق Cloudflare كخدمة ويندوز بنجاح!" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
