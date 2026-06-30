import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/api_client.dart';
import '../core/session.dart';
import 'template_edit_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSuper = ref.watch(sessionProvider).auth?.isSuperAdmin ?? false;
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          const TabBar(tabs: [
            Tab(text: 'الشركات'),
            Tab(text: 'الجهات'),
            Tab(text: 'القوالب'),
            Tab(text: 'أسعار الصرف'),
          ]),
          Expanded(
            child: TabBarView(children: [
              _CompaniesTab(canCreate: isSuper),
              const _EntitiesTab(),
              const _TemplatesTab(),
              const _RatesTab(),
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
  _Field(this.key, this.label);
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
    _ctrls = {for (final f in widget.fields) f.key: TextEditingController()};
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
  void initState() { super.initState(); _f = ref.read(apiClientProvider).companies(); }
  void _reload() => setState(() { _f = ref.read(apiClientProvider).companies(); });

  Future<void> _add() async {
    final messenger = ScaffoldMessenger.of(context);
    final r = await _prompt(context, 'شركة جديدة', [_Field('name', 'الاسم'), _Field('prefix', 'الرمز (DEN)')]);
    if (r == null) return;
    try {
      await ref.read(apiClientProvider).createCompany(r['name']!, r['prefix']!);
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
            children: [for (final c in list) ListTile(leading: const Icon(Icons.business), title: Text(c.name), subtitle: Text('الرمز: ${c.prefix}'))],
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
            children: [for (final e in list) ListTile(leading: const Icon(Icons.account_balance), title: Text(e.name))],
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
