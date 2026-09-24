param([string]$AdminPwd='Admin@12345', [string]$Base='http://localhost:5091/api',
      [string]$Db='Server=.;Database=DmsE2E_New;Integrated Security=true;TrustServerCertificate=True')
# ════════════════════════════════════════════════════════════════════════════════════════
#  منع إنشاء الكتاب نفسه مرّتين (ADR-051) — ترويسة `Idempotency-Key`.
#
#  السيناريو: يصل الطلب ويُنشأ الكتاب، ثم ينقطع الاتصال قبل الردّ، فتبقى المسوّدة «لم تُرسَل»
#  ويُعاد إرسالها بعد العودة. والمطلوب: **يعود الكتابُ الأوّل ولا يُنشأ ثانٍ**.
#
#  يُثبت: ١) المفتاح نفسه مرّتين ⇒ الكيان نفسه (جهة · صادر · وارد · مهمة) وصفٌّ واحد في القاعدة ·
#  ٢) بلا مفتاح ⇒ إنشاءان (السلوك القديم لم يتغيّر) · ٣) المفتاح لكل مستخدم ·
#  ٤) مفتاحٌ لنوعٍ آخر ⇒ 400 · ٥) إنشاءٌ فاشل لا يحجز المفتاح · ٦) طلباتٌ متزامنة ⇒ كتابٌ واحد ·
#  ٧) مفتاحٌ مشوَّه ⇒ 400.
#
#  ⚠️ **على قاعدةٍ منفصلة لا `DmsDb`** — ويعدّ الصفوف من القاعدة مباشرةً.
# ════════════════════════════════════════════════════════════════════════════════════════
$ErrorActionPreference='Stop'; $pass=0; $fail=0
function Ok($m){ $script:pass++; Write-Host "  [نجح] $m" -ForegroundColor Green }
function Bad($m){ $script:fail++; Write-Host "  [فشل] $m" -ForegroundColor Red }
function Api($m,$u,$b,$t,$c,$key){ $h=@{}; if($t){$h.Authorization="Bearer $t"}; if($c){$h."X-Company-Id"="$c"}; if($key){$h."Idempotency-Key"=$key}
  $p=@{Uri="$Base$u";Method=$m;Headers=$h;ContentType="application/json; charset=utf-8"}
  if($null -ne $b){$p.Body=[Text.Encoding]::UTF8.GetBytes(($b|ConvertTo-Json -Depth 8 -Compress))}
  try{$r=Invoke-WebRequest @p -UseBasicParsing; $j=$null; if($r.Content){try{$j=$r.Content|ConvertFrom-Json}catch{}}; return @{S=[int]$r.StatusCode;B=$j}}
  catch{$resp=$_.Exception.Response; $code=if($resp){[int]$resp.StatusCode}else{0}; $ct=''; if($resp){$sr=[IO.StreamReader]::new($resp.GetResponseStream());$ct=$sr.ReadToEnd()}; $j=$null; if($ct){try{$j=$ct|ConvertFrom-Json}catch{}}; return @{S=$code;B=$j}}
}
function Expect($label,$actual,$expected){ if("$actual" -eq "$expected"){ Ok $label } else { Bad "$label (المتوقّع $expected والفعلي $actual)" } }
function SqlScalar($sql){
  $cn=New-Object System.Data.SqlClient.SqlConnection($Db); $cn.Open()
  try{ $cmd=$cn.CreateCommand(); $cmd.CommandText=$sql; return $cmd.ExecuteScalar() } finally { $cn.Close() }
}
function LoginR($u,$p){ return Api POST "/auth/login" @{username=$u;password=$p} $null $null }
function NewKey($suffix){ return "$([Guid]::NewGuid().ToString())`:$suffix" }

# ════════════════════════════ إعداد ════════════════════════════
Write-Host "`n=== إعداد ===" -ForegroundColor Cyan
$admin=(LoginR 'admin' $AdminPwd).B.accessToken
if(-not $admin){ Bad "فشل دخول admin"; exit 1 }
# ⚠️ **شركةٌ قائمة لا جديدة** — سكربتاتٌ بعده تأخذ أوّل شركةٍ أبجدياً (درس ٧).
$companies=@((Api GET "/companies" $null $admin $null).B)
if(-not $companies.Count){ Bad "لا شركة في القاعدة — شغّل review-fixes أوّلاً"; exit 1 }
$cid=$companies[0].companyId
$tpl=@((Api GET "/templates" $null $admin $cid).B) | Where-Object { $_.isActive } | Select-Object -First 1
if(-not $tpl){ $tpl=(Api POST "/templates" @{name="قالب التكرار";watermarkOpacity=8;marginTop=24;marginRight=40;marginBottom=24;marginLeft=40;pageSize='A4';fontFamily='Amiri';isActive=$true} $admin $cid).B }
if(-not $tpl.templateId){ Bad "تعذّر الحصول على قالب"; exit 1 }
$mk=Get-Random -Minimum 10000 -Maximum 99999
Ok "الشركة $cid · القالب $($tpl.templateId) · الوسم $mk"

# ════════════════════ ١) المفتاح نفسه مرّتين ⇒ الكيان نفسه ════════════════════
Write-Host "`n=== ١) المفتاح نفسه مرّتين ⇒ الكيان نفسه ===" -ForegroundColor Cyan

# الجهة الجديدة — تُنشأ قبل الكتاب، وكانت تتكرّر بلا أيّ فحص.
$kE=NewKey 'entity'; $ename="جهة التكرار $mk"
$e1=Api POST "/entities" @{name=$ename;kind='Both'} $admin $cid $kE
$e2=Api POST "/entities" @{name=$ename;kind='Both'} $admin $cid $kE
Expect "الجهة: الطلب الأوّل" $e1.S 200
Expect "الجهة: الثاني بالمفتاح نفسه يعيد الأولى" $e2.B.entityId $e1.B.entityId
Expect "   وفي القاعدة جهةٌ واحدة بهذا الاسم" ([int](SqlScalar "SELECT COUNT(*) FROM Entities WHERE Name=N'$ename'")) 1
$eid=$e1.B.entityId

# الصادر
$kO=NewKey 'outgoing'; $osub="صادر التكرار $mk"
$ob=@{entityId=$eid;templateId=$tpl.templateId;date=(Get-Date -Format 'yyyy-MM-dd');subject=$osub;bodyHtml='<p>نص</p>'}
$o1=Api POST "/outgoing" $ob $admin $cid $kO
$o2=Api POST "/outgoing" $ob $admin $cid $kO
Expect "الصادر: الطلب الأوّل" $o1.S 200
Expect "الصادر: الثاني يعيد الأوّل" $o2.B.outgoingId $o1.B.outgoingId
Expect "   وفي القاعدة صادرٌ واحد" ([int](SqlScalar "SELECT COUNT(*) FROM OutgoingBooks WHERE Subject=N'$osub'")) 1

# الوارد
$kI=NewKey 'incoming'; $isub="وارد التكرار $mk"
$ib=@{entityId=$eid;subject=$isub;receivedDate=(Get-Date -Format 'yyyy-MM-dd');receiveMethod='Manual'}
$i1=Api POST "/incoming" $ib $admin $cid $kI
$i2=Api POST "/incoming" $ib $admin $cid $kI
Expect "الوارد: الطلب الأوّل" $i1.S 200
Expect "الوارد: الثاني يعيد الأوّل" $i2.B.incomingId $i1.B.incomingId
Expect "   وفي القاعدة واردٌ واحد (رقمٌ واحد مُستهلَك)" ([int](SqlScalar "SELECT COUNT(*) FROM IncomingBooks WHERE Subject=N'$isub'")) 1

# المهمة
$kT=NewKey 'task'; $ttl="مهمة التكرار $mk"; $due=(Get-Date).AddDays(3).ToString('yyyy-MM-dd')
$tb=@{title=$ttl;taskType='Individual';priority='Normal';dueDate=$due}
$t1=Api POST "/tasks" $tb $admin $cid $kT
$t2=Api POST "/tasks" $tb $admin $cid $kT
Expect "المهمة: الطلب الأوّل" $t1.S 200
Expect "المهمة: الثانية تعيد الأولى" $t2.B.taskId $t1.B.taskId
Expect "   وفي القاعدة مهمةٌ واحدة" ([int](SqlScalar "SELECT COUNT(*) FROM DmsTasks WHERE Title=N'$ttl'")) 1

# ════════════════════ ٢) بلا مفتاح ⇒ السلوك القديم ════════════════════
Write-Host "`n=== ٢) بلا مفتاح ⇒ إنشاءان كما كان ===" -ForegroundColor Cyan
$nsub="بلا مفتاح $mk"
$null=Api POST "/outgoing" (@{entityId=$eid;templateId=$tpl.templateId;date=(Get-Date -Format 'yyyy-MM-dd');subject=$nsub;bodyHtml='<p>ن</p>'}) $admin $cid
$null=Api POST "/outgoing" (@{entityId=$eid;templateId=$tpl.templateId;date=(Get-Date -Format 'yyyy-MM-dd');subject=$nsub;bodyHtml='<p>ن</p>'}) $admin $cid
Expect "طلبان بلا مفتاح ⇒ صادران" ([int](SqlScalar "SELECT COUNT(*) FROM OutgoingBooks WHERE Subject=N'$nsub'")) 2

# ════════════════════ ٣) المفتاح لكل مستخدم ════════════════════
Write-Host "`n=== ٣) المفتاح لكل مستخدم لا للنظام ===" -ForegroundColor Cyan
$uname="dr_emp$mk"; $upwd='Dr@123456'
$link=@{companyId=$cid;modules=@('Outgoing','Incoming');departmentId=$null;canApprove=$false;canManageIncoming=$false
        canViewAllIncoming=$false;canManageEmployees=$false;canManagePayroll=$false;canAmendPaidPayroll=$false;canManageTasks=$false}
$null=Api POST "/users" @{username=$uname;password=$upwd;fullName="موظف التكرار";role='Employee';isActive=$true;companies=@($link)} $admin $null
. "$PSScriptRoot\_activate.ps1"   # G19: الكلمة المؤقتة تُفعَّل قبل الاستعمال
$null=Enable-TempPassword $Base $uname $upwd
$emp=(LoginR $uname $upwd).B.accessToken
if(-not $emp){ Bad "فشل دخول الموظف"; exit 1 }
$e3=Api POST "/entities" @{name="$ename-موظف";kind='Both'} $emp $cid $kE
Expect "مستخدمٌ آخر بالمفتاح نفسه ⇒ ينشئ جهته" $e3.S 200
if($e3.B.entityId -and $e3.B.entityId -ne $e1.B.entityId){ Ok "   وهي غير جهة المدير ($($e3.B.entityId))" } else { Bad "   أعاد جهة مستخدمٍ آخر!" }

# ════════════════════ ٤) مفتاحٌ لنوعٍ آخر ════════════════════
Write-Host "`n=== ٤) مفتاحُ الصادر على الوارد ⇒ 400 ===" -ForegroundColor Cyan
Expect "مفتاحٌ واحد لا يخدم نوعين" (Api POST "/incoming" $ib $admin $cid $kO).S 400

# ════════════════════ ٥) الفشل لا يحجز المفتاح ════════════════════
Write-Host "`n=== ٥) إنشاءٌ فاشل لا يحجز المفتاح ===" -ForegroundColor Cyan
$kF=NewKey 'outgoing'; $fsub="بعد الفشل $mk"
$bad=@{entityId=$eid;templateId=$tpl.templateId;date=(Get-Date -Format 'yyyy-MM-dd');subject='';bodyHtml='<p>ن</p>'}
$r=Api POST "/outgoing" $bad $admin $cid $kF
Expect "طلبٌ بلا موضوع ⇒ 400" $r.S 400
Expect "   ولم يبقَ له حجز" ([int](SqlScalar "SELECT COUNT(*) FROM ClientRequests WHERE [Key]='$kF'")) 0
$good=@{entityId=$eid;templateId=$tpl.templateId;date=(Get-Date -Format 'yyyy-MM-dd');subject=$fsub;bodyHtml='<p>ن</p>'}
$r=Api POST "/outgoing" $good $admin $cid $kF
Expect "   والمفتاح نفسه بعد التصحيح ينجح" $r.S 200

# ════════════════════ ٦) طلباتٌ متزامنة ════════════════════
Write-Host "`n=== ٦) خمسة طلباتٍ متزامنة بالمفتاح نفسه ⇒ كتابٌ واحد ===" -ForegroundColor Cyan
$kC=NewKey 'incoming'; $csub="متزامن $mk"
$payload=[Text.Encoding]::UTF8.GetBytes((@{entityId=$eid;subject=$csub;receivedDate=(Get-Date -Format 'yyyy-MM-dd');receiveMethod='Manual'}|ConvertTo-Json -Compress))
# ⚠️ **متزامنةٌ فعلاً** — `Start-Job` يُطلق كلَّ طلبٍ بعد ثانيةٍ من سابقه فلا يختبر السباق.
#    `HttpClient.SendAsync` يُطلق الخمسة معاً ثم ينتظرها.
Add-Type -AssemblyName System.Net.Http
$http=[System.Net.Http.HttpClient]::new()
$tasks=1..5 | ForEach-Object {
  $req=[System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Post,"$Base/incoming")
  $req.Headers.Add('Authorization',"Bearer $admin"); $req.Headers.Add('X-Company-Id',"$cid"); $req.Headers.Add('Idempotency-Key',$kC)
  $req.Content=[System.Net.Http.ByteArrayContent]::new($payload)
  $req.Content.Headers.ContentType=[System.Net.Http.Headers.MediaTypeHeaderValue]::Parse('application/json; charset=utf-8')
  $http.SendAsync($req)
}
[System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]$tasks)
$codes=@($tasks | ForEach-Object { "$([int]$_.Result.StatusCode)" }); $http.Dispose()
$okN=@($codes | Where-Object { $_ -eq '200' }).Count
$busyN=@($codes | Where-Object { $_ -eq '409' }).Count
if($okN -ge 1 -and ($okN + $busyN) -eq 5){ Ok "الردود: $okN نجاح · $busyN «قيد المعالجة» ($($codes -join ','))" } else { Bad "ردودٌ غير متوقّعة: $($codes -join ',')" }
Expect "   وفي القاعدة واردٌ واحد" ([int](SqlScalar "SELECT COUNT(*) FROM IncomingBooks WHERE Subject=N'$csub'")) 1

# ════════════════════ ٧) مفتاحٌ مشوَّه ════════════════════
Write-Host "`n=== ٧) مفتاحٌ مشوَّه ⇒ 400 ===" -ForegroundColor Cyan
Expect "مفتاحٌ بفراغ" (Api POST "/entities" @{name="x$mk";kind='Both'} $admin $cid 'bad key').S 400
Expect "مفتاحٌ أطول من 80" (Api POST "/entities" @{name="y$mk";kind='Both'} $admin $cid ('a'*81)).S 400

Write-Host "`n══════ النتيجة: $pass نجح · $fail فشل ══════" -ForegroundColor $(if($fail){'Red'}else{'Green'})
if($fail){ exit 1 }
