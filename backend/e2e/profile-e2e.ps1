param([string]$AdminPwd='Speed3ds', [string]$Base='http://localhost:5080/api')
# ════════════════════════════════════════════════════════════════════════════════════════
#  اختبار التدفق الشامل (E2E) للبروفايل الشخصي — ADR-033. يعمل على API حيّ.
#
#  يغطّي: ربط البطاقة بحساب · هويّتي · طلب إجازة ذاتيّ · قرار الحسم عند المراجعة ·
#         رواتبي (المُسدَّدة وحدها) · وفكّ الربط.
#
#  🔐 **وأهمّ ما يحرسه — أن البروفايل ليس باباً خلفياً:**
#     · موظفٌ **بلا قسم الرواتب ولا الموظفين** يرى راتبه هو، ولا يرى `/payroll` ولا `/employees`.
#     · ولا يرى **بطاقة غيره**: كل نقطة تشتقّ الموظف من التوكن ولا تقبل معرّفاً.
#     · و**القارئ يدخل بروفايله** رغم أن `[RequireHrModule]` يحجبه عن الوحدة كلّها.
#
#  ⚠️ يكتب بيانات اختبار (مستخدم + موظف) ويعيد استعمالها عند إعادة التشغيل، ويُنظّف الربط.
#  ⚠️ ملفات PowerShell بالعربية تحتاج ترميز UTF-8 with BOM وإلا فشل التحليل في PS 5.1.
#  ⚠️ **المطابقة بالمعرّفات لا بالنصّ العربي** — PS 5.1 يشوّه العربية العائدة من الـAPI
#     فتفشل المطابقة صامتةً (درس مسجَّل في hr-e2e.ps1).
# ════════════════════════════════════════════════════════════════════════════════════════
$ErrorActionPreference='Stop'; $pass=0; $fail=0
function Ok($m){ $script:pass++; Write-Host "  [نجح] $m" -ForegroundColor Green }
function Bad($m){ $script:fail++; Write-Host "  [فشل] $m" -ForegroundColor Red }
function Sec($t){ Write-Host "`n=== $t ===" -ForegroundColor Cyan }
function Expect($label,$actual,$expected){
  if("$actual" -eq "$expected"){ Ok "$label" } else { Bad "$label — متوقع $expected لكن جاء $actual" }
}
function Api($m,$u,$b,$t,$c){ $h=@{}; if($t){$h.Authorization="Bearer $t"}; if($c){$h."X-Company-Id"="$c"}
  $p=@{Uri="$Base$u";Method=$m;Headers=$h;ContentType="application/json; charset=utf-8"}
  if($null -ne $b){$p.Body=[Text.Encoding]::UTF8.GetBytes(($b|ConvertTo-Json -Depth 8 -Compress))}
  try{$r=Invoke-WebRequest @p -UseBasicParsing; $j=$null; if($r.Content){try{$j=$r.Content|ConvertFrom-Json}catch{}}; return @{S=[int]$r.StatusCode;B=$j}}
  catch{$resp=$_.Exception.Response; $code=if($resp){[int]$resp.StatusCode}else{0}; $ct=''; if($resp){$sr=[IO.StreamReader]::new($resp.GetResponseStream());$ct=$sr.ReadToEnd()}; $j=$null; if($ct){try{$j=$ct|ConvertFrom-Json}catch{}}; return @{S=$code;B=$j}}
}

# ───────────────────────────── الإعداد ─────────────────────────────
Sec "الإعداد"
$admin=(Api POST "/auth/login" @{username='admin';password=$AdminPwd} $null $null).B.accessToken
if(-not $admin){ Bad "تعذّر دخول admin"; exit 1 }
# قاعدةٌ نظيفة بلا شركة؟ ننشئ واحدة — فالسكربت يعمل على قاعدة اختبارٍ مستقلّة كما
# يعمل على قاعدة التطوير، ولا يفترض بذراً لم يعد النظام يفعله.
$companies=@((Api GET "/companies" $null $admin $null).B)
if($companies.Count -eq 0){
  $new=Api POST "/companies" @{name='شركة اختبار البروفايل';prefix='PROF';isActive=$true} $admin $null
  if($new.S -ne 200){ Bad "تعذّر إنشاء شركة الاختبار ($($new.S))"; exit 1 }
  $companies=@((Api GET "/companies" $null $admin $null).B)
}
$cid=$companies[0].companyId
Ok "الشركة الفعّالة: $cid"

function UpsertUser($username,$displayName,$role,$modules){
  $ex=(Api GET "/users" $null $admin $cid).B | Where-Object { $_.username -eq $username } | Select-Object -First 1
  $body=@{fullName=$displayName;role=$role;isActive=$true;companies=@(
    @{companyId=$cid;modules=$modules;departmentId=$null;canApprove=$false;canManageIncoming=$false;
      canViewAllIncoming=$false;canManageEmployees=$false;canManagePayroll=$false})}
  if($ex){ $null=Api PUT "/users/$($ex.userId)" $body $admin $cid }
  else { $body.username=$username; $body.password='Prof@12345'; $null=Api POST "/users" $body $admin $cid }
  return (Api GET "/users" $null $admin $cid).B | Where-Object { $_.username -eq $username } | Select-Object -First 1
}
function Login($user){
  $r=Api POST "/auth/login" @{username=$user;password='Prof@12345new'} $null $null
  if($r.S -ne 200){ $r=Api POST "/auth/login" @{username=$user;password='Prof@12345'} $null $null }
  if($r.B.mustChangePassword){ $tok=$r.B.accessToken
    $null=Api POST "/auth/change-password" @{currentPassword='Prof@12345';newPassword='Prof@12345new'} $tok $null
    $r=Api POST "/auth/login" @{username=$user;password='Prof@12345new'} $null $null }
  return $r.B.accessToken
}

# 🔴 **المستخدم بلا أي قسم من أقسام الموارد البشرية** — وهذا محورُ الاختبار كلّه:
#    لو مُنح `Payroll` لصار رؤيتُه راتبَه بديهيةً ولم نُثبت شيئاً.
$u1=UpsertUser 'prof_emp' 'موظف البروفايل' 'Employee' @('Outgoing')
$u2=UpsertUser 'prof_emp2' 'موظف بروفايل ثانٍ' 'Employee' @('Outgoing')
$rdr=UpsertUser 'prof_rdr' 'قارئ البروفايل' 'Reader' @('Outgoing')
if($u1 -and $u2 -and $rdr){ Ok "ثلاثة حسابات اختبار (بلا قسمَي الموظفين والرواتب)" } else { Bad "تعذّر إنشاء الحسابات"; exit 1 }

# بطاقة موظف بمعرّف هوية ثابت — يُعاد استعمالها.
$found=(Api GET "/employees/lookup?nationalId=19770707" $null $admin $cid).B
if($found -and $found.employeeId){ $eid=$found.employeeId }
else {
  $eid=(Api POST "/employees" @{profile=@{fullName='صاحب البروفايل';fullNameEn='Profile Owner';
        nationalId='19770707';receiptLanguage='Arabic'};
        employment=@{position='مهندس مشاريع';positionEn='Engineer';hireDate='2022-04-01T00:00:00';
        salaryCurrency='IQD';baseSalary=900000;displayOrder=7;isActive=$true}} $admin $cid).B.employeeId
}
if($eid){ Ok "بطاقة الموظف: $eid" } else { Bad "تعذّر إنشاء البطاقة"; exit 1 }

# نظافةُ بداية: نفكّ أي ربطٍ سابق فيبدأ التشغيل من حالٍ معروفة.
$null=Api DELETE "/employees/$eid/user" $null $admin $cid

# ─────────────────────── ١) قبل الربط ───────────────────────
Sec "١) قبل الربط — بروفايلٌ بلا بطاقة"
$tok1=Login 'prof_emp'
if($tok1){ Ok "دخول prof_emp" } else { Bad "فشل دخول prof_emp"; exit 1 }

$me=Api GET "/profile" $null $tok1 $cid
Expect "البروفايل مفتوح بلا أي قسم (لا Employees ولا Payroll)" $me.S 200
Expect "وغير مرتبط ببطاقة" $me.B.isLinkedToEmployee $false
if(-not $me.B.employeeId){ Ok "ومعرّف البطاقة فارغ — حالةٌ عاديّة لا خطأ" } else { Bad "معرّف موظف ظهر بلا ربط" }

# 🔴 الحارس: بلا بطاقة **لا إجازات ولا رواتب** — 404 لا 200 بقائمةٍ فارغة كاذبة.
Expect "🔐 الإجازات محجوبة قبل الربط" (Api GET "/profile/leaves" $null $tok1 $cid).S 404
Expect "🔐 والرواتب كذلك"             (Api GET "/profile/payslips" $null $tok1 $cid).S 404

# ─────────────────────── ٢) الربط ───────────────────────
Sec "٢) ربط البطاقة بالحساب"
$linkable=(Api GET "/employees/linkable-users" $null $admin $cid).B
if(($linkable | Where-Object { $_.userId -eq $u1.userId })){ Ok "الحساب يظهر في قائمة الحسابات الحرّة" }
else { Bad "الحساب غائب عن قائمة الربط" }

$lnk=Api PUT "/employees/$eid/user" @{userId=$u1.userId} $admin $cid
Expect "الربط نجح" $lnk.S 200
Expect "والبطاقة تحمل الحساب" $lnk.B.userId $u1.userId
if($lnk.B.username){ Ok "واسمُ الحساب يُعاد ليُعرض: $($lnk.B.username)" } else { Bad "اسم الحساب لم يُعَد" }

# 🔴 حسابٌ واحد لبطاقةٍ واحدة — في الاتجاهين.
$dup=Api PUT "/employees/$eid/user" @{userId=$u2.userId} $admin $cid
Expect "🔐 بطاقةٌ مربوطة لا تُربط بحسابٍ ثانٍ (409)" $dup.S 409

$after=(Api GET "/employees/linkable-users" $null $admin $cid).B
if(-not ($after | Where-Object { $_.userId -eq $u1.userId })){ Ok "🔐 والحساب خرج من قائمة الحسابات الحرّة" }
else { Bad "الحساب المربوط ما زال معروضاً للربط" }

# ─────────────────────── ٣) هويّتي بعد الربط ───────────────────────
Sec "٣) هويّتي"
$me=(Api GET "/profile" $null $tok1 $cid)
Expect "مرتبطٌ الآن" $me.B.isLinkedToEmployee $true
Expect "ومعرّف البطاقة صحيح" $me.B.employeeId $eid
if($me.B.position){ Ok "والصفة تصل من إسناد الشركة" } else { Bad "الصفة لم تصل" }
if($me.B.hireDate){ Ok "وتاريخ التعيين يصل" } else { Bad "تاريخ التعيين لم يصل" }

# 🔴 **البروفايل ليس باباً خلفياً**: القسمان ما زالا محجوبين رغم فتح البروفايل.
Sec "🔐 البروفايل لا يفتح الوحدة"
foreach($ep in @("/employees","/payroll/years","/hr/summary","/hr/leaves/pending")){
  $r=Api GET $ep $null $tok1 $cid
  if($r.S -eq 403){ Ok "🔐 $ep محجوبة (403) رغم أن بروفايله مفتوح" }
  else { Bad "تسرّب: $ep ردّت $($r.S) لمن لا يملك القسم" }
}

# ─────────────────────── ٤) طلب إجازة ذاتيّ ───────────────────────
Sec "٤) طلب إجازة ذاتيّ"
# نظافةُ بداية: نسحب أي طلبٍ معلّق من تشغيلٍ سابق.
foreach($old in ((Api GET "/profile/leaves" $null $tok1 $cid).B | Where-Object { $_.status -eq 'Pending' })){
  $null=Api DELETE "/profile/leaves/$($old.leaveId)" $null $tok1 $cid
}

$from=(Get-Date).AddDays(400).ToString('yyyy-MM-dd')
$to=(Get-Date).AddDays(403).ToString('yyyy-MM-dd')
$req=Api POST "/profile/leaves" @{leaveType='Annual';fromDate="$($from)T00:00:00";toDate="$($to)T00:00:00";notes='طلب اختبار'} $tok1 $cid
Expect "الطلب نجح" $req.S 200
$lid=$req.B.leaveId

# 🔴 الحرّاس الثلاثة التي تمنع الموظف من منح نفسه إجازةً بلا حسم:
Expect "🔐 الحالة **معلّقة** لا مقبولة"      $req.B.status 'Pending'
Expect "🔐 وطلبُ الموافقة مفروضٌ true" $req.B.requiresApproval $true
Expect "🔐 والحسم false — كغيابِ قرارٍ لا كقرار" $req.B.deductFromSalary $false
Expect "🔐 والعلَم الذاتيّ true — يُخبر المراجع أن الحسم لم يُقرَّر" $req.B.isSelfRequested $true

# ⚠️ ولو حاول إرسال الحقول المحظورة، فالعقد لا يقرؤها أصلاً — نتأكّد أن حقنها لا يمرّ.
$inject=Api POST "/profile/leaves" @{leaveType='Annual';
      fromDate="$((Get-Date).AddDays(500).ToString('yyyy-MM-dd'))T00:00:00";
      toDate="$((Get-Date).AddDays(501).ToString('yyyy-MM-dd'))T00:00:00";
      requiresApproval=$false;deductFromSalary=$false;status='Approved'} $tok1 $cid
if($inject.S -eq 200){
  Expect "🔐 حقنُ طلبِ الموافقة false لا يمرّ — الحالة معلّقة" $inject.B.status 'Pending'
  $null=Api DELETE "/profile/leaves/$($inject.B.leaveId)" $null $tok1 $cid
} else { Bad "الطلب الثاني ردّ $($inject.S)" }

# التداخل مرفوض — القاعدة نفسها التي في LeaveService لا استثناء منها.
$overlap=Api POST "/profile/leaves" @{leaveType='Sick';fromDate="$($from)T00:00:00";toDate="$($to)T00:00:00"} $tok1 $cid
Expect "التداخل مرفوض (409)" $overlap.S 409

# والإجازة تظهر في **قائمة المعلّقات** لمن يديرها، بعلَمها الذاتيّ.
$pending=(Api GET "/hr/leaves/pending" $null $admin $cid).B | Where-Object { $_.leaveId -eq $lid } | Select-Object -First 1
if($pending){ Ok "الطلب يظهر في قائمة المعلّقات لمن يديرها" } else { Bad "الطلب غائب عن قائمة المعلّقات" }
if($pending){ Expect "🔐 وبالعلَم الذاتيّ فيها" $pending.isSelfRequested $true }

# ─────────────────────── ٥) قرار الحسم عند المراجعة ───────────────────────
Sec "٥) المراجعة تقرّر الحسم"
$rev=Api PATCH "/employees/leaves/$lid" @{approve=$true;notes='موافق';deductFromSalary=$true} $admin $cid
Expect "الموافقة نجحت" $rev.S 200
Expect "🔴 وقرار الحسم **كُتب** (لولاه لمرّ false صامتاً)" $rev.B.deductFromSalary $true
Expect "والحالة صارت مقبولة" $rev.B.status 'Approved'

# والموظف يرى القرار في إجازاته.
$mine=(Api GET "/profile/leaves" $null $tok1 $cid).B | Where-Object { $_.leaveId -eq $lid } | Select-Object -First 1
if($mine){ Expect "والموظف يرى أنها تُحسم" $mine.deductFromSalary $true } else { Bad "الإجازة غائبة عن قائمته" }

# 🔴 وبعد البتّ لا يُسحب الطلب.
Expect "🔐 المبتوت لا يُسحب (409)" (Api DELETE "/profile/leaves/$lid" $null $tok1 $cid).S 409

# ─────────────────────── ٦) رواتبي ───────────────────────
Sec "٦) رواتبي — المُسدَّدة وحدها"
$slips=Api GET "/profile/payslips" $null $tok1 $cid
Expect "القائمة تُقرأ بلا قسم الرواتب" $slips.S 200
$drafts=@($slips.B | Where-Object { $_.paidAt -eq $null })
if($drafts.Count -eq 0){ Ok "🔐 ولا سطرَ من شهرٍ غير مُسدَّد (المسودّة رقمٌ غير نهائيّ)" }
else { Bad "تسرّب: $($drafts.Count) سطراً بلا تاريخ تسديد" }

# ⚠️ الرواتب قد تكون فارغة في قاعدةٍ نظيفة — وذلك ليس فشلاً.
if(@($slips.B).Count -gt 0){
  $one=@($slips.B)[0]
  if($one.monthLabel){ Ok "والشهر يصل بتسميته العربية" } else { Bad "تسمية الشهر لم تصل" }
  if($null -ne $one.eligibleDays){ Ok "وتفصيلُ الأيام يصل (يُفهم منه الرقم)" } else { Bad "التفصيل لم يصل" }
} else { Write-Host "  [تخطّي] لا رواتب مُسدَّدة لهذا الموظف — شغّل hr-e2e أولاً لتغطية هذا الجزء" -ForegroundColor Yellow }

# ─────────────────────── ٧) القارئ يدخل بروفايله ───────────────────────
Sec "٧) القارئ — محجوبٌ عن الوحدة، مفتوحٌ له بروفايله"
$tokR=Login 'prof_rdr'
if($tokR){
  Expect "🔐 القارئ محجوب عن الموظفين" (Api GET "/employees" $null $tokR $cid).S 403
  Expect "🔐 ومحجوب عن الرواتب"        (Api GET "/payroll/years" $null $tokR $cid).S 403
  Expect "🔓 وبروفايلُه مفتوح"          (Api GET "/profile" $null $tokR $cid).S 200
} else { Bad "فشل دخول القارئ" }

# ─────────────────────── ٨) فكّ الربط ───────────────────────
Sec "٨) فكّ الربط يُغلق النافذة فوراً"
$unl=Api DELETE "/employees/$eid/user" $null $admin $cid
Expect "الفكّ نجح" $unl.S 200
if(-not $unl.B.userId){ Ok "والبطاقة صارت بلا حساب" } else { Bad "الحساب ما زال مربوطاً" }

Expect "🔐 والإجازات صارت محجوبة عن الحساب فوراً" (Api GET "/profile/leaves" $null $tok1 $cid).S 404
Expect "🔐 والرواتب كذلك"                         (Api GET "/profile/payslips" $null $tok1 $cid).S 404
Expect "والبروفايل نفسه يبقى مفتوحاً بلا بطاقة"   (Api GET "/profile" $null $tok1 $cid).S 200

# والسجلّ يبقى مقروءاً — من يفتح الملفّ يعرف متى فُتحت النافذة ومتى أُغلقت.
$log=(Api GET "/employees/$eid/log" $null $admin $cid).B
$linkLogs=@($log | Where-Object { $_.changeType -eq 'UserLinked' -or $_.changeType -eq 'UserUnlinked' })
if($linkLogs.Count -ge 2){ Ok "🔴 وسطرا السجلّ (ربط + فكّ) باقيان في ملفّ الموظف" }
else { Bad "سجلّ الربط ناقص — وُجد $($linkLogs.Count) سطراً" }

# وإعادة الربط ممكنة بعد الفكّ (الفهرس الفريد مفلتر على NULL).
$re=Api PUT "/employees/$eid/user" @{userId=$u1.userId} $admin $cid
Expect "وإعادة الربط بعد الفكّ تعمل" $re.S 200
$null=Api DELETE "/employees/$eid/user" $null $admin $cid

Write-Host "`n=== النتيجة ===" -ForegroundColor Cyan
Write-Host "نجح: $pass" -ForegroundColor Green
Write-Host "فشل: $fail" -ForegroundColor $(if($fail -eq 0){'Green'}else{'Red'})
if($fail -gt 0){ exit 1 }
