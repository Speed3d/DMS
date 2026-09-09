param([string]$AdminPwd='Speed3ds', [string]$Base='http://localhost:5080/api', [string]$Root='http://localhost:5080')
$ErrorActionPreference='Stop'; $pass=0; $fail=0
function Ok($m){ $script:pass++; Write-Host "  [نجح] $m" -ForegroundColor Green }
function Bad($m){ $script:fail++; Write-Host "  [فشل] $m" -ForegroundColor Red }
function Api($m,$u,$b,$t,$c){ $h=@{}; if($t){$h.Authorization="Bearer $t"}; if($c){$h."X-Company-Id"="$c"}
  $p=@{Uri="$Base$u";Method=$m;Headers=$h;ContentType="application/json; charset=utf-8"}
  if($null -ne $b){$p.Body=[Text.Encoding]::UTF8.GetBytes(($b|ConvertTo-Json -Depth 8 -Compress))}
  try{$r=Invoke-WebRequest @p -UseBasicParsing; $j=$null; if($r.Content){try{$j=$r.Content|ConvertFrom-Json}catch{}}; return @{S=[int]$r.StatusCode;B=$j}}
  catch{$resp=$_.Exception.Response; $code=if($resp){[int]$resp.StatusCode}else{0}; return @{S=$code;B=$null}}
}

# صفحةٌ عامّة: بلا توكن وبلا ترويسة شركة.
function Page($path){
  try{ $r=Invoke-WebRequest -Uri "$Root$path" -UseBasicParsing -TimeoutSec 20
       return @{S=[int]$r.StatusCode; H=$r.Content} }
  catch{ $resp=$_.Exception.Response; return @{S=$(if($resp){[int]$resp.StatusCode}else{0}); H=''} }
}

# 🔴 **يُقرأ الحكم من `meta` لا من نصٍّ عربيّ** — PS 5.1 يشوّه العربية، ومطابقتُها حارسٌ هشّ
#    (درسٌ مسجَّل في `hr-e2e.ps1`). والنصّ العربي يُفحص مرّةً واحدة بصيغةٍ مقتضبة.
function Verdict($html){
  if($html -match 'name="dms-verdict" content="([A-Za-z]+)"'){ return $Matches[1] }
  return 'NONE'
}
function Bytes($path){
  try{ $r=Invoke-WebRequest -Uri "$Root$path" -UseBasicParsing -TimeoutSec 30
       return @{S=[int]$r.StatusCode; D=$r.Content; N=$r.Headers['Content-Disposition']} }
  catch{ $resp=$_.Exception.Response; return @{S=$(if($resp){[int]$resp.StatusCode}else{0}); D=$null; N=$null} }
}

Write-Host "=== إعداد ===" -ForegroundColor Cyan
$admin=(Api POST "/auth/login" @{username='admin';password=$AdminPwd} $null $null).B.accessToken
if(-not $admin){ Bad "تعذّر دخول admin"; exit 1 }

$companies=@((Api GET "/companies" $null $admin $null).B)
if($companies.Count -lt 1){ Bad "لا توجد شركات"; exit 1 }
$cid=[int]$companies[0].companyId
Ok "الشركة الفعّالة: $cid"

$ent=@((Api GET "/entities" $null $admin $cid).B) | Select-Object -First 1
if(-not $ent){ $ent=(Api POST "/entities" @{name='جهة التحقق';kind='Both';isActive=$true} $admin $cid).B }
$tpl=@((Api GET "/templates" $null $admin $cid).B) | Select-Object -First 1
if(-not $tpl){ $tpl=(Api POST "/templates" @{companyId=$cid;name='قالب التحقق';watermarkOpacity=10;marginTop=40;marginRight=40;marginBottom=40;marginLeft=40;pageSize='A4';fontFamily='Amiri';isActive=$true} $admin $cid).B }
if(-not $ent -or -not $tpl){ Bad "تعذّر تجهيز الجهة/القالب"; exit 1 }
Ok "جهةٌ وقالب جاهزان"

# ⚠️ **كتابٌ خاصٌّ بكل تشغيل** — وإلا التقط التشغيلُ الثاني كتابَ الأول فبدت النتائج مختلطة
#    (درسٌ من `tasks-e2e`: عنوانٌ ثابت جعل السكربت يبلّغ عن تكاثرٍ لم يقع).
$mk=[guid]::NewGuid().ToString('N').Substring(0,6)
$draft=Api POST "/outgoing" @{companyId=$cid;entityId=[int]$ent.entityId;templateId=[int]$tpl.templateId
    date=(Get-Date).ToString("yyyy-MM-dd");subject="تحقق-$mk";bodyHtml="<p>كتاب اختبار التحقق</p>"} $admin $cid
if($draft.S -ne 200){ Bad "تعذّر إنشاء الكتاب: $($draft.S)"; exit 1 }
$oid=[int]$draft.B.outgoingId

$appr=Api POST "/outgoing/$oid/approve" $null $admin $cid
if($appr.S -eq 200){ Ok "أُنشئ كتابٌ واعتُمد ($($appr.B.number))" } else { Bad "تعذّر الاعتماد: $($appr.S)"; exit 1 }

Write-Host "`n=== رابط التحقق ===" -ForegroundColor Cyan
$detail=(Api GET "/outgoing/$oid" $null $admin $cid).B
$link=$detail.verifyUrl
if($link -and $link -match '^/v/[A-Za-z0-9_-]{22}$'){ Ok "المعتمد يحمل رابط تحقّقٍ بصيغته: $link" }
else { Bad "رابط التحقق غائبٌ أو بصيغةٍ غريبة: $link"; exit 1 }
$token=$link.Substring(3)

# 🔴 **المسودّة بلا رابط** — لا رمزَ مطبوعاً فيها أصلاً.
$d2=Api POST "/outgoing" @{companyId=$cid;entityId=[int]$ent.entityId;templateId=[int]$tpl.templateId
    date=(Get-Date).ToString("yyyy-MM-dd");subject="مسودة-$mk";bodyHtml="<p>مسودّة</p>"} $admin $cid
$draftLink=(Api GET "/outgoing/$([int]$d2.B.outgoingId)" $null $admin $cid).B.verifyUrl
if($null -eq $draftLink){ Ok "🔴 والمسودّة بلا رابط تحقّق — لا رمزَ مطبوعاً فيها" }
else { Bad "المسودّة حملت رابطاً: $draftLink" }

Write-Host "`n=== الصفحة العامة — بلا حساب ===" -ForegroundColor Cyan
$p=Page "/v/$token"
if($p.S -eq 200 -and (Verdict $p.H) -eq 'Genuine'){ Ok "كتابٌ معتمد ⇒ «تم إصدار هذا الكتاب فعلاً من الشركة»" }
else { Bad "الحكم: $(Verdict $p.H) والحالة $($p.S)" }

# ⚠️ **النصّ العربي يُفحص مرّةً** — فالحكم الآليّ لا يُثبت أن المستخدم يقرأ الجملة الصحيحة.
if($p.H -match 'تم إصدار هذا الكتاب'){ Ok "والنصّ العربي يظهر للقارئ فعلاً" }
else { Bad "الحكم صحيح والنصّ العربي غائب — الصفحة تُرضي الفحص ولا تُفهم" }

if($p.H -match [regex]::Escape($detail.number)){ Ok "والصفحة تعرض رقم الكتاب للمطابقة" }
else { Bad "رقم الكتاب غائبٌ عن الصفحة" }

# 🔐 **المبلغ لا يُعرض** (قرار المالك) — والصفحة موضع الإفصاح الوحيد بعد أن صار الرمز معتِماً.
if($p.H -notmatch 'المبلغ'){ Ok "🔐 ولا يُعرض المبلغ إطلاقاً" } else { Bad "المبلغ ظاهرٌ في صفحةٍ عامة" }

Write-Host "`n=== الرموز المزوَّرة ===" -ForegroundColor Cyan
foreach($bad in @('AAAAAAAAAAAAAAAAAAAAAA','not-a-token','%D8%B9%D8%B1%D8%A8%D9%8A','AAAA')){
  $r=Page "/v/$bad"
  if($r.S -eq 200 -and (Verdict $r.H) -eq 'Tampered'){ Ok "رمز «$bad» ⇒ «تم التلاعب بالكتاب»" }
  else { Bad "رمز «$bad» أعطى $(Verdict $r.H) بالحالة $($r.S)" }
}

# 🔴 **ولا يُفصح المزوَّر عن وجود الكتاب** — لا رقمَ ولا جهة في صفحة التلاعب.
$t=Page "/v/AAAAAAAAAAAAAAAAAAAAAA"
if($t.H -notmatch [regex]::Escape($detail.number)){ Ok "🔐 وصفحةُ التلاعب لا تُفصح برقمٍ ولا ببيانات" }
else { Bad "صفحة التلاعب سرّبت بيانات" }

Write-Host "`n=== تنزيل الـPDF ===" -ForegroundColor Cyan
$pdf=Bytes "/v/$token/pdf"
if($pdf.S -eq 200 -and $pdf.D -and $pdf.D.Length -gt 1000 -and $pdf.D[0] -eq 0x25 -and $pdf.D[1] -eq 0x50){
  Ok "تنزيلٌ عامّ يعمل ($($pdf.D.Length) بايت، ويبدأ بـ%PDF)" } else { Bad "التنزيل: الحالة $($pdf.S)" }
if($pdf.N -and $pdf.N -match [regex]::Escape($detail.number)){ Ok "وباسم الكتاب لا باسمٍ عامّ" }
else { Bad "اسم الملف: $($pdf.N)" }

$badPdf=Bytes "/v/AAAAAAAAAAAAAAAAAAAAAA/pdf"
if($badPdf.S -eq 404){ Ok "🔐 ورمزٌ مزوَّر لا يُنزّل شيئاً (404)" } else { Bad "ردّ $($badPdf.S)" }

Write-Host "`n=== سجلّ التدقيق ===" -ForegroundColor Cyan
# ⚠️ **يُقرأ من نقطة التدقيق لا من القاعدة** — فالسكربت يفحص ما يراه النظام لا ما في الجدول.
$logs=@((Api GET "/audit?take=50" $null $admin $cid).B)
$scans=@($logs | Where-Object { $_.action -eq 'VerifyScan' -and $_.entityId -eq "$oid" })
$dls=@($logs | Where-Object { $_.action -eq 'PublicPdfDownload' -and $_.entityId -eq "$oid" })
if($scans.Count -ge 1){ Ok "الفحص العامّ مسجَّلٌ في سجلّ التدقيق ($($scans.Count))" } else { Bad "لا سطرَ فحصٍ في السجلّ" }
if($dls.Count -ge 1){ Ok "والتنزيل كذلك ($($dls.Count))" } else { Bad "لا سطرَ تنزيلٍ في السجلّ" }

Write-Host "`n=== حدّ الطلبات ===" -ForegroundColor Cyan
# 🔴 **النقطة عامّة وتضرب القاعدة في كل طلب** — وبلا حدٍّ يكفي سكربتٌ واحد ليُثقل السيرفر.
$codes=@()
for($i=0;$i -lt 45;$i++){ $codes+=(Page "/v/$token").S }
$tooMany=@($codes | Where-Object { $_ -eq 429 }).Count
if($tooMany -ge 1){ Ok "تجاوزُ الحدّ يردّ 429 ($tooMany من 45)" } else { Bad "لا حدّ للطلبات — 0 من 45 رُدَّت" }

Write-Host "`n=== النتيجة ===" -ForegroundColor Cyan
Write-Host "نجح: $pass" -ForegroundColor Green
Write-Host "فشل: $fail" -ForegroundColor $(if($fail -gt 0){'Red'}else{'Green'})
if($fail -gt 0){ exit 1 }
