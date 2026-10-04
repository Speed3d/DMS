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
    final doc = html.parse(source);
    final table = doc.querySelector('table');
    if (table == null) return null;
    final rows = <List<String>>[];
    for (final tr in table.querySelectorAll('tr')) {
      final row = <String>[];
      for (final td in tr.children.where((e) => e.localName == 'td' || e.localName == 'th')) {
        row.add(_text(td));
        final span = int.tryParse(td.attributes['colspan'] ?? '') ?? 1;
        for (var k = 1; k < span; k++) {
          row.add('');
        }
      }
      if (row.isNotEmpty) rows.add(row);
    }
    return rows.isEmpty ? null : _rectangular(rows);
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
