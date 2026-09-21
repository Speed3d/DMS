param([string]$AdminPwd='Speed3ds', [string]$Base='http://localhost:5080/api')
$ErrorActionPreference='Stop'; $pass=0; $fail=0
function Ok($m){ $script:pass++; Write-Host "  [نجح] $m" -ForegroundColor Green }
function Bad($m){ $script:fail++; Write-Host "  [فشل] $m" -ForegroundColor Red }
function Skip($m){ Write-Host "  [تخطّي] $m" -ForegroundColor DarkYellow }
function Api($m,$u,$b,$t,$c){ $h=@{}; if($t){$h.Authorization="Bearer $t"}; if($c){$h."X-Company-Id"="$c"}
  $p=@{Uri="$Base$u";Method=$m;Headers=$h;ContentType="application/json; charset=utf-8"}
  if($null -ne $b){$p.Body=[Text.Encoding]::UTF8.GetBytes(($b|ConvertTo-Json -Depth 8 -Compress))}
  try{$r=Invoke-WebRequest @p -UseBasicParsing; $j=$null; if($r.Content){try{$j=$r.Content|ConvertFrom-Json}catch{}}; return @{S=[int]$r.StatusCode;B=$j}}
  catch{$resp=$_.Exception.Response; $code=if($resp){[int]$resp.StatusCode}else{0}; $ct=''; if($resp){$sr=[IO.StreamReader]::new($resp.GetResponseStream());$ct=$sr.ReadToEnd()}; $j=$null; if($ct){try{$j=$ct|ConvertFrom-Json}catch{}}; return @{S=$code;B=$j}}
}
function Expect($label,$actual,$expected){ if($actual -eq $expected){ Ok "$label (HTTP $actual)" } else { Bad "$label — متوقع $expected وجاء $actual" } }

# ⚠️ **المطابقة بالمعرّفات الرقمية لا بالأسماء العربية** — PS 5.1 يشوّه العربية العائدة من
#    الـAPI فتفشل المطابقة صامتةً (درسٌ مسجَّل من وحدة الرواتب).
# ⚠️ **و`@((Api ...).B)` لا `@(Api ...).B`** — الثانية تضيع معها `.Count` حين تكون القائمة
#    من عنصرٍ واحد فتُبلّغ «فارغة» وهي ليست كذلك (G17).
# 🔴 **ولكل تشغيلٍ بصمةٌ خاصّة** — المطابقة بقيمةٍ ثابتة تلتقط أثر التشغيل السابق فتبدو
#    تكاثراً وهو ليس كذلك: **عيبُ مرشِّحٍ لا عيبُ منتج**.
$mk=[guid]::NewGuid().ToString('N').Substring(0,6)

Write-Host "=== إعداد ===" -ForegroundColor Cyan
$admin=(Api POST "/auth/login" @{username='admin';password=$AdminPwd} $null $null).B.accessToken
if(-not $admin){ Bad "تعذّر دخول admin"; exit 1 }
$companies=@((Api GET "/companies" $null $admin $null).B)
if($companies.Count -lt 1){
  # ⚠️ يُنشئ الشركة إن غابت — فالسكربت يعمل على قاعدةٍ نظيفة (نمط `profile-e2e`).
  $null=Api POST "/companies" @{name="شركة الاختبار $mk";prefix="T$((Get-Random -Minimum 10 -Maximum 99))";isActive=$true} $admin $null
  $companies=@((Api GET "/companies" $null $admin $null).B)
}
if($companies.Count -lt 1){ Bad "تعذّر تجهيز شركة"; exit 1 }
$cid=[int]$companies[0].companyId
$cid2=if($companies.Count -ge 2){[int]$companies[1].companyId}else{0}
Ok "الشركة الفعّالة: $cid"

$ent=@((Api GET "/entities" $null $admin $cid).B) | Select-Object -First 1
if(-not $ent){ $ent=(Api POST "/entities" @{companyId=$cid;name="جهة $mk";kind='Both'} $admin $cid).B }
$eid=[int]$ent.entityId

$depts=@((Api GET "/departments" $null $admin $cid).B)
$dep=$depts | Where-Object { $_.name -eq 'CASE-DEP' } | Select-Object -First 1
if(-not $dep){ $dep=(Api POST "/departments" @{companyId=$cid;name='CASE-DEP';isActive=$true} $admin $cid).B }
$depId=[int]$dep.departmentId

$other=$depts | Where-Object { $_.name -eq 'CASE-OTHER' } | Select-Object -First 1
if(-not $other){ $other=(Api POST "/departments" @{companyId=$cid;name='CASE-OTHER';isActive=$true} $admin $cid).B }
$otherDepId=[int]$other.departmentId
Ok "قسمان للاختبار: $depId و $otherDepId"

function UpsertUser($username,$displayName,$role,$modules,$canIncoming,$departmentId){
  $ex=@((Api GET "/users" $null $admin $cid).B) | Where-Object { $_.username -eq $username } | Select-Object -First 1
  $body=@{fullName=$displayName;role=$role;isActive=$true;companies=@(
    @{companyId=$cid;modules=$modules;departmentId=$departmentId;canManageIncoming=$canIncoming})}
  if($ex){ $null=Api PUT "/users/$($ex.userId)" $body $admin $cid }
  else { $body.username=$username; $body.password='Case@12345'; $null=Api POST "/users" $body $admin $cid }
  return @((Api GET "/users" $null $admin $cid).B) | Where-Object { $_.username -eq $username } | Select-Object -First 1
}
function UserLogin($u){ (Api POST "/auth/login" @{username=$u;password='Case@12345'} $null $null).B.accessToken }

$null=UpsertUser 'case_mgr' 'مدير المعاملات' 'Employee' @('Incoming','Outgoing') $true  $depId
$null=UpsertUser 'case_out' 'موظف قسم آخر'   'Employee' @('Incoming','Outgoing') $true  $otherDepId
$null=UpsertUser 'case_rdr' 'قارئ'           'Reader'   @('Incoming','Outgoing') $true  $depId
$null=UpsertUser 'case_og'  'صادرٌ فقط'      'Employee' @('Outgoing')            $true  $depId
$tMgr=UserLogin 'case_mgr'; $tOut=UserLogin 'case_out'; $tRdr=UserLogin 'case_rdr'; $tOg=UserLogin 'case_og'
if($tMgr -and $tOut -and $tRdr -and $tOg){ Ok "دخول الأربعة" } else { Bad "تعذّر دخول أحدهم"; exit 1 }

function NewIncoming($subject,$tok){
  (Api POST "/incoming" @{companyId=$cid;receivedDate='2026-09-01T00:00:00';entityId=$eid
    subject=$subject;receiveMethod='Manual'} $tok $cid).B
}

Write-Host "`n=== ١) الإنشاء والضمّ ===" -ForegroundColor Cyan
$a=NewIncoming "وارد أ $mk" $tMgr
$b=NewIncoming "وارد ب $mk" $tMgr
if($a.incomingId -and $b.incomingId){ Ok "أُنشئ واردان" } else { Bad "تعذّر إنشاء الوارد"; exit 1 }

$rel=Api POST "/case-files/relate" @{kind='Incoming';bookId=$a.incomingId
  otherKind='Incoming';otherBookId=$b.incomingId;title="معاملة الاختبار $mk"} $tMgr $cid
Expect "«يخصّ كتاباً سابقاً» يُنشئ معاملة ويضمّ الطرفين" $rel.S 200
$caseId=[int]$rel.B.caseFileId
if(@($rel.B.members).Count -eq 2){ Ok "المعاملة فيها كتابان" } else { Bad "عدد الأعضاء: $(@($rel.B.members).Count)" }

# 🔴 **الضمّ لا يمسّ الحالة إطلاقاً** — تجميعٌ لا إجراء (قرار المالك). وهذا يخالف الربط
#    بصادر الذي ينقل إلى «تم الرد»، والزرّان متجاوران في الشاشة.
$after=(Api GET "/incoming/$($a.incomingId)" $null $tMgr $cid).B
if($after.status -eq $a.status){ Ok "الضمّ لم يغيّر الحالة ($($after.status))" } else { Bad "تغيّرت الحالة: $($a.status) ⇒ $($after.status)" }

Write-Host "`n=== ٢) بطاقة الكتب المرتبطة ===" -ForegroundColor Cyan
$rel1=Api GET "/case-files/related/Incoming/$($a.incomingId)" $null $tMgr $cid
Expect "بطاقة المرتبط تُرجع المعاملة" $rel1.S 200
if(@($rel1.B.members).Count -eq 1){ Ok "وتستبعد الكتابَ نفسه (يعرض الآخر وحده)" } else { Bad "عدد الأعضاء: $(@($rel1.B.members).Count)" }

$lone=NewIncoming "وارد بلا معاملة $mk" $tMgr
Expect "كتابٌ بلا معاملة يردّ 204" (Api GET "/case-files/related/Incoming/$($lone.incomingId)" $null $tMgr $cid).S 204

Write-Host "`n=== ٣) المحجوب: عددٌ بلا تفاصيل ===" -ForegroundColor Cyan
# يُحال أحد الكتابين إلى قسمٍ لا ينتمي إليه `case_out` فيُحجب عنه، ويُترك الآخر مرئياً له.
$null=Api POST "/incoming/$($a.incomingId)/forward" @{departments=@(@{departmentId=$otherDepId;note='لقسم آخر'})} $tMgr $cid
$null=Api POST "/incoming/$($b.incomingId)/forward" @{departments=@(@{departmentId=$depId;note='لقسمه'})} $tMgr $cid

$seen=Api GET "/case-files/$caseId" $null $tOut $cid
if($seen.S -eq 200){
  $vis=@($seen.B.members).Count
  $hid=[int]$seen.B.hiddenCount
  if($vis -eq 1 -and $hid -eq 1){ Ok "يرى كتاباً واحداً ويُعلَن أن ١ محجوب" } else { Bad "مرئي=$vis محجوب=$hid (المتوقع 1 و1)" }

  # 🔐 **ولا يتسرّب رقمٌ ولا عنوان** للكتاب المحجوب.
  $raw=($seen.B.members | ConvertTo-Json -Depth 6 -Compress)
  if($raw -notmatch [regex]::Escape("$($b.incomingNumber)")){ Ok "ولا يتسرّب رقم الكتاب المحجوب" } else { Bad "رقم الكتاب المحجوب ظاهر في الرد" }
} else { Bad "تعذّر على موظف القسم الآخر فتح المعاملة: $($seen.S)" }

Write-Host "`n=== ٤) القائمة لا تكشف معاملةً كلُّ كتبها محجوبة ===" -ForegroundColor Cyan
$hidden=NewIncoming "وارد مخفيّ تماماً $mk" $tMgr
$null=Api POST "/incoming/$($hidden.incomingId)/forward" @{departments=@(@{departmentId=$otherDepId;note='لقسم آخر'})} $tMgr $cid
$secret=Api POST "/case-files" @{title="معاملة سرّية $mk"} $tMgr $cid
$null=Api POST "/case-files/$([int]$secret.B.caseFileId)/members" @{kind='Incoming';bookId=$hidden.incomingId} $tMgr $cid

# `case_mgr` في CASE-DEP والكتاب مُحال إلى CASE-OTHER — لكنه **هو مَن أحاله** فيراه
# (قاعدة «مَن أحال يبقى يرى»). فنسأل موظفاً ثالثاً لا علاقة له: `case_og` بلا قسم وارد.
$listForOg=@((Api GET "/case-files" $null $tOg $cid).B)
$leak=$listForOg | Where-Object { [int]$_.caseFileId -eq [int]$secret.B.caseFileId }
if(-not $leak){ Ok "معاملةٌ بلا كتابٍ مرئيّ لا تظهر في قائمته" } else { Bad "تسرّبت المعاملة السرّية إلى القائمة" }
Expect "وفتحُها المباشر يردّ 404 لا 403" (Api GET "/case-files/$([int]$secret.B.caseFileId)" $null $tOg $cid).S 404

Write-Host "`n=== ٥) الصلاحيات ===" -ForegroundColor Cyan
Expect "القارئ محجوبٌ عن الإنشاء" (Api POST "/case-files" @{title="محاولة قارئ $mk"} $tRdr $cid).S 403
Expect "والقارئ محجوبٌ عن الضمّ" (Api POST "/case-files/$caseId/members" @{kind='Incoming';bookId=$lone.incomingId} $tRdr $cid).S 403
# 🔐 والقارئ **يقرأ** المعاملة إن رأى كتاباً فيها — القراءة ليست الكتابة.
$rdrRead=(Api GET "/case-files/$caseId" $null $tRdr $cid)
if($rdrRead.S -eq 200 -or $rdrRead.S -eq 404){ Ok "وقراءتُه تتبع رؤيته لا دورَه (HTTP $($rdrRead.S))" } else { Bad "قراءة القارئ: $($rdrRead.S)" }

Write-Host "`n=== ٦) الدمج ===" -ForegroundColor Cyan
$x=NewIncoming "وارد س $mk" $tMgr
$y=NewIncoming "وارد ص $mk" $tMgr
$c2=Api POST "/case-files/relate" @{kind='Incoming';bookId=$x.incomingId
  otherKind='Incoming';otherBookId=$y.incomingId;title="معاملة ثانية $mk"} $tMgr $cid
$case2=[int]$c2.B.caseFileId
Expect "رفض دمج معاملةٍ بنفسها" (Api POST "/case-files/$case2/merge/$case2" $null $tMgr $cid).S 400

$merged=Api POST "/case-files/$caseId/merge/$case2" $null $tMgr $cid
Expect "الدمج ينجح لمن يرى الكلّ" $merged.S 200
if(@($merged.B.members).Count -ge 4){ Ok "والهدف يحوي كتب الاثنتين ($(@($merged.B.members).Count))" } else { Bad "عدد الأعضاء بعد الدمج: $(@($merged.B.members).Count)" }
Expect "والمصدر طُوي بعد الدمج" (Api GET "/case-files/$case2" $null $tMgr $cid).S 404

Write-Host "`n=== ٧) الإخراج وطيُّ الفارغة ===" -ForegroundColor Cyan
$solo=NewIncoming "وارد وحيد $mk" $tMgr
$sc=Api POST "/case-files" @{title="معاملة تُطوى $mk"} $tMgr $cid
# 🔴 **حارسٌ وُلد من عيبٍ كشفه هذا السكربت**: `POST` يُنهي بـ`Get`، وقاعدةُ «أخفِ ما لا
#    كتابَ مرئيّاً فيه» كانت تنطبق على معاملةٍ **فارغة لتوّها** فتردّ 404 على مُنشئها.
#    **والفارغة ليست «كلُّها محجوبة»** — ما لا كتابَ فيه لا يُخفي شيئاً.
Expect "إنشاء معاملة فارغة يردّ 200 لا 404" $sc.S 200
$scId=[int]$sc.B.caseFileId
Expect "ضمُّ كتابٍ إليها" (Api POST "/case-files/$scId/members" @{kind='Incoming';bookId=$solo.incomingId} $tMgr $cid).S 200
$rm=Api DELETE "/case-files/$scId/members/Incoming/$($solo.incomingId)" $null $tMgr $cid
if($rm.S -eq 200 -or $rm.S -eq 204){ Ok "الإخراج نجح (HTTP $($rm.S))" } else { Bad "الإخراج: $($rm.S)" }
Expect "والمعاملة طُويت بخروج آخر كتاب" (Api GET "/case-files/$scId" $null $tMgr $cid).S 404

Write-Host "`n=== ٨) العزل بين الشركات ===" -ForegroundColor Cyan
if($cid2 -gt 0){
  Expect "معاملةُ الشركة الأولى لا تُرى من الثانية" (Api GET "/case-files/$caseId" $null $admin $cid2).S 404
} else { Skip "لا شركة ثانية" }

Write-Host "`n=== ٩) الإشعارات (الدفعة ٤) ===" -ForegroundColor Cyan
# 🔔 **الإشعار ملكُ صاحبه** — فنقرأ إشعارات المستلِم بتوكنه هو لا بتوكن الأدمن.
# ⚠️ **ولا يُشعَر الفاعل بفعل نفسه** — فالمُحيل لا يصله إشعار إحالته.
$nWork=NewIncoming "وارد للإشعار $mk" $tMgr
$fw=Api POST "/incoming/$($nWork.incomingId)/forward" @{departments=@(@{departmentId=$otherDepId;note='لقسم آخر'})} $tMgr $cid
Expect "إحالة كتابٍ إلى قسم زميل" $fw.S 200

$inbox=@((Api GET "/notifications" $null $tOut $cid).B.items)
$hit=$inbox | Where-Object { $_.entityType -eq 'IncomingBook' -and [int]$_.entityId -eq [int]$nWork.incomingId } | Select-Object -First 1
if($hit){ Ok "موظفُ القسم المُحال إليه وصله إشعار" } else { Bad "لم يصل إشعارُ الإحالة" }

# 🔴 **الحقلان اللذان يجعلان الإشعار قابلاً للفتح** — وبدونهما يصل ولا يُفتح بالنقر
#    (نمط «ميزة بلا مدخل»). وموجّهُ الواجهة يقرأ `entityType` حصراً.
if($hit){
  if($hit.entityType -eq 'IncomingBook'){ Ok "ويحمل `entityType` الذي يعرفه موجّه الواجهة" } else { Bad "entityType: $($hit.entityType)" }
  if([int]$hit.entityId -gt 0){ Ok "ويحمل `entityId` فيُفتح الكتاب بالنقر" } else { Bad "entityId فارغ" }
}

# ⚠️ **ولا يُشعَر الفاعل** — المُحيل نفسه لا يجد الإشعار في صندوقه.
$own=@((Api GET "/notifications" $null $tMgr $cid).B.items)
$self=$own | Where-Object { $_.entityType -eq 'IncomingBook' -and [int]$_.entityId -eq [int]$nWork.incomingId } | Select-Object -First 1
if(-not $self){ Ok "والمُحيل نفسه لا يصله إشعارُ فعله" } else { Bad "وصل الفاعلَ إشعارُ فعله" }

# 🔴 **تكرارُ الإحالة لا يُكرّر الإشعار** — `DedupKey` بفهرسٍ فريد يمنعه **في القاعدة**.
$before=@($inbox | Where-Object { [int]$_.entityId -eq [int]$nWork.incomingId }).Count
$null=Api POST "/incoming/$($nWork.incomingId)/forward" @{departments=@(@{departmentId=$otherDepId;note='إعادة'})} $tMgr $cid
$after=@(@((Api GET "/notifications" $null $tOut $cid).B.items) | Where-Object { [int]$_.entityId -eq [int]$nWork.incomingId }).Count
if($after -eq $before){ Ok "وإعادةُ الإحالة لا تُكرّر الإشعار ($after)" } else { Bad "تكاثر: $before ثم $after" }

Write-Host "`n=== النتيجة ===" -ForegroundColor Cyan
Write-Host "نجح: $pass" -ForegroundColor Green
Write-Host "فشل: $fail" -ForegroundColor $(if($fail -gt 0){'Red'}else{'Green'})
if($fail -gt 0){ exit 1 }
