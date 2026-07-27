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

Write-Host "=== إعداد: قسمان + موظفان + رئيس ===" -ForegroundColor Cyan
$admin=(Api POST "/auth/login" @{username='admin';password=$AdminPwd} $null $null).B.accessToken
$cid=(Api GET "/companies" $null $admin $null).B[0].companyId
$eid=(Api GET "/entities" $null $admin $cid).B[0].entityId

# قسمان
function GetOrMakeDept($name){ $d=(Api GET "/departments" $null $admin $cid).B|?{$_.name -eq $name}|select -f 1
  if($d){return $d.departmentId}; return (Api POST "/departments" @{name=$name} $admin $cid).B.departmentId }
$finance=GetOrMakeDept "المالية"
$legal=GetOrMakeDept "القانونية"
Ok "قسمان: المالية=$finance القانونية=$legal"

# موظفان بكلمة مرور معروفة — واحد في المالية بصلاحية إدارة، وآخر في القانونية
function MakeEmp($user,$dept,$manage){
  $ex=(Api GET "/users" $null $admin $cid).B|?{$_.username -eq $user}|select -f 1
  # الصلاحيات والقسم صارت **لكل شركة** (ADR-017).
  $body=@{fullName=$user;role='Employee';isActive=$true;companies=@(
            @{companyId=$cid;modules=@('Incoming');departmentId=$dept;canApprove=$false;canManageIncoming=$manage})}
  if($ex){ $body.Remove('password'); $null=Api PUT "/users/$($ex.userId)" $body $admin $cid; return $ex.userId }
  else { $body.username=$user; $body.password='Emp@12345'; return (Api POST "/users" $body $admin $cid).B.userId }
}
$empFin=MakeEmp "emp_fin" $finance $true    # المالية + صلاحية إدارة
$empLeg=MakeEmp "emp_leg" $legal  $false    # القانونية بلا صلاحية
Ok "موظفان: emp_fin(مالية+إدارة) emp_leg(قانونية)"

# دخول الموظفَين — قابل لإعادة التشغيل.
# Hint: الموظف الجديد يُنشأ بـ 'Emp@12345' ويُجبَر على تغييرها إلى 'Emp@12345new'، فالتشغيل
# الثاني لا تنفع فيه الكلمة الأولى. نجرّب **الأحدث أولاً** لأن إعادة التشغيل هي الحالة الشائعة،
# فلا نُراكم محاولات فاشلة (القفل بعد 5). الدخول الناجح يصفّر العدّاد.
function EmpLogin($user){
  $r=Api POST "/auth/login" @{username=$user;password='Emp@12345new'} $null $null
  if($r.S -ne 200){ $r=Api POST "/auth/login" @{username=$user;password='Emp@12345'} $null $null }
  if($r.B.mustChangePassword){ $tok=$r.B.accessToken
    $null=Api POST "/auth/change-password" @{currentPassword='Emp@12345';newPassword='Emp@12345new'} $tok $null
    $r=Api POST "/auth/login" @{username=$user;password='Emp@12345new'} $null $null }
  return $r.B.accessToken
}
$tokFin=EmpLogin "emp_fin"; $tokLeg=EmpLogin "emp_leg"
if($tokFin -and $tokLeg){ Ok "دخول الموظفَين" } else { Bad "فشل دخول موظف"; exit 1 }

Write-Host "`n=== الاختبار الجوهري: رؤية كتب القسم ===" -ForegroundColor Cyan
# admin ينشئ كتاباً ويحيله للمالية
$book=(Api POST "/incoming" @{companyId=$cid;receivedDate='2026-07-25T00:00:00';entityId=$eid;subject='كتاب محال للمالية';receiveMethod='Manual'} $admin $cid).B
$null=Api POST "/incoming/$($book.incomingId)/forward" @{departments=@(@{departmentId=$finance;note='للمراجعة'})} $admin $cid
Ok "admin أنشأ كتاباً وأحاله للمالية: $($book.incomingNumber)"

# موظف المالية يجب أن يراه (رغم أنه لم يستلمه)
$finSee=Api GET "/incoming/$($book.incomingId)" $null $tokFin $cid
if($finSee.S -eq 200){ Ok "موظف المالية يرى الكتاب المحال لقسمه (وإن لم يستلمه) ✔ الميزة الجوهرية" }
else { Bad "موظف المالية لا يرى كتاب قسمه (HTTP $($finSee.S))" }

# موظف القانونية يجب ألا يراه
$legSee=Api GET "/incoming/$($book.incomingId)" $null $tokLeg $cid
if($legSee.S -eq 404){ Ok "موظف القانونية لا يرى كتاب قسم آخر (404) ✔ العزل" }
else { Bad "تسرّب: موظف القانونية رأى كتاب المالية (HTTP $($legSee.S))" }

# القائمة: المالية ترى الكتاب، القانونية لا
$finList=@(Api GET "/incoming" $null $tokFin $cid).B
$legList=@(Api GET "/incoming" $null $tokLeg $cid).B
if(($finList|?{$_.incomingId -eq $book.incomingId})){ Ok "الكتاب يظهر في قائمة المالية" } else { Bad "الكتاب غائب عن قائمة المالية" }
if(-not ($legList|?{$_.incomingId -eq $book.incomingId})){ Ok "الكتاب غائب عن قائمة القانونية" } else { Bad "تسرّب في قائمة القانونية" }

Write-Host "`n=== صلاحية CanManageIncoming ===" -ForegroundColor Cyan
# موظف المالية (بصلاحية) يغيّر الحالة لتم الرد
$r=Api POST "/incoming/$($book.incomingId)/status" @{status='Replied';note='تمت المعالجة'} $tokFin $cid
if($r.S -eq 200){ Ok "موظف المالية (بصلاحية إدارة) غيّر الحالة إلى (تم الرد)" } else { Bad "فشل تغيير الحالة رغم الصلاحية (HTTP $($r.S)): $($r.B.error)" }

# نحيل كتاباً للقانونية ونتأكد أن موظفها (بلا صلاحية) لا يستطيع تجاوز جديد←قيد المراجعة
$book2=(Api POST "/incoming" @{companyId=$cid;receivedDate='2026-07-25T00:00:00';entityId=$eid;subject='كتاب للقانونية';receiveMethod='Manual'} $admin $cid).B
$null=Api POST "/incoming/$($book2.incomingId)/forward" @{departments=@(@{departmentId=$legal;note=$null})} $admin $cid
$r=Api POST "/incoming/$($book2.incomingId)/status" @{status='Closed';note='محاولة'} $tokLeg $cid
if($r.S -eq 403){ Ok "موظف القانونية (بلا صلاحية) مُنع من الإغلاق (403)" } else { Bad "الموظف بلا صلاحية أغلق كتاباً! (HTTP $($r.S))" }

Write-Host "`n=== مرفقات كتاب القسم (بلاغ المالك) ===" -ForegroundColor Cyan
# admin يرفع مرفقاً على الكتاب المُحال للمالية، ثم موظف المالية يجب أن يراه ويرفع مثله.
# ⚠️ كان فحص المرفقات يقارن بـ CreatedByUserId (قاعدة الصادر/الأرشيف) فيمنع موظف القسم
#    من مرفقات كتاب **يراه** — «لا تملك صلاحية الوصول لمرفقات عنصر غيرك».
# Hint: نستخدم curl.exe للرفع — بناء multipart يدوياً في PowerShell هشّ ويُنتج 400.
$tmpPdf = Join-Path $env:TEMP "dms-dept-e2e.pdf"
[System.IO.File]::WriteAllBytes($tmpPdf, [Text.Encoding]::ASCII.GetBytes("%PDF-1.4`n% attachment test`n%%EOF"))
function UploadPdf($tok,$id){
  $code = & curl.exe -s -o "$env:TEMP\dept-att.json" -w "%{http_code}" -X POST "$Base/incoming/$id/attachments" `
          -H "Authorization: Bearer $tok" -H "X-Company-Id: $cid" -F "file=@$tmpPdf"
  return [int]$code }

# كتاب جديد مُحال للمالية — الكتاب الأول صار (تم الرد) فلم تعُد الإحالة مسموحة عليه.
$b2=(Api POST "/incoming" @{companyId=$cid;receivedDate='2026-07-26T00:00:00';entityId=$eid;subject='مرفقات وإحالة';receiveMethod='Manual'} $admin $cid).B
$null=Api POST "/incoming/$($b2.incomingId)/forward" @{departments=@(@{departmentId=$finance;note='للمالية'})} $admin $cid

$upAdmin=UploadPdf $admin $b2.incomingId
if($upAdmin -eq 200){ Ok "admin رفع مرفقاً على الكتاب" } else { Bad "فشل رفع مرفق admin (HTTP $upAdmin)" }

$attFin=Api GET "/incoming/$($b2.incomingId)/attachments" $null $tokFin $cid
if($attFin.S -eq 200){ Ok "موظف المالية يرى مرفقات كتاب قسمه ✔ (كان 403)" }
else { Bad "موظف المالية مُنع من مرفقات كتاب قسمه (HTTP $($attFin.S))" }

$upFin=UploadPdf $tokFin $b2.incomingId
if($upFin -eq 200){ Ok "موظف المالية يرفع مرفقاً على كتاب قسمه ✔" } else { Bad "مُنع موظف المالية من الرفع (HTTP $upFin)" }

$attLeg=Api GET "/incoming/$($b2.incomingId)/attachments" $null $tokLeg $cid
if($attLeg.S -eq 404 -or $attLeg.S -eq 403){ Ok "موظف القانونية محجوب عن مرفقات كتاب قسم آخر ✔ العزل" }
else { Bad "تسرّب: القانونية رأى مرفقات كتاب المالية (HTTP $($attLeg.S))" }

Write-Host "`n=== الإحالة تراكمية ومَن أحال يبقى يرى (ADR-018) ===" -ForegroundColor Cyan
# ⚠️ كان الكونترولر يُنهي الإحالة بقراءة الكتاب، فيردّ 404 **بعد نجاح العملية وحفظها**
#    إن أخرجتْه من رؤية المنفِّذ — فيرى المستخدم فشلاً لعملٍ تمّ.
$fwOut=Api POST "/incoming/$($b2.incomingId)/forward" @{departments=@(@{departmentId=$legal;note='تحويل للقانونية'})} $tokFin $cid
if($fwOut.S -eq 200 -or $fwOut.S -eq 204){ Ok "إحالة الكتاب لقسم آخر نجحت بلا 404 (HTTP $($fwOut.S)) ✔" }
else { Bad "الإحالة ردّت خطأً رغم نجاحها (HTTP $($fwOut.S))" }

# 🔴 انقلبَ التوقّع عمداً (ADR-018): كانت الإحالة **تُزيح** القسم السابق، فيفقد المُحيلُ
#    رؤيةَ كتابٍ باشره بنفسه ولا يتابع مصيره. صارت **تراكمية**، و«مَن أحال يبقى يرى».
$still=Api GET "/incoming/$($b2.incomingId)" $null $tokFin $cid
if($still.S -eq 200){ Ok "موظف المالية ما زال يرى الكتاب بعد إحالته ✔ (مَن أحال يبقى يرى)" }
else { Bad "المُحيل فقد رؤية كتابه بعد الإحالة (HTTP $($still.S))" }

$names=@($still.B.departments | ForEach-Object { $_.name })
if($names.Count -eq 2){ Ok "الكتاب مُسنَد لقسمين معاً ✔ ($($names -join '، '))" }
else { Bad "عدد الأقسام بعد الإحالة التراكمية: $($names.Count) — المتوقّع 2" }

$legNow=Api GET "/incoming/$($b2.incomingId)" $null $tokLeg $cid
if($legNow.S -eq 200){ Ok "موظف القانونية صار يرى الكتاب بعد إحالته إليه ✔" }
else { Bad "القانونية لا يرى الكتاب المُحال إليه (HTTP $($legNow.S))" }

# إعادة الإحالة لقسم موجود: تُحدّث ملاحظته ولا تُكرّره.
$null=Api POST "/incoming/$($b2.incomingId)/forward" @{departments=@(@{departmentId=$legal;note='توجيه محدَّث'})} $admin $cid
$after=Api GET "/incoming/$($b2.incomingId)" $null $admin $cid
$legAsg=@($after.B.departments | Where-Object { $_.departmentId -eq $legal })
if($legAsg.Count -eq 1 -and $legAsg[0].note -eq 'توجيه محدَّث'){ Ok "إعادة الإحالة حدّثت الملاحظة ولم تُكرّر القسم ✔" }
else { Bad "تكرار أو ملاحظة غير محدَّثة (عدد=$($legAsg.Count))" }

# إحالة إلى قسمين في طلب واحد.
$b3=(Api POST "/incoming" @{companyId=$cid;receivedDate='2026-07-27T00:00:00';entityId=$eid;subject='إحالة متعددة';receiveMethod='Manual'} $admin $cid).B
$multi=Api POST "/incoming/$($b3.incomingId)/forward" @{departments=@(@{departmentId=$finance;note='للمالية'},@{departmentId=$legal;note='للقانونية'});generalNote='عاجل'} $admin $cid
if($multi.S -eq 200 -and @($multi.B.departments).Count -eq 2){ Ok "إحالة لقسمين في طلب واحد ✔" }
else { Bad "فشل الإحالة المتعددة (HTTP $($multi.S)، أقسام=$(@($multi.B.departments).Count))" }

# قسم واحد غير صالح يُبطل الإحالة كلها — إحالة نصفية أسوأ من رفض كامل.
$b4=(Api POST "/incoming" @{companyId=$cid;receivedDate='2026-07-27T00:00:00';entityId=$eid;subject='رفض شامل';receiveMethod='Manual'} $admin $cid).B
$bad=Api POST "/incoming/$($b4.incomingId)/forward" @{departments=@(@{departmentId=$finance;note=$null},@{departmentId=999999;note=$null})} $admin $cid
$b4After=Api GET "/incoming/$($b4.incomingId)" $null $admin $cid
if($bad.S -eq 400 -and @($b4After.B.departments).Count -eq 0){ Ok "قسم واحد غير صالح يُبطل الإحالة كلها ✔ (لا إحالة نصفية)" }
else { Bad "إحالة نصفية أو قبول خاطئ (HTTP $($bad.S)، أقسام=$(@($b4After.B.departments).Count))" }

$empty=Api POST "/incoming/$($b3.incomingId)/forward" @{departments=@()} $admin $cid
if($empty.S -eq 400){ Ok "رفض إحالة بلا أقسام ✔" } else { Bad "قبلت إحالة بلا أقسام (HTTP $($empty.S))" }

Write-Host "`n============ النتيجة ============" -ForegroundColor Cyan
Write-Host "  نجح: $pass" -ForegroundColor Green
Write-Host "  فشل: $fail" -ForegroundColor $(if($fail){'Red'}else{'Green'})
exit $(if($fail){1}else{0})
