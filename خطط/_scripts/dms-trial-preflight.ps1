# ─────────────────────────────────────────────────────────────────────────────
# DMS — فحصُ ما قبل التنصيب على حاسبة التجربة   (قراءةٌ خالصة: لا يغيّر شيئاً)
#
#   التشغيل (PowerShell كمسؤول):
#       powershell -ExecutionPolicy Bypass -File .\dms-trial-preflight.ps1
#
#   ماذا يفعل: يفحص الستّة التي يقوم عليها التنصيب، ثم **يطبع لك الأوامر التالية
#   وقد كُتب فيها اسمُ مثيل SQL عندك ودومينك** — فلا تخمّن ولا تبدّل بيدك.
#
#   🔑 ولماذا سكربتُ فحصٍ أصلاً؟ لأن ثلاثة من هذه الستّة **تفشل متأخّرةً ومُضلِّلةً**:
#      · حزمةُ .NET الخطأ  ⇐ الخدمة لا تُقلع بلا سجلٍّ مفهوم
#      · اسمُ مثيل SQL خطأ ⇐ `depend=` يمرّ صامتاً ولا يظهر إلا يوم إعادة تشغيل
#      · `web.config` مفقود ⇐ صفحةٌ بيضاء بلا رسالة خطأ
#   الملف بترميز UTF-8 with BOM ليقرأ PowerShell 5.1 العربية صحيحةً.
# ─────────────────────────────────────────────────────────────────────────────

param(
    [string]$Domain  = "dms.nociraq.com",
    [string]$DbName  = "DmsTrial",
    [string]$ApiDir  = "C:\DMS\api",
    [string]$AppDir  = "C:\DMS\app",
    [string]$DataDir = "C:\DMS\data"
)

$ErrorActionPreference = "Continue"
$script:Fail = 0
$script:Warn = 0

function Head($t) { Write-Host "`n══ $t" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "   [ نجح ]  $m" -ForegroundColor Green }
function Bad($m)  { Write-Host "   [ فشل ]  $m" -ForegroundColor Red;    $script:Fail++ }
function Note($m) { Write-Host "   [ انتبه] $m" -ForegroundColor Yellow; $script:Warn++ }
function Info($m) { Write-Host "            $m" -ForegroundColor DarkGray }

Write-Host "`n╔═══════════════════════════════════════════════════════╗"
Write-Host   "║   DMS — فحص ما قبل التنصيب (حاسبة التجربة)            ║"
Write-Host   "╚═══════════════════════════════════════════════════════╝"
Write-Host "   الدومين: $Domain   ·   القاعدة: $DbName"

# ── 1) ASP.NET Core Runtime 9 ────────────────────────────────────────────────
# 🔴 «.NET Runtime» و«ASP.NET Core Runtime» حزمتان مختلفتان في الصفحة نفسها.
#    الأولى وحدها تجعل Dms.Api.exe يخرج فوراً بـ«framework not found» بلا خدمة.
#
# 🔑 والفحصُ **يجرّب البرنامج نفسه** ولا يسأل `dotnet` الذي في الـPATH — لأن ذاك قد يكون
#    تثبيتاً **32-بت** (‎C:\Program Files (x86)\dotnet‎) بينما Dms.Api.exe مبنيٌّ x64 ويقرأ
#    تثبيتاً آخر تماماً. فسؤالُ الـPATH يعطي «فشل» كاذباً والإطارُ سليمٌ فعلاً (وقع 2026-09-22).
#    ودرسُ المشروع نفسه: اختبارٌ لا يجرّب المنتج الحقيقيّ يحرس هيكلاً لا منتجاً.
#
#    والمسبار آمنٌ تماماً: `generate-secrets` بلا `--out` يطبع سطر الاستخدام ويخرج
#    **بلا كتابة ملفٍّ واحد** (مُتحقَّقٌ من `SecretsGenerator.Run`).
Head "1) ASP.NET Core Runtime 9"
$exeProbe = Join-Path $ApiDir "Dms.Api.exe"

if (Test-Path $exeProbe) {
    $probe = ""
    try { $probe = (& $exeProbe generate-secrets 2>&1 | Out-String) } catch { $probe = "$_" }

    if ($probe -match 'generate-secrets --out') {
        Ok "الإطار سليم — Dms.Api.exe أقلع ونفّذ فعلاً (مسبارٌ حقيقيّ لا استنتاج)."
    } elseif ($probe -match 'AspNetCore\.App|must install|framework.*not found|to run this application') {
        Bad "الإطار ناقص — Dms.Api.exe لا يجد Microsoft.AspNetCore.App 9."
        Info "نزّل **ASP.NET Core Runtime 9.x.x** ← Windows **x64** Installer:"
        Info "  https://dotnet.microsoft.com/download/dotnet/9.0"
        Info "(لا «.NET Runtime» ولا «.NET Desktop Runtime» — والاسم يجب أن يبدأ بـ aspnetcore-runtime)"
        ($probe -split "`n" | Select-Object -First 4) | ForEach-Object { if ($_.Trim()) { Info $_.Trim() } }
    } else {
        Note "ناتج المسبار غير متوقَّع — اقرأه بنفسك:"
        ($probe -split "`n" | Select-Object -First 6) | ForEach-Object { if ($_.Trim()) { Info $_.Trim() } }
    }
} else {
    Note "Dms.Api.exe لم يصل بعد — فحصٌ غير مباشر (أضعفُ من المسبار)."
    $x64 = "C:\Program Files\dotnet\shared\Microsoft.AspNetCore.App"
    $found = @(Get-ChildItem $x64 -Directory -EA SilentlyContinue | Where-Object Name -like '9.*')
    if ($found) {
        Ok "وُجدت x64: $($found.Name -join ', ')"
    } else {
        Bad "لا ASP.NET Core Runtime 9 في التثبيت x64 ($x64)."
        Info "نزّل: https://dotnet.microsoft.com/download/dotnet/9.0 ← ASP.NET Core Runtime 9 ← Windows x64"
    }
}

# ⚠️ ولا تُبنى نتيجةٌ على هذا — للعلم فقط، فقد يكون تثبيتاً 32-بت لا يخصّنا.
$pathDotnet = (Get-Command dotnet -EA SilentlyContinue).Source
if ($pathDotnet) {
    Info "للعلم — dotnet في الـPATH: $pathDotnet"
    if ($pathDotnet -like '*Program Files (x86)*') {
        Info "  ⚠️ وهو **32-بت**، فـ `dotnet --list-runtimes` لا يعرض تثبيت x64 الذي يستعمله البرنامج."
    }
}

# ── 2) مثيل SQL Server ───────────────────────────────────────────────────────
# اسمُه يدخل في ثلاثة أوامر لاحقة، فيُقرأ من الجهاز ولا يُفترض.
Head "2) مثيل SQL Server"
$sqlSvc = Get-Service | Where-Object { $_.Name -eq 'MSSQLSERVER' -or $_.Name -like 'MSSQL$*' }
$DbServer = $null; $SqlServiceName = $null

if (-not $sqlSvc) {
    Bad "لا مثيل SQL Server على هذا الجهاز."
    Info "ثبّت SQL Server 2022 Express (خيار Basic)."
} else {
    foreach ($s in $sqlSvc) {
        $state = if ($s.Status -eq 'Running') { 'يعمل' } else { "متوقّف ($($s.Status))" }
        Info "$($s.Name)  —  $state"
    }
    $running = @($sqlSvc | Where-Object Status -eq 'Running')
    $pick = if ($running.Count -ge 1) { $running[0] } else { $sqlSvc[0] }
    $SqlServiceName = $pick.Name
    $DbServer = if ($pick.Name -eq 'MSSQLSERVER') { "." } else { ".\" + $pick.Name.Split('$')[1] }

    if ($running.Count -eq 0) {
        Bad "المثيل موجود لكنه متوقّف. شغّله:  Start-Service '$SqlServiceName'"
    } elseif ($running.Count -gt 1) {
        Note "أكثر من مثيلٍ يعمل — اخترتُ '$SqlServiceName'. غيّره إن أردتَ غيره."
        Ok "db-server = $DbServer"
    } else {
        Ok "المثيل: $SqlServiceName   ⇒   --db-server $DbServer"
    }
}

# ── 3) IIS ───────────────────────────────────────────────────────────────────
Head "3) IIS (لخدمة ملفات الواجهة)"
if (Get-Service W3SVC -ErrorAction SilentlyContinue) {
    Ok "IIS مثبَّت."
} else {
    Bad "IIS غير مثبَّت — الواجهة بلا خادم ملفات."
    Info "على ويندوز 10/11 (كمسؤول):"
    Info "  Enable-WindowsOptionalFeature -Online -All -FeatureName IIS-WebServerRole, IIS-WebServer, IIS-StaticContent, IIS-DefaultDocument, IIS-ManagementConsole"
    Info "على Windows Server:  Install-WindowsFeature -Name Web-Server -IncludeManagementTools"
}

# ── 4) cloudflared ───────────────────────────────────────────────────────────
Head "4) cloudflared (النفق)"
$cf = Get-Command cloudflared -ErrorAction SilentlyContinue
if ($cf) { Ok "موجود: $(& cloudflared --version 2>$null)" }
else {
    Note "غير مثبَّت — يلزم في المرحلة ز (بعد نجاح ما قبلها، فلا يمنعك الآن)."
    Info "نزّل cloudflared-windows-amd64.msi من:"
    Info "  https://github.com/cloudflare/cloudflared/releases/latest"
}

# ── 5) المجلدات والملفات المنقولة ────────────────────────────────────────────
Head "5) المجلدات وملفات الإصدار"
foreach ($d in @($ApiDir, $AppDir, "$DataDir\storage", "$DataDir\backups")) {
    if (Test-Path $d) { Ok "موجود: $d" } else { Note "ناقص: $d  (يُنشأ في الأمر أدناه)" }
}

$exe = Join-Path $ApiDir "Dms.Api.exe"
if (Test-Path $exe) { Ok "وصل الباك-إند: Dms.Api.exe" }
else { Bad "Dms.Api.exe غير موجود في $ApiDir — فُكّ dms-api.zip هناك." }

# 🔴 غيابُ web.config لا يعطي خطأً: يعطي صفحةً بيضاء — وهي أصعب ما يُشخَّص.
$webcfg = Join-Path $AppDir "web.config"
if (Test-Path $webcfg) { Ok "وصلت الواجهة ومعها web.config (تعريف .wasm)" }
else {
    Bad "web.config غير موجود في $AppDir"
    Info "بلا هذا الملف يردّ IIS بـ404 على canvaskit.wasm ⇒ صفحةٌ بيضاء بلا رسالة خطأ."
    Info "فُكّ dms-app.zip كاملاً في $AppDir (لا تنسخ ملفاتٍ منتقاة)."
}

# 🔐 ملفُّ تطويرٍ وصل ⇒ أسرارٌ تسرّبت، وإقلاعةٌ بالبيئة الخطأ تفتح نقطة تصفير القاعدة.
if (Test-Path (Join-Path $ApiDir "appsettings.Development.json")) {
    Bad "appsettings.Development.json موجود — احذفه فوراً."
    Info "يحمل مفاتيح تطوير، وإقلاعٌ ببيئة تطويرٍ خطأً يفتح AllowAnyOrigin وSwagger ونقطة تصفير القاعدة."
} else { Ok "لا ملفَّ تطويرٍ مُسرَّب." }

# ── 6) المنافذ ───────────────────────────────────────────────────────────────
Head "6) المنافذ 80 و 5080"
foreach ($p in @(80, 5080)) {
    $used = Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue
    if ($used) {
        $pid0 = ($used | Select-Object -First 1).OwningProcess
        $pname = (Get-Process -Id $pid0 -ErrorAction SilentlyContinue).ProcessName
        Note "المنفذ $p مشغول بـ '$pname' (PID $pid0)."
        if ($p -eq 80) { Info "غالباً 'Default Web Site' — يوقفه الأمر في §و-5." }
    } else { Ok "المنفذ $p حرّ." }
}

# ── الخلاصة ──────────────────────────────────────────────────────────────────
Write-Host "`n╔═══════════════════════════════════════════════════════╗"
if ($script:Fail -eq 0) {
    Write-Host "║  ✔ جاهز — لا مانع                                     ║" -ForegroundColor Green
} else {
    Write-Host "║  ✖ $($script:Fail) مانعاً — عالجها قبل المتابعة            ║" -ForegroundColor Red
}
Write-Host   "╚═══════════════════════════════════════════════════════╝"
Write-Host "   موانع: $($script:Fail)   ·   تنبيهات: $($script:Warn)"

if ($DbServer) {
    Write-Host "`n─── الأوامر التالية، مكتوبةً بقيم جهازك ───────────────" -ForegroundColor Cyan
    Write-Host @"

# (1) المجلدات + إذنُ محرّك SQL بالكتابة في مجلد النسخ
'$ApiDir','$AppDir','$DataDir\storage','$DataDir\backups' |
    ForEach-Object { New-Item -ItemType Directory -Force -Path `$_ | Out-Null }
icacls "$DataDir\backups" /grant '"NT SERVICE\$SqlServiceName":(OI)(CI)(M)'

# (2) توليد الأسرار  —  اكتب كلمة مرور المدير الظاهرة على الشاشة فوراً
cd $ApiDir
.\Dms.Api.exe generate-secrets ``
    --out       $ApiDir\appsettings.Production.json ``
    --origins   https://$Domain ``
    --db-server "$DbServer" ``
    --db-name   $DbName ``
    --storage   $DataDir\storage ``
    --backup    $DataDir\backups

# (3) أول إقلاع — ينشئ القاعدة ويطبّق المهاجرات، ثم Ctrl+C
`$env:ASPNETCORE_ENVIRONMENT = "Production"
.\Dms.Api.exe
#    انتظر:  Now listening on: http://localhost:5080    ثم  Ctrl+C
#    تحقّق في SSMS:  USE $DbName; SELECT COUNT(*) FROM __EFMigrationsHistory;   -- يجب 30

# (4) تسجيل الخدمة   (لاحظ الاقتباس المفرد في depend= — `$ في PowerShell متغيّر)
sc.exe create DmsApi binPath= "$ApiDir\Dms.Api.exe" start= auto DisplayName= "DMS API Service"
sc.exe config DmsApi depend= '$SqlServiceName'
sc.exe failure DmsApi reset= 86400 actions= restart/30000/restart/30000/restart/60000
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\DmsApi" ``
    -Name "Environment" -Value @("ASPNETCORE_ENVIRONMENT=Production") -Type MultiString
Start-Service DmsApi
Invoke-RestMethod -Uri "http://localhost:5080/api/system/status"    # maintenance : False

# (5) الواجهة على IIS
Import-Module WebAdministration
Stop-Website -Name "Default Web Site" -ErrorAction SilentlyContinue
New-Website -Name "DmsApp" -Port 80 -PhysicalPath "$AppDir" -Force
Start-Website -Name "DmsApp"
icacls "$AppDir" /grant "IIS_IUSRS:(OI)(CI)(RX)"
(Invoke-WebRequest "http://localhost/canvaskit/canvaskit.wasm" -UseBasicParsing).StatusCode   # 200

"@ -ForegroundColor White
}

Write-Host ""
