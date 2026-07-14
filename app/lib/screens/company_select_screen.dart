import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/session.dart';
import '../models.dart';
import '../core/theme.dart';
import '../widgets/custom_card.dart';

/// اختيار الشركة الفعّالة (للسوبر أدمن فقط) قبل الدخول للنظام.
class CompanySelectScreen extends ConsumerStatefulWidget {
  const CompanySelectScreen({super.key});
  @override
  ConsumerState<CompanySelectScreen> createState() => _State();
}

class _State extends ConsumerState<CompanySelectScreen> {
  late Future<List<Company>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(apiClientProvider).companies();
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = Theme.of(context).scaffoldBackgroundColor;
    
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('نظام إدارة الوثائق (DMS)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        centerTitle: true,
        backgroundColor: AppColors.navyDeep,
        elevation: 0,
        actions: [
          TextButton.icon(
            onPressed: () => ref.read(sessionProvider.notifier).logout(),
            icon: const Icon(Icons.logout_rounded, color: AppColors.gold, size: 20),
            label: const Text('تسجيل خروج', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.navyDeep, bgColor],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const [0.0, 0.4],
          ),
        ),
        child: FutureBuilder<List<Company>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator(color: AppColors.gold));
            }
            if (snap.hasError) {
              return Center(
                child: CustomCard(
                  padding: const EdgeInsets.all(24),
                  child: Text('حدث خطأ أثناء جلب الشركات:\n${snap.error}', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger)),
                ),
              );
            }
            
            final companies = snap.data ?? [];
            
            if (companies.isEmpty) {
              // نظام فارغ: ادخل بلا شركة (بلا معرّف زائف) ليُنشئ السوبر أدمن أول شركة من الإعدادات.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                ref.read(sessionProvider.notifier).enterWithoutCompany();
              });
              return const Center(
                child: Text(
                  'لا توجد شركات بعد — يمكنك إنشاء أول شركة من الإعدادات.',
                  style: TextStyle(color: Colors.white, fontSize: 18),
                  textAlign: TextAlign.center,
                ),
              );
            }
            
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.business_center_rounded, size: 80, color: AppColors.gold),
                      const SizedBox(height: 16),
                      const Text(
                        'مرحباً بك!',
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'يرجى اختيار الشركة التي تود الدخول إليها لإدارة أعمالك.',
                        style: TextStyle(fontSize: 16, color: Colors.white70),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 48),
                      ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: companies.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 16),
                          itemBuilder: (context, i) {
                            final c = companies[i];
                            return _CompanyCard(
                              company: c,
                              onTap: () => ref.read(sessionProvider.notifier).setActiveCompany(c.companyId),
                            );
                          },
                        ),
                        
                      const SizedBox(height: 48),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CompanyCard extends StatefulWidget {
  final Company company;
  final VoidCallback onTap;

  const _CompanyCard({required this.company, required this.onTap});

  @override
  State<_CompanyCard> createState() => _CompanyCardState();
}

class _CompanyCardState extends State<_CompanyCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          transform: Matrix4.translationValues(0, _isHovered ? -4 : 0, 0),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: _isHovered ? AppColors.gold.withValues(alpha: 0.3) : Colors.black12,
                blurRadius: _isHovered ? 20 : 10,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(
              color: _isHovered ? AppColors.gold : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.navyDeep.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.corporate_fare_rounded, size: 32, color: AppColors.navyDeep),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.company.name,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.navyDeep),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.gold.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'الرمز: ${widget.company.prefix}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.gold),
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: EdgeInsets.only(right: _isHovered ? 8 : 0),
                  child: const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.gold, size: 20),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
