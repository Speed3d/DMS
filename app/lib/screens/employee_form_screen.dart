import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../models.dart';
import '../widgets/custom_card.dart';

/// موظفٌ قائم يُسنَد إلى الشركة الفعّالة — الشخص معروف، والمطلوب شروطُ عمله هنا (ADR-027).
class LinkExistingEmployee {
  final int employeeId;
  final String fullName;
  const LinkExistingEmployee({required this.employeeId, required this.fullName});
}

/// Hint: نموذج إضافة/تعديل موظف — تبويبان: بيانات شخصية + بيانات الوظيفة في هذه الشركة.
class EmployeeFormScreen extends ConsumerStatefulWidget {
  /// `null` = موظف جديد.
  final int? employeeId;

  /// وضع **الإسناد**: ملفّ الشخص موجود في شركة أخرى، فلا تُطلب بياناته الشخصية.
  ///
  /// ⚠️ **لماذا وضعٌ ثالث لا إعادةُ استعمال «موظف جديد»؟** لأن ذلك الوضع كان يطلب الاسم
  /// ويتحقّق منه ثم **يتجاهله** عند الإسناد — فيملأ المستخدم حقلاً لا أثر له، وقد يكتب
  /// اسماً مخالفاً للمحفوظ فيظنّه سيُحفظ. والبيانات الشخصية ملكُ الملفّ الواحد، وتعديلها
  /// من هنا كان سيغيّرها على الشركة الأخرى أيضاً بلا أن يقصد أحد.
  final LinkExistingEmployee? link;

  const EmployeeFormScreen({super.key, this.employeeId, this.link})
      : assert(employeeId == null || link == null,
            'التعديل والإسناد وضعان متنافيان — لا يجتمعان في نموذج واحد.');

  @override
  ConsumerState<EmployeeFormScreen> createState() => _EmployeeFormScreenState();
}

class _EmployeeFormScreenState extends ConsumerState<EmployeeFormScreen> {
  final _formKey = GlobalKey<FormState>();

  // بيانات شخصية
  final _name = TextEditingController();
  final _nameEn = TextEditingController();
  final _nationalId = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _notes = TextEditingController();
  String _receiptLanguage = 'Arabic';

  // بيانات الوظيفة
  final _position = TextEditingController();
  final _positionEn = TextEditingController();
  final _baseSalary = TextEditingController();
  final _displayOrder = TextEditingController(text: '0');
  String _currency = 'IQD';
  DateTime _hireDate = DateTime.now();
  bool _isActive = true;

  bool _loading = false;
  bool _saving = false;
  String? _error;

  /// تنبيه «هذا الشخص مسجَّل أصلاً» بعد البحث برقم الهوية.
  ExistingEmployeeHint? _existing;

  // ── الصورة الشخصية ──
  //
  // ⚠️ **تُحتفظ في الذاكرة وتُرفع بعد الحفظ**: نقطة الرفع تحتاج `employeeId`، وهو لا يوجد
  //    قبل الإنشاء. ورفعُها بعد `createEmployee` (التي تُعيد الملفّ بمعرّفه) يجعل مسار
  //    «موظف جديد بصورة» يعمل في خطوةٍ واحدة عند المستخدم وإن كان طلبَين تحت السطح.
  Uint8List? _photoBytes;
  String? _photoName;

  /// صورةٌ محفوظة على الخادم (وضع التعديل) — تُعرض حتى يختار المستخدم بديلاً.
  Uint8List? _serverPhoto;

  bool get _isEdit => widget.employeeId != null;

  /// وضع الإسناد — الشخص موجود، والمطلوب شروط عمله في هذه الشركة وحدها.
  bool get _isLink => widget.link != null;

  /// شروط عمله في الشركة الأخرى — تُعبَّأ افتراضاً وتبقى مقفلة حتى يطلب تغييرها (ADR-028).
  EmploymentTemplate? _template;

  /// هل فتح المستخدم القفل ليكتب شروطاً مختلفة في هذه الشركة؟
  ///
  /// ⚠️ **مقفولٌ افتراضاً بقرار المالك**: الغالب أن الشروط واحدة، والقفل يمنع تعديلاً
  /// بالخطأ. وتاريخُ التعيين **خارج القفل دائماً** — فهو تاريخ بدء العمل هنا لا هناك.
  bool _customTerms = false;

  /// هل حقول شروط العمل قابلة للتحرير؟ تُقفل **فقط** في وضع الإسناد وقد جاء قالبٌ ولم
  /// يُطلب تغييره — فيما عدا ذلك تبقى كما كانت.
  bool get _fieldsEditable => !_isLink || _template == null || _customTerms;

  @override
  void initState() {
    super.initState();
    if (_isEdit) _load();
    if (_isLink) _loadTemplate();
  }

  /// يجلب شروط عمله من الشركة الأخرى ويعبّئ بها الحقول.
  Future<void> _loadTemplate() async {
    try {
      final t = await ref.read(apiClientProvider).employmentTemplate(widget.link!.employeeId);
      if (t == null || !mounted) return;
      setState(() {
        _template = t;
        _position.text = t.position;
        _positionEn.text = t.positionEn ?? '';
        _currency = t.salaryCurrency;
        _baseSalary.text = t.baseSalary.toStringAsFixed(0);
      });
    } catch (_) {
      // القالب مساعِدٌ لا حاسم: فشلُ جلبه يترك الحقول فارغة ويكملها المستخدم بيده.
    }
  }

  @override
  void dispose() {
    for (final c in [
      _name, _nameEn, _nationalId, _phone, _address, _notes,
      _position, _positionEn, _baseSalary, _displayOrder,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final e = await ref.read(apiClientProvider).employee(widget.employeeId!);
      _name.text = e.fullName;
      _nameEn.text = e.fullNameEn ?? '';
      _nationalId.text = e.nationalId ?? '';
      _phone.text = e.phone ?? '';
      _address.text = e.address ?? '';
      _notes.text = e.notes ?? '';
      _receiptLanguage = e.receiptLanguage;

      final job = e.employment;
      if (job != null) {
        _position.text = job.position;
        _positionEn.text = job.positionEn ?? '';
        _baseSalary.text = job.baseSalary.toStringAsFixed(0);
        _displayOrder.text = '${job.displayOrder}';
        _currency = job.salaryCurrency;
        _hireDate = job.hireDate;
        _isActive = job.isActive;
      }

      if (e.hasPhoto) {
        try {
          _serverPhoto = await ref.read(apiClientProvider).employeePhoto(widget.employeeId!);
        } catch (_) {
          // غياب الصورة لا يمنع تحرير الملفّ.
        }
      }
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _loading = false);
  }

  /// يختار صورةً ويُبقيها في الذاكرة — الرفع يقع عند الحفظ (انظر [_photoBytes]).
  Future<void> _pickPhoto() async {
    final messenger = ScaffoldMessenger.of(context);
    final res = await FilePicker.pickFiles(type: FileType.image, withData: true);
    if (res == null || res.files.single.bytes == null) return;
    final f = res.files.single;
    if (f.size > 2 * 1024 * 1024) {
      messenger.showSnackBar(const SnackBar(
          content: Text('حجم الصورة يتجاوز 2 م.ب'), backgroundColor: Colors.red));
      return;
    }
    setState(() {
      _photoBytes = f.bytes;
      _photoName = f.name;
    });
  }

  /// يبحث عن ملفّ قائم بنفس رقم الهوية — يمنع ملفّين لشخص واحد (ADR-023).
  Future<void> _lookup() async {
    final id = _nationalId.text.trim();
    if (id.isEmpty || _isEdit) return;
    try {
      final hint = await ref.read(apiClientProvider).lookupEmployee(id);
      if (mounted) setState(() => _existing = hint);
    } catch (_) {
      // البحث مساعِدٌ لا حاسم — فشلُه لا يمنع الإدخال.
    }
  }

  Map<String, dynamic> get _profileBody => {
        'fullName': _name.text.trim(),
        'fullNameEn': _nameEn.text.trim().isEmpty ? null : _nameEn.text.trim(),
        'nationalId': _nationalId.text.trim().isEmpty ? null : _nationalId.text.trim(),
        'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        'address': _address.text.trim().isEmpty ? null : _address.text.trim(),
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        'receiptLanguage': _receiptLanguage,
      };

  Map<String, dynamic> get _employmentBody => {
        'position': _position.text.trim(),
        'positionEn': _positionEn.text.trim().isEmpty ? null : _positionEn.text.trim(),
        'hireDate': _hireDate.toIso8601String(),
        'salaryCurrency': _currency,
        'baseSalary': double.tryParse(_baseSalary.text.trim()) ?? 0,
        'displayOrder': int.tryParse(_displayOrder.text.trim()) ?? 0,
        'isActive': _isActive,
      };

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      int employeeId;
      if (_isLink) {
        // إسنادٌ خالص: **شروط العمل وحدها** — البيانات الشخصية ملكُ الملفّ الواحد، وكتابتُها
        // من هنا كانت ستغيّرها على الشركة الأخرى معه.
        await api.saveEmployment(widget.link!.employeeId, _employmentBody);
        employeeId = widget.link!.employeeId;
      } else if (_isEdit) {
        await api.updateEmployee(widget.employeeId!, _profileBody);
        await api.saveEmployment(widget.employeeId!, _employmentBody);
        employeeId = widget.employeeId!;
      } else if (_existing != null && !_existing!.alreadyInThisCompany) {
        // الشخص مسجَّل في شركة أخرى ⇒ نُسنده لشركتنا بدل إنشاء ملفّ ثانٍ له.
        await api.saveEmployment(_existing!.employeeId, _employmentBody);
        employeeId = _existing!.employeeId;
      } else {
        employeeId = (await api.createEmployee(_profileBody, _employmentBody)).employeeId;
      }

      // ⚠️ **الصورة بعد الحفظ لا قبله** — نقطتُها تحتاج معرّفاً لا يوجد قبل الإنشاء.
      //    وفشلُ رفعها **لا يُسقط الحفظ**: الملفّ محفوظٌ فعلاً، وإسقاطُه هنا كان يُوهم
      //    المستخدم أن بياناته ضاعت فيُعيد الإدخال ويُنشئ ملفّاً ثانياً.
      if (_photoBytes != null) {
        try {
          await api.uploadEmployeePhoto(employeeId, _photoName ?? 'photo.jpg', _photoBytes!);
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('حُفظ الموظف، وتعذّر رفع الصورة: $e'),
                backgroundColor: Colors.orange));
          }
        }
      }

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canManage = ref.watch(sessionProvider).canManageEmployees;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isLink
            ? 'إسناد موظف قائم'
            : _isEdit
                ? 'تعديل موظف'
                : 'موظف جديد'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(32),
                children: [
                  if (_error != null) ...[
                    _ErrorBanner(message: _error!),
                    const SizedBox(height: 16),
                  ],

                  // ── تنبيه الملفّ القائم ──
                  if (_existing != null) ...[
                    _ExistingBanner(hint: _existing!),
                    const SizedBox(height: 16),
                  ],

                  // ── وضع الإسناد: هويّة الشخص للقراءة، لا حقولٌ تُملأ ──
                  if (_isLink) ...[
                    _LinkBanner(fullName: widget.link!.fullName),
                    const SizedBox(height: 20),
                  ],

                  // البيانات الشخصية تُخفى في وضع الإسناد: ملفُّ الشخص واحدٌ لكل الشركات،
                  // وتحريرُه من نموذج إسنادٍ كان يعدّله على الشركة الأخرى معه.
                  if (!_isLink)
                  _Section(
                    title: 'البيانات الشخصية',
                    icon: Icons.badge_outlined,
                    children: [
                      _PhotoPicker(
                        bytes: _photoBytes ?? _serverPhoto,
                        isNew: _photoBytes != null,
                        enabled: canManage && !_saving,
                        onPick: _pickPhoto,
                        onClear: _photoBytes == null
                            ? null
                            : () => setState(() {
                                  _photoBytes = null;
                                  _photoName = null;
                                }),
                      ),
                      const SizedBox(height: 14),
                      _Field(
                        controller: _name,
                        label: 'الاسم الكامل بالعربية *',
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'الاسم مطلوب' : null,
                      ),
                      _Field(
                        controller: _nameEn,
                        label: 'الاسم بالإنجليزية',
                        hint: 'إلزامي لمن لغة إيصاله إنجليزية',
                        validator: (v) =>
                            (_receiptLanguage == 'English' && (v == null || v.trim().isEmpty))
                                ? 'مطلوب لأن لغة الإيصال إنجليزية'
                                : null,
                      ),
                      _Field(controller: _nationalId, label: 'رقم الهوية', onEditingDone: _lookup),
                      _Field(controller: _phone, label: 'الهاتف'),
                      _Field(controller: _address, label: 'العنوان'),
                      _Dropdown<String>(
                        label: 'لغة إيصال الراتب',
                        value: _receiptLanguage,
                        items: const {'Arabic': 'العربية', 'English': 'الإنجليزية'},
                        onChanged: (v) => setState(() => _receiptLanguage = v!),
                      ),
                      _Field(controller: _notes, label: 'ملاحظات', maxLines: 3),
                    ],
                  ),
                  if (!_isLink) const SizedBox(height: 20),

                  _Section(
                    title: 'بيانات الوظيفة في هذه الشركة',
                    icon: Icons.work_outline_rounded,
                    subtitle: 'الراتب والصفة يخصّان الشركة الفعّالة وحدها — '
                        'للموظف في شركة أخرى شروطُ عملٍ مستقلّة هناك.',
                    children: [
                      // ── قالب الشركة الأخرى: معبّأ ومقفول حتى يُطلب تغييره (ADR-028) ──
                      if (_isLink && _template != null) ...[
                        _TemplateNotice(
                          sourceCompany: _template!.sourceCompanyName,
                          custom: _customTerms,
                          onChanged: (v) => setState(() => _customTerms = v),
                        ),
                        const SizedBox(height: 12),
                      ],
                      _Field(
                        controller: _position,
                        label: 'الصفة بالعربية *',
                        enabled: _fieldsEditable,
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'الصفة مطلوبة' : null,
                      ),
                      _Field(
                          controller: _positionEn,
                          label: 'الصفة بالإنجليزية',
                          enabled: _fieldsEditable),
                      // ⚠️ **تاريخ التعيين خارج القفل دائماً** (قرار المالك): هو تاريخ بدء
                      //    العمل في **هذه** الشركة لا المنقول عن الأخرى، ويؤثّر في مكافأة
                      //    نهاية الخدمة وفي الشهر الجزئي الأول.
                      _DateField(
                        label: 'تاريخ التعيين *',
                        value: _hireDate,
                        onChanged: (d) => setState(() => _hireDate = d),
                      ),
                      _Dropdown<String>(
                        label: 'عملة الراتب',
                        value: _currency,
                        items: const {'IQD': 'دينار عراقي', 'USD': 'دولار أمريكي'},
                        onChanged: _fieldsEditable
                            ? (v) => setState(() => _currency = v!)
                            : null,
                      ),
                      _Field(
                        controller: _baseSalary,
                        label: 'الراتب الأساسي *',
                        enabled: _fieldsEditable,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                        validator: (v) {
                          final n = double.tryParse((v ?? '').trim());
                          if (n == null) return 'أدخل رقماً صحيحاً';
                          if (n < 0) return 'الراتب لا يكون سالباً';
                          return null;
                        },
                      ),
                      _Field(
                        controller: _displayOrder,
                        label: 'الترتيب في كشف الرواتب',
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      ),
                      // `Material` شفّافة: `ListTile` داخل `CustomCard` يرسم خلفيته وأثر
                      // النقر على أقرب `Material` فوقه، وبطاقةُ `DecoratedBox` تحجبهما.
                      Material(
                        type: MaterialType.transparency,
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _isActive,
                          onChanged: (v) => setState(() => _isActive = v),
                          title: const Text('على رأس العمل', style: TextStyle(fontSize: 14)),
                          subtitle: Text('غير الفعّال لا يُدرَج في كشوف الشهور الجديدة',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: theme.textTheme.bodyMedium?.color
                                      ?.withValues(alpha: 0.6))),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),

                  SizedBox(
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: (_saving || !canManage) ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.save_rounded),
                      label: Text(
                          _saving
                              ? 'جارٍ الحفظ...'
                              : _isLink
                                  ? 'إسناده إلى هذه الشركة'
                                  : 'حفظ',
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
                              color: theme.textTheme.bodyMedium?.color
                                  ?.withValues(alpha: 0.6))),
                    ),
                ],
              ),
            ),
    );
  }
}

/// هويّة الشخص في وضع الإسناد — **للقراءة**، فبياناته الشخصية ملكُ ملفّه الواحد.
class _LinkBanner extends StatelessWidget {
  final String fullName;
  const _LinkBanner({required this.fullName});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final color = isDark ? AppColors.successDark : AppColors.success;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: color.withValues(alpha: 0.18),
            child: Text(
              fullName.trim().isNotEmpty ? fullName.trim().characters.first : '؟',
              style: TextStyle(
                  fontSize: 19, fontWeight: FontWeight.w900, color: color),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(fullName,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(
                  'ملفّه موجود في النظام من شركة أخرى. حدِّد شروط عمله في هذه الشركة — '
                  'وبياناته الشخصية تبقى كما هي.',
                  style: TextStyle(
                      fontSize: 12.5,
                      height: 1.6,
                      color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.75)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// بطاقة «شروطه منقولة من شركةٍ أخرى» + مفتاح فتح القفل (ADR-028).
class _TemplateNotice extends StatelessWidget {
  final String sourceCompany;
  final bool custom;
  final ValueChanged<bool> onChanged;
  const _TemplateNotice({
    required this.sourceCompany,
    required this.custom,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final color = isDark ? AppColors.goldBrightDark : AppColors.navyDeep;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.content_copy_rounded, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                custom
                    ? 'تكتب شروطاً مستقلّة في هذه الشركة — لا تُغيّر شيئاً في «$sourceCompany».'
                    : 'الصفة والعملة والراتب منقولة من «$sourceCompany».',
                style: TextStyle(fontSize: 12.5, height: 1.6, color: color),
              ),
            ),
          ]),
          // `Material` شفّافة: `SwitchListTile` يرسم خلفيته على أقرب `Material` فوقه،
          // وحاوية ذات خلفية تحجبه (الدرس المسجَّل في `hr_render_test`).
          Material(
            type: MaterialType.transparency,
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: custom,
              onChanged: onChanged,
              title: const Text('شروط مختلفة في هذه الشركة',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              subtitle: Text('افتحه لتحديد صفةٍ أو راتبٍ مختلف',
                  style: TextStyle(
                      fontSize: 11.5,
                      color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6))),
            ),
          ),
        ],
      ),
    );
  }
}

/// «هذا الشخص مسجَّل أصلاً» — الجسر الوحيد بين الشركات، ويعرض الاسم فقط.
class _ExistingBanner extends StatelessWidget {
  final ExistingEmployeeHint hint;
  const _ExistingBanner({required this.hint});

  @override
  Widget build(BuildContext context) {
    final here = hint.alreadyInThisCompany;
    final color = here ? AppColors.danger : AppColors.warn;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(here ? Icons.error_outline_rounded : Icons.info_outline_rounded, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              here
                  ? 'رقم الهوية هذا مسجَّل بالفعل للموظف «${hint.fullName}» في هذه الشركة.'
                  : 'هذا الشخص («${hint.fullName}») مسجَّل في النظام ويعمل في شركة أخرى.\n'
                      'الحفظ سيُسنده إلى شركتك بشروط العمل أدناه — بلا إنشاء ملفّ ثانٍ له.',
              style: TextStyle(fontSize: 13, color: color, height: 1.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
        ),
        child: Row(children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.danger),
          const SizedBox(width: 12),
          Expanded(
              child: Text(message,
                  style: const TextStyle(fontSize: 13, color: AppColors.danger, height: 1.6))),
        ]),
      );
}

class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final String? subtitle;
  final List<Widget> children;
  const _Section(
      {required this.title, required this.icon, this.subtitle, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(icon, size: 20, color: AppColors.gold),
            const SizedBox(width: 10),
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
          ]),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(subtitle!,
                style: TextStyle(
                    fontSize: 12.5,
                    height: 1.6,
                    color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6))),
          ],
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

/// منتقي الصورة الشخصية — معاينةٌ دائرية وزرّ اختيار.
///
/// ⚠️ **الصورة المختارة لم تُرفع بعد** ولذلك تُعلَّم «ستُرفع عند الحفظ»: لولا ذلك لظنّ
/// المستخدم أنها حُفظت فأغلق النموذج بلا حفظٍ فضاعت.
class _PhotoPicker extends StatelessWidget {
  final Uint8List? bytes;
  final bool isNew;
  final bool enabled;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  const _PhotoPicker({
    required this.bytes, required this.isNew, required this.enabled,
    required this.onPick, this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(children: [
      CircleAvatar(
        radius: 34,
        backgroundColor: AppColors.navyDeep.withValues(alpha: 0.10),
        backgroundImage: bytes != null ? MemoryImage(bytes!) : null,
        child: bytes == null
            ? Icon(Icons.person_rounded,
                size: 34, color: AppColors.navyDeep.withValues(alpha: 0.45))
            : null,
      ),
      const SizedBox(width: 16),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('الصورة الشخصية',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(
              isNew
                  ? 'صورة جديدة — تُرفع عند الحفظ'
                  : (bytes != null ? 'صورة محفوظة' : 'بلا صورة — PNG أو JPEG حتى 2 م.ب'),
              style: TextStyle(
                  fontSize: 12,
                  color: isNew
                      ? AppColors.gold
                      : theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 8),
            Row(children: [
              OutlinedButton.icon(
                onPressed: enabled ? onPick : null,
                icon: const Icon(Icons.image_outlined, size: 16),
                label: Text(bytes == null ? 'اختيار صورة' : 'تغيير',
                    style: const TextStyle(fontSize: 12.5)),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
              ),
              if (onClear != null) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: enabled ? onClear : null,
                  child: const Text('تراجع', style: TextStyle(fontSize: 12.5)),
                ),
              ],
            ]),
          ],
        ),
      ),
    ]);
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final int maxLines;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;
  final VoidCallback? onEditingDone;

  /// حقلٌ مقروءٌ لا محرَّر — يُستعمل لقفل شروط العمل المنقولة عن شركةٍ أخرى (ADR-028).
  ///
  /// ⚠️ **`enabled` لا `readOnly`**: الأول يُبهت الحقل فيُرى مقفولاً بلا شرح، والثاني يبدو
  /// محرَّراً ثم لا يستجيب — وهو أسوأ ما يُقدَّم لمستخدم.
  final bool enabled;

  const _Field({
    required this.controller,
    required this.label,
    this.hint,
    this.maxLines = 1,
    this.keyboardType,
    this.inputFormatters,
    this.validator,
    this.onEditingDone,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: TextFormField(
          controller: controller,
          enabled: enabled,
          maxLines: maxLines,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          validator: validator,
          onEditingComplete: onEditingDone,
          onTapOutside: (_) => onEditingDone?.call(),
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
        ),
      );
}

class _Dropdown<T> extends StatelessWidget {
  final String label;
  final T value;
  final Map<T, String> items;
  /// `null` تُعطّل القائمة — نظير `enabled: false` في [_Field] (سلوك Flutter المعتاد).
  final ValueChanged<T?>? onChanged;
  const _Dropdown(
      {required this.label, required this.value, required this.items, required this.onChanged});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: DropdownButtonFormField<T>(
          initialValue: value,
          decoration: InputDecoration(
            labelText: label,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
          items: items.entries
              .map((e) => DropdownMenuItem<T>(value: e.key, child: Text(e.value)))
              .toList(),
          onChanged: onChanged,
        ),
      );
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  const _DateField({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: value,
            firstDate: DateTime(1970),
            lastDate: DateTime(2100),
          );
          if (picked != null) onChanged(picked);
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
          child: Row(children: [
            Icon(Icons.calendar_today_rounded,
                size: 16, color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.5)),
            const SizedBox(width: 10),
            Text(DateFormat('yyyy-MM-dd').format(value), style: const TextStyle(fontSize: 14)),
          ]),
        ),
      ),
    );
  }
}
