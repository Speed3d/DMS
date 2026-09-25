import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api_client.dart';
import '../core/app_version.dart';
import '../core/remembered_user.dart';
import '../core/session.dart';
import '../core/system_status.dart';
import '../models.dart';
import '../widgets/password_field.dart';
import '../core/theme.dart';

/// Hint: شاشة تسجيل الدخول بتصميم مقسوم (Split Screen) للشاشات العريضة
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _user = TextEditingController(text: '');
  final _pass = TextEditingController();
  bool _busy = false;
  String? _error;
  /// «تذكّرني» — **مؤشَّرٌ إن كان للجهاز اسمٌ محفوظ**، وإلا فلا: جهازٌ عامّ لا يحفظ اسماً بلا طلب.
  bool _rememberMe = false;

  /// أثناء الإيقاف: أظهر المسؤولُ نموذجَ الدخول برابط «دخول المسؤول» (ADR-050).
  bool _adminMode = false;

  @override
  void initState() {
    super.initState();
    // 🔑 **الاسم المحفوظ يملأ الحقل** — والتركيز لكلمة المرور تلقائياً بعده.
    RememberedUser.load().then((name) {
      if (!mounted || name == null || _user.text.isNotEmpty) return;
      setState(() {
        _user.text = name;
        _rememberMe = true;
      });
    });
  }

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  /// «نسيت كلمة المرور» — يشرح الطريق الموجود فعلاً (قرار المالك 2026-09-24).
  void _showForgotPassword() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.lock_reset_rounded, color: AppColors.action(ctx), size: 36),
        title: const Text('نسيت كلمة المرور؟'),
        content: const Text(
          'تواصل مع مدير النظام ليعيّن لك كلمة مرورٍ مؤقتة.\n'
          'وعند أوّل دخولٍ بها سيُطلب منك اختيار كلمةٍ جديدة خاصّة بك.',
          style: TextStyle(height: 1.8),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.action(ctx),
              foregroundColor: AppColors.onAction(ctx),
            ),
            child: const Text('حسناً'),
          ),
        ],
      ),
    );
  }

  Future<void> _login() async {
    if (_user.text.trim().isEmpty || _pass.text.isEmpty) return;
    setState(() { _busy = true; _error = null; });
    try {
      final api = ref.read(apiClientProvider);
      final result = await api.login(_user.text.trim(), _pass.text);
      // ⚠️ **قبل `setAuth`** — بعده تُستبدل الشاشة فلا يبقى مَن يحفظ. **وبعد نجاح الدخول وحده**:
      //    اسمٌ خاطئ لا يُحفظ.
      await RememberedUser.afterLogin(_user.text, remember: _rememberMe);
      await ref.read(sessionProvider.notifier).setAuth(result);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'تعذّر تسجيل الدخول. تأكد من تشغيل الخادم.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 800) {
            // Hint: شاشات سطح المكتب والويب (مقسمة لجزئين)
            return Row(
              children: [
                Expanded(flex: 11, child: _buildHeroSection()),
                Expanded(flex: 9, child: _buildLoginSection()),
              ],
            );
          }
          // Hint: شاشات الموبايل (نضع بطاقة الدخول فوق الخلفية الزرقاء)
          return Stack(
            children: [
              Positioned.fill(child: _buildHeroSection()),
              Positioned.fill(
                child: Container(color: Colors.black.withValues(alpha: 0.4)),
              ),
              Center(child: _buildLoginCard()),
            ],
          );
        },
      ),
    );
  }

  // Hint: القسم الأيمن (الترحيب والمميزات)
  Widget _buildHeroSection() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0B1830),
            Color(0xFF0C1B33),
            Color(0xFF11264A),
          ],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 72, vertical: 64),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 20)],
                  ),
                  padding: const EdgeInsets.all(5),
                  // Hint: يمكن لاحقاً وضع لوغو الشركة الحقيقي هنا
                  child: const Icon(Icons.apartment, color: AppColors.navy, size: 32),
                ),
                const SizedBox(width: 14),
                // ⚠️ **مرِنٌ لا بعرضه الطبيعيّ**: كان يفيض 184 بكسلاً على هاتفٍ بعرض 360
                //    (الحشوة 72 من كل جهة) — كشفه حارسُ `review_gaps_test`.
                const Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('DMS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20, letterSpacing: 0.5)),
                      Text('Document Management System',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Color(0xFF9DB0D2), fontSize: 12.5)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 54),
            const Text('نظام إدارة الوثائق الإلكتروني', style: TextStyle(color: AppColors.goldBright, fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 3)),
            const SizedBox(height: 14),
            RichText(
              text: const TextSpan(
                style: TextStyle(fontFamily: 'Cairo', fontSize: 46, height: 1.18, fontWeight: FontWeight.w900, color: Colors.white),
                children: [
                  TextSpan(text: 'إدارة '),
                  TextSpan(text: 'الصادر والأرشيف\n', style: TextStyle(color: AppColors.goldBright)),
                  TextSpan(text: 'باحترافية وأمان'),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'إنشاء الكتب الرسمية، توليد PDF مع رمز QR موقّع رقمياً، أرشفة ذكية وتقارير مالية دقيقة — في منصّة واحدة متعددة الشركات.',
              style: TextStyle(color: Color(0xFFA9BAD8), fontSize: 16, height: 1.9),
            ),
            const SizedBox(height: 40),
            Wrap(
              spacing: 40,
              runSpacing: 24,
              children: [
                _buildFeature('QR موقّع', 'غير قابل للتزوير'),
                _buildFeature('متعدد الشركات', 'عزل بيانات كامل'),
                _buildFeature('سحابي', 'الوصول من أي مكان'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeature(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
        Text(subtitle, style: const TextStyle(color: Color(0xFF8FA3C6), fontSize: 13)),
      ],
    );
  }

  // Hint: القسم الأيسر (منطقة الفورم)
  Widget _buildLoginSection() {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(40),
          child: _buildLoginCard(),
        ),
      ),
    );
  }

  // Hint: بطاقة تسجيل الدخول
  Widget _buildLoginCard() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final lockdown = ref.watch(systemStatusProvider).lockdown;

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black54 : const Color(0x6B0C1B33),
            blurRadius: 64,
            offset: const Offset(0, 32),
            spreadRadius: -28,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Column(
              children: [
                Text('تسجيل الدخول', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: theme.textTheme.bodyMedium?.color)),
                const SizedBox(height: 6),
                Text('مرحباً بعودتك، أدخل بياناتك للمتابعة', style: TextStyle(fontSize: 13.5, color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6))),
              ],
            ),
          ),
          const SizedBox(height: 26),

          // ⏸️ **النظام موقوف (ADR-050)**: رسالة المالك مكان النموذج — فلا يكتب الموظف كلمة
          //    مروره ليُردّ بعدها. ورابطٌ صغير للمسؤول يُظهر النموذج.
          if (lockdown.active && !_adminMode) ...[
            _buildLockdownNotice(theme, lockdown),
            const SizedBox(height: 18),
            Center(
              child: TextButton(
                onPressed: () => setState(() => _adminMode = true),
                child: Text('دخول المسؤول',
                    style: TextStyle(fontSize: 12.5, color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.55))),
              ),
            ),
          ] else ...[
          if (lockdown.active) ...[
            _buildLockdownNotice(theme, lockdown, compact: true),
            const SizedBox(height: 18),
          ],
          _buildLabel('اسم المستخدم'),
          const SizedBox(height: 8),
          TextField(
            controller: _user,
            decoration: _inputDecoration(theme, Icons.person_outline),
          ),
          const SizedBox(height: 18),
          
          _buildLabel('كلمة المرور'),
          const SizedBox(height: 8),
          PasswordField(
            controller: _pass,
            onSubmitted: (_) => _login(),
            decoration: _inputDecoration(theme, Icons.lock_outline),
          ),
          const SizedBox(height: 14),

          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: AppColors.danger, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13, fontWeight: FontWeight.w700))),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Checkbox(
                    value: _rememberMe,
                    onChanged: (v) => setState(() => _rememberMe = v ?? true),
                    activeColor: AppColors.gold,
                  ),
                  Text('تذكّرني', style: TextStyle(fontSize: 13, color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6))),
                ],
              ),
              // ⚠️ **كان `onPressed: () {}`** — ثامنُ «زرٍّ بلا وظيفة» (ADR-053). والنظام لا يرسل
              //    بريداً ولا رسائل، فالطريق الوحيد إعادةُ تعيينٍ بيد المدير (كلمةٌ مؤقتة يُجبَر
              //    صاحبها على تغييرها — G19). فالزرّ يقول ذلك بدل أن يَعِد بما لا يوجد.
              //    ⚠️ **ومرِنٌ داخل السطر**: كان يفيض 31 بكسلاً حين يتّسع الخطّ (هاتفٌ ضيّق ·
              //    تكبيرُ الخطّ) — كشفه حارسُ هذا الزرّ نفسه.
              Flexible(
                child: TextButton(
                  key: const Key('forgot-password'),
                  onPressed: _showForgotPassword,
                  child: Text('نسيت كلمة المرور؟',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: isDark ? AppColors.navyDark : AppColors.navy, fontWeight: FontWeight.w700, fontSize: 13)),
                ),
              )
            ],
          ),
          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _busy ? null : _login,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.action(context),
                foregroundColor: AppColors.onAction(context),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 14,
                shadowColor: AppColors.action(context).withValues(alpha: 0.8),
              ),
              child: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: AppColors.gold, strokeWidth: 2))
                  : const Text('دخول إلى النظام', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
            ),
          ),
          ],
          const SizedBox(height: 22),
          Center(
            child: Text('جميع كلمات المرور محمية ومشفرة بالكامل', style: TextStyle(fontSize: 12, color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.4))),
          ),
          const SizedBox(height: 6),
          // 🏷️ إصدار الواجهة (ADR-054) — **الواجهة وحدها**: الخادم لا يكشف إصداره لغير المسجَّل.
          Center(
            child: Text(appVersionLabel(),
                key: const Key('login-version'),
                style: TextStyle(fontSize: 11, color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.35))),
          ),
        ],
      ),
    );
  }

  /// بطاقة رسالة الإيقاف على شاشة الدخول.
  Widget _buildLockdownNotice(ThemeData theme, LockdownInfo lockdown, {bool compact = false}) {
    final isDark = theme.brightness == Brightness.dark;
    final accent = isDark ? AppColors.warnDark : AppColors.warn;
    return Container(
      key: const Key('login-lockdown-notice'),
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 12 : 18),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.construction_rounded, color: accent, size: compact ? 20 : 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(compact ? 'النظام متوقّف عن المستخدمين' : 'النظام متوقّف مؤقتاً',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: compact ? 13 : 16, color: accent)),
                const SizedBox(height: 6),
                Text(
                  compact ? 'الدخول الآن للسوبر أدمن وحده.' : (lockdown.message ?? 'سيعود النظام قريباً.'),
                  style: TextStyle(fontSize: compact ? 12.5 : 14, height: 1.6, color: theme.textTheme.bodyMedium?.color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.6)));
  }

  InputDecoration _inputDecoration(ThemeData theme, IconData icon) {
    return InputDecoration(
      filled: true,
      fillColor: theme.colorScheme.surfaceContainerHighest, // surface-2
      prefixIcon: Icon(icon, color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.4)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: theme.dividerColor, width: 1.5)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: theme.dividerColor, width: 1.5)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.gold, width: 2)),
    );
  }
}
