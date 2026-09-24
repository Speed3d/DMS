param([string]$AdminPwd='Admin@12345', [string]$Base='http://localhost:5091/api')
# ════════════════════════════════════════════════════════════════════════════════════════
#  تهيئة قاعدةٍ جديدة للسكربتات — **يُشغَّل أوّلاً دائماً** (G19).
#
#  المدير المبذور يحمل «يجب تغيير كلمة المرور»، والخادم صار يحجب به كلَّ شيء. فيُفعَّل هنا
#  **مرّةً واحدة** بكلمته نفسها (انظر `_activate.ps1`) لتعمل السكربتات بعده بـ-AdminPwd كما هي.
# ════════════════════════════════════════════════════════════════════════════════════════
. "$PSScriptRoot\_activate.ps1"
for ($i = 0; $i -lt 60; $i++) {
  try { Invoke-WebRequest "$Base/system/status" -UseBasicParsing -TimeoutSec 3 | Out-Null; break } catch { Start-Sleep 2 }
}
if (Enable-TempPassword $Base 'admin' $AdminPwd) {
  Write-Host "  [نجح] المدير مُفعَّل بكلمته نفسها" -ForegroundColor Green
  Write-Host "`n══════ النتيجة: 1 نجح · 0 فشل ══════" -ForegroundColor Green
} else {
  Write-Host "  [فشل] تعذّر دخول المدير بـ$AdminPwd" -ForegroundColor Red
  Write-Host "`n══════ النتيجة: 0 نجح · 1 فشل ══════" -ForegroundColor Red
  exit 1
}
