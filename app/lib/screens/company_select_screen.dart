import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/company_providers.dart';
import '../core/session.dart';
import '../models.dart';
import '../core/theme.dart';

/// اختيار الشركة الفعّالة بعد الدخول — للسوبر أدمن ولكل مستخدمٍ مُسنَدٍ لأكثر من شركة.
///
/// 🎨 **أُعيد تصميمها بطلب المالك (2026-09-23)** لتطابق هويّة البرنامج: ترويسةٌ كحليّة بتدرّج
/// شاشة الدخول نفسه، و**كروتٌ مربّعة** بلون أسطح التطبيق (فتعمل نهاراً وليلاً) بدل
/// المستطيلات — شعارُ الشركة واسمُها ورمزُها، وإبرازٌ ذهبيّ عند المرور.
class CompanySelectScreen extends ConsumerStatefulWidget {
  const CompanySelectScreen({super.key});
  @override
  ConsumerState<CompanySelectScreen> createState() => _State();
}

/// تدرّج الترويسة — **هو تدرّج شاشة الدخول حرفياً** فلا تبدو الشاشتان من برنامجين.
/// ⚠️ **كحليٌّ في الوضعين عمداً** (نظير ما يقوله `AppColors.action` عن هذه الشاشة).
const _kHeroGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF0B1830), Color(0xFF0C1B33), Color(0xFF11264A)],
);

class _State extends ConsumerState<CompanySelectScreen> {
  late Future<List<Company>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(apiClientProvider).companies();
  }

  // ⚠️ **الجسمُ بأقواس لا بسهم**: `() => _future = …` يُعيد الـFuture نفسه من `setState`،
  //    وFlutter يرفض ذلك صراحةً — فيسقط زرّ «إعادة المحاولة» في اللحظة التي يُحتاج فيها.
  void _retry() {
    final next = ref.read(apiClientProvider).companies();
    setState(() {
      _future = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = ref.watch(sessionProvider).auth?.fullName ?? '';

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          // الترويسة الكحليّة — تمتدّ تحت أوّل الكروت فتتداخل معها قليلاً.
          const Positioned(
            top: 0, left: 0, right: 0, height: 300,
            child: DecoratedBox(decoration: BoxDecoration(gradient: _kHeroGradient)),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1040),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _TopBar(onLogout: () => ref.read(sessionProvider.notifier).logout()),
                      const SizedBox(height: 36),
                      _Greeting(name: name),
                      const SizedBox(height: 36),
                      FutureBuilder<List<Company>>(
                        future: _future,
                        builder: (context, snap) {
                          if (snap.connectionState != ConnectionState.done) {
                            return const Padding(
                              padding: EdgeInsets.all(48),
                              child: Center(child: CircularProgressIndicator(color: AppColors.gold)),
                            );
                          }
                          if (snap.hasError) {
                            return _Message(
                              icon: Icons.cloud_off_rounded,
                              text: 'تعذّر جلب الشركات:\n${snap.error}',
                              isError: true,
                              onRetry: _retry,
                            );
                          }

                          final companies = snap.data ?? [];
                          if (companies.isEmpty) {
                            // نظام فارغ: ادخل بلا شركة (بلا معرّف زائف) ليُنشئ السوبر أدمن أول شركة من الإعدادات.
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              ref.read(sessionProvider.notifier).enterWithoutCompany();
                            });
                            return const _Message(
                              icon: Icons.domain_add_rounded,
                              text: 'لا توجد شركات بعد — يمكنك إنشاء أول شركة من الإعدادات.',
                            );
                          }

                          return _CompanyGrid(
                            companies: companies,
                            onSelect: (c) =>
                                ref.read(sessionProvider.notifier).setActiveCompany(c.companyId),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// الشريط العلوي: هويّة البرنامج يميناً وتسجيل الخروج يساراً.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.onLogout});
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(13),
            boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 16)],
          ),
          child: const Icon(Icons.apartment_rounded, color: AppColors.navy, size: 28),
        ),
        const SizedBox(width: 12),
        // ⚠️ **`Expanded`** — فلا يدفع العنوانُ زرَّ الخروج خارج الشاشة على الهاتف.
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('نظام إدارة الوثائق',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17)),
              Text('DMS',
                  style: TextStyle(color: Color(0xFF9DB0D2), fontSize: 12, letterSpacing: 1.5)),
            ],
          ),
        ),
        OutlinedButton.icon(
          onPressed: onLogout,
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: BorderSide(color: AppColors.goldBright.withValues(alpha: 0.7)),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          icon: const Icon(Icons.logout_rounded, size: 18, color: AppColors.goldBright),
          label: const Text('تسجيل الخروج', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text('اختيار الشركة',
            style: TextStyle(
                color: AppColors.goldBright, fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 3)),
        const SizedBox(height: 10),
        Text(
          name.isEmpty ? 'مرحباً بك' : 'مرحباً، $name',
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        const Text(
          'اختر الشركة التي تريد العمل عليها.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFFA9BAD8), fontSize: 15),
        ),
      ],
    );
  }
}

/// شبكة الكروت — **مقاسُ الكرت يُحسب من العرض** ولا يُكتب رقماً ثابتاً (قاعدة المشروع).
///
/// عددُ الأعمدة ما يتّسع لكروتٍ بعرض ~220، و**كرتان على الأقل** في الهاتف ما دام لكلٍّ
/// منهما 140 بكسلاً فأكثر — فلا تصير الشاشة عموداً طويلاً من مربّعاتٍ ضخمة.
class _CompanyGrid extends StatelessWidget {
  const _CompanyGrid({required this.companies, required this.onSelect});

  final List<Company> companies;
  final ValueChanged<Company> onSelect;

  static const double _target = 220;
  static const double _gap = 20;
  static const double _minTwoUp = 140;

  static double cardSize(double available) {
    var count = ((available + _gap) / (_target + _gap)).floor();
    if (count < 2 && available >= 2 * _minTwoUp + _gap) count = 2;
    if (count < 1) count = 1;
    final size = (available - _gap * (count - 1)) / count;
    return size > _target ? _target : size;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final size = cardSize(c.maxWidth);
        return Wrap(
          alignment: WrapAlignment.center,
          spacing: _gap,
          runSpacing: _gap,
          children: [
            for (final co in companies)
              SizedBox(
                key: ValueKey('company-card-${co.companyId}'),
                width: size,
                height: size,
                child: _CompanyCard(company: co, size: size, onTap: () => onSelect(co)),
              ),
          ],
        );
      },
    );
  }
}

class _CompanyCard extends StatefulWidget {
  const _CompanyCard({required this.company, required this.size, required this.onTap});

  final Company company;
  final double size;
  final VoidCallback onTap;

  @override
  State<_CompanyCard> createState() => _CompanyCardState();
}

class _CompanyCardState extends State<_CompanyCard> {
  bool _hot = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // ⚠️ **لونٌ يعرف الوضع لا ثابت** — الذهبيّ الداكن يصير باهتاً على السطح الليلي (ADR-041).
    final gold = isDark ? AppColors.goldBrightDark : AppColors.gold;
    final s = widget.size;
    final logo = (s * 0.32).clamp(44.0, 72.0);
    // سطرُ «دخول» يظهر حين يتّسع الكرت له وحده — وفي الهاتف يكفي الكرتُ نفسه زرّاً.
    final showEnter = s >= 180;
    final logoUrl = companyLogoUrl(widget.company);

    return Semantics(
      button: true,
      label: 'الدخول إلى ${widget.company.name}',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _hot ? -4 : 0, 0),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _hot ? gold : theme.dividerColor,
            width: _hot ? 1.6 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: _hot
                  ? gold.withValues(alpha: isDark ? 0.25 : 0.30)
                  : (isDark ? Colors.black54 : const Color(0x220C1B33)),
              blurRadius: _hot ? 26 : 16,
              offset: const Offset(0, 8),
              spreadRadius: -6,
            ),
          ],
        ),
        // `Material` شفّاف ليرسم `InkWell` تموّجه داخل الكرت لا خلفه.
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: widget.onTap,
            onHover: (v) => setState(() => _hot = v),
            onFocusChange: (v) => setState(() => _hot = v),
            child: Padding(
              padding: EdgeInsets.all(s < 180 ? 12 : 18),
              child: Column(
                children: [
                  // شعار الشركة على بياضٍ دائماً — الشعارات تُصمَّم لخلفيةٍ فاتحة.
                  Container(
                    width: logo,
                    height: logo,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(logo * 0.26),
                      border: Border.all(color: gold.withValues(alpha: _hot ? 0.8 : 0.35)),
                    ),
                    padding: EdgeInsets.all(logo * 0.12),
                    child: logoUrl == null
                        ? Icon(Icons.apartment_rounded, color: AppColors.navy, size: logo * 0.55)
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(logo * 0.16),
                            child: Image.network(
                              logoUrl,
                              fit: BoxFit.contain,
                              // 🔴 فشلُ الشعار لا يُفرغ الكرت — نظيرُ صدر القائمة الجانبية.
                              errorBuilder: (_, _, _) => Icon(Icons.apartment_rounded,
                                  color: AppColors.navy, size: logo * 0.55),
                            ),
                          ),
                  ),
                  const Spacer(),
                  Text(
                    widget.company.name,
                    textAlign: TextAlign.center,
                    // ⚠️ **سطران وقصّ** — أسماء الشركات الرسمية طويلة.
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: s < 180 ? 14 : 16,
                      height: 1.3,
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: gold.withValues(alpha: isDark ? 0.16 : 0.14),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      widget.company.prefix,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11.5, fontWeight: FontWeight.bold, color: gold, letterSpacing: 0.8),
                    ),
                  ),
                  const Spacer(),
                  if (showEnter)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('دخول',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: _hot ? gold : AppColors.action(context),
                            )),
                        const SizedBox(width: 6),
                        // `arrow_forward` يتبع اتجاه النصّ — فيشير يساراً في العربية.
                        Icon(Icons.arrow_forward_rounded,
                            size: 16, color: _hot ? gold : AppColors.action(context)),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// رسالةٌ داخل بطاقة — للخطأ (مع «إعادة المحاولة») وللنظام الفارغ.
class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.isError = false, this.onRetry});

  final IconData icon;
  final String text;
  final bool isError;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final color = isError
        ? (isDark ? AppColors.dangerDark : AppColors.danger)
        : theme.colorScheme.onSurface;

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 460),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: color),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: TextStyle(color: color, fontSize: 15, height: 1.6)),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.action(context),
                  foregroundColor: AppColors.onAction(context),
                ),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
