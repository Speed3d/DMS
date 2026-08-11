param([string]$AdminPwd='Speed3ds', [string]$Base='http://localhost:5080/api', [int]$Parallel=12)
# ════════════════════════════════════════════════════════════════════════════════════════
#  حرّاس **العزل الصفّي** و**توليد الرقم تحت التزامن** — إغلاق الفجوة G2.
#
#  🔴 **لماذا E2E لا اختبار وحدة؟** لأن ما يُختبَر هنا **لا يعيش خارج قاعدة بيانات حقيقية**:
#     · العزل يفرضه **Global Query Filter** في EF — لا منطقَ مجالٍ يُستدعى.
#     · الترقيم يعتمد `FromSql` بـ`WITH (UPDLOCK, HOLDLOCK)` — قفلُ صفٍّ في SQL Server.
#     ومزوّد `Sqlite` **لا يدعم `IsRowVersion`**، و`InMemory` **لا يدعم `FromSql`** ولا
#     المعاملات ⇒ اختبارٌ عليهما يقول «سليم» عن آليةٍ لم يُشغّلها أصلاً — **ثقةٌ كاذبة**.
#
#  ⚠️ **وهذا لا يُغني عن مشروع اختبارات على SQL Server حقيقي (الفجوة G15)** — يبقى مؤجَّلاً
#     لما قبل التسليم النهائي بقرار المالك. هذا السكربت يغطّي **الواقع**، لكنه يحتاج خادماً
#     يعمل فلا ينكشف انكسارُه في كل بناء.
#
#  ⚠️ يُنشئ بيانات في شركتين — **بيئة تطوير فقط**. قابل لإعادة التشغيل.
# ════════════════════════════════════════════════════════════════════════════════════════
$ErrorActionPreference='Stop'; $pass=0; $fail=0
function Ok($m){ $script:pass++; Write-Host "  [نجح] $m" -ForegroundColor Green }
function Bad($m){ $script:fail++; Write-Host "  [فشل] $m" -ForegroundColor Red }
function Skip($m){ Write-Host "  [تخطٍّ] $m" -ForegroundColor Yellow }
function Api($m,$u,$b,$t,$c){ $h=@{}; if($t){$h.Authorization="Bearer $t"}; if($c){$h."X-Company-Id"="$c"}
  $p=@{Uri="$Base$u";Method=$m;Headers=$h;ContentType="application/json; charset=utf-8"}
  if($null -ne $b){$p.Body=[Text.Encoding]::UTF8.GetBytes(($b|ConvertTo-Json -Depth 8 -Compress))}
  try{$r=Invoke-WebRequest @p -UseBasicParsing; $j=$null; if($r.Content){try{$j=$r.Content|ConvertFrom-Json}catch{}}; return @{S=[int]$r.StatusCode;B=$j}}
  catch{$resp=$_.Exception.Response; $code=if($resp){[int]$resp.StatusCode}else{0}; $ct=''; if($resp){$sr=[IO.StreamReader]::new($resp.GetResponseStream());$ct=$sr.ReadToEnd()}; $j=$null; if($ct){try{$j=$ct|ConvertFrom-Json}catch{}}; return @{S=$code;B=$j}}
}
function Expect($label,$actual,$expected){ if("$actual" -eq "$expected"){ Ok $label } else { Bad "$label (المتوقّع $expected والفعلي $actual)" } }

# ⚠️ **المطابقة بالمعرّفات لا بالأسماء العربية** — PS 5.1 يشوّه العربية العائدة من الـAPI
#    فتفشل المطابقة صامتةً (درسٌ مسجَّل في `hr-e2e.ps1`).

Write-Host "`n=== إعداد: شركتان ===" -ForegroundColor Cyan
$admin=(Api POST "/auth/login" @{username='admin';password=$AdminPwd} $null $null).B.accessToken
if(-not $admin){ Bad "فشل دخول admin"; exit 1 }

$companies=@((Api GET "/companies" $null $admin $null).B)
if($companies.Count -lt 2){
  $pfx="ISO$(Get-Random -Minimum 100 -Maximum 999)"
  $null=Api POST "/companies" @{name="شركة عزل الاختبار";prefix=$pfx;isActive=$true} $admin $null
  $companies=@((Api GET "/companies" $null $admin $null).B)
}
if($companies.Count -lt 2){ Bad "تعذّر تجهيز شركتين"; exit 1 }
$cidA=$companies[0].companyId; $cidB=$companies[1].companyId
Ok "الشركتان: A=$cidA · B=$cidB"

# جهةٌ في كل شركة (الصادر يحتاج جهة).
function EntityIn($cid,$name){
  $found=@((Api GET "/entities" $null $admin $cid).B) | Select-Object -First 1
  if($found){ return $found.entityId }
  return (Api POST "/entities" @{name=$name;kind='Both';isActive=$true} $admin $cid).B.entityId
}
$entA=EntityIn $cidA "جهة العزل أ"
$entB=EntityIn $cidB "جهة العزل ب"
if(-not $entA -or -not $entB){ Bad "تعذّر تجهيز الجهات"; exit 1 }
Ok "جهتان: A=$entA · B=$entB"

# ⚠️ **الاعتماد يتطلّب قالباً** — والقاعدة الجديدة بلا قوالب، فيردّ «القالب غير موجود» (404).
#    كشفه أول تشغيل: فشلت الاثنتا عشرة اعتماداً كلُّها **بعيبٍ في السكربت لا في المنتج**.
function TemplateIn($cid,$name){
  $found=@((Api GET "/templates" $null $admin $cid).B) | Select-Object -First 1
  if($found){ return $found.templateId }
  # ⚠️ `WatermarkOpacity` **عددٌ صحيح** (نسبة مئوية) لا كسر — وإرسال `0.1` يردّ 400.
  #    والهوامش والقياس والخط **مطلوبة كلها** في العقد.
  return (Api POST "/templates" @{companyId=$cid;name=$name;watermarkOpacity=10
      marginTop=20;marginRight=20;marginBottom=20;marginLeft=20
      pageSize='A4';fontFamily='Amiri';isActive=$true} $admin $cid).B.templateId
}
$tplA=TemplateIn $cidA "قالب العزل أ"
$tplB=TemplateIn $cidB "قالب العزل ب"
if(-not $tplA -or -not $tplB){ Bad "تعذّر تجهيز القوالب"; exit 1 }
Ok "قالبان: A=$tplA · B=$tplB"

# ════════════════════════════ ١) العزل الصفّي ════════════════════════════
Write-Host "`n=== ١) العزل الصفّي بين الشركتين ===" -ForegroundColor Cyan
# 🔴 **الاختبار بالمعرّف لا بغياب السطر من القائمة.** قائمةٌ فارغة قد تعني «لا بيانات»،
#    أما `GET /outgoing/{id}` بمعرّفٍ **معلوم الوجود** فيفصل: 404 = محجوب · 200 = تسرّب.

$mk=Get-Random -Minimum 1000 -Maximum 9999
$draftA=Api POST "/outgoing" @{companyId=$cidA;entityId=$entA;templateId=$tplA
    date=(Get-Date).ToString("yyyy-MM-dd");subject="عزل-$mk";bodyHtml="<p>كتاب شركة أ</p>"} $admin $cidA
if($draftA.S -ne 200){ Bad "تعذّر إنشاء كتاب في أ: $($draftA.S)"; exit 1 }
$oidA=$draftA.B.outgoingId
Ok "كتابٌ في الشركة أ (معرّف $oidA)"

Expect "🔐 الصادر: كتاب أ محجوبٌ عن ب (404)" (Api GET "/outgoing/$oidA" $null $admin $cidB).S 404
Expect "   ومرئيٌّ في أ (200)" (Api GET "/outgoing/$oidA" $null $admin $cidA).S 200
$inB=@((Api GET "/outgoing" $null $admin $cidB).B) | Where-Object { $_.outgoingId -eq $oidA }
Expect "   وغائبٌ عن قائمة ب" @($inB).Count 0

# مرفقات الكتاب: بابٌ ثانٍ للوصول — يجب أن يُحجب كذلك.
Expect "🔐 ومرفقاته محجوبة عن ب" (Api GET "/outgoing/$oidA/attachments" $null $admin $cidB).S 404

# الوارد
$incA=Api POST "/incoming" @{companyId=$cidA;entityId=$entA;externalNumber="X-$mk"
    externalDate=(Get-Date).ToString("yyyy-MM-dd");receivedDate=(Get-Date).ToString("yyyy-MM-dd")
    subject="وارد عزل-$mk";receiveMethod='Manual'} $admin $cidA
if($incA.S -eq 200){
  $iidA=$incA.B.incomingId
  Expect "🔐 الوارد: كتاب أ محجوبٌ عن ب (404)" (Api GET "/incoming/$iidA" $null $admin $cidB).S 404
  Expect "   ومرئيٌّ في أ" (Api GET "/incoming/$iidA" $null $admin $cidA).S 200
} else { Bad "تعذّر إنشاء وارد في أ: $($incA.S)" }

# الأرشيف
$arcA=Api POST "/archive" @{companyId=$cidA;title="أضبارة عزل-$mk";documentTypeId=$null
    fromEntityId=$entA;toEntityId=$null;bookNumber="A-$mk";notes=$null} $admin $cidA
if($arcA.S -eq 200){
  $aidA=$arcA.B.archiveId
  Expect "🔐 الأرشيف: أضبارة أ محجوبة عن ب (404)" (Api GET "/archive/$aidA" $null $admin $cidB).S 404
} else { Skip "تعذّر إنشاء أضبارة ($($arcA.S)) — تخطّي حارس الأرشيف" }

# الأقسام والجهات: قوائم كلٍّ لا تتسرّب إلى الأخرى.
$deptA=(Api POST "/departments" @{name="قسم عزل-$mk";isActive=$true} $admin $cidA).B.departmentId
if($deptA){
  $seen=@((Api GET "/departments" $null $admin $cidB).B) | Where-Object { $_.departmentId -eq $deptA }
  Expect "🔐 الأقسام: قسم أ غائبٌ عن قائمة ب" @($seen).Count 0
}
$entSeen=@((Api GET "/entities" $null $admin $cidB).B) | Where-Object { $_.entityId -eq $entA }
Expect "🔐 الجهات: جهة أ غائبةٌ عن قائمة ب" @($entSeen).Count 0

# التقرير المالي: لا يجمع أرقام الشركة الأخرى.
$repA=@((Api GET "/reports/financial?source=All" $null $admin $cidA).B.rows)
$repB=@((Api GET "/reports/financial?source=All" $null $admin $cidB).B.rows)
$leak=$repB | Where-Object { $_.number -and $repA.number -contains $_.number }
Expect "🔐 التقرير المالي: لا صفَّ مشتركاً بين الشركتين" @($leak).Count 0

# ════════════════════════════ ٢) الترقيم تحت التزامن ════════════════════════════
Write-Host "`n=== ٢) توليد الرقم الرسمي تحت تزامنٍ حقيقي ($Parallel طلباً معاً) ===" -ForegroundColor Cyan
# 🔴 **الرقم يُحجَز عند الاعتماد** بـ`NumberingService.NextSerialAsync` عبر
#    `SELECT ... WITH (UPDLOCK, HOLDLOCK)`. وهذا الحارس يُثبت أن قفل الصفّ يعمل فعلاً:
#    نُنشئ مسودّات متتابعة ثم **نعتمدها كلَّها في اللحظة نفسها**.
# ⚠️ `Start-Job` لا يصلح هنا (كل وظيفة عمليةٌ جديدة فيتباعد التوقيت) — نستعمل
#    `HttpClient.SendAsync` فتنطلق الطلبات فعلاً معاً.

$drafts=@()
foreach($i in 1..$Parallel){
  $d=Api POST "/outgoing" @{companyId=$cidA;entityId=$entA;templateId=$tplA
      date=(Get-Date).ToString("yyyy-MM-dd");subject="تزامن-$mk-$i";bodyHtml="<p>$i</p>"} $admin $cidA
  if($d.S -eq 200){ $drafts += $d.B.outgoingId }
}
Expect "أُنشئت $Parallel مسودّة" $drafts.Count $Parallel

if($drafts.Count -eq $Parallel){
  Add-Type -AssemblyName System.Net.Http | Out-Null
  $handler=New-Object System.Net.Http.HttpClientHandler
  $client=New-Object System.Net.Http.HttpClient($handler)
  $client.Timeout=[TimeSpan]::FromSeconds(90)

  $tasks=New-Object 'System.Collections.Generic.List[System.Threading.Tasks.Task[System.Net.Http.HttpResponseMessage]]'
  foreach($id in $drafts){
    $req=New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Post, "$Base/outgoing/$id/approve")
    $req.Headers.Add("Authorization","Bearer $admin")
    $req.Headers.Add("X-Company-Id","$cidA")
    $req.Content=New-Object System.Net.Http.StringContent("", [Text.Encoding]::UTF8, "application/json")
    $tasks.Add($client.SendAsync($req))
  }
  [System.Threading.Tasks.Task]::WaitAll($tasks.ToArray())

  $okCount=0
  foreach($t in $tasks){ if([int]$t.Result.StatusCode -eq 200){ $okCount++ } }
  Expect "اعتُمدت $Parallel معاً بلا فشل" $okCount $Parallel
  $client.Dispose()

  # النتيجة: أرقامٌ متمايزة كلها.
  $numbers=@()
  foreach($id in $drafts){
    $b=(Api GET "/outgoing/$id" $null $admin $cidA).B
    if($b.number){ $numbers += $b.number }
  }
  Expect "لكل كتابٍ رقمٌ رسمي" $numbers.Count $Parallel
  $distinct=@($numbers | Select-Object -Unique)
  Expect "🔴 **لا رقمَ مكرَّراً تحت التزامن** ($($distinct.Count) رقماً متمايزاً)" $distinct.Count $Parallel

  # ولا ثقوب: التسلسل متّصل بين أصغر رقمٍ وأكبره.
  $serials=@($numbers | ForEach-Object { [int]($_ -split '-')[-1] } | Sort-Object)
  if($serials.Count -eq $Parallel){
    $span=$serials[-1]-$serials[0]+1
    Expect "والتسلسل متّصل بلا ثقوب ($($serials[0])…$($serials[-1]))" $span $Parallel
  }

  # 🔐 وعدّاد الشركة الأخرى لم يتحرّك بفعل تزامن الأولى.
  $bDraft=Api POST "/outgoing" @{companyId=$cidB;entityId=$entB;templateId=$tplB
      date=(Get-Date).ToString("yyyy-MM-dd");subject="تزامن-ب-$mk";bodyHtml="<p>ب</p>"} $admin $cidB
  if($bDraft.S -eq 200){
    $bApp=Api POST "/outgoing/$($bDraft.B.outgoingId)/approve" $null $admin $cidB
    if($bApp.S -eq 200){
      $bNum=(Api GET "/outgoing/$($bDraft.B.outgoingId)" $null $admin $cidB).B.number
      $bSerial=[int]($bNum -split '-')[-1]
      Expect "🔐 عدّاد الشركة ب مستقلٌّ عن تزامن أ (تسلسله $bSerial لا $($serials[-1]+1))" ($bSerial -ne ($serials[-1]+1) -or $bNum -ne $numbers[-1]) $true
      Ok "   رقم ب: $bNum · وآخر رقمٍ في أ: $($numbers[-1])"
    }
  }

  # تنظيف: الكتب المعتمدة لا تُحذف حذفاً فعلياً — حذفٌ ناعم يكفي لئلا تتراكم.
  foreach($id in $drafts){ $null=Api DELETE "/outgoing/$id" $null $admin $cidA }
}

Write-Host "`n=== النتيجة ===" -ForegroundColor Cyan
Write-Host "نجح: $pass" -ForegroundColor Green
Write-Host "فشل: $fail" -ForegroundColor $(if($fail -eq 0){'Green'}else{'Red'})
if($fail -gt 0){ exit 1 }
