import 'package:flutter/material.dart';

/// Hint: بطاقة مخصصة تستخدم في كل مكان (الإحصائيات، القوائم) لتعطي شكلاً موحداً مع ظلال خفيفة
class CustomCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final Color? backgroundColor;
  final bool border;
  final void Function()? onTap;

  const CustomCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(22),
    this.margin,
    this.width,
    this.height,
    this.backgroundColor,
    this.border = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Widget card = Container(
      width: width,
      height: height,
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: border ? Border.all(color: theme.dividerColor, width: 1.5) : null,
        boxShadow: [
          // Hint: ظل خفيف يعطي إحساساً بالعمق
          BoxShadow(
            color: isDark ? Colors.black38 : const Color(0x0F102040),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
          BoxShadow(
            color: isDark ? Colors.black54 : const Color(0x0A102040),
            blurRadius: 40,
            offset: const Offset(0, 18),
            spreadRadius: -14,
          ),
        ],
      ),
      child: child,
    );

    if (onTap != null) {
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: card,
        ),
      );
    }

    return card;
  }
}
