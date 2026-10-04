import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

/// قراءة جدولٍ منسوخ من Excel أو Word (ADR-057، قرار المالك: «كتابة خليةً خلية أو لصق»).
///
/// 🔑 **Excel يضع في الحافظة نصّاً مفصولاً بـTab** (والخلية ذات الأسطر بين علامتي تنصيص، و`""` تنصيصٌ داخلها)،
/// **وWord يضع HTML** فيه `<table>`. والنصّ العاديّ متاحٌ في كل متصفّح، فالـTSV هو الطريق المضمون.
class BtPaste {
  BtPaste._();

  /// شبكة نصوص من نصٍّ مفصولٍ بـTab — أو `null` إن لم يكن جدولاً (سطرٌ واحد بلا Tab: لصقٌ عاديّ في الخلية).
  static List<List<String>>? parseTsv(String text) {
    var s = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (s.endsWith('\n')) s = s.substring(0, s.length - 1);   // Excel يُنهي النسخ بسطرٍ جديد
    if (!s.contains('\t') && !s.contains('\n')) return null;

    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var quoted = false;
    var atFieldStart = true;
    for (var i = 0; i < s.length; i++) {
      final ch = s[i];
      if (quoted) {
        if (ch == '"') {
          if (i + 1 < s.length && s[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            quoted = false;
          }
        } else {
          field.write(ch);
        }
        continue;
      }
      if (ch == '"' && atFieldStart) {
        quoted = true;
        atFieldStart = false;
      } else if (ch == '\t') {
        row.add(field.toString());
        field.clear();
        atFieldStart = true;
      } else if (ch == '\n') {
        row.add(field.toString());
        field.clear();
        rows.add(row);
        row = <String>[];
        atFieldStart = true;
      } else {
        field.write(ch);
        atFieldStart = false;
      }
    }
    row.add(field.toString());
    rows.add(row);
    return _rectangular(rows);
  }

  /// شبكة نصوص من HTML فيه `<table>` (Word · Excel على الويب) — أو `null` إن لم يكن فيه جدول.
  /// الخلية المدموجة أفقياً تُفرَد خاناتٍ فارغة بعدها (الدمج يُعاد في المحرّر إن أراده المستخدم).
  static List<List<String>>? parseHtmlTable(String source) {
    final cells = parseHtmlCells(source);
    return cells == null ? null : [for (final r in cells) [for (final c in r) c.text]];
  }

  /// كـ[parseHtmlTable] ومعها **العريض ولون الخلفية** لكل خلية (قرار المالك: «النصّ والعريض ولون الخلفية»).
  static List<List<BtPasteCell>>? parseHtmlCells(String source) {
    final doc = html.parse(source);
    final table = doc.querySelector('table');
    if (table == null) return null;
    final rows = <List<BtPasteCell>>[];
    for (final tr in table.querySelectorAll('tr')) {
      final row = <BtPasteCell>[];
      for (final td in tr.children.where((e) => e.localName == 'td' || e.localName == 'th')) {
        final text = _text(td);
        row.add(BtPasteCell(text, bold: text.isEmpty ? null : _isBold(td), bg: _background(td)));
        final span = int.tryParse(td.attributes['colspan'] ?? '') ?? 1;
        for (var k = 1; k < span; k++) {
          row.add(const BtPasteCell(''));
        }
      }
      if (row.isNotEmpty) rows.add(row);
    }
    if (rows.isEmpty) return null;
    final width = rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);
    return [for (final r in rows) [...r, for (var i = r.length; i < width; i++) const BtPasteCell('')]];
  }

  /// شبكةٌ من نصٍّ عاديّ — الخلايا نصوصٌ بلا تنسيق.
  static List<List<BtPasteCell>> plainCells(List<List<String>> grid) => [
        for (final r in grid) [for (final t in r) BtPasteCell(t)]
      ];

  /// نسخٌ إلى الحافظة بصيغة Excel: Tab بين الخلايا وسطرٌ بين الصفوف — والخلية ذات السطر أو التنصيص بين علامتي تنصيص.
  static String toTsv(List<List<String>> grid) => grid
      .map((row) => row.map((v) => v.contains('\t') || v.contains('\n') || v.contains('"') ? '"${v.replaceAll('"', '""')}"' : v).join('\t'))
      .join('\n');

  /// عريضةٌ إن كان **كلُّ نصّها** داخل `<b>`/`<strong>` أو بخطٍّ عريض — نصفُ عريضٍ لا يُعدّ عريضاً.
  static bool _isBold(dom.Element td) {
    bool boldStyle(dom.Element e) {
      final w = RegExp(r'font-weight\s*:\s*(\w+)', caseSensitive: false).firstMatch(e.attributes['style'] ?? '')?.group(1);
      return w != null && (w == 'bold' || w == 'bolder' || (int.tryParse(w) ?? 0) >= 600);
    }

    var anyText = false;
    var allBold = true;
    void walk(dom.Node n, bool bold) {
      if (n is dom.Text) {
        if (n.text.trim().isNotEmpty) {
          anyText = true;
          if (!bold) allBold = false;
        }
      } else if (n is dom.Element) {
        final b = bold || n.localName == 'b' || n.localName == 'strong' || n.localName == 'th' || boldStyle(n);
        for (final c in n.nodes) {
          walk(c, b);
        }
      }
    }

    walk(td, boldStyle(td));
    return anyText && allBold;
  }

  /// لون خلفية الخلية من `background`/`background-color`/`bgcolor` — بصيغة `#RRGGBB` وحدها (قاعدة الخادم).
  static String? _background(dom.Element td) {
    final style = td.attributes['style'] ?? '';
    final m = RegExp(r'background(?:-color)?\s*:\s*([^;]+)', caseSensitive: false).firstMatch(style);
    return _hex(m?.group(1)) ?? _hex(td.attributes['bgcolor']);
  }

  static String? _hex(String? v) {
    if (v == null) return null;
    final s = v.trim().toLowerCase();
    final hex = RegExp(r'#([0-9a-f]{6})\b').firstMatch(s);
    if (hex != null) {
      final h = hex.group(1)!.toUpperCase();
      return h == 'FFFFFF' ? null : '#$h';   // الأبيض = بلا لون (Word يكتبه لكل خلية)
    }
    final rgb = RegExp(r'rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)').firstMatch(s);
    if (rgb != null) {
      final parts = [for (var i = 1; i <= 3; i++) int.parse(rgb.group(i)!).clamp(0, 255)];
      if (parts.every((p) => p == 255)) return null;
      return '#${parts.map((p) => p.toRadixString(16).padLeft(2, '0')).join().toUpperCase()}';
    }
    return null;
  }

  /// نصّ الخلية: `<br>` والفقرات أسطرٌ، والمسافات المتكرّرة تُطوى.
  static String _text(dom.Element e) {
    final b = StringBuffer();
    void walk(dom.Node n) {
      if (n is dom.Text) {
        b.write(n.text.replaceAll(RegExp(r'[ \t\r\n ]+'), ' '));
      } else if (n is dom.Element) {
        if (n.localName == 'br') {
          b.write('\n');
          return;
        }
        final block = n.localName == 'p' || n.localName == 'div';
        if (block && b.isNotEmpty && !b.toString().endsWith('\n')) b.write('\n');
        for (final c in n.nodes) {
          walk(c);
        }
      }
    }

    walk(e);
    return b.toString().split('\n').map((l) => l.trim()).join('\n').trim();
  }

  static List<List<String>> _rectangular(List<List<String>> rows) {
    final width = rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);
    return [for (final r in rows) [...r, for (var i = r.length; i < width; i++) '']];
  }
}

/// خليةٌ ملصوقة: نصّها — ومعه العريض ولون الخلفية إن حدّدهما المصدر (`null` = لم يحدّد ⟵ يبقى شكل الخلية كما هو).
class BtPasteCell {
  const BtPasteCell(this.text, {this.bold, this.bg});
  final String text;
  final bool? bold;
  final String? bg;
}
