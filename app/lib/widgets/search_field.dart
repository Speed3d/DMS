import 'dart:async';
import 'package:flutter/material.dart';

/// حقل بحثٍ **يبحث وأنت تكتب** — بلا ضغط `Enter` (بلاغ المالك 2026-08-20).
///
/// 🔴 **لماذا ودجةٌ واحدة لا `onChanged` في كل شاشة؟** لأن البحث الحيّ ثلاثةُ قرارات لا
/// قرارٌ واحد، وتكرارها في ثلاث شاشات يعني أن تُصيبها في واحدة وتُخطئها في اثنتين:
///
/// 1. **مهلةٌ بعد آخر حرف** ([debounce]) — بدونها يصير «DEN-IN-2026» **اثني عشر طلباً**
///    للخادم، ويثقل مع نموّ البيانات حتى يبدو النظام بطيئاً بلا سبب ظاهر.
/// 2. **لا طلبَ إن لم يتغيّر النصّ فعلاً**: مفاتيح الأسهم والتحديد تُطلق `onChanged`
///    أحياناً بالنصّ نفسه، فتُعاد الجلبة بلا فائدة.
/// 3. **و`Enter` يبقى عاملاً** — من اعتاد الضغط لا يُفاجأ بأنه لم يعد يفعل شيئاً،
///    ويُلغى المؤقّت عنده فلا يقع طلبان متتاليان.
///
/// ⚠️ **ولا يحمل هذا الحقل حارساً ضدّ الردّ المتأخّر** (أن يصل ردّ «DEN» بعد ردّ
/// «DEN-IN» فيعرض نتائج أقدم): الشاشات الثلاث تُسند `Future` **كاملاً** إلى
/// `FutureBuilder`/مزوّد، وهو يتجاهل ما سبق آخر إسناد. أيّ شاشةٍ تجمع النتائج في
/// `setState` يدوياً **يجب أن تضيف الحارس بنفسها**.
class DebouncedSearchField extends StatefulWidget {
  /// متحكّمٌ خارجيّ إن كانت الشاشة تقرأ النصّ عند الجلب (`_search.text`).
  final TextEditingController? controller;
  final String hintText;

  /// يُنادى بعد سكون [debounce] — أو فور الضغط على `Enter`.
  final ValueChanged<String> onChanged;
  final Duration debounce;

  const DebouncedSearchField({
    super.key,
    this.controller,
    required this.hintText,
    required this.onChanged,
    this.debounce = const Duration(milliseconds: 350),
  });

  @override
  State<DebouncedSearchField> createState() => _DebouncedSearchFieldState();
}

class _DebouncedSearchFieldState extends State<DebouncedSearchField> {
  late final TextEditingController _controller =
      widget.controller ?? TextEditingController();
  Timer? _timer;
  String _lastSent = '';

  @override
  void initState() {
    super.initState();
    _lastSent = _controller.text;
  }

  @override
  void dispose() {
    // ⚠️ **المؤقّت يُلغى دائماً**، وإلا نُودي `onChanged` بعد إزالة الشاشة
    //    فسقط التطبيق بـ`setState() called after dispose()`.
    _timer?.cancel();
    // والمتحكّم الخارجيّ ملكُ صاحبه — لا نتصرّف بما لم نُنشئه.
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  void _fire(String value) {
    _timer?.cancel();
    if (value == _lastSent) return;
    _lastSent = value;
    widget.onChanged(value);
  }

  void _onChanged(String value) {
    _timer?.cancel();
    _timer = Timer(widget.debounce, () {
      if (mounted) _fire(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final faded = theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.4);

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor, width: 1.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Icon(Icons.search_rounded, color: faded),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _controller,
              onChanged: _onChanged,
              onSubmitted: _fire,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: widget.hintText,
                border: InputBorder.none,
                hintStyle: TextStyle(fontSize: 14, color: faded),
              ),
            ),
          ),
          // مسحُ البحث بضغطةٍ واحدة — ويعود للقائمة كاملةً فوراً لا بعد مهلة.
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (_, value, __) => value.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: 'مسح البحث',
                    icon: Icon(Icons.close_rounded, size: 18, color: faded),
                    onPressed: () {
                      _controller.clear();
                      _fire('');
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
