import 'package:flutter/material.dart';

/// نصّ خليةٍ من Delta (ADR-057) — **رسمٌ خفيف** بلا محرّر: 438 خلية في فاتورة لا تحتمل 438 محرّر Quill.
///
/// يرسم ما يكتبه المحرّر: عريض · مائل · تسطير · شطب · لون · حجم · خط — ومحاذاة كل سطر. والوحدة على الورقة **نقطة**
/// (الورقة تُرسم بعرض 595 = عرض A4 بالنقاط ثم تُكبَّر كلُّها) — فالحجم 12 هنا هو 12 في الطباعة.
class BtRichText extends StatelessWidget {
  const BtRichText({super.key, required this.delta, required this.base, this.defaultAlign = TextAlign.start});

  final List<Map<String, dynamic>> delta;
  final TextStyle base;
  final TextAlign defaultAlign;

  @override
  Widget build(BuildContext context) {
    final lines = btDeltaLines(delta);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final line in lines)
          Text.rich(
            TextSpan(children: [
              for (final s in line.spans) TextSpan(text: s.text, style: btSpanStyle(base, s.attrs)),
              if (line.spans.isEmpty) TextSpan(text: '​', style: base),   // سطرٌ فارغ يحفظ ارتفاعه
            ]),
            textAlign: _align(line.block['align']) ?? defaultAlign,
          ),
      ],
    );
  }

  static TextAlign? _align(Object? a) => switch (a) {
        'center' => TextAlign.center,
        'right' => TextAlign.right,
        'left' => TextAlign.left,
        'justify' => TextAlign.justify,
        _ => null,
      };
}

class BtLine {
  BtLine(this.spans, this.block);
  final List<BtSpan> spans;
  final Map<String, dynamic> block;
}

class BtSpan {
  BtSpan(this.text, this.attrs);
  final String text;
  final Map<String, dynamic> attrs;
}

/// أسطر Delta بأجزائها — وسمات السطر (المحاذاة) على محرف السطر الجديد كما يكتبها Quill.
List<BtLine> btDeltaLines(List<Map<String, dynamic>> delta) {
  const blockKeys = {'align', 'direction', 'header', 'list', 'indent'};
  final lines = <BtLine>[];
  var spans = <BtSpan>[];
  for (final op in delta) {
    final ins = op['insert'];
    if (ins is! String) continue;
    final attrs = (op['attributes'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final parts = ins.split('\n');
    for (var i = 0; i < parts.length; i++) {
      if (parts[i].isNotEmpty) spans.add(BtSpan(parts[i], {for (final e in attrs.entries) if (!blockKeys.contains(e.key)) e.key: e.value}));
      if (i < parts.length - 1) {
        lines.add(BtLine(spans, {for (final e in attrs.entries) if (blockKeys.contains(e.key)) e.key: e.value}));
        spans = <BtSpan>[];
      }
    }
  }
  if (spans.isNotEmpty) lines.add(BtLine(spans, const {}));
  if (lines.isEmpty) lines.add(BtLine([], const {}));
  return lines;
}

/// تنسيق جزءٍ من النصّ — بسمات Quill نفسها.
TextStyle btSpanStyle(TextStyle base, Map<String, dynamic> a) {
  var s = base;
  if (a['bold'] == true) s = s.copyWith(fontWeight: FontWeight.bold);
  if (a['italic'] == true) s = s.copyWith(fontStyle: FontStyle.italic);
  final deco = [
    if (a['underline'] == true) TextDecoration.underline,
    if (a['strike'] == true) TextDecoration.lineThrough,
  ];
  if (deco.isNotEmpty) s = s.copyWith(decoration: TextDecoration.combine(deco));
  final size = double.tryParse('${a['size'] ?? ''}');
  if (size != null && size > 0) s = s.copyWith(fontSize: size);
  final font = a['font'];
  if (font is String && font.isNotEmpty) s = s.copyWith(fontFamily: font);
  final color = btParseColor(a['color']);
  if (color != null) s = s.copyWith(color: color);
  return s;
}

/// `#RRGGBB` أو `#AARRGGBB` ⟵ لون — وغيرُ ذلك `null`.
Color? btParseColor(Object? v) {
  if (v is! String || !v.startsWith('#')) return null;
  final hex = v.substring(1);
  if (hex.length == 6) return Color(int.parse('FF$hex', radix: 16));
  if (hex.length == 8) return Color(int.parse(hex, radix: 16));
  return null;
}
