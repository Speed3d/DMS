import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import '../core/api_client.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../widgets/password_field.dart';

import 'company_edit_screen.dart';
import 'hr_settings_screen.dart';
import 'system_control_tab.dart';
import 'template_edit_screen.dart';

/// فتح شاشة تأكيد تصفير قاعدة البيانات بالكامل — **للسوبر أدمن حصراً**.
/// Hint: نستخدم شاشة كاملة (Scaffold) بدل showDialog لتفادي خلل محرّك Flutter Web مع الحقول النصّية،
///       ولكي تبقى الشاشة مفتوحة عند إدخال كلمة مرور خاطئة فيرى السوبر أدمن رسالة الخطأ ويصحّحها فوراً.
Future<void> openResetDatabasePage(BuildContext context) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(builder: (_) => const ResetDatabaseConfirmPage()),
  );
}

/// شاشة تأكيد تصفير قاعدة البيانات بالكامل — محمية بكلمة مرور السوبر أدمن + كتابة كلمة «تصفير».
/// Hint: تتحقّق من شرطين معاً قبل تفعيل زرّ التنفيذ:
///       1. إدخال كلمة مرور السوبر أدمن الحالية (يتحقّق منها الخادم عبر IPasswordHasher.Verify).
///       2. كتابة كلمة «تصفير» صراحةً لمنع الضغطة العابرة.
class ResetDatabaseConfirmPage extends ConsumerStatefulWidget {
  const ResetDatabaseConfirmPage({super.key});

  @override
  ConsumerState<ResetDatabaseConfirmPage> createState() => _ResetDatabaseConfirmPageState();
}

class _ResetDatabaseConfirmPageState extends ConsumerState<ResetDatabaseConfirmPage> {
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _passwordCtrl.addListener(_onChanged);
    _confirmCtrl.addListener(_onChanged);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_busy &&
      _passwordCtrl.text.isNotEmpty &&
      _confirmCtrl.text.trim() == 'تصفير';

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(apiClientProvider).resetDb(
            password: _passwordCtrl.text,
            confirmation: _confirmCtrl.text.trim(),
          );
      messenger.showSnackBar(const SnackBar(
        content: Text('تم تصفير قاعدة البيانات بالكامل بنجاح. سجّل الدخول بحساب السوبر أدمن للبدء من الصفر.'),
      ));
      await ref.read(sessionProvider.notifier).logout();
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'خطأ: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('منطقة خطر — تصفير قاعدة البيانات بالكامل'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.danger.withValues(alpha: 0.45)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 28),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'تحذير نهائي — لا يمكن التراجع عن هذا الإجراء',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: AppColors.danger,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'عند التنفيذ سيتم مسح جميع البيانات بالكامل والبدء من الصفر:\n'
                        '• جميع الشركات والمستخدمين وتفويضات الاعتماد\n'
                        '• جميع الكتب الصادرة والواردة والأرشيف والمعاملات والردود\n'
                        '• جميع الموظفين والرواتب والإجازات والمهام والإشعارات\n'
                        '• جميع الأقسام والجهات والقوالب وأنواع الكتب والملفات المرفوعة\n\n'
                        '✅ يبقى حساب السوبر أدمن الحالي وحده فقط (بنفس اسم المستخدم وكلمة المرور الحالية) لتتمكّن من تسجيل الدخول والبدء من جديد.\n\n'
                        '⚠️ هذا ليس «حذف شركة». لحذف شركةٍ واحدة: الإعدادات ← الشركات ← عطّلها ثم احذفها.',
                        style: TextStyle(height: 1.75),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                PasswordField(
                  key: const Key('reset-db-password'),
                  controller: _passwordCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'كلمة مرور السوبر أدمن الحالية (للتأكيد)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('reset-db-confirm'),
                  controller: _confirmCtrl,
                  decoration: const InputDecoration(
                    labelText: 'اكتب كلمة التأكيد: تصفير',
                    hintText: 'تصفير',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: AppColors.danger, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                // Hint: نستخدم Wrap بدل Row لتفادي فيض الأزرار على الشاشات الضيقة (درس G12).
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  alignment: WrapAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: _busy ? null : () => Navigator.of(context).pop(),
                      child: const Text('إلغاء'),
                    ),
                    FilledButton.icon(
                      key: const Key('reset-db-submit'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.danger,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _canSubmit ? _submit : null,
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.delete_forever_rounded),
                      label: const Text('تصفير قاعدة البيانات بالكامل'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final isSuper = session.auth?.isSuperAdmin ?? false;
    // ⚠️ تبويب الإعدادات يتبع **الرواتب**: محتواه أيامُ عمل ومكافأةُ نهاية خدمة — أي
    //    قواعدُ حسابٍ ماليّ، ونقطتُه `[RequireHrModule(Payroll)]`.
    final showHr = session.canSeePayroll;

    return DefaultTabController(
      length: 7 + (showHr ? 1 : 0) + (isSuper ? 1 : 0),
      child: Column(
        children: [
          TabBar(isScrollable: true, tabs: [
            const Tab(text: 'الشركات'),
            const Tab(text: 'الجهات'),
            const Tab(text: 'الأقسام'),
            const Tab(text: 'أنواع المستندات'),
            // ADR-057: قائمةٌ منفصلة لما تُصدره الشركة (قرار المالك) — لا «شكوى» و«مخطّط» في إنشاء فاتورة.
            const Tab(text: 'أنواع الصادر'),
            const Tab(text: 'القوالب'),
            const Tab(text: 'أسعار الصرف'),
            if (showHr) const Tab(text: 'الموظفون والرواتب'),
            // ⏸️ إيقاف النظام وشريط الإعلان (ADR-050) — للسوبر أدمن وحده، **وفي الإنتاج**
            //    (لا `kDebugMode`): هو أداةُ تشغيلٍ يوميّ لا أداةُ مطوّر.
            if (isSuper) const Tab(text: 'النظام'),
          ]),
          Expanded(
            child: TabBarView(children: [
              _CompaniesTab(canCreate: isSuper),
              const _EntitiesTab(),
              const _DepartmentsTab(),
              const _DocumentTypesTab(),
              const _OutgoingBookTypesTab(),
              const _TemplatesTab(),
              const _RatesTab(),
              if (showHr) const HrSettingsScreen(),
              if (isSuper) const SystemControlTab(),
            ]),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final List<Widget> children;
  final VoidCallback? onAdd;
  final String addLabel;
  const _Section({required this.children, this.onAdd, required this.addLabel});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (onAdd != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: Text(addLabel)),
              ),
            const SizedBox(height: 12),
            Expanded(child: Card(child: ListView(children: children))),
          ],
        ),
      );
}

// نستخدم شاشة كاملة بدل showDialog لتفادي خلل محرّك الويب مع الحقول النصّية داخل الحوارات.
Future<Map<String, String>?> _prompt(BuildContext context, String title, List<_Field> fields) {
  return Navigator.of(context).push<Map<String, String>>(
    MaterialPageRoute(builder: (_) => _PromptPage(title: title, fields: fields)),
  );
}

class _Field {
  final String key, label;
  String val;
  _Field(this.key, this.label, {String initial = ''}) : val = initial;
}

class _PromptPage extends StatefulWidget {
  final String title;
  final List<_Field> fields;
  const _PromptPage({required this.title, required this.fields});
  @override
  State<_PromptPage> createState() => _PromptPageState();
}

class _PromptPageState extends State<_PromptPage> {
  late final Map<String, TextEditingController> _ctrls;

  @override
  void initState() {
    super.initState();
    _ctrls = {for (final f in widget.fields) f.key: TextEditingController(text: f.val)};
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() =>
      Navigator.pop(context, {for (final e in _ctrls.entries) e.key: e.value.text.trim()});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              for (final f in widget.fields)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: TextField(
                    controller: _ctrls[f.key],
                    decoration: InputDecoration(labelText: f.label),
                    onSubmitted: (_) => _save(),
                  ),
                ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save),
                label: const Text('حفظ'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ----- الشركات -----
class _CompaniesTab extends ConsumerStatefulWidget {
  final bool canCreate;
  const _CompaniesTab({required this.canCreate});
  @override
  ConsumerState<_CompaniesTab> createState() => _CompaniesTabState();
}

class _CompaniesTabState extends ConsumerState<_CompaniesTab> {
  late Future _f;
  @override
  // ⚠️ **`includeInactive` هنا وحدها** (ADR-047): هذه شاشة الإدارة، فتُظهر المعطَّلة
  //    رماديةً بزرّ إعادة تفعيل. **ومبدّلُ الشركات لا يمرّرها** فلا تظهر فيه.
  @override
  void initState() { super.initState(); _f = _fetch(); }
  Future _fetch() => ref.read(apiClientProvider).companies(includeInactive: true);
  void _reload() => setState(() { _f = _fetch(); });

  /// تفعيل/تعطيل — **والخادم يرفض تعطيلاً يُقفل مستخدماً خارج النظام**.
  ///
  /// 🔑 **التعطيل هو الحذف الناعم للشركة**: تختفي من المبدّل ومن رموز المستخدمين،
  /// **وبياناتها تبقى كاملة**. وهو الجواب الصحيح لـ«شركةٌ توقّفنا عن العمل بها».
  Future<void> _toggleActive(Company c) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(apiClientProvider).updateCompany(
          c.companyId, c.name, c.prefix, !c.isActive,
          defaultSignatoryName: c.defaultSignatoryName,
          defaultSignatoryTitle: c.defaultSignatoryTitle);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(
          c.isActive ? 'عُطّلت «${c.name}» — لم تعُد تظهر في مبدّل الشركات.'
                     : 'فُعّلت «${c.name}».')));
      _reload();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.red));
    }
  }

  Future<void> _add() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final r = await _prompt(context, 'شركة جديدة', [
      _Field('name', 'الاسم'),
      _Field('prefix', 'الرمز (DEN)'),
      _Field('sigName', 'الاسم الافتراضي للموقّع (اختياري)'),
      _Field('sigTitle', 'المنصب الافتراضي للموقّع (اختياري)'),
    ]);
    if (r == null) return;
    try {
      final created = await ref.read(apiClientProvider).createCompany(r['name']!, r['prefix']!, defaultSignatoryName: r['sigName'], defaultSignatoryTitle: r['sigTitle']);
      await navigator.push(MaterialPageRoute(builder: (_) => CompanyEditScreen(companyId: created.companyId)));
      if (mounted) _reload();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: _f,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) return Center(child: Text('خطأ: ${snap.error}'));
          final list = snap.data as List;
          return _Section(
            addLabel: 'شركة جديدة',
            onAdd: widget.canCreate ? _add : null,
            children: [
              for (final c in list)
                ListTile(
                  leading: Icon(Icons.business,
                      color: c.isActive ? null : Theme.of(context).disabledColor),
                  title: Text(c.name,
                      style: TextStyle(
                          color: c.isActive ? null : Theme.of(context).disabledColor,
                          decoration: c.isActive ? null : TextDecoration.lineThrough)),
                  subtitle: Text(c.isActive
                      ? 'الرمز: ${c.prefix}'
                      : 'الرمز: ${c.prefix} · معطَّلة — مخفيّة عن مبدّل الشركات'),
                  trailing: !widget.canCreate
                      ? null
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
                                  c.isActive ? Icons.toggle_on : Icons.toggle_off,
                                  size: 28,
                                  color: c.isActive
                                      ? AppColors.success
                                      : Theme.of(context).disabledColor),
                              tooltip: c.isActive ? 'تعطيل' : 'تفعيل',
                              onPressed: () => _toggleActive(c),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit),
                              tooltip: 'تعديل',
                              onPressed: () async {
                                await Navigator.push(context, MaterialPageRoute(
                                    builder: (_) => CompanyEditScreen(companyId: c.companyId)));
                                if (mounted) _reload();
                              },
                            ),
                          ],
                        ),
                                )
            ],
          );
        },
      );
}

// ----- الجهات -----
class _EntitiesTab extends ConsumerStatefulWidget {
  const _EntitiesTab();
  @override
  ConsumerState<_EntitiesTab> createState() => _EntitiesTabState();
}

class _EntitiesTabState extends ConsumerState<_EntitiesTab> {
  late Future _f;
  @override
  void initState() { super.initState(); _f = ref.read(apiClientProvider).entities(); }
  void _reload() => setState(() { _f = ref.read(apiClientProvider).entities(); });

  Future<void> _add() async {
    final messenger = ScaffoldMessenger.of(context);
    final r = await _prompt(context, 'جهة جديدة', [_Field('name', 'الاسم')]);
    if (r == null || r['name']!.isEmpty) return;
    try {
      await ref.read(apiClientProvider).createEntity(r['name']!, 'Both');
      if (mounted) _reload();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.red));
    }
  }

  /// حذف جهة — الخادم يرفض إن كانت مستخدَمة ويوضّح أين، فنعرض رسالته كما هي.
  Future<void> _deleteEntity(dynamic e) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('حذف جهة'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Text('هل تريد حذف الجهة «${e.name}»؟\n'
            'لن يتم الحذف إن كانت مستخدَمة في أي كتاب صادر أو وارد أو أرشيف.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiClientProvider).deleteEntity(e.entityId);
      if (mounted) _reload();
      messenger.showSnackBar(SnackBar(content: Text('تم حذف الجهة «${e.name}».'), backgroundColor: Colors.green));
    } on ApiException catch (ex) {
      messenger.showSnackBar(SnackBar(content: Text(ex.message), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: _f,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) return Center(child: Text('خطأ: ${snap.error}'));
          final list = snap.data as List;
          return _Section(
            addLabel: 'جهة جديدة',
            onAdd: _add,
            children: [
              for (final e in list)
                ListTile(
                  leading: const Icon(Icons.account_balance),
                  title: Text(e.name),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    tooltip: 'حذف الجهة',
                    onPressed: () => _deleteEntity(e),
                  ),
                ),
            ],
          );
        },
      );
}

// ----- أنواع المستندات -----
/// إدارة أنواع المستندات (تصنيف الوارد والأرشيف — يُستخدم في الحقل والفلترة).
///
/// ⚠️ **سبب وجود هذا التبويب:** الحقل والفلترة ونقاط الـAPI كانت مبنية منذ البداية، لكن
/// **لا شاشة تملأ القائمة** — فبقيت المنسدلة فارغة أبداً و**صفر** كتاب من 43 يحمل نوعاً.
/// نفس نمط عيب «تصدير Word»: ميزة بلا مدخل في الواجهة تموت بصمت.
class _DocumentTypesTab extends ConsumerStatefulWidget {
  const _DocumentTypesTab();
  @override
  ConsumerState<_DocumentTypesTab> createState() => _DocumentTypesTabState();
}

class _DocumentTypesTabState extends ConsumerState<_DocumentTypesTab> {
  late Future<List<DocumentTypeModel>> _f;
  @override
  void initState() { super.initState(); _f = ref.read(apiClientProvider).documentTypes(); }
  void _reload() => setState(() { _f = ref.read(apiClientProvider).documentTypes(); });

  Future<void> _add() async {
    final messenger = ScaffoldMessenger.of(context);
    final r = await _prompt(context, 'نوع مستند جديد', [_Field('name', 'اسم النوع (مثل: فاتورة)')]);
    if (r == null || r['name']!.trim().isEmpty) return;
    try {
      await ref.read(apiClientProvider).createDocumentType(r['name']!.trim());
      if (mounted) _reload();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.red));
    }
  }

  Future<void> _rename(DocumentTypeModel t) async {
    final messenger = ScaffoldMessenger.of(context);
    final r = await _prompt(context, 'تعديل النوع', [_Field('name', 'اسم النوع', initial: t.name)]);
    if (r == null || r['name']!.trim().isEmpty) return;
    try {
      await ref.read(apiClientProvider).updateDocumentType(t.documentTypeId, r['name']!.trim());
      if (mounted) _reload();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.red));
    }
  }

  Future<void> _delete(DocumentTypeModel t) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('حذف نوع مستند'),
        content: Text('هل تريد حذف النوع «${t.name}»؟\n'
            'لن يتم الحذف إن كان مستخدَماً في كتب واردة أو مستندات أرشيف — عدّل اسمه بدل حذفه.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiClientProvider).deleteDocumentType(t.documentTypeId);
      if (mounted) _reload();
      messenger.showSnackBar(SnackBar(content: Text('تم حذف النوع «${t.name}».'), backgroundColor: Colors.green));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<DocumentTypeModel>>(
        future: _f,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) return Center(child: Text('خطأ: ${snap.error}'));
          final list = snap.data ?? const <DocumentTypeModel>[];
          return _Section(
            addLabel: 'نوع جديد',
            onAdd: _add,
            children: [
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('لا توجد أنواع مستندات بعد. أضِف الأنواع التي تتعامل بها '
                      '(كتاب رسمي · فاتورة · عقد · مخطّط …) لتصنيف الوارد والأرشيف والبحث بها.',
                      style: TextStyle(color: Colors.grey)),
                ),
              for (final t in list)
                ListTile(
                  leading: const Icon(Icons.label_outline_rounded),
                  title: Text(t.name),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'تعديل', onPressed: () => _rename(t)),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        tooltip: 'حذف',
                        onPressed: () => _delete(t),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      );
}

// ----- أنواع الصادر (ADR-057) -----
/// أنواع الكتاب الصادر — كتاب رسمي · فاتورة · عرض سعر · وما يضيفه المالك. نظيرُ [_DocumentTypesTab].
class _OutgoingBookTypesTab extends ConsumerStatefulWidget {
  const _OutgoingBookTypesTab();
  @override
  ConsumerState<_OutgoingBookTypesTab> createState() => _OutgoingBookTypesTabState();
}

class _OutgoingBookTypesTabState extends ConsumerState<_OutgoingBookTypesTab> {
  late Future<List<OutgoingBookTypeModel>> _f;
  @override
  void initState() { super.initState(); _f = ref.read(apiClientProvider).outgoingBookTypes(); }
  void _reload() => setState(() { _f = ref.read(apiClientProvider).outgoingBookTypes(); });

  Future<void> _run(Future<void> Function() action, {String? done}) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      if (mounted) _reload();
      if (done != null) messenger.showSnackBar(SnackBar(content: Text(done), backgroundColor: Colors.green));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.red));
    }
  }

  Future<void> _add() async {
    final r = await _prompt(context, 'نوع كتابٍ صادر جديد', [_Field('name', 'اسم النوع (مثل: كشف كميات)')]);
    if (r == null || r['name']!.trim().isEmpty) return;
    await _run(() => ref.read(apiClientProvider).createOutgoingBookType(r['name']!.trim()));
  }

  Future<void> _rename(OutgoingBookTypeModel t) async {
    final r = await _prompt(context, 'تعديل النوع', [_Field('name', 'اسم النوع', initial: t.name)]);
    if (r == null || r['name']!.trim().isEmpty) return;
    await _run(() => ref.read(apiClientProvider).updateOutgoingBookType(t.outgoingBookTypeId, r['name']!.trim()));
  }

  Future<void> _delete(OutgoingBookTypeModel t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('حذف نوع كتابٍ صادر'),
        content: Text('هل تريد حذف النوع «${t.name}»؟\n'
            'لن يتم الحذف إن كان مستخدَماً في كتبٍ صادرة — عدّل اسمه بدل حذفه.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() => ref.read(apiClientProvider).deleteOutgoingBookType(t.outgoingBookTypeId),
        done: 'تم حذف النوع «${t.name}».');
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<OutgoingBookTypeModel>>(
        future: _f,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) return Center(child: Text('خطأ: ${snap.error}'));
          final list = snap.data ?? const <OutgoingBookTypeModel>[];
          return _Section(
            addLabel: 'نوع جديد',
            onAdd: _add,
            children: [
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('لا توجد أنواعٌ للصادر بعد. أضِف ما تُصدره الشركة '
                      '(كتاب رسمي · فاتورة · عرض سعر …) لتصنيف الكتب والفلترة بها.',
                      style: TextStyle(color: Colors.grey)),
                ),
              for (final (i, t) in list.indexed)
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: Text(t.name),
                  // الأوّل هو افتراض الكتاب الجديد (قرار المالك: «كتاب رسمي») — يُقال صراحةً.
                  subtitle: i == 0 ? const Text('الافتراضي للكتاب الجديد') : null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'تعديل', onPressed: () => _rename(t)),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        tooltip: 'حذف',
                        onPressed: () => _delete(t),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      );
}

// ----- الأقسام -----
/// إدارة أقسام الشركة (وجهات إحالة الوارد ومواقع عمل الموظفين).
class _DepartmentsTab extends ConsumerStatefulWidget {
  const _DepartmentsTab();
  @override
  ConsumerState<_DepartmentsTab> createState() => _DepartmentsTabState();
}

class _DepartmentsTabState extends ConsumerState<_DepartmentsTab> {
  late Future<List<DepartmentModel>> _f;
  @override
  void initState() { super.initState(); _f = ref.read(apiClientProvider).departments(); }
  void _reload() => setState(() { _f = ref.read(apiClientProvider).departments(); });

  Future<void> _add() async {
    final messenger = ScaffoldMessenger.of(context);
    final r = await _prompt(context, 'قسم جديد', [_Field('name', 'اسم القسم (مثل: المالية)')]);
    if (r == null || r['name']!.trim().isEmpty) return;
    try {
      await ref.read(apiClientProvider).createDepartment(r['name']!.trim());
      if (mounted) _reload();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.red));
    }
  }

  Future<void> _rename(DepartmentModel d) async {
    final messenger = ScaffoldMessenger.of(context);
    final r = await _prompt(context, 'تعديل القسم', [_Field('name', 'اسم القسم', initial: d.name)]);
    if (r == null || r['name']!.trim().isEmpty) return;
    try {
      await ref.read(apiClientProvider).updateDepartment(d.departmentId, r['name']!.trim(), d.isActive);
      if (mounted) _reload();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.red));
    }
  }

  Future<void> _toggleActive(DepartmentModel d) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(apiClientProvider).updateDepartment(d.departmentId, d.name, !d.isActive);
      if (mounted) _reload();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.red));
    }
  }

  Future<void> _delete(DepartmentModel d) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('حذف قسم'),
        content: Text('هل تريد حذف القسم «${d.name}»؟\n'
            'لن يتم الحذف إن كان محالاً إليه كتب واردة — عطّله بدل حذفه في تلك الحالة.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiClientProvider).deleteDepartment(d.departmentId);
      if (mounted) _reload();
      messenger.showSnackBar(SnackBar(content: Text('تم حذف القسم «${d.name}».'), backgroundColor: Colors.green));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<DepartmentModel>>(
        future: _f,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) return Center(child: Text('خطأ: ${snap.error}'));
          final list = snap.data ?? const <DepartmentModel>[];
          return _Section(
            addLabel: 'قسم جديد',
            onAdd: _add,
            children: [
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('لا توجد أقسام بعد. أضِف أقسام الشركة (الإدارة · المتابعة · المالية …) '
                      'لتتمكّن من إحالة الكتب الواردة إليها.', style: TextStyle(color: Colors.grey)),
                ),
              for (final d in list)
                ListTile(
                  leading: Icon(Icons.apartment_rounded,
                      color: d.isActive ? null : Colors.grey),
                  title: Text(d.name,
                      style: TextStyle(
                          decoration: d.isActive ? null : TextDecoration.lineThrough,
                          color: d.isActive ? null : Colors.grey)),
                  subtitle: d.isActive ? null : const Text('معطّل', style: TextStyle(color: Colors.orange, fontSize: 12)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(d.isActive ? Icons.toggle_on : Icons.toggle_off,
                            color: d.isActive ? Colors.green : Colors.grey, size: 28),
                        tooltip: d.isActive ? 'تعطيل' : 'تفعيل',
                        onPressed: () => _toggleActive(d),
                      ),
                      IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'تعديل', onPressed: () => _rename(d)),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        tooltip: 'حذف',
                        onPressed: () => _delete(d),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      );
}

// ----- القوالب -----
class _TemplatesTab extends ConsumerStatefulWidget {
  const _TemplatesTab();
  @override
  ConsumerState<_TemplatesTab> createState() => _TemplatesTabState();
}

class _TemplatesTabState extends ConsumerState<_TemplatesTab> {
  late Future _f;
  @override
  void initState() { super.initState(); _f = ref.read(apiClientProvider).templates(); }
  void _reload() => setState(() { _f = ref.read(apiClientProvider).templates(); });

  Future<void> _add() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final r = await _prompt(context, 'قالب جديد', [_Field('name', 'اسم القالب')]);
    if (r == null || r['name']!.isEmpty) return;
    try {
      final created = await ref.read(apiClientProvider).createTemplate(r['name']!);
      // افتح شاشة التعديل لرفع الصور وضبط الإعدادات مباشرةً
      await navigator.push(MaterialPageRoute(
          builder: (_) => TemplateEditScreen(templateId: created.templateId)));
      if (mounted) _reload();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.red));
    }
  }

  Future<void> _openEdit(int id) async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => TemplateEditScreen(templateId: id)));
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: _f,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) return Center(child: Text('خطأ: ${snap.error}'));
          final list = snap.data as List;
          return _Section(
            addLabel: 'قالب جديد',
            onAdd: _add,
            children: [
              for (final t in list)
                ListTile(
                  leading: const Icon(Icons.description),
                  title: Text(t.name),
                  subtitle: Text([
                    t.isActive ? 'مُفعّل' : 'مُعطّل',
                    if (t.hasHeader) 'هيدر',
                    if (t.hasFooter) 'فوتر',
                    if (t.hasWatermark) 'علامة',
                  ].join(' • ')),
                  trailing: const Icon(Icons.edit),
                  onTap: () => _openEdit(t.templateId),
                ),
            ],
          );
        },
      );
}

// ----- أسعار الصرف -----
class _RatesTab extends ConsumerStatefulWidget {
  const _RatesTab();
  @override
  ConsumerState<_RatesTab> createState() => _RatesTabState();
}

class _RatesTabState extends ConsumerState<_RatesTab> {
  late Future _f;
  @override
  void initState() { super.initState(); _f = ref.read(apiClientProvider).exchangeRates(); }
  void _reload() => setState(() { _f = ref.read(apiClientProvider).exchangeRates(); });

  Future<void> _add() async {
    final messenger = ScaffoldMessenger.of(context);
    final r = await _prompt(context, 'سعر صرف (USD)', [_Field('rate', 'السعر (دينار لكل دولار)')]);
    if (r == null) return;
    final rate = num.tryParse(r['rate'] ?? '');
    if (rate == null || rate <= 0) return;
    try {
      await ref.read(apiClientProvider).createRate('USD', rate);
      if (mounted) _reload();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: _f,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) return Center(child: Text('خطأ: ${snap.error}'));
          final list = snap.data as List;
          return _Section(
            addLabel: 'سعر صرف جديد',
            onAdd: _add,
            children: [
              for (final r in list)
                ListTile(
                  leading: const Icon(Icons.currency_exchange),
                  title: Text('${r.currency} = ${r.rate}'),
                  subtitle: Text(DateFormat('yyyy-MM-dd').format(r.effectiveDate)),
                ),
            ],
          );
        },
      );
}
