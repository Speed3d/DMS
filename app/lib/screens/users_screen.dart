import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/api_client.dart';
import '../core/session.dart';
import '../models.dart';

const _roleLabels = {
  'SuperAdmin': 'سوبر أدمن',
  'President': 'رئيس الشركة',
  'Manager': 'مدير',
  'Employee': 'موظف',
  'Reader': 'قارئ',
};
const _roleLevels = {'SuperAdmin': 1, 'President': 2, 'Manager': 3, 'Employee': 4, 'Reader': 5};

class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(tabs: [Tab(text: 'المستخدمون'), Tab(text: 'التفويضات')]),
          const Expanded(child: TabBarView(children: [_UsersTab(), _DelegationsTab()])),
        ],
      ),
    );
  }
}

// ----------------- المستخدمون -----------------
class _UsersTab extends ConsumerStatefulWidget {
  const _UsersTab();
  @override
  ConsumerState<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends ConsumerState<_UsersTab> {
  late Future<List<UserModel>> _f;
  @override
  void initState() { super.initState(); _f = ref.read(apiClientProvider).users(); }
  void _reload() => setState(() { _f = ref.read(apiClientProvider).users(); });

  List<String> _manageableRoles() {
    final actor = ref.read(sessionProvider).auth!.role;
    final lvl = _roleLevels[actor] ?? 5;
    return _roleLevels.entries.where((e) => e.value > lvl).map((e) => e.key).toList();
  }

  Future<void> _create() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final res = await navigator.push<Map<String, dynamic>>(MaterialPageRoute(
        builder: (_) => _UserFormPage(roles: _manageableRoles())));
    if (res == null) return;
    try {
      res['companyId'] = ref.read(sessionProvider).effectiveCompanyId;
      await ref.read(apiClientProvider).createUser(res);
      if (mounted) _reload();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.red));
    }
  }

  Future<void> _edit(UserModel u) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final res = await navigator.push<Map<String, dynamic>>(MaterialPageRoute(
        builder: (_) => _UserFormPage(roles: _manageableRoles(), existing: u)));
    if (res == null) return;
    try {
      await ref.read(apiClientProvider).updateUser(u.userId, {
        'fullName': res['fullName'], 'role': res['role'],
        'isActive': res['isActive'], 'canApprove': res['canApprove'],
      });
      if (mounted) _reload();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.red));
    }
  }

  Future<void> _resetPassword(UserModel u) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final res = await navigator.push<Map<String, dynamic>>(MaterialPageRoute(
        builder: (_) => _PasswordPage(username: u.username)));
    if (res == null) return;
    try {
      await ref.read(apiClientProvider).resetPassword(u.userId, res['password']);
      messenger.showSnackBar(const SnackBar(content: Text('تم إعادة تعيين كلمة المرور.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.icon(onPressed: _create, icon: const Icon(Icons.person_add), label: const Text('مستخدم جديد')),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Card(
              child: FutureBuilder<List<UserModel>>(
                future: _f,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
                  if (snap.hasError) return Center(child: Text('خطأ: ${snap.error}'));
                  final users = snap.data ?? [];
                  if (users.isEmpty) return const Center(child: Text('لا يوجد مستخدمون أدنى منك.'));
                  return ListView(
                    children: [
                      for (final u in users)
                        ListTile(
                          leading: Icon(u.isActive ? Icons.person : Icons.person_off,
                              color: u.isActive ? null : Colors.grey),
                          title: Text(u.fullName),
                          subtitle: Text('${u.username} • ${_roleLabels[u.role] ?? u.role}'
                              '${u.canApprove ? ' • يعتمد' : ''}'),
                          trailing: PopupMenuButton<String>(
                            onSelected: (v) => v == 'edit' ? _edit(u) : _resetPassword(u),
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'edit', child: Text('تعديل')),
                              PopupMenuItem(value: 'reset', child: Text('إعادة تعيين كلمة المرور')),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ----------------- التفويضات -----------------
class _DelegationsTab extends ConsumerStatefulWidget {
  const _DelegationsTab();
  @override
  ConsumerState<_DelegationsTab> createState() => _DelegationsTabState();
}

class _DelegationsTabState extends ConsumerState<_DelegationsTab> {
  late Future<List<DelegationModel>> _f;
  @override
  void initState() { super.initState(); _f = ref.read(apiClientProvider).delegations(); }
  void _reload() => setState(() { _f = ref.read(apiClientProvider).delegations(); });

  Future<void> _create() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final users = await ref.read(apiClientProvider).users();
    if (!mounted) return;
    if (users.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('لا يوجد مستخدمون للتفويض إليهم.')));
      return;
    }
    final res = await navigator.push<Map<String, dynamic>>(
        MaterialPageRoute(builder: (_) => _DelegationFormPage(users: users)));
    if (res == null) return;
    try {
      await ref.read(apiClientProvider).createDelegation(res['toUserId'], res['start'], res['end']);
      if (mounted) _reload();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.red));
    }
  }

  Future<void> _revoke(int id) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(apiClientProvider).revokeDelegation(id);
      if (mounted) _reload();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.icon(onPressed: _create, icon: const Icon(Icons.add), label: const Text('تفويض اعتماد جديد')),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Card(
              child: FutureBuilder<List<DelegationModel>>(
                future: _f,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
                  if (snap.hasError) return Center(child: Text('خطأ: ${snap.error}'));
                  final list = snap.data ?? [];
                  if (list.isEmpty) return const Center(child: Text('لا توجد تفويضات.'));
                  return ListView(
                    children: [
                      for (final d in list)
                        ListTile(
                          leading: Icon(Icons.how_to_reg, color: d.isActive ? Colors.green : Colors.grey),
                          title: Text('تفويض للمستخدم #${d.toUserId}'),
                          subtitle: Text('من ${DateFormat('yyyy-MM-dd').format(d.startDate)}'
                              '${d.endDate != null ? ' إلى ${DateFormat('yyyy-MM-dd').format(d.endDate!)}' : ' (دائم)'}'
                              '${d.isActive ? '' : ' • مُلغى'}'),
                          trailing: d.isActive
                              ? IconButton(icon: const Icon(Icons.cancel), onPressed: () => _revoke(d.delegationId))
                              : null,
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ----------------- نماذج الإدخال (شاشات كاملة) -----------------
class _UserFormPage extends StatefulWidget {
  final List<String> roles;
  final UserModel? existing;
  const _UserFormPage({required this.roles, this.existing});
  @override
  State<_UserFormPage> createState() => _UserFormPageState();
}

class _UserFormPageState extends State<_UserFormPage> {
  final _fullName = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  String? _role;
  bool _canApprove = false;
  bool _isActive = true;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _fullName.text = e.fullName;
      _username.text = e.username;
      _role = widget.roles.contains(e.role) ? e.role : null;
      _canApprove = e.canApprove;
      _isActive = e.isActive;
    } else if (widget.roles.isNotEmpty) {
      _role = widget.roles.last; // الأدنى افتراضاً
    }
  }

  @override
  void dispose() { _fullName.dispose(); _username.dispose(); _password.dispose(); super.dispose(); }

  void _save() {
    if (_fullName.text.trim().isEmpty || _role == null) return;
    if (!_isEdit && (_username.text.trim().isEmpty || _password.text.length < 8)) return;
    Navigator.pop<Map<String, dynamic>>(context, {
      'fullName': _fullName.text.trim(),
      'username': _username.text.trim(),
      'password': _password.text,
      'role': _role,
      'canApprove': _canApprove,
      'isActive': _isActive,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'تعديل مستخدم' : 'مستخدم جديد')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              TextField(controller: _fullName, decoration: const InputDecoration(labelText: 'الاسم الكامل')),
              const SizedBox(height: 12),
              TextField(
                controller: _username,
                enabled: !_isEdit,
                decoration: const InputDecoration(labelText: 'اسم المستخدم'),
              ),
              if (!_isEdit) ...[
                const SizedBox(height: 12),
                TextField(controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'كلمة المرور (8 أحرف+)')),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: const InputDecoration(labelText: 'الدور'),
                items: widget.roles.map((r) => DropdownMenuItem(value: r, child: Text(_roleLabels[r] ?? r))).toList(),
                onChanged: (v) => setState(() => _role = v),
              ),
              SwitchListTile(
                value: _canApprove, contentPadding: EdgeInsets.zero,
                title: const Text('صلاحية الاعتماد'),
                onChanged: (v) => setState(() => _canApprove = v),
              ),
              if (_isEdit)
                SwitchListTile(
                  value: _isActive, contentPadding: EdgeInsets.zero,
                  title: const Text('مُفعّل'),
                  onChanged: (v) => setState(() => _isActive = v),
                ),
              const SizedBox(height: 16),
              FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save), label: const Text('حفظ')),
            ],
          ),
        ),
      ),
    );
  }
}

class _PasswordPage extends StatefulWidget {
  final String username;
  const _PasswordPage({required this.username});
  @override
  State<_PasswordPage> createState() => _PasswordPageState();
}

class _PasswordPageState extends State<_PasswordPage> {
  final _password = TextEditingController();
  String? _error;
  @override
  void dispose() { _password.dispose(); super.dispose(); }
  void _save() {
    if (_password.text.length < 8) { setState(() => _error = '8 أحرف على الأقل.'); return; }
    Navigator.pop<Map<String, dynamic>>(context, {'password': _password.text});
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('كلمة مرور جديدة لـ ${widget.username}')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              TextField(controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'كلمة المرور الجديدة')),
              if (_error != null) ...[const SizedBox(height: 8), Text(_error!, style: const TextStyle(color: Colors.red))],
              const SizedBox(height: 16),
              FilledButton(onPressed: _save, child: const Text('حفظ')),
            ],
          ),
        ),
      ),
    );
  }
}

class _DelegationFormPage extends StatefulWidget {
  final List<UserModel> users;
  const _DelegationFormPage({required this.users});
  @override
  State<_DelegationFormPage> createState() => _DelegationFormPageState();
}

class _DelegationFormPageState extends State<_DelegationFormPage> {
  int? _toUserId;
  DateTime _start = DateTime.now();
  DateTime? _end;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تفويض اعتماد')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              DropdownButtonFormField<int>(
                initialValue: _toUserId,
                decoration: const InputDecoration(labelText: 'المستخدم المفوَّض'),
                items: widget.users.map((u) => DropdownMenuItem(value: u.userId, child: Text('${u.fullName} (${u.username})'))).toList(),
                onChanged: (v) => setState(() => _toUserId = v),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: Text('من: ${DateFormat('yyyy-MM-dd').format(_start)}')),
                TextButton(onPressed: () async {
                  final d = await showDatePicker(context: context, initialDate: _start, firstDate: DateTime(2020), lastDate: DateTime(2100));
                  if (d != null) setState(() => _start = d);
                }, child: const Text('تغيير')),
              ]),
              Row(children: [
                Expanded(child: Text('إلى: ${_end == null ? 'دائم' : DateFormat('yyyy-MM-dd').format(_end!)}')),
                TextButton(onPressed: () async {
                  final d = await showDatePicker(context: context, initialDate: _end ?? _start.add(const Duration(days: 7)), firstDate: DateTime(2020), lastDate: DateTime(2100));
                  if (d != null) setState(() => _end = d);
                }, child: const Text('تحديد')),
                if (_end != null)
                  TextButton(onPressed: () => setState(() => _end = null), child: const Text('دائم')),
              ]),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _toUserId == null ? null : () => Navigator.pop<Map<String, dynamic>>(context, {'toUserId': _toUserId, 'start': _start, 'end': _end}),
                icon: const Icon(Icons.save),
                label: const Text('حفظ التفويض'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
