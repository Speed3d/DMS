param([string]$AdminPwd='Admin@12345', [string]$Base='http://localhost:5091/api',
      [string]$Db='Server=.;Database=DmsE2E_New;Integrated Security=true;TrustServerCertificate=True')
# ════════════════════════════════════════════════════════════════════════════
#  الجداول داخل الكتاب الصادر · أنواع الصادر · خيارات الطباعة (ADR-057 — الإصدار 0.12.0):
#   - أنواع الصادر: البذر الثلاثيّ · الإنشاء والتكرار (409) · الحذف وهو مستعمل (409) · الكتابة للمدير فأعلى.
#   - كتابٌ بجدول فاتورة بالشكل الذي تحفظه الواجهة نفسه (`<div data-dms-table="…">`) ⟵ معاينة · حفظ · تفاصيل.
#   - 🔐 **الخادم حَكَمُ الطباعة**: جدولٌ معطوب ⟵ 400 بالعربية بلا أثر · **والجمع يُعاد حسابه** ولو أرسل العميل رقماً مزوّراً.
#   - سجلّ الحركة المفصّل (القديم والجديد) · فلتر النوع · **دورة الاعتماد كما هي** (الرقم والتاريخ والـPDF عند الاعتماد وحده).
#   - Word طبق الأصل (المسودّة والمعتمد) · التعديل بعد الاعتماد · القارئ كما هو.
#  ⚠️ على قاعدةٍ منفصلة لا `DmsDb`.
# ════════════════════════════════════════════════════════════════════════════
$ErrorActionPreference='Stop'; $pass=0; $fail=0
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
function Ok($m){ $script:pass++; Write-Host "  [نجح] $m" -ForegroundColor Green }
function Bad($m){ $script:fail++; Write-Host "  [فشل] $m" -ForegroundColor Red }
function Api($m,$u,$b,$t,$c){ $h=@{}; if($t){$h.Authorization="Bearer $t"}; if($c){$h."X-Company-Id"="$c"}
  $p=@{Uri="$Base$u";Method=$m;Headers=$h;ContentType="application/json; charset=utf-8"}
  if($null -ne $b){$p.Body=[Text.Encoding]::UTF8.GetBytes(($b|ConvertTo-Json -Depth 20 -Compress))}
  try{$r=Invoke-WebRequest @p -UseBasicParsing; $j=$null; $raw=$r.Content; if($raw -is [string] -and $raw){try{$j=$raw|ConvertFrom-Json}catch{}}; return @{S=[int]$r.StatusCode;B=$j;Raw=$raw}}
  catch{$resp=$_.Exception.Response; $code=if($resp){[int]$resp.StatusCode}else{0}; $ct=''; if($resp){$sr=[IO.StreamReader]::new($resp.GetResponseStream());$ct=$sr.ReadToEnd()}; $j=$null; if($ct){try{$j=$ct|ConvertFrom-Json}catch{}}; return @{S=$code;B=$j;Raw=$ct}}
}
function Bytes($m,$u,$b,$t,$c){ $h=@{}; if($t){$h.Authorization="Bearer $t"}; if($c){$h."X-Company-Id"="$c"}
  $tmp=[IO.Path]::GetTempFileName()
  $p=@{Uri="$Base$u";Method=$m;Headers=$h;ContentType="application/json; charset=utf-8";OutFile=$tmp}
  if($null -ne $b){$p.Body=[Text.Encoding]::UTF8.GetBytes(($b|ConvertTo-Json -Depth 20 -Compress))}
  try{ Invoke-WebRequest @p -UseBasicParsing; $bytes=[IO.File]::ReadAllBytes($tmp); return @{S=200;Bytes=$bytes} }
  catch{ $resp=$_.Exception.Response; return @{S=$(if($resp){[int]$resp.StatusCode}else{0});Bytes=$null} }
  finally{ Remove-Item $tmp -ErrorAction SilentlyContinue }
}
function IsPdf($r){ $r.S -eq 200 -and $r.Bytes -and $r.Bytes.Length -gt 1000 -and [Text.Encoding]::ASCII.GetString($r.Bytes,0,4) -eq '%PDF' }
function DocXml($bytes){ $ms=New-Object IO.MemoryStream(,$bytes); $z=New-Object IO.Compression.ZipArchive($ms)
  try{ $e=$z.GetEntry('word/document.xml'); $sr=New-Object IO.StreamReader($e.Open(),[Text.Encoding]::UTF8); return $sr.ReadToEnd() } finally { $z.Dispose() } }
function Expect($label,$actual,$expected){ if("$actual" -eq "$expected"){ Ok $label } else { Bad "$label (المتوقّع $expected والفعلي $actual)" } }
function Sql($sql){ $cn=New-Object System.Data.SqlClient.SqlConnection($Db); $cn.Open()
  try{ $cmd=$cn.CreateCommand(); $cmd.CommandText=$sql; return $cmd.ExecuteScalar() } finally { $cn.Close() } }
. "$PSScriptRoot\_activate.ps1"
$pwd0='Tables@12345'
function Login($u){ $null=Enable-TempPassword $Base $u $pwd0; return (Api POST "/auth/login" @{username=$u;password=$pwd0} $null $null).B.accessToken }
$mk=[guid]::NewGuid().ToString('N').Substring(0,6)

# ─────────── بناء الجدول بالشكل الذي تحفظه الواجهة (`BtJson.htmlTag`) ───────────
$script:seq=0
function NewId($p){ $script:seq++; "$p$mk$($script:seq)" }
function P($t){ if([string]::IsNullOrEmpty($t)){ '<p><br/></p>' } else { "<p><strong>$t</strong></p>" } }
function Cell($html,[hashtable]$extra){ $c=[ordered]@{id=(NewId 'c');rowSpan=1;colSpan=1;vAlign='middle';html=$html}
  if($extra){ foreach($k in $extra.Keys){ $c[$k]=$extra[$k] } }; return $c }
function Row($cells){ return [ordered]@{id=(NewId 'r');cells=@($cells)} }
function TableTag($t){ $json=$t | ConvertTo-Json -Depth 20 -Compress
  $esc=$json.Replace('&','&amp;').Replace('"','&quot;').Replace("'",'&#39;').Replace('<','&lt;').Replace('>','&gt;')
  return "<div data-dms-table=`"$esc`"></div>" }
# فاتورةٌ بشكل نموذج المالك: ت · إنجليزي · عربي · كمية · مفرد · كلّي — وصفّ مجموعٍ مدموج: «المجموع» · Σ للعمود الأخير · الحروف.
#  [$sumHtml] ما يكتبه العميل في خلية الجمع — **والخادم يتجاهله ويحسب** (حارس التزوير).
function Invoice($items,[string]$sumHtml='<p>999</p>',[string]$prefix=$null){
  $grey='#AEAAAA'
  $head=Row @(foreach($t in 'ت','المادة بالإنجليزي','المادة بالعربي','الكمية','سعر المفرد','السعر الكلي'){ Cell (P $t) @{bg=$grey} })
  $rows=@($head)
  $n=0; foreach($it in $items){ $n++; $rows+=Row @((Cell (P "$n")),(Cell (P $it[0])),(Cell (P $it[1])),(Cell (P $it[2])),(Cell (P $it[3])),(Cell (P $it[4]))) }
  $sum=Cell $sumHtml @{colSpan=2;bg=$grey;formula=[ordered]@{type='sum';col=5}}
  $w=[ordered]@{sourceCellId=$sum.id;currency='IQD'}; if($prefix){ $w.prefix=$prefix; $w.suffix='لا غير' }
  $words=Cell '<p><br/></p>' @{colSpan=2;bg=$grey;words=$w}
  $rows+=Row @((Cell (P 'المجموع') @{colSpan=2;bg=$grey}),$null,$sum,$null,$words,$null)
  return [ordered]@{id=(NewId 't');v=1;dir='rtl';widthPct=100;align='center';border=[ordered]@{widthPt=0.75;color='#000000'}
    headerRows=1;repeatHeader=$true;numberingCol=0;cols=@(foreach($w2 in 876,2977,2410,834,1559,1712){ [ordered]@{id=(NewId 'k');weight=$w2} });rows=$rows}
}
function Body($tables){ $h='<p>نرفق لكم الفاتورة أدناه.</p>'; foreach($t in $tables){ $h+=(TableTag $t) }; return $h+'<p>مع التقدير.</p>' }

Write-Host "=== إعداد ===" -ForegroundColor Cyan
$admin=(Api POST "/auth/login" @{username='admin';password=$AdminPwd} $null $null).B.accessToken
if(-not $admin){ Bad "تعذّر دخول admin — هل شُغّل bootstrap-e2e أولاً؟"; exit 1 }
$companies=@((Api GET "/companies" $null $admin $null).B)
if($companies.Count -lt 1){
  $null=Api POST "/companies" @{name="شركة الجداول $mk";prefix="T$((Get-Random -Minimum 10 -Maximum 99))";isActive=$true} $admin $null
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
UpsertUser 'tbl_emp' 'Employee' @('Outgoing')
UpsertUser 'tbl_rdr' 'Reader'   @('Outgoing')
$tE=Login 'tbl_emp'; $tR=Login 'tbl_rdr'
if($tE -and $tR){ Ok "دخول الموظف والقارئ" } else { Bad "تعذّر دخول أحدهما"; exit 1 }

function Book($subject,$html,$typeId,[hashtable]$opts){ $b=[ordered]@{companyId=$cid;entityId=$eid;templateId=$tplId;date='2026-10-05T00:00:00'
  headerPhrase=$null;signatoryName='المدير';signatoryTitle='المدير العام';subject=$subject;bodyHtml=$html;bodyJson=$null
  amount=$null;currency=$null;exchangeRate=$null;outgoingBookTypeId=$typeId}
  if($opts){ foreach($k in $opts.Keys){ $b[$k]=$opts[$k] } }; return $b }
function Moves($id,$tok){ @((Api GET "/outgoing/$id/movements" $null $tok $cid).B) }

Write-Host "`n=== ١) أنواع الصادر ===" -ForegroundColor Cyan
$types=@((Api GET "/outgoing-book-types" $null $admin $cid).B)
foreach($n in 'كتاب رسمي','فاتورة','عرض سعر'){ if($types.name -contains $n){ Ok "النوع المبذور «$n» موجود" } else { Bad "النوع «$n» غائب" } }
$tOfficial=[int]($types | Where-Object name -eq 'كتاب رسمي' | Select-Object -First 1).outgoingBookTypeId
$tInvoice=[int]($types | Where-Object name -eq 'فاتورة' | Select-Object -First 1).outgoingBookTypeId
Expect "🔐 الموظف لا ينشئ نوعاً (المدير فأعلى)" (Api POST "/outgoing-book-types" @{name="نوع الموظف $mk"} $tE $cid).S 403
$memo=Api POST "/outgoing-book-types" @{name="مذكرة $mk"} $admin $cid
Expect "المدير ينشئ نوعاً جديداً" $memo.S 200
Expect "   والاسم نفسه ثانيةً ⟵ 409" (Api POST "/outgoing-book-types" @{name="مذكرة $mk"} $admin $cid).S 409
$memoId=[int]$memo.B.outgoingBookTypeId
Expect "إعادة تسميته" (Api PUT "/outgoing-book-types/$memoId" @{name="مذكرة داخلية $mk"} $admin $cid).S 200
if($cid2){
  $t2=@((Api GET "/outgoing-book-types" $null $admin $cid2).B) | Select-Object -First 1
  $x=Api POST "/outgoing" (Book "نوعٌ من شركةٍ أخرى $mk" '<p>نص</p>' ([int]$t2.outgoingBookTypeId) $null) $admin $cid
  if($x.S -eq 400 -or $x.S -eq 404){ Ok "🔐 نوعٌ من شركةٍ أخرى يُرفض ($($x.S))" } else { Bad "نوعٌ من شركةٍ أخرى قُبل ($($x.S))" }
}

Write-Host "`n=== ٢) التفقيط في الخادم وحده ===" -ForegroundColor Cyan
$w=Api GET "/outgoing/number-words?value=9450000000&currency=IQD" $null $tE $cid
if("$($w.B.words)" -match 'تسعة مليارات' -and "$($w.B.words)" -match 'دينار'){ Ok "مبلغ فاتورة المالك بالحروف: $($w.B.words)" } else { Bad "التفقيط: $($w.Raw)" }
$w=Api GET "/outgoing/number-words?value=1430.33&currency=USD" $null $tE $cid
if("$($w.B.words)" -match 'دولار' -and "$($w.B.words)" -match 'سنت'){ Ok "الدولار بالسنتات: $($w.B.words)" } else { Bad "الدولار: $($w.Raw)" }
Expect "🔐 والمجهول لا يصل (401)" (Api GET "/outgoing/number-words?value=1&currency=IQD" $null $null $null).S 401

Write-Host "`n=== ٣) كتابٌ بجدول فاتورة — كما تحفظه الواجهة ===" -ForegroundColor Cyan
$items=@(@('CAT III Localizer','جهاز اللوكلايزر','1','2,850,000,000','2,850,000,000'),@('Monitor','جهاز مراقبة','2','50,000,000','100,000,000'))
$inv=Invoice $items '<p>999</p>' 'فقط'
$html=Body @($inv)
$opts=@{printEntity=$false;printSubject=$true;pageNumbers=$true;signaturePlacement='StampEveryPage'}
$before=[int](Sql "SELECT COUNT(*) FROM OutgoingBooks")
Expect "معاينة PDF قبل الحفظ" (IsPdf (Bytes POST "/outgoing/preview" (Book "فاتورة $mk" $html $tInvoice $opts) $tE $cid)) 'True'
Expect "   والمعاينة لا تحفظ شيئاً" ([int](Sql "SELECT COUNT(*) FROM OutgoingBooks")) $before
$d=Api POST "/outgoing" (Book "فاتورة $mk" $html $tInvoice $opts) $tE $cid
Expect "الموظف يحفظ المسودّة" $d.S 200
$oid=[int]$d.B.outgoingId
$g=(Api GET "/outgoing/$oid" $null $tE $cid).B
Expect "   النوع «فاتورة»" $g.outgoingBookTypeName 'فاتورة'
Expect "   طباعة الجهة: لا (والجهة مسجّلة)" "$($g.printEntity)|$($g.entityId)" "False|$eid"
Expect "   الترقيم: نعم" $g.pageNumbers 'True'
Expect "   الختم في كل صفحة والتوقيع في الأخيرة" $g.signaturePlacement 'StampEveryPage'
Expect "   🔑 بلا رقمٍ ولا QR قبل الاعتماد (الدورة كما هي)" "$([string]::IsNullOrEmpty("$($g.number)"))|$([string]::IsNullOrEmpty("$($g.qrContent)"))|$($g.hasPdf)" 'True|True|False'
if("$($g.bodyHtml)" -match 'data-dms-table'){ Ok "   والجدول محفوظٌ في المتن" } else { Bad "   الجدول غائب عن المتن" }
Expect "معاينة المسودّة المحفوظة (preview-draft)" (IsPdf (Bytes GET "/outgoing/$oid/preview-draft" $null $tE $cid)) 'True'

Write-Host "`n=== ٤) 🔐 الخادم حَكَم الطباعة: الجمع يُعاد حسابه ===" -ForegroundColor Cyan
$wd=Bytes GET "/outgoing/$oid/word" $null $tE $cid
Expect "Word للمسودّة" ($wd.S -eq 200 -and [Text.Encoding]::ASCII.GetString($wd.Bytes,0,2) -eq 'PK') 'True'
$xml=DocXml $wd.Bytes
if($xml -match '2,950,000,000'){ Ok "   المجموع المحسوب 2,950,000,000 في الملف" } else { Bad "   المجموع المحسوب غائب" }
if($xml -notmatch '>999<'){ Ok "   🔐 والرقم المزوَّر (999) لم يُطبع" } else { Bad "   الرقم المزوَّر طُبع" }
$words=(Api GET "/outgoing/number-words?value=2950000000&currency=IQD" $null $tE $cid).B.words
if($xml.Contains($words) -and $xml -match 'فقط'){ Ok "   والمبلغ كتابةً من الخادم بـ«فقط … لا غير»" } else { Bad "   المبلغ كتابةً غائب" }

Write-Host "`n=== ٥) 🔐 جدولٌ معطوب ⟵ 400 بالعربية ولا أثر ===" -ForegroundColor Cyan
$count=[int](Sql "SELECT COUNT(*) FROM OutgoingBooks")
function Broken($label,$t,[string]$extra){ $r=Api POST "/outgoing" (Book "معطوب $mk" (Body @($t)) $tOfficial $null) $tE $cid
  $msg="$($r.B.error)"
  if($r.S -eq 400 -and $msg -match '\p{IsArabic}'){ Ok "$label ⟵ 400: $msg" } else { Bad "$label (الحالة $($r.S)) $msg" } }
$t=Invoice $items; $t.rows[1].cells[1].colSpan=2
Broken "دمجٌ يتداخل مع خليةٍ قائمة" $t
$t=Invoice $items; $t.rows[1].cells[1].html='<p><a href="https://x">رابط</a></p>'
Broken "وسمٌ خارج القائمة (رابط في خلية)" $t
$t=Invoice $items; $t.rows[-1].cells[4].words.sourceCellId='لا-وجود'
Broken "«كتابة بالحروف» تشير إلى خليةٍ غير موجودة" $t
$t=Invoice $items; $t.rows[-1].cells[2].words=[ordered]@{sourceCellId=$t.rows[1].cells[5].id;currency='IQD'}
Broken "خليةٌ جمعٌ وحروفٌ معاً" $t
$t=Invoice $items; $t.rows[1].cells[2].bg='red'
Broken "لونٌ بغير صيغة #RRGGBB" $t
$t=Invoice $items; $t.cols=@($t.cols + @(foreach($i in 1..25){ [ordered]@{id=(NewId 'k');weight=1} })); foreach($r in $t.rows){ $r.cells=@($r.cells + @(foreach($i in 1..25){ Cell (P '') $null })) }
Broken "31 عموداً (الحدّ 30)" $t
$r=Api POST "/outgoing" (Book "26 جدولاً $mk" (Body @(foreach($i in 1..26){ Invoice @(,@('a','b','1','1','1')) })) $tOfficial $null) $tE $cid
if($r.S -eq 400){ Ok "26 جدولاً في الكتاب (الحدّ 25) ⟵ 400" } else { Bad "26 جدولاً قُبلت ($($r.S))" }
Expect "   ولم يُحفظ كتابٌ واحد من المعطوبة" ([int](Sql "SELECT COUNT(*) FROM OutgoingBooks")) $count

Write-Host "`n=== ٦) تعديل الجدول ⟵ سجلّ حركةٍ مفصّل ===" -ForegroundColor Cyan
$inv2=Invoice ($items + ,@('Antenna','هوائي','1','30,000,000','30,000,000')) '<p>0</p>' 'فقط'
# المعرّفات نفسها للجدول والصفوف القائمة — كما تحفظها الواجهة بعد التعديل
$inv2.id=$inv.id; for($i=0;$i -lt 3;$i++){ $inv2.rows[$i].id=$inv.rows[$i].id; for($c=0;$c -lt 6;$c++){ if($inv2.rows[$i].cells[$c] -and $inv.rows[$i].cells[$c]){ $inv2.rows[$i].cells[$c].id=$inv.rows[$i].cells[$c].id } } }
for($c=0;$c -lt 6;$c++){ $inv2.cols[$c].id=$inv.cols[$c].id }
$inv2.rows[2].cells[5].html='<p><strong>120,000,000</strong></p>'
$u=Api PUT "/outgoing/$oid" (Book "فاتورة $mk" (Body @($inv2)) $tInvoice $null) $tE $cid
Expect "الموظف يعدّل جدوله" $u.S 200
$m=Moves $oid $tE
$last=$m[-1]
Expect "   حركة التعديل" $last.action 'Edited'
if("$($last.description)" -match 'الجد(و|ا)ول'){ Ok "   تسمّي الجداول: $($last.description)" } else { Bad "   الوصف: $($last.description)" }
if("$($last.details)" -match '100,000,000 ⟵ 120,000,000'){ Ok "   والتفاصيل بالقديم والجديد" } else { Bad "   التفاصيل: $($last.details)" }
if("$($last.details)" -match 'صف'){ Ok "   وتذكر الصفّ المُضاف" } else { Bad "   التفاصيل بلا الصفّ المُضاف: $($last.details)" }
Expect "   🔑 والخيارات بقيت كما هي (التعديل لم يرسلها)" "$((Api GET "/outgoing/$oid" $null $tE $cid).B.signaturePlacement)" 'StampEveryPage'

Write-Host "`n=== ٧) فلتر النوع ===" -ForegroundColor Cyan
$inList=@((Api GET "/outgoing?typeId=$tInvoice" $null $tE $cid).B) | Where-Object outgoingId -eq $oid
Expect "الكتاب في قائمة «فاتورة»" (@($inList).Count) 1
$notIn=@((Api GET "/outgoing?typeId=$tOfficial" $null $tE $cid).B) | Where-Object outgoingId -eq $oid
Expect "   وليس في «كتاب رسمي»" (@($notIn).Count) 0

Write-Host "`n=== ٨) الاعتماد — الدورة كما هي ===" -ForegroundColor Cyan
Expect "🔐 الموظف لا يعتمد" (Api POST "/outgoing/$oid/approve" $null $tE $cid).S 403
$ap=Api POST "/outgoing/$oid/approve" $null $admin $cid
Expect "المدير يعتمد" $ap.S 200
$g=(Api GET "/outgoing/$oid" $null $admin $cid).B
if("$($g.number)" -and "$($g.qrContent)" -and $g.hasPdf){ Ok "   الآن فقط: رقمٌ ($($g.number)) وQR وPDF" } else { Bad "   الاعتماد بلا رقم/QR/PDF" }
$pdf=Bytes GET "/outgoing/$oid/pdf" $null $tE $cid
Expect "   تنزيل الـPDF الرسميّ" (IsPdf $pdf) 'True'
$wd=Bytes GET "/outgoing/$oid/word" $null $admin $cid
$xml=DocXml $wd.Bytes
# المجموع بعد التعديل: 2,850,000,000 + 120,000,000 + 30,000,000
if($xml.Contains("$($g.number)") -and $xml -match '3,000,000,000'){ Ok "   Word للمعتمد: الرقم والمجموع بعد التعديل 3,000,000,000" } else { Bad "   Word للمعتمد ناقص (الرقم: $($xml.Contains("$($g.number)")))" }
Expect "   حركة الاعتماد" (Moves $oid $admin)[-1].action 'Approved'

Write-Host "`n=== ٩) التعديل بعد الاعتماد ===" -ForegroundColor Cyan
$inv3=$inv2 | ConvertTo-Json -Depth 20 | ConvertFrom-Json
$inv3.rows[1].cells[5].html='<p><strong>2,900,000,000</strong></p>'
$ea=Book "فاتورة $mk" (Body @($inv3)) $tInvoice @{rowVersion=$g.rowVersion;changeNote='تصحيح سعر البند الأوّل'}
$ea.Remove('companyId')
Expect "المدير يعدّل الكتاب المعتمد" (Api PUT "/outgoing/$oid/edit-approved" $ea $admin $cid).S 200
$last=(Moves $oid $admin)[-1]
Expect "   حركة التعديل بعد الاعتماد" $last.action 'EditedApproved'
if("$($last.details)" -match '2,850,000,000 ⟵ 2,900,000,000'){ Ok "   بتفاصيل الخلية" } else { Bad "   التفاصيل: $($last.details)" }
Expect "   🔑 والرقم الرسميّ لم يتغيّر" (Api GET "/outgoing/$oid" $null $admin $cid).B.number "$($g.number)"
if(@((Api GET "/outgoing/$oid/versions" $null $admin $cid).B).Count -ge 1){ Ok "   وسجلّ الإصدارات فيه النسخة السابقة" } else { Bad "   لا إصدار سابق" }
Expect "   والـPDF الرسميّ يُنزَّل بعد التعديل" (IsPdf (Bytes GET "/outgoing/$oid/pdf" $null $admin $cid)) 'True'

Write-Host "`n=== ١٠) القارئ كما هو ===" -ForegroundColor Cyan
Expect "القارئ يرى الكتاب" (Api GET "/outgoing/$oid" $null $tR $cid).S 200
Expect "   ويقرأ الـPDF" (IsPdf (Bytes GET "/outgoing/$oid/pdf" $null $tR $cid)) 'True'
Expect "🔐 ولا يرى سجلّ الحركة (403)" (Api GET "/outgoing/$oid/movements" $null $tR $cid).S 403
Expect "🔐 ولا يعدّل" (Api PUT "/outgoing/$oid/edit-approved" $ea $tR $cid).S 403
Expect "🔐 ولا ينشئ نوعاً" (Api POST "/outgoing-book-types" @{name="نوع القارئ $mk"} $tR $cid).S 403

Write-Host "`n=== ١١) أنواعٌ مستعملة · كتابٌ بلا جدول · جدولٌ كبير ===" -ForegroundColor Cyan
Expect "حذف نوعٍ مستعمل ⟵ 409" (Api DELETE "/outgoing-book-types/$tInvoice" $null $admin $cid).S 409
Expect "حذف النوع غير المستعمل" (Api DELETE "/outgoing-book-types/$memoId" $null $admin $cid).S 204
$plain=Api POST "/outgoing" (Book "كتاب بلا جدول $mk" '<p>نصٌّ عاديّ كما كان.</p>' $null $null) $tE $cid
Expect "كتابٌ بلا جدول ولا نوع: يُحفظ كما كان" $plain.S 200
Expect "   ويأخذ النوع الافتراضيّ «كتاب رسمي»" $plain.B.outgoingBookTypeName 'كتاب رسمي'
Expect "   والخيارات الافتراضية (الأخيرة · بترقيم · بالجهة والموضوع)" "$($plain.B.signaturePlacement)|$($plain.B.pageNumbers)|$($plain.B.printEntity)|$($plain.B.printSubject)" 'LastPage|True|True|True'
$big=Invoice @(foreach($i in 1..300){ ,@("Item $i","مادة $i",'1','1,000','1,000') })
$sw=[Diagnostics.Stopwatch]::StartNew()
$pv=Bytes POST "/outgoing/preview" (Book "300 بند $mk" (Body @($big)) $tInvoice $null) $tE $cid
$sw.Stop()
if((IsPdf $pv) -and $sw.Elapsed.TotalSeconds -lt 60){ Ok "جدولٌ من 300 بند: PDF في $([math]::Round($sw.Elapsed.TotalSeconds,1)) ثانية" } else { Bad "جدول 300 بند: $($pv.S) في $($sw.Elapsed.TotalSeconds) ثانية" }

Write-Host "`n============ النتيجة ============" -ForegroundColor Cyan
Write-Host "  نجح: $pass" -ForegroundColor Green
Write-Host "  فشل: $fail" -ForegroundColor $(if($fail){'Red'}else{'Green'})
exit $(if($fail){1}else{0})
