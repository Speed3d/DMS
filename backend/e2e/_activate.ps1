# ════════════════════════════════════════════════════════════════════════════════════════
#  تفعيل حسابٍ بكلمةٍ مؤقتة — للسكربتات وحدها (G19).
#
#  الخادم صار يحجب كلَّ شيء عن رمزٍ لم تُغيَّر كلمتُه المؤقتة، و**الجديدة تختلف عن الحالية**.
#  والسكربتات تحتاج أن تبقى كلماتها ثابتة (يُستدعى السكربت الثاني بـ-AdminPwd نفسه) —
#  فالتفعيل **دورتان**: المؤقتة ⟵ وسيطة ⟵ المؤقتة. كلُّ خطوةٍ «تختلف عن الحالية» فتمرّ،
#  وتنتهي بالعلَم مطفأً والكلمة كما هي.
#
#  ⚠️ **هذا لتهيئة الاختبار لا ثغرة**: مستخدمٌ حقيقيّ يستطيع الشيء نفسه ليُبقي الكلمة التي
#  يعرفها المدير — والتدقيق يسجّل «تغيير كلمة المرور» مرّتين. سجلُّ كلماتٍ سابقة خارج النطاق.
#
#  الاستعمال:  . "$PSScriptRoot\_activate.ps1"   ثم   Enable-TempPassword $Base 'user' 'Pwd@12345'
# ════════════════════════════════════════════════════════════════════════════════════════
function Enable-TempPassword([string]$base, [string]$user, [string]$pass) {
  $j = 'application/json; charset=utf-8'
  try {
    $login = Invoke-RestMethod -Uri "$base/auth/login" -Method Post -ContentType $j `
      -Body ([Text.Encoding]::UTF8.GetBytes((@{ username = $user; password = $pass } | ConvertTo-Json -Compress)))
  } catch { return $false }
  if (-not $login.mustChangePassword) { return $true }

  $mid = "$pass~e2e"
  $a = Invoke-RestMethod -Uri "$base/auth/change-password" -Method Post -ContentType $j `
    -Headers @{ Authorization = "Bearer $($login.accessToken)" } `
    -Body ([Text.Encoding]::UTF8.GetBytes((@{ currentPassword = $pass; newPassword = $mid } | ConvertTo-Json -Compress)))
  $null = Invoke-RestMethod -Uri "$base/auth/change-password" -Method Post -ContentType $j `
    -Headers @{ Authorization = "Bearer $($a.accessToken)" } `
    -Body ([Text.Encoding]::UTF8.GetBytes((@{ currentPassword = $mid; newPassword = $pass } | ConvertTo-Json -Compress)))
  return $true
}
