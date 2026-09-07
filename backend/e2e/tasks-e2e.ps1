param([string]$AdminPwd='Speed3ds', [string]$Base='http://localhost:5080/api')
$ErrorActionPreference='Stop'; $pass=0; $fail=0
function Ok($m){ $script:pass++; Write-Host "  [نجح] $m" -ForegroundColor Green }
function Bad($m){ $script:fail++; Write-Host "  [فشل] $m" -ForegroundColor Red }
function Api($m,$u,$b,$t,$c){ $h=@{}; if($t){$h.Authorization="Bearer $t"}; if($c){$h."X-Company-Id"="$c"}
  $p=@{Uri="$Base$u";Method=$m;Headers=$h;ContentType="application/json; charset=utf-8"}
  if($null -ne $b){$p.Body=[Text.Encoding]::UTF8.GetBytes(($b|ConvertTo-Json -Depth 8 -Compress))}
  try{$r=Invoke-WebRequest @p -UseBasicParsing; $j=$null; if($r.Content){try{$j=$r.Content|ConvertFrom-Json}catch{}}; return @{S=[int]$r.StatusCode;B=$j}}
  catch{$resp=$_.Exception.Response; $code=if($resp){[int]$resp.StatusCode}else{0}; $ct=''; if($resp){$sr=[IO.StreamReader]::new($resp.GetResponseStream());$ct=$sr.ReadToEnd()}; $j=$null; if($ct){try{$j=$ct|ConvertFrom-Json}catch{}}; return @{S=$code;B=$j}}
}

# ⚠️ **المطابقة بالمعرّفات الرقمية لا بالأسماء العربية** — PS 5.1 يشوّه العربية العائدة من
#    الـAPI فتفشل المطابقة صامتةً (درسٌ مسجَّل من وحدة الرواتب).
# ⚠️ **و`@((Api ...).B)` لا `@(Api ...).B`** — الثانية تضيع معها `.Count` حين تكون القائمة
#    من عنصرٍ واحد، فتُبلّغ «فارغة» وهي ليست كذلك (G17).

Write-Host "=== إعداد ===" -ForegroundColor Cyan
$admin=(Api POST "/auth/login" @{username='admin';password=$AdminPwd} $null $null).B.accessToken
if(-not $admin){ Bad "تعذّر دخول admin"; exit 1 }

$companies=@((Api GET "/companies" $null $admin $null).B)
if($companies.Count -lt 1){ Bad "لا توجد شركات"; exit 1 }
$cid=[int]$companies[0].companyId
$cid2=if($companies.Count -ge 2){[int]$companies[1].companyId}else{0}
Ok "الشركة الفعّالة: $cid"

$depts=@((Api GET "/departments" $null $admin $cid).B)
$dep=$depts | Where-Object { $_.name -eq 'TASKS-DEP' } | Select-Object -First 1
if(-not $dep){ $dep=(Api POST "/departments" @{companyId=$cid;name='TASKS-DEP';isActive=$true} $admin $cid).B }
$depId=[int]$dep.departmentId
Ok "قسم الاختبار: $depId"

function UpsertUser($username,$displayName,$role,$modules,$canTasks,$departmentId){
  $ex=(Api GET "/users" $null $admin $cid).B | Where-Object { $_.username -eq $username } | Select-Object -First 1
  $body=@{fullName=$displayName;role=$role;isActive=$true;companies=@(
    @{companyId=$cid;modules=$modules;departmentId=$departmentId;canManageTasks=$canTasks})}
  if($ex){ $null=Api PUT "/users/$($ex.userId)" $body $admin $cid }
  else { $body.username=$username; $body.password='Tsk@12345'; $null=Api POST "/users" $body $admin $cid }
  return (Api GET "/users" $null $admin $cid).B | Where-Object { $_.username -eq $username } | Select-Object -First 1
}
function UserLogin($u){ (Api POST "/auth/login" @{username=$u;password='Tsk@12345'} $null $null).B.accessToken }

$mng=UpsertUser 'tsk_mgr' 'مدير المهام' 'Employee' @('Outgoing','Tasks') $true $depId
$wrk=UpsertUser 'tsk_wrk' 'موظف المهام' 'Employee' @('Outgoing','Tasks') $false $depId
$out=UpsertUser 'tsk_out' 'موظف خارج القسم' 'Employee' @('Outgoing','Tasks') $false $null
$rdr=UpsertUser 'tsk_rdr' 'قارئ المهام' 'Reader' @('Outgoing','Tasks') $true $null
Ok "أربعة مستخدمين: مدير مهام · موظف · خارج القسم · قارئ"

$tMng=UserLogin 'tsk_mgr'; $tWrk=UserLogin 'tsk_wrk'; $tOut=UserLogin 'tsk_out'; $tRdr=UserLogin 'tsk_rdr'
if($tMng -and $tWrk -and $tOut -and $tRdr){ Ok "دخول الأربعة" } else { Bad "تعذّر دخول أحدهم"; exit 1 }

$today=(Get-Date).Date
$due=$today.AddDays(7).ToString('yyyy-MM-ddT00:00:00')
$past=$today.AddDays(-3).ToString('yyyy-MM-ddT00:00:00')

Write-Host "`n=== الترقيم والإنشاء ===" -ForegroundColor Cyan
$t1=(Api POST "/tasks" @{title='مهمة الاختبار الأولى';taskType='Individual';priority='High';dueDate=$due} $tMng $cid)
if($t1.S -eq 200 -and $t1.B.taskId){ Ok "أُنشئت المهمة ($($t1.B.taskId))" } else { Bad "تعذّر الإنشاء: $($t1.S)"; exit 1 }
$id1=[int]$t1.B.taskId
if($t1.B.taskNumber -match '-TSK-\d{4}-\d{5}$'){ Ok "الرقم بصيغته: $($t1.B.taskNumber)" } else { Bad "صيغة الرقم: $($t1.B.taskNumber)" }
if($t1.B.status -eq 'New'){ Ok "تبدأ (جديدة)" } else { Bad "بدأت بـ$($t1.B.status)" }
if($t1.B.progressPercent -eq 0){ Ok "ونسبتها صفر" } else { Bad "نسبتها $($t1.B.progressPercent)" }

$t2=(Api POST "/tasks" @{title='مهمة الاختبار الثانية';taskType='Individual';priority='Normal';dueDate=$due} $tMng $cid)
$id2=[int]$t2.B.taskId
$n1=[int]($t1.B.taskNumber -split '-')[-1]; $n2=[int]($t2.B.taskNumber -split '-')[-1]
if($n2 -eq $n1+1){ Ok "الترقيم متسلسل بلا ثقوب ($n1 ثم $n2)" } else { Bad "تسلسل: $n1 ثم $n2" }

Write-Host "`n=== العقد: كل حقلٍ محسوبٍ يعبر ===" -ForegroundColor Cyan
$g=(Api GET "/tasks/$id1" $null $tMng $cid).B
foreach($f in @('statusLabel','priorityLabel','taskTypeLabel','createdByUserName','rowVersion')){
  if($g.$f){ Ok "الحقل المحسوب $f يصل: $($g.$f)" } else { Bad "الحقل $f فارغ في العقد" }
}
if($g.isOverdue -eq $false){ Ok "isOverdue تصل (false لمهمة مستقبلية)" } else { Bad "isOverdue=$($g.isOverdue)" }
if($g.daysRemaining -eq 7){ Ok "daysRemaining محسوبة = 7" } else { Bad "daysRemaining=$($g.daysRemaining)" }
if(@($g.nextStatuses).Count -eq 2){ Ok "nextStatuses من مصفوفة المجال (2)" } else { Bad "nextStatuses=$(@($g.nextStatuses).Count)" }
if($g.canEdit -eq $true){ Ok "canEdit تصل — فلا تُعرض أزرارٌ تردّ 403" } else { Bad "canEdit=$($g.canEdit)" }

Write-Host "`n=== الموعد الماضي: مرفوضٌ إنشاءً مقبولٌ تعديلاً ===" -ForegroundColor Cyan
$bad=(Api POST "/tasks" @{title='ماضية';taskType='Individual';priority='Low';dueDate=$past} $tMng $cid)
if($bad.S -eq 400){ Ok "الإنشاء بموعدٍ ماضٍ مرفوض (400)" } else { Bad "ردّ $($bad.S)" }
# ⚠️ **بسببٍ الآن**: تغيير الموعد يمسّ غيرك (يحكم التأخّر والتصعيد) فيلزمه تعليل — ADR-037.
$updNoReason=(Api PUT "/tasks/$id2" @{title='مهمة الاختبار الثانية';priority='Normal';dueDate=$past;rowVersion=$t2.B.rowVersion} $tMng $cid)
if($updNoReason.S -eq 400){ Ok "🔐 وتعديل الموعد بلا سبب مرفوض" } else { Bad "ردّ $($updNoReason.S)" }
$upd=(Api PUT "/tasks/$id2" @{title='مهمة الاختبار الثانية';priority='Normal';dueDate=$past;rowVersion=$t2.B.rowVersion;reason='تصحيح تاريخٍ أُدخل خطأً'} $tMng $cid)
if($upd.S -eq 200){ Ok "والتعديل إليه مقبول بسببٍ — قد يكون تصحيحاً لتاريخٍ خطأ" } else { Bad "التعديل ردّ $($upd.S)" }
if($upd.B.isOverdue -eq $true){ Ok "وصارت متأخرةً فوراً — «متأخر» محسوبٌ لا مخزَّن" } else { Bad "isOverdue=$($upd.B.isOverdue)" }
if($upd.B.daysOverdue -eq 3){ Ok "وتأخّرها 3 أيام بالضبط" } else { Bad "daysOverdue=$($upd.B.daysOverdue)" }

Write-Host "`n=== مصفوفة الانتقالات المغلقة ===" -ForegroundColor Cyan
$r=(Api POST "/tasks/$id1/status" @{newStatus='Completed'} $tMng $cid)
if($r.S -eq 400){ Ok "القفز من (جديدة) إلى (مكتملة) مرفوض" } else { Bad "ردّ $($r.S)" }
$r=(Api POST "/tasks/$id1/status" @{newStatus='OnHold'} $tMng $cid)
if($r.S -eq 400){ Ok "وتعليقُ ما لم يبدأ مرفوض" } else { Bad "ردّ $($r.S)" }
$r=(Api POST "/tasks/$id1/status" @{newStatus='InProgress'} $tMng $cid)
if($r.S -eq 200 -and $r.B.status -eq 'InProgress'){ Ok "الانتقال إلى (قيد التنفيذ) مقبول" } else { Bad "ردّ $($r.S)" }
if($r.B.startDate){ Ok "وتاريخ البدء سُجِّل تلقائياً" } else { Bad "تاريخ البدء فارغ" }
$startFirst=$r.B.startDate
$null=Api POST "/tasks/$id1/status" @{newStatus='OnHold'} $tMng $cid
$r=(Api POST "/tasks/$id1/status" @{newStatus='InProgress'} $tMng $cid)
if($r.B.startDate -eq $startFirst){ Ok "والاستئناف بعد تعليقٍ لا يُزيح تاريخ البدء" } else { Bad "أُزيح تاريخ البدء" }
$r=(Api POST "/tasks/$id1/status" @{newStatus='InProgress'} $tMng $cid)
if($r.S -eq 400){ Ok "والبقاء على الحالة نفسها ليس انتقالاً" } else { Bad "ردّ $($r.S)" }

Write-Host "`n=== النسبة لا تُكمل المهمة ===" -ForegroundColor Cyan
$r=(Api POST "/tasks/$id1/progress" @{percent=100} $tMng $cid)
if($r.S -eq 200 -and $r.B.progressPercent -eq 100){ Ok "النسبة صارت 100" } else { Bad "ردّ $($r.S)" }
if($r.B.status -eq 'InProgress'){ Ok "والحالة لم تتغيّر — الإكمال قرارٌ صريح لا اشتقاقٌ من رقم" } else { Bad "الحالة صارت $($r.B.status)" }
$r=(Api POST "/tasks/$id1/progress" @{percent=140} $tMng $cid)
if($r.S -eq 400){ Ok "ونسبةٌ خارج 0..100 مرفوضة" } else { Bad "ردّ $($r.S)" }

Write-Host "`n=== إعادة الفتح: حارسٌ مضاعف ===" -ForegroundColor Cyan
$null=Api POST "/tasks/$id1/status" @{newStatus='Completed'} $tMng $cid
$r=(Api GET "/tasks/$id1" $null $tMng $cid)
if($r.B.completedDate){ Ok "الإكمال سجّل تاريخه" } else { Bad "تاريخ الإكمال فارغ" }
$r=(Api POST "/tasks/$id1/reopen" @{reason='قصير'} $admin $cid)
if($r.S -eq 400){ Ok "سببٌ دون خمسة أحرف مرفوض" } else { Bad "ردّ $($r.S)" }
$r=(Api POST "/tasks/$id1/reopen" @{reason='المخرجات ناقصة وتحتاج مراجعة'} $tMng $cid)
if($r.S -eq 403){ Ok "والموظف لا يعيد الفتح ولو ملك علَم الإدارة" } else { Bad "ردّ $($r.S)" }
$r=(Api POST "/tasks/$id1/reopen" @{reason='المخرجات ناقصة وتحتاج مراجعة'} $admin $cid)
if($r.S -eq 200 -and $r.B.status -eq 'Reopened'){ Ok "والمدير فأعلى يعيد الفتح بسببٍ كافٍ" } else { Bad "ردّ $($r.S)" }
if(-not $r.B.completedDate){ Ok "وتاريخ الإكمال صُفِّر — وإلا بقيت مكتملةً في التقرير" } else { Bad "تاريخ الإكمال باقٍ" }
$r=(Api POST "/tasks/$id1/status" @{newStatus='Reopened'} $admin $cid)
if($r.S -eq 400){ Ok "وإعادة الفتح لا تمرّ من نقطة الحالة العامة (تتخطّى حارسها)" } else { Bad "ردّ $($r.S)" }

Write-Host "`n=== الإلغاء نهائيّ ===" -ForegroundColor Cyan
$tc=(Api POST "/tasks" @{title='مهمة ستُلغى';taskType='Individual';priority='Low';dueDate=$due} $tMng $cid).B
$null=Api POST "/tasks/$($tc.taskId)/status" @{newStatus='Cancelled'} $tMng $cid
foreach($s in @('InProgress','Completed','Reopened','New')){
  $r=(Api POST "/tasks/$($tc.taskId)/status" @{newStatus=$s} $admin $cid)
  if($r.S -eq 400){ Ok "لا مخرج من (ملغاة) إلى ($s)" } else { Bad "($s) ردّ $($r.S)" }
}

Write-Host "`n=== الإسناد: قسرٌ لا رفض ===" -ForegroundColor Cyan
$mngId=[int]$mng.userId
$t=(Api POST "/tasks" @{title='يحاول الإسناد لغيره';taskType='Individual';priority='Normal';dueDate=$due;assignedToUserId=$mngId} $tWrk $cid)
if($t.S -eq 200){ Ok "الطلب قُبل ولم يُرفض — نموذجٌ لا يفشل بلا سببٍ مفهوم" } else { Bad "ردّ $($t.S)" }
if([int]$t.B.assignedToUserId -eq [int]$wrk.userId){ Ok "وأُسنِد لنفسه قسراً لا لمن طلب" } else { Bad "أُسنِد إلى $($t.B.assignedToUserId)" }
$idW=[int]$t.B.taskId

$r=(Api POST "/tasks/$idW/reassign" @{assignedToUserId=$mngId} $tWrk $cid)
if($r.S -eq 403){ Ok "ولا يملك إعادة الإسناد" } else { Bad "ردّ $($r.S)" }
$r=(Api POST "/tasks/$idW/reassign" @{assignedToUserId=$mngId} $tMng $cid)
if($r.S -eq 200 -and [int]$r.B.assignedToUserId -eq $mngId){ Ok "وصاحبُ العلَم يُسنِد" } else { Bad "ردّ $($r.S)" }
$r=(Api POST "/tasks/$idW/reassign" @{assignedToUserId=[int]$rdr.userId} $tMng $cid)
if($r.S -eq 400){ Ok "والإسناد لقارئ مرفوض — لا يرى الوحدة فلا يبلغه عملُه" } else { Bad "ردّ $($r.S)" }
$r=(Api GET "/tasks/assignable-users" $null $tMng $cid)
$assignable=@($r.B)
if($assignable.Count -gt 0 -and -not ($assignable | Where-Object { $_.role -eq 'Reader' })){ Ok "وقائمة المسؤولين بلا قارئ ($($assignable.Count))" } else { Bad "القائمة فيها قارئ أو فارغة" }
$r=(Api GET "/tasks/assignable-users" $null $tWrk $cid)
if($r.S -eq 403){ Ok "وهي محجوبة عمّن لا يملك العلَم" } else { Bad "ردّ $($r.S)" }

Write-Host "`n=== مهمة القسم: يراها كل موظفيه ===" -ForegroundColor Cyan
$bad=(Api POST "/tasks" @{title='قسم بلا قسم';taskType='Department';priority='Normal';dueDate=$due} $tMng $cid)
if($bad.S -eq 400){ Ok "مهمة قسمٍ بلا قسم مرفوضة" } else { Bad "ردّ $($bad.S)" }
$td=(Api POST "/tasks" @{title='مهمة قسم';taskType='Department';priority='High';dueDate=$due;departmentId=$depId} $tMng $cid)
$idD=[int]$td.B.taskId
if($td.S -eq 200 -and $td.B.departmentName){ Ok "أُنشئت مهمة القسم واسمُ القسم يصل" } else { Bad "ردّ $($td.S)" }
$r=(Api GET "/tasks/$idD" $null $tWrk $cid)
if($r.S -eq 200){ Ok "وموظف القسم يراها ولم يُنشئها ولم تُسنَد إليه" } else { Bad "ردّ $($r.S)" }
$r=(Api POST "/tasks/$idD/progress" @{percent=25} $tWrk $cid)
if($r.S -eq 200){ Ok "ويحدّثها (قرار المالك: كل موظفي القسم)" } else { Bad "ردّ $($r.S)" }
$r=(Api GET "/tasks/$idD" $null $tOut $cid)
if($r.S -eq 404){ Ok "ومَن خارج القسم لا يراها (404 لا 403 — لا يُفشى وجودُها)" } else { Bad "ردّ $($r.S)" }

Write-Host "`n=== التزامن المتفائل ===" -ForegroundColor Cyan
$cur=(Api GET "/tasks/$idD" $null $tMng $cid).B
$stale=$cur.rowVersion
$null=Api PUT "/tasks/$idD" @{title='عنوانٌ جديد';priority='High';dueDate=$due;departmentId=$depId;rowVersion=$stale;reason='تصحيح العنوان'} $tMng $cid
$r=(Api PUT "/tasks/$idD" @{title='عنوانٌ ثالث';priority='High';dueDate=$due;departmentId=$depId;rowVersion=$stale;reason='تصحيح العنوان ثانيةً'} $tMng $cid)
# 🔴 **وترتيب الحارسين جزءٌ من العقد**: فحصُ السبب **قبل** `SetRowVersion` — فرفضٌ بلا سببٍ
#    يجب ألّا يستهلك محاولة تزامن. ولهذا يصل هذا الطلب (وله سبب) إلى حارس التزامن فيردّ 409.
if($r.S -eq 409){ Ok "الكتابة بنسخةٍ قديمة تُرفض (409)" } else { Bad "ردّ $($r.S)" }

Write-Host "`n=== السجلّ الشاهد ===" -ForegroundColor Cyan
$ups=@((Api GET "/tasks/$id1/updates" $null $tMng $cid).B)
if($ups.Count -ge 5){ Ok "سجلّ المهمة يحمل $($ups.Count) قيداً" } else { Bad "السجلّ فيه $($ups.Count) فقط" }
if($ups | Where-Object { $_.updateType -eq 'Created' }){ Ok "وفيه قيد الإنشاء" } else { Bad "لا قيد إنشاء" }
if($ups | Where-Object { $_.updateType -eq 'Reopen' }){ Ok "وقيد إعادة الفتح" } else { Bad "لا قيد إعادة فتح" }
$withName=@($ups | Where-Object { $_.updatedByUserName -and $_.updatedByUserName -ne '—' })
if($withName.Count -eq $ups.Count){ Ok "وكل قيدٍ يحمل اسم فاعله (لا سطرَ بلا فاعل)" } else { Bad "$($ups.Count - $withName.Count) قيداً بلا فاعل" }

# 🔴 **الحارس الذي كشف العيب — والذي لا يكشفه الذي قبله**: قيدُ إعادة الفتح كتبه **سوبر أدمن
#    غير مُسنَد لشركة**، و`Include` على خاصيةٍ إلزامية يولّد INNER JOIN على `Users` المفلتَر
#    فيُسقط **القيد كلَّه** لا اسمَ فاعله. والحارسُ أعلاه أعمى عنه: الصفّ لا يُفرَّغ بل يُحذف،
#    فتبقى كلُّ السطور الباقية بأسماء. (ADR-034 يتكرّر — انظر `GetUpdatesAsync`.)
$adminRows=@($ups | Where-Object { $_.updateType -eq 'Reopen' })
if($adminRows.Count -ge 1){ Ok "وقيدٌ كتبه سوبر أدمن بلا شركة يبقى في السجلّ (حارس ADR-034)" }
else { Bad "قيد السوبر أدمن سقط من الاستجابة — ربطٌ داخليّ يمحو سطوراً" }
$expected=7
if($ups.Count -eq $expected){ Ok "وعدد القيود $expected بالضبط — لا سطرَ يضيع صامتاً" }
else { Bad "القيود $($ups.Count) والمتوقّع $expected" }
$r=(Api POST "/tasks/$id1/comment" @{text='تعليق اختباري على المهمة'} $tMng $cid)
if($r.S -eq 200 -and $r.B.updateType -eq 'Comment'){ Ok "والتعليق يُضاف كقيدٍ في السجلّ" } else { Bad "ردّ $($r.S)" }

Write-Host "`n=== المرفقات: قاعدة الرؤية نفسها لا نسخةٌ منها ===" -ForegroundColor Cyan
$tmp=[IO.Path]::GetTempFileName(); [IO.File]::WriteAllText($tmp,'task attachment test')
$boundary=[Guid]::NewGuid().ToString()
function UploadFile($taskId,$tok){
  $fileBytes=[IO.File]::ReadAllBytes($tmp)
  $enc=[Text.Encoding]::GetEncoding('iso-8859-1')
  $body="--$boundary`r`nContent-Disposition: form-data; name=`"file`"; filename=`"note.pdf`"`r`nContent-Type: text/plain`r`n`r`n$($enc.GetString($fileBytes))`r`n--$boundary--`r`n"
  $h=@{Authorization="Bearer $tok";"X-Company-Id"="$cid"}
  try{$r=Invoke-WebRequest -Uri "$Base/tasks/$taskId/attachments" -Method POST -Headers $h -ContentType "multipart/form-data; boundary=$boundary" -Body $enc.GetBytes($body) -UseBasicParsing
      return @{S=[int]$r.StatusCode;B=($r.Content|ConvertFrom-Json)}}
  catch{$resp=$_.Exception.Response; return @{S=$(if($resp){[int]$resp.StatusCode}else{0});B=$null}}
}
$up=UploadFile $idD $tMng
if($up.S -eq 200){ Ok "رُفع مرفقٌ على المهمة" } else { Bad "الرفع ردّ $($up.S)" }
$atts=@((Api GET "/tasks/$idD/attachments" $null $tMng $cid).B)
if($atts.Count -ge 1){ Ok "ويظهر في القائمة ($($atts.Count))" } else { Bad "القائمة فارغة" }
$r=(Api GET "/tasks/$idD/attachments" $null $tWrk $cid)
if($r.S -eq 200){ Ok "وموظف القسم يبلغ مرفقاتها — الرؤية واحدةٌ للمهمة ولمرفقها" } else { Bad "ردّ $($r.S)" }
$r=(Api GET "/tasks/$idD/attachments" $null $tOut $cid)
if($r.S -eq 404){ Ok "ومَن لا يرى المهمة لا يبلغ مرفقاتها" } else { Bad "ردّ $($r.S)" }
Remove-Item $tmp -Force -ErrorAction SilentlyContinue

Write-Host "`n=== القارئ محجوبٌ عن كل النقاط ===" -ForegroundColor Cyan
$rdrMods=@($rdr.companies[0].modules)
if($rdrMods -notcontains 'Tasks'){ Ok "قسم المهام جُرِّد من القارئ رغم طلبه صراحةً" } else { Bad "تسرّب: القارئ احتفظ بالقسم" }
if(-not $rdr.companies[0].canManageTasks){ Ok "وعلَم الإدارة جُرِّد معه — لا علَمَ بلا قسمه" } else { Bad "تسرّب: علَم الإدارة باقٍ" }
foreach($ep in @("/tasks","/tasks/summary","/tasks/overdue","/tasks/my","/tasks/assignable-users","/tasks/$id1")){
  $r=(Api GET $ep $null $tRdr $cid)
  if($r.S -eq 403){ Ok "القارئ محجوب عن $ep (403)" } else { Bad "تسرّب: $ep ردّ $($r.S)" }
}
$r=(Api POST "/tasks" @{title='من قارئ';taskType='Individual';priority='Low';dueDate=$due} $tRdr $cid)
if($r.S -eq 403){ Ok "ولا يُنشئ مهمة (403)" } else { Bad "ردّ $($r.S)" }

Write-Host "`n=== 🔴 مهمةٌ أنشأها السوبر أدمن (حارس ADR-034) ===" -ForegroundColor Cyan
# 🔴 **بلاغ المالك 2026-09-06: «السوبر أدمن لا يستطيع إنشاء مهمة».** والحقيقة أن المهمة
#    تُنشأ ثم يردّ الخادم 404 عند قراءتها — لأن `Include(t => t.CreatedByUser)` على خاصيةٍ
#    **إلزامية** يولّد INNER JOIN على `Users` المفلتَر، والسوبر أدمن **بلا شركة مُسنَدة**
#    فيسقط صفُّه ⇒ **تسقط المهمة كلُّها**. وهو ADR-034 للمرّة الثالثة في هذه الوحدة.
$sa=(Api POST "/tasks" @{title='مهمة أنشأها السوبر أدمن';taskType='Individual';priority='Normal';dueDate=$due} $admin $cid)
if($sa.S -eq 200 -and $sa.B.taskId){ Ok "السوبر أدمن يُنشئ مهمة ($($sa.B.taskId))" } else { Bad "الإنشاء ردّ $($sa.S)" }
$idSa=[int]$sa.B.taskId
if($sa.B.createdByUserName){ Ok "واسم مُنشئها يصل: $($sa.B.createdByUserName)" } else { Bad "اسم المُنشئ فارغ" }

$re=(Api GET "/tasks/$idSa" $null $admin $cid)
if($re.S -eq 200){ Ok "🔴 وتُقرأ بعد الإنشاء (لا 404) — الربط الداخليّ لم يمحُها" }
else { Bad "قراءتها ردّت $($re.S) — الربط الداخليّ يمحو المهمة" }

$saList=(Api GET "/tasks?pageSize=200" $null $admin $cid).B
$found=@(@($saList.items) | Where-Object { [int]$_.taskId -eq $idSa })
if($found.Count -eq 1){ Ok "وتظهر في القائمة" } else { Bad "سقطت من القائمة" }

# 🔴 **والعدّاد كان يكذب كذلك**: `CountAsync` يعدّ بلا ربط، والصفحة تُسقط ما يُسقطه الربط.
if($saList.total -eq @($saList.items).Count){ Ok "🔴 والعدّاد يطابق ما تُرجعه القائمة ($($saList.total))" }
else { Bad "العدّاد $($saList.total) والقائمة $(@($saList.items).Count) — الربط يُسقط صفوفاً يعدّها العدّاد" }

$reassignSa=(Api POST "/tasks/$idSa/reassign" @{assignedToUserId=$mngId} $admin $cid)
if($reassignSa.S -eq 200){ Ok "وإعادة إسنادها تعمل" } else { Bad "إعادة الإسناد ردّت $($reassignSa.S)" }

Write-Host "`n=== سببٌ عند التراجع وعند التعديل الجوهريّ ===" -ForegroundColor Cyan
$tr=(Api POST "/tasks" @{title='مهمة لفحص الأسباب';taskType='Individual';priority='Normal';dueDate=$due} $tMng $cid).B
$idR=[int]$tr.taskId
$null=Api POST "/tasks/$idR/status" @{newStatus='InProgress'} $tMng $cid
$null=Api POST "/tasks/$idR/progress" @{percent=75} $tMng $cid

$back=(Api POST "/tasks/$idR/progress" @{percent=25} $tMng $cid)
if($back.S -eq 400){ Ok "🔐 تقليل النسبة بلا سبب مرفوض (400)" } else { Bad "ردّ $($back.S)" }
$backShort=(Api POST "/tasks/$idR/progress" @{percent=25;reason='قصير'} $tMng $cid)
if($backShort.S -eq 400){ Ok "وسببٌ دون خمسة أحرف مرفوض" } else { Bad "ردّ $($backShort.S)" }
$backOk=(Api POST "/tasks/$idR/progress" @{percent=25;reason='انكشف عملٌ ناقص في التقرير'} $tMng $cid)
if($backOk.S -eq 200 -and $backOk.B.progressPercent -eq 25){ Ok "وبسببٍ كافٍ يمرّ" } else { Bad "ردّ $($backOk.S)" }

$fwd=(Api POST "/tasks/$idR/progress" @{percent=50} $tMng $cid)
if($fwd.S -eq 200){ Ok "🔴 والتقدّم لا يحتاج سبباً — القاعدة تفرّق بين النقض والإنجاز" } else { Bad "ردّ $($fwd.S)" }

$cur=(Api GET "/tasks/$idR" $null $tMng $cid).B
$editNoReason=(Api PUT "/tasks/$idR" @{title='عنوانٌ مختلف تماماً';priority='Normal';dueDate=$due;rowVersion=$cur.rowVersion} $tMng $cid)
if($editNoReason.S -eq 400){ Ok "🔐 وتغيير العنوان بلا سبب مرفوض" } else { Bad "ردّ $($editNoReason.S)" }

$cur=(Api GET "/tasks/$idR" $null $tMng $cid).B
$editMinor=(Api PUT "/tasks/$idR" @{title=$cur.title;description='وصفٌ جديد';priority=$cur.priority;dueDate=$due;rowVersion=$cur.rowVersion} $tMng $cid)
if($editMinor.S -eq 200){ Ok "🔴 وتصحيح الوصف يمرّ بلا سبب — فلا يصير الحقل شكليّاً" } else { Bad "ردّ $($editMinor.S)" }

$cur=(Api GET "/tasks/$idR" $null $tMng $cid).B
$editOk=(Api PUT "/tasks/$idR" @{title='عنوانٌ مختلف تماماً';priority='Normal';dueDate=$due;rowVersion=$cur.rowVersion;reason='تصحيح العنوان بطلب المدير'} $tMng $cid)
if($editOk.S -eq 200){ Ok "وبسببٍ كافٍ يمرّ التعديل الجوهريّ" } else { Bad "ردّ $($editOk.S)" }

$upsR=@((Api GET "/tasks/$idR/updates" $null $tMng $cid).B)
$withReason=@($upsR | Where-Object { $_.comment -and $_.comment -like '*انكشف*' })
if($withReason.Count -ge 1){ Ok "🔴 وسبب التراجع محفوظٌ في السجلّ يقرؤه غيرُك" } else { Bad "سبب التراجع غير محفوظ" }

Write-Host "`n=== الفلاتر والملخّص ===" -ForegroundColor Cyan
$lst=(Api GET "/tasks?pageSize=100" $null $tMng $cid).B
if($lst.total -ge 4){ Ok "القائمة تُرجع $($lst.total) مهمة" } else { Bad "الإجمالي $($lst.total)" }
$ov=(Api GET "/tasks?isOverdue=true&pageSize=100" $null $tMng $cid).B
$notOverdue=@(@($ov.items) | Where-Object { -not $_.isOverdue })
if($notOverdue.Count -eq 0){ Ok "وفلتر (متأخرة) لا يسرّب غير المتأخّرة" } else { Bad "$($notOverdue.Count) صفّاً غير متأخّر" }
$byStatus=(Api GET "/tasks?status=Cancelled&pageSize=100" $null $tMng $cid).B
$wrongStatus=@(@($byStatus.items) | Where-Object { $_.status -ne 'Cancelled' })
if($wrongStatus.Count -eq 0){ Ok "وفلتر الحالة كذلك" } else { Bad "$($wrongStatus.Count) صفّاً بحالةٍ أخرى" }
$mine=(Api GET "/tasks/my?pageSize=100" $null $tWrk $cid).B
$notMine=@(@($mine.items) | Where-Object { [int]$_.assignedToUserId -ne [int]$wrk.userId })
if($notMine.Count -eq 0){ Ok "و(مهامي) لا تُرجع مهامّ غيري" } else { Bad "$($notMine.Count) مهمةً لغيره" }
$sm=(Api GET "/tasks/summary" $null $tMng $cid).B
if($null -ne $sm.total -and $null -ne $sm.overdue){ Ok "الملخّص يصل (إجمالي=$($sm.total) متأخر=$($sm.overdue))" } else { Bad "الملخّص ناقص" }

Write-Host "`n=== 👥 المشاركون: مَن يرى المهمة غير مسؤولها (ADR-037) ===" -ForegroundColor Cyan
# 🔴 **بلاغ المالك**: إعادة الإسناد كانت **تستبدل** فيفقد السابقُ رؤية المهمة صامتاً، ولم
#    يكن ثمّة سبيلٌ لإشراك قسمٍ ثانٍ أو شخصٍ ثانٍ. والنموذج المُعتمَد: **مسؤولٌ واحد محاسَب
#    + مشاركون كُثر**.
$tp=(Api POST "/tasks" @{title='مهمة المشاركين';taskType='Individual';priority='Normal';dueDate=$due;assignedToUserId=$mngId} $tMng $cid).B
$idP=[int]$tp.taskId
$outId=[int]$out.userId

# ── العزل قبل الإشراك ──
$r=(Api GET "/tasks/$idP" $null $tOut $cid)
if($r.S -eq 404){ Ok "🔐 مَن خارج المهمة لا يراها قبل إشراكه (404)" } else { Bad "ردّ $($r.S)" }

# ── إشراك شخص ──
$add=(Api POST "/tasks/$idP/participants" @{userId=$outId;note='للمتابعة'} $tMng $cid)
if($add.S -eq 200){ Ok "أُشرِك شخصٌ في المهمة" } else { Bad "الإشراك ردّ $($add.S)" }
$r=(Api GET "/tasks/$idP" $null $tOut $cid)
if($r.S -eq 200){ Ok "🔴 وصار يراها فوراً — وهذا جوهر الطلب" } else { Bad "ردّ $($r.S)" }
$lstOut=(Api GET "/tasks?pageSize=200" $null $tOut $cid).B
if(@(@($lstOut.items) | Where-Object { [int]$_.taskId -eq $idP }).Count -eq 1){ Ok "وتظهر في قائمته" } else { Bad "لا تظهر في قائمته" }

# ── الإزالة تنزع الرؤية ──
$plist=@((Api GET "/tasks/$idP/participants" $null $tMng $cid).B)
$partId=[int](@($plist | Where-Object { [int]$_.userId -eq $outId })[0].participantId)
$rm=(Api DELETE "/tasks/$idP/participants/$partId" $null $tMng $cid)
if($rm.S -eq 204){ Ok "وأُزيل من المشاركين (204)" } else { Bad "الإزالة ردّت $($rm.S)" }
$r=(Api GET "/tasks/$idP" $null $tOut $cid)
if($r.S -eq 404){ Ok "🔴 وفقد رؤيتها فوراً — شرط `!IsRemoved` يحرس" } else { Bad "تسرّب: ردّ $($r.S)" }

# ── وسطرُه يبقى شاهداً ──
$plist2=@((Api GET "/tasks/$idP/participants" $null $tMng $cid).B)
$removedRow=@($plist2 | Where-Object { [int]$_.participantId -eq $partId })
if($removedRow.Count -eq 1 -and $removedRow[0].isRemoved){ Ok "وسطرُه باقٍ شاهداً على مشاركةٍ وقعت" } else { Bad "سطر المُزال اختفى" }

# ── إعادة الإشراك تُحيي ولا تُكرّر ──
$again=(Api POST "/tasks/$idP/participants" @{userId=$outId} $tMng $cid)
$plist3=@((Api GET "/tasks/$idP/participants" $null $tMng $cid).B)
$forUser=@($plist3 | Where-Object { [int]$_.userId -eq $outId })
if($forUser.Count -eq 1){ Ok "🔴 وإعادة الإشراك **تُحيي السطر ولا تُكرّره** (فهرسٌ فريد مُرشَّح)" } else { Bad "صار له $($forUser.Count) سطراً" }

# ── إشراك قسم ──
$addDep=(Api POST "/tasks/$idP/participants" @{departmentId=$depId} $tMng $cid)
if($addDep.S -eq 200){ Ok "وأُشرِك قسمٌ كذلك" } else { Bad "ردّ $($addDep.S)" }
$r=(Api GET "/tasks/$idP" $null $tWrk $cid)
if($r.S -eq 200){ Ok "🔴 وموظف ذلك القسم صار يراها — وهو طلبك الثاني بعينه" } else { Bad "ردّ $($r.S)" }

# ── أحدُ الحقلين لا كلاهما ──
$bad1=(Api POST "/tasks/$idP/participants" @{} $tMng $cid)
if($bad1.S -eq 400){ Ok "🔐 مشاركٌ بلا مستخدمٍ ولا قسم مرفوض" } else { Bad "ردّ $($bad1.S)" }
$bad2=(Api POST "/tasks/$idP/participants" @{userId=$outId;departmentId=$depId} $tMng $cid)
if($bad2.S -eq 400){ Ok "🔐 والاثنان معاً مرفوضان" } else { Bad "ردّ $($bad2.S)" }

Write-Host "`n=== 🔁 نقل المسؤولية: يُسأل عمّا يحلّ بالسابق ===" -ForegroundColor Cyan
$th=(Api POST "/tasks" @{title='مهمة نقل المسؤولية';taskType='Individual';priority='Normal';dueDate=$due;assignedToUserId=[int]$wrk.userId} $tMng $cid).B
$idH=[int]$th.taskId
$r=(Api GET "/tasks/$idH" $null $tWrk $cid)
if($r.S -eq 200){ Ok "المسؤول الأول يراها" } else { Bad "ردّ $($r.S)" }

# ── الإبقاء (الافتراض) ──
$keep=(Api POST "/tasks/$idH/reassign" @{assignedToUserId=$mngId;keepPreviousAsParticipant=$true} $tMng $cid)
if($keep.S -eq 200 -and [int]$keep.B.assignedToUserId -eq $mngId){ Ok "نُقلت المسؤولية" } else { Bad "ردّ $($keep.S)" }
$r=(Api GET "/tasks/$idH" $null $tWrk $cid)
if($r.S -eq 200){ Ok "🔴 والسابق **بقي يراها** — كان يفقدها صامتاً قبل هذا" } else { Bad "تسرّب: فقد الرؤية رغم الإبقاء ($($r.S))" }
$hist=@((Api GET "/tasks/$idH/updates" $null $tMng $cid).B)
if(@($hist | Where-Object { $_.description -like '*بقي*' }).Count -ge 1){ Ok "والسجلّ يقول صراحةً إنه بقي — لا يُستنتج" } else { Bad "السجلّ لا يذكر مصير السابق" }

# ── النزع ──
$th2=(Api POST "/tasks" @{title='مهمة نزع الرؤية';taskType='Individual';priority='Normal';dueDate=$due;assignedToUserId=[int]$wrk.userId} $tMng $cid).B
$idH2=[int]$th2.taskId
$drop=(Api POST "/tasks/$idH2/reassign" @{assignedToUserId=$mngId;keepPreviousAsParticipant=$false} $tMng $cid)
if($drop.S -eq 200){ Ok "ونقلٌ آخر بنزع الرؤية" } else { Bad "ردّ $($drop.S)" }
$r=(Api GET "/tasks/$idH2" $null $tWrk $cid)
if($r.S -eq 404){ Ok "🔐 والسابق فقد الرؤية — بقرارٍ صريح لا صمتاً" } else { Bad "ردّ $($r.S)" }
$hist2=@((Api GET "/tasks/$idH2/updates" $null $tMng $cid).B)
if(@($hist2 | Where-Object { $_.description -like '*نُزعت*' }).Count -ge 1){ Ok "والسجلّ يقول صراحةً إنها نُزعت" } else { Bad "السجلّ لا يذكر النزع" }

# ── القارئ لا يُشرَك ──
$rdrP=(Api POST "/tasks/$idP/participants" @{userId=[int]$rdr.userId} $tMng $cid)
if($rdrP.S -eq 400){ Ok "🔐 ولا يُشرَك قارئ — لا يرى الوحدة فلا يبلغه عملُه" } else { Bad "ردّ $($rdrP.S)" }

Write-Host "`n=== 🔔 الإشعارات (ADR-038) ===" -ForegroundColor Cyan
# 🔐 **ثلاث قواعد أمنية**: الإشعار ملكُ صاحبه · و`read` على إشعار غيرك **404 لا 403** ·
#    والفاعلُ **لا يُشعَر بفعل نفسه**.
$before=(Api GET "/notifications/unread-count" $null $tWrk $cid).B
$tn=(Api POST "/tasks" @{title='مهمة تُشعِر مسؤولها';taskType='Individual';priority='Normal';dueDate=$due;assignedToUserId=[int]$wrk.userId} $tMng $cid)
if($tn.S -eq 200){ Ok "أُنشئت مهمةٌ لمسؤولٍ آخر" } else { Bad "ردّ $($tn.S)" }
$idN=[int]$tn.B.taskId

$after=(Api GET "/notifications/unread-count" $null $tWrk $cid).B
if([int]$after -eq [int]$before + 1){ Ok "🔴 ووصل المسؤولَ إشعارٌ واحد ($before ثم $after)" } else { Bad "العدّاد $before ثم $after" }

# 🔴 **الفاعل لا يُشعَر بفعله** — وهو أوّل ما يجعل المستخدم يتجاهل الجرس.
$mgrCount=(Api GET "/notifications/unread-count" $null $tMng $cid).B
$tn2=(Api POST "/tasks" @{title='مهمة لنفسي';taskType='Individual';priority='Normal';dueDate=$due;assignedToUserId=$mngId} $tMng $cid)
$mgrAfter=(Api GET "/notifications/unread-count" $null $tMng $cid).B
if([int]$mgrAfter -eq [int]$mgrCount){ Ok "🔴 ومَن أنشأ لنفسه **لا يُشعَر بفعله**" } else { Bad "أُشعر بنفسه: $mgrCount ثم $mgrAfter" }

# ── القائمة والمحتوى ──
$nl=(Api GET "/notifications?pageSize=50" $null $tWrk $cid).B
$mine=@(@($nl.items) | Where-Object { [int]$_.entityId -eq $idN })
if($mine.Count -ge 1){ Ok "والإشعار يحمل الكيان المعنيّ (entityId=$idN)" } else { Bad "الإشعار بلا كيان" }
if($mine.Count -ge 1 -and $mine[0].category -eq 'Task'){ Ok "وتصنيفَه Task" } else { Bad "التصنيف خطأ" }
$notifId=[long]$mine[0].notificationId

# ── إعادة الفتح: أولوية عالية ──
$null=Api POST "/tasks/$idN/status" @{newStatus='InProgress'} $tWrk $cid
$null=Api POST "/tasks/$idN/status" @{newStatus='Completed'} $tWrk $cid
$null=Api POST "/tasks/$idN/reopen" @{reason='المخرجات ناقصة وتحتاج مراجعة'} $admin $cid
$nl2=(Api GET "/notifications?pageSize=50" $null $tWrk $cid).B
$hi=@(@($nl2.items) | Where-Object { [int]$_.entityId -eq $idN -and $_.priority -eq 'High' })
if($hi.Count -ge 1){ Ok "🔴 وإعادة الفتح تُنتج إشعاراً **عالي الأولوية** — نقضُ إنجازٍ مُعلَن" } else { Bad "لا إشعار High" }

# ── حارس التكرار ──
$cntA=(Api GET "/notifications/unread-count" $null $tWrk $cid).B
$null=Api POST "/tasks/$idN/status" @{newStatus='InProgress'} $tWrk $cid
$null=Api POST "/tasks/$idN/status" @{newStatus='Completed'} $tWrk $cid
$null=Api POST "/tasks/$idN/reopen" @{reason='سببٌ ثانٍ لإعادة الفتح'} $admin $cid
$cntB=(Api GET "/notifications/unread-count" $null $tWrk $cid).B
if([int]$cntB -eq [int]$cntA){ Ok "🔴 و`DedupKey` يمنع إشعاراً ثانياً عن الواقعة نفسها" } else { Bad "تكرّر: $cntA ثم $cntB" }

# ── الوسم بالمقروء ──
$rd=(Api POST "/notifications/$notifId/read" $null $tWrk $cid)
if($rd.S -eq 204){ Ok "الوسم بالمقروء يعمل (204)" } else { Bad "ردّ $($rd.S)" }
$cntC=(Api GET "/notifications/unread-count" $null $tWrk $cid).B
if([int]$cntC -lt [int]$cntB){ Ok "والعدّاد ينقص ($cntB ثم $cntC)" } else { Bad "لم ينقص" }

# 🔐 ── إشعار غيرك: 404 لا 403 ──
$steal=(Api POST "/notifications/$notifId/read" $null $tOut $cid)
if($steal.S -eq 404){ Ok "🔐 وإشعارُ غيرك يردّ **404 لا 403** — لا يُفشى وجودُه" } else { Bad "ردّ $($steal.S)" }

# 🔐 ── لا يرى أحدٌ إشعارات غيره ولو كان سوبر أدمن ──
$adminList=(Api GET "/notifications?pageSize=100" $null $admin $cid).B
$leak=@(@($adminList.items) | Where-Object { [long]$_.notificationId -eq $notifId })
if($leak.Count -eq 0){ Ok "🔐 والسوبر أدمن **لا يرى إشعار غيره** — الرقابة لها سجلّ التدقيق" } else { Bad "تسرّب إلى السوبر أدمن" }

# ── تحديد الكل كمقروء ──
$allRead=(Api POST "/notifications/read-all" $null $tWrk $cid)
if($allRead.S -eq 200){ Ok "تحديد الكل كمقروء يعمل" } else { Bad "ردّ $($allRead.S)" }
$cntD=(Api GET "/notifications/unread-count" $null $tWrk $cid).B
if([int]$cntD -eq 0){ Ok "والعدّاد صار صفراً" } else { Bad "بقي $cntD" }

# ── الإشراك يُخطِر المُشرَك ──
$cntOut=(Api GET "/notifications/unread-count" $null $tOut $cid).B
$null=Api POST "/tasks/$idN/participants" @{userId=[int]$out.userId} $tMng $cid
$cntOut2=(Api GET "/notifications/unread-count" $null $tOut $cid).B
if([int]$cntOut2 -gt [int]$cntOut){ Ok "🔴 ومَن أُشرك يُخطَر بما يتابعه" } else { Bad "لم يُخطَر: $cntOut ثم $cntOut2" }

Write-Host "`n=== ⚙️ الخدمة الخلفية: التصعيد والتذكير والتوليد (ADR-039) ===" -ForegroundColor Cyan
# 🔴 **لا يُقبل «انتظار ساعة» كخطة تحقّق** — الحلقة تُستخرج في `RunOnceAsync` وتُنادى من
#    نقطةٍ يدوية محميّة بـ**السوبر أدمن وبيئة التطوير معاً**.
function RunJobs { (Api POST "/tasks/run-jobs" $null $admin $cid) }

# ── مهمةٌ متأخرةٌ يوماً: المستوى الأول ──
# ⚠️ الإنشاء يرفض الماضي، فتُنشأ بموعدٍ صالح ثم يُعدَّل إلى الماضي بسببٍ (قاعدة ٤ب).
$ovr=(Api POST "/tasks" @{title='مهمة للتصعيد';taskType='Individual';priority='Normal';dueDate=$due;assignedToUserId=[int]$wrk.userId} $tMng $cid).B
$idO=[int]$ovr.taskId
$d1=(Get-Date).Date.AddDays(-1).ToString('yyyy-MM-ddT00:00:00')
$null=Api PUT "/tasks/$idO" @{title=$ovr.title;priority='Normal';dueDate=$d1;rowVersion=$ovr.rowVersion;reason='ضبط الموعد لاختبار التصعيد'} $tMng $cid

$c0=(Api GET "/notifications/unread-count" $null $tWrk $cid).B
$r1=RunJobs
if($r1.S -eq 200){ Ok "نقطة التشغيل اليدوية تعمل (صعّدت $($r1.B.escalated))" } else { Bad "ردّ $($r1.S)" }
$c1=(Api GET "/notifications/unread-count" $null $tWrk $cid).B
if([int]$c1 -gt [int]$c0){ Ok "🔴 ووصل المسؤولَ إشعارُ تأخّر ($c0 ثم $c1)" } else { Bad "لم يُشعَر: $c0 ثم $c1" }

# 🔴 ── X2: تشغيلٌ ثانٍ فوراً ⇒ صفر إشعارات جديدة ──
$r2=RunJobs
$c2=(Api GET "/notifications/unread-count" $null $tWrk $cid).B
if([int]$c2 -eq [int]$c1){ Ok "🔴 وتشغيلٌ ثانٍ **لا يُنتج إشعاراً جديداً** (X2 — الحالة في أعمدة لا في ذاكرة)" }
else { Bad "تكرّر: $c1 ثم $c2" }

# ── المستوى الثاني: كل مديري الشركة ──
$d4=(Get-Date).Date.AddDays(-4).ToString('yyyy-MM-ddT00:00:00')
$cur=(Api GET "/tasks/$idO" $null $tMng $cid).B
$null=Api PUT "/tasks/$idO" @{title=$cur.title;priority='Normal';dueDate=$d4;rowVersion=$cur.rowVersion;reason='تعميق التأخّر لاختبار المستوى الثاني'} $tMng $cid
$null=RunJobs
$after=(Api GET "/tasks/$idO" $null $tMng $cid)
if($after.S -eq 200){ Ok "المهمة ما زالت تُقرأ بعد التصعيد" } else { Bad "ردّ $($after.S)" }

# ── 🔐 X1: عزل الشركات — أخطر ما في هذه الدفعة ──
# الخدمة الخلفية **بلا فلتر شركة إطلاقاً**، فالتجميع بـ`CompanyId` هو الحارس الوحيد.
if($cid2 -gt 0){
  $notifs2=(Api GET "/notifications?pageSize=100" $null $admin $cid2).B
  $leak=@(@($notifs2.items) | Where-Object { [int]$_.entityId -eq $idO })
  if($leak.Count -eq 0){ Ok "🔐 **X1**: تصعيدُ الشركة الأولى لا يظهر في إشعارات الثانية" }
  else { Bad "🔴 تسرّب عبر الشركات: $($leak.Count) إشعاراً" }
} else { Write-Host "  [تخطّي] لا شركة ثانية" -ForegroundColor DarkYellow }

# ── إعادة الفتح تُصفّر التصعيد ──
$null=Api POST "/tasks/$idO/status" @{newStatus='InProgress'} $tMng $cid
$null=Api POST "/tasks/$idO/status" @{newStatus='Completed'} $tMng $cid
$null=Api POST "/tasks/$idO/reopen" @{reason='إعادة فتحٍ لاختبار تصفير التصعيد'} $admin $cid
$cBefore=(Api GET "/notifications/unread-count" $null $tWrk $cid).B
$r3=RunJobs
if([int]$r3.B.escalated -ge 1){ Ok "🔴 وبعد إعادة الفتح **يُستأنف التصعيد من الصفر** (الأعمدة صُفِّرت)" }
else { Bad "لم يُستأنف: صعّد $($r3.B.escalated)" }

Write-Host "`n=== 🔁 توليد النسخة التالية من المتكررة ===" -ForegroundColor Cyan
# ⚠️ **عنوانٌ خاصٌّ بكل تشغيل**: المطابقة بعنوانٍ ثابت تلتقط سلسلة التشغيل السابق فتبدو
#    تكاثراً وهو ليس كذلك — **عيبُ مرشِّحٍ لا عيبُ منتج** (تحقّقتُ من القاعدة: رأسٌ واحد
#    ونسخةٌ واحدة لكلٍّ).
$recTitle = 'مهمة أسبوعية متكررة ' + [Guid]::NewGuid().ToString('N').Substring(0,6)
$rec=(Api POST "/tasks" @{title=$recTitle;taskType='Individual';priority='Normal';dueDate=$due;assignedToUserId=[int]$wrk.userId;isRecurring=$true;recurrencePattern='Weekly';recurrenceInterval=1} $tMng $cid)
if($rec.S -eq 200 -and $rec.B.isRecurring){ Ok "أُنشئت مهمةٌ متكررة أسبوعياً" } else { Bad "ردّ $($rec.S)" }
$idR2=[int]$rec.B.taskId

$before=(Api GET "/tasks?pageSize=200" $null $tMng $cid).B.total
$null=RunJobs
$mid=(Api GET "/tasks?pageSize=200" $null $tMng $cid).B.total
if([int]$mid -eq [int]$before){ Ok "🔴 ولا نسخة ما دامت لم تُكمَل — **التوليد يُطلقه الإنهاء لا مرورُ الوقت**" }
else { Bad "وُلِّدت نسخةٌ قبل الإكمال" }

$null=Api POST "/tasks/$idR2/status" @{newStatus='InProgress'} $tMng $cid
$null=Api POST "/tasks/$idR2/status" @{newStatus='Completed'} $tMng $cid
$rg=RunJobs
if([int]$rg.B.recurringCreated -ge 1){ Ok "وبعد الإكمال وُلِّدت نسخة ($($rg.B.recurringCreated))" } else { Bad "لم تُولَّد" }

$lst=(Api GET "/tasks?pageSize=200" $null $tMng $cid).B
$copies=@(@($lst.items) | Where-Object { $_.title -eq $recTitle -and [int]$_.taskId -ne $idR2 })
if($copies.Count -eq 1){ Ok "ونسخةٌ **واحدة** لا أكثر" } else { Bad "عدد النسخ $($copies.Count)" }
if($copies.Count -ge 1 -and $copies[0].taskNumber -and $copies[0].taskNumber -ne $rec.B.taskNumber){ Ok "وبترقيمٍ جديد ($($copies[0].taskNumber))" } else { Bad "الترقيم لم يتجدّد" }

# 🔴 ── X3: تشغيلٌ ثانٍ فوراً ⇒ لا نسخة ثانية ──
$rg2=RunJobs
$lst2=(Api GET "/tasks?pageSize=200" $null $tMng $cid).B
$copies2=@(@($lst2.items) | Where-Object { $_.title -eq $recTitle -and [int]$_.taskId -ne $idR2 })
if($copies2.Count -eq 1){ Ok "🔴 **X3**: تشغيلٌ ثانٍ لا يُنتج نسخةً ثانية — فحصُ وجودٍ وفهرسٌ فريد" }
else { Bad "تكاثرت: $($copies2.Count) نسخة" }

# ── نهاية السلسلة ──
$endDate=(Get-Date).Date.AddDays(8).ToString('yyyy-MM-ddT00:00:00')
$fin=(Api POST "/tasks" @{title='متكررة تنتهي قريباً';taskType='Individual';priority='Low';dueDate=$due;assignedToUserId=[int]$wrk.userId;isRecurring=$true;recurrencePattern='Monthly';recurrenceInterval=1;recurrenceEndDate=$endDate} $tMng $cid).B
$idF=[int]$fin.taskId
$null=Api POST "/tasks/$idF/status" @{newStatus='InProgress'} $tMng $cid
$null=Api POST "/tasks/$idF/status" @{newStatus='Completed'} $tMng $cid
$before2=(Api GET "/tasks?pageSize=200" $null $tMng $cid).B.total
$null=RunJobs
$after2=(Api GET "/tasks?pageSize=200" $null $tMng $cid).B.total
if([int]$after2 -eq [int]$before2){ Ok "🔴 ومتكررةٌ تجاوز موعدُها التالي نهايةَ السلسلة **لا تُولّد**" }
else { Bad "وُلِّدت رغم انتهاء السلسلة" }

# 🔐 ── نقطة التشغيل محميّة ──
$byWrk=(Api POST "/tasks/run-jobs" $null $tWrk $cid)
if($byWrk.S -eq 403){ Ok "🔐 ونقطة التشغيل مقصورةٌ على السوبر أدمن (403 للموظف)" } else { Bad "ردّ $($byWrk.S)" }

Write-Host "`n=== الحذف الناعم ===" -ForegroundColor Cyan
$td2=(Api POST "/tasks" @{title='ستُحذف';taskType='Individual';priority='Low';dueDate=$due} $tMng $cid).B
$idDel=[int]$td2.taskId
$r=(Api DELETE "/tasks/$idDel" $null $tMng $cid)
if($r.S -eq 204){ Ok "الحذف يردّ 204" } else { Bad "ردّ $($r.S)" }
$r=(Api GET "/tasks/$idDel" $null $tMng $cid)
if($r.S -eq 404){ Ok "والمحذوفة لا تُقرأ بعده" } else { Bad "ردّ $($r.S)" }

Write-Host "`n=== العزل بين الشركتين ===" -ForegroundColor Cyan
if($cid2 -gt 0){
  $r=(Api GET "/tasks/$id1" $null $admin $cid2)
  if($r.S -eq 404){ Ok "مهمة الشركة الأولى غير موجودة من الثانية (بالمعرّف لا بغياب السطر)" } else { Bad "ردّ $($r.S)" }
  $l2=(Api GET "/tasks?pageSize=100" $null $admin $cid2).B
  $leak=@(@($l2.items) | Where-Object { [int]$_.taskId -eq $id1 })
  if($leak.Count -eq 0){ Ok "ولا تظهر في قائمتها" } else { Bad "تسرّبت إلى قائمة الشركة الثانية" }
} else { Write-Host "  [تخطّي] لا شركة ثانية" -ForegroundColor DarkYellow }

Write-Host "`n=== تقرير المهام (الدفعة ٧) ===" -ForegroundColor Cyan

# ⚠️ **بايتات لا JSON**: نقطتا PDF/Excel تُعيدان ملفاً، فتُقرأ بايتاته للتحقّق من نوعه.
function ApiBytes($u,$t,$c){ $h=@{Authorization="Bearer $t"}; if($c){$h."X-Company-Id"="$c"}
  try{ $r=Invoke-WebRequest -Uri "$Base$u" -Headers $h -UseBasicParsing
       return @{S=[int]$r.StatusCode; D=$r.Content} }
  catch{ $resp=$_.Exception.Response; $code=if($resp){[int]$resp.StatusCode}else{0}; return @{S=$code;D=$null} }
}

# 🔐 مستخدمو الحدّ المزدوج: التقارير+المهام · التقارير وحدها · قارئٌ بالاثنين.
$rep=UpsertUser 'tsk_rep' 'موظف التقارير والمهام' 'Employee' @('Outgoing','Tasks','Reports') $false $depId
$ronly=UpsertUser 'tsk_ronly' 'موظف التقارير وحدها' 'Employee' @('Outgoing','Reports') $false $depId
$rrd=UpsertUser 'tsk_rrd' 'قارئ بالتقارير والمهام' 'Reader' @('Outgoing','Tasks','Reports') $false $depId
$tRep=UserLogin 'tsk_rep'; $tRonly=UserLogin 'tsk_ronly'; $tRrd=UserLogin 'tsk_rrd'
if($tRep -and $tRonly -and $tRrd){ Ok "دخول مستخدمي التقارير الثلاثة" } else { Bad "تعذّر دخول أحدهم" }

# 🔐 ── الحدّ المزدوج في الاتجاهين ──
$r=(Api GET "/reports/tasks-detail" $null $tMng $cid)
if($r.S -eq 403){ Ok "🔐 قسم المهام بلا التقارير ⇒ 403 (الحدّ الأول)" } else { Bad "ردّ $($r.S) لمن لا يملك التقارير" }

$r=(Api GET "/reports/tasks-detail" $null $tRonly $cid)
if($r.S -eq 403){ Ok "🔐 وقسم التقارير بلا المهام ⇒ 403 (الحدّ الثاني) — فالتقرير ليس باباً خلفياً" }
else { Bad "ردّ $($r.S) لمن لا يملك المهام" }

$r=(Api GET "/reports/tasks-detail" $null $tRrd $cid)
if($r.S -eq 403){ Ok "🔐 والقارئ محجوبٌ ولو مُنح القسمين — «RequireGrantedModule» لا «RequireModule»" }
else { Bad "ردّ $($r.S) للقارئ" }

# ── التقرير يعمل لمن يملك الحدَّين ──
$rep1=(Api GET "/reports/tasks-detail" $null $tRep $cid)
if($rep1.S -eq 200){ Ok "والتقرير يستجيب لمن يملك القسمين مع دورٍ فوق القارئ" } else { Bad "ردّ $($rep1.S)" }
$repRows=@($rep1.B.rows)

# 🔴 ── **الرؤية واحدة: ما يُطبَع عين ما يُرى** ──
$listTotal=[int](Api GET "/tasks?pageSize=200" $null $tRep $cid).B.total
if([int]$rep1.B.count -eq $listTotal){
  Ok "🔴 عدد صفوف التقرير = عدد قائمة الشاشة ($listTotal) — «Filtered()» واحدة لا نسختان" }
else { Bad "التقرير $($rep1.B.count) والقائمة $listTotal — قاعدتا رؤيةٍ تباعدتا" }

# 🔴 وكل صفٍّ في التقرير **يُفتح** بمعرّفه من صاحبه نفسه — برهانٌ مباشر لا استنتاج.
$unseen=0
foreach($row in ($repRows | Select-Object -First 5)){
  $one=(Api GET "/tasks/$([int]$row.taskId)" $null $tRep $cid)
  if($one.S -ne 200){ $unseen++ }
}
if($unseen -eq 0){ Ok "وكل صفٍّ مفحوصٍ يُفتح بمعرّفه من صاحب التقرير — لا صفَّ لا يراه" }
else { Bad "$unseen صفّاً في التقرير لا يستطيع صاحبه فتحه — تسريب رؤية" }

# ── الفلاتر تُطبَّق ──
#
# 🔴 **تُصنَع مهمةٌ متأخّرة أولاً**: حارسٌ يفحص «لا صفَّ غير متأخّر» على نتيجةٍ فارغة
#    **ينجح دائماً ولا يحرس شيئاً** — درسُ «حارسٌ يقيس قيمةً لم تصل يكذب» (الدفعة ٥).
# ⚠️ **الإنشاء بموعدٍ ماضٍ مرفوضٌ بالتصميم** (حارسٌ في السطر 80) — فتُنشأ بموعدٍ صالح
#    **ثم يُؤجَّل موعدها إلى الماضي بسببٍ مكتوب**، وهو المسار الحقيقيّ لكل مهمةٍ تتأخّر.
$ovTask=(Api POST "/tasks" @{title='مهمة متأخّرة للتقرير';taskType='Individual';priority='Normal';dueDate=$due;assignedToUserId=[int]$rep.userId} $admin $cid).B
$idOv=[int]$ovTask.taskId
$ovUpd=(Api PUT "/tasks/$idOv" @{title='مهمة متأخّرة للتقرير';priority='Normal';dueDate=$past;rowVersion=$ovTask.rowVersion;reason='ضبط الموعد ليصير متأخّراً لاختبار الفلتر'} $admin $cid)
if($ovUpd.S -eq 200){ Ok "أُنشئت مهمةٌ ثم أُرجع موعدُها فصارت متأخّرة" } else { Bad "تعذّر ضبط الموعد: $($ovUpd.S)" }
$ovRep=(Api GET "/reports/tasks-detail?isOverdue=true" $null $tRep $cid)
$ovRows=@($ovRep.B.rows)
$notOverdue=@($ovRows | Where-Object { -not $_.isOverdue })
if($ovRows.Count -ge 1 -and $notOverdue.Count -eq 0){
  Ok "فلتر «المتأخّرة» يُعيد متأخّراتٍ فقط ($($ovRows.Count) صفّاً) — وقد صُنعت واحدة ليحرس فعلاً" }
elseif($ovRows.Count -eq 0){ Bad "الفلتر أعاد صفراً رغم وجود متأخّرة — حارسٌ لا يقيس شيئاً" }
else { Bad "$($notOverdue.Count) صفٍّ غير متأخّر ضمن فلتر المتأخّرة" }

$mine=@($ovRows | Where-Object { [int]$_.taskId -eq $idOv })
if($mine.Count -eq 1 -and [int]$mine[0].daysOverdue -ge 1){
  Ok "والمتأخّرة تحمل عدد أيامها ($([int]$mine[0].daysOverdue) يوماً) لا صفراً" }
else { Bad "لم تظهر المتأخّرة المصنوعة أو أيامها صفر" }

$repByStatus=(Api GET "/reports/tasks-detail?status=Completed" $null $tRep $cid)
$wrongStatus=@(@($repByStatus.B.rows) | Where-Object { $_.status -ne 'Completed' })
if($wrongStatus.Count -eq 0){ Ok "وفلتر الحالة كذلك" } else { Bad "$($wrongStatus.Count) صفٍّ بحالةٍ أخرى" }

# 🔴 ── الملخّص صادق ──
if([int]$rep1.B.averageProgress -ge 0 -and [int]$rep1.B.averageProgress -le 100){
  Ok "متوسّط الإنجاز ضمن [0،100]: $($rep1.B.averageProgress)% — وعلى النشِطة وحدها" }
else { Bad "متوسّطٌ خارج المدى: $($rep1.B.averageProgress)" }

$sumByStatus=0; foreach($s in @($rep1.B.byStatus)){ $sumByStatus += [int]$s.count }
if($sumByStatus -eq [int]$rep1.B.count){ Ok "وتوزيع الحالات يجمع إلى العدد الكلّي ($sumByStatus)" }
else { Bad "التوزيع $sumByStatus والعدد $($rep1.B.count)" }

# ── المخرجان ──
$pdf=ApiBytes "/reports/tasks-detail/pdf" $tRep $cid
if($pdf.S -eq 200 -and $pdf.D -and $pdf.D.Length -gt 1000 -and $pdf.D[0] -eq 0x25 -and $pdf.D[1] -eq 0x50){
  Ok "PDF المهام يُولَّد ($($pdf.D.Length) بايت، ويبدأ بـ%PDF)" }
else { Bad "PDF: الحالة $($pdf.S)" }

$xls=ApiBytes "/reports/tasks-detail/excel" $tRep $cid
if($xls.S -eq 200 -and $xls.D -and $xls.D.Length -gt 500 -and $xls.D[0] -eq 0x50 -and $xls.D[1] -eq 0x4B){
  Ok "و Excel كذلك ($($xls.D.Length) بايت، ويبدأ بـPK)" }
else { Bad "Excel: الحالة $($xls.S)" }

# 🔐 والمخرجان محروسان كالتقرير — لا يكفي حجب الجدول وترك ملفّه.
$p403=ApiBytes "/reports/tasks-detail/pdf" $tRonly $cid
$x403=ApiBytes "/reports/tasks-detail/excel" $tRonly $cid
if($p403.S -eq 403 -and $x403.S -eq 403){ Ok "🔐 والمخرجان محروسان بالحدّ نفسه (403 لمن لا يملك المهام)" }
else { Bad "PDF=$($p403.S) Excel=$($x403.S) — بابٌ خلفيّ في المخرجات" }

# 🔴 ── سطرٌ أنشأه السوبر أدمن لا يسقط من التقرير (ADR-034) ──
$adminTask=(Api POST "/tasks" @{title='مهمة أنشأها السوبر أدمن للتقرير';taskType='Individual';priority='Normal';dueDate=$due;assignedToUserId=[int]$rep.userId} $admin $cid).B
$idAdm=[int]$adminTask.taskId
$repAfter=(Api GET "/reports/tasks-detail" $null $tRep $cid)
$found=@(@($repAfter.B.rows) | Where-Object { [int]$_.taskId -eq $idAdm })
if($found.Count -eq 1){ Ok "🔴 ومهمةٌ أنشأها سوبر أدمن غير مُسنَد **تظهر في التقرير** (حارس ADR-034)" }
else { Bad "سقطت من التقرير — «Include» على علاقةٍ مطلوبة عاد" }
if($found.Count -eq 1 -and $found[0].createdBy -and $found[0].createdBy -ne '—'){
  Ok "وسطرُها يحمل اسم مُنشئه: $($found[0].createdBy)" }
else { Bad "سطرُ السوبر أدمن بلا اسم مُنشئ" }

Write-Host "`n=== النتيجة ===" -ForegroundColor Cyan
Write-Host "نجح: $pass" -ForegroundColor Green
Write-Host "فشل: $fail" -ForegroundColor $(if($fail -gt 0){'Red'}else{'Green'})
if($fail -gt 0){ exit 1 }
