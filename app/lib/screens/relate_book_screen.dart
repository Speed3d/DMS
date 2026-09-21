import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';


import '../core/session.dart';
import '../core/theme.dart';
import '../models.dart';

/// نتيجةُ شاشة «يخصّ كتاباً سابقاً».
class RelateChoice {
  const RelateChoice({required this.kind, required this.bookId, required this.title});
  final CaseMemberKind kind;
  final int bookId;

  /// عنوانُ المعاملة إن لزم إنشاؤها — **يكتبه المستخدم**.
  final String title;
}

/// شاشة اختيار الكتاب السابق الذي يخصّه هذا الكتاب (ADR-045).
///
/// 🔴 **شاشةٌ لا حوار** — قاعدةُ مشروعٍ مستقرّة: حقول البحث داخل `showDialog` تسبّب خلل
/// `disposed EngineFlutterView` على الويب.
///
/// 🔐 **والقائمة تأتي من نقاط الخادم المفلترة بقاعدة الرؤية**، فلا يظهر هنا كتابٌ محجوب —
/// ولا يصير البحث بابَ اكتشافٍ لما لا يُرى.
///
/// 🔴 **والعنوان يُعرض ويُعدَّل قبل الحفظ**: اشتقاقُه صامتاً من عنوان أوّل كتاب كان
/// **يُسرّب موضوع كتابٍ محجوب** لمن يرى الكتاب الآخر لاحقاً. وبعرضه على المُنشئ — وهو يرى
/// الطرفين أصلاً — **يقع قرار الإفصاح على إنسان**.
class RelateBookScreen extends ConsumerStatefulWidget {
  const RelateBookScreen({
    super.key,
    required this.selfKind,
    required this.selfBookId,
    required this.suggestedTitle,
    required this.hasCaseAlready,
  });

  final CaseMemberKind selfKind;
  final int selfBookId;

  /// عنوانٌ مُهيّأ من موضوع الكتاب الحالي — قابلٌ للتعديل.
  final String suggestedTitle;

  /// هل للكتاب الحالي معاملةٌ أصلاً؟ (فلا يُطلب عنوانٌ جديد).
  final bool hasCaseAlready;

  @override
  ConsumerState<RelateBookScreen> createState() => _RelateBookScreenState();
}

class _RelateBookScreenState extends ConsumerState<RelateBookScreen> {
  CaseMemberKind _tab = CaseMemberKind.incoming;
  String _search = '';
  late final TextEditingController _title =
      TextEditingController(text: widget.suggestedTitle);

  Future<List<_Row>>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _load() {
    final api = ref.read(apiClientProvider);
    _future = _tab == CaseMemberKind.incoming
        ? api.incomingList(search: _search).then((l) => l
            .where((b) => !(widget.selfKind == CaseMemberKind.incoming &&
                b.incomingId == widget.selfBookId))
            .map((b) => _Row(CaseMemberKind.incoming, b.incomingId, b.incomingNumber,
                b.receivedDate, b.subject))
            .toList())
        : api.outgoingList(search: _search).then((l) => l
            .where((b) => !(widget.selfKind == CaseMemberKind.outgoing &&
                b.outgoingId == widget.selfBookId))
            .map((b) => _Row(CaseMemberKind.outgoing, b.outgoingId, b.number, b.date, b.subject))
            .toList());
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final muted = Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.6);

    // 🔐 **تبويبٌ لا يملك قسمَه لا يُعرض** — بندٌ يقود إلى 403 أسوأ من غيابه.
    final canIncoming = session.hasModule('Incoming');
    final canOutgoing = session.hasModule('Outgoing');

    return Scaffold(
      appBar: AppBar(title: const Text('يخصّ كتاباً سابقاً'), centerTitle: true),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text(
                  'اختر الكتاب الذي يخصّه هذا الكتاب — وسيظهر الاثنان معاً في معاملةٍ واحدة، '
                  'فيرى من يفتح أيّهما بقيّةَ الخيط.',
                  style: TextStyle(fontSize: 12.5, height: 1.6, color: muted),
                ),
                const SizedBox(height: 14),

                if (!widget.hasCaseAlready) ...[
                  TextField(
                    controller: _title,
                    maxLength: 200,
                    decoration: const InputDecoration(
                      labelText: 'عنوان المعاملة',
                      helperText: 'يظهر في قائمة المعاملات — عدّله ليصف القضية',
                      prefixIcon: Icon(Icons.account_tree_rounded),
                    ),
                  ),
                  const SizedBox(height: 6),
                ],

                if (canIncoming && canOutgoing)
                  SegmentedButton<CaseMemberKind>(
                    segments: const [
                      ButtonSegment(
                          value: CaseMemberKind.incoming,
                          icon: Icon(Icons.call_received_rounded, size: 16),
                          label: Text('وارد')),
                      ButtonSegment(
                          value: CaseMemberKind.outgoing,
                          icon: Icon(Icons.call_made_rounded, size: 16),
                          label: Text('صادر')),
                    ],
                    selected: {_tab},
                    onSelectionChanged: (s) {
                      _tab = s.first;
                      _load();
                    },
                  ),
                const SizedBox(height: 12),

                TextField(
                  decoration: const InputDecoration(
                    labelText: 'بحث برقم الكتاب أو موضوعه',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  onChanged: (v) => _search = v,
                  onSubmitted: (_) => _load(),
                ),
                const SizedBox(height: 12),

                Expanded(
                  child: FutureBuilder<List<_Row>>(
                    future: _future,
                    builder: (context, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snap.hasError) {
                        return Center(
                            child: Text('تعذّر جلب الكتب: ${snap.error}',
                                style: TextStyle(color: AppColors.danger)));
                      }
                      final items = snap.data ?? const <_Row>[];
                      if (items.isEmpty) {
                        return Center(
                            child: Text('لا توجد كتب مطابقة.', style: TextStyle(color: muted)));
                      }
                      return ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final r = items[i];
                          return ListTile(
                            title: Text(r.number ?? '#${r.id}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 13.5)),
                            subtitle: Text(
                                '${r.subject}\n${DateFormat('yyyy/MM/dd').format(r.date)}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: muted)),
                            isThreeLine: true,
                            trailing: FilledButton(
                              onPressed: () => Navigator.pop(
                                  context,
                                  RelateChoice(
                                    kind: r.kind,
                                    bookId: r.id,
                                    title: _title.text.trim(),
                                  )),
                              child: const Text('ربط'),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Row {
  _Row(this.kind, this.id, this.number, this.date, this.subject);
  final CaseMemberKind kind;
  final int id;
  final String? number;
  final DateTime date;
  final String subject;
}
