import 'package:flutter/material.dart';
import '../core/theme.dart';

/// اختيار العملة **بالضغط** لا بقائمة منسدلة.
///
/// Hint: العملة خياران اثنان فقط، والقائمة المنسدلة تُخفيهما خلف ضغطتين. الأزرار تُظهر
///       الخيارين وتُبرز المختار، فيُعرف المُدخَل بلمحة — وهو مهم في حقل مالي.
///
/// لا قيمة افتراضية عمداً: المبلغ بلا عملة خطأ صامت، فيبقى الاختيار صريحاً ويظلّ
/// التحقق («يرجى اختيار العملة») هو الحارس.
class CurrencySelector extends StatelessWidget {
  const CurrencySelector({super.key, required this.value, required this.onChanged});

  /// `IQD` أو `USD` أو `null` (لم يُختَر بعد).
  final String? value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _option(context, code: 'IQD', label: 'دينار', icon: Icons.payments_rounded)),
        const SizedBox(width: 12),
        Expanded(child: _option(context, code: 'USD', label: 'دولار', icon: Icons.attach_money_rounded)),
      ],
    );
  }

  Widget _option(BuildContext context, {required String code, required String label, required IconData icon}) {
    final theme = Theme.of(context);
    final selected = value == code;
    final accent = theme.brightness == Brightness.dark ? AppColors.goldDark : AppColors.gold;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected ? accent.withValues(alpha: 0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => onChanged(code),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? accent : theme.dividerColor,
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: selected ? accent : theme.iconTheme.color?.withValues(alpha: 0.6)),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                      color: selected ? accent : theme.textTheme.bodyMedium?.color,
                    ),
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
