import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../widgets/custom_card.dart';

/// Hint: إعدادات وحدة الموظفين والرواتب — أيام العمل الافتراضية ومكافأة نهاية الخدمة.
class HrSettingsScreen extends ConsumerStatefulWidget {
  const HrSettingsScreen({super.key});
  @override
  ConsumerState<HrSettingsScreen> createState() => _HrSettingsScreenState();
}

class _HrSettingsScreenState extends ConsumerState<HrSettingsScreen> {
  String _mode = 'Fixed';
  final _days = TextEditingController(text: '30');
  bool _eosEnabled = false;
  String _eosRatio = 'MonthPerYear';
  final _eosDays = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _days.dispose();
    _eosDays.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await ref.read(apiClientProvider).hrSettings();
      if (!mounted) return;
      setState(() {
        _mode = s.defaultWorkingDaysMode;
        _days.text = '${s.defaultWorkingDays}';
        _eosEnabled = s.endOfServiceEnabled;
        _eosRatio = s.endOfServiceRatio;
        _eosDays.text = s.endOfServiceCustomDays?.toString() ?? '';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(apiClientProvider).updateHrSettings(
            _mode,
            int.tryParse(_days.text.trim()) ?? 30,
            endOfServiceEnabled: _eosEnabled,
            endOfServiceRatio: _eosRatio,
            endOfServiceCustomDays:
                _eosRatio == 'CustomDays' ? int.tryParse(_eosDays.text.trim()) : null,
          );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('حُفظت إعدادات الموظفين.')));
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canManage = ref.watch(sessionProvider).canManagePayroll;

    if (_loading) return const Center(child: CircularProgressIndicator());

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (_error != null) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
            ),
            child: Text(_error!,
                style: const TextStyle(fontSize: 13, color: AppColors.danger, height: 1.6)),
          ),
          const SizedBox(height: 16),
        ],

        CustomCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(children: [
                Icon(Icons.event_note_rounded, size: 20, color: AppColors.gold),
                SizedBox(width: 10),
                Text('أيام العمل الافتراضية',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
              ]),
              const SizedBox(height: 6),
              Text('تُطبَّق على كل شهر جديد عند توليده — ويمكن تغييرها داخل الكشف نفسه.',
                  style: TextStyle(
                      fontSize: 12.5,
                      height: 1.6,
                      color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6))),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _mode,
                decoration: InputDecoration(
                  labelText: 'الوضع',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                items: const [
                  DropdownMenuItem(value: 'Fixed', child: Text('ثابت (30 يوماً عرفاً)')),
                  DropdownMenuItem(value: 'Calendar', child: Text('تقويمي (أيام الشهر الحقيقية)')),
                ],
                onChanged: canManage ? (v) => setState(() => _mode = v!) : null,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _days,
                enabled: canManage && _mode == 'Fixed',
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'عدد الأيام',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        CustomCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(children: [
                Icon(Icons.workspace_premium_rounded, size: 20, color: AppColors.gold),
                SizedBox(width: 10),
                Text('مكافأة نهاية الخدمة',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
              ]),
              const SizedBox(height: 6),
              Text(
                  'حين تُفعَّل، يقترح النظام مكافأةً لمن انتهت خدمته في الشهر — '
                  '**اقتراحٌ لا يُطبَّق تلقائياً**، تراجعه وتقرّه بنفسك قبل التسديد.\n'
                  'وأجر اليوم يُحسب على أساس شهرٍ من 30 يوماً دائماً (عرف تعاقدي)، '
                  'فلا تختلف مكافأة موظفَين متطابقَين باختلاف طول شهر الإنهاء.',
                  style: TextStyle(
                      fontSize: 12.5,
                      height: 1.7,
                      color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6))),
              const SizedBox(height: 8),
              // ⚠️ **`Material` شفّافة حول `SwitchListTile` داخل `CustomCard`:** البطاقة
              //    `DecoratedBox` ذات خلفية، و`ListTile` يرسم خلفيته وأثر النقر على أقرب
              //    `Material` **فوقه** — فتحجبهما البطاقة، ويرمي Flutter تأكيداً:
              //    «ListTile background color or ink splashes may be invisible».
              //    الشفافة لا تغيّر المظهر وتُعطي الأثر سطحاً يرتسم عليه (بلاغ المالك).
              Material(
                type: MaterialType.transparency,
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _eosEnabled,
                  title: const Text('تفعيل مكافأة نهاية الخدمة',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  onChanged: canManage ? (v) => setState(() => _eosEnabled = v) : null,
                ),
              ),
              if (_eosEnabled) ...[
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: _eosRatio,
                  decoration: InputDecoration(
                    labelText: 'النسبة عن كل سنة خدمة',
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'MonthPerYear', child: Text('راتب شهر (30 يوماً)')),
                    DropdownMenuItem(value: 'HalfMonthPerYear', child: Text('نصف شهر (15 يوماً)')),
                    DropdownMenuItem(value: 'CustomDays', child: Text('عدد أيام مخصّص')),
                  ],
                  onChanged: canManage ? (v) => setState(() => _eosRatio = v!) : null,
                ),
                if (_eosRatio == 'CustomDays') ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: _eosDays,
                    enabled: canManage,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: 'الأيام المستحقّة عن كل سنة',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),

        SizedBox(
          height: 48,
          child: ElevatedButton.icon(
            onPressed: (_saving || !canManage) ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_rounded),
            label: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ الإعدادات',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.navyDeep,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 8,
              shadowColor: AppColors.navyDeep.withValues(alpha: 0.5),
            ),
          ),
        ),
        if (!canManage)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('لا تملك صلاحية إدارة الموظفين — العرض فقط.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12.5,
                    color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6))),
          ),
      ],
    );
  }
}
