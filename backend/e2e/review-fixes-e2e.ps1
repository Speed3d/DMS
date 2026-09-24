param([string]$AdminPwd='Admin@12345', [string]$Base='http://localhost:5091/api',
      [string]$Db='Server=.;Database=DmsReviewScratch;Integrated Security=true;TrustServerCertificate=True')
# ════════════════════════════════════════════════════════════════════════════════════════
#  حرّاس المراجعة الشاملة (2026-09-23) — ثلاثة عيوب كُشفت بالقراءة وتُثبَت هنا بالتشغيل.
#
#  ١) **تعديلُ مديرٍ لمستخدمٍ يُفسد صلاحياته**: الواجهة ترسل قائمة الشركات دائماً، فكان
#     الخادم يعيد أقسام المستخدم إلى الافتراض (127) ويُسقط إسناداته في الشركات الأخرى.
#     ورئيسُ الشركة يُسقط إسناداتٍ في شركاتٍ ليست له.
#  ٢) **كتابة المستمسكات والإيصالات محروسةٌ بالرؤية وحدها**: مَن يرى الموظفين أو الرواتب
#     بلا علَم الكتابة كان يرفع ويحذف — والإيصال كان **يُحفظ قبل** فحص الكتابة.
#  ٣) **حذفُ شركةٍ فيها مهمةٌ محذوفة ناعماً يفشل بـ500** (مفتاح أجنبيّ من المهام)، والحذف
#     الناجح كان يُخلّف صفوفاً يتيمة (أرشيف · أقسام · كشوف رواتب · إعدادات).
#
#  ⚠️ **على قاعدةٍ منفصلة لا `DmsDb`** — والتحقّق من الصفوف اليتيمة يقرأ القاعدة مباشرةً.
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


# رفعُ ملفٍّ متعدّد الأجزاء — يعيد رمز الحالة وجسم الردّ.
function Upload($u,$t,$c,$name){
  $bd=[Guid]::NewGuid().ToString()
  $body=[Text.Encoding]::UTF8.GetBytes(
    "--$bd`r`nContent-Disposition: form-data; name=`"file`"; filename=`"$name`"`r`nContent-Type: application/pdf`r`n`r`n%PDF-1.4 review`r`n--$bd--`r`n")
  try{
    $r=Invoke-WebRequest -Uri "$Base$u" -Method Post -Headers @{Authorization="Bearer $t";'X-Company-Id'="$c"} `
       -ContentType "multipart/form-data; boundary=$bd" -Body $body -UseBasicParsing
    return @{S=[int]$r.StatusCode;B=($r.Content|ConvertFrom-Json)}
  }catch{ $resp=$_.Exception.Response; return @{S=$(if($resp){[int]$resp.StatusCode}else{0});B=$null} }
}

# عدُّ صفوفٍ مباشرةً من القاعدة — ما لا تكشفه الـAPI بعد اختفاء الشركة.
function SqlCount($sql){
  $cn=New-Object System.Data.SqlClient.SqlConnection($Db); $cn.Open()
  try{ $cmd=$cn.CreateCommand(); $cmd.CommandText=$sql; return [int]$cmd.ExecuteScalar() } finally { $cn.Close() }
}

. "$PSScriptRoot\_activate.ps1"   # G19: الكلمة المؤقتة تُفعَّل قبل الاستعمال
function Login($u,$p){ $null=Enable-TempPassword $Base $u $p; return (Api POST "/auth/login" @{username=$u;password=$p} $null $null).B.accessToken }

function Link($cid,$mods,$extra){
  $l=@{companyId=$cid;modules=$mods;departmentId=$null;canApprove=$false;canManageIncoming=$false
       canViewAllIncoming=$false;canManageEmployees=$false;canManagePayroll=$false
       canAmendPaidPayroll=$false;canManageTasks=$false}
  if($extra){ foreach($k in $extra.Keys){ $l[$k]=$extra[$k] } }
  return $l
}

function EnsureUser($username,$role,$companies){
  $ex=@((Api GET "/users" $null $admin $null).B) | Where-Object { $_.username -eq $username } | Select-Object -First 1
  $body=@{fullName="مراجعة $username";role=$role;isActive=$true;companies=$companies}
  if($ex){ $null=Api PUT "/users/$($ex.userId)" $body $admin $null }
  else { $body.username=$username; $body.password='Rv@123456'; $null=Api POST "/users" $body $admin $null }
  return @((Api GET "/users" $null $admin $null).B) | Where-Object { $_.username -eq $username } | Select-Object -First 1
}

function UserById($id){ return @((Api GET "/users" $null $admin $null).B) | Where-Object { $_.userId -eq $id } | Select-Object -First 1 }
function LinkOf($u,$cid){ return @($u.companies) | Where-Object { $_.companyId -eq $cid } | Select-Object -First 1 }
function Mods($l){ return (@($l.modules) | Sort-Object) -join ',' }

# ════════════════════════════ إعداد ════════════════════════════
Write-Host "`n=== إعداد: شركتان ===" -ForegroundColor Cyan
$admin=Login 'admin' $AdminPwd
if(-not $admin){ Bad "فشل دخول admin"; exit 1 }

$mk=Get-Random -Minimum 100 -Maximum 999
$cA=(Api POST "/companies" @{name="مراجعة أ $mk";prefix="RVA$mk";isActive=$true} $admin $null).B.companyId
$cB=(Api POST "/companies" @{name="مراجعة ب $mk";prefix="RVB$mk";isActive=$true} $admin $null).B.companyId
if(-not $cA -or -not $cB){ Bad "تعذّر إنشاء الشركتين"; exit 1 }
Ok "الشركتان: A=$cA · B=$cB"

# ════════════════════ ١) تعديلُ المستخدم لا يُفسد صلاحياته ════════════════════
Write-Host "`n=== ١) تعديل المدير والرئيس لمستخدمٍ في شركتين ===" -ForegroundColor Cyan

$emp=EnsureUser "rv_emp$mk" 'Employee' @(
  (Link $cA @('Incoming','Tasks') @{canManageTasks=$true}),
  (Link $cB @('Outgoing') $null))
$mgr=EnsureUser "rv_mgr$mk" 'Manager' @((Link $cA @('Outgoing','Archive','Reports','Users','Settings','Backup','Incoming') $null))
$pres=EnsureUser "rv_pres$mk" 'President' @((Link $cA @() $null))

Expect "المستخدم مُسنَدٌ لشركتين قبل التعديل" @($emp.companies).Count 2
Expect "   وأقسامه في A: الوارد والمهام وحدهما" (Mods (LinkOf $emp $cA)) 'Incoming,Tasks'

$tMgr=Login "rv_mgr$mk" 'Rv@123456'
if(-not $tMgr){ Bad "فشل دخول المدير"; exit 1 }

# ما ترسله الواجهة حرفياً: كل إسنادات المستخدم كما وصلتها + الاسم المعدَّل.
$seen=@((Api GET "/users" $null $tMgr $cA).B) | Where-Object { $_.userId -eq $emp.userId } | Select-Object -First 1
if(-not $seen){ Bad "المدير لا يرى المستخدم"; exit 1 }
$payload=@(@($seen.companies) | ForEach-Object {
  @{companyId=$_.companyId;modules=@($_.modules);departmentId=$_.departmentId;canApprove=$_.canApprove
    canManageIncoming=$_.canManageIncoming;canViewAllIncoming=$_.canViewAllIncoming
    canManageEmployees=$_.canManageEmployees;canManagePayroll=$_.canManagePayroll
    canAmendPaidPayroll=$_.canAmendPaidPayroll;canManageTasks=$_.canManageTasks} })
# والمدير يمنح «الاعتماد» في شركته — حقلٌ يملكه فعلاً ويجب أن يبقى يعمل.
($payload | Where-Object { $_.companyId -eq $cA }).canApprove=$true

$r=Api PUT "/users/$($emp.userId)" @{fullName="اسمٌ عدّله المدير";role='Employee';isActive=$true;companies=$payload} $tMgr $cA
Expect "تعديلُ المدير ينجح" $r.S 200

$after=UserById $emp.userId
Expect "🔴 المستخدم **ما زال** مُسنَداً للشركة B (المدير لا يملكها)" ([bool](LinkOf $after $cB)) 'True'
Expect "🔴 وأقسامه في A **لم تُصفَّر إلى 127**" (Mods (LinkOf $after $cA)) 'Incoming,Tasks'
Expect "🔴 وعلَمُ إدارة المهام **لم يسقط**" (LinkOf $after $cA).canManageTasks 'True'
Expect "   وأقسامه في B كما هي" (Mods (LinkOf $after $cB)) 'Outgoing'
Expect "✅ والاعتماد الذي منحه المدير **حُفظ** (ما يملكه المدير يبقى يعمل)" (LinkOf $after $cA).canApprove 'True'
Expect "✅ والاسم تغيّر" ($after.fullName -eq "اسمٌ عدّله المدير") 'True'

# المدير يُنزل الدور إلى «قارئ» ⇒ قاعدة القارئ تبقى نافذة: المهام تُجرَّد وعلَمها معها.
$payload2=$payload | ForEach-Object { $_ }
$r=Api PUT "/users/$($emp.userId)" @{fullName="اسمٌ عدّله المدير";role='Reader';isActive=$true;companies=$payload2} $tMgr $cA
Expect "إنزالُ الدور إلى قارئ ينجح" $r.S 200
$rd=UserById $emp.userId
Expect "🔐 والقارئ **جُرِّد من المهام** رغم الحفظ" (Mods (LinkOf $rd $cA)) 'Incoming'
Expect "🔐 وعلَمُ المهام جُرِّد معها" (LinkOf $rd $cA).canManageTasks 'False'
Expect "   والإسناد في B باقٍ" ([bool](LinkOf $rd $cB)) 'True'

# إعادةٌ إلى الأصل ثم اختبار الرئيس.
$emp=EnsureUser "rv_emp$mk" 'Employee' @(
  (Link $cA @('Incoming','Tasks') @{canManageTasks=$true}),
  (Link $cB @('Outgoing') $null))
$tPres=Login "rv_pres$mk" 'Rv@123456'
$seenP=@((Api GET "/users" $null $tPres $cA).B) | Where-Object { $_.userId -eq $emp.userId } | Select-Object -First 1
$payloadP=@(@($seenP.companies) | ForEach-Object {
  @{companyId=$_.companyId;modules=@($_.modules);departmentId=$_.departmentId;canApprove=$_.canApprove
    canManageIncoming=$_.canManageIncoming;canViewAllIncoming=$_.canViewAllIncoming
    canManageEmployees=$_.canManageEmployees;canManagePayroll=$_.canManagePayroll
    canAmendPaidPayroll=$_.canAmendPaidPayroll;canManageTasks=$_.canManageTasks} })
# الرئيس يملك الأقسام في شركته فيغيّرها فعلاً.
($payloadP | Where-Object { $_.companyId -eq $cA }).modules=@('Incoming','Tasks','Archive')
$r=Api PUT "/users/$($emp.userId)" @{fullName="اسمٌ عدّله الرئيس";role='Employee';isActive=$true;companies=$payloadP} $tPres $cA
Expect "تعديلُ الرئيس ينجح" $r.S 200
$afterP=UserById $emp.userId
Expect "🔴 الرئيس (في A وحدها) **لم يُسقط** إسناد B" ([bool](LinkOf $afterP $cB)) 'True'
Expect "✅ والرئيس غيّر الأقسام في شركته فعلاً" (Mods (LinkOf $afterP $cA)) 'Archive,Incoming,Tasks'

# والرئيس ما زال يستطيع **إزالة** إسنادٍ في شركته هو — لا نُجمّد ما يملكه.
$onlyB=@($payloadP | Where-Object { $_.companyId -eq $cB })
$r=Api PUT "/users/$($emp.userId)" @{fullName="اسمٌ عدّله الرئيس";role='Employee';isActive=$true;companies=$onlyB} $tPres $cA
Expect "الرئيس يُزيل إسناد شركته" $r.S 200
$afterR=UserById $emp.userId
Expect "✅ فأُزيل إسناد A" ([bool](LinkOf $afterR $cA)) 'False'
Expect "   وبقي B" ([bool](LinkOf $afterR $cB)) 'True'

# ════════════════ ٢) كتابة المستمسكات والإيصالات تحتاج علَم الكتابة ════════════════
Write-Host "`n=== ٢) المستمسكات والإيصالات: الرؤية ليست الكتابة ===" -ForegroundColor Cyan

$nid="RV$mk$(Get-Random -Minimum 1000 -Maximum 9999)"
$e=(Api POST "/employees" @{profile=@{fullName='موظف المراجعة';fullNameEn='Reviewer';nationalId=$nid;phone=$null;address=$null;notes=$null;receiptLanguage='Arabic'}
    employment=@{position='محاسب';positionEn='Accountant';hireDate='2024-01-01T00:00:00';salaryCurrency='IQD';baseSalary=1000000;displayOrder=1;isActive=$true}} $admin $cA).B
$empId=$e.employeeId
if(-not $empId){ Bad "تعذّر إنشاء الموظف"; exit 1 }
Ok "موظف: $empId"

$viewer=EnsureUser "rv_view$mk" 'Employee' @((Link $cA @('Employees','Payroll') $null))
$tView=Login "rv_view$mk" 'Rv@123456'
if(-not $tView){ Bad "فشل دخول القارئ-بالقسم"; exit 1 }

$up=Upload "/employees/$empId/attachments" $admin $cA 'id.pdf'
Expect "✅ صاحبُ الكتابة يرفع مستمسكاً" $up.S 200
$docId=$up.B.attachmentId

$list=Api GET "/employees/$empId/attachments" $null $tView $cA
Expect "✅ مَن يملك القسم **يرى** المستمسكات" $list.S 200

$up2=Upload "/employees/$empId/attachments" $tView $cA 'fake.pdf'
Expect "🔴 ومَن لا يملك علَم الكتابة **لا يرفع** مستمسكاً" $up2.S 403
$del=Api DELETE "/attachments/$docId" $null $tView $cA
Expect "🔴 **ولا يحذف** مستمسكاً" $del.S 403
Expect "   والمستمسك باقٍ" @(@((Api GET "/employees/$empId/attachments" $null $admin $cA).B) | Where-Object { $_.attachmentId -eq $docId }).Count 1

# الإيصال: سطرُ راتبٍ في كشف مسودّة يكفي (الرفع لا يشترط التسديد).
$yr=(Get-Date).Year; $mo=(Get-Date).Month
$null=Api POST "/payroll/periods/$yr/$mo" $null $admin $cA
$per=(Api GET "/payroll/periods/$yr/$mo" $null $admin $cA).B
$entry=@($per.entries) | Select-Object -First 1
if(-not $entry){ Bad "لا سطر في الكشف"; exit 1 }
$before=@((Api GET "/payroll/entries/$($entry.entryId)/receipts" $null $admin $cA).B).Count

$rc=Upload "/payroll/entries/$($entry.entryId)/receipts" $tView $cA 'receipt.pdf'
Expect "🔴 مَن يرى الرواتب بلا علَم الكتابة **لا يرفع** إيصالاً" $rc.S 403
$afterRc=@((Api GET "/payroll/entries/$($entry.entryId)/receipts" $null $admin $cA).B).Count
Expect "🔴 **ولا يُحفظ الملف رغم الرفض** (كان يُحفظ ثم يُرفض)" $afterRc $before

$rcOk=Upload "/payroll/entries/$($entry.entryId)/receipts" $admin $cA 'receipt.pdf'
Expect "✅ صاحبُ الكتابة يرفع الإيصال" $rcOk.S 200
$delRc=Api DELETE "/attachments/$($rcOk.B.attachmentId)" $null $tView $cA
Expect "🔴 ومَن لا يملك الكتابة **لا يحذف** الإيصال" $delRc.S 403

$delOk=Api DELETE "/attachments/$docId" $null $admin $cA
Expect "✅ وصاحبُ الكتابة يحذف المستمسك" $delOk.S 204

# ════════════════ ٣) حذف الشركة: مهمةٌ محذوفة لا تُفشله · ولا يتيم بعده ════════════════
Write-Host "`n=== ٣) حذف شركةٍ فيها بقايا محذوفة ناعماً ===" -ForegroundColor Cyan

$pC="RVC$mk"; $nameC="مراجعة الحذف $mk"
$cC=(Api POST "/companies" @{name=$nameC;prefix=$pC;isActive=$true} $admin $null).B.companyId
Ok "شركة الحذف: $cC"

# مهمتان: واحدةٌ تبقى (تُحذف ناعماً) وبمرفق.
$tk=(Api POST "/tasks" @{title='مهمة ستُحذف';taskType='Individual';priority='Normal';dueDate=(Get-Date).AddDays(3).ToString('yyyy-MM-dd')} $admin $cC).B
$tkAtt=Upload "/tasks/$($tk.taskId)/attachments" $admin $cC 'task.pdf'
$null=Api DELETE "/tasks/$($tk.taskId)" $null $admin $cC

# أرشيفٌ محذوف ناعماً · قسم · وموظفٌ فُكّ إسناده بعد كشفٍ مسودّة.
$ar=(Api POST "/archive" @{companyId=$cC;title='أضبارة ستُحذف'} $admin $cC).B
$null=Api DELETE "/archive/$($ar.archiveId)" $null $admin $cC
$null=Api POST "/departments" @{name='قسم الحذف'} $admin $cC
$nid2="RD$mk$(Get-Random -Minimum 1000 -Maximum 9999)"
$e2=(Api POST "/employees" @{profile=@{fullName='موظف الحذف';fullNameEn=$null;nationalId=$nid2;phone=$null;address=$null;notes=$null;receiptLanguage='Arabic'}
    employment=@{position='سائق';positionEn=$null;hireDate='2024-01-01T00:00:00';salaryCurrency='IQD';baseSalary=500000;displayOrder=1;isActive=$true}} $admin $cC).B
$null=Api POST "/payroll/periods/$yr/$mo" $null $admin $cC
$un=Api DELETE "/employees/$($e2.employeeId)/employment" $null $admin $cC
Expect "فكُّ إسناد الموظف (كشفٌ مسودّة لا يمنعه)" ($un.S -in 200,204) 'True'

$pv=(Api GET "/companies/$cC/delete-preview" $null $admin $null).B
$null=Api PUT "/companies/$cC" @{name=$nameC;prefix=$pC;isActive=$false} $admin $null
$pv=(Api GET "/companies/$cC/delete-preview" $null $admin $null).B
Expect "البيان يقول إن الحذف جائز (لا سجلّ حيّ)" $pv.canDelete 'True'

$d=Api DELETE "/companies/$cC`?confirm=$([uri]::EscapeDataString($nameC))" $null $admin $null
Expect "حذفُ الشركة يبدأ في الخلفية" $d.S 202
$dJob = WaitJob $d $admin
Expect "🔴 **حذفُ الشركة ينجح** رغم مهمةٍ محذوفة ناعماً (كان 500)" $dJob.state "Succeeded"

if($dJob.state -eq 'Succeeded'){
  $tables=@('OutgoingBooks','IncomingBooks','ArchiveDocs','DmsTasks','DmsTaskUpdates','DmsTaskParticipants',
    'Departments','EmployeeCompanies','PayrollPeriods','PayrollEntries','EmployeeLeaves','EmployeeLogs',
    'EmployeeLeaveSettlements','HrSettings','CaseFiles','BookReplies','MovementLogs','Notifications',
    'UserCompanies','Entities','DocumentTypes','Templates','Counters','ApprovalDelegations')
  $left=@()
  foreach($t in $tables){ $n=SqlCount "SELECT COUNT(*) FROM [$t] WHERE CompanyId=$cC"; if($n -gt 0){ $left+="$t=$n" } }
  if($left.Count -eq 0){ Ok "🔴 **لا صفَّ يتيماً** في $($tables.Count) جدولاً" } else { Bad "صفوفٌ يتيمة: $($left -join ' · ')" }

  if($tkAtt.S -eq 200){
    Expect "   ومرفقُ المهمة المحذوفة أُزيل من جدول المرفقات" (SqlCount "SELECT COUNT(*) FROM Attachments WHERE AttachmentId=$($tkAtt.B.attachmentId)") 0
  } else { Bad "تعذّر رفع مرفق المهمة: $($tkAtt.S)" }

  Expect "   🔐 وسجلُّ التدقيق **باقٍ** (شاهدٌ لا يُمحى)" ((SqlCount "SELECT COUNT(*) FROM AuditLogs WHERE CompanyId=$cC") -gt 0) 'True'
  Expect "   والموظف نفسه باقٍ (كيانٌ عابرٌ للشركات)" (SqlCount "SELECT COUNT(*) FROM Employees WHERE EmployeeId=$($e2.employeeId)") 1
}

# ✅ وسلامة الشركتين الأخريين بعد الحذف.
Expect "✅ الشركة A سليمة بعد الحذف" (Api GET "/companies/$cA" $null $admin $null).S 200
Expect "✅ وموظفها ما زال يُقرأ" (Api GET "/employees/$empId" $null $admin $cA).S 200

Write-Host "`n=== النتيجة ===" -ForegroundColor Cyan
Write-Host "نجح: $pass" -ForegroundColor Green
Write-Host "فشل: $fail" -ForegroundColor $(if($fail -eq 0){'Green'}else{'Red'})
if($fail -gt 0){ exit 1 }
