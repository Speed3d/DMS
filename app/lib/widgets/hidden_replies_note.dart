import 'package:flutter/material.dart';

/// نصُّ «الردود المحجوبة» — **العدد يُعلَن والتفاصيل لا** (G20 — ADR-053).
///
/// نظيرُ ما في بطاقة المعاملة (`related_books_card.dart`): من لا يعرف أن الخيط ناقص يبني
/// قراراً على نصف صورة، ورقمُ الكتاب المحجوب وموضوعُه لا يصلان العميل أصلاً.
/// [outgoing] = المحجوب كتبٌ صادرة (تفاصيل الوارد)، وإلا فهي واردة (تفاصيل الصادر).
String hiddenRepliesText(int count, {required bool outgoing}) {
  final kind = outgoing ? 'صادر' : 'وارد';
  if (count == 1) return 'وكتابٌ $kind واحد مرتبطٌ خارج صلاحيتك.';
  if (count == 2) return 'وكتابان ${outgoing ? 'صادران' : 'واردان'} مرتبطان خارج صلاحيتك.';
  return 'و$count كتبٍ ${outgoing ? 'صادرة' : 'واردة'} مرتبطة خارج صلاحيتك.';
}

/// سطرُ القفل تحت قائمة الردود — لا يظهر إن لم يُحجب شيء.
class HiddenRepliesNote extends StatelessWidget {
  const HiddenRepliesNote({super.key, required this.count, required this.outgoing});

  final int count;
  final bool outgoing;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final muted = Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.6);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          Icon(Icons.lock_outline_rounded, size: 15, color: muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(hiddenRepliesText(count, outgoing: outgoing),
                style: TextStyle(fontSize: 12, color: muted)),
          ),
        ],
      ),
    );
  }
}
