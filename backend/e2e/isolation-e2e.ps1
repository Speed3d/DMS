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
# ⚙️ **حذفُ الشركة صار عمليةً خلفية** (يأخذ نسخةً كاملة قبله — حدّ Cloudflare ~100 ثانية):
#    يردّ 202 برقم العملية، ثم تُسأل `/system/jobs/{id}` حتى تنتهي.
function WaitJob($start,$tok){
  if($start.S -ne 202 -or -not $start.B.id){ return $null }
  for($i=0;$i -lt 600;$i++){
    $j=Api GET "/system/jobs/$($start.B.id)" $null $tok $null
    if($j.S -ne 200){ return [pscustomobject]@{state="Lost";message="HTTP $($j.S)"} }
    if($j.B.state -ne 'Running'){ return $j.B }
    Start-Sleep -Milliseconds 400
  }
  return [pscustomobject]@{state="Timeout";message="لم تنتهِ"}
}


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


# ════════════════════════ ٤) الإشعارات: عزلٌ بالشركة (ADR-046) ════════════════════════
#
# 🔴 **لماذا E2E لا اختبار وحدة؟** العزل هنا يفرضه **Global Query Filter** في EF بحسب
#    ترويسة `X-Company-Id` — ولا منطقَ مجالٍ يُستدعى. واختبارٌ في الذاكرة يقول «سليم»
#    عن آليةٍ لم يُشغّلها.
#
# ⚠️ **والمستلِم غيرُ الفاعل عمداً**: `SendAsync` لا يُشعر الفاعلَ بفعل نفسه، فلو أسند
#    admin مهمةً لنفسه **لما وُلد إشعارٌ أصلاً** ومرّ الحارس بلا أن يحرس شيئاً.

Write-Host "`n=== ٤) عزل الإشعارات بالشركة (ADR-046) ===" -ForegroundColor Cyan

function UpsertIsoUser($username,$displayName){
  $ex=(Api GET "/users" $null $admin $cidA).B | Where-Object { $_.username -eq $username } | Select-Object -First 1
  $body=@{fullName=$displayName;role='Employee';isActive=$true;companies=@(
    @{companyId=$cidA;modules=@('Outgoing','Tasks');canManageTasks=$false},
    @{companyId=$cidB;modules=@('Outgoing','Tasks');canManageTasks=$false})}
  if($ex){ $null=Api PUT "/users/$($ex.userId)" $body $admin $cidA }
  else { $body.username=$username; $body.password='Iso@12345'; $null=Api POST "/users" $body $admin $cidA }
  return (Api GET "/users" $null $admin $cidA).B | Where-Object { $_.username -eq $username } | Select-Object -First 1
}

$dual=UpsertIsoUser 'iso_dual' 'موظف الشركتين'
if($dual){ Ok "مستخدمٌ مُسنَدٌ للشركتين (id=$($dual.userId))" } else { Bad "تعذّر تجهيز المستخدم المزدوج" }

if($dual){
  $due=(Get-Date).Date.AddDays(7).ToString('yyyy-MM-ddT00:00:00')
  $mk="ISO$(Get-Random -Minimum 1000 -Maximum 9999)"

  # مهمّةٌ في كل شركة **مُسنَدةٌ إليه** ⇒ إشعارٌ في كلٍّ.
  $tA=(Api POST "/tasks" @{title="إشعار-أ-$mk";taskType='Individual';priority='Normal'
      dueDate=$due;assignedToUserId=$dual.userId} $admin $cidA)
  $tB=(Api POST "/tasks" @{title="إشعار-ب-$mk";taskType='Individual';priority='Normal'
      dueDate=$due;assignedToUserId=$dual.userId} $admin $cidB)

  if($tA.S -eq 200 -and $tB.S -eq 200){
    $idA=[int]$tA.B.taskId; $idB=[int]$tB.B.taskId
    Ok "مهمّتان مُسنَدتان إليه: أ=$idA · ب=$idB"

    . "$PSScriptRoot\_activate.ps1"   # G19: الكلمة المؤقتة تُفعَّل قبل الاستعمال
    $null=Enable-TempPassword $Base 'iso_dual' 'Iso@12345'
    $tk=(Api POST "/auth/login" @{username='iso_dual';password='Iso@12345'} $null $null).B.accessToken
    if(-not $tk){ Bad "تعذّر دخول iso_dual" }
    else{
      $nA=(Api GET "/notifications" $null $tk $cidA).B
      $nB=(Api GET "/notifications" $null $tk $cidB).B

      # 🔴 **المطابقة بمعرّف الكيان لا بالعنوان** — العربية تتشوّه في PS 5.1 فتفشل صامتةً.
      $seenAinA=@($nA.items | Where-Object { $_.entityType -eq 'DmsTask' -and [int]$_.entityId -eq $idA }).Count
      $seenBinA=@($nA.items | Where-Object { $_.entityType -eq 'DmsTask' -and [int]$_.entityId -eq $idB }).Count
      $seenBinB=@($nB.items | Where-Object { $_.entityType -eq 'DmsTask' -and [int]$_.entityId -eq $idB }).Count
      $seenAinB=@($nB.items | Where-Object { $_.entityType -eq 'DmsTask' -and [int]$_.entityId -eq $idA }).Count

      Expect "إشعارُ الشركة أ يظهر وهو فيها" $seenAinA 1
      Expect "🔐 وإشعارُ الشركة ب **محجوبٌ** وهو في أ" $seenBinA 0
      Expect "إشعارُ الشركة ب يظهر وهو فيها" $seenBinB 1
      Expect "🔐 وإشعارُ الشركة أ **محجوبٌ** وهو في ب" $seenAinB 0

      # ── الإعلان يسدّ ثغرة الفقد الصامت ──
      $otherInA=@($nA.otherCompanies | Where-Object { [int]$_.companyId -eq $cidB })
      $otherInB=@($nB.otherCompanies | Where-Object { [int]$_.companyId -eq $cidA })
      if($otherInA.Count -eq 1 -and [int]$otherInA[0].unread -ge 1){
        Ok "✅ والمحجوب **يُعلَن**: شركة ب فيها $($otherInA[0].unread) غير مقروء"
      } else { Bad "سطرُ «شركاتك الأخرى» غائبٌ في أ" }
      if($otherInB.Count -eq 1 -and [int]$otherInB[0].unread -ge 1){
        Ok "✅ والعكس: شركة أ فيها $($otherInB[0].unread) غير مقروء" 
      } else { Bad "سطرُ «شركاتك الأخرى» غائبٌ في ب" }

      # 🔐 **بالعدد واسم الشركة فقط** — لا عنوان ولا متن ولا معرّف كيان يتسرّب.
      $leak=@($otherInA[0].PSObject.Properties.Name | Where-Object { $_ -notin @('companyId','companyName','unread') }).Count
      Expect "🔐 ولا حقلَ زائداً في الإعلان (عددٌ واسمٌ فقط)" $leak 0

      # ── الشارة تتبع الشركة الفعّالة ──
      $cA=[int](Api GET "/notifications/unread-count" $null $tk $cidA).B
      $cB=[int](Api GET "/notifications/unread-count" $null $tk $cidB).B
      if($cA -ge 1 -and $cB -ge 1){ Ok "شارةُ الجرس تُحسب لكل شركة ($cA في أ · $cB في ب)" }
      else { Bad "شارةٌ صفرٌ في إحداهما: أ=$cA ب=$cB" }

      # 🔐 **الوسمُ بالمقروء يمرّ من القُمع نفسه** — فإشعارُ شركةٍ أخرى **404 لا 403**.
      $bNotifId=@($nB.items | Where-Object { $_.entityType -eq 'DmsTask' -and [int]$_.entityId -eq $idB })[0].notificationId
      if($bNotifId){
        $mark=Api POST "/notifications/$bNotifId/read" $null $tk $cidA
        Expect "🔐 وسمُ إشعارِ شركةٍ أخرى مقروءاً ⇒ 404 (لا يُفشى وجودُه)" $mark.S 404
        $markOk=Api POST "/notifications/$bNotifId/read" $null $tk $cidB
        Expect "   ونجاحُه من شركته هو" $markOk.S 204
      } else { Bad "تعذّر التقاط معرّف إشعار ب" }

      # 🔴 **تعليم الكل مقروءاً لا يتجاوز الشركة** — وإلا مسح إشعاراتٍ لم يرها أصلاً.
      $null=Api POST "/notifications/read-all" $null $tk $cidA
      $stillB=[int](Api GET "/notifications/unread-count" $null $tk $cidB).B
      $nowA=[int](Api GET "/notifications/unread-count" $null $tk $cidA).B
      Expect "«تحديد الكل كمقروء» في أ يُصفّرها" $nowA 0
      if($stillB -ge 0){ Ok "   ولا يمسّ شركة ب (بقي $stillB)" }
    }
  } else { Bad "تعذّر إنشاء المهمّتين: أ=$($tA.S) ب=$($tB.S)" }
}


# ══════════════ ٥) دورة حياة الشركة: التعطيل ثم الحذف (ADR-047) ══════════════
#
# 🔴 **وُلدت هذه الحرّاس من حادثةٍ وقعت 2026-09-21**: بابا حذف الجهة والشركة أُغلقا
#    بسبب كتابٍ **محذوف ناعماً**، برسالتين غامضتين — فذهب المالك إلى زرّ تصفير القاعدة.
#
# ⚠️ **E2E لا اختبار وحدة**: القواعد النقيّة يحرسها `CompanyLifecycleTests`، وما هنا
#    **التوصيل**: معامل `confirm` · نقطة البيان · النسخة قبل الحذف · وتصفية القائمة.

Write-Host "`n=== ٥) التعطيل ثم الحذف (ADR-047) ===" -ForegroundColor Cyan

$pfx = "DEL$(Get-Random -Minimum 100 -Maximum 999)"
$tmp = (Api POST "/companies" @{name="شركة الحذف $pfx";prefix=$pfx;isActive=$true} $admin $null)
if($tmp.S -ne 200){ Bad "تعذّر إنشاء شركة الاختبار: $($tmp.S)" }
else{
  $cidT = [int]$tmp.B.companyId
  $nameT = "شركة الحذف $pfx"
  Ok "شركةٌ للاختبار: $cidT"

  # ── القائمة: النشِطة افتراضاً، والمعطَّلة بطلبٍ صريح ──
  $inDefault = @((Api GET "/companies" $null $admin $null).B | Where-Object { [int]$_.companyId -eq $cidT }).Count
  Expect "الشركة النشِطة تظهر في القائمة الافتراضية" $inDefault 1

  # ── ١) الحذف مرفوضٌ ما دامت مفعَّلة ──
  $d1 = Api DELETE "/companies/$cidT`?confirm=$([uri]::EscapeDataString($nameT))" $null $admin $null
  Expect "🔴 حذفُ شركةٍ **مفعَّلة** مرفوض (خطوتان لا واحدة)" $d1.S 409

  # ── ٢) التعطيل ──
  $upd = Api PUT "/companies/$cidT" @{name=$nameT;prefix=$pfx;isActive=$false} $admin $null
  Expect "التعطيل ينجح" $upd.S 200

  $inDefault2 = @((Api GET "/companies" $null $admin $null).B | Where-Object { [int]$_.companyId -eq $cidT }).Count
  Expect "🔐 والمعطَّلة **تختفي** من القائمة الافتراضية (مبدّل الشركات)" $inDefault2 0
  $inAll = @((Api GET "/companies?includeInactive=true" $null $admin $null).B | Where-Object { [int]$_.companyId -eq $cidT }).Count
  Expect "   وتظهر في شاشة الإعدادات بـincludeInactive" $inAll 1

  # ── ٣) البيان قبل الحذف ──
  $pv = Api GET "/companies/$cidT/delete-preview" $null $admin $null
  if($pv.S -eq 200){
    Ok "نقطةُ البيان تعمل"
    Expect "   والبيان يقول إن الحذف جائز" $pv.B.canDelete "True"
    Expect "   وسببُ المنع None" $pv.B.blockReason "None"
    Expect "   وعددُ ما سيُمحى صفرٌ لشركةٍ فارغة" ([int]$pv.B.willBeErased) 0
  } else { Bad "نقطة البيان: $($pv.S)" }

  # ── ٤) التأكيد إلزاميّ ──
  $d2 = Api DELETE "/companies/$cidT" $null $admin $null
  Expect "🔐 الحذف **بلا تأكيد** مرفوض" $d2.S 409
  $d3 = Api DELETE "/companies/$cidT`?confirm=اسم-خاطئ" $null $admin $null
  Expect "🔐 وبتأكيدٍ **لا يطابق الاسم** مرفوض" $d3.S 409

  # ── ٥) سجلٌّ حيّ يمنع · والمحذوف ناعماً **لا يمنع** (بلاغ المالك) ──
  $entT = (Api POST "/entities" @{name="جهة الحذف $pfx";kind='Both';isActive=$true} $admin $cidT).B.entityId
  $tplT = (Api POST "/templates" @{companyId=$cidT;name="قالب $pfx";watermarkOpacity=10
      marginTop=20;marginRight=20;marginBottom=20;marginLeft=20
      pageSize='A4';fontFamily='Amiri';isActive=$true} $admin $cidT).B.templateId

  if($entT -and $tplT){
    $bk = Api POST "/outgoing" @{companyId=$cidT;entityId=$entT;templateId=$tplT
        date=(Get-Date).ToString("yyyy-MM-dd");subject="كتاب الحذف";bodyHtml="<p>x</p>"} $admin $cidT
    if($bk.S -eq 200){
      $bid = [int]$bk.B.outgoingId
      $null = Api POST "/outgoing/$bid/approve" $null $admin $cidT

      $pv2 = (Api GET "/companies/$cidT/delete-preview" $null $admin $null).B
      Expect "🔴 وكتابٌ **حيّ** يمنع الحذف" $pv2.canDelete "False"
      Expect "   والسبب HasLiveRecords" $pv2.blockReason "HasLiveRecords"
      Expect "   والبيان يعدّه صادراً حيّاً" ([int]$pv2.liveOutgoing) 1

      # حذفٌ ناعم للكتاب — وهذا ما فعله المالك
      $null = Api DELETE "/outgoing/$bid" $null $admin $cidT

      $pv3 = (Api GET "/companies/$cidT/delete-preview" $null $admin $null).B
      Expect "✅ **وبعد حذفه ناعماً صار الحذف جائزاً** (عين بلاغ المالك)" $pv3.canDelete "True"
      Expect "   والبيان ينقله إلى «محذوف» لا يمحوه" ([int]$pv3.deletedOutgoing) 1
      Expect "   والحيُّ صار صفراً" ([int]$pv3.liveOutgoing) 0
      if([int]$pv3.willBeErased -ge 1){ Ok "   ويُعلَن أنه **سيُمحى فعلياً** ($($pv3.willBeErased))" }
      else { Bad "willBeErased لا يعدّ المحذوف" }

      # 🔴 والجهة: رسالتُها تذكر **المحذوف** صراحةً
      $delEnt = Api DELETE "/entities/$entT" $null $admin $cidT
      $entMsg = if($delEnt.B.message){ $delEnt.B.message } elseif($delEnt.B.detail){ $delEnt.B.detail } else { "$($delEnt.B)" }
      if($delEnt.S -eq 409 -and $entMsg -match "محذوف"){
        Ok "✅ ورسالةُ حذف الجهة **تقول إن الكتاب محذوف** لا «1 صادر» فقط"
      } elseif($delEnt.S -eq 409) { Bad "الجهة مرفوضة لكن الرسالة لا تذكر المحذوف" }
      else { Bad "حذفُ الجهة ردّ $($delEnt.S) بدل 409" }
    } else { Bad "تعذّر إنشاء كتاب الاختبار: $($bk.S)" }
  } else { Bad "تعذّر تجهيز جهة/قالب لشركة الحذف" }

  # ── ٦) الحذف الناجح — ونسخةٌ قبله ──
  $backupsBefore = @((Api GET "/backup" $null $admin $null).B).Count
  $d4 = Api DELETE "/companies/$cidT`?confirm=$([uri]::EscapeDataString($nameT))" $null $admin $null
  Expect "✅ الحذف يبدأ في الخلفية بعد التعطيل والتأكيد" $d4.S 202
  $d4Job = WaitJob $d4 $admin
  Expect "   والحذف اكتمل" $d4Job.state "Succeeded"

  if($d4Job.state -eq 'Succeeded'){
    $gone = Api GET "/companies/$cidT" $null $admin $null
    Expect "   والشركة اختفت" $gone.S 404
    $backupsAfter = @((Api GET "/backup" $null $admin $null).B).Count
    if($backupsAfter -gt $backupsBefore){ Ok "🗄️ **ونسخةٌ احتياطية أُخذت قبل الحذف** ($backupsBefore ⟵ $backupsAfter)" }
    else { Bad "لم تُؤخذ نسخةٌ قبل الحذف (قبل=$backupsBefore بعد=$backupsAfter)" }
  }
}

Write-Host "`n=== النتيجة ===" -ForegroundColor Cyan
Write-Host "نجح: $pass" -ForegroundColor Green
Write-Host "فشل: $fail" -ForegroundColor $(if($fail -eq 0){'Green'}else{'Red'})
if($fail -gt 0){ exit 1 }
