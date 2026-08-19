import 'package:flutter/material.dart';

/// حقل كلمة مرور **بزرّ إظهار** (بلاغ المالك 2026-08-20).
///
/// 🔴 **لماذا يستحقّ ودجةً؟** لأن الفشل الذي يعالجه **صامتٌ ومربك**: يكتب المستخدم
/// بلوحةٍ عربية أو بـ`Caps Lock` مرفوع، فيرى نجوماً متطابقة ورسالةً واحدة — «اسم
/// المستخدم أو كلمة المرور غير صحيحة» — ولا شيء يدلّه على أن الخطأ في **شكل** ما كتب
/// لا في تذكّره. وهو أكثر ما يقع في أول دخولٍ لموظفٍ جديد بكلمةٍ مؤقّتة.
///
/// ⚠️ **والإظهار مؤقّتٌ بالضغط لا يُحفظ**: لا نتذكّر التفضيل بين الجلسات — كلمةُ مرورٍ
/// ظاهرةٌ افتراضياً على شاشةٍ في مكتبٍ مفتوح أسوأ من كلمةٍ يصعب كتابتها.
///
/// يقبل [decoration] جاهزاً (شاشة الدخول لها زخرفةٌ خاصّة) ويحقن فيه زرّ العين،
/// أو يبني واحداً من [labelText].
class PasswordField extends StatefulWidget {
  final TextEditingController controller;
  final String? labelText;
  final InputDecoration? decoration;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  const PasswordField({
    super.key,
    required this.controller,
    this.labelText,
    this.decoration,
    this.onSubmitted,
    this.autofocus = false,
  });

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    final base = widget.decoration ?? InputDecoration(labelText: widget.labelText);

    return TextField(
      controller: widget.controller,
      obscureText: !_visible,
      autofocus: widget.autofocus,
      onSubmitted: widget.onSubmitted,
      // ⚠️ بلا `enableSuggestions`/`autocorrect` — لوحاتُ المفاتيح تقترح على كلمة المرور.
      enableSuggestions: false,
      autocorrect: false,
      decoration: base.copyWith(
        suffixIcon: IconButton(
          tooltip: _visible ? 'إخفاء كلمة المرور' : 'إظهار كلمة المرور',
          icon: Icon(
            _visible ? Icons.visibility_off_rounded : Icons.visibility_rounded,
            size: 20,
          ),
          onPressed: () => setState(() => _visible = !_visible),
        ),
      ),
    );
  }
}
