import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'currency_selector.dart';

/// **الشريط الماليّ** — مفتاحٌ ومبلغٌ وعملةٌ وسعرُ صرفٍ في سطرٍ واحد فوق الأعمدة.
///
/// 🔴 **وُلد من بلاغ المالك (2026-09-21)**: كانت بطاقةً في **أسفل** عمود البيانات، فلا
/// تُرى إلا بتمرير — ومَن لا يرى الحقل لا يملؤه. والقرار: **شريطٌ ممتدّ فوق الشاشة كلِّها**.
///
/// 🔑 **ودجةٌ واحدة لا ثلاث نسخ**: الشاشات الثلاث (إنشاء · تعديل مسودّة · تعديل معتمد)
/// كانت تكرّر الكتلة نفسها بثلاث صياغات مختلفة — **وثلاثُ نسخٍ تتباعد عند أوّل تعديل**،
/// وهو بعينه ما كلّف المشروع ADR-030 (شرطُ رؤيةٍ نُسخ فاختلف عن أصله).
///
/// ⚠️ **وحالةُ المفتاح ليست ملكَ الشريط**: يملكها صاحبُ الشاشة لأنه يحفظها ويقرؤها من
/// الخادم (`amount != null`). الشريطُ يعرض ويُبلّغ، **ولا يحتفظ بحقيقةٍ يملكها غيرُه**.
class FinancialBar extends StatelessWidget {
  const FinancialBar({
    super.key,
    required this.enabled,
    required this.onEnabledChanged,
    required this.amount,
    required this.rate,
    this.currency,
    required this.onCurrencyChanged,
    this.title = 'التفاصيل المالية',
    this.readOnly = false,
  });

  final bool enabled;
  final ValueChanged<bool> onEnabledChanged;

  final TextEditingController amount;
  final TextEditingController rate;

  /// `IQD` أو `USD` أو **`null` (لم تُختَر بعد)**.
  ///
  /// ⚠️ **نوعٌ لاغٍ عمداً** — مرآةٌ لـ`CurrencySelector` ولشاشة الإنشاء حيث تبدأ فارغة،
  /// **وحقلٌ غيرُ لاغٍ هنا كان يُجبر الشاشة على اختيارٍ لم يقع** فيَحفظ عملةً لم تُختر.
  final String? currency;
  final ValueChanged<String> onCurrencyChanged;

  /// عنوانُ الشريط — يختلف في شاشة التعديل («التفاصيل المالية والملاحظات»).
  final String title;

  /// شاشةُ عرضٍ لا تحرير (لم تُستعمل بعد — تُبقي الباب مفتوحاً بلا نسخةٍ ثانية).
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final gold = isDark ? AppColors.goldBrightDark : AppColors.gold;
    final muted = theme.textTheme.bodySmall?.color;

    return Container(
      decoration: BoxDecoration(
        // ⚠️ **لونٌ مشتقٌّ من الهوية لا ثابت** — واللونُ الثابت يصير 1.1:1 ليلاً (ADR-041).
        color: enabled
            ? gold.withValues(alpha: isDark ? 0.10 : 0.07)
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: enabled ? gold.withValues(alpha: 0.45) : theme.dividerColor,
          width: enabled ? 1.4 : 1,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: LayoutBuilder(
        builder: (context, c) {
          // 🔴 **العتبة تُقاس لا تُكتب**: الحقول الثلاثة + العنوان + المفتاح تحتاج ~720
          //    بكسلاً لتقف في سطرٍ واحد. ودونها **تُلفّ** ولا تُقصّ.
          final oneLine = c.maxWidth >= 720;

          final header = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: gold.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.monetization_on_rounded, size: 18, color: gold),
              ),
              const SizedBox(width: 10),
              // 🔴 **`Flexible` على العنوان** — كشفه الحارس: عنوانُ شاشة التعديل
              //    («التفاصيل المالية والملاحظات») يدفع المفتاح خارج الشريط عند 360 بكسل.
              //    **والقصُّ هنا مقبول** لأنه عنوانُ قسمٍ لا قيمةَ بيانات.
              Flexible(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 4),
              Switch(
                value: enabled,
                activeThumbColor: gold,
                onChanged: readOnly ? null : onEnabledChanged,
              ),
            ],
          );

          if (!enabled) {
            // ⚠️ **الحالة المطفأة تقول ماذا يقع لو أُشعلت** — ومفتاحٌ بلا شرحٍ يُترك مطفأً.
            return Row(
              children: [
                // ⚠️ **`Flexible` على الترويسة كلِّها** — فتُصغَّر قبل أن تفيض.
                Flexible(child: header),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'اختياريّ — فعّله لإدخال مبلغ الكتاب وعملته.',
                    style: TextStyle(fontSize: 12.5, color: muted),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            );
          }

          final fields = <Widget>[
            SizedBox(
              width: oneLine ? 220 : double.infinity,
              child: TextField(
                controller: amount,
                readOnly: readOnly,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: _dec(context, 'المبلغ', Icons.payments_rounded),
              ),
            ),
            SizedBox(
              width: oneLine ? 190 : double.infinity,
              child: CurrencySelector(
                value: currency,
                onChanged: readOnly ? (_) {} : onCurrencyChanged,
              ),
            ),
            // ⚠️ **سعرُ الصرف يظهر بالدولار وحده** — حقلٌ لا معنى له بالدينار يُربك ويُملأ خطأً.
            if (currency == 'USD')
              SizedBox(
                width: oneLine ? 220 : double.infinity,
                child: TextField(
                  controller: rate,
                  readOnly: readOnly,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: _dec(context, 'سعر الصرف للدينار', Icons.price_change_rounded),
                ),
              ),
          ];

          // 🔴 **`Wrap` لا `Row`**: ثلاثةُ حقولٍ وعنوانٌ ومفتاح **يفيضون** تحت ~720 بكسلاً،
          //    والقصُّ هنا يخفي حقلَ إدخالٍ لا نصَّ عرض.
          return Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [header, ...fields],
          );
        },
      ),
    );
  }

  InputDecoration _dec(BuildContext context, String label, IconData icon) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 19, color: AppColors.action(context)),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      filled: true,
      fillColor: isDark ? theme.colorScheme.surface : Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: theme.dividerColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: theme.dividerColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppColors.action(context), width: 1.6),
      ),
    );
  }
}
