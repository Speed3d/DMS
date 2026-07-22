# ─────────────────────────────────────────────────────────────────────────────
# اختبار التدفق الشامل (E2E) لوحدة الوارد — يعمل على API حيّ
#
# التشغيل:
#   1) شغّل الـ API:  cd D:\DMS\backend ; dotnet run --project Dms.Api
#   2) شغّل الاختبار: powershell -File backend\e2e\incoming-e2e.ps1 -AdminPwd <كلمة المرور> -EmployeeUser sinan -EmployeePwd <كلمة المرور>
#
# ملاحظات:
#   - كلمات المرور تُمرَّر كمعاملات ولا تُخزَّن في الملف إطلاقاً.
#   - الاختبار يُنشئ بيانات حقيقية (كتب واردة، وكتاب صادر معتمد إن لم يوجد) في قاعدة
#     البيانات المتصل بها. شغّله على بيئة تطوير فقط.
#   - الملف محفوظ بترميز UTF-8 with BOM ليقرأ PowerShell 5.1 العربية بشكل صحيح.
# ─────────────────────────────────────────────────────────────────────────────
param(
    [Parameter(Mandatory=$true)][string]$AdminPwd,
    [string]$AdminUser = "admin",
    [string]$EmployeeUser = "",
    [string]$EmployeePwd = "",
    [string]$BaseUrl = "http://localhost:5080/api"
)

$ErrorActionPreference = "Stop"
$script:pass = 0
$script:fail = 0

function Ok($msg)    { $script:pass++; Write-Host "  [نجح]  $msg" -ForegroundColor Green }
function Bad($msg)   { $script:fail++; Write-Host "  [فشل]  $msg" -ForegroundColor Red }
function Skip($msg)  { Write-Host "  [تخطّي] $msg" -ForegroundColor Yellow }
function Section($t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }

# استدعاء الـ API — يعيد كائناً فيه Status و Body
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
    if ($actual -eq $expected) { Ok "$label (HTTP $actual)" }
    else { Bad "$label — متوقع HTTP $expected لكن جاء $actual" }
}

# ─────────────────────────── 1) الدخول والتجهيز ───────────────────────────
Section "1) تسجيل الدخول والتجهيز"
$login = Api POST "/auth/login" @{ username = $AdminUser; password = $AdminPwd } $null $null
if ($login.Status -ne 200) { Bad "تعذّر الدخول بـ $AdminUser : $($login.Status) $($login.Raw)"; exit 1 }
$adminTok = $login.Body.accessToken
Ok "دخول $AdminUser — الدور: $($login.Body.role)"
if ($login.Body.modules -contains "Incoming") { Ok "صلاحية قسم الوارد متاحة" } else { Bad "لا يملك صلاحية قسم الوارد" }

$company = (Api GET "/companies" $null $adminTok $null).Body | Select-Object -First 1
if (-not $company) { Bad "لا توجد شركة في النظام"; exit 1 }
$cid = $company.companyId
Ok "الشركة: $($company.name) (رمز $($company.prefix))"

$entity = (Api GET "/entities" $null $adminTok $cid).Body |
          Where-Object { $_.kind -eq "Incoming" -or $_.kind -eq "Both" } | Select-Object -First 1
if (-not $entity) {
    $entity = (Api POST "/entities" @{ companyId = $cid; name = "جهة اختبار الوارد"; kind = "Both"; notes = $null } $adminTok $cid).Body
}
$eid = $entity.entityId
Ok "الجهة المرسلة: $($entity.name)"

# قالب كتاب وارد يُعاد استخدامه في كل الاختبارات
$template = @{
    companyId = $cid; externalNumber = "E2E"; externalDate = "2026-07-18T00:00:00"
    receivedDate = "2026-07-21T00:00:00"; receivedTime = "09:15:00"
    entityId = $eid; subject = "اختبار الوارد"; documentTypeId = $null
    receiveMethod = "Manual"; folderName = $null; keywords = "اختبار"; notes = $null
    amount = $null; currency = $null; exchangeRate = $null
}
function NewBook($subject, $token) {
    $b = $template.Clone(); $b.subject = $subject
    return (Api POST "/incoming" $b $token $cid)
}

# ─────────────────────────── 2) التسجيل والترقيم ───────────────────────────
Section "2) تسجيل كتاب وارد وطريقة الاستلام"
$create = NewBook "اختبار دورة الوارد الكاملة" $adminTok
Expect "تسجيل كتاب وارد (receiveMethod=Manual)" $create.Status 200
if ($create.Status -ne 200) { Write-Host $create.Raw -ForegroundColor Yellow; exit 1 }
$book = $create.Body
$bid  = $book.incomingId
Ok "الرقم المولَّد: $($book.incomingNumber) — الحالة: $($book.status)"
if ($book.incomingNumber -like "$($company.prefix)-IN-*") { Ok "صيغة الترقيم صحيحة" } else { Bad "صيغة الترقيم: $($book.incomingNumber)" }
if ($book.status -eq "New") { Ok "الحالة الابتدائية (جديد)" } else { Bad "الحالة الابتدائية: $($book.status)" }
if ($book.receivedByUserName) { Ok "اسم المستلم معبّأ: $($book.receivedByUserName)" } else { Bad "اسم المستلم فارغ" }

foreach ($m in @("Mail", "Email")) {
    $b = $template.Clone(); $b.receiveMethod = $m; $b.subject = "اختبار طريقة الاستلام $m"
    Expect "تسجيل كتاب بطريقة استلام $m" (Api POST "/incoming" $b $adminTok $cid).Status 200
}
$bad = $template.Clone(); $bad.receiveMethod = "Hand"   # قيمة غير موجودة في enum الباك-إند
$r = Api POST "/incoming" $bad $adminTok $cid
if ($r.Status -ge 400) { Ok "قيمة طريقة استلام غير معروفة مرفوضة (HTTP $($r.Status))" } else { Bad "قيمة غير معروفة قُبلت!" }

# ─────────────────────────── 3) مصفوفة الانتقالات ───────────────────────────
Section "3) مصفوفة انتقالات الحالة"
function ChangeStatus($id, $status, $note) { Api POST "/incoming/$id/status" @{ status = $status; note = $note } $adminTok $cid }

Expect "رفض: جديد ← تم الرد"                  (ChangeStatus $bid "Replied" "رد مباشر").Status 400
Expect "رفض: جديد ← مؤرشف (يتخطى الإغلاق)"    (ChangeStatus $bid "Archived" $null).Status 400
Expect "رفض: جديد ← جديد (نفس الحالة)"        (ChangeStatus $bid "New" $null).Status 400
Expect "قبول: جديد ← قيد المراجعة"            (ChangeStatus $bid "InReview" "تحويل للمراجعة").Status 200
Expect "رفض: تم الرد يدوياً بلا ملاحظة"        (ChangeStatus $bid "Replied" $null).Status 400
Expect "قبول: قيد المراجعة ← تم الرد (بملاحظة)" (ChangeStatus $bid "Replied" "رد ورقي رقم 77").Status 200
Expect "رفض: تم الرد ← مؤرشف"                 (ChangeStatus $bid "Archived" $null).Status 400
Expect "رفض: تم الرد ← قيد المراجعة (رجوع)"    (ChangeStatus $bid "InReview" $null).Status 400

# ─────────────────────────── 4) الإحالة ───────────────────────────
Section "4) الإحالة لقسم"
Expect "رفض إحالة كتاب في حالة (تم الرد)" (Api POST "/incoming/$bid/forward" @{ toDepartment = "قسم المالية"; note = $null } $adminTok $cid).Status 400

$fresh = (NewBook "كتاب لاختبار الإحالة" $adminTok).Body
$r = Api POST "/incoming/$($fresh.incomingId)/forward" @{ toDepartment = "قسم المالية"; note = "للدراسة والرأي" } $adminTok $cid
Expect "قبول إحالة كتاب (جديد)" $r.Status 200
if ($r.Body.status -eq "InReview") { Ok "الإحالة نقلت الحالة إلى (قيد المراجعة)" } else { Bad "الحالة بعد الإحالة: $($r.Body.status)" }
if ($r.Body.folderName -eq "قسم المالية") { Ok "القسم المحال إليه محفوظ" } else { Bad "القسم: $($r.Body.folderName)" }

# ─────────────────────────── 5) الإغلاق والأرشفة ───────────────────────────
Section "5) إتمام الدورة حتى الأرشفة"
Expect "قبول: تم الرد ← مغلق"        (ChangeStatus $bid "Closed" "انتهت المعاملة").Status 200
Expect "قبول: مغلق ← مؤرشف"          (ChangeStatus $bid "Archived" "أرشفة نهائية").Status 200
Expect "رفض: مؤرشف ← جديد"           (ChangeStatus $bid "New" $null).Status 400
Expect "رفض إحالة كتاب مؤرشف"        (Api POST "/incoming/$bid/forward" @{ toDepartment = "قسم آخر"; note = $null } $adminTok $cid).Status 400
$upd = @{ externalNumber="x"; externalDate=$null; receivedDate="2026-07-21T00:00:00"; receivedTime=$null
          entityId=$eid; subject="تعديل ممنوع"; documentTypeId=$null; receiveMethod="Manual"
          folderName=$null; keywords=$null; notes=$null; amount=$null; currency=$null; exchangeRate=$null }
Expect "رفض تعديل كتاب مؤرشف" (Api PUT "/incoming/$bid" $upd $adminTok $cid).Status 400

# ─────────────────────────── 6) الربط بالصادر ───────────────────────────
Section "6) الربط بكتاب صادر معتمد"
# Hint: نبحث عن صادر معتمد **غير مرتبط** بوارد آخر — الربط علاقة واحد‑لواحد،
# وبدون هذا الفحص يفشل الاختبار عند إعادة تشغيله (الصادر يبقى مرتبطاً من تشغيل سابق).
$approved = $null
foreach ($o in ((Api GET "/outgoing" $null $adminTok $cid).Body | Where-Object { $_.status -eq "Final" })) {
    $detail = (Api GET "/outgoing/$($o.outgoingId)" $null $adminTok $cid).Body
    if ($null -eq $detail.replyToIncomingId) { $approved = $detail; break }
}
if (-not $approved) {
    $tpl = (Api GET "/templates" $null $adminTok $cid).Body | Select-Object -First 1
    if ($tpl) {
        $draft = Api POST "/outgoing" @{
            companyId = $cid; entityId = $eid; templateId = $tpl.templateId; date = "2026-07-21T00:00:00"
            headerPhrase = "إلى"; signatoryName = "المدير"; signatoryTitle = "المدير العام"
            subject = "ردّ اختباري على كتاب وارد"; bodyHtml = "<p>كتاب صادر أُنشئ آلياً لاختبار الربط.</p>"
            amount = $null; currency = $null; exchangeRate = $null; bodyJson = $null } $adminTok $cid
        if ($draft.Status -eq 200) { $approved = (Api POST "/outgoing/$($draft.Body.outgoingId)/approve" $null $adminTok $cid).Body }
    }
}
if ($approved) {
    $oid = $approved.outgoingId
    Ok "الصادر المعتمد: $($approved.number)"
    $target = (NewBook "كتاب وارد يُربط بصادر" $adminTok).Body
    $r = Api POST "/incoming/$($target.incomingId)/link/$oid" $null $adminTok $cid
    Expect "ربط الوارد بالصادر" $r.Status 200
    if ($r.Body.status -eq "Replied") { Ok "الربط نقل الحالة إلى (تم الرد)" } else { Bad "الحالة: $($r.Body.status)" }
    if ($r.Body.replyOutgoingNumber -eq $approved.number) { Ok "رقم الصادر المرتبط معبّأ: $($r.Body.replyOutgoingNumber)" } else { Bad "رقم الصادر المرتبط فارغ" }

    # الربط العكسي من جهة الصادر
    $o = (Api GET "/outgoing/$oid" $null $adminTok $cid).Body
    if ($o.replyToIncomingNumber -eq $target.incomingNumber) { Ok "الربط العكسي ظاهر في الصادر: $($o.replyToIncomingNumber)" } else { Bad "الربط العكسي مفقود في الصادر" }

    $other = (NewBook "كتاب وارد ثانٍ" $adminTok).Body
    Expect "رفض ربط نفس الصادر بوارد آخر" (Api POST "/incoming/$($other.incomingId)/link/$oid" $null $adminTok $cid).Status 409

    $r = Api DELETE "/incoming/$($target.incomingId)/link" $null $adminTok $cid
    Expect "فك الارتباط" $r.Status 200
    if ($r.Body.status -eq "InReview") { Ok "فك الارتباط أعاد الحالة إلى (قيد المراجعة)" } else { Bad "الحالة: $($r.Body.status)" }
    Expect "رفض فك ارتباط غير موجود" (Api DELETE "/incoming/$($target.incomingId)/link" $null $adminTok $cid).Status 400

    $closed = (NewBook "كتاب يُغلق ثم يُحاول ربطه" $adminTok).Body
    $null = ChangeStatus $closed.incomingId "Closed" "إغلاق مباشر"
    Expect "رفض ربط كتاب (مغلق)" (Api POST "/incoming/$($closed.incomingId)/link/$oid" $null $adminTok $cid).Status 400
} else {
    Skip "تعذّر تجهيز كتاب صادر معتمد — تخطّي اختبارات الربط"
}

# ─────────────────────────── 7) سجل الحركة والبحث ───────────────────────────
Section "7) سجل الحركة والبحث"
$mv = Api GET "/incoming/$bid/movements" $null $adminTok $cid
Expect "سجل الحركة متاح للسوبر أدمن" $mv.Status 200
if ($mv.Body.Count -ge 5) { Ok "عدد الحركات: $($mv.Body.Count) (تسجيل + تغييرات الحالة)" } else { Bad "عدد الحركات أقل من المتوقع: $($mv.Body.Count)" }
if ($mv.Body[0].action -eq "Registered") { Ok "حركة التسجيل مسجَّلة" } else { Bad "حركة التسجيل مفقودة — أول حركة: $($mv.Body[0].action)" }
if ($mv.Body[0].performedByUserName) { Ok "اسم منفّذ الحركة معبّأ: $($mv.Body[0].performedByUserName)" } else { Bad "اسم منفّذ الحركة فارغ" }

Expect "بحث بالحالة"                 (Api GET "/incoming?status=Archived" $null $adminTok $cid).Status 200
Expect "قيمة حالة غير صحيحة ← 400"    (Api GET "/incoming?status=NotAStatus" $null $adminTok $cid).Status 400
Expect "بحث بطريقة الاستلام"          (Api GET "/incoming?receiveMethod=0" $null $adminTok $cid).Status 200
Expect "بحث نصّي حر"                 (Api GET "/incoming?search=دورة" $null $adminTok $cid).Status 200

# ─────────────────────────── 8) المرفقات ───────────────────────────
Section "8) المرفقات"
$tmp = Join-Path $env:TEMP "dms-e2e-attachment.pdf"
[System.IO.File]::WriteAllBytes($tmp, [System.Text.Encoding]::ASCII.GetBytes("%PDF-1.4`n% اختبار مرفق`n%%EOF"))
$code = & curl.exe -s -o "$env:TEMP\att.json" -w "%{http_code}" -X POST "$BaseUrl/incoming/$($fresh.incomingId)/attachments" `
        -H "Authorization: Bearer $adminTok" -H "X-Company-Id: $cid" -F "file=@$tmp"
Expect "رفع مرفق PDF" ([int]$code) 200
$list = Api GET "/incoming/$($fresh.incomingId)/attachments" $null $adminTok $cid
Expect "قائمة المرفقات" $list.Status 200
if ($list.Body.Count -ge 1) {
    Ok "عدد المرفقات: $($list.Body.Count)"
    Expect "حذف المرفق" (Api DELETE "/incoming/$($fresh.incomingId)/attachments/$($list.Body[0].attachmentId)" $null $adminTok $cid).Status 204
} else { Bad "لم يُسجَّل المرفق" }

# ─────────────────────────── 9) صلاحيات الموظف ───────────────────────────
Section "9) صلاحيات الموظف"
if ($EmployeeUser -and $EmployeePwd) {
    $users = (Api GET "/users" $null $adminTok $cid).Body
    $emp = $users | Where-Object { $_.username -eq $EmployeeUser } | Select-Object -First 1
    if ($emp) {
        $mods = @($emp.modules)
        if ($mods -notcontains "Incoming") {
            Expect "منح $EmployeeUser صلاحية الوارد" (Api PUT "/users/$($emp.userId)" @{
                fullName = $emp.fullName; role = $emp.role; companyIds = $emp.companyIds
                isActive = $true; canApprove = $emp.canApprove; modules = ($mods + "Incoming") } $adminTok $cid).Status 200
        } else { Ok "$EmployeeUser يملك صلاحية الوارد" }

        $sLogin = Api POST "/auth/login" @{ username = $EmployeeUser; password = $EmployeePwd } $null $null
        if ($sLogin.Status -eq 200) {
            $sTok = $sLogin.Body.accessToken
            Ok "دخول $EmployeeUser — الدور: $($sLogin.Body.role)"
            $sBook = NewBook "كتاب أنشأه الموظف" $sTok
            Expect "الموظف يسجّل كتاباً وارداً" $sBook.Status 200
            $sid = $sBook.Body.incomingId
            Expect "الموظف: جديد ← قيد المراجعة (مسموح)" (Api POST "/incoming/$sid/status" @{ status = "InReview"; note = $null } $sTok $cid).Status 200
            Expect "رفض: الموظف يغلق كتاباً"            (Api POST "/incoming/$sid/status" @{ status = "Closed"; note = "إغلاق" } $sTok $cid).Status 403
            Expect "رفض: الموظف يضع (تم الرد)"          (Api POST "/incoming/$sid/status" @{ status = "Replied"; note = "رد" } $sTok $cid).Status 403
            if ($approved) {
                Expect "رفض: الموظف يربط بصادر (منع الالتفاف)" (Api POST "/incoming/$sid/link/$($approved.outgoingId)" $null $sTok $cid).Status 403
                Expect "رفض: الموظف يفك ارتباطاً"              (Api DELETE "/incoming/$sid/link" $null $sTok $cid).Status 403
            }
            Expect "رفض: سجل الحركة محجوب عن الموظف" (Api GET "/incoming/$sid/movements" $null $sTok $cid).Status 403
            Expect "رفض: الموظف لا يرى كتاب غيره"     (Api GET "/incoming/$bid" $null $sTok $cid).Status 404
        } else { Bad "تعذّر الدخول بـ $EmployeeUser : $($sLogin.Status)" }
    } else { Bad "المستخدم $EmployeeUser غير موجود" }
} else {
    Skip "لم تُمرَّر بيانات موظف (-EmployeeUser / -EmployeePwd) — تخطّي اختبارات الصلاحيات"
}

# ─────────────────────────── النتيجة ───────────────────────────
Write-Host "`n================ النتيجة ================" -ForegroundColor Cyan
Write-Host "  نجح: $script:pass" -ForegroundColor Green
Write-Host "  فشل: $script:fail" -ForegroundColor $(if ($script:fail -gt 0) { "Red" } else { "Green" })
if ($script:fail -eq 0) { Write-Host "  دورة الوارد سليمة بالكامل" -ForegroundColor Green }
exit $(if ($script:fail -gt 0) { 1 } else { 0 })
