param([string]$AdminPwd='Speed3ds', [string]$Base='http://localhost:5080/api', [int]$Year=2026, [int]$Month=0)
$ErrorActionPreference='Stop'; $pass=0; $fail=0
function Ok($m){ $script:pass++; Write-Host "  [نجح] $m" -ForegroundColor Green }
function Bad($m){ $script:fail++; Write-Host "  [فشل] $m" -ForegroundColor Red }
function Api($m,$u,$b,$t,$c){ $h=@{}; if($t){$h.Authorization="Bearer $t"}; if($c){$h."X-Company-Id"="$c"}
  $p=@{Uri="$Base$u";Method=$m;Headers=$h;ContentType="application/json; charset=utf-8"}
  if($null -ne $b){$p.Body=[Text.Encoding]::UTF8.GetBytes(($b|ConvertTo-Json -Depth 8 -Compress))}
  try{$r=Invoke-WebRequest @p -UseBasicParsing; $j=$null; if($r.Content){try{$j=$r.Content|ConvertFrom-Json}catch{}}; return @{S=[int]$r.StatusCode;B=$j}}
  catch{$resp=$_.Exception.Response; $code=if($resp){[int]$resp.StatusCode}else{0}; $ct=''; if($resp){$sr=[IO.StreamReader]::new($resp.GetResponseStream());$ct=$sr.ReadToEnd()}; $j=$null; if($ct){try{$j=$ct|ConvertFrom-Json}catch{}}; return @{S=$code;B=$j}}
}

# ⚠️ **المطابقة بالمعرّفات الرقمية لا بالأسماء العربية.** PowerShell 5.1 يشوّه العربية العائدة
#    من الـAPI، فمطابقةُ سطرٍ بـ`$_.name -eq 'سنان'` تفشل **صامتةً** وتوهم أن الكتابة لم تُحفظ.
#    (وقع فعلاً أثناء بناء الوحدة وأضاع وقتاً في تشخيص عيبٍ غير موجود.)

Write-Host "=== إعداد: شركة + موظفان (دينار/دولار) ===" -ForegroundColor Cyan
$admin=(Api POST "/auth/login" @{username='admin';password=$AdminPwd} $null $null).B.accessToken
if(-not $admin){ Bad "تعذّر دخول admin"; exit 1 }
$cid=(Api GET "/companies" $null $admin $null).B[0].companyId
Ok "الشركة الفعّالة: $cid"

# ── اختيار شهرٍ يملكه هذا التشغيل ──
# ⚠️ السكربت **يُسدّد** في آخره، والتسديد لا رجعة فيه: الكشف المُسدَّد يرفض الحذف (409)
#    بحكم التصميم. فلو ثبّتنا الشهر لصار التشغيل الثاني يصطدم بكشفٍ مقفل ويفشل بتسعة
#    تحقّقات **بلا عيبٍ في المنتج** (حدث فعلاً في أول تشغيل). لذلك نختار أول شهرٍ غير
#    مُسدَّد ونحذف مسودّته إن وُجدت.
if($Month -eq 0){
  $months=@(Api GET "/payroll/years/$Year/months" $null $admin $cid).B
  $free=$months | Where-Object { $_.status -ne 'Paid' } | Select-Object -First 1
  if(-not $free){ Bad "كل أشهر $Year مُسدَّدة — شغّل بـ -Year أخرى"; exit 1 }
  $Month=[int]$free.month
}
$null=Api DELETE "/payroll/periods/$Year/$Month" $null $admin $cid
Ok "شهر الاختبار: $Month/$Year"

# موظفان بمعرّفَي هوية ثابتين — يُعاد استعمالهما عند إعادة التشغيل.
function GetOrMakeEmployee($nid,$name,$nameEn,$pos,$cur,$salary,$order,$hire,$lang){
  $found=(Api GET "/employees/lookup?nationalId=$nid" $null $admin $cid).B
  $emp=@{position=$pos;positionEn='Staff';hireDate=$hire;salaryCurrency=$cur;baseSalary=$salary;displayOrder=$order;isActive=$true}
  if($found){ $null=Api PUT "/employees/$($found.employeeId)/employment" $emp $admin $cid; return $found.employeeId }
  $body=@{profile=@{fullName=$name;fullNameEn=$nameEn;nationalId=$nid;phone=$null;address=$null;notes=$null;receiptLanguage=$lang};employment=$emp}
  return (Api POST "/employees" $body $admin $cid).B.employeeId
}
$e1=GetOrMakeEmployee '19900101' 'سنان الجبوري' 'Sinan' 'مهندس' 'IQD' 1200000 1 '2020-01-01T00:00:00' 'Arabic'
$e2=GetOrMakeEmployee '19950505' 'جون سميث' 'John Smith' 'سائق' 'USD' 700 2 "$Year-$($Month.ToString('00'))-16T00:00:00" 'English'
if($e1 -and $e2){ Ok "موظفان: دينار=$e1 · دولار(عُيِّن منتصف الشهر)=$e2" } else { Bad "تعذّر إنشاء الموظفين"; exit 1 }

Write-Host "`n=== التوليد والتناسب الجزئي ===" -ForegroundColor Cyan
$g=(Api POST "/payroll/periods/$Year/$Month" $null $admin $cid).B
if($g.added -ge 2){ Ok "تولّد الكشف: أُضيف $($g.added)" } else { Bad "التوليد أضاف $($g.added) بدل 2+" }

$p=(Api GET "/payroll/periods/$Year/$Month" $null $admin $cid).B
if($p.entries.Count -ge 2){ Ok "الكشف فيه $($p.entries.Count) سطراً" } else { Bad "عدد السطور $($p.entries.Count)" }

# سطر الدينار: شهر كامل ⇒ 30 يوماً وصافٍ = الأساسي
$rIqd=$p.entries | Where-Object { $_.currency -eq 'IQD' } | Select-Object -First 1
if($rIqd.eligibleDays -eq 30){ Ok "الموظف المستقرّ: 30 يوماً مستحقّاً" } else { Bad "أيام المستقرّ $($rIqd.eligibleDays) بدل 30" }
if([math]::Abs($rIqd.netSalary - 1200000) -lt 0.01){ Ok "صافي المستقرّ = 1,200,000" } else { Bad "صافي المستقرّ $($rIqd.netSalary)" }

# سطر الدولار: عُيِّن يوم 16 ⇒ من 16 إلى آخر الشهر، بسقف أيام العمل.
# ⚠️ **التوقّع يُحسب من القاعدة لا يُكتب رقماً ثابتاً**: السكربت يختار شهراً مختلفاً كل تشغيل،
#    و«16 يوماً» صحيحةٌ في شهرٍ من 31 وخاطئةٌ في شباط (13). رقمٌ ثابت كان سيجعل الاختبار
#    يفشل بحسب الشهر لا بحسب صحة الكود — وهو أسوأ من ألّا يوجد اختبار.
$daysInMonth=[DateTime]::DaysInMonth($Year,$Month)
$expDays=[math]::Min($daysInMonth-15, 30)
$expNet=[math]::Round(700 * $expDays / 30, 2)
$rUsd=$p.entries | Where-Object { $_.currency -eq 'USD' } | Select-Object -First 1
if($rUsd.eligibleDays -eq $expDays){ Ok "التعيين منتصف الشهر: $expDays يوماً من $daysInMonth ✔ التناسب الجزئي" } else { Bad "أيام الجديد $($rUsd.eligibleDays) بدل $expDays" }
if([math]::Abs($rUsd.netSalary - $expNet) -lt 0.02){ Ok "صافي الجديد = $expNet دولار (700 × $expDays/30)" } else { Bad "صافي الجديد $($rUsd.netSalary) بدل $expNet" }
if($rUsd.isNewHire){ Ok "الموظف الجديد مُعلَّم isNewHire" } else { Bad "isNewHire غير مضبوط" }

Write-Host "`n=== نقص سعر الصرف: لا يمنع التوليد ويمنع التسديد ===" -ForegroundColor Cyan
# ⚠️ الرمي وقت التوليد كان يُنتج قفلاً مغلقاً: لا إنشاء للشهر بلا سعر ولا وضع للسعر بلا شهر.
if($null -eq $p.exchangeRate -or $p.exchangeRate -le 0){
  if([math]::Abs($rUsd.netSalaryIqd) -lt 0.01){ Ok "بلا سعر صرف: الصافي بالدولار صحيح والمعادل صفرٌ مؤقّت" } else { Bad "المعادل $($rUsd.netSalaryIqd) رغم غياب السعر" }
  $payNoRate=Api POST "/payroll/periods/$Year/$Month/pay" @{rowVersion=$p.rowVersion;paidAt="$Year-08-01T00:00:00";outgoingBookId=$null;manualBookNumber=$null;notes=$null} $admin $cid
  if($payNoRate.S -eq 400){ Ok "التسديد مرفوض بلا سعر صرف (400) ✔ الحارس في مكانه" } else { Bad "التسديد بلا سعر ردّ $($payNoRate.S) بدل 400" }
} else { Ok "سعر الصرف مُعبّأ مسبقاً من الجدول المركزي: $($p.exchangeRate)" }

# ضبط السعر ⇒ إعادة حساب الكشف كله
$p2=(Api PUT "/payroll/periods/$Year/$Month" @{rowVersion=$p.rowVersion;exchangeRate=1310;workingDaysMode='Fixed';workingDays=30;notes=$null} $admin $cid).B
$rUsd2=$p2.entries | Where-Object { $_.currency -eq 'USD' } | Select-Object -First 1
$expIqd=[math]::Round($expNet * 1310, 2)
if([math]::Abs($rUsd2.netSalaryIqd - $expIqd) -lt 1){ Ok "بعد السعر: $expNet × 1310 = $($rUsd2.netSalaryIqd) د.ع" } else { Bad "المعادل $($rUsd2.netSalaryIqd) بدل $expIqd" }

Write-Host "`n=== التحرير وإعادة الحساب على الخادم ===" -ForegroundColor Cyan
$rIqd2=$p2.entries | Where-Object { $_.entryId -eq $rIqd.entryId } | Select-Object -First 1
$rows=@(@{entryId=$rIqd2.entryId;absenceDays=2;bonusAmount=100000;deductionAmount=$null;manualAbsenceDeduction=$null;eligibleDaysOverride=$null;notes='اختبار'})
$p3=(Api PUT "/payroll/periods/$Year/$Month/entries" @{rowVersion=$p2.rowVersion;entries=$rows} $admin $cid).B
$edited=$p3.entries | Where-Object { $_.entryId -eq $rIqd2.entryId } | Select-Object -First 1
if([math]::Abs($edited.absenceDeduction - 80000) -lt 0.01){ Ok "خصم الغياب محسوب: 1.2م × 2/30 = 80,000" } else { Bad "خصم الغياب $($edited.absenceDeduction) بدل 80,000" }
if([math]::Abs($edited.netSalary - 1220000) -lt 0.01){ Ok "الصافي = 1.2م + 100ك − 80ك = 1,220,000 ✔ الخادم يحسب" } else { Bad "الصافي $($edited.netSalary) بدل 1,220,000" }

Write-Host "`n=== التزامن المتفائل ===" -ForegroundColor Cyan
# نسخة قديمة (rowVersion الأول) يجب أن تُرفض — وإلا محا مستخدمٌ عملَ آخر صامتاً.
$stale=Api PUT "/payroll/periods/$Year/$Month/entries" @{rowVersion=$p2.rowVersion;entries=$rows} $admin $cid
if($stale.S -eq 409){ Ok "الحفظ بنسخة قديمة مرفوض (409) ✔ لا كتابة فوق عمل الآخرين" } else { Bad "الحفظ بنسخة قديمة ردّ $($stale.S) بدل 409" }

Write-Host "`n=== التوليد التراكمي يصون المدخلات اليدوية ===" -ForegroundColor Cyan
$g2=(Api POST "/payroll/periods/$Year/$Month" $null $admin $cid).B
$p4=(Api GET "/payroll/periods/$Year/$Month" $null $admin $cid).B
$still=$p4.entries | Where-Object { $_.entryId -eq $rIqd2.entryId } | Select-Object -First 1
if($g2.added -eq 0 -and $g2.existing -ge 2){ Ok "إعادة التوليد: أُضيف 0 · موجود $($g2.existing)" } else { Bad "إعادة التوليد أضافت $($g2.added)" }
if([math]::Abs($still.bonusAmount - 100000) -lt 0.01){ Ok "المكافأة اليدوية **باقية** بعد إعادة التوليد ✔ لا يمحو عمل ساعة بضغطة" } else { Bad "المكافأة صارت $($still.bonusAmount) — التوليد محا المدخلات" }

Write-Host "`n=== المخرجات ===" -ForegroundColor Cyan
function FileOk($kind,$label){
  $h=@{Authorization="Bearer $admin";"X-Company-Id"="$cid"}
  try{ $r=Invoke-WebRequest -Uri "$Base/payroll/periods/$Year/$Month/$kind" -Headers $h -UseBasicParsing
       $len=[int]$r.RawContentLength; if($len -le 0){ $len=$r.Content.Length }
       if($len -gt 500){ Ok "$label ($len بايت)" } else { Bad "$label صغير جداً ($len بايت)" } }
  catch{ Bad "$label فشل: $($_.Exception.Message)" }
}
FileOk 'excel' 'تصدير Excel'
FileOk 'pdf' 'كشف PDF'
FileOk 'receipts' 'إيصالات الاستلام PDF'

Write-Host "`n=== التسديد والقفل ===" -ForegroundColor Cyan
$payRes=Api POST "/payroll/periods/$Year/$Month/pay" @{rowVersion=$p4.rowVersion;paidAt="$Year-08-01T00:00:00";outgoingBookId=$null;manualBookNumber="صرف/$Year/$Month";notes=$null} $admin $cid
if($payRes.S -eq 204){ Ok "تمّ التسديد" } else { Bad "التسديد ردّ $($payRes.S)" }

$p5=(Api GET "/payroll/periods/$Year/$Month" $null $admin $cid).B
if($p5.status -eq 'Paid'){ Ok "حالة الكشف: مُسدَّد" } else { Bad "الحالة $($p5.status)" }
$allPaid=@($p5.entries | Where-Object { $_.paymentStatus -ne 'PaidByThisCompany' }).Count
if($allPaid -eq 0){ Ok "كل السطور صارت «مصروف من هذه الشركة»" } else { Bad "$allPaid سطراً لم يُعلَّم مصروفاً" }

$editPaid=Api PUT "/payroll/periods/$Year/$Month/entries" @{rowVersion=$p5.rowVersion;entries=@()} $admin $cid
if($editPaid.S -eq 409){ Ok "التعديل بعد التسديد مرفوض (409)" } else { Bad "التعديل بعد التسديد ردّ $($editPaid.S)" }
$delPaid=Api DELETE "/payroll/periods/$Year/$Month" $null $admin $cid
if($delPaid.S -eq 409){ Ok "الحذف بعد التسديد مرفوض (409)" } else { Bad "الحذف بعد التسديد ردّ $($delPaid.S)" }

$delEmp=Api DELETE "/employees/$e1" $null $admin $cid
if($delEmp.S -eq 409){ Ok "حذف موظف له رواتب مُسدَّدة مرفوض (409) ✔ السجل المالي محميّ" } else { Bad "حذف الموظف ردّ $($delEmp.S) بدل 409" }

Write-Host "`n=== 🔐 العزل: الموظف العادي محجوب كلياً ===" -ForegroundColor Cyan
# نطلب له **كل** الأقسام بما فيها HR صراحةً — والباك-إند يجب أن يجرّدها منه.
$empUser='emp_hr'
$ex=(Api GET "/users" $null $admin $cid).B | Where-Object { $_.username -eq $empUser } | Select-Object -First 1
$ubody=@{fullName='موظف اختبار الرواتب';role='Employee';isActive=$true;companies=@(
  @{companyId=$cid;modules=@('Outgoing','Incoming','Archive','Reports','Users','Settings','Backup','HR');departmentId=$null;canApprove=$false;canManageIncoming=$false;canViewAllIncoming=$false;canManageHR=$true})}
if($ex){ $null=Api PUT "/users/$($ex.userId)" $ubody $admin $cid; $created=$ex }
else { $ubody.username=$empUser; $ubody.password='Emp@12345'; $created=(Api POST "/users" $ubody $admin $cid).B }

$granted=(Api GET "/users" $null $admin $cid).B | Where-Object { $_.username -eq $empUser } | Select-Object -First 1
if($granted.companies[0].modules -notcontains 'HR'){ Ok "HR **جُرِّدت** من الموظف رغم طلبها صراحةً ✔ الحارس في الخدمة لا في الواجهة" } else { Bad "تسرّب: الموظف احتفظ بقسم HR" }

function EmpLogin($user){
  $r=Api POST "/auth/login" @{username=$user;password='Emp@12345new'} $null $null
  if($r.S -ne 200){ $r=Api POST "/auth/login" @{username=$user;password='Emp@12345'} $null $null }
  if($r.B.mustChangePassword){ $tok=$r.B.accessToken
    $null=Api POST "/auth/change-password" @{currentPassword='Emp@12345';newPassword='Emp@12345new'} $tok $null
    $r=Api POST "/auth/login" @{username=$user;password='Emp@12345new'} $null $null }
  return $r.B.accessToken
}
$tokEmp=EmpLogin $empUser
if($tokEmp){ Ok "دخول الموظف" } else { Bad "فشل دخول الموظف" }

foreach($ep in @("/employees","/payroll/years","/payroll/periods/$Year/$Month","/hr/settings","/hr/summary","/payroll/periods/$Year/$Month/excel")){
  $r=Api GET $ep $null $tokEmp $cid
  if($r.S -eq 403){ Ok "الموظف محجوب عن $ep (403)" } else { Bad "تسرّب: $ep ردّ $($r.S) للموظف" }
}
$rw=Api POST "/employees" @{profile=@{fullName='مخترق';receiptLanguage='Arabic'};employment=@{position='x';hireDate='2026-01-01T00:00:00';salaryCurrency='IQD';baseSalary=1;displayOrder=0;isActive=$true}} $tokEmp $cid
if($rw.S -eq 403){ Ok "الموظف محجوب عن **إنشاء** موظف (403)" } else { Bad "تسرّب: إنشاء موظف ردّ $($rw.S)" }

Write-Host "`n=== النتيجة ===" -ForegroundColor Cyan
Write-Host "نجح: $pass" -ForegroundColor Green
Write-Host "فشل: $fail" -ForegroundColor $(if($fail -eq 0){'Green'}else{'Red'})
if($fail -gt 0){ exit 1 }
