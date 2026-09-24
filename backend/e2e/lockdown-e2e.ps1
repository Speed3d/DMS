param([string]$AdminPwd='Admin@12345', [string]$Base='http://localhost:5091/api',
      [string]$Db='Server=.;Database=DmsLockdownScratch;Integrated Security=true;TrustServerCertificate=True',
      [string]$StateFile='', [string]$ApiDll='')
# ════════════════════════════════════════════════════════════════════════════════════════
#  إيقاف النظام عن المستخدمين + شريط الإعلان (ADR-050).
#
#  يُثبت: ١) السوبر أدمن وحده يتصفّح أثناء الإيقاف · ٢) دخولُ غيره بكلمةٍ صحيحة يُردّ 503
#  **بلا عدٍّ في محاولات القفل** والكلمةُ الخاطئة تُحسب · ٣) التجديد يُردّ 503 **بلا تدوير**
#  فيعود المستخدم بجلسته · ٤) صفحة التحقق العامّة تبقى تعمل · ٥) الشريط للمصادَق وحده ·
#  ٦) النسخ اليدويّ والاستعادة للسوبر أدمن — **والاستعادة لا تُنهي الإيقاف** ·
#  ٧) أمرُ الطوارئ على السيرفر يسري والخادم يعمل (إن مُرّر -StateFile و-ApiDll).
#
#  ⚠️ **على قاعدةٍ منفصلة وملفّ حالةٍ منفصل** — الخادم يُشغَّل بـ`SystemControl__StateFile`،
#     وإلا أوقف هذا السكربت خادمَ التطوير الذي يشاركه مجلد التخزين.
#  ⚠️ **ويُطفئ الإيقاف في آخره** حتى لو فشل شيء (finally).
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
function WaitJob($start,$tok){
  if($start.S -ne 202 -or -not $start.B.id){ return $null }
  for($i=0;$i -lt 600;$i++){
    $j=Api GET "/system/jobs/$($start.B.id)" $null $tok $null
    if($j.S -eq 503){ Start-Sleep -Milliseconds 500; continue }   # الاستعادة: صيانةٌ تحجب الجميع
    if($j.S -ne 200){ return [pscustomobject]@{state="Lost";message="HTTP $($j.S)"} }
    if($j.B.state -ne 'Running'){ return $j.B }
    Start-Sleep -Milliseconds 400
  }
  return [pscustomobject]@{state="Timeout";message="لم تنتهِ"}
}
function SqlScalar($sql){
  $cn=New-Object System.Data.SqlClient.SqlConnection($Db); $cn.Open()
  try{ $cmd=$cn.CreateCommand(); $cmd.CommandText=$sql; return $cmd.ExecuteScalar() } finally { $cn.Close() }
}
function LoginR($u,$p){ return Api POST "/auth/login" @{username=$u;password=$p} $null $null }

# ════════════════════════════ إعداد ════════════════════════════
Write-Host "`n=== إعداد: شركة وموظف ===" -ForegroundColor Cyan
$admin=(LoginR 'admin' $AdminPwd).B.accessToken
if(-not $admin){ Bad "فشل دخول admin"; exit 1 }

# بدايةٌ نظيفة: لو بقي إيقافٌ من تشغيلٍ سابق.
$null=Api PUT "/system/lockdown" @{active=$false} $admin $null
$null=Api PUT "/system/announcement" @{visible=$false;text=$null;kind='Info'} $admin $null

$mk=Get-Random -Minimum 100 -Maximum 999
# ⚠️ **شركةٌ قائمة لا جديدة** — `backup-restore` بعده يأخذ **أوّل شركةٍ أبجدياً**، وشركةٌ جديدة
#    اسمُها «إيقاف…» تسبق غيرها فتُسقطه بلا عيبٍ في الكود (وقع 2026-09-23 — درس ٧ في سجلّ الجلسة).
$existing=@((Api GET "/companies" $null $admin $null).B)
$cid=if($existing.Count){ $existing[0].companyId } else { (Api POST "/companies" @{name="ي إيقاف $mk";prefix="LKD$mk";isActive=$true} $admin $null).B.companyId }
if(-not $cid){ Bad "تعذّر الحصول على شركة"; exit 1 }
$uname="lk_emp$mk"; $upwd='Lk@123456'
$link=@{companyId=$cid;modules=@('Outgoing','Incoming');departmentId=$null;canApprove=$false;canManageIncoming=$false
        canViewAllIncoming=$false;canManageEmployees=$false;canManagePayroll=$false;canAmendPaidPayroll=$false;canManageTasks=$false}
$r=Api POST "/users" @{username=$uname;password=$upwd;fullName="موظف الإيقاف";role='Employee';isActive=$true;companies=@($link)} $admin $null
Expect "إنشاء الموظف" $r.S 200
$empUserId=$r.B.userId
if(-not $empUserId){ $empUserId=(@((Api GET "/users" $null $admin $null).B) | ? { $_.username -eq $uname } | Select -First 1).userId }

# الموظف يغيّر كلمته المؤقتة ليصير دخوله عادياً، ثم يدخل.
. "$PSScriptRoot\_activate.ps1"   # G19: بلا هذا يُحجب رمزُه كلُّه قبل الإيقاف أصلاً
$null=Enable-TempPassword $Base $uname $upwd
$emp=LoginR $uname $upwd
$empTok=$emp.B.accessToken; $empRefresh=$emp.B.refreshToken
Expect "دخول الموظف قبل الإيقاف" $emp.S 200
Expect "الموظف يرى الصادر قبل الإيقاف" (Api GET "/outgoing" $null $empTok $cid).S 200

try {
# ════════════════════ ١) الإيقاف ════════════════════
Write-Host "`n=== ١) الإيقاف: السوبر أدمن وحده يتصفّح ===" -ForegroundColor Cyan
Expect "الموظف لا يملك لوحة التحكّم" (Api PUT "/system/lockdown" @{active=$true;message="x"} $empTok $cid).S 403
Expect "الإيقاف بلا رسالة يُرفض" (Api PUT "/system/lockdown" @{active=$true;message="  "} $admin $null).S 400

$msg="النظام متوقّف للتحديث — نعود خلال نصف ساعة"
$r=Api PUT "/system/lockdown" @{active=$true;message=$msg} $admin $null
Expect "السوبر أدمن يوقف النظام" $r.S 200
Expect "   والحالة موقوفة" $r.B.lockdown.active $true
if($r.B.lockdown.byName){ Ok "   واسم مَن أوقفه ظاهرٌ له: $($r.B.lockdown.byName)" } else { Bad "   اسم الفاعل غائب" }

$r=Api GET "/outgoing" $null $empTok $cid
Expect "الموظف: قائمة الصادر ⇒ 503" $r.S 503
Expect "   والجسم يحمل رسالة المالك" $r.B.error $msg
Expect "   ويُعلَّم صيانةً" $r.B.maintenance $true
Expect "   ويُعلَّم إيقافاً" $r.B.lockdown $true
Expect "الموظف: إنشاء وارد ⇒ 503" (Api POST "/incoming" @{subject="x"} $empTok $cid).S 503
Expect "الموظف: /auth/me ⇒ 503" (Api GET "/auth/me" $null $empTok $cid).S 503

Expect "السوبر أدمن: قائمة الصادر تعمل" (Api GET "/outgoing" $null $admin $cid).S 200
Expect "السوبر أدمن: قائمة المستخدمين تعمل" (Api GET "/users" $null $admin $null).S 200

$st=Api GET "/system/status" $null $null $null
Expect "الحالة العامّة تجيب بلا رمز" $st.S 200
Expect "   وتُعلن الإيقاف" $st.B.lockdown.active $true
Expect "   برسالة المالك (تظهر على شاشة الدخول)" $st.B.lockdown.message $msg
if(-not $st.B.lockdown.byName){ Ok "   ولا تكشف اسم مَن أوقفه للعموم" } else { Bad "   كشفت اسم الفاعل: $($st.B.lockdown.byName)" }
Expect "طلبٌ مجهول لنقطةٍ مغلقة ⇒ 503" (Api GET "/companies/$cid/logo" $null $null $null).S 503
$exp=Api GET "/outgoing" $null "eyJhbGciOiJIUzI1NiJ9.e30.invalid" $cid
Expect "رمزٌ غير مقبول ⇒ 401 لا 503 (ليجدّده صاحبه)" $exp.S 401

# ════════════════════ ٢) الدخول ════════════════════
Write-Host "`n=== ٢) الدخول أثناء الإيقاف ===" -ForegroundColor Cyan
$before=[int](SqlScalar "SELECT FailedLoginCount FROM Users WHERE UserId=$empUserId")
$r=LoginR $uname $upwd
Expect "كلمة صحيحة لموظف ⇒ 503" $r.S 503
Expect "   برسالة المالك" $r.B.error $msg
if(-not $r.B.accessToken){ Ok "   ولا يُصدَر رمز" } else { Bad "   صدر رمزٌ أثناء الإيقاف" }
Expect "   ولا تُحسب محاولةً فاشلة" ([int](SqlScalar "SELECT FailedLoginCount FROM Users WHERE UserId=$empUserId")) $before

$r=LoginR $uname 'Wrong@000'
Expect "كلمة خاطئة ⇒ 400 كالمعتاد" $r.S 400
Expect "   وتُحسب (حماية التخمين باقية)" ([int](SqlScalar "SELECT FailedLoginCount FROM Users WHERE UserId=$empUserId")) ($before+1)

# ⚠️ **يُعدّ قبل وبعد لا من الصفر**: تفعيلُ الكلمة المؤقتة (G19) يُلغي جلساتٍ سابقة عمداً.
$revBefore=[int](SqlScalar "SELECT COUNT(*) FROM RefreshTokens WHERE UserId=$empUserId AND RevokedAt IS NOT NULL")
$r=Api POST "/auth/refresh" @{refreshToken=$empRefresh} $null $null
Expect "تجديد رمز الموظف ⇒ 503" $r.S 503
$revoked=[int](SqlScalar "SELECT COUNT(*) FROM RefreshTokens WHERE UserId=$empUserId AND RevokedAt IS NOT NULL")
Expect "   ولم يُدوَّر رمز التجديد (الجلسة باقية)" $revoked $revBefore

$r=LoginR 'admin' $AdminPwd
Expect "السوبر أدمن يدخل أثناء الإيقاف" $r.S 200
$admin=$r.B.accessToken

# ════════════════════ ٣) التحقق العامّ ════════════════════
Write-Host "`n=== ٣) صفحة التحقق العامّة تبقى تعمل ===" -ForegroundColor Cyan
$root=$Base -replace '/api$',''
try { $v=Invoke-WebRequest -Uri "$root/v/AAAAAAAAAAAAAAAAAAAAAA" -UseBasicParsing; $vs=[int]$v.StatusCode } catch { $vs=[int]$_.Exception.Response.StatusCode }
if($vs -ne 503){ Ok "/v/{token} تجيب ($vs) لا 503" } else { Bad "/v/{token} محجوبة بالإيقاف" }
$r=Api POST "/verify" @{payload="DMS1|x"} $null $null
if($r.S -ne 503){ Ok "/api/verify تجيب ($($r.S)) لا 503" } else { Bad "/api/verify محجوبة بالإيقاف" }

# ════════════════════ ٤) الشريط ════════════════════
Write-Host "`n=== ٤) شريط الإعلان ===" -ForegroundColor Cyan
Expect "إظهارٌ بلا نصّ يُرفض" (Api PUT "/system/announcement" @{visible=$true;text="";kind='Info'} $admin $null).S 400
$ann="سيُحدَّث النظام الليلة"
$r=Api PUT "/system/announcement" @{visible=$true;text=$ann;kind='Warning'} $admin $null
Expect "إظهار الشريط" $r.S 200
$st=Api GET "/system/status" $null $admin $null
Expect "   المصادَق يرى النصّ" $st.B.announcement.text $ann
Expect "   بنوعه" $st.B.announcement.kind 'Warning'
$st=Api GET "/system/status" $null $null $null
if($null -eq $st.B.announcement){ Ok "   والمجهول لا يراه" } else { Bad "   المجهول رأى الشريط: $($st.B.announcement.text)" }
$r=Api PUT "/system/announcement" @{visible=$false;text=$null;kind='Warning'} $admin $null
Expect "إخفاء الشريط" $r.B.announcement.visible $false
Expect "   والنصّ باقٍ لإعادة إظهاره" $r.B.announcement.text $ann

# النصوص المحفوظة
$r=Api POST "/system/saved-texts" @{kind='Lockdown';text=$msg} $admin $null
Expect "حفظ نصّ إيقاف" (@($r.B.savedLockdownTexts) -contains $msg) $true
$r=Api POST "/system/saved-texts" @{kind='Announcement';text=$ann} $admin $null
Expect "حفظ نصّ شريط (قائمةٌ منفصلة)" "$(@($r.B.savedAnnouncementTexts).Count)/$(@($r.B.savedLockdownTexts).Count)" "1/1"
$enc=[uri]::EscapeDataString($ann)
Expect "حذف نصٍّ محفوظ" (Api DELETE "/system/saved-texts?kind=Announcement&text=$enc" $null $admin $null).S 200
Expect "   وحذفُه ثانيةً ⇒ 404" (Api DELETE "/system/saved-texts?kind=Announcement&text=$enc" $null $admin $null).S 404

# ════════════════════ ٥) النسخ والاستعادة أثناء الإيقاف ════════════════════
Write-Host "`n=== ٥) نسخةٌ يدوية واستعادة — والإيقاف يبقى ===" -ForegroundColor Cyan
$job=WaitJob (Api POST "/backup/run" $null $admin $null) $admin
Expect "السوبر أدمن يأخذ نسخةً يدوية أثناء الإيقاف" $job.state 'Succeeded'
$bkId=$job.result.backupRecordId
if($bkId){
  $job=WaitJob (Api POST "/backup/$bkId/restore" @{confirmation="استعادة"} $admin $null) $admin
  Expect "   ويستعيدها" $job.state 'Succeeded'
  $st=Api GET "/system/status" $null $null $null
  Expect "   🔴 والاستعادة لم تُنهِ الإيقاف" $st.B.lockdown.active $true
  Expect "   ولا صيانةَ استعادةٍ عالقة" $st.B.maintenance $false
  Expect "   والموظف ما زال محجوباً" (Api GET "/outgoing" $null $empTok $cid).S 503
} else { Bad "لم تُعِد النسخة رقمها: $($job | ConvertTo-Json -Compress)" }

# ════════════════════ ٦) أمر الطوارئ على السيرفر ════════════════════
if($StateFile -and $ApiDll){
  Write-Host "`n=== ٦) أمر الطوارئ: maintenance off/on من سطر الأوامر ===" -ForegroundColor Cyan
  $out=& dotnet $ApiDll maintenance off --file $StateFile 2>&1
  Start-Sleep -Seconds 4
  Expect "الأمر off يسري والخادم يعمل" (Api GET "/system/status" $null $null $null).B.lockdown.active $false
  Expect "   والموظف يعود" (Api GET "/outgoing" $null $empTok $cid).S 200
  $out=& dotnet $ApiDll maintenance on "طوارئ من السيرفر" --file $StateFile 2>&1
  Start-Sleep -Seconds 4
  $st=Api GET "/system/status" $null $null $null
  Expect "الأمر on يسري" $st.B.lockdown.active $true
  Expect "   برسالته" $st.B.lockdown.message "طوارئ من السيرفر"
  $n=[int](SqlScalar "SELECT COUNT(*) FROM AuditLogs WHERE EntityType='System' AND Details LIKE N'%وحدة تحكّم السيرفر%'")
  if($n -ge 2){ Ok "   وكلاهما مدوَّنٌ في التدقيق ($n)" } else { Bad "   سطور التدقيق من السيرفر: $n" }
} else { Write-Host "  (تُخطّى: مرّر -StateFile و-ApiDll لاختبار أمر الطوارئ)" -ForegroundColor DarkGray }

# ════════════════════ ٧) التشغيل ════════════════════
Write-Host "`n=== ٧) التشغيل: الموظف يعود بجلسته نفسها ===" -ForegroundColor Cyan
$r=Api PUT "/system/lockdown" @{active=$false} $admin $null
Expect "السوبر أدمن يشغّل النظام" $r.B.lockdown.active $false
Expect "الموظف يرى الصادر بالرمز نفسه" (Api GET "/outgoing" $null $empTok $cid).S 200
$r=Api POST "/auth/refresh" @{refreshToken=$empRefresh} $null $null
Expect "   ورمز التجديد القديم ما زال صالحاً" $r.S 200
Expect "   ودخوله بكلمته يعمل" (LoginR $uname $upwd).S 200

$acts=@(SqlScalar "SELECT COUNT(*) FROM AuditLogs WHERE Action IN ('SystemLockdownOn','SystemLockdownOff','AnnouncementShown','AnnouncementHidden')")
if([int]$acts[0] -ge 4){ Ok "الإيقاف والتشغيل والشريط مدوَّنةٌ في التدقيق ($($acts[0]))" } else { Bad "سطور التدقيق: $($acts[0])" }
}
finally {
  $t=(LoginR 'admin' $AdminPwd).B.accessToken
  if($t){ $null=Api PUT "/system/lockdown" @{active=$false} $t $null }
}

Write-Host "`n══════ النتيجة: $pass نجح · $fail فشل ══════" -ForegroundColor $(if($fail){'Red'}else{'Green'})
if($fail){ exit 1 }
