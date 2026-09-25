param([string]$AdminPwd='Admin@12345', [string]$Base='http://localhost:5091/api',
      [string]$Db='Server=.;Database=DmsE2E_New;Integrated Security=true;TrustServerCertificate=True',
      [string]$VersionFile="$PSScriptRoot\..\..\VERSION")
# ════════════════════════════════════════════════════════════════════════════
#  رقم إصدار البرنامج (ADR-054):
#   - الخادم يحمل رقم ملف `VERSION` نفسه (من ملف التجميع لا من إعداد).
#   - 🔐 **لا يكشفه للمجهول** — `/system/status` مفتوحةٌ للعالم عبر الدومين.
#   - «حول النظام» للمصادَق: الإصدار والـcommit ولحظة البناء وآخر مهاجرة.
#   - أوّلُ إقلاعٍ بإصدارٍ جديد يُسجَّل في التدقيق **مرّةً واحدة**.
# ════════════════════════════════════════════════════════════════════════════
$ErrorActionPreference='Stop'; $pass=0; $fail=0
function Ok($m){ $script:pass++; Write-Host "  [نجح] $m" -ForegroundColor Green }
function Bad($m){ $script:fail++; Write-Host "  [فشل] $m" -ForegroundColor Red }
function Api($m,$u,$b,$t){ $h=@{}; if($t){$h.Authorization="Bearer $t"}
  $p=@{Uri="$Base$u";Method=$m;Headers=$h;ContentType="application/json; charset=utf-8"}
  if($null -ne $b){$p.Body=[Text.Encoding]::UTF8.GetBytes(($b|ConvertTo-Json -Depth 8 -Compress))}
  try{$r=Invoke-WebRequest @p -UseBasicParsing; $j=$null; if($r.Content){try{$j=$r.Content|ConvertFrom-Json}catch{}}; return @{S=[int]$r.StatusCode;B=$j;Raw=$r.Content}}
  catch{$resp=$_.Exception.Response; $code=if($resp){[int]$resp.StatusCode}else{0}; return @{S=$code;B=$null;Raw=''}}
}
function Expect($label,$actual,$expected){ if("$actual" -eq "$expected"){ Ok $label } else { Bad "$label (المتوقّع $expected والفعلي $actual)" } }
function Sql($sql){
  $cn=New-Object System.Data.SqlClient.SqlConnection($Db); $cn.Open()
  try{ $cmd=$cn.CreateCommand(); $cmd.CommandText=$sql; return $cmd.ExecuteScalar() } finally { $cn.Close() }
}

$expected=(Get-Content $VersionFile -Raw).Trim()
Write-Host "=== الإصدار المتوقّع من VERSION: $expected ===" -ForegroundColor Cyan

Write-Host "`n=== ١) المجهول لا يرى الإصدار ===" -ForegroundColor Cyan
$anon=Api GET "/system/status" $null $null
Expect "حالة النظام تجيب بلا رمز" $anon.S 200
Expect "🔐 ولا تكشف الإصدار للمجهول" ([string]::IsNullOrEmpty("$($anon.B.version)")) 'True'
Expect "🔐 و«حول النظام» محجوبٌ عن المجهول (401)" (Api GET "/system/about" $null $null).S 401

Write-Host "`n=== ٢) المصادَق يراه — وهو رقم الملف نفسه ===" -ForegroundColor Cyan
$admin=(Api POST "/auth/login" @{username='admin';password=$AdminPwd} $null).B.accessToken
if(-not $admin){ Bad "تعذّر دخول admin — هل شُغّل bootstrap-e2e أولاً؟"; exit 1 }
Expect "حالة النظام تحمل الإصدار للمصادَق" (Api GET "/system/status" $null $admin).B.version $expected

$about=Api GET "/system/about" $null $admin
Expect "«حول النظام» يجيب" $about.S 200
Expect "🔑 إصدار الخادم = ملف VERSION" $about.B.version $expected
if("$($about.B.commit)" -match '^[0-9a-f]{7}$'){ Ok "ومعه رمز الـcommit المختصر ($($about.B.commit))" } else { Bad "رمز الـcommit غائبٌ أو بغير صيغته: '$($about.B.commit)'" }
if($about.B.builtAtUtc){ Ok "ولحظة البناء ($($about.B.builtAtUtc))" } else { Bad "لحظة البناء غائبة" }
Expect "آخرُ مهاجرةٍ في الكود = آخرُ المطبَّق على القاعدة" $about.B.latestMigration $about.B.appliedMigration
$dbCount=[int](Sql "SELECT COUNT(*) FROM __EFMigrationsHistory")
Expect "وعددُ المهاجرات = سجلُّ القاعدة نفسه ($dbCount)" $about.B.migrationCount $dbCount

Write-Host "`n=== ٣) سجلّ التدقيق ===" -ForegroundColor Cyan
# 🔑 **مرّةً واحدة لكل إصدار** — وإلا امتلأ السجلّ بسطرٍ مع كل إعادة تشغيل.
$rows=[int](Sql "SELECT COUNT(*) FROM AuditLogs WHERE Action='AppVersion' AND EntityId='$expected'")
Expect "الإقلاع بالإصدار $expected مسجَّلٌ في التدقيق مرّةً واحدة" $rows 1
$details="$(Sql "SELECT TOP 1 Details FROM AuditLogs WHERE Action='AppVersion' ORDER BY LogId DESC")"
if($details -match [regex]::Escape($expected)){ Ok "والسطر يذكر الإصدار" } else { Bad "سطر التدقيق لا يذكر الإصدار: $details" }

Write-Host "`n============ النتيجة ============" -ForegroundColor Cyan
Write-Host "  نجح: $pass" -ForegroundColor Green
Write-Host "  فشل: $fail" -ForegroundColor $(if($fail){'Red'}else{'Green'})
exit $(if($fail){1}else{0})
