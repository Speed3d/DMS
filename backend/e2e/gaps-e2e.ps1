param([string]$AdminPwd='Admin@12345', [string]$Base='http://localhost:5091/api',
      [string]$Db='Server=.;Database=DmsE2E_New;Integrated Security=true;TrustServerCertificate=True')
# ════════════════════════════════════════════════════════════════════════════
#  حرّاس فجوات المراجعة (ADR-053 — قرار المالك 2026-09-24):
#
#  G20) رقمُ الكتاب المرتبط وموضوعُه لمن لا يملك قسمه: تفاصيل الوارد كانت تعرض الصادر الذي
#       ردّ عليه لكلّ من يرى الوارد، والعكس — والآن **العدد وحده** («المحجوب بالعدد»).
#       ومعه: الواردُ المحجوب بحدّ القسم كان **يُسقَط صامتاً** من تفاصيل الصادر.
#  G22) القارئ لا يعتمد ولا يدير الوارد — لا بعلَمٍ يُطلب، ولا بعلَمٍ مخزَّنٍ من قبل،
#       ولا بتفويض. (G23 حارسُه في `review-fixes-e2e` حيث تُبنى شركةُ الحذف.)
#
#  ⚠️ **على قاعدةٍ منفصلة لا `DmsDb`** — والسكربت يكتب علَماً «قديماً» في القاعدة مباشرةً.
# ════════════════════════════════════════════════════════════════════════════
$ErrorActionPreference='Stop'; $pass=0; $fail=0
function Ok($m){ $script:pass++; Write-Host "  [نجح] $m" -ForegroundColor Green }
function Bad($m){ $script:fail++; Write-Host "  [فشل] $m" -ForegroundColor Red }
function Api($m,$u,$b,$t,$c){ $h=@{}; if($t){$h.Authorization="Bearer $t"}; if($c){$h."X-Company-Id"="$c"}
  $p=@{Uri="$Base$u";Method=$m;Headers=$h;ContentType="application/json; charset=utf-8"}
  if($null -ne $b){$p.Body=[Text.Encoding]::UTF8.GetBytes(($b|ConvertTo-Json -Depth 8 -Compress))}
  try{$r=Invoke-WebRequest @p -UseBasicParsing; $j=$null; $raw=$r.Content; if($raw){try{$j=$raw|ConvertFrom-Json}catch{}}; return @{S=[int]$r.StatusCode;B=$j;Raw=$raw}}
  catch{$resp=$_.Exception.Response; $code=if($resp){[int]$resp.StatusCode}else{0}; $ct=''; if($resp){$sr=[IO.StreamReader]::new($resp.GetResponseStream());$ct=$sr.ReadToEnd()}; $j=$null; if($ct){try{$j=$ct|ConvertFrom-Json}catch{}}; return @{S=$code;B=$j;Raw=$ct}}
}
function Expect($label,$actual,$expected){ if("$actual" -eq "$expected"){ Ok $label } else { Bad "$label (المتوقّع $expected والفعلي $actual)" } }
function Sql($sql){
  $cn=New-Object System.Data.SqlClient.SqlConnection($Db); $cn.Open()
  try{ $cmd=$cn.CreateCommand(); $cmd.CommandText=$sql; return $cmd.ExecuteScalar() } finally { $cn.Close() }
}
. "$PSScriptRoot\_activate.ps1"   # G19: الكلمة المؤقتة تُفعَّل قبل الاستعمال
$pwd0='Gaps@12345'
function Login($u){ $null=Enable-TempPassword $Base $u $pwd0; return (Api POST "/auth/login" @{username=$u;password=$pwd0} $null $null).B.accessToken }

# 🔴 **بصمةٌ لكل تشغيل** — عناوينُ وأرقامٌ لا تلتقط أثر تشغيلٍ سابق.
$mk=[guid]::NewGuid().ToString('N').Substring(0,6)

Write-Host "=== إعداد ===" -ForegroundColor Cyan
$admin=(Api POST "/auth/login" @{username='admin';password=$AdminPwd} $null $null).B.accessToken
if(-not $admin){ Bad "تعذّر دخول admin — هل شُغّل bootstrap-e2e أولاً؟"; exit 1 }
# ⚠️ **شركةٌ قائمة لا جديدة** — شركةٌ جديدة قد تسبق أبجدياً فتُسقط السكربتات بعدها (الدرس ٧).
#    ويُنشئها **إن غابت وحدها** (قاعدةٌ فارغة، تشغيلٌ منفرد) — نمط `case-files-e2e`.
$companies=@((Api GET "/companies" $null $admin $null).B)
if($companies.Count -lt 1){
  $null=Api POST "/companies" @{name="شركة الفجوات $mk";prefix="G$((Get-Random -Minimum 10 -Maximum 99))";isActive=$true} $admin $null
  $companies=@((Api GET "/companies" $null $admin $null).B)
}
if($companies.Count -lt 1){ Bad "تعذّر تجهيز شركة"; exit 1 }
$cid=[int]$companies[0].companyId
$ent=@((Api GET "/entities" $null $admin $cid).B) | Select-Object -First 1
if(-not $ent){ $ent=(Api POST "/entities" @{companyId=$cid;name="جهة $mk";kind='Both'} $admin $cid).B }
$eid=[int]$ent.entityId
$tpl=@((Api GET "/templates" $null $admin $cid).B) | Select-Object -First 1
if(-not $tpl){ $tpl=(Api POST "/templates" @{companyId=$cid;name="قالب $mk";watermarkOpacity=8;marginTop=24;marginRight=40;marginBottom=24;marginLeft=40;pageSize='A4';fontFamily='Amiri';isActive=$true} $admin $cid).B }
$tplId=[int]$tpl.templateId
Ok "الشركة $cid · الجهة $eid · القالب $tplId"

function UpsertUser($username,$role,$modules,[hashtable]$flags){
  $row=@{companyId=$cid;modules=$modules}
  foreach($k in $flags.Keys){ $row[$k]=$flags[$k] }
  $body=@{fullName="مستخدم $username";role=$role;isActive=$true;companies=@($row)}
  $ex=@((Api GET "/users" $null $admin $cid).B) | Where-Object { $_.username -eq $username } | Select-Object -First 1
  if($ex){ $r=Api PUT "/users/$($ex.userId)" $body $admin $cid }
  else { $body.username=$username; $body.password=$pwd0; $r=Api POST "/users" $body $admin $cid }
  if($r.S -ne 200){ Bad "تعذّر حفظ $username ($($r.S))"; exit 1 }
  return @((Api GET "/users" $null $admin $cid).B) | Where-Object { $_.username -eq $username } | Select-Object -First 1
}

$uIn  =UpsertUser 'gap_in'   'Employee' @('Incoming')             @{}
$uOut =UpsertUser 'gap_out'  'Employee' @('Outgoing')             @{}
$uBoth=UpsertUser 'gap_both' 'Employee' @('Incoming','Outgoing')  @{}
$tIn=Login 'gap_in'; $tOut=Login 'gap_out'; $tBoth=Login 'gap_both'
if($tIn -and $tOut -and $tBoth){ Ok "دخول الثلاثة" } else { Bad "تعذّر دخول أحدهم"; exit 1 }

# ════════════════ G20 ════════════════
Write-Host "`n=== G20) الردّ المرتبط لمن لا يملك قسمه — بالعدد وحده ===" -ForegroundColor Cyan
# الواردُ يُنشئه `gap_in` بنفسه فيراه (موظفٌ بلا قسم يرى ما أنشأه).
$inc=Api POST "/incoming" @{companyId=$cid;receivedDate='2026-09-01T00:00:00';entityId=$eid;subject="وارد الفجوات $mk";receiveMethod='Manual'} $tIn $cid
Expect "gap_in يُنشئ وارداً" $inc.S 200
$iid=[int]$inc.B.incomingId

$draft=Api POST "/outgoing" @{companyId=$cid;entityId=$eid;templateId=$tplId;date='2026-09-02T00:00:00'
  headerPhrase='إلى';signatoryName='المدير';signatoryTitle='المدير العام';subject="صادرٌ سرّيّ $mk"
  bodyHtml='<p>ردّ</p>';amount=$null;currency=$null;exchangeRate=$null;bodyJson=$null} $admin $cid
$ap=Api POST "/outgoing/$($draft.B.outgoingId)/approve" $null $admin $cid
Expect "صادرٌ معتمد للربط" $ap.S 200
$oid=[int]$ap.B.outgoingId; $onum="$($ap.B.number)"
$lk=Api POST "/incoming/$iid/link/$oid" $null $admin $cid
Expect "الربط: الصادر يردّ على الوارد" $lk.S 200

# ── صاحبُ الوارد بلا قسم الصادر ──
$dIn=Api GET "/incoming/$iid" $null $tIn $cid
Expect "gap_in يفتح وارده" $dIn.S 200
Expect "🔐 G20: لا يرى الردّ نفسه (بلا قسم الصادر)" @($dIn.B.replies).Count 0
Expect "🔐 G20: ويُعلَن أن ردّاً واحداً محجوب" $dIn.B.hiddenRepliesCount 1
if($onum -and $dIn.Raw -notmatch [regex]::Escape($onum)){ Ok "🔐 G20: ولا يتسرّب رقم الصادر ($onum) في الردّ" } else { Bad "رقم الصادر ظاهر لمن لا يملك قسمه" }
if($dIn.Raw -notmatch [regex]::Escape("صادرٌ سرّيّ $mk")){ Ok "🔐 G20: ولا موضوعه" } else { Bad "موضوع الصادر ظاهر لمن لا يملك قسمه" }
# 🔴 **الرقم كان يتسرّب من بابٍ ثانٍ** — «آخر إجراء» يُكتب نصّاً لحظة الربط («تم الرد بالصادر …»)،
#    وسجلُّ الحركة والإشعار كذلك. كشفه هذا الحارس نفسه بعد إصلاح `replies`: **طابِق الردّ الخامّ
#    كلَّه لا الحقل الذي أصلحتَه.**
$mv=Api GET "/incoming/$iid/movements" $null $tIn $cid
Expect "gap_in يقرأ سجلّ حركة وارده" $mv.S 200
if($onum -and $mv.Raw -notmatch [regex]::Escape($onum)){ Ok "🔐 G20: ولا يتسرّب رقم الصادر من سجلّ الحركة" } else { Bad "رقم الصادر ظاهر في سجلّ الحركة" }
$nt=Api GET "/notifications" $null $tIn $cid
if($onum -and $nt.Raw -notmatch [regex]::Escape($onum)){ Ok "🔐 G20: ولا من إشعار الردّ (يصل مَن سجّل الوارد)" } else { Bad "رقم الصادر ظاهر في الإشعار" }

# ── صاحبُ الصادر بلا قسم الوارد ──
$dOut=Api GET "/outgoing/$oid" $null $tOut $cid
Expect "gap_out يفتح الصادر (يرى صادر شركته — ADR-030)" $dOut.S 200
Expect "🔐 G20: لا يرى الوارد المردود عليه (بلا قسم الوارد)" @($dOut.B.repliesTo).Count 0
Expect "🔐 G20: ويُعلَن أن واحداً محجوب" $dOut.B.hiddenRepliesCount 1
if($dOut.Raw -notmatch [regex]::Escape("وارد الفجوات $mk")){ Ok "🔐 G20: ولا يتسرّب موضوع الوارد" } else { Bad "موضوع الوارد ظاهر لمن لا يملك قسمه" }

# ── صاحبُ القسمين والواردُ خارج حدّ قسمه — كان يُسقَط صامتاً ──
$dBoth=Api GET "/outgoing/$oid" $null $tBoth $cid
Expect "gap_both لا يرى وارداً لم يُنشئه ولم يُحَل إليه" @($dBoth.B.repliesTo).Count 0
Expect "🔴 G20: والمحجوب بحدّ القسم **يُعدّ** — كان يُسقَط صامتاً" $dBoth.B.hiddenRepliesCount 1

# ── مَن يملك الكلّ يرى الكلّ (ضابط: الحجب ليس عشوائياً) ──
$aIn=(Api GET "/incoming/$iid" $null $admin $cid).B
Expect "الأدمن يرى الردّ في الوارد" @($aIn.replies).Count 1
Expect "   وصفرُ محجوب" $aIn.hiddenRepliesCount 0
$aOut=(Api GET "/outgoing/$oid" $null $admin $cid).B
Expect "الأدمن يرى الوارد في الصادر" @($aOut.repliesTo).Count 1
Expect "   وصفرُ محجوب" $aOut.hiddenRepliesCount 0

# ════════════════ G22 ════════════════
Write-Host "`n=== G22) القارئ لا يعتمد ولا يدير الوارد ===" -ForegroundColor Cyan
$uRdr=UpsertUser 'gap_rdr' 'Reader' @('Incoming','Outgoing') @{canApprove=$true;canManageIncoming=$true;canViewAllIncoming=$true}
$acc=@($uRdr.companies) | Where-Object { $_.companyId -eq $cid } | Select-Object -First 1
Expect "🔐 G22: طلبُ «يعتمد» للقارئ لا يُخزَّن" $acc.canApprove 'False'
Expect "🔐 G22: وطلبُ «يدير الوارد» كذلك" $acc.canManageIncoming 'False'
Expect "   و«يرى كل الوارد» يبقى — قراءةٌ خالصة يحقّ له" $acc.canViewAllIncoming 'True'

# 🔴 **علَمٌ مخزَّنٌ من قبل** — إسناداتٌ حُفظت قبل الإصلاح قد تحمله. يُكتب في القاعدة مباشرةً.
$rid=[int]$uRdr.userId
$null=Sql "UPDATE UserCompanies SET CanApprove=1, CanManageIncoming=1 WHERE UserId=$rid AND CompanyId=$cid"
Expect "العلَمان مكتوبان في القاعدة (محاكاةُ بياناتٍ قديمة)" (Sql "SELECT CAST(CanApprove AS int)+CAST(CanManageIncoming AS int) FROM UserCompanies WHERE UserId=$rid AND CompanyId=$cid") 2
$tRdr=Login 'gap_rdr'
if(-not $tRdr){ Bad "تعذّر دخول القارئ"; exit 1 }

$me=(Api GET "/auth/me" $null $tRdr $cid).B
Expect "🔐 G22: /me للقارئ — لا يعتمد ولو حمل العلَم" $me.canApprove 'False'
Expect "🔐 G22: /me للقارئ — ولا يدير الوارد" $me.canManageIncoming 'False'

$d2=Api POST "/outgoing" @{companyId=$cid;entityId=$eid;templateId=$tplId;date='2026-09-03T00:00:00'
  headerPhrase='إلى';signatoryName='المدير';signatoryTitle='المدير العام';subject="مسودّة للقارئ $mk"
  bodyHtml='<p>م</p>';amount=$null;currency=$null;exchangeRate=$null;bodyJson=$null} $admin $cid
Expect "🔴 G22: القارئ بعلَمٍ مخزَّن **لا يعتمد** (403)" (Api POST "/outgoing/$($d2.B.outgoingId)/approve" $null $tRdr $cid).S 403
Expect "   والمسودّة باقيةٌ مسودّة" (Api GET "/outgoing/$($d2.B.outgoingId)" $null $admin $cid).B.status 'Draft'

$inc2=(Api POST "/incoming" @{companyId=$cid;receivedDate='2026-09-01T00:00:00';entityId=$eid;subject="وارد القارئ $mk";receiveMethod='Manual'} $admin $cid).B
Expect "🔴 G22: ولا يُغلق وارداً (جديد ← مغلق يحتاج «إدارة الوارد») — 403" (Api POST "/incoming/$($inc2.incomingId)/status" @{status='Closed';note='إغلاق'} $tRdr $cid).S 403

# ── التفويض ──
$dl=Api POST "/delegations" @{toUserId=$rid;startDate=(Get-Date).ToString('yyyy-MM-ddT00:00:00');endDate=$null} $admin $cid
Expect "🔐 G22: تفويضُ الاعتماد إلى قارئ **يُرفض صراحةً** (400)" $dl.S 400
# وتفويضٌ قائمٌ من قبل (قبل الإصلاح) يُتجاهل — يُكتب مباشرةً.
$null=Sql "INSERT INTO ApprovalDelegations (CompanyId,FromUserId,ToUserId,StartDate,EndDate,IsActive,CreatedByUserId,CreatedAt) SELECT $cid, UserId, $rid, DATEADD(day,-1,SYSUTCDATETIME()), NULL, 1, UserId, SYSUTCDATETIME() FROM Users WHERE Username='admin'"
Expect "🔴 G22: وتفويضٌ قائمٌ من قبل لا يمنحه الاعتماد (403)" (Api POST "/outgoing/$($d2.B.outgoingId)/approve" $null $tRdr $cid).S 403
$null=Sql "UPDATE ApprovalDelegations SET IsActive=0 WHERE ToUserId=$rid"

# ── ضابط: الموظف يُمنح العلَم ويعتمد (الإصلاح يخصّ القارئ وحده) ──
$uApr=UpsertUser 'gap_apr' 'Employee' @('Outgoing') @{canApprove=$true}
Expect "ضابط: «يعتمد» يُخزَّن للموظف" (@($uApr.companies) | Where-Object { $_.companyId -eq $cid } | Select-Object -First 1).canApprove 'True'
$tApr=Login 'gap_apr'
Expect "ضابط: والموظف صاحب العلَم يعتمد (200)" (Api POST "/outgoing/$($d2.B.outgoingId)/approve" $null $tApr $cid).S 200

Write-Host "`n============ النتيجة ============" -ForegroundColor Cyan
Write-Host "  نجح: $pass" -ForegroundColor Green
Write-Host "  فشل: $fail" -ForegroundColor $(if($fail){'Red'}else{'Green'})
exit $(if($fail){1}else{0})
