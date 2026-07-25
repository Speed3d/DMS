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
$null=Api POST "/incoming/$($book.incomingId)/forward" @{departmentId=$finance;note='للمراجعة'} $admin $cid
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
$null=Api POST "/incoming/$($book2.incomingId)/forward" @{departmentId=$legal;note=$null} $admin $cid
$r=Api POST "/incoming/$($book2.incomingId)/status" @{status='Closed';note='محاولة'} $tokLeg $cid
if($r.S -eq 403){ Ok "موظف القانونية (بلا صلاحية) مُنع من الإغلاق (403)" } else { Bad "الموظف بلا صلاحية أغلق كتاباً! (HTTP $($r.S))" }

Write-Host "`n============ النتيجة ============" -ForegroundColor Cyan
Write-Host "  نجح: $pass" -ForegroundColor Green
Write-Host "  فشل: $fail" -ForegroundColor $(if($fail){'Red'}else{'Green'})
exit $(if($fail){1}else{0})
