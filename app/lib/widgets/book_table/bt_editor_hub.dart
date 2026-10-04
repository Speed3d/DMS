// ⚠️ واجهتان «تجريبيتان» في flutter_quill لا بديل عنهما: اعتراضُ اللصق (`onClipboardPaste`) ومفاتيحُ الخلية قبل Quill
//    (`onKeyPressed`). الإصدار مثبَّتٌ في `pubspec.lock`، **وحرّاس `outgoing_table_editor_test.dart` تسقط** إن تغيّر سلوكهما بترقية.
// ignore_for_file: experimental_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:quill_native_bridge/quill_native_bridge.dart';

import '../../core/book_table/book_table.dart';
import '../../core/book_table/table_formulas.dart';
import '../../core/book_table/table_ops.dart';
import '../../core/book_table/table_paste.dart';
import '../../core/book_table/table_serializer.dart';
import 'bt_table_view.dart';

/// التحديد في جدول: نقطة الارتكاز (حيث بدأ) والرأس (حيث انتهى) — والمستطيل بينهما.
class BtSelection {
  const BtSelection(this.tableId, this.ar, this.ac, this.hr, this.hc);
  final String tableId;
  final int ar, ac, hr, hc;
  int get top => math.min(ar, hr);
  int get bottom => math.max(ar, hr);
  int get left => math.min(ac, hc);
  int get right => math.max(ac, hc);
  bool get single => ar == hr && ac == hc;
}

/// جدولٌ في المستند بموضعه.
class BtLocated {
  const BtLocated(this.offset, this.table);
  final int offset;
  final BtTable table;
}

/// محرّك تحرير الجداول داخل متن الكتاب (ADR-057، الدفعة ٧).
///
/// 🔑 **الحالة هنا لا في شجرة الودجات**: Quill يعيد بناء البلوك المضمَّن مع كل تغييرٍ في المستند، فتحديدٌ أو خليةٌ مفتوحة
/// محفوظةٌ في `State` الجدول **تضيع مع أوّل حرفٍ يُكتب** — والمحرّك يبقى ما بقيت الشاشة.
///
/// 📝 **الكتابة في الخلية لا تمسّ المستند حتى تُغادَر** (Tab · نقرة خارجها · Esc · أيّ عمليةٍ على الجدول): المستند يتغيّر
/// مرّةً للخلية لا مرّةً للحرف — فلا يُعاد بناء الجدول تحت المؤشّر، والتراجع في المتن خطوةٌ للخلية. **وما يُرسَل ويُحفظ
/// يقرأ الخلية المفتوحة** (`bodyDelta`) — فلا يضيع ما كُتب ولم يُغادَر.
///
/// 🔴 **المحرّر الرئيسيّ يستردّ التركيز عند النقر على خلية** (كشفته تجربة الدفعة ٠: `Ctrl+A` بعدها **مسح المستند كلَّه**) —
/// فتركيز الخلية يُطلب **بعد** انتهاء النقرة، واستردادٌ في الإطارين التاليين للفتح يُعاد إلى الخلية لا يُغلق الجدول.
class BtEditorHub extends ChangeNotifier {
  BtEditorHub({
    required this.fetchWords,
    this.onMessage,
    this.askPasteAsTable,
    this.focusMain,
    Future<String?> Function()? readClipboardHtml,
    Future<String?> Function()? readClipboardText,
    Future<void> Function(String text)? writeClipboardText,
  })  : _readHtml = readClipboardHtml ?? _defaultReadHtml,
        _readText = readClipboardText ?? _defaultReadText,
        _writeText = writeClipboardText ?? _defaultWriteText;

  /// التفقيط من الخادم وحده (`GET /outgoing/number-words`) — تطبيقٌ واحد لا اثنان يتباعدان.
  final Future<String> Function(num value, String currency) fetchWords;

  /// رسالةٌ للمستخدم (سببُ رفض عملية · تنبيه).
  final void Function(String message)? onMessage;

  /// لصقُ جدولٍ في نصٍّ عاديّ: «إدراجه جدولاً؟» — `true` جدول، `false` نصّ.
  final Future<bool> Function(int rows, int cols)? askPasteAsTable;

  /// إعادة التركيز إلى المتن عند موضعٍ بعد الخروج من الجدول بـEsc.
  final void Function(int offset)? focusMain;

  final Future<String?> Function() _readHtml;
  final Future<String?> Function() _readText;
  final Future<void> Function(String text) _writeText;

  quill.QuillController? _main;
  quill.QuillController get main => _main!;

  void attach(quill.QuillController controller) {
    _main?.removeListener(_onMainChanged);
    _main = controller..addListener(_onMainChanged);
  }

  // ─────────────────────────── الحالة ───────────────────────────

  BtSelection? sel;
  String? editingCellId;
  quill.QuillController? cell;
  FocusNode? cellFocus;
  GlobalKey? cellKey;
  ScrollController? _cellScroll;
  final tableFocus = FocusNode(debugLabel: 'bt-table');

  /// يتغيّر مع الكتابة في الخلية (بعد توقّفٍ قصير) — المعاينة والجمع الحيّ يتبعانه.
  final contentTick = ValueNotifier<int>(0);

  /// نافذة الاسترداد: من فتح الخلية حتى إطارين بعده — **بالإطارات لا بالساعة** (الاختبارات لا تُقدّم الساعة الحقيقية،
  /// والمتصفّح البطيء قد يتجاوز أيّ مدّةٍ ثابتة).
  bool _activating = false;
  Timer? _typingTimer;
  bool _wasEmpty = false;
  Map<String, dynamic>? _emptyStyle;
  bool _disposed = false;

  // سحب حدّ عمود: يُرى وهو يُسحب، ويُكتب عند الإفلات
  String? dragTableId;
  List<double>? dragWeights;

  bool get editing => editingCellId != null && cell != null;
  bool get active => sel != null;

  // ─────────────────────────── القراءة ───────────────────────────

  final _parsed = <String, BtTable>{};

  /// قراءة بيانات البلوك — بذاكرةٍ صغيرة (البلوك يُعاد بناؤه كثيراً، وفاتورةٌ بـ600 صفّ لا تُحلَّل في كل إطار).
  BtTable parse(Object? data) {
    final key = data is String ? data : jsonEncode(data);
    final hit = _parsed[key];
    if (hit != null) return hit;
    final t = BtJson.fromEmbedData(data);
    if (_parsed.length > 40) _parsed.remove(_parsed.keys.first);
    _parsed[key] = t;
    return t;
  }

  /// الجدول بمعرّفه وموضعه في المستند — أو `null` إن لم يعد موجوداً (حُذف · تراجع).
  BtLocated? locate(String id) {
    var offset = 0;
    for (final op in main.document.toDelta().toList()) {
      final data = op.data;
      if (data is Map && data.containsKey(kDmsTableEmbed)) {
        try {
          final t = parse(data[kDmsTableEmbed]);
          if (t.id == id) return BtLocated(offset, t);
        } catch (_) {
          // بلوكٌ تالف — يُتخطّى
        }
      }
      offset += op.length ?? 1;
    }
    return null;
  }

  int get tableCount =>
      main.document.toDelta().toList().where((op) => op.data is Map && (op.data as Map).containsKey(kDmsTableEmbed)).length;

  /// الجدول كما يراه المستخدم الآن: المخزَّن **ومعه ما كُتب في الخلية المفتوحة**.
  BtTable current(BtTable t) {
    final id = editingCellId;
    if (id == null || cell == null || sel?.tableId != t.id) return t;
    final copy = t.copy();
    final s = copy.findCell(id);
    if (s == null) return t;
    _writeCell(s.cell);
    return copy;
  }

  /// الجدول النشط (بالخلية المفتوحة) — لشريط الجدول.
  BtTable? get activeTable {
    final s = sel;
    if (s == null) return null;
    final loc = locate(s.tableId);
    return loc == null ? null : current(loc.table);
  }

  BtSlot? get headSlot {
    final t = activeTable;
    final s = sel;
    return t == null || s == null ? null : t.ownerOf(s.hr, s.hc);
  }

  /// Delta المتن كاملاً **بالخلية المفتوحة** — للحفظ والمعاينة والمسوّدة.
  List<Map<String, dynamic>> bodyDelta() {
    final ops = main.document.toDelta().toJson().cast<Map<String, dynamic>>();
    final s = sel;
    if (!editing || s == null) return ops;
    return [
      for (final op in ops)
        if (op['insert'] is Map && (op['insert'] as Map).containsKey(kDmsTableEmbed))
          _withOverlay(op, s.tableId)
        else
          op,
    ];
  }

  Map<String, dynamic> _withOverlay(Map<String, dynamic> op, String tableId) {
    try {
      final t = parse((op['insert'] as Map)[kDmsTableEmbed]);
      if (t.id != tableId) return op;
      return {...op, 'insert': {kDmsTableEmbed: BtJson.toEmbedData(current(t))}};
    } catch (_) {
      return op;
    }
  }

  bool inSelection(String tableId, BtSlot s) {
    final x = sel;
    if (x == null || x.tableId != tableId) return false;
    return s.row <= x.bottom && s.row + s.cell.rowSpan - 1 >= x.top && s.col <= x.right && s.col + s.cell.colSpan - 1 >= x.left;
  }

  bool isHead(String tableId, BtSlot s) {
    final x = sel;
    return x != null && x.tableId == tableId && s.row <= x.hr && s.row + s.cell.rowSpan > x.hr && s.col <= x.hc && s.col + s.cell.colSpan > x.hc;
  }

  // ─────────────────────────── «كتابة بالحروف» ───────────────────────────

  final _words = <String, String>{};
  /// المطلوب من الخادم — **آخرُ قيمةٍ لكل خلية حروف** (مفهرساً بمعرّفها): كتابة «2,500» حرفاً حرفاً تمرّ بـ2 و25 و250…
  /// ولا يُطلب منها إلا ما بقي عند التوقّف.
  final _wanted = <String, (String, num, String)>{};
  Timer? _wordsTimer;

  /// قيمٌ فشل طلبها — لا تُعاد حتى تتغيّر القيمة (وإلا صار خادمٌ متوقّف طلباً كل 400 ملّيثانية بلا نهاية).
  final _failed = <String>{};

  /// نصوص الحروف للجدول (من الخادم) — وما لم يصل بعد يُطلب بعد توقّفٍ قصير (لا طلبٌ لكل رقمٍ يُكتب).
  Map<String, String> wordsFor(BtTable t) {
    final out = <String, String>{};
    Map<String, BtComputed>? computed;
    for (final s in t.masters) {
      final w = s.cell.words;
      if (w == null) continue;
      computed ??= BtFormulas.evaluate(t);
      final v = BtFormulas.wordsSource(t, w, computed);
      if (v == null) continue;
      final key = '$v|${w.currency}';
      final hit = _words[key];
      if (hit != null) {
        out[s.cell.id] = hit;
      } else if (_wanted[s.cell.id]?.$1 != key && !_failed.contains(key)) {
        _wanted[s.cell.id] = (key, v, w.currency);
        _wordsTimer?.cancel();
        _wordsTimer = Timer(const Duration(milliseconds: 400), _flushWords);
      }
    }
    return out;
  }

  Future<void> _flushWords() async {
    final batch = Map.of(_wanted);
    _wanted.clear();
    final done = <String>{};
    for (final (key, value, currency) in batch.values) {
      if (!done.add(key) || _words.containsKey(key)) continue;
      try {
        final text = await fetchWords(value, currency);
        if (_disposed) return;
        if (_words.length > 500) _words.remove(_words.keys.first);
        _words[key] = text;
      } catch (_) {
        // يبقى «…» — والطباعة تولّده في الخادم على كل حال
        if (_failed.length > 200) _failed.clear();
        _failed.add(key);
      }
    }
    if (!_disposed) notifyListeners();
  }

  /// نصّ الحروف لقيمةٍ وعملة — لمعاينة النافذة.
  Future<String?> wordsText(num value, String currency) async {
    final key = '$value|$currency';
    if (_words.containsKey(key)) return _words[key];
    try {
      final text = await fetchWords(value, currency);
      _words[key] = text;
      return text;
    } catch (_) {
      return null;
    }
  }

  // ─────────────────────────── الكتابة في المستند ───────────────────────────

  /// يستبدل البلوك في مكانه — **ولا يُلبسه تنسيقاً مُفعَّلاً** (عريضٌ مضغوطٌ في المتن كان سيُطبَّق على البلوك نفسه).
  bool _replace(String id, BtTable t) {
    final loc = locate(id);
    if (loc == null) return false;
    final problem = BtOps.validate(t);
    if (problem != null) {
      onMessage?.call(problem);
      return false;
    }
    _embedInto(loc.offset, 1, t, null);
    return true;
  }

  /// [keepFocus]: تغييرٌ داخل الجدول لا يمسّ التركيز (`ignoreFocus`) — ⚠️ **وQuill لا يعيد بناء المتن معه**، فالجدول يقرأ
  /// بياناته من المستند عبر المحرّك (`BtTableEditor`) لا من نسخةٍ التقطها عند بنائه. والإدراج والحذف (سطرٌ يُضاف أو يُزال)
  /// يحتاجان إعادة بناءٍ كاملة ⟵ بلا `ignoreFocus`، والتركيز يُستردّ في نافذة الاسترداد.
  void _embedInto(int index, int len, BtTable t, TextSelection? selection, {bool keepFocus = true}) {
    final toggled = main.toggledStyle;
    main.toggledStyle = const quill.Style();
    // 🔴 **كل تغييرٍ في الجدول خطوةُ تراجعٍ مستقلّة**: Quill يدمج ما يقع في 400 ملّيثانية في خطوةٍ واحدة — وحفظُ الخلية ثم
    //    «صفٌّ تحت» يقعان في اللحظة نفسها، فكان Ctrl+Z سيمحو المكتوب مع الصفّ. وبعده كذلك: كتابةُ المتن لا تُدمج فيه.
    main.document.history.lastRecorded = 0;
    main.replaceText(index, len, quill.CustomBlockEmbed(kDmsTableEmbed, BtJson.toEmbedData(t)), selection, ignoreFocus: keepFocus);
    main.document.history.lastRecorded = 0;
    main.toggledStyle = toggled;
  }

  /// يُدرج جدولاً عند المؤشّر — ويفتح خليته الأولى للكتابة.
  void insertTable(BtTable t) {
    stopEditing();
    if (tableCount >= 25) {
      onMessage?.call('بلغ الكتاب الحدّ الأعلى للجداول (25).');
      return;
    }
    final s = main.selection;
    final max = math.max(0, main.document.length - 1);
    final index = (s.isValid ? s.start : max).clamp(0, max);
    sel = BtSelection(t.id, 0, 0, 0, 0);
    _arm();
    _embedInto(index, 0, t, TextSelection.collapsed(offset: index + 1), keepFocus: false);
    final first = t.ownerOf(0, 0)!.cell;
    if (_editable(first)) {
      _beginEdit(first);
    } else {
      _focusTableSoon();
    }
    notifyListeners();
  }

  void deleteTable() {
    final s = sel;
    if (s == null) return;
    _endEdit();
    final loc = locate(s.tableId);
    sel = null;
    if (loc != null) main.replaceText(loc.offset, 1, '', TextSelection.collapsed(offset: loc.offset));
    notifyListeners();
    if (loc != null) focusMain?.call(loc.offset);
  }

  /// يطبّق عمليةً على الجدول النشط — وعمليةٌ تترك جدولاً معطوباً **تُرفض** (`validate`) فلا يصل الخادمَ ما يرفضه.
  bool apply(BtTable Function(BtTable t, BtSelection s) op) {
    final s = sel;
    if (s == null) return false;
    final editingId = editingCellId;
    commitCell();
    final loc = locate(s.tableId);
    if (loc == null) {
      exit();
      return false;
    }
    final next = op(loc.table, s);
    if (identical(next, loc.table)) return false;
    if (!_replace(s.tableId, next)) return false;
    _clamp(next);
    if (editingId != null) {
      final now = next.findCell(editingId);
      if (now == null || !_editable(now.cell)) {
        _endEdit();
        _focusTableSoon();
      } else if (jsonEncode(now.cell.delta) != jsonEncode(_cellDelta())) {
        // العملية غيّرت نصّ الخلية المفتوحة (تنسيقٌ على التحديد) ⟵ تُفتح من جديد بما صار فيها
        _beginEdit(now.cell);
      } else {
        _focusCellSoon();
      }
    } else {
      _focusTableSoon();
    }
    notifyListeners();
    return true;
  }

  /// عمليةٌ على المستطيل المحدّد.
  bool applyRect(BtTable Function(BtTable t, int top, int left, int bottom, int right) op) =>
      apply((t, s) => op(t, s.top, s.left, s.bottom, s.right));

  void _clamp(BtTable t) {
    final s = sel;
    if (s == null) return;
    int r(int v) => v.clamp(0, t.rowCount - 1);
    int c(int v) => v.clamp(0, t.colCount - 1);
    sel = BtSelection(s.tableId, r(s.ar), c(s.ac), r(s.hr), c(s.hc));
  }

  // ─────────────────────────── التحديد والتحرير ───────────────────────────

  /// النقر على خلية: تُفتح للكتابة (كما في Word) — ومع Shift يمتدّ التحديد.
  void tapCell(String tableId, int r, int c, {bool extend = false}) {
    if (extend && sel?.tableId == tableId) {
      stopEditing(notify: false);
      final s = sel!;
      sel = _expand(tableId, BtSelection(tableId, s.ar, s.ac, r, c));
      _focusTableSoon();
      notifyListeners();
      return;
    }
    final loc = locate(tableId);
    final o = loc?.table.ownerOf(r, c);
    if (o == null) return;
    if (editingCellId == o.cell.id) return;
    commitCell();
    final fresh = locate(tableId)?.table.ownerOf(r, c);   // الحفظ قد غيّر المستند
    if (fresh == null) return;
    sel = BtSelection(tableId, fresh.row, fresh.col, fresh.row, fresh.col);
    if (_editable(fresh.cell)) {
      _beginEdit(fresh.cell);
    } else {
      _endEdit();
      _focusTableSoon();
    }
    notifyListeners();
  }

  /// خلية الجمع والحروف يولّدها النظام — لا تُكتب.
  static bool _editable(BtCell c) => c.formula == null && c.words == null;

  /// تحديدٌ يقطع دمجاً يتّسع ليشمله كلَّه (كما يفعل Excel) — فالدمج والتنسيق لا يقعان على نصف خلية.
  BtSelection _expand(String tableId, BtSelection s) {
    final t = locate(tableId)?.table;
    if (t == null) return s;
    var top = s.top, left = s.left, bottom = s.bottom, right = s.right;
    var changed = true;
    while (changed) {
      changed = false;
      for (final m in t.masters) {
        final mb = m.row + m.cell.rowSpan - 1, mr = m.col + m.cell.colSpan - 1;
        final overlaps = m.row <= bottom && mb >= top && m.col <= right && mr >= left;
        if (!overlaps) continue;
        if (m.row < top || mb > bottom || m.col < left || mr > right) {
          top = math.min(top, m.row);
          left = math.min(left, m.col);
          bottom = math.max(bottom, mb);
          right = math.max(right, mr);
          changed = true;
        }
      }
    }
    // الرأس يبقى حيث وقف، والارتكاز يأخذ الركن المقابل
    final ar = s.hr >= s.ar ? top : bottom, ac = s.hc >= s.ac ? left : right;
    final hr = s.hr >= s.ar ? bottom : top, hc = s.hc >= s.ac ? right : left;
    return BtSelection(tableId, ar, ac, hr, hc);
  }

  /// يفتح الخلية للكتابة.
  ///
  /// 🔴 **محرّرٌ واحد للجلسة كلّها**: الانتقال بين الخلايا (Tab · نقرة) **يبدّل مستند المحرّر القائم** ولا يُنشئ غيره —
  /// والودجة بمفتاحها العامّ تنتقل إلى الخلية الجديدة **بتركيزها واتصالها بلوحة المفاتيح**. كان كلُّ Tab يُغلق محرّراً ويفتح
  /// آخر، فتضيع الحروف المكتوبة فوراً بعده (كشفه المتصفّح الحقيقيّ: «Tab ثم كتابة» يمرّ والنصّ لا يصل).
  void _beginEdit(BtCell stored, {String? typed}) {
    var delta = stored.delta;
    if (typed != null) {
      final c = stored.copy();
      BtOps.setText(c, typed);
      delta = c.delta;
    }
    final doc = quill.Document.fromJson(delta);
    _wasEmpty = stored.isEmpty && typed == null;
    _emptyStyle = stored.textStyle;
    final existing = cell;
    if (existing != null) {
      _typingTimer?.cancel();
      existing.removeListener(_onCellChanged);
      existing.document = doc;
      existing.updateSelection(TextSelection.collapsed(offset: math.max(0, doc.length - 1)), quill.ChangeSource.local);
      existing.toggledStyle = _wasEmpty && _emptyStyle != null ? quill.Style.fromJson(_emptyStyle) : const quill.Style();
      existing.addListener(_onCellChanged);
      editingCellId = stored.id;
      _focusCellSoon();
      return;
    }
    final ctl = quill.QuillController(
      document: doc,
      selection: TextSelection.collapsed(offset: math.max(0, doc.length - 1)),
      config: quill.QuillControllerConfig(clipboardConfig: quill.QuillClipboardConfig(onClipboardPaste: _onCellPaste)),
    );
    if (_wasEmpty && _emptyStyle != null) ctl.toggledStyle = quill.Style.fromJson(_emptyStyle);
    ctl.addListener(_onCellChanged);
    cell = ctl;
    cellFocus = FocusNode(debugLabel: 'bt-cell');
    cellKey = GlobalKey(debugLabel: 'bt-cell-editor');
    _cellScroll = ScrollController();
    editingCellId = stored.id;
    _focusCellSoon();
  }

  void _onCellChanged() {
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(milliseconds: 150), () {
      if (_disposed) return;
      contentTick.value++;
      notifyListeners();   // الجمع الحيّ والحروف تتبع الكتابة
    });
  }

  /// Delta الخلية المفتوحة بلا ما لا يُطبع.
  List<Map<String, dynamic>> _cellDelta() => BtOps.sanitizeDelta(cell!.document.toDelta().toJson().cast<Map<String, dynamic>>());

  /// يكتب الخلية المفتوحة في [target] — وخليةٌ كانت فارغةً بتنسيقٍ محفوظ يلبس نصُّها الجديدُ تنسيقَها
  /// (Quill يُسقط التنسيق المُفعَّل مع أوّل نقرة — وخليةُ البند العريضة في الفاتورة يجب أن تبقى عريضة).
  void _writeCell(BtCell target) {
    var delta = _cellDelta();
    final hasText = delta.any((op) => (op['insert'] as String).trim().isNotEmpty);
    final plain = delta.every((op) {
      final a = op['attributes'] as Map?;
      return (op['insert'] as String).trim().isEmpty || a == null || a.keys.every(BtOps.cellBlockKeys.contains);
    });
    if (_wasEmpty && hasText && plain && _emptyStyle != null) {
      final styled = target.copy()..delta = delta;
      final style = Map<String, dynamic>.from(_emptyStyle!);
      final c = BtOps.formatCells(BtTable(id: 'x', cols: [BtCol(id: 'k')], rows: [BtRow(id: 'r', cells: [styled])]), 0, 0, 0, 0, style);
      delta = c.rows.first.cells.first!.delta;
    }
    target.delta = delta;
    if (hasText) {
      final first = delta.firstWhere((op) => (op['insert'] as String).trim().isNotEmpty);
      final a = (first['attributes'] as Map?)?.cast<String, dynamic>();
      final inline = a == null ? null : {for (final e in a.entries) if (!BtOps.cellBlockKeys.contains(e.key)) e.key: e.value};
      target.textStyle = inline == null || inline.isEmpty ? null : inline;
    }
  }

  /// يكتب الخلية المفتوحة في المستند إن تغيّرت — وتبقى مفتوحة.
  void commitCell() {
    final id = editingCellId;
    final s = sel;
    if (id == null || s == null || cell == null) return;
    final loc = locate(s.tableId);
    final stored = loc?.table.findCell(id)?.cell;
    if (loc == null || stored == null) {
      _endEdit();
      return;
    }
    final probe = stored.copy();
    _writeCell(probe);
    if (jsonEncode(probe.delta) == jsonEncode(stored.delta) && jsonEncode(probe.textStyle) == jsonEncode(stored.textStyle)) return;
    final t = loc.table.copy();
    _writeCell(t.findCell(id)!.cell);
    _replace(s.tableId, t);
    // ما كُتب صار في المستند ⟵ الخلية لم تعُد «فارغةً بتنسيقٍ محفوظ»
    _wasEmpty = false;
  }

  void stopEditing({bool notify = true}) {
    if (!editing) return;
    commitCell();
    _endEdit();
    if (notify) notifyListeners();
  }

  void _endEdit() {
    final ctl = cell, focus = cellFocus, scroll = _cellScroll;
    _typingTimer?.cancel();
    cell = null;
    cellFocus = null;
    cellKey = null;
    _cellScroll = null;
    editingCellId = null;
    ctl?.removeListener(_onCellChanged);
    // الودجة القديمة قد تبقى إطاراً واحداً — تُحرَّر بعده
    if (ctl != null || focus != null || scroll != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ctl?.dispose();
        focus?.dispose();
        scroll?.dispose();
      });
    }
  }

  /// الخروج من الجدول: تُحفظ الخلية المفتوحة ويزول التحديد.
  void exit() {
    if (sel == null && !editing) return;
    stopEditing(notify: false);
    sel = null;
    dragTableId = null;
    dragWeights = null;
    notifyListeners();
  }

  /// المحرّر الرئيسيّ صار **صاحب التركيز نفسه** (نقرةٌ في المتن) ⟵ يُغادَر الجدول — إلا استرداداً عقب نقرة الخلية نفسها.
  ///
  /// 🔴 **Quill يُسلّم النقرة لمحرّره الرئيسيّ ولو ربحها غيرُه** (`_TransparentTapGestureRecognizer.rejectGesture` يقبلها
  /// عمداً) — فكلُّ نقرةٍ على خليةٍ يتبعها استردادٌ للتركيز في الحدث نفسه. وتمرَّر [hasPrimaryFocus] لا `hasFocus`: الخلية
  /// داخل شجرة المحرّر الرئيسيّ، فـ`hasFocus` صادقةٌ له ما دامت الخلية مركَّزة.
  void onMainFocus(bool hasPrimaryFocus) {
    if (!hasPrimaryFocus || sel == null) return;
    if (_activating) {
      editing ? _focusCellSoon(arm: false) : _focusTableSoon(arm: false);
      return;
    }
    exit();
  }

  void _arm() {
    _activating = true;
    final b = WidgetsBinding.instance;
    b.addPostFrameCallback((_) {
      b.addPostFrameCallback((_) => _activating = false);
      b.scheduleFrame();
    });
    b.scheduleFrame();
  }

  void _onMainChanged() {
    final s = sel;
    if (s == null) return;
    final loc = locate(s.tableId);
    // تراجعٌ أو حذفٌ أزال الجدول ⟵ لا تحديدَ لجدولٍ غير موجود
    if (loc == null) {
      _endEdit();
      sel = null;
      notifyListeners();
      return;
    }
    // تراجعٌ صغّر الجدول ⟵ التحديد داخل حدوده، والخلية المفتوحة إن زالت تُغلق
    final t = loc.table;
    if (s.ar >= t.rowCount || s.hr >= t.rowCount || s.ac >= t.colCount || s.hc >= t.colCount) _clamp(t);
    if (editingCellId != null && t.findCell(editingCellId!) == null) _endEdit();
  }

  void _focusCellSoon({bool arm = true}) {
    if (arm) _arm();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) cellFocus?.requestFocus();
    });
  }

  void _focusTableSoon({bool arm = true}) {
    if (arm) _arm();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed && sel != null && !editing) tableFocus.requestFocus();
    });
  }

  /// Tab · Shift+Tab: الخلية التالية/السابقة — **وTab من آخر بندٍ قبل صفّ المجموع يُضيف بنداً** (فالفاتورة تُكتب بلا فأرة).
  void moveNext({bool backward = false}) {
    final s = sel;
    if (s == null) return;
    commitCell();
    final t = locate(s.tableId)?.table;
    if (t == null) return;
    final order = [for (final m in t.masters) if (_editable(m.cell)) m];
    final head = t.ownerOf(s.hr, s.hc);
    final i = order.indexWhere((m) => m.cell.id == head?.cell.id);
    if (!backward) {
      final next = i + 1 < order.length ? order[i + 1] : null;
      final endOfItems = head != null && (next == null || _isTotalRow(t, next.row)) && !_isTotalRow(t, head.row) && head.row >= t.headerRows;
      if (endOfItems) {
        final at = head.row + head.cell.rowSpan;
        if (t.rowCount >= 600) {
          onMessage?.call('بلغ الجدول الحدّ الأعلى للصفوف (600).');
        } else if (_replace(s.tableId, BtOps.insertRow(t, at))) {
          final nt = locate(s.tableId)!.table;
          final first = [for (final m in nt.masters) if (m.row == at && _editable(m.cell)) m];
          // عمود الترقيم امتلأ وحده ⟵ تبدأ الكتابة في الخلية التي بعده
          final target = first.length > 1 && nt.numberingCol == first.first.col ? first[1] : (first.isEmpty ? null : first.first);
          if (target != null) {
            sel = BtSelection(s.tableId, target.row, target.col, target.row, target.col);
            _beginEdit(target.cell);
            notifyListeners();
            return;
          }
        }
      }
      if (next != null) return _open(t, next);
    } else if (i > 0) {
      return _open(t, order[i - 1]);
    }
    _endEdit();
    _focusTableSoon();
    notifyListeners();
  }

  void _open(BtTable t, BtSlot m) {
    sel = BtSelection(t.id, m.row, m.col, m.row, m.col);
    _beginEdit(m.cell);
    notifyListeners();
  }

  static bool _isTotalRow(BtTable t, int r) =>
      t.rows[r].cells.any((c) => c != null && (c.formula != null || c.words != null));

  // ─────────────────────────── لوحة المفاتيح ───────────────────────────

  bool get _ctrl => HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;

  /// مفاتيح الخلية المفتوحة — تُرى **قبل** Quill (`onKeyPressed`): Tab ينتقل بدل أن يُزيح السطر، وEsc يُنهي الكتابة.
  KeyEventResult? onCellKey(KeyEvent e, quill.Node? node) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return null;
    if (e.logicalKey == LogicalKeyboardKey.tab) {
      moveNext(backward: HardwareKeyboard.instance.isShiftPressed);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.escape) {
      stopEditing();
      _focusTableSoon();
      return KeyEventResult.handled;
    }
    return null;
  }

  /// مفاتيح الجدول (خلايا محدّدة بلا كتابة) — كما في Excel.
  KeyEventResult onTableKey(FocusNode node, KeyEvent e) {
    final s = sel;
    if (s == null || (e is! KeyDownEvent && e is! KeyRepeatEvent)) return KeyEventResult.ignored;
    // 🔴 محرّر الخلية داخل عقدة الجدول ⟵ ما لا يعالجه (حرفٌ يُكتب · Delete) **يصعد إلى هنا** — فلو عولج لأُعيد فتح الخلية
    //    مع كل حرفٍ ومُسح ما كُتب. أثناء الكتابة هذه المفاتيح للخلية وحدها.
    if (editing) {
      final ch = e.character;
      final c = cell;
      if (c != null && !(cellFocus?.hasPrimaryFocus ?? false) && !_ctrl && _printable(ch)) {
        final at = c.selection.isValid ? c.selection.end : math.max(0, c.document.length - 1);
        c.replaceText(at, 0, ch!, TextSelection.collapsed(offset: at + ch.length));
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final t = locate(s.tableId)?.table;
    if (t == null) return KeyEventResult.ignored;
    if (_ctrl) {
      if (k == LogicalKeyboardKey.keyZ || k == LogicalKeyboardKey.keyY) {
        // Quill يطلب التركيز للمتن مع التراجع ⟵ استردادٌ لا خروجٌ من الجدول
        _arm();
        (k == LogicalKeyboardKey.keyY || shift) ? main.redo() : main.undo();
        _focusTableSoon(arm: false);
        notifyListeners();
      } else if (k == LogicalKeyboardKey.keyC || k == LogicalKeyboardKey.keyX) {
        unawaited(copySelection(cut: k == LogicalKeyboardKey.keyX));
      } else if (k == LogicalKeyboardKey.keyV) {
        unawaited(pasteIntoSelection());
      } else if (k == LogicalKeyboardKey.keyA) {
        sel = BtSelection(s.tableId, 0, 0, t.rowCount - 1, t.colCount - 1);
        notifyListeners();
      } else {
        return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape) {
      final loc = locate(s.tableId);
      exit();
      if (loc != null) focusMain?.call(loc.offset + 1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.tab) {
      moveNext(backward: shift);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter || k == LogicalKeyboardKey.f2) {
      final h = t.ownerOf(s.hr, s.hc);
      if (h != null && _editable(h.cell)) {
        sel = BtSelection(s.tableId, h.row, h.col, h.row, h.col);
        _beginEdit(h.cell);
        notifyListeners();
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.delete || k == LogicalKeyboardKey.backspace) {
      applyRect(BtOps.clearCells);
      return KeyEventResult.handled;
    }
    final arrows = {
      LogicalKeyboardKey.arrowUp: (-1, 0),
      LogicalKeyboardKey.arrowDown: (1, 0),
      // في الجدول العربيّ «يسار» = العمود التالي
      LogicalKeyboardKey.arrowLeft: (0, t.rtl ? 1 : -1),
      LogicalKeyboardKey.arrowRight: (0, t.rtl ? -1 : 1),
    };
    final d = arrows[k];
    if (d != null) {
      _move(t, s, d.$1, d.$2, extend: shift);
      return KeyEventResult.handled;
    }
    // حرفٌ يُكتب ⟵ تُفتح الخلية بهذا الحرف بدل نصّها (كما في Excel)
    final ch = e.character;
    if (_printable(ch)) {
      final h = t.ownerOf(s.hr, s.hc);
      if (h != null && _editable(h.cell)) {
        sel = BtSelection(s.tableId, h.row, h.col, h.row, h.col);
        _beginEdit(h.cell, typed: ch);
        notifyListeners();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  static bool _printable(String? ch) => ch != null && ch.isNotEmpty && ch.runes.first >= 0x20 && ch.runes.first != 0x7F;

  void _move(BtTable t, BtSelection s, int dr, int dc, {required bool extend}) {
    final o = t.ownerOf(s.hr, s.hc);
    if (o == null) return;
    var r = s.hr, c = s.hc;
    if (dr > 0) r = o.row + o.cell.rowSpan;
    if (dr < 0) r = o.row - 1;
    if (dc > 0) c = o.col + o.cell.colSpan;
    if (dc < 0) c = o.col - 1;
    if (r < 0 || c < 0 || r >= t.rowCount || c >= t.colCount) return;
    final n = t.ownerOf(r, c)!;
    sel = extend ? _expand(s.tableId, BtSelection(s.tableId, s.ar, s.ac, r, c)) : BtSelection(s.tableId, n.row, n.col, n.row, n.col);
    notifyListeners();
  }

  // ─────────────────────────── الحافظة ───────────────────────────

  Future<void> copySelection({bool cut = false}) async {
    final s = sel;
    final t = activeTable;
    if (s == null || t == null) return;
    final grid = BtOps.copyGrid(t, s.top, s.left, s.bottom, s.right, words: wordsFor(t));
    await _writeText(BtPaste.toTsv(grid));
    if (cut) applyRect(BtOps.clearCells);
  }

  /// ما في الحافظة شبكةً — جدول Word بـHTML (بعريضه ولونه) أو نصّ Excel المفصول بـTab — أو نصٌّ مفرد.
  Future<List<List<BtPasteCell>>?> readClipboardGrid() async {
    String? html;
    try {
      html = await _readHtml();
    } catch (_) {
      html = null;
    }
    if (html != null && html.toLowerCase().contains('<table')) {
      final cells = BtPaste.parseHtmlCells(html);
      if (cells != null) return cells;
    }
    String? text;
    try {
      text = await _readText();
    } catch (_) {
      text = null;
    }
    if (text == null || text.isEmpty) return null;
    final tsv = BtPaste.parseTsv(text);
    return tsv == null ? [[BtPasteCell(text)]] : BtPaste.plainCells(tsv);
  }

  static bool _isGrid(List<List<BtPasteCell>> g) => g.length > 1 || g.first.length > 1;

  /// اللصق في الخلية المفتوحة: شبكةٌ ⟵ تملأ الجدول من هذه الخلية · نصٌّ ⟵ نصّاً خالصاً (لا تنسيقَ غريبٍ يرفضه الخادم).
  Future<bool> _onCellPaste() async {
    final ctl = cell;
    final s = sel;
    if (ctl == null || s == null) return true;
    final grid = await readClipboardGrid();
    if (grid == null) return true;
    if (!_isGrid(grid)) {
      final text = grid.first.first.text.replaceAll('\r', '');
      final at = ctl.selection;
      ctl.replaceText(at.start, at.end - at.start, text, TextSelection.collapsed(offset: at.start + text.length));
      return true;
    }
    final head = activeTable?.ownerOf(s.hr, s.hc);
    if (head == null) return true;
    stopEditing(notify: false);
    sel = BtSelection(s.tableId, head.row, head.col, head.row, head.col);
    _pasteGrid(grid, head.row, head.col);
    return true;
  }

  /// Ctrl+V على خلايا محدّدة: شبكةٌ تُلصق من الركن الأعلى — وقيمةٌ واحدة تملأ كلَّ المحدّد (كما في Excel).
  Future<void> pasteIntoSelection() async {
    final s = sel;
    if (s == null) return;
    final grid = await readClipboardGrid();
    if (grid == null || sel == null) return;
    if (!_isGrid(grid)) {
      final text = grid.first.first.text;
      applyRect((t, top, left, bottom, right) => BtOps.editCells(t, top, left, bottom, right, (c) {
            if (_editable(c)) BtOps.setText(c, text);
          }));
      return;
    }
    _pasteGrid(grid, s.top, s.left);
  }

  void _pasteGrid(List<List<BtPasteCell>> grid, int r, int c) {
    final width = grid.fold<int>(0, (m, row) => math.max(m, row.length));
    apply((t, s) {
      final next = BtOps.pasteCells(t, r, c, grid);
      if (next.rowCount > 600) {
        onMessage?.call('اللصق يتجاوز الحدّ الأعلى للصفوف (600) — قسّمه على جدولين.');
        return t;   // كما هو ⟵ لا تغيير
      }
      if (c + width > 30) onMessage?.call('الأعمدة الزائدة عن 30 لم تُلصق.');
      return next;
    });
  }

  /// لصقٌ في المتن: جدولٌ منسوخ ⟵ «إدراجه جدولاً؟» — وإلا يمضي اللصق العاديّ.
  Future<bool> onMainPaste() async {
    if (sel != null) return false;
    final grid = await readClipboardGrid();
    if (grid == null || grid.first.length < 2) return false;   // عمودٌ واحد = أسطر نصّ، لا جدول
    final ask = askPasteAsTable;
    if (ask == null || !await ask(grid.length, grid.first.length)) return false;
    insertTable(BtOps.fromGrid(grid));
    return true;
  }

  // ─────────────────────────── سحب حدّ العمود ───────────────────────────

  void dragStart(String tableId, List<double> weights) {
    dragTableId = tableId;
    dragWeights = List.of(weights);
    notifyListeners();
  }

  void dragUpdate(List<double> weights) {
    dragWeights = weights;
    notifyListeners();
  }

  void dragEnd() {
    final id = dragTableId, w = dragWeights;
    dragTableId = null;
    dragWeights = null;
    if (id != null && w != null && sel?.tableId == id) {
      apply((t, _) => BtOps.setColumnWeights(t, w));
    } else {
      notifyListeners();
    }
  }

  // ─────────────────────────── محرّر الخلية ───────────────────────────

  /// محرّر الخلية المفتوحة — بخطّ الورقة نفسه فلا يقفز النصّ بين العرض والكتابة.
  ///
  /// 🔴 **محرّرٌ داخل محرّر**: Quill يسجّل أفعال النصّ (الحذف · التحديد · تحديد الكل · النسخ · اللصق · التراجع) «قابلةً
  /// للتجاوز» — وFlutter يبحث عن المتجاوِز **في أسلاف الخلية، والمحرّر الرئيسيّ منهم**. فبلا هذه الطبقة كان Backspace في
  /// الخلية **يحذف من المتن**، وCtrl+Z **يتراجع في المتن**، وCtrl+A يحسب نصّ المتن ويطبّقه على الخلية فيرمي (كشفه الحارس).
  /// الطبقة تُعيد كل فعلٍ إلى فعل الخلية نفسها (`callingAction`) قبل أن يصل المحرّر الرئيسيّ.
  Widget buildCellEditor() => Actions(actions: _ownActions, child: _cellQuill());

  static final Map<Type, Action<Intent>> _ownActions = {
    DeleteCharacterIntent: _OwnAction<DeleteCharacterIntent>(),
    DeleteToNextWordBoundaryIntent: _OwnAction<DeleteToNextWordBoundaryIntent>(),
    DeleteToLineBreakIntent: _OwnAction<DeleteToLineBreakIntent>(),
    ExtendSelectionByCharacterIntent: _OwnAction<ExtendSelectionByCharacterIntent>(),
    ExtendSelectionToNextWordBoundaryIntent: _OwnAction<ExtendSelectionToNextWordBoundaryIntent>(),
    ExtendSelectionToLineBreakIntent: _OwnAction<ExtendSelectionToLineBreakIntent>(),
    ExtendSelectionVerticallyToAdjacentLineIntent: _OwnAction<ExtendSelectionVerticallyToAdjacentLineIntent>(),
    ExtendSelectionToDocumentBoundaryIntent: _OwnAction<ExtendSelectionToDocumentBoundaryIntent>(),
    ExtendSelectionToNextWordBoundaryOrCaretLocationIntent: _OwnAction<ExtendSelectionToNextWordBoundaryOrCaretLocationIntent>(),
    ExpandSelectionToDocumentBoundaryIntent: _OwnAction<ExpandSelectionToDocumentBoundaryIntent>(),
    ExpandSelectionToLineBreakIntent: _OwnAction<ExpandSelectionToLineBreakIntent>(),
    SelectAllTextIntent: _OwnAction<SelectAllTextIntent>(),
    CopySelectionTextIntent: _OwnAction<CopySelectionTextIntent>(),
    PasteTextIntent: _OwnAction<PasteTextIntent>(),
    UndoTextIntent: _OwnAction<UndoTextIntent>(),
    RedoTextIntent: _OwnAction<RedoTextIntent>(),
  };

  Widget _cellQuill() => quill.QuillEditor(
        key: cellKey,
        controller: cell!,
        focusNode: cellFocus!,
        scrollController: _cellScroll!,
        config: quill.QuillEditorConfig(
          scrollable: false,
          padding: EdgeInsets.zero,
          // النقر خارج الخلية (شريط الأدوات · خليةٌ أخرى) لا يُسقط تركيزها — المحرّك يقرّر متى تُغادَر
          onTapOutside: (_, _) {},
          onKeyPressed: onCellKey,
          customStyles: quill.DefaultStyles(
            paragraph: quill.DefaultTextBlockStyle(
              kPaperBase,
              const quill.HorizontalSpacing(0, 0),
              const quill.VerticalSpacing(0, 0),
              const quill.VerticalSpacing(0, 0),
              null,
            ),
          ),
        ),
      );

  // ─────────────────────────── الحافظة الافتراضية ───────────────────────────

  static Future<String?> _defaultReadHtml() async {
    final bridge = QuillNativeBridge();
    if (!await bridge.isSupported(QuillNativeBridgeFeature.getClipboardHtml)) return null;
    return bridge.getClipboardHtml();
  }

  static Future<String?> _defaultReadText() async => (await Clipboard.getData(Clipboard.kTextPlain))?.text;

  static Future<void> _defaultWriteText(String text) => Clipboard.setData(ClipboardData(text: text));

  @override
  void dispose() {
    _disposed = true;
    _main?.removeListener(_onMainChanged);
    _typingTimer?.cancel();
    _wordsTimer?.cancel();
    cell?.dispose();
    cellFocus?.dispose();
    _cellScroll?.dispose();
    tableFocus.dispose();
    contentTick.dispose();
    super.dispose();
  }
}

/// متجاوِزٌ يُعيد الفعل إلى صاحبه (فعل الخلية الافتراضيّ) — فيقف البحث عند الخلية ولا يصعد إلى المحرّر الرئيسيّ.
class _OwnAction<T extends Intent> extends ContextAction<T> {
  @override
  bool isEnabled(T intent, [BuildContext? context]) {
    final a = callingAction;
    if (a is ContextAction<T>) return a.isEnabled(intent, context);
    return a?.isEnabled(intent) ?? false;
  }

  @override
  bool consumesKey(T intent) => callingAction?.consumesKey(intent) ?? false;

  @override
  Object? invoke(T intent, [BuildContext? context]) {
    final a = callingAction;
    if (a is ContextAction<T>) return a.invoke(intent, context);
    return a?.invoke(intent);
  }
}
