import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../models.dart';
import '../widgets/custom_card.dart';
import '../widgets/status_pill.dart';

/// Hint: شاشة لوحة التحكم (Dashboard) الرئيسية مع الرسوم البيانية والإحصائيات
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});
  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  late Future<List<OutgoingListItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(apiClientProvider).outgoingList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<OutgoingListItem>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: AppColors.gold));
          }
          if (snap.hasError) {
            return Center(child: Text('حدث خطأ: ${snap.error}', style: const TextStyle(color: AppColors.danger)));
          }
          final items = snap.data ?? [];
          final drafts = items.where((e) => e.status.toLowerCase().contains('draft')).length;
          final finals = items.where((e) => e.status.toLowerCase().contains('final')).length;
          final totalIqd = items.fold<num>(0, (a, e) => a + (e.amountInIqd ?? 0));

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
                        SizedBox(width: cardWidth, child: _buildStatCard('بانتظار الاعتماد', '$drafts', Icons.pending_actions_rounded, AppColors.warn)),
                        SizedBox(width: cardWidth, child: _buildStatCard('كتب معتمدة', '$finals', Icons.verified_rounded, AppColors.success)),
                        SizedBox(width: cardWidth, child: _buildStatCard('إجمالي المبالغ', '${_fmt(totalIqd)} د.ع', Icons.payments_rounded, AppColors.gold)),
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
                            child: _buildChart(),
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
  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
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
  Widget _buildChart() {
    final theme = Theme.of(context);
    
    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 10,
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
              interval: 10,
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
        maxY: 40,
        lineBarsData: [
          // الخط الأول (المسودات)
          LineChartBarData(
            spots: const [
              FlSpot(0, 12), FlSpot(1, 15), FlSpot(2, 22), FlSpot(3, 18),
              FlSpot(4, 28), FlSpot(5, 10), FlSpot(6, 14),
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
            spots: const [
              FlSpot(0, 5), FlSpot(1, 10), FlSpot(2, 18), FlSpot(3, 25),
              FlSpot(4, 20), FlSpot(5, 8), FlSpot(6, 11),
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
