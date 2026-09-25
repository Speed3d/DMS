param([string]$AdminPwd='Admin@12345', [string]$Base='http://localhost:5091/api',
      [string]$Db='Server=.;Database=DmsE2E_New;Integrated Security=true;TrustServerCertificate=True')
# ════════════════════════════════════════════════════════════════════════════
#  سجلّ حركة الصادر وصورة السوبر أدمن (ADR-056 — طلب المالك 2026-09-25):
#   - «أحمد ينشئ كتاباً، وسنان لا يعدّله، وأحمد أو الرئيس أو السوبر أدمن يعدّلون» — **ويُسجَّل كلُّ ذلك**:
#     الإنشاء · التعديل بأسماء الحقول · الاعتماد · التعديل بعد الاعتماد · الربط وفكّه · الحذف.
#   - 🔐 القارئ لا يرى السجلّ (كالوارد) · ورقم الوارد المرتبط لمن يراه وحده (G20).
#   - 👤 السوبر أدمن بلا بطاقة يغيّر صورته (على حسابه) — وغيرُه بلا بطاقة لا.
#  ⚠️ على قاعدةٍ منفصلة لا `DmsDb`.
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
function Sql($sql){ $cn=New-Object System.Data.SqlClient.SqlConnection($Db); $cn.Open()
  try{ $cmd=$cn.CreateCommand(); $cmd.CommandText=$sql; return $cmd.ExecuteScalar() } finally { $cn.Close() } }
function UploadPhoto($token,$company,$name){
  $b=[Guid]::NewGuid().ToString()
  $png=[Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==')
  $pre=[Text.Encoding]::UTF8.GetBytes("--$b`r`nContent-Disposition: form-data; name=`"file`"; filename=`"$name`"`r`nContent-Type: image/png`r`n`r`n")
  $post=[Text.Encoding]::UTF8.GetBytes("`r`n--$b--`r`n")
  $body=New-Object byte[] ($pre.Length+$png.Length+$post.Length)
  [Array]::Copy($pre,0,$body,0,$pre.Length); [Array]::Copy($png,0,$body,$pre.Length,$png.Length)
  [Array]::Copy($post,0,$body,$pre.Length+$png.Length,$post.Length)
  $h=@{Authorization="Bearer $token"}; if($company){$h.'X-Company-Id'="$company"}
  try{ $r=Invoke-WebRequest -Uri "$Base/profile/photo" -Method Post -Headers $h -ContentType "multipart/form-data; boundary=$b" -Body $body -UseBasicParsing; return [int]$r.StatusCode }
  catch{ $resp=$_.Exception.Response; if($resp){return [int]$resp.StatusCode} else {return 0} }
}
. "$PSScriptRoot\_activate.ps1"
$pwd0='OutLog@12345'
function Login($u){ $null=Enable-TempPassword $Base $u $pwd0; return (Api POST "/auth/login" @{username=$u;password=$pwd0} $null $null).B.accessToken }
$mk=[guid]::NewGuid().ToString('N').Substring(0,6)

Write-Host "=== إعداد ===" -ForegroundColor Cyan
$admin=(Api POST "/auth/login" @{username='admin';password=$AdminPwd} $null $null).B.accessToken
if(-not $admin){ Bad "تعذّر دخول admin — هل شُغّل bootstrap-e2e أولاً؟"; exit 1 }
$companies=@((Api GET "/companies" $null $admin $null).B)
if($companies.Count -lt 1){
  $null=Api POST "/companies" @{name="شركة السجلّ $mk";prefix="L$((Get-Random -Minimum 10 -Maximum 99))";isActive=$true} $admin $null
  $companies=@((Api GET "/companies" $null $admin $null).B)
}
$cid=[int]$companies[0].companyId
$cid2=if($companies.Count -ge 2){[int]$companies[1].companyId}else{0}
$ent=@((Api GET "/entities" $null $admin $cid).B) | Select-Object -First 1
if(-not $ent){ $ent=(Api POST "/entities" @{companyId=$cid;name="جهة $mk";kind='Both'} $admin $cid).B }
$tpl=@((Api GET "/templates" $null $admin $cid).B) | Select-Object -First 1
if(-not $tpl){ $tpl=(Api POST "/templates" @{companyId=$cid;name="قالب $mk";watermarkOpacity=8;marginTop=24;marginRight=40;marginBottom=24;marginLeft=40;pageSize='A4';fontFamily='Amiri';isActive=$true} $admin $cid).B }
$eid=[int]$ent.entityId; $tplId=[int]$tpl.templateId

function UpsertUser($username,$role,$modules){
  $body=@{fullName="مستخدم $username";role=$role;isActive=$true;companies=@(@{companyId=$cid;modules=$modules})}
  $ex=@((Api GET "/users" $null $admin $cid).B) | Where-Object { $_.username -eq $username } | Select-Object -First 1
  if($ex){ $null=Api PUT "/users/$($ex.userId)" $body $admin $cid } else { $body.username=$username; $body.password=$pwd0; $null=Api POST "/users" $body $admin $cid }
}
UpsertUser 'log_ahmed' 'Employee' @('Outgoing','Incoming')
UpsertUser 'log_sinan' 'Employee' @('Outgoing')
UpsertUser 'log_rdr'   'Reader'   @('Outgoing')
$tA=Login 'log_ahmed'; $tS=Login 'log_sinan'; $tR=Login 'log_rdr'
if($tA -and $tS -and $tR){ Ok "دخول الثلاثة (أحمد · سنان · قارئ)" } else { Bad "تعذّر دخول أحدهم"; exit 1 }

function Draft($subject,$amount){ @{companyId=$cid;entityId=$eid;templateId=$tplId;date='2026-09-25T00:00:00'
  headerPhrase='إلى';signatoryName='المدير';signatoryTitle='المدير العام';subject=$subject;bodyHtml='<p>نص</p>'
  amount=$amount;currency='IQD';exchangeRate=$null;bodyJson=$null} }
function Moves($id,$tok){ Api GET "/outgoing/$id/movements" $null $tok $cid }

Write-Host "`n=== ١) أحمد ينشئ · سنان لا يعدّل · أحمد يعدّل — وكلُّه مسجَّل ===" -ForegroundColor Cyan
$d=Api POST "/outgoing" (Draft "كتاب أحمد $mk" 100) $tA $cid
Expect "أحمد ينشئ مسودّة" $d.S 200
$oid=[int]$d.B.outgoingId
$m=Moves $oid $tA
Expect "السجلّ فيه حركة الإنشاء" @($m.B).Count 1
Expect "   بإجراء Created" @($m.B)[0].action 'Created'
if("$(@($m.B)[0].performedByUserName)" -match 'log_ahmed'){ Ok "   ومنفّذها أحمد" } else { Bad "   المنفّذ: $(@($m.B)[0].performedByUserName)" }

Expect "سنان لا يعدّل كتاب أحمد (403 — كما كان)" (Api PUT "/outgoing/$oid" (Draft "تلاعب $mk" 999) $tS $cid).S 403
Expect "   ولا حركةَ لمحاولةٍ مرفوضة" @((Moves $oid $tA).B).Count 1

$u=Api PUT "/outgoing/$oid" (Draft "كتاب أحمد المعدّل $mk" 250) $tA $cid
Expect "أحمد يعدّل مسودّته" $u.S 200
$m=@((Moves $oid $tA).B)
Expect "   حركة التعديل سُجّلت" $m[1].action 'Edited'
if("$($m[1].description)" -match 'الموضوع' -and "$($m[1].description)" -match 'المبلغ' -and "$($m[1].description)" -notmatch 'المتن'){ Ok "   وتسمّي ما تغيّر وحده (الموضوع · المبلغ): $($m[1].description)" } else { Bad "   الوصف: $($m[1].description)" }

Write-Host "`n=== ٢) الاعتماد · التعديل بعده · الربط وفكّه ===" -ForegroundColor Cyan
$ap=Api POST "/outgoing/$oid/approve" $null $admin $cid
Expect "السوبر أدمن يعتمد" $ap.S 200
$num="$($ap.B.number)"
$m=@((Moves $oid $admin).B)
Expect "   حركة الاعتماد" $m[-1].action 'Approved'
if("$($m[-1].description)" -match [regex]::Escape($num)){ Ok "   بالرقم الرسميّ ($num)" } else { Bad "   الوصف: $($m[-1].description)" }

$cur=(Api GET "/outgoing/$oid" $null $admin $cid).B
$ea=Draft "كتاب أحمد بعد الاعتماد $mk" 250; $ea.Remove('companyId'); $ea.rowVersion=$cur.rowVersion; $ea.changeNote='تصحيح العنوان'
Expect "التعديل بعد الاعتماد" (Api PUT "/outgoing/$oid/edit-approved" $ea $admin $cid).S 200
$m=@((Moves $oid $admin).B)
Expect "   حركته سُجّلت" $m[-1].action 'EditedApproved'
if("$($m[-1].description)" -match 'الإصدار 1' -and "$($m[-1].description)" -match 'تصحيح العنوان'){ Ok "   برقم الإصدار وملاحظة التعديل" } else { Bad "   الوصف: $($m[-1].description)" }

$inc=(Api POST "/incoming" @{companyId=$cid;receivedDate='2026-09-20T00:00:00';entityId=$eid;subject="وارد السجلّ $mk";receiveMethod='Manual'} $admin $cid).B
$incNum="$($inc.incomingNumber)"
Expect "الربط بوارد" (Api POST "/incoming/$($inc.incomingId)/link/$oid" $null $admin $cid).S 200
$m=@((Moves $oid $admin).B)
Expect "   حركة الربط في سجلّ الصادر" $m[-1].action 'LinkedIncoming'
Expect "   ورقم الوارد لمن يراه (الأدمن)" $m[-1].relatedIncomingNumber $incNum

# 🔐 سنان: بلا قسم الوارد ⇒ الحركة بوصفها المحايد، **بلا رقمٍ ولا معرّف** (G20).
$ms=Moves $oid $tS
Expect "سنان يرى سجلّ الكتاب (يملك الصادر)" $ms.S 200
$last=@($ms.B)[-1]
Expect "🔐 وحركة الربط بلا رقم الوارد له" ([string]::IsNullOrEmpty("$($last.relatedIncomingNumber)")) 'True'
if($ms.Raw -notmatch [regex]::Escape($incNum)){ Ok "🔐 ولا يتسرّب رقم الوارد في الردّ كلِّه" } else { Bad "رقم الوارد ظاهر لسنان" }

Expect "فكّ الربط" (Api DELETE "/incoming/$($inc.incomingId)/link/$oid" $null $admin $cid).S 200
Expect "   حركة فكّ الربط" @((Moves $oid $admin).B)[-1].action 'UnlinkedIncoming'

Write-Host "`n=== ٣) مَن يرى السجلّ ===" -ForegroundColor Cyan
Expect "🔐 القارئ لا يرى سجلّ الصادر (403 — كالوارد)" (Moves $oid $tR).S 403
if($cid2){ Expect "🔐 ولا يُقرأ سجلُّ كتابٍ من شركةٍ أخرى (404)" (Api GET "/outgoing/$oid/movements" $null $admin $cid2).S 404 }
Expect "والترتيب زمنيّ: الإنشاء أوّلاً" @((Moves $oid $admin).B)[0].action 'Created'

Write-Host "`n=== ٤) الحذف يُسجَّل ===" -ForegroundColor Cyan
$d2=(Api POST "/outgoing" (Draft "مسودّة للحذف $mk" $null) $tA $cid).B
Expect "أحمد يحذف مسودّته" (Api DELETE "/outgoing/$($d2.outgoingId)" $null $tA $cid).S 204
Expect "🔑 حركة الحذف في القاعدة (والكتاب لم يعُد يُرى)" ([int](Sql "SELECT COUNT(*) FROM OutgoingMovements WHERE OutgoingId=$($d2.outgoingId) AND Action='Deleted'")) 1

Write-Host "`n=== ٥) صورة السوبر أدمن (بلا بطاقة) ===" -ForegroundColor Cyan
$me=(Api GET "/profile" $null $admin $null).B
Expect "السوبر أدمن بلا بطاقة موظف" ([string]::IsNullOrEmpty("$($me.employeeId)")) 'True'
Expect "👤 ويُسمح له بتغيير صورته (canChangePhoto)" $me.canChangePhoto 'True'
Expect "👤 يرفع صورته" (UploadPhoto $admin $null 'admin.png') 204
Expect "   فتصير له صورة" (Api GET "/profile" $null $admin $null).B.hasPhoto 'True'
Expect "   ويقرؤها" (Api GET "/profile/photo" $null $admin $null).S 200
Expect "   ومحفوظةٌ على حسابه" ([string]::IsNullOrEmpty("$(Sql "SELECT PhotoBlobKey FROM Users WHERE Username='admin'")")) 'False'

$meS=(Api GET "/profile" $null $tS $cid).B
Expect "🔐 موظفٌ بلا بطاقة لا يغيّر صورته (قرار المالك: للسوبر أدمن وحده)" $meS.canChangePhoto 'False'
Expect "   والخادم يرفض فعلاً (404)" (UploadPhoto $tS $cid 'x.png') 404

Write-Host "`n============ النتيجة ============" -ForegroundColor Cyan
Write-Host "  نجح: $pass" -ForegroundColor Green
Write-Host "  فشل: $fail" -ForegroundColor $(if($fail){'Red'}else{'Green'})
exit $(if($fail){1}else{0})
