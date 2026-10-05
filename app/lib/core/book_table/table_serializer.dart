import 'dart:convert';

import '../quill_html.dart';
import 'book_table.dart';

/// نوع البلوك المضمَّن في مستند Quill — والوسم في `BodyHtml` (ADR-057).
const kDmsTableEmbed = 'dms-table';

/// تحويل الجدول ⇄ JSON (ADR-057) — **الشكل نفسه الذي يقرؤه الخادم** (`BookTableJson`: camelCase).
///
/// 📦 صورتان للجدول نفسه:
/// * **في `BodyJson`** (داخل Delta المحرّر): كاملٌ بـDelta كل خلية — مصدر التحرير.
/// * **في `BodyHtml`** (للطباعة): وسمٌ واحد `<div data-dms-table="…">` يحمل النموذج **بـ`html` كل خلية بلا Delta** —
///   فالخادم لا يحتاج أن يفهم Delta، ونصّ الخلية يُرسم بمحرّك الفقرات القائم نفسه.
class BtJson {
  BtJson._();

  static Map<String, dynamic> toJson(BtTable t, {bool forPrint = false}) => {
        'id': t.id,
        'v': BtTable.version,
        'dir': t.dir,
        'widthPct': t.widthPct,
        'align': t.align,
        'border': {'widthPt': t.borderWidthPt, 'color': t.borderColor},
        'headerRows': t.headerRows,
        'repeatHeader': t.repeatHeader,
        if (t.numberingCol != null) 'numberingCol': t.numberingCol,
        'cols': [for (final c in t.cols) {'id': c.id, 'weight': c.weight}],
        'rows': [
          for (final r in t.rows)
            {
              'id': r.id,
              'cells': [for (final c in r.cells) c == null ? null : _cell(c, forPrint)],
            }
        ],
      };

  static Map<String, dynamic> _cell(BtCell c, bool forPrint) => {
        'id': c.id,
        'rowSpan': c.rowSpan,
        'colSpan': c.colSpan,
        if (c.bg != null) 'bg': c.bg,
        'vAlign': c.vAlign,
        if (forPrint) 'html': cellHtml(c) else 'delta': c.delta,
        if (!forPrint && c.textStyle != null) 'textStyle': c.textStyle,   // للمحرّر وحده
        if (c.formula != null) 'formula': {'type': c.formula!.type, 'col': c.formula!.col},
        if (c.words != null)
          'words': {
            'sourceCellId': c.words!.sourceCellId,
            'currency': c.words!.currency,
            if (c.words!.prefix != null) 'prefix': c.words!.prefix,
            if (c.words!.suffix != null) 'suffix': c.words!.suffix,
          },
      };

  /// HTML نصّ الخلية — بالمحوّل نفسه الذي يحوّل المتن (التنسيق المختلط يصل الطباعة كما هو).
  ///
  /// 🔴 **خلية الجمع والحروف فارغةٌ في المحرّر** (نصّها يولّده الخادم) **وتنسيقها في `textStyle`** — فكانت تُرسَل `<p><br/></p>`
  /// ويُطبع المجموع **رفيعاً صغيراً** وهو في المحرّر وفي نموذج المالك **عريضٌ بحجم 14** (كشفته فاتورة المالك مبنيّةً بعمليات المحرّر).
  /// الآن تُرسَل **غلافَ تنسيقها فارغاً** (`<p …><strong><span style="font-size: 14pt"></span></strong></p>`) — والخادم يُدرج الرقم في
  /// أعمق وسمٍ فارغ (`TableFormulas.WithText`) فيرثه كاملاً.
  static String cellHtml(BtCell c) {
    final style = c.textStyle;
    if ((c.formula != null || c.words != null) && c.isEmpty && style != null && style.isNotEmpty) {
      Map<String, dynamic>? block;
      for (final op in c.delta) {
        final a = op['attributes'];
        if (op['insert'] is String && (op['insert'] as String).contains('\n') && a is Map) block = Map<String, dynamic>.from(a);
      }
      return quillDeltaToHtml([
        {'insert': _mark, 'attributes': style},
        {'insert': '\n', if (block != null) 'attributes': block},
      ]).replaceAll(_mark, '');
    }
    return quillDeltaToHtml(c.delta);
  }

  /// علامةٌ مؤقّتة تحمل التنسيق ثم تُحذف (المحوّل لا يُخرج وسماً حول نصٍّ فارغ).
  static const _mark = 'DMSVALUE';

  /// قراءةٌ متسامحة — حقلٌ غائب يأخذ افتراضه، فلا تُسقط مسوّدةٌ قديمة المحرّر.
  static BtTable fromJson(Map<String, dynamic> j) {
    final border = (j['border'] as Map?)?.cast<String, dynamic>() ?? const {};
    return BtTable(
      id: j['id'] as String? ?? btNewId('t'),
      dir: j['dir'] as String? ?? 'rtl',
      widthPct: (j['widthPct'] as num?)?.toInt() ?? 100,
      align: j['align'] as String? ?? 'center',
      borderWidthPt: (border['widthPt'] as num?)?.toDouble() ?? 0.75,
      borderColor: border['color'] as String? ?? '#000000',
      headerRows: (j['headerRows'] as num?)?.toInt() ?? 0,
      repeatHeader: j['repeatHeader'] as bool? ?? true,
      numberingCol: (j['numberingCol'] as num?)?.toInt(),
      cols: [
        for (final c in (j['cols'] as List? ?? const []))
          BtCol(id: (c as Map)['id'] as String? ?? btNewId('k'), weight: (c['weight'] as num?)?.toDouble() ?? 1),
      ],
      rows: [
        for (final r in (j['rows'] as List? ?? const []))
          BtRow(
            id: (r as Map)['id'] as String? ?? btNewId('r'),
            cells: [for (final c in (r['cells'] as List? ?? const [])) c == null ? null : _cellFrom(Map<String, dynamic>.from(c as Map))],
          ),
      ],
    );
  }

  static BtCell _cellFrom(Map<String, dynamic> j) {
    final f = (j['formula'] as Map?)?.cast<String, dynamic>();
    final w = (j['words'] as Map?)?.cast<String, dynamic>();
    final delta = (j['delta'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return BtCell(
      id: j['id'] as String? ?? btNewId('c'),
      rowSpan: (j['rowSpan'] as num?)?.toInt() ?? 1,
      colSpan: (j['colSpan'] as num?)?.toInt() ?? 1,
      bg: j['bg'] as String?,
      vAlign: j['vAlign'] as String? ?? 'middle',
      delta: delta == null || delta.isEmpty ? null : delta,
      textStyle: (j['textStyle'] as Map?)?.cast<String, dynamic>(),
      formula: f == null ? null : BtFormula(type: f['type'] as String? ?? 'sum', col: (f['col'] as num?)?.toInt() ?? 0),
      words: w == null
          ? null
          : BtWords(
              sourceCellId: w['sourceCellId'] as String? ?? '',
              currency: w['currency'] as String? ?? 'IQD',
              prefix: w['prefix'] as String?,
              suffix: w['suffix'] as String?,
            ),
    );
  }

  /// نصّ البلوك المضمَّن في Quill — JSON كامل بـDelta الخلايا.
  static String toEmbedData(BtTable t) => jsonEncode(toJson(t));

  static BtTable fromEmbedData(Object? data) =>
      fromJson(Map<String, dynamic>.from((data is String ? jsonDecode(data) : data) as Map));

  /// الوسم في `BodyHtml` — والخادم يقرأ ما بين علامتي التنصيص بعد فكّ التهريب (`BookTableCodec`).
  static String htmlTag(BtTable t) => '<div data-dms-table="${escapeAttribute(jsonEncode(toJson(t, forPrint: true)))}"></div>';

  /// تهريبٌ كامل لقيمة سمةٍ بين علامتي تنصيص مزدوجتين.
  static String escapeAttribute(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}
