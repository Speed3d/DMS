param([string]$AdminPwd='Admin@12345', [string]$Base='http://localhost:5091/api',
      [string]$Db='Server=.;Database=DmsE2E_New;Integrated Security=true;TrustServerCertificate=True')
# ════════════════════════════════════════════════════════════════════════════
#  ترقيم الصادر (ADR-064 — طلب المالك 2026-10-20، وإصلاحاته 0.18.1):
#   - حذفُ آخر كتابٍ معتمد يُرجع العداد · والرقم المحذوف يُعاد استعماله (الفهرس الفريد يتجاهل المحذوف).
#   - حذفُ كتابٍ في الوسط لا يمسّ العداد · والفجوة تُملأ يدوياً ويبقى العداد كما هو.
#   - الرقم اليدوي فوق العداد يرفعه · والمستعمل 409 · والصفر 400.
#   - 🔴 معتمِدان بالرقم اليدوي نفسه في اللحظة نفسها ⟵ واحدٌ 200 والآخر 409 **لا 500**.
#   - 🔴 ختمُ الكتاب المحذوف لا يُقال عنه «صادرٌ فعلاً» ولو أخذ كتابٌ حيّ رقمه.
#  ⚠️ على قاعدةٍ منفصلة لا `DmsDb` — ويُنشئ شركةً خاصّة به (اسمها يبدأ بـ«ي» فلا تسبق شركتي السكربتات أبجدياً).
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

$mk=[guid]::NewGuid().ToString('N').Substring(0,6)
Write-Host "=== إعداد: شركةٌ جديدة بعدادٍ صفر ===" -ForegroundColor Cyan
$admin=(Api POST "/auth/login" @{username='admin';password=$AdminPwd} $null $null).B.accessToken
if(-not $admin){ Bad "تعذّر دخول admin — هل شُغّل bootstrap-e2e أولاً؟"; exit 1 }
$prefix="N$((Get-Random -Minimum 100 -Maximum 999))"
$co=Api POST "/companies" @{name="يترقيم $mk";prefix=$prefix;isActive=$true} $admin $null
Expect "إنشاء شركة الترقيم ($prefix)" $co.S 200
$cid=[int]$co.B.companyId
$eid=[int](Api POST "/entities" @{companyId=$cid;name="جهة الترقيم $mk";kind='Both'} $admin $cid).B.entityId
$tplId=[int](Api POST "/templates" @{companyId=$cid;name="قالب $mk";watermarkOpacity=8;marginTop=24;marginRight=40;marginBottom=24;marginLeft=40;pageSize='A4';fontFamily='Amiri';isActive=$true} $admin $cid).B.templateId
$year=[int](Api GET "/outgoing/numbering-info" $null $admin $cid).B.year
function N($s){ "$prefix-$year-$('{0:D5}' -f $s)" }
function Counter(){ [int](Sql "SELECT ISNULL((SELECT LastNumber FROM Counters WHERE CompanyId=$cid AND [Year]=$year AND [Type]='Outgoing'),0)") }
function NewDraft($subject){ [int](Api POST "/outgoing" @{companyId=$cid;entityId=$eid;templateId=$tplId;date="$year-10-20T00:00:00"
  headerPhrase='إلى';signatoryName='المدير';signatoryTitle='المدير العام';subject=$subject;bodyHtml='<p>نص</p>'
  amount=1000;currency='IQD';exchangeRate=$null;bodyJson=$null} $admin $cid).B.outgoingId }
function Approve($id,$manual){ $b=if($null -ne $manual){@{manualSerial=$manual}}else{$null}; Api POST "/outgoing/$id/approve" $b $admin $cid }
function DeleteBook($id){ (Api DELETE "/outgoing/$id" $null $admin $cid).S }
function Check($s){ (Api GET "/outgoing/check-serial?serial=$s" $null $admin $cid).B }

$ni=(Api GET "/outgoing/numbering-info" $null $admin $cid).B
Expect "العداد يبدأ صفراً" $ni.currentCounter 0
Expect "   والتالي 1" $ni.nextSerial 1

Write-Host "`n=== ١) حذف آخر كتاب يُرجع العداد والرقم يُعاد ===" -ForegroundColor Cyan
$a=NewDraft "أ $mk"; $b=NewDraft "ب $mk"; $c=NewDraft "ج $mk"
Expect "اعتماد أ ⟵ 1" (Approve $a $null).B.number (N 1)
Expect "اعتماد ب ⟵ 2" (Approve $b $null).B.number (N 2)
Expect "اعتماد ج ⟵ 3" (Approve $c $null).B.number (N 3)
$qrC=[string](Sql "SELECT QrContent FROM OutgoingBooks WHERE OutgoingId=$c")
Expect "حذف ج (آخر كتاب)" (DeleteBook $c) 204
Expect "   العداد رجع إلى 2" (Counter) 2
Expect "   وسطر تدقيق CounterRollback" ([int](Sql "SELECT COUNT(*) FROM AuditLogs WHERE Action='CounterRollback' AND CompanyId=$cid")) 1
$d=NewDraft "د $mk"
Expect "اعتماد د تلقائياً يأخذ رقم ج المحذوف" (Approve $d $null).B.number (N 3)
Expect "   صفّان بالرقم نفسه في القاعدة (المحذوف والحيّ)" ([int](Sql "SELECT COUNT(*) FROM OutgoingBooks WHERE Number='$(N 3)'")) 2

Write-Host "`n=== ٢) 🔴 ختم الكتاب المحذوف بعد إعادة رقمه ===" -ForegroundColor Cyan
$vC=Api POST "/verify" @{qrContent=$qrC} $null $null
if($vC.S -eq 200 -and $vC.B.verdict -eq 'Withdrawn' -and -not $vC.B.foundInDb -and $vC.B.isValid){ Ok "ختم ج المحذوف ⟵ Withdrawn ولو حمل د رقمه" } else { Bad "ختم ج: $($vC.S) $($vC.B.verdict) foundInDb=$($vC.B.foundInDb)" }
$qrD=[string](Sql "SELECT QrContent FROM OutgoingBooks WHERE OutgoingId=$d")
$vD=Api POST "/verify" @{qrContent=$qrD} $null $null
if($vD.B.verdict -eq 'Genuine' -and $vD.B.foundInDb){ Ok "وختم د الحيّ ⟵ Genuine" } else { Bad "ختم د: $($vD.B.verdict)" }
$vT=Api POST "/verify" @{qrContent=($qrD.Substring(0,30)+'X'+$qrD.Substring(31))} $null $null
Expect "والمزوَّر ⟵ Tampered كما كان" $vT.B.verdict 'Tampered'

Write-Host "`n=== ٣) حذفٌ في الوسط · الفجوة · الفحص اللحظي ===" -ForegroundColor Cyan
Expect "حذف ب (في الوسط)" (DeleteBook $b) 204
Expect "   العداد يبقى 3" (Counter) 3
Expect "فحص 2 ⟵ فجوة" (Check 2).status 'AvailableGap'
Expect "فحص 3 ⟵ مستعمل" (Check 3).status 'AlreadyUsed'
Expect "فحص 4 ⟵ التالي" (Check 4).status 'AvailableNext'
Expect "فحص 10 ⟵ فوق العداد" (Check 10).status 'AvailableAboveCounter'
Expect "فحص 0 ⟵ 400" (Api GET "/outgoing/check-serial?serial=0" $null $admin $cid).S 400
$e=NewDraft "هـ $mk"
Expect "اعتماد هـ يدوياً بالفجوة 2" (Approve $e 2).B.number (N 2)
Expect "   والعداد باقٍ 3" (Counter) 3
$f=NewDraft "و $mk"
Expect "اعتماد و تلقائياً ⟵ 4" (Approve $f $null).B.number (N 4)

Write-Host "`n=== ٤) المستعمل والصفر والقفزة ===" -ForegroundColor Cyan
$g=NewDraft "ز $mk"
$r=Approve $g 3
Expect "يدويٌّ مستعمل ⟵ 409" $r.S 409
if("$($r.B.error)" -match [regex]::Escape((N 3))){ Ok "   برسالةٍ تسمّي الرقم: $($r.B.error)" } else { Bad "   الرسالة: $($r.Raw)" }
Expect "   والكتاب باقٍ مسودّة" ([int](Sql "SELECT Status FROM OutgoingBooks WHERE OutgoingId=$g")) 0
Expect "يدويٌّ صفر ⟵ 400" (Approve $g 0).S 400
Expect "اعتماد ز يدوياً بـ10 (قفزة)" (Approve $g 10).B.number (N 10)
Expect "   العداد ارتفع إلى 10" (Counter) 10
$h=NewDraft "ح $mk"
Expect "التلقائي بعدها ⟵ 11" (Approve $h $null).B.number (N 11)
Expect "حذف ح (11)" (DeleteBook $h) 204
Expect "   العداد ⟵ 10" (Counter) 10
Expect "حذف ز (10)" (DeleteBook $g) 204
Expect "   العداد ⟵ أعلى حيّ باقٍ (4) لا 9" (Counter) 4
$dr=NewDraft "مسودّة $mk"
Expect "حذف مسودّة" (DeleteBook $dr) 204
Expect "   لا يمسّ العداد" (Counter) 4

Write-Host "`n=== ٥) 🔴 معتمِدان بالرقم اليدوي نفسه في اللحظة نفسها ===" -ForegroundColor Cyan
$x=NewDraft "س $mk"; $y=NewDraft "ص $mk"
Add-Type -AssemblyName System.Net.Http
$hc=[System.Net.Http.HttpClient]::new()
$hc.DefaultRequestHeaders.Authorization=[System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer',$admin)
$hc.DefaultRequestHeaders.Add('X-Company-Id',"$cid")
$tasks=@($x,$y) | ForEach-Object {
  $hc.PostAsync("$Base/outgoing/$_/approve", [System.Net.Http.StringContent]::new('{"manualSerial":20}',[Text.Encoding]::UTF8,'application/json')) }
[System.Threading.Tasks.Task]::WaitAll($tasks)
$codes=@($tasks | ForEach-Object { [int]$_.Result.StatusCode } | Sort-Object)
Expect "واحدٌ 200 والآخر 409 (لا 500)" ($codes -join ',') '200,409'
Expect "   وكتابٌ حيّ واحد برقم 20" ([int](Sql "SELECT COUNT(*) FROM OutgoingBooks WHERE CompanyId=$cid AND SerialNo=20 AND IsDeleted=0")) 1
Expect "   والعداد 20" (Counter) 20
$hc.Dispose()

Write-Host "`n=== النتيجة: نجح $pass · فشل $fail ===" -ForegroundColor $(if($fail){'Red'}else{'Green'})
if($fail){ exit 1 }
