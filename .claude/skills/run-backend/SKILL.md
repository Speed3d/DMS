---
name: run-backend
description: تشغيل باك-إند DMS (Dms.Api) محلياً مع Swagger، وإيقافه بأمان. استخدمها عند طلب تشغيل/إيقاف الـ API أو فتح Swagger أو اختبار نقطة نهاية.
---

# تشغيل باك-إند DMS

## التشغيل (في الخلفية)
من `D:\DMS\backend`، شغّل في الخلفية (run_in_background) مع تثبيت البيئة والمنفذ:

```powershell
$env:ASPNETCORE_ENVIRONMENT='Development'
$env:ASPNETCORE_URLS='http://localhost:5080'
Set-Location "D:\DMS\backend"
dotnet run --project Dms.Api --no-launch-profile
```

- بيئة Development ضرورية لتحميل أسرار `appsettings.Development.json` (JWT + مفاتيح QR) و Swagger.
- يطبّق الـ Migrations وينشئ أول SuperAdmin تلقائياً.
- Swagger: `http://localhost:5080/swagger`. أول دخول: `admin` / `Admin@12345`.

## انتظار الجاهزية
استطلِع حتى يستجيب:
```powershell
for ($i=0;$i -lt 40;$i++){ try { if((Invoke-WebRequest "http://localhost:5080/swagger/v1/swagger.json" -UseBasicParsing -TimeoutSec 3).StatusCode -eq 200){"UP";break} } catch { Start-Sleep -Milliseconds 750 } }
```

## الإيقاف (قبل إعادة البناء — يقفل ملفات الإخراج)
```powershell
$c = Get-NetTCPConnection -LocalPort 5080 -State Listen -ErrorAction SilentlyContinue
if ($c) { $c.OwningProcess | Select-Object -Unique | ForEach-Object { Stop-Process -Id $_ -Force } }
```

## ملاحظات
- غيّر المنفذ بتعديل `ASPNETCORE_URLS`.
- للحصول على توكن: `POST /api/auth/login` بـ `{username,password}`؛ مرّر `Authorization: Bearer <token>` و `X-Company-Id` للسوبر أدمن.
