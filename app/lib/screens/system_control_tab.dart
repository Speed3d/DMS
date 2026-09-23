import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/api_client.dart';
import '../core/session.dart';
import '../core/system_status.dart';
import '../core/theme.dart';
import '../models.dart';
import '../widgets/custom_card.dart';
import '../widgets/system_shell.dart';

/// تبويب «النظام» في الإعدادات — **للسوبر أدمن وحده** (ADR-050).
///
/// قسمان مستقلّان بقرار المالك: **إيقاف النظام** (يحجب الجميع عداه) و**شريط الإعلان**
/// (نصٌّ يظهر أعلى الشاشات بلا حجب). ولكلٍّ **نصوصُه المحفوظة** يكتبها المالك ويعيد استعمالها.
class SystemControlTab extends ConsumerStatefulWidget {
  const SystemControlTab({super.key});

  @override
  ConsumerState<SystemControlTab> createState() => _SystemControlTabState();
}

class _SystemControlTabState extends ConsumerState<SystemControlTab> {
  final _lockMsg = TextEditingController();
  final _annText = TextEditingController();
  AnnouncementKind _kind = AnnouncementKind.info;

  SystemControlInfo? _info;
  String? _loadError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
    // المعاينة وزرُّ «احفظ هذا النصّ» يتبعان الكتابة.
    _annText.addListener(() => setState(() {}));
    _lockMsg.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _lockMsg.dispose();
    _annText.dispose();
    super.dispose();
  }

  ApiClient get _api => ref.read(apiClientProvider);

  Future<void> _load() async {
    try {
      final info = await _api.systemControl();
      if (!mounted) return;
      setState(() {
        _info = info;
        _loadError = null;
        _lockMsg.text = info.lockdown.message ?? '';
        _annText.text = info.announcement.text ?? '';
        _kind = info.announcement.kind;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    }
  }

  /// ينفّذ عمليةً ثم يحدّث اللوحة **وحالةَ النظام فوراً** (فيظهر الشريط أو يختفي الآن).
  Future<void> _run(Future<SystemControlInfo> Function() op, String done) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final info = await op();
      if (!mounted) return;
      setState(() => _info = info);
      await ref.read(systemStatusProvider.notifier).check();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message), backgroundColor: AppColors.danger));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String body, String action, {bool danger = false}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body, style: const TextStyle(height: 1.7)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(
            style: danger
                ? FilledButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white)
                : null,
            onPressed: () => Navigator.pop(c, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  // ───────────── الإيقاف ─────────────

  Future<void> _lock() async {
    if (_lockMsg.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('اكتب الرسالة التي سيراها المستخدمون أولاً.')));
      return;
    }
    final ok = await _confirm(
      'إيقاف النظام عن المستخدمين؟',
      'سيُحجب كل المستخدمين في كل الشركات خلال نصف دقيقة، وتظهر لهم رسالتك.\n'
          'أنت وحدك (السوبر أدمن) تبقى تتصفّح النظام.\n\n'
          'ولا يعود النظام للعمل وحده — تشغّله أنت من هنا أو من الشريط الأحمر.',
      'أوقف النظام',
      danger: true,
    );
    if (!ok) return;
    await _run(() => _api.setLockdown(active: true, message: _lockMsg.text.trim()), 'أُوقف النظام عن المستخدمين.');
  }

  Future<void> _updateLockMessage() =>
      _run(() => _api.setLockdown(active: true, message: _lockMsg.text.trim()), 'حُدّثت رسالة الإيقاف.');

  Future<void> _unlock() async {
    final ok = await _confirm('تشغيل النظام للجميع؟', 'سيعود كل المستخدمين إلى النظام خلال نصف دقيقة.', 'تشغيل');
    if (!ok) return;
    await _run(() => _api.setLockdown(active: false), 'النظام يعمل للجميع.');
  }

  // ───────────── الشريط ─────────────

  Future<void> _showAnnouncement() async {
    if (_annText.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اكتب نصّ الشريط أولاً.')));
      return;
    }
    final wasVisible = _info?.announcement.visible ?? false;
    await _run(() => _api.setAnnouncement(visible: true, text: _annText.text.trim(), kind: _kind),
        wasVisible ? 'حُدّث الشريط.' : 'ظهر الشريط للجميع.');
  }

  Future<void> _hideAnnouncement() =>
      _run(() => _api.setAnnouncement(visible: false, text: _annText.text.trim(), kind: _kind), 'أُخفي الشريط.');

  // ───────────── النصوص المحفوظة ─────────────

  Future<void> _saveText({required bool lockdown}) async {
    final t = (lockdown ? _lockMsg : _annText).text.trim();
    if (t.isEmpty) return;
    await _run(() => _api.addSavedText(lockdown: lockdown, text: t), 'حُفظ النصّ.');
  }

  Future<void> _removeText({required bool lockdown, required String text}) =>
      _run(() => _api.removeSavedText(lockdown: lockdown, text: text), 'حُذف النصّ.');

  @override
  Widget build(BuildContext context) {
    final info = _info;
    if (info == null) {
      return Center(
        child: _loadError == null
            ? const CircularProgressIndicator()
            : Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_loadError!),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: _load, child: const Text('إعادة المحاولة')),
              ]),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _lockdownCard(info),
        const SizedBox(height: 16),
        _announcementCard(info),
      ],
    );
  }

  Widget _lockdownCard(SystemControlInfo info) {
    final theme = Theme.of(context);
    final l = info.lockdown;
    final dark = theme.brightness == Brightness.dark;
    final statusColor = l.active ? (dark ? AppColors.dangerDark : AppColors.danger) : (dark ? AppColors.successDark : AppColors.success);
    final since = l.since == null ? null : DateTime.now().toUtc().difference(l.since!);

    return CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(Icons.power_settings_new_rounded, 'إيقاف النظام عن المستخدمين',
              'للصيانة أو لتنزيل تحديث — يُحجب الجميع عداك، ويرون رسالتك.'),
          const SizedBox(height: 14),
          Container(
            key: const Key('lockdown-status'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(children: [
              Icon(l.active ? Icons.pause_circle_filled_rounded : Icons.check_circle_rounded, color: statusColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l.active
                      ? 'موقوف${since == null ? '' : ' منذ ${arabicDuration(since)}'}'
                          '${l.since == null ? '' : ' (${DateFormat('yyyy/MM/dd HH:mm').format(l.since!.toLocal())})'}'
                          '${l.byName == null ? '' : ' — أوقفه ${l.byName}'}'
                      : 'النظام يعمل للجميع',
                  style: TextStyle(fontWeight: FontWeight.w800, color: statusColor),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _lockMsg,
            maxLines: 3,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'الرسالة التي يراها المستخدمون',
              hintText: 'مثال: النظام متوقّف للتحديث — نعود خلال نصف ساعة',
              border: OutlineInputBorder(),
            ),
          ),
          _savedTexts(info.savedLockdownTexts, _lockMsg, lockdown: true),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.end,
            children: [
              if (l.active) ...[
                OutlinedButton.icon(
                  onPressed: _busy ? null : _updateLockMessage,
                  icon: const Icon(Icons.edit_rounded),
                  label: const Text('تحديث الرسالة'),
                ),
                FilledButton.icon(
                  key: const Key('unlock-button'),
                  style: FilledButton.styleFrom(
                    backgroundColor: dark ? AppColors.successDark : AppColors.success,
                    foregroundColor: dark ? AppColors.navyDeepDark : Colors.white,
                  ),
                  onPressed: _busy ? null : _unlock,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('تشغيل النظام للجميع'),
                ),
              ] else
                FilledButton.icon(
                  key: const Key('lock-button'),
                  style: FilledButton.styleFrom(
                    backgroundColor: dark ? AppColors.dangerDark : AppColors.danger,
                    foregroundColor: dark ? AppColors.navyDeepDark : Colors.white,
                  ),
                  onPressed: _busy ? null : _lock,
                  icon: const Icon(Icons.pause_rounded),
                  label: const Text('إيقاف النظام'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _announcementCard(SystemControlInfo info) {
    final a = info.announcement;
    final previewText = _annText.text.trim();

    return CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(Icons.campaign_rounded, 'شريط الإعلان',
              'نصٌّ يظهر أعلى الشاشات لكل المستخدمين — لا يُغلقه أحدٌ غيرك. مستقلٌّ عن الإيقاف.'),
          const SizedBox(height: 14),
          Row(children: [
            Text(a.visible ? 'ظاهرٌ الآن للجميع' : 'مخفيّ',
                style: TextStyle(fontWeight: FontWeight.w800, color: a.visible ? AppColors.action(context) : null)),
            const Spacer(),
            SegmentedButton<AnnouncementKind>(
              segments: const [
                ButtonSegment(value: AnnouncementKind.info, label: Text('معلومة'), icon: Icon(Icons.info_outline)),
                ButtonSegment(value: AnnouncementKind.warning, label: Text('تنبيه'), icon: Icon(Icons.warning_amber_rounded)),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
          ]),
          const SizedBox(height: 14),
          TextField(
            controller: _annText,
            maxLines: 2,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'نصّ الشريط',
              hintText: 'مثال: سيتوقّف النظام بعد 10 دقائق للتحديث — احفظ عملك',
              border: OutlineInputBorder(),
            ),
          ),
          _savedTexts(info.savedAnnouncementTexts, _annText, lockdown: false),
          if (previewText.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('معاينة:', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: AnnouncementBar(
                announcement: AnnouncementInfo(visible: true, text: previewText, kind: _kind),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.end,
            children: [
              if (a.visible)
                OutlinedButton.icon(
                  key: const Key('hide-announcement'),
                  onPressed: _busy ? null : _hideAnnouncement,
                  icon: const Icon(Icons.visibility_off_rounded),
                  label: const Text('إخفاء الشريط'),
                ),
              FilledButton.icon(
                key: const Key('show-announcement'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.action(context),
                  foregroundColor: AppColors.onAction(context),
                ),
                onPressed: _busy ? null : _showAnnouncement,
                icon: const Icon(Icons.visibility_rounded),
                label: Text(a.visible ? 'تحديث الشريط' : 'إظهار للجميع'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _header(IconData icon, String title, String subtitle) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.action(context), size: 28),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(height: 1.5)),
          ]),
        ),
      ],
    );
  }

  /// النصوص المحفوظة: الضغطُ يضعها في الحقل، و× يحذفها، و«احفظ» يضيف ما في الحقل.
  Widget _savedTexts(List<String> texts, TextEditingController field, {required bool lockdown}) {
    final current = field.text.trim();
    final canSave = current.isNotEmpty && !texts.contains(current);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Text('نصوصي المحفوظة', style: Theme.of(context).textTheme.labelLarge),
          const Spacer(),
          TextButton.icon(
            onPressed: _busy || !canSave ? null : () => _saveText(lockdown: lockdown),
            icon: const Icon(Icons.bookmark_add_outlined, size: 18),
            label: const Text('احفظ هذا النصّ'),
          ),
        ]),
        if (texts.isEmpty)
          Text('لا نصوص محفوظة بعد — اكتب نصّاً ثم «احفظ هذا النصّ».',
              style: Theme.of(context).textTheme.bodySmall)
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in texts)
                InputChip(
                  label: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Text(t, overflow: TextOverflow.ellipsis),
                  ),
                  tooltip: t,
                  selected: t == current,
                  onPressed: () => setState(() => field.text = t),
                  onDeleted: _busy ? null : () => _removeText(lockdown: lockdown, text: t),
                  deleteButtonTooltipMessage: 'حذف من المحفوظات',
                ),
            ],
          ),
      ],
    );
  }
}
