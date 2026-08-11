param(
    [Parameter(Mandatory=$true)][string]$AdminPwd,
    [string]$AdminUser = "admin",
    [string]$EmployeeUser = "",
    [string]$EmployeePwd = "",
    [string]$Base = "http://localhost:5080/api"
)
# ════════════════════════════════════════════════════════════════════════════════════════
#  اختبار التدفق الشامل (E2E) لوحدة التقارير — يعمل على API حيّ.
#
#  يغطّي: التقرير المالي (القائم) · **تقرير النشاط** (جديد) · **التقارير التفصيلية** للصادر
#  والأرشيف · ومخرجاتها PDF/Excel · و🔐 **الحارس المزدوج**: قسم التقارير لا يكفي لقراءة
#  سجلّ التدقيق، فالنشاط لرئيس الشركة فأعلى (نظير `AuditController`).
#
#  ⚠️ **يقرأ ولا يكتب** — لا يُنشئ بيانات ولا يحذف. آمنٌ على قاعدة العمل، بخلاف بقية
#     السكربتات. (عدا تسجيل الدخول نفسه الذي يُسجَّل في سجل التدقيق بطبيعته.)
#  ⚠️ ملفات PowerShell بالعربية تحتاج ترميز UTF-8 with BOM وإلا فشل التحليل في PS 5.1.
#  ⚠️ **المطابقة بالمعرّفات لا بالنصّ العربي** — PS 5.1 يشوّه العربية العائدة من الـAPI
#     فتفشل المطابقة صامتةً (درس مسجَّل في hr-e2e.ps1).
# ════════════════════════════════════════════════════════════════════════════════════════
$ErrorActionPreference = "Stop"
$script:pass = 0
$script:fail = 0

function Ok($m)   { $script:pass++; Write-Host "  [نجح]  $m" -ForegroundColor Green }
function Bad($m)  { $script:fail++; Write-Host "  [فشل]  $m" -ForegroundColor Red }
function Skip($m) { Write-Host "  [تخطّي] $m" -ForegroundColor Yellow }
function Section($t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }
function Expect($label, $actual, $expected) {
    if ("$actual" -eq "$expected") { Ok "$label" } else { Bad "$label — متوقع $expected لكن جاء $actual" }
}

function Api($method, $url, $body, $token, $companyId) {
    $h = @{}
    if ($token)     { $h["Authorization"] = "Bearer $token" }
    if ($companyId) { $h["X-Company-Id"]  = "$companyId" }
    $p = @{ Uri = "$Base$url"; Method = $method; Headers = $h; ContentType = "application/json; charset=utf-8" }
    if ($null -ne $body) { $p.Body = [Text.Encoding]::UTF8.GetBytes(($body | ConvertTo-Json -Depth 8 -Compress)) }
    try {
        $r = Invoke-WebRequest @p -UseBasicParsing
        $j = $null; if ($r.Content) { try { $j = $r.Content | ConvertFrom-Json } catch {} }
        return @{ Status = [int]$r.StatusCode; Body = $j }
    } catch {
        $resp = $_.Exception.Response
        $code = if ($resp) { [int]$resp.StatusCode } else { 0 }
        return @{ Status = $code; Body = $null }
    }
}

# تنزيل ملف والتحقق من بصمته الحقيقية (لا من حجمه وحده — ملفٌ فارغ سليم الحجم يخدع).
function FileCheck($label, $url, $token, $companyId, $magic) {
    $tmp = [IO.Path]::GetTempFileName()
    try {
        $h = @{ Authorization = "Bearer $token" }
        if ($companyId) { $h["X-Company-Id"] = "$companyId" }
        Invoke-WebRequest -Uri "$Base$url" -Headers $h -OutFile $tmp -UseBasicParsing | Out-Null
        $bytes = [IO.File]::ReadAllBytes($tmp)
        $head  = [Text.Encoding]::ASCII.GetString($bytes[0..($magic.Length - 1)])
        if ($bytes.Length -gt 800 -and $head -eq $magic) { Ok "$label ($([Math]::Round($bytes.Length / 1024, 1)) ك.ب، بصمة $magic)" }
        else { Bad "$label — الحجم $($bytes.Length) والبصمة '$head' (المتوقّع '$magic')" }
    } catch { Bad "$label — تعذّر التنزيل: $($_.Exception.Message)" }
    finally { if (Test-Path $tmp) { Remove-Item $tmp -Force } }
}

# ───────────────────────────── الإعداد ─────────────────────────────
Section "الإعداد — دخول الأدمن"
$adminTok = (Api POST "/auth/login" @{ username = $AdminUser; password = $AdminPwd } $null $null).Body.accessToken
if (-not $adminTok) { Bad "فشل دخول $AdminUser"; exit 1 }
Ok "دخول $AdminUser"

$cid = ((Api GET "/companies" $null $adminTok $null).Body | Select-Object -First 1).companyId
if (-not $cid) { Bad "لا شركة في النظام"; exit 1 }
Ok "الشركة الفعّالة: $cid"

# ───────────────────────────── 1) التقرير المالي (انحدار) ─────────────────────────────
Section "1) التقرير المالي — حارس انحدار"
$fin = Api GET "/reports/financial?source=All" $null $adminTok $cid
Expect "التقرير المالي يستجيب" $fin.Status 200
if ($fin.Status -eq 200) {
    $rowsCount = @($fin.Body.rows).Count
    if ($fin.Body.count -eq $rowsCount) { Ok "عدد السطور يطابق الحقل count ($rowsCount)" }
    else { Bad "count=$($fin.Body.count) وعدد السطور=$rowsCount" }
}

# ───────────────────────────── 2) تقرير النشاط ─────────────────────────────
Section "2) تقرير النشاط — من سجل التدقيق"
$act = Api GET "/reports/activity?take=50" $null $adminTok $cid
Expect "تقرير النشاط يستجيب" $act.Status 200

if ($act.Status -eq 200) {
    $rows = @($act.Body.rows)
    if ($rows.Count -gt 0) { Ok "سطور النشاط: $($rows.Count)" } else { Bad "لا سطور نشاط إطلاقاً" }

    # العدد الكلّي قبل القصّ — «رأيتَ 50 من 12,340» معلومة، و«رأيتَ 50» تضليل.
    if ($act.Body.totalCount -ge $rows.Count) { Ok "الإجمالي قبل القصّ ($($act.Body.totalCount)) ≥ المعروض ($($rows.Count))" }
    else { Bad "totalCount=$($act.Body.totalCount) أصغر من المعروض $($rows.Count)" }

    if (@($act.Body.byAction).Count -gt 0) { Ok "تجميع بالفعل: $(@($act.Body.byAction).Count) صنفاً" } else { Bad "تجميع الأفعال فارغ" }
    if (@($act.Body.byUser).Count  -gt 0) { Ok "تجميع بالمستخدم: $(@($act.Body.byUser).Count) مستخدماً" } else { Bad "تجميع المستخدمين فارغ" }

    # 🔴 الترجمة تصل فعلاً: نطابق **بطول النصّ واختلافه عن المفتاح** لا بالنصّ العربي نفسه.
    $login = @($rows | Where-Object { $_.action -eq "Login" } | Select-Object -First 1)
    if ($login.Count -eq 1) {
        Ok "سطر تسجيل دخول موجود (الفعل الخام يصل للفلترة)"
        if ($login[0].actionLabel -and $login[0].actionLabel -ne $login[0].action) { Ok "وترجمته العربية تصل ومختلفة عن المفتاح" }
        else { Bad "actionLabel فارغة أو مطابقة للمفتاح — الترجمة لم تصل" }
        if ($login[0].userName -and $login[0].userName -ne "—") { Ok "واسم المنفّذ معبّأ لا شرطة" }
        else { Bad "userName فارغ — الاسم لم يُوصَل" }
    } else { Bad "لا سطر Login رغم أننا سجّلنا دخولاً قبل قليل" }
}

Section "3) فلاتر النشاط"
$byAction = Api GET "/reports/activity?action=Login&take=20" $null $adminTok $cid
Expect "الفلترة بالفعل تستجيب" $byAction.Status 200
if ($byAction.Status -eq 200) {
    $others = @(@($byAction.Body.rows) | Where-Object { $_.action -ne "Login" })
    Expect "كل السطور المُعادة Login فقط" $others.Count 0
}

$capped = Api GET "/reports/activity?take=3" $null $adminTok $cid
if ($capped.Status -eq 200) {
    if (@($capped.Body.rows).Count -le 3) { Ok "take=3 يقصّ السطور فعلاً" } else { Bad "take=3 وعاد $(@($capped.Body.rows).Count)" }
    # 🔴 والقصّ لا يمسّ الإجمالي ولا التجميع — وإلا صار الملخّص يصف الصفحة الأولى.
    if ($capped.Body.totalCount -eq $act.Body.totalCount) { Ok "والقصّ لا يغيّر الإجمالي (التجميع على كامل النطاق)" }
    else { Bad "الإجمالي تغيّر بتغيّر take: $($capped.Body.totalCount) مقابل $($act.Body.totalCount)" }
}

# 🔴 **حارس الفاعل في أحداث المصادقة** — كشفه أول تشغيل: 188 سطر دخول بـUserId=null،
#    لأن المستخدم غير مصادَقٍ لحظة كتابة السجلّ، فالفاعل في EntityId. والثبات المطلوب:
#    **ما يُعرض باسم فلان يجب أن يظهر حين يُفلتَر بفلان** — وإلا فقد التقريرُ ثقتَه.
$loginRow = @(@($act.Body.rows) | Where-Object { $_.action -eq "Login" -and $_.userId } | Select-Object -First 1)
if ($loginRow.Count -eq 1) {
    $uid = $loginRow[0].userId
    Ok "سطر الدخول يحمل فاعلاً (userId=$uid) لا فراغاً"
    $byUser = Api GET "/reports/activity?userId=$uid&action=Login&take=20" $null $adminTok $cid
    Expect "الفلترة بذلك المستخدم تستجيب" $byUser.Status 200
    if ($byUser.Status -eq 200) {
        $got = @($byUser.Body.rows)
        if ($got.Count -gt 0) { Ok "وتُعيد أحداث دخوله ($($got.Count)) — الفلتر يتبع قاعدة العرض" }
        else { Bad "عُرض سطرٌ باسمه ثم اختفى عند الفلترة به — تناقض العرض والفلترة" }
        $alien = @($got | Where-Object { $_.userId -ne $uid })
        Expect "ولا تُسرّب أحداث غيره" $alien.Count 0
    }
} else { Bad "لا سطر دخول بفاعلٍ معبّأ — إصلاح الفاعل لم يصل" }

$future = (Get-Date).AddYears(5).ToString("yyyy-MM-dd")
$empty = Api GET "/reports/activity?from=$future" $null $adminTok $cid
if ($empty.Status -eq 200) { Expect "فترة مستقبلية ⇒ صفر سطر (الفلتر الزمني يعمل)" @($empty.Body.rows).Count 0 }

Section "4) مفردات السجلّ (لملء الفلاتر)"
$vocab = Api GET "/reports/activity/vocabulary" $null $adminTok $cid
Expect "المفردات تستجيب" $vocab.Status 200
if ($vocab.Status -eq 200) {
    $acts = @($vocab.Body.actions); $ents = @($vocab.Body.entities)
    if ($acts.Count -ge 40) { Ok "الأفعال: $($acts.Count)" } else { Bad "الأفعال $($acts.Count) — أقلّ من المتوقّع (≥40)" }
    if ($ents.Count -ge 20) { Ok "الأنواع: $($ents.Count)" } else { Bad "الأنواع $($ents.Count) — أقلّ من المتوقّع (≥20)" }
    $blank = @($acts | Where-Object { -not $_.label -or $_.label -eq $_.value })
    Expect "لا فعل بلا ترجمة عربية" $blank.Count 0
    # المفردات من AuditLabels لا من DISTINCT على السجلّ: فعلٌ لم يقع بعد يجب أن يظهر.
    $rare = @($acts | Where-Object { $_.value -eq "RestoreMirror" })
    Expect "فعلٌ نادر (RestoreMirror) موجود ولو لم يقع قطّ" $rare.Count 1
}

Section "5) مخرجات النشاط"
FileCheck "تقرير النشاط PDF" "/reports/activity/pdf?take=50" $adminTok $cid "%PDF"
FileCheck "تقرير النشاط Excel" "/reports/activity/excel?take=50" $adminTok $cid "PK"

# ───────────────────────────── 6) الصادر التفصيلي ─────────────────────────────
Section "6) التقرير التفصيلي للصادر"
$od = Api GET "/reports/outgoing-detail" $null $adminTok $cid
Expect "الصادر التفصيلي يستجيب" $od.Status 200
if ($od.Status -eq 200) {
    $rows = @($od.Body.rows)
    Expect "عدد السطور يطابق count" $rows.Count $od.Body.count
    Expect "مسودّات + معتمدة = الكل" ($od.Body.drafts + $od.Body.approved) $od.Body.count

    # ⚠️ **الحالة تصل نصّاً لا رقماً** (`"Final"`/`"Draft"`) — الـAPI يسلسل الـenums بأسمائها.
    #    والمطابقة الرقمية (`-eq 1`) **تكذب صامتةً**: تُرجع صفراً فيبدو أن المسودّات تسرّبت
    #    إلى المجموع والمنتجُ سليم. (كذبت في أول تشغيل فعلاً — 2026-08-11.)
    $isFinal = { param($r) "$($r.status)" -eq "Final" }

    # 🔴 **حارس ADR-029 مباشرةً**: الإجمالي **للمعتمد وحده**. نحسبه من السطور العائدة
    #    ونطابقه — فلو دخلت مسودّةٌ في المجموع لانكشف الفرق فوراً.
    $sumFinal = 0.0
    foreach ($r in $rows) { if ((& $isFinal $r) -and $r.amountInIqd) { $sumFinal += [double]$r.amountInIqd } }
    $reported = [double]$od.Body.approvedTotalIqd
    if ([Math]::Abs($sumFinal - $reported) -lt 0.01) { Ok "الإجمالي = مجموع المعتمد وحده ($reported)" }
    else { Bad "الإجمالي $reported ومجموع المعتمد المحسوب $sumFinal — المسودّات تسرّبت إلى المجموع" }

    # ومسودّةٌ لها مبلغ لا تدخل المجموع — نُثبت وجود الحالة لا نفترضها.
    $draftWithAmount = @($rows | Where-Object { "$($_.status)" -eq "Draft" -and $_.amountInIqd })
    if ($draftWithAmount.Count -gt 0) { Ok "توجد مسودّة بمبلغ ($($draftWithAmount.Count)) — والمجموع لم يشملها" }
    else { Skip "لا مسودّة بمبلغ في البيانات — حارس التسرّب لم يُفعَّل هذه المرّة" }
}

$odDraft = Api GET "/reports/outgoing-detail?status=Draft" $null $adminTok $cid
if ($odDraft.Status -eq 200) {
    $draftRows = @($odDraft.Body.rows)
    if ($draftRows.Count -eq 0) {
        # تحقّقٌ فارغ يمرّ دائماً ولا يقول شيئاً — نُعلنه تخطّياً بدل أن نعدّه نجاحاً.
        Skip "لا مسودّات في هذه الشركة — فلتر الحالة بلا مادّة يختبرها"
    } else {
        $notDraft = @($draftRows | Where-Object { "$($_.status)" -ne "Draft" })
        Expect "فلتر الحالة: مسودّات فقط ($($draftRows.Count) سطراً)" $notDraft.Count 0
    }
    Expect "وإجمالي المعتمد في نتيجة المسودّات صفر" ([double]$odDraft.Body.approvedTotalIqd) 0
}

$odFinal = Api GET "/reports/outgoing-detail?status=Final" $null $adminTok $cid
if ($odFinal.Status -eq 200) {
    $notFinal = @(@($odFinal.Body.rows) | Where-Object { "$($_.status)" -ne "Final" })
    Expect "فلتر الحالة: معتمدة فقط" $notFinal.Count 0
    Expect "وعدد مسودّاتها صفر" $odFinal.Body.drafts 0
}

FileCheck "الصادر التفصيلي PDF" "/reports/outgoing-detail/pdf" $adminTok $cid "%PDF"
FileCheck "الصادر التفصيلي Excel" "/reports/outgoing-detail/excel" $adminTok $cid "PK"

# ───────────────────────────── 7) الأرشيف التفصيلي ─────────────────────────────
Section "7) التقرير التفصيلي للأرشيف — من العدسة نفسها"
$ad = Api GET "/reports/archive-detail" $null $adminTok $cid
Expect "الأرشيف التفصيلي يستجيب" $ad.Status 200
if ($ad.Status -eq 200) {
    Expect "وارد + أضابير = الكل" ($ad.Body.incomingCount + $ad.Body.paperCount) $ad.Body.count

    # 🔴 **الحارس الجوهري**: التقرير يجمع **عين ما تعرضه الشاشة**. لو نُسخت قاعدة العدسة
    #    بدل استدعائها لتباعد الرقمان عند أول تعديل — وهو عطل ADR-030 حرفياً.
    $lens = Api GET "/archive/lens" $null $adminTok $cid
    if ($lens.Status -eq 200) {
        Expect "عدد التقرير = عدد عدسة الشاشة" $ad.Body.count @($lens.Body).Count
    } else { Skip "العدسة لم تستجب ($($lens.Status)) — تعذّرت المطابقة" }

    # والوارد المؤرشف بلا مبلغ (أُلغي من الحساب المالي 2026-07-25) — لا يُضخّم الإجمالي.
    $incomingWithAmount = @(@($ad.Body.rows) | Where-Object { $_.isIncoming -and $_.amountInIqd })
    Expect "لا مبلغ على صفوف الوارد المؤرشف" $incomingWithAmount.Count 0
}

$adPaper = Api GET "/reports/archive-detail?source=Paper" $null $adminTok $cid
if ($adPaper.Status -eq 200) { Expect "مِرشَّح المصدر: أضابير فقط (صفر وارد)" $adPaper.Body.incomingCount 0 }

FileCheck "الأرشيف التفصيلي PDF" "/reports/archive-detail/pdf" $adminTok $cid "%PDF"
FileCheck "الأرشيف التفصيلي Excel" "/reports/archive-detail/excel" $adminTok $cid "PK"

# ───────────────────────────── 8) 🔐 الحارس المزدوج ─────────────────────────────
Section "8) 🔐 الحارس المزدوج — قسم التقارير لا يفتح سجلّ التدقيق"
if ($EmployeeUser -and $EmployeePwd) {
    $empTok = (Api POST "/auth/login" @{ username = $EmployeeUser; password = $EmployeePwd } $null $null).Body.accessToken
    if ($empTok) {
        Ok "دخول $EmployeeUser"

        # الشرط الذي يجعل الاختبار ذا معنى: الموظف **يملك قسم التقارير فعلاً**.
        $finEmp = Api GET "/reports/financial?source=Outgoing" $null $empTok $cid
        if ($finEmp.Status -eq 200) {
            Ok "الموظف يملك قسم التقارير (المالي يستجيب له 200)"

            Expect "🔐 ومع ذلك يُمنع من تقرير النشاط (403)" (Api GET "/reports/activity" $null $empTok $cid).Status 403
            Expect "🔐 ومن مخرجه PDF (403)"   (Api GET "/reports/activity/pdf" $null $empTok $cid).Status 403
            Expect "🔐 ومن مخرجه Excel (403)"  (Api GET "/reports/activity/excel" $null $empTok $cid).Status 403
            Expect "🔐 ومن المفردات (403)"     (Api GET "/reports/activity/vocabulary" $null $empTok $cid).Status 403
            Expect "🔐 وسجل التدقيق الخام محجوب عنه أيضاً (403)" (Api GET "/audit?take=5" $null $empTok $cid).Status 403

            # ── والحدّ المزدوج بالقسم في التقارير التفصيلية ──
            # ⚠️ **التوقّعات تتبع أقسام الموظف الفعلية لا افتراضاً ثابتاً** (درس incoming-e2e):
            #    نقرأ أقسامه من الـAPI ثم نطالب بالسلوك المطابق لها.
            $u = (Api GET "/users" $null $adminTok $cid).Body | Where-Object { $_.username -eq $EmployeeUser }
            $mods = @(($u.companies | Where-Object { $_.companyId -eq $cid }).modules)
            Ok "أقسام $($EmployeeUser): $($mods -join ',')"

            $expOut = if ($mods -contains "Outgoing") { 200 } else { 403 }
            Expect "🔐 الصادر التفصيلي يتبع قسم الصادر (المتوقّع $expOut)" (Api GET "/reports/outgoing-detail" $null $empTok $cid).Status $expOut

            $expArc = if ($mods -contains "Archive") { 200 } else { 403 }
            Expect "🔐 الأرشيف التفصيلي يتبع قسم الأرشيف (المتوقّع $expArc)" (Api GET "/reports/archive-detail" $null $empTok $cid).Status $expArc

            # 🔴 والدليل أن الحدّ **مزدوج فعلاً**: التقرير المالي يمرّ بقسم التقارير وحده،
            #    فلو كان الحارس واحداً لمرّ التفصيليان معه.
            if ($expOut -eq 403 -or $expArc -eq 403) { Ok "🔐 وقسم التقارير وحده لا يفتح التفصيليين — الحدّ مزدوج فعلاً" }
            else { Skip "الموظف يملك القسمين — لا يمكن إثبات ازدواج الحدّ بهذا الحساب" }
        } else {
            Skip "الموظف بلا قسم التقارير (رد $($finEmp.Status)) — حارس النشاط بلا معنى بدونه"
        }
    } else { Bad "فشل دخول $EmployeeUser" }
} else {
    Skip "لم يُمرَّر موظف اختبار — تخطّي حرّاس الصلاحية (مرّر -EmployeeUser و -EmployeePwd)"
}

# ───────────────────────────── النتيجة ─────────────────────────────
Write-Host "`n================ النتيجة ================" -ForegroundColor Cyan
Write-Host "  نجح: $script:pass" -ForegroundColor Green
Write-Host "  فشل: $script:fail" -ForegroundColor $(if ($script:fail -eq 0) { "Green" } else { "Red" })
if ($script:fail -eq 0) { Write-Host "  وحدة التقارير سليمة." -ForegroundColor Green; exit 0 } else { exit 1 }
