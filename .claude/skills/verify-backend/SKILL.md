---
name: verify-backend
description: تشغيل اختبار التدفق الشامل (E2E) لباك-إند DMS عبر الـ API الحيّ للتأكد من سلامة دورة الصادر. استخدمها بعد تغييرات مهمة في الباك-إند أو للتحقق من أن النظام يعمل end-to-end.
---

# اختبار E2E لباك-إند DMS

يفترض أن الـ API يعمل على `http://localhost:5080` (انظر مهارة `run-backend`).

يغطّي: تسجيل دخول → إنشاء شركة (برمز فريد عشوائي) → جهة → قالب → سعر صرف → مسودّة صادر → اعتماد (رقم+PDF+QR) → تنزيل PDF → تعديل بعد الاعتماد → سجل إصدارات → تحقق QR → كشف تزوير → سجل تدقيق.

```powershell
$ErrorActionPreference='Stop'
$base="http://localhost:5080/api"; $prefix="D$(Get-Random -Minimum 100 -Maximum 999)"
function Call($m,$u,$t,$b,$c){ $h=@{}; if($t){$h["Authorization"]="Bearer $t"}; if($c){$h["X-Company-Id"]="$c"}
  $a=@{Method=$m;Uri="$base$u";Headers=$h}; if($b -ne $null){$a["Body"]=($b|ConvertTo-Json -Depth 6);$a["ContentType"]="application/json; charset=utf-8"}; Invoke-RestMethod @a }
$tok=(Call POST "/auth/login" $null @{username="admin";password="Admin@12345"} $null).accessToken
$cid=(Call POST "/companies" $tok @{name="أرض العرين";prefix=$prefix;isActive=$true} $null).companyId
$eid=(Call POST "/entities" $tok @{name="وزارة الإعمار";kind="Both"} $cid).entityId
$tid=(Call POST "/templates" $tok @{name="القالب";watermarkOpacity=8;marginTop=24;marginRight=40;marginBottom=24;marginLeft=40;pageSize="A4";fontFamily="Amiri";isActive=$true} $cid).templateId
Call POST "/exchange-rates" $tok @{currency="USD";rate=1310;effectiveDate="2026-06-28"} $cid | Out-Null
$oid=(Call POST "/outgoing" $tok @{entityId=$eid;templateId=$tid;date="2026-06-28";subject="اختبار";bodyHtml="نص";amount=25000;currency="USD";exchangeRate=1310} $cid).outgoingId
$ap=Call POST "/outgoing/$oid/approve" $tok $null $cid; "APPROVED number=$($ap.number) hasPdf=$($ap.hasPdf)"
$d=Call GET "/outgoing/$oid" $tok $null $cid
Call PUT "/outgoing/$oid/edit-approved" $tok @{entityId=$eid;templateId=$tid;date="2026-06-28";subject="معدّل";bodyHtml="نص2";amount=30000;currency="USD";exchangeRate=1310;rowVersion=$d.rowVersion;changeNote="تعديل"} $cid | Out-Null
$d2=Call GET "/outgoing/$oid" $tok $null $cid
$v=Call POST "/verify" $null @{qrContent=$d2.qrContent} $null; "VERIFY isValid=$($v.isValid) foundInDb=$($v.foundInDb)"
"DONE"
```

النتيجة المتوقّعة: رقم بالصيغة `Dxxx-2026-00001`، `hasPdf=True`، `isValid=True`, `foundInDb=True`.
