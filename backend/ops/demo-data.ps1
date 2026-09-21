#requires -Version 5.1
# ══════════════════════════════════════════════════════════════════════════════
#  بذرُ بياناتٍ تجريبية واقعية — دورةٌ كاملة يراها المالك في الشاشات
#
#  الاستعمال:
#      powershell -File backend\ops\demo-data.ps1 -AdminPwd <كلمة-المرور>
#      powershell -File backend\ops\demo-data.ps1 -AdminPwd <..> -CompanyId 1
#
#  ما يُنشئه في كل شركة:
#      الصادر  : 5 كتب — 3 معتمدة بأرقام رسمية وPDF وختم QR · 2 مسودّة
#      الوارد  : 6 كتب — جديد · قيد المراجعة بإحالة · تم الرد بربط · مغلق
#      المعاملة: صادرٌ واحد يجيب واردَين ⇒ خيطٌ يجمع الثلاثة (ADR-045)
#      الأرشيف : واردان مؤرشفان + 3 أضابير ورقية
#      المهام  : 5 مهام بأولويات وحالات ونسب إنجاز ومشاركين
#
#  🔴 **إضافةٌ محضة — لا يحذف شيئاً ولا يعدّل بياناتٍ قائمة.** وقابلٌ لإعادة التشغيل:
#     كل تشغيلٍ يُضيف دفعةً جديدة بوسمٍ زمنيّ، فلا يتعارض مع سابقتها.
#
#  ⚠️ **يعمل على القاعدة التي يشير إليها الخادم.** خذ نسخةً احتياطية قبله إن كانت
#     قاعدةَ عمل — النظام يوفّرها من: الإعدادات ← النسخ الاحتياطي ← «نسخة الآن».
# ══════════════════════════════════════════════════════════════════════════════

param(
    [Parameter(Mandatory = $true)][string]$AdminPwd,
    [string]$Base = 'http://localhost:5080/api',
    [string]$AdminUser = 'admin',
    [int]$CompanyId = 0          # 0 = كل الشركات النشِطة
)

$ErrorActionPreference = 'Stop'
$script:made = @{}

function Say($m, $c = 'Gray') { Write-Host "  $m" -ForegroundColor $c }
function Head($m) { Write-Host "`n$m" -ForegroundColor Cyan }
function Good($m) { Write-Host "  [تم] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  [تنبيه] $m" -ForegroundColor Yellow }
function Fail($m) { Write-Host "  [فشل] $m" -ForegroundColor Red }
function Note($k, $v) { $script:made[$k] = $v }

function Api($method, $path, $body, $token, $cid) {
    $h = @{}
    if ($token) { $h.Authorization = "Bearer $token" }
    if ($cid) { $h."X-Company-Id" = "$cid" }
    $p = @{ Uri = "$Base$path"; Method = $method; Headers = $h; ContentType = 'application/json; charset=utf-8' }
    if ($null -ne $body) { $p.Body = [Text.Encoding]::UTF8.GetBytes(($body | ConvertTo-Json -Depth 8 -Compress)) }
    try {
        $r = Invoke-WebRequest @p -UseBasicParsing
        $j = $null
        if ($r.Content) { try { $j = $r.Content | ConvertFrom-Json } catch { } }
        return @{ S = [int]$r.StatusCode; B = $j }
    }
    catch {
        $resp = $_.Exception.Response
        $code = 0; $txt = ''
        if ($resp) {
            $code = [int]$resp.StatusCode
            try { $sr = [IO.StreamReader]::new($resp.GetResponseStream()); $txt = $sr.ReadToEnd() } catch { }
        }
        $j = $null
        if ($txt) { try { $j = $txt | ConvertFrom-Json } catch { } }
        return @{ S = $code; B = $j; Raw = $txt }
    }
}

# ═════════════════════════════ الدخول ═════════════════════════════
Head "الدخول"
$login = Api POST "/auth/login" @{ username = $AdminUser; password = $AdminPwd } $null $null
if ($login.S -ne 200 -or -not $login.B.accessToken) {
    Fail "تعذّر الدخول ($($login.S)). تحقّق من اسم المستخدم وكلمة المرور."
    exit 1
}
$tok = $login.B.accessToken
Good "دخل $AdminUser"

$companies = @((Api GET "/companies" $null $tok $null).B)
if ($CompanyId -gt 0) { $companies = @($companies | Where-Object { [int]$_.companyId -eq $CompanyId }) }
if ($companies.Count -eq 0) { Fail "لا شركات نشِطة."; exit 1 }
Good "الشركات المستهدَفة: $($companies.Count)"

# وسمٌ زمنيّ يميّز دفعة هذا التشغيل — فإعادةُ التشغيل لا تلتبس بسابقتها
$tag = Get-Date -Format 'MMdd-HHmm'
$today = Get-Date

foreach ($co in $companies) {
    $cid = [int]$co.companyId
    Head "══════ [$($co.name)] ($($co.prefix)) ══════"

    # ── ما تحتاجه الكتب: جهة · قالب · أقسام ─────────────────────────
    $entities = @((Api GET "/entities" $null $tok $cid).B)
    if ($entities.Count -lt 2) {
        foreach ($n in @("وزارة الإعمار والإسكان", "مديرية بلدية بغداد", "شركة الفرات للمقاولات")) {
            if (-not ($entities | Where-Object { $_.name -eq $n })) {
                $null = Api POST "/entities" @{ name = $n; kind = 'Both'; isActive = $true } $tok $cid
            }
        }
        $entities = @((Api GET "/entities" $null $tok $cid).B)
    }
    $ent = $entities[0].entityId
    $ent2 = if ($entities.Count -gt 1) { $entities[1].entityId } else { $ent }
    Good "جهات: $($entities.Count)"

    $templates = @((Api GET "/templates" $null $tok $cid).B)
    if ($templates.Count -eq 0) {
        $t = Api POST "/templates" @{
            companyId = $cid; name = "قالب $($co.prefix)"; watermarkOpacity = 10
            marginTop = 20; marginRight = 20; marginBottom = 20; marginLeft = 20
            pageSize = 'A4'; fontFamily = 'Amiri'; isActive = $true
        } $tok $cid
        if ($t.S -ne 200) { Fail "تعذّر إنشاء قالب: $($t.S)"; continue }
        $templates = @((Api GET "/templates" $null $tok $cid).B)
    }
    $tpl = $templates[0].templateId
    Good "قالب: $($templates[0].name)"

    $depts = @((Api GET "/departments" $null $tok $cid).B)
    if ($depts.Count -eq 0) {
        foreach ($n in @("المالية", "القانونية", "الإدارة")) {
            $null = Api POST "/departments" @{ companyId = $cid; name = $n; isActive = $true } $tok $cid
        }
        $depts = @((Api GET "/departments" $null $tok $cid).B)
    }
    $dept = $depts[0].departmentId
    $dept2 = if ($depts.Count -gt 1) { $depts[1].departmentId } else { $dept }
    Good "أقسام: $($depts.Count)"

    # ═══════════════════════ ١) الصادر ═══════════════════════
    Head "١) الصادر — 3 معتمدة و2 مسودّة"
    $outSubjects = @(
        "طلب تخصيص مبلغ لمشروع تأهيل الطريق",
        "إجابة على استفسار بشأن كشف الكميات",
        "تسمية ممثل الشركة في لجنة الاستلام",
        "مسودّة: عرض فنّي أوّليّ (لم تُعتمد)",
        "مسودّة: طلب تمديد مدّة التنفيذ (لم تُعتمد)"
    )
    $outIds = @(); $outNums = @()
    for ($i = 0; $i -lt $outSubjects.Count; $i++) {
        $body = @{
            companyId  = $cid; entityId = $(if ($i % 2 -eq 0) { $ent } else { $ent2 }); templateId = $tpl
            date       = $today.AddDays(-($outSubjects.Count - $i)).ToString('yyyy-MM-dd')
            subject    = "$($outSubjects[$i]) [$tag]"
            bodyHtml   = "<p>يرجى التفضّل بالاطّلاع على ما يخصّ <b>$($outSubjects[$i])</b>، مع التقدير.</p>"
            headerPhrase = "م/ $($outSubjects[$i])"
        }
        if ($i -eq 0) { $body.amount = 125000000; $body.currency = 'IQD' }
        if ($i -eq 1) { $body.amount = 48750; $body.currency = 'USD'; $body.exchangeRate = 1320 }

        $r = Api POST "/outgoing" $body $tok $cid
        if ($r.S -ne 200) { Fail "صادر #$($i+1): $($r.S) $($r.B.message)"; continue }
        $id = [int]$r.B.outgoingId
        $outIds += $id

        if ($i -lt 3) {
            $ap = Api POST "/outgoing/$id/approve" $null $tok $cid
            if ($ap.S -eq 200) {
                $num = (Api GET "/outgoing/$id" $null $tok $cid).B.number
                $outNums += $num
                Say "معتمد: $num — $($outSubjects[$i])" 'Green'
            }
            else { Warn "تعذّر اعتماد صادر $id ($($ap.S))" }
        }
        else { Say "مسودّة: #$id — $($outSubjects[$i])" }
    }
    Note "صادر [$($co.name)]" "$($outIds.Count) كتب · معتمدة: $($outNums -join ' · ')"

    # ═══════════════════════ ٢) الوارد ═══════════════════════
    Head "٢) الوارد — 6 كتب بحالاتٍ مختلفة"
    $inSubjects = @(
        "كتاب تخويل بتسلّم الموقع",
        "استفسار عن جدول التقدّم الشهري",
        "طلب مستمسكات الكادر الهندسي",
        "إشعار بموعد لجنة الاستلام الأوّلي",
        "تنبيه بشأن مواصفات المواد المجهّزة",
        "كتاب شكر وتقدير"
    )
    $inIds = @()
    for ($i = 0; $i -lt $inSubjects.Count; $i++) {
        $d = $today.AddDays(-($inSubjects.Count - $i) * 2)
        $r = Api POST "/incoming" @{
            companyId      = $cid
            externalNumber = "$($co.prefix)/$tag/$($i + 1)"
            externalDate   = $d.ToString('yyyy-MM-ddT00:00:00')
            receivedDate   = $d.AddDays(1).ToString('yyyy-MM-ddT00:00:00')
            receivedTime   = '09:30:00'
            entityId       = $(if ($i % 2 -eq 0) { $ent } else { $ent2 })
            subject        = "$($inSubjects[$i]) [$tag]"
            documentTypeId = $null
            receiveMethod  = @('Manual', 'Mail', 'Email')[$i % 3]
            keywords       = 'تجريبي'
            notes          = $null
            amount         = $null; currency = $null; exchangeRate = $null
        } $tok $cid
        if ($r.S -ne 200) { Fail "وارد #$($i+1): $($r.S) $($r.B.message)"; continue }
        $id = [int]$r.B.incomingId
        $inIds += $id
        Say "وارد: $($r.B.incomingNumber) — $($inSubjects[$i])"
    }

    # إحالة اثنين إلى قسمين ⇒ «قيد المراجعة»
    if ($inIds.Count -ge 2) {
        $f1 = Api POST "/incoming/$($inIds[0])/forward" @{ departments = @(@{ departmentId = $dept; note = "للدراسة وإبداء الرأي" }) } $tok $cid
        $f2 = Api POST "/incoming/$($inIds[1])/forward" @{ departments = @(
                @{ departmentId = $dept; note = "للتدقيق المالي" },
                @{ departmentId = $dept2; note = "للرأي القانوني" }) } $tok $cid
        if ($f1.S -lt 300) { Good "أُحيل الأول إلى قسمٍ واحد" }
        if ($f2.S -lt 300) { Good "وأُحيل الثاني إلى **قسمين معاً** (إحالة تراكمية — ADR-018)" }
    }

    # إغلاق كتابٍ لا يحتاج إجراء
    if ($inIds.Count -ge 6) {
        $cl = Api POST "/incoming/$($inIds[5])/status" @{ status = 'Closed'; note = "لا يحتاج إجراءً — كتاب شكر" } $tok $cid
        if ($cl.S -lt 300) { Good "أُغلق كتاب الشكر" }
    }
    Note "وارد [$($co.name)]" "$($inIds.Count) كتب — منها 2 محالة و1 مغلق"

    # ═══════════════ ٣) الربط والمعاملة (ADR-045) ═══════════════
    Head "٣) المعاملة — صادرٌ واحد يجيب واردَين"
    if ($outIds.Count -ge 2 -and $inIds.Count -ge 3) {
        $l1 = Api POST "/incoming/$($inIds[1])/link/$($outIds[1])" $null $tok $cid
        $l2 = Api POST "/incoming/$($inIds[2])/link/$($outIds[1])" $null $tok $cid
        if ($l1.S -lt 300 -and $l2.S -lt 300) {
            Good "رُبط صادرٌ واحد بوارِدَين ⇒ كلاهما «تم الرد»"

            # «يخصّ كتاباً سابقاً» ⇒ يُنشئ المعاملة ويضمّ
            $rel = Api POST "/case-files/relate" @{
                kind = 'Outgoing'; bookId = $outIds[1]
                otherKind = 'Incoming'; otherBookId = $inIds[1]
                title = "معاملة كشف الكميات [$tag]"
            } $tok $cid
            if ($rel.S -eq 200) {
                $caseId = [int]$rel.B.caseFileId
                $null = Api POST "/case-files/$caseId/members" @{ kind = 'Incoming'; bookId = $inIds[2] } $tok $cid
                $null = Api POST "/case-files/$caseId/members" @{ kind = 'Incoming'; bookId = $inIds[3] } $tok $cid
                $det = (Api GET "/case-files/$caseId" $null $tok $cid).B
                Good "معاملة #$caseId «$($det.title)» — أعضاؤها: $(@($det.members).Count)"
                Note "معاملة [$($co.name)]" "#$caseId — $(@($det.members).Count) كتب في خيطٍ واحد"
            }
            else { Warn "تعذّر إنشاء المعاملة ($($rel.S)) $($rel.B.message)" }
        }
        else { Warn "تعذّر الربط ($($l1.S)/$($l2.S))" }
    }

    # ═══════════════════════ ٤) الأرشيف ═══════════════════════
    Head "٤) الأرشيف — أرشفةُ وارد + أضابير ورقية"
    # 🔴 **الأرشفة خطوتان لا واحدة**: مصفوفة انتقالات الوارد **مغلقة** (ADR-013)،
    #    و`Archived` لا تُبلَغ إلا من `Closed`. ومحاولةُ القفز إليها مباشرةً تُردّ —
    #    **وهذا سلوكٌ صحيح**: الأرشفة إقرارٌ بانتهاء المعاملة لا إخفاءٌ للكتاب.
    $archived = 0
    foreach ($idx in @(4)) {
        if ($inIds.Count -gt $idx) {
            $c1 = Api POST "/incoming/$($inIds[$idx])/status" @{ status = 'Closed'; note = "أُنجز الإجراء" } $tok $cid
            if ($c1.S -lt 300) {
                $a = Api POST "/incoming/$($inIds[$idx])/status" @{ status = 'Archived'; note = "أُرشف نهائياً" } $tok $cid
                if ($a.S -lt 300) { $archived++ } else { Warn "تعذّرت الأرشفة ($($a.S))" }
            }
            else { Warn "تعذّر الإغلاق قبل الأرشفة ($($c1.S))" }
        }
    }
    if ($archived -gt 0) { Good "أُرشف $archived كتاب وارد (يبقى وارداً — الأرشيف عدسة لا صندوق)" }

    $paper = 0
    $papers = @(
        @{ t = "عقد المقاولة الأصلي"; n = "ع/$tag/1" },
        @{ t = "محضر استلام أوّلي"; n = "م/$tag/2" },
        @{ t = "كتاب إحالة المناقصة"; n = "ح/$tag/3" }
    )
    foreach ($p in $papers) {
        $r = Api POST "/archive" @{
            companyId = $cid; title = "$($p.t) [$tag]"; documentTypeId = $null
            fromEntityId = $ent; toEntityId = $null; bookNumber = $p.n
            notes = "أُدخل ضمن البيانات التجريبية"
        } $tok $cid
        if ($r.S -eq 200) { $paper++; Say "أضبارة: $($r.B.number) — $($p.t)" }
    }
    Good "أضابير ورقية: $paper"
    Note "أرشيف [$($co.name)]" "$archived وارد مؤرشف + $paper أضبارة ورقية"

    # ═══════════════════════ ٥) المهام ═══════════════════════
    Head "٥) المهام — 5 بأولويات وحالات ونسب"
    $users = @((Api GET "/users" $null $tok $cid).B)
    $u1 = if ($users.Count -gt 0) { [int]$users[0].userId } else { $null }
    $u2 = if ($users.Count -gt 1) { [int]$users[1].userId } else { $u1 }

    $taskDefs = @(
        @{ t = "إعداد كشف الكميات النهائي"; p = 'Urgent'; k = 'Individual'; due = 3; status = 'InProgress'; prog = 65 },
        @{ t = "مراجعة العقد قانونياً"; p = 'High'; k = 'Individual'; due = 7; status = 'InProgress'; prog = 30 },
        @{ t = "تدقيق مستمسكات الكادر"; p = 'Normal'; k = 'Department'; due = 14; status = 'New'; prog = 0 },
        @{ t = "تجهيز تقرير التقدّم الشهري"; p = 'Normal'; k = 'Individual'; due = 0; status = 'InProgress'; prog = 80 },   # ⚠️ لا موعدَ ماضٍ: `TaskService` يرفضه عند الإنشاء
        @{ t = "أرشفة مراسلات الربع الأول"; p = 'Low'; k = 'Individual'; due = 21; status = 'Completed'; prog = 100 }
    )
    $tCount = 0
    foreach ($td in $taskDefs) {
        $b = @{
            title    = "$($td.t) [$tag]"
            taskType = $td.k
            priority = $td.p
            dueDate  = $today.AddDays($td.due).Date.ToString('yyyy-MM-ddT00:00:00')
            description = "مهمّةٌ ضمن البيانات التجريبية — $($td.t)."
        }
        if ($td.k -eq 'Individual' -and $u1) { $b.assignedToUserId = $u1 }
        # ⚠️ **`departmentId` لا `assignedToDepartmentId`** — عقدُ `CreateTaskRequest`.
        if ($td.k -eq 'Department') { $b.departmentId = $dept }

        $r = Api POST "/tasks" $b $tok $cid
        if ($r.S -ne 200) { Warn "مهمة «$($td.t)»: $($r.S) $($r.B.message)"; continue }
        $tid = [int]$r.B.taskId
        $tCount++

        if ($td.status -ne 'New') {
            $null = Api POST "/tasks/$tid/status" @{ newStatus = 'InProgress' } $tok $cid
            if ($td.prog -gt 0 -and $td.prog -lt 100) {
                $null = Api POST "/tasks/$tid/progress" @{ percent = $td.prog; comment = "تقدّمٌ مسجَّل" } $tok $cid
            }
            if ($td.status -eq 'Completed') {
                $null = Api POST "/tasks/$tid/progress" @{ percent = 100; comment = "أُنجزت" } $tok $cid
                $null = Api POST "/tasks/$tid/status" @{ newStatus = 'Completed' } $tok $cid
            }
        }
        # مشاركٌ ثانٍ على أوّل مهمة — ليُرى فرقُ «مسؤولٌ واحد + مشاركون»
        if ($tCount -eq 1 -and $u2 -and $u2 -ne $u1) {
            $null = Api POST "/tasks/$tid/participants" @{ userId = $u2 } $tok $cid
        }
        Say "مهمة: $($r.B.taskNumber) — $($td.t) [$($td.p)]"
    }
    Good "مهام: $tCount"
    Note "مهام [$($co.name)]" "$tCount مهام — متأخّرة ومنجزة وقيد التنفيذ"
}

# ═════════════════════════════ الخلاصة ═════════════════════════════
Head "══════════ ما أُنشئ — تحقّق منه في الشاشات ══════════"
foreach ($k in $script:made.Keys | Sort-Object) { Say "$k : $($script:made[$k])" 'White' }

Write-Host ""
Head "قائمة تحقّقٍ سريعة"
@(
    "الصادر ← الكتب المعتمدة لها **رقمٌ رسميّ** وPDF فيه الترويسة و**ختم QR**",
    "الصادر ← المسودّتان بلا رقمٍ وقابلتان للتعديل",
    "الوارد ← كتابان **قيد المراجعة** (أحدهما محالٌ لقسمين) · وواحد **مغلق**",
    "الوارد ← كتابان **تم الرد** — وافتح أيّهما تَرَ بطاقة «الكتب المرتبطة»",
    "المعاملات ← خيطٌ واحد يجمع الصادر مع الواردات",
    "الأرشيف ← الوارد المؤرشف **والأضابير الورقية** في عدسةٍ واحدة",
    "المهام ← لوحة كانبان: جديدة · قيد التنفيذ · منجزة — و**واحدة تستحقّ اليوم**",
    "المهام ← الأولى فيها **مشاركٌ ثانٍ** إضافةً إلى المسؤول",
    "الجرس ← إشعاراتُ الشركة الفعّالة وحدها (ADR-046)",
    "بدّل الشركة ← القوائم كلُّها تتبدّل معها"
) | ForEach-Object { Write-Host "  [ ] $_" -ForegroundColor White }
Write-Host ""
