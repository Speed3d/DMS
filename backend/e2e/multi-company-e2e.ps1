param([string]$AdminPwd='Speed3ds', [string]$Base='http://localhost:5080/api')
# اختبار العزل بين شركتَي مستخدم واحد (ADR-017).
#
# الميزة كلها عن العزل، والعزل لا يُصدَّق بلا اختبار يُثبته: موظف واحد مُسنَد لشركتين
# بصلاحيات وأقسام **مختلفة** — يجب أن يرى في كلٍّ ما يخصّه فقط، ويُحجب عمّا لا يخصّه.
#
# ⚠️ يُنشئ شركة ثانية وموظف اختبار — بيئة تطوير فقط. قابل لإعادة التشغيل.
$ErrorActionPreference='Stop'; $pass=0; $fail=0
function Ok($m){ $script:pass++; Write-Host "  [نجح] $m" -ForegroundColor Green }
function Bad($m){ $script:fail++; Write-Host "  [فشل] $m" -ForegroundColor Red }
function Api($m,$u,$b,$t,$c){ $h=@{}; if($t){$h.Authorization="Bearer $t"}; if($c){$h."X-Company-Id"="$c"}
  $p=@{Uri="$Base$u";Method=$m;Headers=$h;ContentType="application/json; charset=utf-8"}
  if($null -ne $b){$p.Body=[Text.Encoding]::UTF8.GetBytes(($b|ConvertTo-Json -Depth 8 -Compress))}
  try{$r=Invoke-WebRequest @p -UseBasicParsing; $j=$null; if($r.Content){try{$j=$r.Content|ConvertFrom-Json}catch{}}; return @{S=[int]$r.StatusCode;B=$j}}
  catch{$resp=$_.Exception.Response; $code=if($resp){[int]$resp.StatusCode}else{0}; $ct=''; if($resp){$sr=[IO.StreamReader]::new($resp.GetResponseStream());$ct=$sr.ReadToEnd()}; $j=$null; if($ct){try{$j=$ct|ConvertFrom-Json}catch{}}; return @{S=$code;B=$j}}
}
function Expect($label,$actual,$expected){ if("$actual" -eq "$expected"){ Ok "$label" } else { Bad "$label (المتوقّع $expected والفعلي $actual)" } }

Write-Host "`n=== 1) إعداد شركتين وقسم في كلٍّ ===" -ForegroundColor Cyan
$admin=(Api POST "/auth/login" @{username='admin';password=$AdminPwd} $null $null).B.accessToken
if(-not $admin){ Bad "فشل دخول admin"; exit 1 }

$companies=(Api GET "/companies" $null $admin $null).B
$cidA=$companies[0].companyId
if($companies.Count -ge 2){ $cidB=$companies[1].companyId }
else {
  $pfx="MC$(Get-Random -Minimum 100 -Maximum 999)"
  $cidB=(Api POST "/companies" @{name="شركة الاختبار الثانية";prefix=$pfx;isActive=$true} $admin $null).B.companyId
}
Expect "شركتان متمايزتان" ($cidA -ne $cidB) $true
Ok "الشركتان: A=$cidA  B=$cidB"

function GetOrMakeDept($name,$cid){
  $d=(Api GET "/departments?companyId=$cid" $null $admin $null).B|Where-Object{$_.name -eq $name}|Select-Object -First 1
  if($d){return $d.departmentId}
  return (Api POST "/departments" @{name=$name} $admin $cid).B.departmentId }
$deptA=GetOrMakeDept "المالية" $cidA
$deptB=GetOrMakeDept "الإدارة"  $cidB
Ok "قسمان: المالية(A)=$deptA  الإدارة(B)=$deptB"

# النقطة الجديدة نفسها تحت الاختبار: أقسام شركة بعينها للمانح.
$listB=(Api GET "/departments?companyId=$cidB" $null $admin $cidA)
Expect "المانح يجلب أقسام شركة أخرى بـ ?companyId=" $listB.S 200
$onlyB=@($listB.B|Where-Object{$_.companyId -ne $cidB}).Count
Expect "القائمة تخصّ الشركة المطلوبة وحدها" $onlyB 0

Write-Host "`n=== 2) موظف واحد في الشركتين بصلاحيات وأقسام مختلفة ===" -ForegroundColor Cyan
# الشركة A: الصادر + الوارد · قسم المالية · بلا اعتماد · يدير الوارد
# الشركة B: الصادر + التقارير · قسم الإدارة · يعتمد · لا يدير الوارد
$body=@{ fullName='موظف متعدد الشركات'; role='Employee'; isActive=$true; companies=@(
    @{ companyId=$cidA; modules=@('Outgoing','Incoming'); departmentId=$deptA; canApprove=$false; canManageIncoming=$true },
    @{ companyId=$cidB; modules=@('Outgoing','Reports');  departmentId=$deptB; canApprove=$true;  canManageIncoming=$false }
)}
$existing=(Api GET "/users" $null $admin $cidA).B|Where-Object{$_.username -eq 'emp_multi'}|Select-Object -First 1
if($existing){ $uid=$existing.userId; $r=Api PUT "/users/$uid" $body $admin $cidA }
else { $body.username='emp_multi'; $body.password='Multi@12345'; $r=Api POST "/users" $body $admin $cidA; $uid=$r.B.userId }
Expect "إنشاء/تعديل الموظف" $r.S ($(if($existing){200}else{200}))

$saved=(Api GET "/users" $null $admin $cidA).B|Where-Object{$_.userId -eq $uid}|Select-Object -First 1
$accA=$saved.companies|Where-Object{$_.companyId -eq $cidA}|Select-Object -First 1
$accB=$saved.companies|Where-Object{$_.companyId -eq $cidB}|Select-Object -First 1

Write-Host "`n=== 3) الحفظ يُبقي الاختلاف بين الشركتين ===" -ForegroundColor Cyan
Expect "قسم الشركة A محفوظ"            $accA.departmentId $deptA
Expect "قسم الشركة B محفوظ ومختلف"     $accB.departmentId $deptB
Expect "إدارة الوارد في A فقط"         $accA.canManageIncoming $true
Expect "إدارة الوارد ليست في B"        $accB.canManageIncoming $false
Expect "الاعتماد في B فقط"             $accB.canApprove $true
Expect "الاعتماد ليس في A"             $accA.canApprove $false
Expect "أقسام A تشمل الوارد"           ($accA.modules -contains 'Incoming') $true
Expect "أقسام B لا تشمل الوارد"        ($accB.modules -contains 'Incoming') $false
Expect "أقسام B تشمل التقارير"         ($accB.modules -contains 'Reports') $true
Expect "أقسام A لا تشمل التقارير"      ($accA.modules -contains 'Reports') $false

Write-Host "`n=== 4) الفرض الحيّ: التوكن يحترم الشركة الفعّالة ===" -ForegroundColor Cyan
$login=Api POST "/auth/login" @{username='emp_multi';password='Multi@12345'} $null $null
if($login.B.mustChangePassword){
  $null=Api POST "/auth/change-password" @{currentPassword='Multi@12345';newPassword='Multi@12345'} $login.B.accessToken $null
  $login=Api POST "/auth/login" @{username='emp_multi';password='Multi@12345'} $null $null
}
$tok=$login.B.accessToken
if(-not $tok){ Bad "فشل دخول emp_multi (HTTP $($login.S))"; Write-Host "`nنجح: $pass`nفشل: $($fail+1)"; exit 1 }
Ok "دخول emp_multi"

# الوارد مسموح في A ممنوع في B — نفس التوكن، تختلف الترويسة فقط.
Expect "الوارد متاح في الشركة A"   (Api GET "/incoming" $null $tok $cidA).S 200
Expect "الوارد محجوب في الشركة B"  (Api GET "/incoming" $null $tok $cidB).S 403
# التقارير معكوسة تماماً.
Expect "التقارير متاحة في الشركة B"  (Api GET "/reports/financial" $null $tok $cidB).S 200
Expect "التقارير محجوبة في الشركة A" (Api GET "/reports/financial" $null $tok $cidA).S 403
# الصادر مسموح في الاثنتين (ضابط: الحجب ليس عشوائياً).
Expect "الصادر متاح في A" (Api GET "/outgoing" $null $tok $cidA).S 200
Expect "الصادر متاح في B" (Api GET "/outgoing" $null $tok $cidB).S 200
# قسم غير مُسنَد إطلاقاً ⇒ محجوب في الشركتين.
Expect "المستخدمون محجوب في A" (Api GET "/users" $null $tok $cidA).S 403
Expect "المستخدمون محجوب في B" (Api GET "/users" $null $tok $cidB).S 403

Write-Host "`n=== 5) رفض إسناد قسم من شركة أخرى ===" -ForegroundColor Cyan
$bad=@{ fullName='موظف متعدد الشركات'; role='Employee'; isActive=$true; companies=@(
    @{ companyId=$cidA; modules=@('Outgoing'); departmentId=$deptB }   # قسم الشركة B داخل صف الشركة A
)}
Expect "قسم من شركة أخرى يُرفض (400)" (Api PUT "/users/$uid" $bad $admin $cidA).S 400

# إعادة الإسناد الصحيح حتى يبقى السكربت قابلاً لإعادة التشغيل.
$null=Api PUT "/users/$uid" $body $admin $cidA

Write-Host "`n============ النتيجة ============" -ForegroundColor Cyan
Write-Host "  نجح: $pass" -ForegroundColor Green
Write-Host "  فشل: $fail" -ForegroundColor $(if($fail){'Red'}else{'Green'})
if($fail -eq 0){ Write-Host "  العزل بين الشركات سليم" -ForegroundColor Green }
exit $(if($fail){1}else{0})
