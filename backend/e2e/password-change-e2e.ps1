param([string]$AdminPwd='Admin@12345', [string]$Base='http://localhost:5091/api',
      [string]$Db='Server=.;Database=DmsE2E_New;Integrated Security=true;TrustServerCertificate=True')
# ════════════════════════════════════════════════════════════════════════════════════════
#  «تغيير كلمة المرور المؤقتة» يفرضه الخادم لا الواجهة وحدها (G19).
#
#  كان مَن يملك كلمةً مؤقتة يستعمل الـAPI مباشرةً دون تغييرها — والمدير الذي أعطاها يعرفها
#  إلى الأبد. يُثبت: ١) رمزُ الكلمة المؤقتة لا يفتح إلا التغيير · ٢) الجديدة تختلف عن الحالية ·
#  ٣) التغيير يعيد رمزاً نظيفاً ويُنهي الجلسات الأخرى · ٤) إعادةُ التعيين تُنهي الجلسات وتعيد الإجبار.
# ════════════════════════════════════════════════════════════════════════════════════════
$ErrorActionPreference='Stop'; $pass=0; $fail=0
function Ok($m){ $script:pass++; Write-Host "  [نجح] $m" -ForegroundColor Green }
function Bad($m){ $script:fail++; Write-Host "  [فشل] $m" -ForegroundColor Red }
function Api($m,$u,$b,$t,$c){ $h=@{}; if($t){$h.Authorization="Bearer $t"}; if($c){$h."X-Company-Id"="$c"}
  $p=@{Uri="$Base$u";Method=$m;Headers=$h;ContentType="application/json; charset=utf-8"}
  if($null -ne $b){$p.Body=[Text.Encoding]::UTF8.GetBytes(($b|ConvertTo-Json -Depth 8 -Compress))}
  try{$r=Invoke-WebRequest @p -UseBasicParsing; $j=$null; if($r.Content){try{$j=$r.Content|ConvertFrom-Json}catch{}}; return @{S=[int]$r.StatusCode;B=$j}}
  catch{$resp=$_.Exception.Response; $code=if($resp){[int]$resp.StatusCode}else{0}; $ct=''; if($resp){$sr=[IO.StreamReader]::new($resp.GetResponseStream());$ct=$sr.ReadToEnd()}; $j=$null; if($ct){try{$j=$ct|ConvertFrom-Json}catch{}}; return @{S=$code;B=$j}}
}
function Expect($label,$actual,$expected){ if("$actual" -eq "$expected"){ Ok $label } else { Bad "$label (المتوقّع $expected والفعلي $actual)" } }
function LoginR($u,$p){ return Api POST "/auth/login" @{username=$u;password=$p} $null $null }

Write-Host "`n=== إعداد ===" -ForegroundColor Cyan
$admin=(LoginR 'admin' $AdminPwd).B.accessToken
if(-not $admin){ Bad "فشل دخول admin (شغّل bootstrap-e2e أوّلاً)"; exit 1 }
$cid=@((Api GET "/companies" $null $admin $null).B)[0].companyId
$mk=Get-Random -Minimum 1000 -Maximum 9999
$uname="pw_emp$mk"; $temp='Temp@12345'; $mine='Mine@98765'
$link=@{companyId=$cid;modules=@('Outgoing');departmentId=$null;canApprove=$false;canManageIncoming=$false
        canViewAllIncoming=$false;canManageEmployees=$false;canManagePayroll=$false;canAmendPaidPayroll=$false;canManageTasks=$false}
$r=Api POST "/users" @{username=$uname;password=$temp;fullName="موظف الكلمة المؤقتة";role='Employee';isActive=$true;companies=@($link)} $admin $null
Expect "إنشاء مستخدمٍ بكلمةٍ مؤقتة" $r.S 200
$uid=$r.B.userId

# ════════════════════ ١) رمز الكلمة المؤقتة ════════════════════
Write-Host "`n=== ١) رمزُ الكلمة المؤقتة لا يفتح إلا التغيير ===" -ForegroundColor Cyan
$l1=LoginR $uname $temp
Expect "الدخول بالمؤقتة ينجح" $l1.S 200
Expect "   ويُعلن «يجب التغيير»" $l1.B.mustChangePassword $true
$t1=$l1.B.accessToken; $refresh1=$l1.B.refreshToken
$r=Api GET "/outgoing" $null $t1 $cid
Expect "🔴 الصادر برمز المؤقتة ⇒ 403" $r.S 403
Expect "   والجسم يقول السبب" $r.B.mustChangePassword $true
Expect "   /auth/me مسموح (لعرض الشاشة)" (Api GET "/auth/me" $null $t1 $cid).S 200
Expect "   /system/status مسموح" (Api GET "/system/status" $null $t1 $null).S 200

# ════════════════════ ٢) الجديدة تختلف ════════════════════
Write-Host "`n=== ٢) الجديدة تختلف عن الحالية ===" -ForegroundColor Cyan
Expect "🔴 «تغيير» إلى الكلمة نفسها ⇒ 400" (Api POST "/auth/change-password" @{currentPassword=$temp;newPassword=$temp} $t1 $null).S 400
Expect "كلمةٌ حاليةٌ خاطئة ⇒ 400" (Api POST "/auth/change-password" @{currentPassword='Wrong@000';newPassword=$mine} $t1 $null).S 400

# جلسةٌ ثانية (جهازٌ آخر) قبل التغيير — يجب أن تنتهي به.
$l2=LoginR $uname $temp; $refresh2=$l2.B.refreshToken

# ════════════════════ ٣) التغيير ════════════════════
Write-Host "`n=== ٣) التغيير يعيد رمزاً نظيفاً ويُنهي الجلسات الأخرى ===" -ForegroundColor Cyan
$c=Api POST "/auth/change-password" @{currentPassword=$temp;newPassword=$mine} $t1 $null
Expect "التغيير ينجح" $c.S 200
Expect "   ويعيد رمزاً جديداً بلا «يجب التغيير»" $c.B.mustChangePassword $false
$t2=$c.B.accessToken
Expect "   والرمز الجديد يفتح الصادر" (Api GET "/outgoing" $null $t2 $cid).S 200
Expect "   والرمز القديم ما زال محجوباً (يحمل العلامة)" (Api GET "/outgoing" $null $t1 $cid).S 403
Expect "🔐 جلسةُ الجهاز الآخر انتهت (تجديدها مرفوض)" (Api POST "/auth/refresh" @{refreshToken=$refresh2} $null $null).S 403
Expect "   وجلسةُ الرمز الأوّل انتهت كذلك" (Api POST "/auth/refresh" @{refreshToken=$refresh1} $null $null).S 403
Expect "   وتجديدُ الرمز الجديد يعمل" (Api POST "/auth/refresh" @{refreshToken=$c.B.refreshToken} $null $null).S 200
$l3=LoginR $uname $mine
Expect "الدخول بالجديدة ⇒ بلا إجبار" $l3.B.mustChangePassword $false
Expect "   والمؤقتة لم تعد تعمل" (LoginR $uname $temp).S 400

# ════════════════════ ٤) إعادة التعيين ════════════════════
Write-Host "`n=== ٤) إعادةُ تعيينِ المدير تُنهي الجلسات وتعيد الإجبار ===" -ForegroundColor Cyan
$l4=LoginR $uname $mine; $refresh4=$l4.B.refreshToken
Expect "المدير يعيد تعيين الكلمة" (Api POST "/users/$uid/reset-password" @{newPassword='Reset@12345'} $admin $cid).S 204
Expect "🔐 جلسةُ المستخدم القائمة انتهت" (Api POST "/auth/refresh" @{refreshToken=$refresh4} $null $null).S 403
$l5=LoginR $uname 'Reset@12345'
Expect "الدخول بالمؤقتة الجديدة ⇒ «يجب التغيير» ثانيةً" $l5.B.mustChangePassword $true
Expect "   ومحجوبٌ حتى يغيّرها" (Api GET "/outgoing" $null $l5.B.accessToken $cid).S 403

Write-Host "`n══════ النتيجة: $pass نجح · $fail فشل ══════" -ForegroundColor $(if($fail){'Red'}else{'Green'})
if($fail){ exit 1 }
