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

class _UsersData {
  final List<UserModel> users;
  final Map<int, String> companies;
  _UsersData(this.users, this.companies);
}

class _UsersTabState extends ConsumerState<_UsersTab> {
  late Future<_UsersData> _f;

  @override
  void initState() { super.initState(); _f = _loadData(); }
  void _reload() => setState(() { _f = _loadData(); });

  Future<_UsersData> _loadData() async {
    final api = ref.read(apiClientProvider);
    final users = await api.users();
    final comps = await api.companies();
    final compMap = {for (final c in comps) c.companyId: c.name};
    return _UsersData(users, compMap);
  }

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

  Color _getRoleColor(String role) {
    switch (role) {
      case 'SuperAdmin': return Colors.red;
      case 'President': return Colors.blue.shade700;
      case 'Manager': return const Color(0xFFC79A3A); // Gold/Orange
      case 'Employee': return Colors.grey.shade700;
      case 'Reader': return Colors.purple.shade600;
      default: return Colors.grey;
    }
  }

  Color _getAvatarColor(String text) {
    final colors = [
      const Color(0xFF1E3A8A), const Color(0xFF1D4ED8), const Color(0xFF047857),
      const Color(0xFFB45309), const Color(0xFF6D28D9), const Color(0xFFBE185D)
    ];
    return colors[text.hashCode % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.icon(
              onPressed: _create, 
              icon: const Icon(Icons.person_add_rounded), 
              label: const Text('مستخدم جديد', style: TextStyle(fontWeight: FontWeight.bold)),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1E3A8A),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? theme.colorScheme.surface : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: FutureBuilder<_UsersData>(
                future: _f,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
                  if (snap.hasError) return Center(child: Text('خطأ: ${snap.error}'));
                  final data = snap.data!;
                  final users = data.users;
                  if (users.isEmpty) return const Center(child: Text('لا يوجد مستخدمون أدنى منك.'));
                  
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header Row
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        decoration: BoxDecoration(
                          color: isDark ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3) : const Color(0xFFF8FAFC),
                          border: Border(bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.5))),
                        ),
                        child: Row(
                          children: [
                            Expanded(flex: 2, child: Text('المستخدم', style: TextStyle(fontWeight: FontWeight.bold, color: theme.textTheme.bodyLarge?.color, fontSize: 13), textAlign: TextAlign.right)),
                            const Expanded(flex: 2, child: Text('الدور', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B), fontSize: 13), textAlign: TextAlign.center)),
                            const Expanded(flex: 2, child: Text('الشركة', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B), fontSize: 13), textAlign: TextAlign.center)),
                            const Expanded(flex: 1, child: Text('الاعتماد', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B), fontSize: 13), textAlign: TextAlign.center)),
                            const Expanded(flex: 1, child: Text('الحالة', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B), fontSize: 13), textAlign: TextAlign.center)),
                            const SizedBox(width: 56), // Action button space
                          ],
                        ),
                      ),
                      
                      // Data Rows
                      Expanded(
                        child: ListView.separated(
                          itemCount: users.length,
                          separatorBuilder: (context, index) => Divider(height: 1, color: theme.dividerColor.withValues(alpha: 0.5)),
                          itemBuilder: (context, index) {
                            final u = users[index];
                            final compName = u.companyId != null ? (data.companies[u.companyId] ?? 'غير معروف') : 'كافة الشركات';
                            final logoUrl = u.companyId != null ? '$kApiBaseUrl/companies/${u.companyId}/logo' : null;
                            final roleColor = _getRoleColor(u.role);
                            
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                              child: Row(
                                children: [
                                  // User (Rightmost, Avatar + Name)
                                  Expanded(
                                    flex: 2,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 40,
                                          height: 40,
                                          decoration: BoxDecoration(
                                            color: _getAvatarColor(u.fullName),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          alignment: Alignment.center,
                                          child: Text(
                                            u.fullName.isNotEmpty ? u.fullName[0].toUpperCase() : '؟',
                                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(u.fullName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                                              const SizedBox(height: 2),
                                              Text('@${u.username}', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  
                                  // Role
                                  Expanded(
                                    flex: 2,
                                    child: Center(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: roleColor.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(99),
                                        ),
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            _roleLabels[u.role] ?? u.role,
                                            style: TextStyle(color: roleColor, fontWeight: FontWeight.bold, fontSize: 12),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  
                                  // Company
                                  Expanded(
                                    flex: 2,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        if (logoUrl != null) ...[
                                          CircleAvatar(
                                            radius: 12,
                                            backgroundColor: Colors.transparent,
                                            backgroundImage: NetworkImage(logoUrl),
                                            onBackgroundImageError: (_, __) {},
                                          ),
                                          const SizedBox(width: 8),
                                        ],
                                        Flexible(
                                          child: Text(compName, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                                        ),
                                      ],
                                    ),
                                  ),
                                  
                                  // Approval
                                  Expanded(
                                    flex: 1,
                                    child: Center(
                                      child: u.canApprove
                                          ? const Icon(Icons.check_rounded, color: Color(0xFF10B981), size: 20)
                                          : const Text('—', style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                                  
                                  // Status
                                  Expanded(
                                    flex: 1,
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.circle, size: 8, color: u.isActive ? const Color(0xFF10B981) : const Color(0xFF94A3B8)),
                                          const SizedBox(width: 6),
                                          Text(u.isActive ? 'نشط' : 'موقوف', style: TextStyle(color: u.isActive ? const Color(0xFF10B981) : const Color(0xFF94A3B8), fontWeight: FontWeight.bold, fontSize: 13)),
                                        ],
                                      ),
                                    ),
                                  ),
                                  
                                  // Actions
                                  SizedBox(
                                    width: 56,
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: PopupMenuButton<String>(
                                        icon: Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: const Icon(Icons.more_vert_rounded, size: 18),
                                        ),
                                        onSelected: (v) => v == 'edit' ? _edit(u) : _resetPassword(u),
                                        itemBuilder: (_) => const [
                                          PopupMenuItem(value: 'edit', child: Text('تعديل')),
                                          PopupMenuItem(value: 'reset', child: Text('إعادة تعيين كلمة المرور')),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
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
  String? _error;

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
    if (_fullName.text.trim().isEmpty) {
      setState(() => _error = 'يرجى إدخال الاسم الكامل.');
      return;
    }
    if (_role == null) {
      setState(() => _error = 'يرجى اختيار الدور.');
      return;
    }
    if (!_isEdit) {
      if (_username.text.trim().isEmpty) {
        setState(() => _error = 'يرجى إدخال اسم المستخدم.');
        return;
      }
      if (_password.text.length < 8) {
        setState(() => _error = 'كلمة المرور يجب أن لا تقل عن 8 أحرف.');
        return;
      }
    }
    setState(() => _error = null);

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
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_error!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                ),
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
