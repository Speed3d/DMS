import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../core/outgoing_providers.dart';
import '../core/theme.dart';
import '../models.dart';
import '../widgets/custom_card.dart';
import '../widgets/status_pill.dart';

/// Hint: شاشة لوحة التحكم (Dashboard) الرئيسية مع الرسوم البيانية والإحصائيات
class DashboardScreen extends ConsumerStatefulWidget {
  final ValueChanged<int>? onNavigate;
  const DashboardScreen({super.key, this.onNavigate});
  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  @override
  Widget build(BuildContext context) {
    final async = ref.watch(outgoingListProvider);
    return Scaffold(
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.gold)),
        error: (e, _) => Center(child: Text('حدث خطأ: $e', style: const TextStyle(color: AppColors.danger))),
        data: (items) {
          final drafts = items.where((e) => e.status.toLowerCase().contains('draft')).length;
          final finals = items.where((e) => e.status.toLowerCase().contains('final')).length;
          // إجمالي المبالغ = الكتب المعتمدة فقط (Final).
          final totalIqd = items
              .where((e) => e.status.toLowerCase().contains('final'))
              .fold<num>(0, (a, e) => a + (e.amountInIqd ?? 0));

          return SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Hint: البطاقات الإحصائية العلوية
                LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    int crossAxisCount = 4;
                    if (width < 500) {
                      crossAxisCount = 1;
                    } else if (width < 900) {
                      crossAxisCount = 2;
                    }
                    
                    final double spacing = 24.0;
                    final double totalSpacing = spacing * (crossAxisCount - 1);
                    final double cardWidth = (width - totalSpacing) / crossAxisCount;

                    return Wrap(
                      spacing: spacing,
                      runSpacing: spacing,
                      children: [
                        SizedBox(width: cardWidth, child: _buildStatCard('إجمالي الصادر', '${items.length}', Icons.outbox_rounded, const Color(0xFF3B82F6))),
                        SizedBox(width: cardWidth, child: _buildStatCard('بانتظار الاعتماد', '$drafts', Icons.pending_actions_rounded, AppColors.warn, onTap: () => widget.onNavigate?.call(2))),
                        SizedBox(width: cardWidth, child: _buildStatCard('كتب معتمدة', '$finals', Icons.verified_rounded, AppColors.success)),
                        SizedBox(width: cardWidth, child: _buildStatCard('إجمالي المعتمد', '${_fmt(totalIqd)} د.ع', Icons.payments_rounded, AppColors.gold)),
                      ],
                    );
                  }
                ),
                const SizedBox(height: 32),

                // Hint: القسم الأوسط (الرسوم البيانية + نشاطات أخيرة)
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isSmall = constraints.maxWidth < 900;
                    
                    final chartCard = CustomCard(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('نشاط الصادر (الأسبوع الحالي)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          Text('مقارنة بين المسودات والكتب المعتمدة يومياً', style: TextStyle(fontSize: 13, color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.6))),
                          const SizedBox(height: 32),
                          SizedBox(
                            height: 300,
                            child: _buildChart(items),
                          ),
                        ],
                      ),
                    );

                    final activitiesCard = CustomCard(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Flexible(child: Text('أحدث الكتب', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                              TextButton(onPressed: (){}, child: const Text('عرض الكل', style: TextStyle(color: AppColors.gold))),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // عرض آخر 5 كتب
                          ...items.take(5).map((e) => _buildActivityItem(e)),
                          if (items.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(24),
                              child: Center(child: Text('لا توجد بيانات حالياً')),
                            ),
                        ],
                      ),
                    );

                    if (isSmall) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          chartCard,
                          const SizedBox(height: 24),
                          activitiesCard,
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 7, child: chartCard),
                        const SizedBox(width: 24),
                        Expanded(flex: 4, child: activitiesCard),
                      ],
                    );
                  }
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // Hint: تصميم بطاقة الإحصائيات (زجاجية ومضيئة)
  Widget _buildStatCard(String title, String value, IconData icon, Color color, {VoidCallback? onTap}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final card = Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor, width: 1.5),
        boxShadow: [
          // ظل ناعم جداً ولونه مأخوذ من لون الأيقونة ليعطي إحساساً بالإضاءة
          BoxShadow(
            color: color.withValues(alpha: isDark ? 0.15 : 0.08),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    value,
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, fontFamily: 'Tahoma', letterSpacing: -0.5),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    title,
                    style: TextStyle(fontSize: 13, color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6), fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: card,
      );
    }
    return card;
  }

  // Hint: تصميم عنصر النشاطات (القائمة المصغرة)
  Widget _buildActivityItem(OutgoingListItem item) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isVerySmall = constraints.maxWidth < 180;
          return Row(
            children: [
              if (!isVerySmall) ...[
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.description_outlined, size: 18, color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6)),
                ),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.subject, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text(item.number ?? 'بلا رقم', style: TextStyle(fontSize: 11, color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.5))),
                  ],
                ),
              ),
              if (!isVerySmall) ...[
                const SizedBox(width: 8),
                StatusPill(status: item.status),
              ],
            ],
          );
        }
      ),
    );
  }

  // Hint: رسم بياني باستخدام حزمة fl_chart
  Widget _buildChart(List<OutgoingListItem> items) {
    final theme = Theme.of(context);
    
    // حساب بداية الأسبوع (الأحد)
    DateTime now = DateTime.now();
    int daysSinceSunday = now.weekday == 7 ? 0 : now.weekday;
    DateTime startOfWeek = DateTime(now.year, now.month, now.day).subtract(Duration(days: daysSinceSunday));
    DateTime endOfWeek = startOfWeek.add(const Duration(days: 7));

    final List<int> draftsPerDay = List.filled(7, 0);
    final List<int> finalsPerDay = List.filled(7, 0);
    int maxCount = 4;

    for (final item in items) {
      if (item.date.isAfter(startOfWeek.subtract(const Duration(milliseconds: 1))) && item.date.isBefore(endOfWeek)) {
        int dayIndex = item.date.weekday == 7 ? 0 : item.date.weekday;
        if (item.status.toLowerCase().contains('draft')) {
          draftsPerDay[dayIndex]++;
        } else {
          finalsPerDay[dayIndex]++;
        }
      }
    }

    for (int i = 0; i < 7; i++) {
      if (draftsPerDay[i] > maxCount) maxCount = draftsPerDay[i];
      if (finalsPerDay[i] > maxCount) maxCount = finalsPerDay[i];
    }
    
    final maxY = ((maxCount / 5).ceil() + 1) * 5.0;
    
    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: (maxY / 5).clamp(1, double.infinity).toDouble(),
          getDrawingHorizontalLine: (value) => FlLine(
            color: theme.dividerColor,
            strokeWidth: 1,
            dashArray: [5, 5],
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: 1,
              getTitlesWidget: (value, meta) {
                const days = ['الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];
                if (value.toInt() >= 0 && value.toInt() < days.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(days[value.toInt()], style: TextStyle(fontSize: 12, color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.5))),
                  );
                }
                return const SizedBox();
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: (maxY / 5).clamp(1, double.infinity).toDouble(),
              reservedSize: 42,
              getTitlesWidget: (value, meta) {
                return Text(value.toInt().toString(), style: TextStyle(fontSize: 12, color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.5)));
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        minX: 0,
        maxX: 6,
        minY: 0,
        maxY: maxY,
        lineBarsData: [
          // الخط الأول (المسودات)
          LineChartBarData(
            spots: [
              for (int i = 0; i < 7; i++) FlSpot(i.toDouble(), draftsPerDay[i].toDouble())
            ],
            isCurved: true,
            color: AppColors.warn,
            barWidth: 4,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: AppColors.warn.withValues(alpha: 0.1),
            ),
          ),
          // الخط الثاني (المعتمدة)
          LineChartBarData(
            spots: [
              for (int i = 0; i < 7; i++) FlSpot(i.toDouble(), finalsPerDay[i].toDouble())
            ],
            isCurved: true,
            color: AppColors.success,
            barWidth: 4,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: AppColors.success.withValues(alpha: 0.1),
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(num n) {
    final s = n.toStringAsFixed(0);
    return s.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
  }
}
