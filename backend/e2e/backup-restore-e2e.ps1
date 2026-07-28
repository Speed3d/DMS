# ─────────────────────────────────────────────────────────────────────────────
# اختبار دورة النسخ الاحتياطي والاستعادة (E2E) — يعمل على API حيّ
#
# التشغيل: powershell -File backend\e2e\backup-restore-e2e.ps1 -AdminPwd <كلمة المرور>
#
# ⚠️ تدميري: يُنشئ كتاباً وارداً، يأخذ نسخة، يحذف الكتاب، يستعيد، ويتحقق أن الكتاب عاد.
#    شغّله على بيئة تطوير فقط. الملف بترميز UTF-8 with BOM لـ PowerShell 5.1.
# ─────────────────────────────────────────────────────────────────────────────
param(
    [Parameter(Mandatory=$true)][string]$AdminPwd,
    [string]$AdminUser = "admin",
    [string]$BaseUrl = "http://localhost:5080/api"
)
$ErrorActionPreference = "Stop"
$script:pass = 0; $script:fail = 0
function Ok($m)   { $script:pass++; Write-Host "  [نجح]  $m" -ForegroundColor Green }
function Bad($m)  { $script:fail++; Write-Host "  [فشل]  $m" -ForegroundColor Red }
function Section($t){ Write-Host "`n=== $t ===" -ForegroundColor Cyan }

function Api($method, $path, $body, $token, $companyId) {
    $headers = @{}
    if ($token)     { $headers["Authorization"] = "Bearer $token" }
    if ($companyId) { $headers["X-Company-Id"]  = "$companyId" }
    $params = @{ Uri = "$BaseUrl$path"; Method = $method; Headers = $headers; ContentType = "application/json; charset=utf-8" }
    if ($null -ne $body) { $params["Body"] = [System.Text.Encoding]::UTF8.GetBytes(($body | ConvertTo-Json -Depth 8 -Compress)) }
    try {
        $r = Invoke-WebRequest @params -UseBasicParsing
        $p = $null; if ($r.Content) { try { $p = $r.Content | ConvertFrom-Json } catch {} }
        return [pscustomobject]@{ Status = [int]$r.StatusCode; Body = $p; Raw = $r.Content }
    } catch {
        $resp = $_.Exception.Response
        $code = if ($resp) { [int]$resp.StatusCode } else { 0 }
        $content = ""
        if ($resp) { $sr = New-Object System.IO.StreamReader($resp.GetResponseStream()); $content = $sr.ReadToEnd() }
        $p = $null; if ($content) { try { $p = $content | ConvertFrom-Json } catch {} }
        return [pscustomobject]@{ Status = $code; Body = $p; Raw = $content }
    }
}
function Expect($label, $actual, $expected) {
    if ($actual -eq $expected) { Ok "$label (HTTP $actual)" } else { Bad "$label — متوقع $expected جاء $actual" }
}

Section "1) الدخول والتجهيز"
$tok = (Api POST "/auth/login" @{ username = $AdminUser; password = $AdminPwd } $null $null).Body.accessToken
if (-not $tok) { Bad "تعذّر الدخول"; exit 1 }
Ok "دخول $AdminUser"
$cid = (Api GET "/companies" $null $tok $null).Body[0].companyId
$eid = (Api GET "/entities" $null $tok $cid).Body[0].entityId

Section "2) إنشاء كتاب وارد مُعلَّم (سيكون شاهدنا على نجاح الاستعادة)"
$marker = "شاهد الاستعادة " + (Get-Date -Format "HHmmss")
$book = (Api POST "/incoming" @{
    companyId=$cid; externalNumber="RESTORE-TEST"; externalDate=$null
    receivedDate="2026-07-22T00:00:00"; receivedTime=$null; entityId=$eid
    subject=$marker; documentTypeId=$null; receiveMethod="Manual"
    keywords=$null; notes=$null; amount=$null; currency=$null; exchangeRate=$null
} $tok $cid).Body
if (-not $book.incomingId) { Bad "تعذّر إنشاء الكتاب الشاهد"; exit 1 }
Ok "الكتاب الشاهد: $($book.incomingNumber) — «$marker»"

Section "3) أخذ نسخة احتياطية كاملة (تحوي الكتاب الشاهد)"
$bk = Api POST "/backup/run" $null $tok $null
Expect "إنشاء نسخة احتياطية" $bk.Status 200
$bkId = $bk.Body.backupRecordId
Ok "النسخة #$bkId — النطاق: $($bk.Body.scope) — التصنيف: $($bk.Body.category) — الحجم: $([math]::Round($bk.Body.sizeBytes/1MB,2)) م.ب"
if ($bk.Body.scope -eq "Full") { Ok "النسخة اليدوية كاملة كما هو متوقع" } else { Bad "النطاق: $($bk.Body.scope)" }

Section "4) حذف الكتاب الشاهد (محاكاة فقدان بيانات)"
Expect "حذف الكتاب الشاهد" (Api DELETE "/incoming/$($book.incomingId)" $null $tok $cid).Status 204
$after = Api GET "/incoming/$($book.incomingId)" $null $tok $cid
Expect "تأكيد اختفاء الكتاب (404)" $after.Status 404

Section "5) رفض الاستعادة بلا كلمة تأكيد صحيحة"
Expect "رفض تأكيد خاطئ" (Api POST "/backup/$bkId/restore" @{ confirmation = "نعم" } $tok $null).Status 400

Section "6) الاستعادة بالتأكيد الصحيح"
Write-Host "  (قد تستغرق بعض الثواني — القاعدة تُغلق وتُستعاد)" -ForegroundColor DarkGray
$restore = Api POST "/backup/$bkId/restore" @{ confirmation = "استعادة" } $tok $null
Expect "الاستعادة نجحت" $restore.Status 200

Section "7) التحقق أن النظام عاد والكتاب رجع"
$status = Api GET "/system/status" $null $null $null
if ($status.Body.maintenance -eq $false) { Ok "النظام خرج من وضع الصيانة" } else { Bad "النظام ما زال في صيانة" }
$recovered = Api GET "/incoming/$($book.incomingId)" $null $tok $cid
Expect "الكتاب الشاهد عاد بعد الاستعادة" $recovered.Status 200
if ($recovered.Body.subject -eq $marker) { Ok "بيانات الكتاب سليمة: «$($recovered.Body.subject)»" } else { Bad "الموضوع لا يطابق: $($recovered.Body.subject)" }

Section "8) التحقق من نسخة الأمان التلقائية"
$list = (Api GET "/backup" $null $tok $null).Body
$safety = $list | Where-Object { $_.note -like "*أمان*قبل الاستعادة*" } | Select-Object -First 1
if ($safety) { Ok "نسخة الأمان سُجّلت تلقائياً: $($safety.fileName)" } else { Bad "لم تُسجَّل نسخة أمان" }

Section "9) تغطية النسخ — تذكير النسخة الكاملة"
$cov = Api GET "/backup/coverage" $null $tok $null
Expect "نقطة التغطية تعمل" $cov.Status 200
if ($cov.Body.urgency -eq "Ok") { Ok "التغطية سليمة بعد نسخة كاملة حديثة" }
else { Bad "التغطية غير متوقّعة: $($cov.Body.urgency)" }

# ───────────────── المرآة: نسخة كاملة يدوية إلى مسار خارجي ─────────────────
# ⚠️ المرآة هي ما يحمي المرفقات فعلاً بعد أن صارت المجدولة «قاعدة فقط».
#    فدورتها (مرآة ← حذف ← استعادة) جزء من معيار القبول 10 لا إضافة تجميلية.
$mirrorDir = Join-Path $env:TEMP "dms-mirror-e2e"
if (Test-Path $mirrorDir) { Remove-Item $mirrorDir -Recurse -Force -ErrorAction SilentlyContinue }

Section "10) المرآة ترفض المسارات الخطرة"
Expect "رفض مسار داخل مجلد نظام" (Api POST "/backup/mirror" @{ targetPath = "C:\Windows\Temp\dms" } $tok $null).Status 400
Expect "رفض مسار نسبي"            (Api POST "/backup/mirror" @{ targetPath = "mirror" } $tok $null).Status 400
Expect "رفض مسار بلا حرف قرص"     (Api POST "/backup/mirror" @{ targetPath = "\mirror" } $tok $null).Status 400
Expect "رفض مسار فارغ"            (Api POST "/backup/mirror" @{ targetPath = "" } $tok $null).Status 400

Section "11) المرآة الأولى تنسخ، والثانية لا تُكرّر"
$m1 = Api POST "/backup/mirror" @{ targetPath = $mirrorDir } $tok $null
Expect "المرآة الأولى نجحت" $m1.Status 200
if ($m1.Body.databaseOk) { Ok "قاعدة البيانات نُسخت إلى المرآة" } else { Bad "فشل نسخ القاعدة: $($m1.Body.note)" }
if ($m1.Body.copied -gt 0) { Ok "نُسخ $($m1.Body.copied) ملفاً" } else { Bad "لم يُنسخ أي ملف" }

$m2 = Api POST "/backup/mirror" @{ targetPath = $mirrorDir } $tok $null
if ($m2.Body.copied -eq 0 -and $m2.Body.skipped -gt 0) {
    Ok "لا تكرار: تُخطّي $($m2.Body.skipped) ملفاً ونُسخ 0"
} else { Bad "المرآة كرّرت النسخ (نُسخ=$($m2.Body.copied))" }

Section "12) دورة المرآة: حذف ← استعادة ← الكتاب يعود"
$mMarker = "شاهد المرآة " + (Get-Date -Format "HHmmss")
$mBook = (Api POST "/incoming" @{
    companyId=$cid; externalNumber="MIR"; externalDate=$null
    receivedDate="2026-07-28T00:00:00"; receivedTime=$null; entityId=$eid
    subject=$mMarker; documentTypeId=$null; receiveMethod="Manual"
    folderName=$null; keywords=$null; notes=$null; amount=$null; currency=$null; exchangeRate=$null
} $tok $cid).Body
if ($mBook) { Ok "الكتاب الشاهد للمرآة: $($mBook.incomingNumber)" } else { Bad "تعذّر إنشاء كتاب المرآة" }

Api POST "/backup/mirror" @{ targetPath = $mirrorDir } $tok $null | Out-Null
Api DELETE "/incoming/$($mBook.incomingId)" $null $tok $cid | Out-Null
Expect "الكتاب حُذف قبل الاستعادة" (Api GET "/incoming/$($mBook.incomingId)" $null $tok $cid).Status 404

Expect "رفض استعادة المرآة بتأكيد خاطئ" (Api POST "/backup/mirror/restore" @{ sourcePath = $mirrorDir; confirmation = "نعم" } $tok $null).Status 400
Expect "الاستعادة من المرآة نجحت" (Api POST "/backup/mirror/restore" @{ sourcePath = $mirrorDir; confirmation = "استعادة" } $tok $null).Status 200
Start-Sleep -Seconds 2
Expect "الكتاب الشاهد عاد من المرآة" (Api GET "/incoming/$($mBook.incomingId)" $null $tok $cid).Status 200

# تنظيف
if (Test-Path $mirrorDir) { Remove-Item $mirrorDir -Recurse -Force -ErrorAction SilentlyContinue }
Api DELETE "/incoming/$($mBook.incomingId)" $null $tok $cid | Out-Null

Write-Host "`n================ النتيجة ================" -ForegroundColor Cyan
Write-Host "  نجح: $script:pass" -ForegroundColor Green
Write-Host "  فشل: $script:fail" -ForegroundColor $(if ($script:fail -gt 0) { "Red" } else { "Green" })
if ($script:fail -eq 0) { Write-Host "  دورة النسخ والاستعادة سليمة" -ForegroundColor Green }
exit $(if ($script:fail -gt 0) { 1 } else { 0 })
