param([string]$AdminPwd='Admin@12345', [string]$Base='http://localhost:5091/api',
      [string]$VersionFile="$PSScriptRoot\..\..\VERSION")
# ════════════════════════════════════════════════════════════════════════════
#  استعادة نسخةٍ من جهاز المستخدم (ADR-055) — **بلاغ المالك 2026-09-24**:
#  أخذ نسخةً على جهاز التطوير وأخرى على الدومين ولم يستطع استعادة أيٍّ منهما على الآخر.
#
#  هنا: نسخةٌ تُؤخذ وتُنزَّل (كما يفعل المالك) ⟵ تُرفع بقطع ⟵ تُفحص ⟵ تظهر «مرفوعة» ⟵ **وتُستعاد**.
#  ومعها الرفض: ملفٌّ ليس نسخة · نسخةٌ من إصدارٍ أحدث · مهاجرةٌ من المستقبل · قطعٌ خارج الترتيب.
#
#  ⚠️ **تدميريّ** (يستعيد القاعدة) — على قاعدةٍ منفصلة، **قبل `backup-restore` مباشرةً**.
# ════════════════════════════════════════════════════════════════════════════
$ErrorActionPreference='Stop'; $pass=0; $fail=0
Add-Type -AssemblyName System.IO.Compression.FileSystem
function Ok($m){ $script:pass++; Write-Host "  [نجح] $m" -ForegroundColor Green }
function Bad($m){ $script:fail++; Write-Host "  [فشل] $m" -ForegroundColor Red }
function Api($m,$u,$b,$t){ $h=@{}; if($t){$h.Authorization="Bearer $t"}
  $p=@{Uri="$Base$u";Method=$m;Headers=$h;ContentType="application/json; charset=utf-8"}
  if($null -ne $b){$p.Body=[Text.Encoding]::UTF8.GetBytes(($b|ConvertTo-Json -Depth 8 -Compress))}
  try{$r=Invoke-WebRequest @p -UseBasicParsing; $j=$null; if($r.Content){try{$j=$r.Content|ConvertFrom-Json}catch{}}; return @{S=[int]$r.StatusCode;B=$j}}
  catch{$resp=$_.Exception.Response; $code=if($resp){[int]$resp.StatusCode}else{0}; $ct=''; if($resp){$sr=[IO.StreamReader]::new($resp.GetResponseStream());$ct=$sr.ReadToEnd()}; $j=$null; if($ct){try{$j=$ct|ConvertFrom-Json}catch{}}; return @{S=$code;B=$j}}
}
function Chunk($id,$index,[byte[]]$bytes,$t){
  try{ $r=Invoke-WebRequest -Uri "$Base/backup/uploads/$id/chunks/$index" -Method Put -Body $bytes `
        -ContentType 'application/octet-stream' -Headers @{Authorization="Bearer $t"} -UseBasicParsing
       return @{S=[int]$r.StatusCode;B=($r.Content|ConvertFrom-Json)} }
  catch{ $resp=$_.Exception.Response; return @{S=$(if($resp){[int]$resp.StatusCode}else{0});B=$null} }
}
function Expect($label,$actual,$expected){ if("$actual" -eq "$expected"){ Ok $label } else { Bad "$label (المتوقّع $expected والفعلي $actual)" } }
function WaitJob($start,$tok){
  if($start.S -ne 202 -or -not $start.B.id){ return [pscustomobject]@{state="NotStarted";message="HTTP $($start.S)"} }
  for($i=0;$i -lt 900;$i++){
    $j=Api GET "/system/jobs/$($start.B.id)" $null $tok
    if($j.S -eq 503){ Start-Sleep -Milliseconds 700; continue }   # صيانة الاستعادة — انتظار
    if($j.S -ne 200){ return [pscustomobject]@{state="Lost";message="HTTP $($j.S)"} }
    if($j.B.state -ne 'Running'){ return $j.B }
    Start-Sleep -Milliseconds 400
  }
  return [pscustomobject]@{state="Timeout";message="لم تنتهِ"}
}
# يرفع ملفاً بقطعٍ بحجمٍ نختاره (أصغر من حدّ الخادم ليُختبر التعدّد) ثم «اكتمل» ويعيد العملية.
function UploadFile($path,$name,$tok,[int]$piece=200000){
  $bytes=[IO.File]::ReadAllBytes($path)
  $st=Api POST "/backup/uploads" @{fileName=$name;sizeBytes=$bytes.Length} $tok
  if($st.S -ne 200){ return @{Start=$st} }
  $id=$st.B.uploadId; $i=0
  for($off=0;$off -lt $bytes.Length;$off+=$piece){
    $len=[Math]::Min($piece,$bytes.Length-$off); $part=New-Object byte[] $len
    [Array]::Copy($bytes,$off,$part,0,$len)
    $r=Chunk $id $i $part $tok; if($r.S -ne 200){ return @{Start=$st;Chunk=$r} }; $i++
  }
  return @{Start=$st;Id=$id;Chunks=$i;Job=(WaitJob (Api POST "/backup/uploads/$id/complete" $null $tok) $tok)}
}
# يعيد كتابة backup-info.json داخل نسخة (لصنع «نسخةٍ من المستقبل»).
function WithInfo($src,$dst,$app,$migration){
  Copy-Item $src $dst -Force
  $z=[IO.Compression.ZipFile]::Open($dst,'Update')
  try{ $old=$z.GetEntry('backup-info.json'); if($old){$old.Delete()}
       $e=$z.CreateEntry('backup-info.json'); $w=New-Object IO.StreamWriter($e.Open())
       $w.Write((@{appVersion=$app;lastMigration=$migration;sqlMajorVersion=$null;createdAtUtc=(Get-Date).ToUniversalTime().ToString('o')}|ConvertTo-Json -Compress)); $w.Close() }
  finally{ $z.Dispose() }
}

$expected=(Get-Content $VersionFile -Raw).Trim()
$mk=[guid]::NewGuid().ToString('N').Substring(0,6)
$work=Join-Path $env:TEMP "dms-upload-e2e-$mk"; New-Item -ItemType Directory -Force $work | Out-Null

$admin=(Api POST "/auth/login" @{username='admin';password=$AdminPwd} $null).B.accessToken
if(-not $admin){ Bad "تعذّر دخول admin — هل شُغّل bootstrap-e2e أولاً؟"; exit 1 }

try {
Write-Host "`n=== ١) نسخةٌ تُؤخذ وتُنزَّل — كما يفعل المالك ===" -ForegroundColor Cyan
$run=WaitJob (Api POST "/backup/run" $null $admin) $admin
Expect "نسخةٌ كاملة تُؤخذ" $run.state 'Succeeded'
$rec=@((Api GET "/backup" $null $admin).B) | Where-Object { $_.status -eq 'Success' } | Sort-Object createdAt -Descending | Select-Object -First 1
$zip=Join-Path $work "downloaded.zip"
Invoke-WebRequest -Uri "$Base/backup/$($rec.backupRecordId)/download" -Headers @{Authorization="Bearer $admin"} -OutFile $zip -UseBasicParsing
if((Get-Item $zip).Length -gt 0){ Ok "وتُنزَّل ($([Math]::Round((Get-Item $zip).Length/1KB)) KB)" } else { Bad "التنزيل فارغ" }

# 🏷️ كلُّ نسخةٍ جديدة تحمل أصلها.
$z=[IO.Compression.ZipFile]::OpenRead($zip)
try{ $e=$z.GetEntry('backup-info.json'); $info=if($e){ (New-Object IO.StreamReader($e.Open())).ReadToEnd() | ConvertFrom-Json } else { $null } } finally { $z.Dispose() }
Expect "🏷️ النسخة تحمل backup-info.json بإصدار البرنامج" $info.appVersion $expected
if($info.lastMigration){ Ok "وآخر مهاجرة ($($info.lastMigration))" } else { Bad "آخر مهاجرة غائبة" }
if($info.sqlMajorVersion -ge 11){ Ok "وإصدار SQL Server ($($info.sqlMajorVersion))" } else { Bad "إصدار SQL Server غائب" }

Write-Host "`n=== ٢) الرفع بقطع — الترتيب والإعادة والإلغاء ===" -ForegroundColor Cyan
Expect "🔐 ملفٌّ غير .zip يُرفض قبل أوّل بايت (400)" (Api POST "/backup/uploads" @{fileName='x.bak';sizeBytes=10} $admin).S 400
Expect "وحجمٌ صفر يُرفض (400)" (Api POST "/backup/uploads" @{fileName='x.zip';sizeBytes=0} $admin).S 400
Expect "🔐 الرفع للسوبر أدمن وحده — المجهول 401" (Api POST "/backup/uploads" @{fileName='x.zip';sizeBytes=10} $null).S 401

$s=(Api POST "/backup/uploads" @{fileName='order.zip';sizeBytes=6} $admin).B
Expect "قطعةٌ خارج الترتيب تُرفض (409)" (Chunk $s.uploadId 1 ([byte[]](1,2,3)) $admin).S 409
$c0=Chunk $s.uploadId 0 ([byte[]](1,2,3)) $admin
Expect "القطعة الأولى تُقبل" $c0.B.receivedBytes 3
$again=Chunk $s.uploadId 0 ([byte[]](1,2,3)) $admin
Expect "🔑 إعادةُ قطعةٍ وصلت لا تُلحَق ثانيةً (طلبٌ ضاع ردُّه)" $again.B.receivedBytes 3
Expect "«اكتمل» قبل الاكتمال يُرفض (400)" (Api POST "/backup/uploads/$($s.uploadId)/complete" $null $admin).S 400
Expect "الإلغاء يحذف ما وصل (204)" (Api DELETE "/backup/uploads/$($s.uploadId)" $null $admin).S 204
Expect "وبعده لا يُعرف الرفع (404)" (Chunk $s.uploadId 1 ([byte[]](4,5,6)) $admin).S 404
Expect "🔐 معرّفٌ ليس سداسياً (محاولة مسار) ⇒ 404" (Chunk '..%2F..%2Fetc' 0 ([byte[]](1)) $admin).S 404

Write-Host "`n=== ٣) الرفض قبل أن يصير نسخة ===" -ForegroundColor Cyan
$notBackup=Join-Path $work "not-a-backup.zip"
$z=[IO.Compression.ZipFile]::Open($notBackup,'Create'); try{ $e=$z.CreateEntry('readme.txt'); $w=New-Object IO.StreamWriter($e.Open()); $w.Write('hello'); $w.Close() } finally { $z.Dispose() }
$u=UploadFile $notBackup 'not-a-backup.zip' $admin
Expect "🔴 أرشيفٌ بلا database.bak يُرفض" $u.Job.state 'Failed'
if("$($u.Job.message)" -match 'database.bak'){ Ok "   ورسالتُه تذكر السبب" } else { Bad "   الرسالة: $($u.Job.message)" }

$future=Join-Path $work "future-version.zip"; WithInfo $zip $future '99.0.0' $info.lastMigration
$u=UploadFile $future 'future-version.zip' $admin
Expect "🔴 نسخةٌ من إصدارٍ أحدث (99.0.0) تُرفض" $u.Job.state 'Failed'
if("$($u.Job.message)" -match '99\.0\.0'){ Ok "   ورسالتُها تذكر الإصدارين" } else { Bad "   الرسالة: $($u.Job.message)" }

$futureMig=Join-Path $work "future-migration.zip"; WithInfo $zip $futureMig $expected '20991231000000_FromTheFuture'
$u=UploadFile $futureMig 'future-migration.zip' $admin
Expect "🔴 نسخةٌ بمهاجرةٍ لا يعرفها الكود تُرفض" $u.Job.state 'Failed'

$before=@((Api GET "/backup" $null $admin).B).Count
Expect "والمرفوضة لا تظهر في القائمة" (@((Api GET "/backup" $null $admin).B) | Where-Object { $_.type -eq 'Uploaded' }).Count 0

Write-Host "`n=== ٤) المرآة: رسالةٌ تدلّ لا تُحيّر ===" -ForegroundColor Cyan
$mirrorDir=Join-Path $work "not-a-mirror"; New-Item -ItemType Directory -Force $mirrorDir | Out-Null
Copy-Item $zip (Join-Path $mirrorDir "backup.zip")
$mr=Api POST "/backup/mirror/restore" @{sourcePath=$mirrorDir;confirmation='استعادة'} $admin
Expect "🐛 مجلدُ نسخةٍ عادية ليس مرآة ⇒ 400 (كان 404 «لم يُعثر على database.bak»)" $mr.S 400

Write-Host "`n=== ٥) الرفع الصحيح ثم الاستعادة — سيناريو المالك ===" -ForegroundColor Cyan
$u=UploadFile $zip "dev-machine-$mk.zip" $admin
if($u.Chunks -gt 1){ Ok "رُفعت بـ$($u.Chunks) قطع" } else { Bad "قطعةٌ واحدة — لم يُختبر التعدّد" }
Expect "✅ النسخة المرفوعة تُفحص وتُقبل" $u.Job.state 'Succeeded'
$up=@((Api GET "/backup" $null $admin).B) | Where-Object { $_.type -eq 'Uploaded' } | Select-Object -First 1
if($up){ Ok "وتظهر في القائمة بنوع «مرفوعة»" } else { Bad "المرفوعة غائبةٌ عن القائمة"; throw "stop" }
if("$($up.note)" -match [regex]::Escape("dev-machine-$mk.zip")){ Ok "   وملاحظتُها تذكر اسم الملف الأصليّ" } else { Bad "   الملاحظة: $($up.note)" }
Expect "   ونطاقُها «كاملة» (فيها files/)" $up.scope 'Full'

# علامةٌ تُكتب **بعد** النسخة — فإن عادت القاعدة إلى النسخة اختفت.
$cid=@((Api GET "/companies" $null $admin).B)[0].companyId
$ent=Api POST "/entities" @{companyId=$cid;name="بعد النسخة $mk";kind='Both'} $admin
$markExists={ @((Api GET "/entities" $null $admin).B) | Where-Object { $_.name -eq "بعد النسخة $mk" } }

$rs=Api POST "/backup/$($up.backupRecordId)/restore" @{confirmation='استعادة'} $admin
$rj=WaitJob $rs $admin
Expect "✅ استعادة النسخة المرفوعة تنجح" $rj.state 'Succeeded'
$admin=(Api POST "/auth/login" @{username='admin';password=$AdminPwd} $null).B.accessToken
Expect "والدخول يعمل بعدها" ([bool]$admin) 'True'
if($ent.S -ne 200){ Ok "(لا شركة فعّالة للسوبر أدمن — تخطّي علامة الجهة)" }
elseif(-not (& $markExists)){ Ok "🔑 القاعدة عادت فعلاً إلى لحظة النسخة (ما كُتب بعدها زال)" } else { Bad "ما كُتب بعد النسخة ما زال — الاستعادة لم تحدث" }
}
finally {
  Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`n============ النتيجة ============" -ForegroundColor Cyan
Write-Host "  نجح: $pass" -ForegroundColor Green
Write-Host "  فشل: $fail" -ForegroundColor $(if($fail){'Red'}else{'Green'})
exit $(if($fail){1}else{0})
