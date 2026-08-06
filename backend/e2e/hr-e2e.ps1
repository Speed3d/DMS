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

Write-Host "`n=== عقد «لا يوجد كشف بعد» ===" -ForegroundColor Cyan
# ⚠️ `Ok(null)` يُنتج **204 بجسمٍ فارغ** لا 200 بـ`null`، فيسلّمه Dio نصّاً فارغاً `''`.
#    بلاغ المالك 2026-08-04: سقطت شاشة الكشف بـTypeError **قبل ظهور زرّ التوليد**، فبدا
#    أول شهر يُفتح في نظامٍ جديد معطوباً. الحارس في العميل: `jsonObjectOrNull`.
$hRaw=@{Authorization="Bearer $admin";"X-Company-Id"="$cid"}
$empty=Invoke-WebRequest -Uri "$Base/payroll/periods/$Year/$Month" -Headers $hRaw -UseBasicParsing
if($empty.StatusCode -eq 204){ Ok "الشهر غير المنشأ يردّ 204 بجسم فارغ (عقدٌ يجب أن يحتمله العميل)" }
else { Bad "ردّ $($empty.StatusCode) بدل 204" }
$lookupNone=Invoke-WebRequest -Uri "$Base/employees/lookup?nationalId=00000000" -Headers $hRaw -UseBasicParsing
if($lookupNone.StatusCode -eq 204){ Ok "البحث بهوية غير موجودة يردّ 204 كذلك" }
else { Bad "البحث ردّ $($lookupNone.StatusCode) بدل 204" }

Write-Host "`n=== التوليد والتناسب الجزئي ===" -ForegroundColor Cyan
$g=(Api POST "/payroll/periods/$Year/$Month" $null $admin $cid).B
if($g.added -ge 2){ Ok "تولّد الكشف: أُضيف $($g.added)" } else { Bad "التوليد أضاف $($g.added) بدل 2+" }

$p=(Api GET "/payroll/periods/$Year/$Month" $null $admin $cid).B
if($p.entries.Count -ge 2){ Ok "الكشف فيه $($p.entries.Count) سطراً" } else { Bad "عدد السطور $($p.entries.Count)" }

# سطر الدينار: شهر كامل ⇒ **كل أيام العمل** وصافٍ = الأساسي.
# ⚠️ يُقارَن بـ`workingDays` لا بالرقم 30: هذا هو الثابت الحقيقي — «المستقرّ يأخذ الشهر كاملاً
#    مهما كان طول الشهر التقويمي». والمقارنة بـ30 كانت ستكشف عيب شباط **لو وقع السكربت عليه**،
#    لكنه يختار أول شهر غير مُسدَّد فوقع على 3 و4 و5 و7 ولم يزره قطّ (بلاغ المالك 2026-08-05).
$rIqd=$p.entries | Where-Object { $_.currency -eq 'IQD' } | Select-Object -First 1
if($rIqd.eligibleDays -eq $p.workingDays){ Ok "الموظف المستقرّ: $($p.workingDays) يوماً مستحقّاً (الشهر التقويمي $([DateTime]::DaysInMonth($Year,$Month)))" } else { Bad "أيام المستقرّ $($rIqd.eligibleDays) بدل $($p.workingDays)" }
if([math]::Abs($rIqd.netSalary - 1200000) -lt 0.01){ Ok "صافي المستقرّ = 1,200,000" } else { Bad "صافي المستقرّ $($rIqd.netSalary)" }

# سطر الدولار: عُيِّن اليوم 16 ⇒ من اليوم 16 إلى آخر يوم عمل في المدى.
# ⚠️ **التوقّع يُحسب من القاعدة لا يُكتب رقماً ثابتاً** — السكربت يختار شهراً مختلفاً كل تشغيل.
#    والقاعدة **عرف 30/360** (2026-08-05): الشهر مدى مرقّم 1..workingDays، فالاستحقاق
#    `workingDays - 16 + 1` **في كل شهر**، ولا يتبع طول الشهر التقويمي.
#    ⚠️ وكان يُحسب هنا من `daysInMonth` فيعطي 16 في شهرٍ من 31 و13 في شباط — وهو **العدّ**
#    الذي أنتج عيب شباط نفسه (بلاغ المالك). التوقّع يتبع القاعدة الجديدة الآن.
$daysInMonth=[DateTime]::DaysInMonth($Year,$Month)
$wd=$p.workingDays
$expDays=$wd - 16 + 1
$expNet=[math]::Round(700 * $expDays / $wd, 2)
$rUsd=$p.entries | Where-Object { $_.currency -eq 'USD' } | Select-Object -First 1
if($rUsd.eligibleDays -eq $expDays){ Ok "التعيين منتصف الشهر: $expDays يوماً من $wd (الشهر التقويمي $daysInMonth) ✔ التناسب الجزئي" } else { Bad "أيام الجديد $($rUsd.eligibleDays) بدل $expDays" }
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

Write-Host "`n=== الأيام المستحقّة تتبع أيام العمل ولا تتجمّد ===" -ForegroundColor Cyan
# 🔴 **حارسٌ وُلد من بلاغ المالك (2026-08-05).** كان `Recompute` يستنتج «يدويّ» من
#    `EligibleDays > 0`، وهو صادقٌ على **كل** سطرٍ حُسِب مرّةً — فتتجمّد الأيام عند أول قيمة
#    ويُعاد حساب الصافي بمقامٍ جديد وبَسطٍ قديم (شباط: 28 مجمّدة ÷ 30 ⇒ 28/30 من الراتب).
#    ⚠️ **اختبارات الوحدة لا تكشفه** لأنها تنادي `PayrollCalculator` مباشرةً ولا تمرّ من الخدمة.
#    الفحص: نُنزل أيام العمل إلى 26 ثم نعيدها إلى 30، ويجب أن يتبعها المستقرّ في الاتجاهين.
$pA=(Api PUT "/payroll/periods/$Year/$Month" @{rowVersion=$p2.rowVersion;exchangeRate=1310;workingDaysMode='Fixed';workingDays=26;notes=$null} $admin $cid).B
$sA=$pA.entries | Where-Object { $_.entryId -eq $rIqd.entryId } | Select-Object -First 1
if($sA.eligibleDays -eq 26){ Ok "خفض أيام العمل إلى 26 ⇒ المستقرّ 26 يوماً" } else { Bad "الأيام $($sA.eligibleDays) بدل 26 — الأيام متجمّدة" }
if([math]::Abs($sA.netSalary - 1200000) -lt 0.01){ Ok "وصافيه كامل (26/26) لا منقوصاً" } else { Bad "الصافي $($sA.netSalary) بدل 1,200,000" }

$pB=(Api PUT "/payroll/periods/$Year/$Month" @{rowVersion=$pA.rowVersion;exchangeRate=1310;workingDaysMode='Fixed';workingDays=30;notes=$null} $admin $cid).B
$sB=$pB.entries | Where-Object { $_.entryId -eq $rIqd.entryId } | Select-Object -First 1
if($sB.eligibleDays -eq 30){ Ok "رفعها إلى 30 ⇒ المستقرّ 30 يوماً (لا تتجمّد في الاتجاه الآخر)" } else { Bad "الأيام $($sB.eligibleDays) بدل 30 — تجمّدت عند 26" }
if([math]::Abs($sB.netSalary - 1200000) -lt 0.01){ Ok "وصافيه كامل بعد العودة" } else { Bad "الصافي $($sB.netSalary) بدل 1,200,000" }
if(-not $sB.eligibleDaysIsManual){ Ok "eligibleDaysIsManual=false ⇒ الأيام محسوبة لا مثبّتة" } else { Bad "الأيام مُعلَّمة يدوية بلا أن يطلبها أحد" }
$p2=$pB

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

Write-Host "`n=== الإجازات وسجلّ التغييرات (الدفعة ٢) ===" -ForegroundColor Cyan
# ⚠️ **تنظيف إجازات الموظف أولاً.** حارس التداخل (409) يجعل السكربت رهينةَ ما تركه غيره:
#    إجازةٌ سابقة على الأيام نفسها تُفشل ثلاثة تحقّقات **بلا عيبٍ في المنتج** (وقع فعلاً حين
#    أُنشئت إجازة يدوياً لالتقاط عيّنات الاختبار). السكربت يملك بياناته أو لا يُوثَق به.
foreach($old in @(Api GET "/employees/$e1/leaves" $null $admin $cid).B){
  $null=Api DELETE "/employees/leaves/$($old.leaveId)" $null $admin $cid
}

# إجازة بلا موافقة ⇒ تُسجَّل مقبولةً مباشرةً (حالة معلّقة بلا مراجعٍ تبقى معلّقة للأبد).
$lv1=(Api POST "/employees/$e1/leaves" @{leaveType='Annual';fromDate="$Year-$($Month.ToString('00'))-05T00:00:00";toDate="$Year-$($Month.ToString('00'))-07T00:00:00";requiresApproval=$false;deductFromSalary=$false;notes='اختبار'} $admin $cid).B
if($lv1.durationDays -eq 3){ Ok "الإجازة 3 أيام (الطرفان محسوبان)" } else { Bad "المدّة $($lv1.durationDays) بدل 3" }
if($lv1.status -eq 'Approved'){ Ok "إجازة بلا موافقة تُسجَّل مقبولةً مباشرةً" } else { Bad "الحالة $($lv1.status)" }

# تداخل مع إجازة قائمة ⇒ رفض
$dup=Api POST "/employees/$e1/leaves" @{leaveType='Sick';fromDate="$Year-$($Month.ToString('00'))-06T00:00:00";toDate="$Year-$($Month.ToString('00'))-08T00:00:00";requiresApproval=$false;deductFromSalary=$false;notes=$null} $admin $cid
if($dup.S -eq 409){ Ok "الإجازة المتداخلة مرفوضة (409)" } else { Bad "التداخل ردّ $($dup.S) بدل 409" }

# إجازة بموافقة ⇒ معلّقة ثم تُراجَع مرّةً واحدة
$lv2=(Api POST "/employees/$e1/leaves" @{leaveType='Administrative';fromDate="$Year-$($Month.ToString('00'))-20T00:00:00";toDate="$Year-$($Month.ToString('00'))-21T00:00:00";requiresApproval=$true;deductFromSalary=$true;notes=$null} $admin $cid).B
if($lv2.status -eq 'Pending'){ Ok "إجازة بموافقة تبدأ معلّقة" } else { Bad "الحالة $($lv2.status)" }

# قائمة «مَن ينتظر» (بلاغ المالك ٨) — البطاقة كانت تعرض العدد وتنقل بلا دلالةٍ على صاحب الطلب.
$pend=@(Api GET "/hr/leaves/pending" $null $admin $cid).B
$mine=$pend | Where-Object { $_.leaveId -eq $lv2.leaveId } | Select-Object -First 1
if($mine){ Ok "الإجازة المعلّقة تظهر في /hr/leaves/pending" } else { Bad "الإجازة المعلّقة غائبة عن القائمة" }
# ⚠️ المطابقة بالمعرّف لا بالاسم العربي (PS 5.1 يشوّهه فتفشل المطابقة صامتةً).
if($mine.employeeId -eq $e1){ Ok "القائمة تحمل معرّف صاحبها فيمكن فتح ملفّه" } else { Bad "employeeId $($mine.employeeId) بدل $e1" }
if($mine.durationDays -eq 2){ Ok "مدّة الإجازة المعلّقة صحيحة (يومان)" } else { Bad "المدّة $($mine.durationDays) بدل 2" }
if(-not [string]::IsNullOrWhiteSpace($mine.leaveTypeLabel)){ Ok "التسمية العربية جاهزة من الخادم" } else { Bad "leaveTypeLabel فارغة" }

$rev=(Api PATCH "/employees/leaves/$($lv2.leaveId)" @{approve=$true;notes='موافق'} $admin $cid).B
if($rev.status -eq 'Approved'){ Ok "الموافقة على الإجازة" } else { Bad "المراجعة ردّت $($rev.status)" }
$rev2=Api PATCH "/employees/leaves/$($lv2.leaveId)" @{approve=$false;notes=$null} $admin $cid
if($rev2.S -eq 409){ Ok "إعادة مراجعة إجازة محسومة مرفوضة (409)" } else { Bad "إعادة المراجعة ردّت $($rev2.S)" }

# وبعد البتّ تخرج من قائمة المنتظِرين — وإلا بقيت البطاقة تُنادي على عملٍ منجَز.
$pend2=@(Api GET "/hr/leaves/pending" $null $admin $cid).B
if(-not ($pend2 | Where-Object { $_.leaveId -eq $lv2.leaveId })){ Ok "الإجازة المبتوتة تخرج من قائمة الانتظار" } else { Bad "الإجازة المبتوتة ما زالت معلّقة في القائمة" }

Write-Host "`n=== مستمسكات الموظف (بلاغ المالك ٧) ===" -ForegroundColor Cyan
# ⚠️ `OwnerType.Employee` وحارسُه كانا جاهزَين منذ الدفعة ١ **بلا نقطتَي رفعٍ وقائمة** —
#    رابع تكرارٍ لنمط «ميزة بلا مدخل». الحارس هنا يمنع موتها صامتةً مرّةً أخرى.
$docBytes=[Text.Encoding]::UTF8.GetBytes('%PDF-1.4 test')
$docPath=Join-Path $env:TEMP 'dms-e2e-doc.pdf'
[IO.File]::WriteAllBytes($docPath,$docBytes)
$fBoundary=[Guid]::NewGuid().ToString()
$fBody=[Text.Encoding]::UTF8.GetBytes(
  "--$fBoundary`r`nContent-Disposition: form-data; name=`"file`"; filename=`"عقد العمل.pdf`"`r`nContent-Type: application/pdf`r`n`r`n" +
  [Text.Encoding]::UTF8.GetString($docBytes) + "`r`n--$fBoundary--`r`n")
try{
  $up=Invoke-WebRequest -Uri "$Base/employees/$e1/attachments" -Method Post -Headers @{Authorization="Bearer $admin";'X-Company-Id'="$cid"} -ContentType "multipart/form-data; boundary=$fBoundary" -Body $fBody -UseBasicParsing
  $upJson=$up.Content|ConvertFrom-Json
  Ok "رُفع مستمسك ($($upJson.fileSize) بايت)"
}catch{ Bad "رفع المستمسك فشل: $($_.Exception.Message)"; $upJson=$null }
$docs=@(Api GET "/employees/$e1/attachments" $null $admin $cid).B
if($docs.Count -ge 1){ Ok "قائمة المستمسكات فيها $($docs.Count)" } else { Bad "القائمة فارغة بعد الرفع" }
if($upJson -and $upJson.attachmentId){
  $dl=Api GET "/employees/$e1/attachments/$($upJson.attachmentId)/download?inline=true" $null $admin $cid
  if($dl.S -eq 200){ Ok "تنزيل/عرض المستمسك يعمل (200)" } else { Bad "التنزيل ردّ $($dl.S)" }
  $del=Api DELETE "/attachments/$($upJson.attachmentId)" $null $admin $cid
  if($del.S -eq 204){ Ok "حذف المستمسك (204)" } else { Bad "الحذف ردّ $($del.S)" }
}

# سجلّ التغييرات: يُكتب تلقائياً عند تغيير الراتب
$null=Api PUT "/employees/$e1/employment" @{position='مهندس أول';positionEn='Senior';hireDate='2020-01-01T00:00:00';salaryCurrency='IQD';baseSalary=1350000;displayOrder=1;isActive=$true} $admin $cid
$log=@(Api GET "/employees/$e1/log" $null $admin $cid).B
if($log.Count -ge 2){ Ok "سجلّ التغييرات فيه $($log.Count) سطراً" } else { Bad "السجلّ فيه $($log.Count) سطراً" }
$hasSalary=@($log | Where-Object { $_.changeType -eq 'SalaryChange' }).Count
$hasPosition=@($log | Where-Object { $_.changeType -eq 'PositionChange' }).Count
if($hasSalary -ge 1){ Ok "تغيّر الراتب مسجَّل" } else { Bad "تغيّر الراتب غير مسجَّل" }
if($hasPosition -ge 1){ Ok "تغيّر الصفة مسجَّل" } else { Bad "تغيّر الصفة غير مسجَّل" }
$hasLeave=@($log | Where-Object { $_.changeType -eq 'LeaveRecorded' }).Count
if($hasLeave -ge 1){ Ok "الإجازات مسجَّلة في السجلّ" } else { Bad "الإجازات غير مسجَّلة" }

# أعِد الراتب لقيمته كي تبقى بقية التحقّقات على أرقامها
$null=Api PUT "/employees/$e1/employment" @{position='مهندس';positionEn='Engineer';hireDate='2020-01-01T00:00:00';salaryCurrency='IQD';baseSalary=1200000;displayOrder=1;isActive=$true} $admin $cid

Write-Host "`n=== مكافأة نهاية الخدمة ===" -ForegroundColor Cyan
$eosOff=@(Api GET "/payroll/periods/$Year/$Month/end-of-service" $null $admin $cid).B
if($eosOff.Count -eq 0){ Ok "مطفأة افتراضياً ⇒ لا اقتراحات" } else { Bad "اقترحت $($eosOff.Count) رغم أنها مطفأة" }
$null=Api PUT "/hr/settings" @{defaultWorkingDaysMode='Fixed';defaultWorkingDays=30;endOfServiceEnabled=$true;endOfServiceRatio='MonthPerYear';endOfServiceCustomDays=$null} $admin $cid
$st=(Api GET "/hr/settings" $null $admin $cid).B
if($st.endOfServiceEnabled){ Ok "فُعّلت مكافأة نهاية الخدمة (راتب شهر/سنة)" } else { Bad "لم تُفعَّل" }
$eosBad=Api PUT "/hr/settings" @{defaultWorkingDaysMode='Fixed';defaultWorkingDays=30;endOfServiceEnabled=$true;endOfServiceRatio='CustomDays';endOfServiceCustomDays=$null} $admin $cid
if($eosBad.S -eq 400){ Ok "«أيام مخصّصة» بلا عدد مرفوضة (400)" } else { Bad "ردّت $($eosBad.S) بدل 400" }
$null=Api PUT "/hr/settings" @{defaultWorkingDaysMode='Fixed';defaultWorkingDays=30;endOfServiceEnabled=$true;endOfServiceRatio='MonthPerYear';endOfServiceCustomDays=$null} $admin $cid

# مكافأة لمن لم تنتهِ خدمته ⇒ رفض
$pNow=(Api GET "/payroll/periods/$Year/$Month" $null $admin $cid).B
$anyRow=$pNow.entries | Select-Object -First 1
$eosWrong=Api PUT "/payroll/periods/$Year/$Month/entries" @{rowVersion=$pNow.rowVersion;entries=@(@{entryId=$anyRow.entryId;absenceDays=0;bonusAmount=$null;deductionAmount=$null;manualAbsenceDeduction=$null;eligibleDaysOverride=$null;notes=$null;endOfServiceAmount=500000})} $admin $cid
if($eosWrong.S -eq 400){ Ok "مكافأة نهاية خدمة لموظف مستمرّ مرفوضة (400) ✔ لا مكافأة بلا سبب" } else { Bad "ردّت $($eosWrong.S) بدل 400" }

Write-Host "`n=== ملخّص الوحدة ===" -ForegroundColor Cyan
$sum=(Api GET "/hr/summary" $null $admin $cid).B
if($sum.activeEmployees -ge 2){ Ok "الملخّص: $($sum.activeEmployees) موظفاً فعّالاً" } else { Bad "عدد الفعّالين $($sum.activeEmployees)" }
if($null -ne $sum.pendingLeaves){ Ok "الملخّص يحمل عدد الإجازات المعلّقة ($($sum.pendingLeaves))" } else { Bad "pendingLeaves غائب" }

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

Write-Host "`n=== 🔐 تعديل الشهر المُسدَّد بإصدارات (ADR-026) ===" -ForegroundColor Cyan
# 🔴 **جراحيّ لا إعادةَ فتح**: الشهر يبقى `Paid` طوال التعديل، وإلا تعطّل كشف «مدفوع من
#    شركة أخرى» (يشترط هذه الحالة) فانفتحت نافذةُ صرفٍ مزدوج.

$pAmend=(Api GET "/payroll/periods/$Year/$Month" $null $admin $cid).B
$oldRate=$pAmend.exchangeRate
$oldTotal=$pAmend.totalIqd

# ١) بلا سبب ⇒ 409 (وهو التحقّق أعلاه أصلاً) · ٢) بسببٍ قصير ⇒ 400
$shortReason=Api PUT "/payroll/periods/$Year/$Month" @{rowVersion=$pAmend.rowVersion;exchangeRate=1400;workingDaysMode='Fixed';workingDays=30;notes=$null;amendmentReason='خطأ'} $admin $cid
if($shortReason.S -eq 400){ Ok "سبب تعديلٍ قصير مرفوض (400)" } else { Bad "السبب القصير ردّ $($shortReason.S) بدل 400" }

# ٣) بسببٍ صحيح ⇒ 200، **والشهر يبقى مُسدَّداً**
$amended=Api PUT "/payroll/periods/$Year/$Month" @{rowVersion=$pAmend.rowVersion;exchangeRate=1400;workingDaysMode='Fixed';workingDays=30;notes=$null;amendmentReason='تصحيح سعر الصرف بعد التسديد — اختبار'} $admin $cid
if($amended.S -eq 200){ Ok "التعديل بسببٍ صحيح نجح (200)" } else { Bad "التعديل ردّ $($amended.S) بدل 200" }
if($amended.B.status -eq 'Paid'){ Ok "🔐 الشهر **بقي مُسدَّداً** أثناء التعديل ✔ لا نافذة صرفٍ مزدوج" } else { Bad "الحالة صارت $($amended.B.status)" }
if($amended.B.exchangeRate -eq 1400){ Ok "سعر الصرف تغيّر إلى 1400" } else { Bad "السعر $($amended.B.exchangeRate)" }
if($amended.B.totalIqd -ne $oldTotal){ Ok "الإجمالي أُعيد حسابه ($oldTotal ⇐ $($amended.B.totalIqd))" } else { Bad "الإجمالي لم يتغيّر" }
if($amended.B.amendmentCount -eq 1){ Ok "عدّاد التعديلات = 1" } else { Bad "العدّاد $($amended.B.amendmentCount)" }

# ٤) سجلّ الإصدارات يحفظ **ما كان** لا ما صار
# ⚠️ `@(Api ...).B` تُفكّك المصفوفة فتضيع `.Count` — التغليف يقع **حول `.B`** لا حولها.
$log=@((Api GET "/payroll/periods/$Year/$Month/amendments" $null $admin $cid).B)
if($log.Count -eq 1){ Ok "سجلّ التعديلات فيه إصدار واحد" } else { Bad "السجلّ فيه $($log.Count)" }
if($log[0].snapshotJson -match "`"ExchangeRate`":$oldRate"){ Ok "🔐 اللقطة تحفظ سعر الصرف **القديم** ($oldRate) ✔ الماضي محفوظ" } else { Bad "اللقطة لا تحمل السعر القديم" }
if(-not [string]::IsNullOrWhiteSpace($log[0].reason)){ Ok "السبب محفوظ في السجلّ" } else { Bad "السبب فارغ" }
if(-not [string]::IsNullOrWhiteSpace($log[0].changedBy)){ Ok "ومَن عدّل محفوظ" } else { Bad "المعدِّل فارغ" }

# ٥) كشف «مدفوع من شركة أخرى» **يبقى عاملاً** — السبب الذي اختير له الجراحيّ
$extAfter=Api GET "/payroll/periods/$Year/$Month/external-payments" $null $admin $cid
if($extAfter.S -eq 200){ Ok "🔐 كشف «مدفوع من شركة أخرى» يعمل بعد التعديل ✔ (ADR-024 سليمة)" } else { Bad "الكشف ردّ $($extAfter.S)" }

Write-Host "`n=== دورة إيصال الاستلام الموقَّع (بلاغ المالك ٦) ===" -ForegroundColor Cyan
$row=$amended.B.entries[0]
$rcBoundary=[Guid]::NewGuid().ToString()
$rcBytes=[Text.Encoding]::UTF8.GetBytes('%PDF-1.4 signed')
$rcBody=[Text.Encoding]::UTF8.GetBytes(
  "--$rcBoundary`r`nContent-Disposition: form-data; name=`"file`"; filename=`"ايصال موقع.pdf`"`r`nContent-Type: application/pdf`r`n`r`n" +
  [Text.Encoding]::UTF8.GetString($rcBytes) + "`r`n--$rcBoundary--`r`n")
try{
  $up=Invoke-WebRequest -Uri "$Base/payroll/entries/$($row.entryId)/receipts" -Method Post -Headers @{Authorization="Bearer $admin";'X-Company-Id'="$cid"} -ContentType "multipart/form-data; boundary=$rcBoundary" -Body $rcBody -UseBasicParsing
  Ok "رُفع الإيصال الموقَّع على شهرٍ **مُسدَّد** ✔ (وهو موضعه الطبيعي)"
}catch{ Bad "رفع الإيصال فشل: $($_.Exception.Message)" }

$pR=(Api GET "/payroll/periods/$Year/$Month" $null $admin $cid).B
$rowR=$pR.entries | Where-Object { $_.entryId -eq $row.entryId } | Select-Object -First 1
if($rowR.signedReceiptCount -ge 1){ Ok "عدّاد الإيصالات = $($rowR.signedReceiptCount)" } else { Bad "العدّاد صفر بعد الرفع" }
if(-not $rowR.receiptIsStale){ Ok "وليس متقادماً (رُفع بعد آخر تعديل)" } else { Bad "عُدّ متقادماً خطأً" }

# تعديلٌ ثانٍ ⇒ الإيصال يتقادم
Start-Sleep -Milliseconds 1200
$amend2=Api PUT "/payroll/periods/$Year/$Month" @{rowVersion=$pR.rowVersion;exchangeRate=1450;workingDaysMode='Fixed';workingDays=30;notes=$null;amendmentReason='تعديل ثانٍ لاختبار تقادم الإيصال'} $admin $cid
$pS=(Api GET "/payroll/periods/$Year/$Month" $null $admin $cid).B
$rowS=$pS.entries | Where-Object { $_.entryId -eq $row.entryId } | Select-Object -First 1
if($rowS.receiptIsStale){ Ok "🔐 بعد التعديل: الإيصال **متقادم** ✔ التنبيه يعمل" } else { Bad "الإيصال لم يُعدّ متقادماً" }

# «رفض» ⇒ يزول التنبيه
$ack=Api POST "/payroll/entries/$($row.entryId)/receipts/acknowledge" $null $admin $cid
if($ack.S -eq 204){ Ok "«رفض — لا يمسّه التعديل» قُبل (204)" } else { Bad "البتّ ردّ $($ack.S)" }
$pT=(Api GET "/payroll/periods/$Year/$Month" $null $admin $cid).B
$rowT=$pT.entries | Where-Object { $_.entryId -eq $row.entryId } | Select-Object -First 1
if(-not $rowT.receiptIsStale){ Ok "وزال التنبيه ✔ دورة كاملة" } else { Bad "التنبيه باقٍ بعد البتّ" }

$delEmp=Api DELETE "/employees/$e1" $null $admin $cid
if($delEmp.S -eq 409){ Ok "حذف موظف له رواتب مُسدَّدة مرفوض (409) ✔ السجل المالي محميّ" } else { Bad "حذف الموظف ردّ $($delEmp.S) بدل 409" }

Write-Host "`n=== 🔐 فصل الصلاحيات: قسمٌ لا يفتح الآخر (ADR-025) ===" -ForegroundColor Cyan
# 🔄 **تغيّر جوهريّ عن ADR-023:** كان الاختبار يُثبت أن الموظف **يُجرَّد** من الوحدة. الآن
#    الوحدة مفتوحة لكل دورٍ فوق القارئ، فالحارس انتقل إلى موضعين آخرين:
#      ١) **القارئ** يُجرَّد ويُحجب.
#      ٢) **قسمٌ واحد لا يمنح الآخر** — وهو جوهر الفصل.

function EmpLogin($user){
  $r=Api POST "/auth/login" @{username=$user;password='Emp@12345new'} $null $null
  if($r.S -ne 200){ $r=Api POST "/auth/login" @{username=$user;password='Emp@12345'} $null $null }
  if($r.B.mustChangePassword){ $tok=$r.B.accessToken
    $null=Api POST "/auth/change-password" @{currentPassword='Emp@12345';newPassword='Emp@12345new'} $tok $null
    $r=Api POST "/auth/login" @{username=$user;password='Emp@12345new'} $null $null }
  return $r.B.accessToken
}

function UpsertUser($username, $displayName, $role, $modules, $canEmp, $canPay){
  $ex=(Api GET "/users" $null $admin $cid).B | Where-Object { $_.username -eq $username } | Select-Object -First 1
  $body=@{fullName=$displayName;role=$role;isActive=$true;companies=@(
    @{companyId=$cid;modules=$modules;departmentId=$null;canApprove=$false;canManageIncoming=$false;
      canViewAllIncoming=$false;canManageEmployees=$canEmp;canManagePayroll=$canPay})}
  if($ex){ $null=Api PUT "/users/$($ex.userId)" $body $admin $cid }
  else { $body.username=$username; $body.password='Emp@12345'; $null=Api POST "/users" $body $admin $cid }
  return (Api GET "/users" $null $admin $cid).B | Where-Object { $_.username -eq $username } | Select-Object -First 1
}

# ── ١) القارئ يُجرَّد من القسمين ولو طُلبا صراحةً ──
$rdr=UpsertUser 'rdr_hr' 'قارئ اختبار الرواتب' 'Reader' @('Outgoing','Employees','Payroll') $true $true
$rdrMods=$rdr.companies[0].modules
if($rdrMods -notcontains 'Employees' -and $rdrMods -notcontains 'Payroll'){
  Ok "القسمان **جُرِّدا** من القارئ رغم طلبهما صراحةً ✔ الحارس في الخدمة لا في الواجهة"
} else { Bad "تسرّب: القارئ احتفظ بـ$($rdrMods -join ',')" }
$tokRdr=EmpLogin 'rdr_hr'
foreach($ep in @("/employees","/payroll/years","/hr/summary","/hr/leaves/pending")){
  $r=Api GET $ep $null $tokRdr $cid
  if($r.S -eq 403){ Ok "القارئ محجوب عن $ep (403)" } else { Bad "تسرّب: $ep ردّ $($r.S) للقارئ" }
}

# ── ٢) موظف بقسم «الموظفين» وحده: يعمل عليه ويُحجب عن الرواتب ──
# 🔄 كان هذا الدور محجوباً كلياً قبل ADR-025.
$empOnly=UpsertUser 'emp_hr' 'كاتب شؤون الموظفين' 'Employee' @('Outgoing','Employees') $true $false
if($empOnly.companies[0].modules -contains 'Employees'){
  Ok "🔄 الموظف **احتفظ** بقسم الموظفين — الوحدة فُتحت لمن دون المدير"
} else { Bad "الموظف جُرِّد من الموظفين رغم ADR-025" }
$tokEmp=EmpLogin 'emp_hr'
if($tokEmp){ Ok "دخول كاتب شؤون الموظفين" } else { Bad "فشل دخوله" }

foreach($ep in @("/employees","/hr/leaves/pending","/employees/$e1/leaves","/employees/$e1/log","/employees/$e1/attachments")){
  $r=Api GET $ep $null $tokEmp $cid
  if($r.S -eq 200){ Ok "يصل إلى $ep (200)" } else { Bad "منعٌ خاطئ: $ep ردّ $($r.S) لصاحب القسم" }
}
# ⚠️ **وهنا جوهر الفصل**: كل نقاط الرواتب محجوبة عنه.
foreach($ep in @("/payroll/years","/payroll/periods/$Year/$Month","/hr/settings","/payroll/periods/$Year/$Month/excel")){
  $r=Api GET $ep $null $tokEmp $cid
  if($r.S -eq 403){ Ok "🔐 محجوب عن $ep (403) — قسم الموظفين لا يفتح الرواتب" } else { Bad "تسرّب: $ep ردّ $($r.S)" }
}
# والملخّص يصله **بلا أرقام الرواتب** لا بأصفارٍ كاذبة.
$sumEmp=(Api GET "/hr/summary" $null $tokEmp $cid).B
if($null -ne $sumEmp.activeEmployees){ Ok "الملخّص يحمل عدد الموظفين لصاحب قسمهم" } else { Bad "الملخّص بلا عدد الموظفين" }
if($null -eq $sumEmp.thisMonthTotalIqd -and $null -eq $sumEmp.unpaidMonths){
  Ok "🔐 وأرقام الرواتب تصله **null** لا صفراً كاذباً"
} else { Bad "تسرّب: أرقام الرواتب وصلت لمن لا يملك قسمها" }
# ويكتب في الموظفين لأنه يملك علَمه.
$newEmp=Api POST "/employees" @{profile=@{fullName='موظف أنشأه الكاتب';receiptLanguage='Arabic'};employment=@{position='فنّي';hireDate="$Year-01-01T00:00:00";salaryCurrency='IQD';baseSalary=500000;displayOrder=9;isActive=$true}} $tokEmp $cid
if($newEmp.S -eq 200){ Ok "ويكتب: أنشأ موظفاً بعلَم CanManageEmployees" } else { Bad "منعٌ خاطئ: الإنشاء ردّ $($newEmp.S)" }
if($newEmp.B.employeeId){ $null=Api DELETE "/employees/$($newEmp.B.employeeId)" $null $admin $cid }

# ── ٣) موظف بقسم «الرواتب» وحدها: العكس تماماً ──
$payOnly=UpsertUser 'pay_hr' 'محاسب الرواتب' 'Employee' @('Outgoing','Payroll') $false $true
$tokPay=EmpLogin 'pay_hr'
if($tokPay){ Ok "دخول محاسب الرواتب" } else { Bad "فشل دخوله" }
foreach($ep in @("/payroll/years","/hr/settings")){
  $r=Api GET $ep $null $tokPay $cid
  if($r.S -eq 200){ Ok "المحاسب يصل إلى $ep (200)" } else { Bad "منعٌ خاطئ: $ep ردّ $($r.S)" }
}
foreach($ep in @("/employees","/hr/leaves/pending","/employees/$e1/attachments")){
  $r=Api GET $ep $null $tokPay $cid
  if($r.S -eq 403){ Ok "🔐 المحاسب محجوب عن $ep (403) — الرواتب لا تفتح الموظفين" } else { Bad "تسرّب: $ep ردّ $($r.S)" }
}
# ولا يكتب في الموظفين: علَمه للرواتب وحدها.
$rw=Api POST "/employees" @{profile=@{fullName='مخترق';receiptLanguage='Arabic'};employment=@{position='x';hireDate="$Year-01-01T00:00:00";salaryCurrency='IQD';baseSalary=1;displayOrder=0;isActive=$true}} $tokPay $cid
if($rw.S -eq 403){ Ok "🔐 والمحاسب محجوب عن **إنشاء** موظف (403)" } else { Bad "تسرّب: إنشاء موظف ردّ $($rw.S)" }

Write-Host "`n=== إسناد موظف قائم إلى شركة ثانية (ADR-027) ===" -ForegroundColor Cyan
# ⚠️ يحتاج **شركتين**. الشركة الثانية تُستعمل ولا تُنشَأ: إنشاؤها من سكربتٍ اختباريّ يترك
#    أثراً دائماً في قاعدةٍ قد تكون قاعدةَ عمل. وغيابُها **يُعلَن بصوتٍ عالٍ** لا يُبتلع
#    صامتاً — قسمٌ لا يعمل ولا أحد يعلم أسوأ من قسمٍ يفشل.
# ⚠️ **كل عدٍّ هنا مُغلَّف بـ`@()`.** في PS 5.1 نتيجةُ مرشَّحٍ بعنصرٍ واحد **ليست مصفوفة**،
#    و`.Count` على `PSCustomObject` تُعيد **فراغاً** لا 1 — فيُقرأ النجاحُ فشلاً. وقع هذا
#    فعلاً في أول تشغيل لهذا القسم: أبلغ «لم يظهر في القائمة» وهو ظاهرٌ فيها.
#    **درسٌ من عائلة «الاختبار قد يكذب»** — والمنتج كان سليماً.
$allCo=@((Api GET "/companies" $null $admin $null).B)
if($allCo.Count -lt 2){
  Write-Host "  [تخطٍّ] لا توجد شركة ثانية — هذا القسم يحتاج شركتين ولم يُنفَّذ." -ForegroundColor Yellow
} else {
  $cid2=$allCo[1].companyId
  $co1Name=$allCo[0].name; $co2Name=$allCo[1].name
  Ok "الشركة الثانية: $cid2"

  # ── ١) قبل الإسناد: لا شركات أخرى، والبحث من الثانية يجده «خارجها» ──
  # ── ١) ما قبل الإسناد ──
  #
  # ⚠️ **مشروطةٌ ومُعلَنة، ولا تُنظَّف بالحذف.** `DELETE /employees/{id}` يحذف **الموظف كلّه**
  #    حذفاً ناعماً لا إسنادَه بشركةٍ بعينها (ولا نقطةَ لفكّ إسنادٍ واحد أصلاً) — فتنظيفُ
  #    الحال به كان سيمحو بياناته في الشركة الأولى أيضاً. وحين يبقى الإسناد من تشغيلٍ سابق
  #    **يُعلَن التخطّي بصوتٍ عالٍ** ولا يُحسب نجاحاً كاذباً.
  $peek=Api GET "/employees/$e1" $null $admin $cid2
  if($peek.S -eq 200){
    Write-Host "  [تخطٍّ] الإسناد قائم من تشغيلٍ سابق — تحقّقات «ما قبل الإسناد» الثلاثة لم تُنفَّذ." -ForegroundColor Yellow
  } else {
    if($peek.S -eq 404){ Ok "🔐 قبل الإسناد: بطاقته من الشركة الثانية تردّ 404" }
    else { Bad "تسرّب: بطاقته من شركةٍ ليس فيها ردّت $($peek.S)" }

    $before=Api GET "/employees/$e1" $null $admin $cid
    if(@($before.B.otherCompanies).Count -eq 0){ Ok "قبل الإسناد: otherCompanies فارغة" }
    else { Bad "otherCompanies ليست فارغة قبل الإسناد" }

    $look2=Api GET "/employees/lookup?nationalId=19900101" $null $admin $cid2
    if($look2.B -and $look2.B.employeeId -eq $e1 -and -not $look2.B.alreadyInThisCompany){
      Ok "البحث بالهوية من الشركة الثانية يجده ويقول «ليس هنا»"
    } else { Bad "البحث من الشركة الثانية أخفق: $($look2.S)" }
  }

  # ── ٢) الإسناد **براتبٍ مختلف** — وهذا بيتُ القصيد في اختبار العزل ──
  # (وهو upsert، فإعادةُ التشغيل تحدّث الإسناد ولا تُنشئ ثانياً — والتحقّقات بعده صالحة
  #  في الحالين.)
  $link=Api PUT "/employees/$e1/employment" @{position='مستشار';positionEn='Advisor';
      hireDate='2023-06-01T00:00:00';salaryCurrency='IQD';baseSalary=750000;displayOrder=1;isActive=$true} $admin $cid2
  if($link.S -eq 200){ Ok "الإسناد إلى الشركة الثانية نجح (200)" } else { Bad "الإسناد ردّ $($link.S)" }

  # ── ٣) بعد الإسناد: كلٌّ يرى شروطَه هو، ويعلم بوجود الأخرى بالاسم فقط ──
  $inCo2=Api GET "/employees/$e1" $null $admin $cid2
  $emp2=@($inCo2.B.companies)
  if($emp2.Count -eq 1 -and $emp2[0].companyId -eq $cid2 -and $emp2[0].baseSalary -eq 750000){
    Ok "🔐 في الشركة الثانية: إسنادٌ واحد براتبها هي (750,000)"
  } else { Bad "تسرّب أو نقص: عدد=$($emp2.Count) راتب=$($emp2[0].baseSalary)" }

  # 🔴 **أخطر تحقّق في القسم:** راتبُ الشركة الأولى (1,200,000) يجب ألّا يظهر هنا إطلاقاً.
  if(@($emp2 | Where-Object { $_.baseSalary -eq 1200000 }).Count -eq 0){
    Ok "🔐 راتب الشركة الأولى **لا يتسرّب** إلى بطاقته في الثانية (ADR-017 نافذ)"
  } else { Bad "🔴 تسرّب راتب الشركة الأولى إلى الثانية" }

  $others2=@($inCo2.B.otherCompanies)
  if($others2.Count -eq 1 -and $others2[0].companyId -eq $cid){
    Ok "«يعمل أيضاً في» يظهر من الشركة الثانية ويشير إلى الأولى"
  } else { Bad "otherCompanies من الثانية: عدد=$($others2.Count)" }

  # وأسماءٌ فقط: لا حقلَ راتبٍ ولا صفة في العنصر.
  $keys=@($others2[0].PSObject.Properties.Name)
  if($keys.Count -eq 2 -and ($keys -contains 'companyId') -and ($keys -contains 'name')){
    Ok "🔐 عنصر «الشركة الأخرى» يحمل المعرّف والاسم **فقط** (لا راتب ولا صفة)"
  } else { Bad "🔴 العنصر يحمل حقولاً زائدة: $($keys -join ',')" }

  # ── ٤) والاتجاه المعاكس: الأولى تعلم بالثانية ──
  $inCo1=Api GET "/employees/$e1" $null $admin $cid
  $others1=@($inCo1.B.otherCompanies)
  if($others1.Count -eq 1 -and $others1[0].companyId -eq $cid2){
    Ok "والكشف متبادل: الأولى ترى الثانية"
  } else { Bad "otherCompanies من الأولى: عدد=$($others1.Count)" }
  if(@($inCo1.B.companies)[0].baseSalary -eq 1200000){
    Ok "🔐 وراتبه في الأولى بقي 1,200,000 — الإسناد الثاني لم يمسّه"
  } else { Bad "🔴 تغيّر راتبه في الأولى بعد الإسناد" }

  # ── ٥) البحث ثانيةً يقول «هنا»، وقائمة الشركة الثانية تضمّه ──
  $look3=Api GET "/employees/lookup?nationalId=19900101" $null $admin $cid2
  if($look3.B.alreadyInThisCompany){ Ok "البحث بعد الإسناد يقول «مُسنَدٌ هنا بالفعل»" }
  else { Bad "البحث ما زال يقول «ليس هنا» بعد الإسناد" }

  $list2=@((Api GET "/employees" $null $admin $cid2).B)
  if(@($list2 | Where-Object { $_.employeeId -eq $e1 }).Count -eq 1){
    Ok "وظهر في قائمة موظفي الشركة الثانية"
  } else { Bad "لم يظهر في قائمة الشركة الثانية" }

  # ── ٦) وموظفٌ لم يُسنَد يبقى محجوباً — فالكشف لا يعمّ ──
  $hidden=Api GET "/employees/$e2" $null $admin $cid2
  if($hidden.S -eq 404){ Ok "🔐 وزميلُه غيرُ المُسنَد يبقى 404 من الشركة الثانية" }
  else { Bad "تسرّب: موظف غير مُسنَد ردّ $($hidden.S)" }
}

Write-Host "`n=== النتيجة ===" -ForegroundColor Cyan
Write-Host "نجح: $pass" -ForegroundColor Green
Write-Host "فشل: $fail" -ForegroundColor $(if($fail -eq 0){'Green'}else{'Red'})
if($fail -gt 0){ exit 1 }
