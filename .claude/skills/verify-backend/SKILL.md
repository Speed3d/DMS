---
name: verify-backend
description: تشغيل اختبار التدفق الشامل (E2E) لباك-إند DMS عبر الـ API الحيّ للتأكد من سلامة دورات الصادر والوارد والنسخ/الاستعادة. استخدمها بعد تغييرات مهمة في الباك-إند أو للتحقق من أن النظام يعمل end-to-end.
---

# اختبار E2E لباك-إند DMS

يفترض أن الـ API يعمل على `http://localhost:5080` (انظر مهارة `run-backend`).

**المجموع: 119 تحقّقاً** عبر أربعة سكربتات — 70 وارد · 26 متعدد الشركات · 13 نسخ/استعادة · 10 أقسام. النجاح في كلٍّ = `فشل: 0` ورمز خروج 0.

> 🔑 **الـAPI لا يعمل من داخل worktree:** ملف الأسرار `appsettings.Development.json` مستبعَد من git
> فلا يُنسخ معها، فيفشل التشغيل بخطأ TCP. انسخه مؤقتاً من `D:\DMS` (ثم احذفه) أو شغّل من هناك.
> ولنفس السبب `dotnet ef` يحتاج `--connection "Server=.;Database=DmsDb;Trusted_Connection=True;TrustServerCertificate=True"`.
⚠️ ملفات PowerShell بالعربية تحتاج ترميز **UTF-8 with BOM** وإلا فشل التحليل النحوي في PS 5.1.

> **الموظف المُمرَّر لسكربت الوارد يجب أن يكون في الشركة التي يختبرها السكربت** (يختار **أول** شركة)
> و**بلا** صلاحية `CanManageIncoming` (وإلا فشلت تأكيدات الـ403). `emp_leg` الذي ينشئه سكربت الأقسام
> يطابق الشرطين — كلمة مروره `Emp@12345new` بعد أول تشغيل.

## 1) وحدة الوارد — سكربت جاهز

```powershell
powershell -File backend\e2e\incoming-e2e.ps1 -AdminPwd <كلمة المرور> -EmployeeUser sinan -EmployeePwd <كلمة المرور>
```

يغطّي **72 تحقّقاً**: التسجيل والترقيم `PREFIX-IN-YEAR-#####` · طرق الاستلام (`Manual/Mail/Email` ورفض غيرها) · مصفوفة انتقالات الحالة (المسموح والمرفوض) · الملاحظة الإلزامية عند «تم الرد» يدوياً · الإحالة (**بالعقد المتعدد** `departments:[{departmentId,note}]` — ADR-018) · الأرشفة ومنع التعديل بعدها · الربط/فك الربط مع الصادر والربط العكسي ومنع الربط المزدوج · سجل الحركة بأسماء المنفّذين · البحث بكل المعاملات · المرفقات · صلاحيات الموظف (403/404).

- **يُعيد تشغيل نفسه بأمان** (يختار صادراً معتمداً غير مرتبط، ويُنشئ واحداً فقط عند الحاجة).
- كلمات المرور تُمرَّر كمعاملات ولا تُخزَّن. النجاح = `فشل: 0` ورمز خروج 0.
- يُنشئ بيانات حقيقية — **بيئة تطوير فقط**.

## 2) الأقسام ورؤية الوارد — سكربت جاهز

```powershell
powershell -File backend\e2e\departments-e2e.ps1 -AdminPwd <كلمة المرور>
```

**22 تحقّقاً** (ADR-015 + ADR-018): إنشاء قسمين وموظفين · **موظف يرى الكتاب المُحال لقسمه وإن لم يستلمه** · عزل بين الأقسام (404) · القوائم مفلترة بالقسم · مرفقات كتاب القسم · صلاحية `CanManageIncoming` · موظف بلا صلاحية يُمنع (403)
· **الإحالة تراكمية** (قسمان معاً بعد إحالتين) · **مَن أحال يبقى يرى** · إعادة الإحالة تُحدّث الملاحظة ولا تُكرّر · إحالة لقسمين في طلب واحد · **قسم واحد غير صالح يُبطل الإحالة كلها** · رفض الإحالة بلا أقسام.
⚠️ يُنشئ موظفَي اختبار (`emp_fin`, `emp_leg`) وأقساماً — بيئة تطوير فقط.
⚠️ **كلمة مرور موظفي الاختبار `Emp@12345new`** (لا كلمة الأدمن) — مرّرها لسكربت الوارد:
`-EmployeeUser emp_fin -EmployeePwd Emp@12345new`.

## 3) العزل بين الشركات — سكربت جاهز (ADR-017)

```powershell
powershell -File backend\e2e\multi-company-e2e.ps1 -AdminPwd <كلمة المرور>
```

26 تحقّقاً: موظف واحد في شركتين بصلاحيات وأقسام **مختلفة** · الحفظ يُبقي الاختلاف ·
**نفس التوكن: الوارد متاح في شركة و403 في الأخرى، والتقارير معكوسة** · قسم من شركة أخرى يُرفَض (400) ·
`GET /departments?companyId=` للمانح.
⚠️ يُنشئ شركة ثانية وموظف `emp_multi` — بيئة تطوير فقط. قابل لإعادة التشغيل.

## 4) النسخ الاحتياطي والاستعادة — سكربت جاهز

```powershell
powershell -File backend\e2e\backup-restore-e2e.ps1 -AdminPwd <كلمة المرور>
```

يغطّي 13 تحقّقاً: إنشاء كتاب شاهد → نسخة كاملة → حذف الكتاب → رفض تأكيد خاطئ → استعادة بكلمة «استعادة» → **الكتاب يعود سليماً** → خروج من وضع الصيانة → تسجيل نسخة أمان تلقائية.

- ⚠️ **تدميري** — يحذف كتاباً ويستعيد قاعدة كاملة. بيئة تطوير فقط.
- بعد الاستعادة تعود القاعدة لحالة النسخة؛ الترقية للمخطّط الحالي تلقائية.

## 4) دورة الصادر — سكربت مضمّن

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
