import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:google_fonts/google_fonts.dart';

import 'package:dms_app/core/theme.dart';

/// حرّاس **تباين الوضع الليلي** (بلاغ المالك 2026-09-09).
///
/// 🔴 **لماذا حارسٌ يقيس بدل فحصٍ بالعين؟** لأن العيب لم يكن في زرٍّ واحد بل في **لوحة
/// الألوان نفسها**: كان الوضع الليلي يعيد تعريف خمسة أدوار ويترك البقية على لوحة Material
/// البنفسجية — فكان `onPrimary` بنفسجياً (`#381E72`) وهو **نصُّ زرّ الحفظ**، و`primary`
/// أغمق من الخلفية بتباينٍ **1.2:1**. وفحصُ العين لا يُعاد مع كل تعديل، **والحساب يُعاد**.
///
/// ⚠️ **والحدّ 4.5:1 ليس اختراعاً** — هو حدّ WCAG AA للنصّ العاديّ، و3:1 للنصّ الكبير
/// والحدود والأيقونات.
void main() {
  /// إضاءةٌ نسبية بحسب WCAG 2.1.
  double luminance(Color c) {
    double ch(double v) =>
        v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
  }

  /// نسبة التباين بين لونين — من 1:1 (متطابقان) إلى 21:1 (أسود وأبيض).
  double contrast(Color a, Color b) {
    final la = luminance(a), lb = luminance(b);
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  String hex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  // ⚠️ **يُمنع جلب الخطوط من الشبكة**: `AppTheme` يبني نمطَ النصّ بـ`GoogleFonts`،
  //    وفي اختبارٍ بلا شبكة يُخفق التحميل فيسقط الملفّ كلّه قبل أن يقيس حرفاً.
  late final ThemeData dark;
  late final ThemeData light;
  late final ColorScheme s;
  late final Color bg;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // ⚠️ **يُمنع جلب الخطوط**: `AppTheme` يبني نمط النصّ بـ`GoogleFonts`، وفي اختبارٍ
    //    بلا شبكة يبقى الجلب معلّقاً فيُخفق الملفّ كلّه. والمنعُ هو الطريق الموثَّق —
    //    **والاختبار يقيس الألوان لا الخطوط**. ويُبنى النمطان هنا **معاً** فلا يقع
    //    جلبٌ داخل أي اختبار.
    GoogleFonts.config.allowRuntimeFetching = false;
    // ⚠️ **الجلب يبقى مسموحاً**: منعُه يجعل `google_fonts` **يرمي**، والسماحُ به في
    //    اختبارٍ بلا شبكة يجعله **يسقط على الخطّ الأساسي** ويُكمل — وهو ما نريد.
    // ⚠️ **ويُبتلع خطأ الخطّ وحده**: `google_fonts` يرمي خطأً **غير متزامن** حين يُمنع
    //    الجلب، فيُنسب إلى `setUpAll` ويُفشله رغم أن الألوان بُنيت. والمنطقةُ المحروسة
    //    تلتقطه — **ولا تلتقط غيره**، فأيّ خطأٍ آخر يبقى ظاهراً.
    await runZonedGuarded(() async {
      dark = AppTheme.dark;
      light = AppTheme.light;
      // تُستنفَد المهامّ غير المتزامنة **داخل المنطقة** فيقع خطأ الخطّ في مصيدتها.
      await Future<void>.delayed(Duration.zero);
    }, (e, _) {
      if (!e.toString().contains('allowRuntimeFetching')) throw e;
    });
    s = dark.colorScheme;
    bg = dark.scaffoldBackgroundColor;
  });

  void expectContrast(String what, Color fg, Color on, double min) {
    final r = contrast(fg, on);
    expect(r, greaterThanOrEqualTo(min),
        reason: '$what: ${hex(fg)} على ${hex(on)} = ${r.toStringAsFixed(2)}:1 '
            '— والمطلوب $min:1');
  }

  group('🌙 تباين الوضع الليلي — نصوصٌ تُقرأ', () {
    test('🔴 نصُّ الزرّ الممتلئ على خلفيته — العيب الذي بلّغ عنه المالك', () {
      // كان `onPrimary` بنفسجياً `#381E72` على `primary` كحليّ داكن ⇒ 1.3:1.
      expectContrast('onPrimary/primary', s.onPrimary, s.primary, 4.5);
    });

    test('🔴 لونُ الفعل على الخلفية وعلى الأسطح', () {
      // كان `primary = #16294A` على خلفية `#070E1C` ⇒ 1.2:1، فكان «سجل الإصدارات»
      // و«إلغاء» شبه غير مرئيَّين.
      expectContrast('primary/scaffold', s.primary, bg, 4.5);
      expectContrast('primary/surface', s.primary, s.surface, 4.5);
      expectContrast('primary/surfaceContainer', s.primary, s.surfaceContainer, 4.5);
      expectContrast('primary/surfaceContainerHighest', s.primary,
          s.surfaceContainerHighest, 4.5);
    });

    test('النصّ الأساسي والثانوي على كل الأسطح', () {
      for (final (name, on) in <(String, Color)>[
        ('scaffold', bg),
        ('surface', s.surface),
        ('surfaceContainer', s.surfaceContainer),
        ('surfaceContainerHigh', s.surfaceContainerHigh),
        ('surfaceContainerHighest', s.surfaceContainerHighest),
      ]) {
        expectContrast('onSurface/$name', s.onSurface, on, 4.5);
        expectContrast('onSurfaceVariant/$name', s.onSurfaceVariant, on, 4.5);
      }
    });

    test('ألوان الحالة تبقى مقروءة على الأسطح', () {
      for (final (name, c) in <(String, Color)>[
        ('success', AppColors.successDark),
        ('warn', AppColors.warnDark),
        ('danger', AppColors.dangerDark),
        ('gold', AppColors.goldBrightDark),
      ]) {
        expectContrast('$name/surface', c, s.surface, 3.0);
        expectContrast('$name/scaffold', c, bg, 3.0);
      }
      expectContrast('onError/error', s.onError, s.error, 4.5);
    });

    test('محتوى الحاويات على حاوياتها', () {
      expectContrast('onPrimaryContainer', s.onPrimaryContainer, s.primaryContainer, 4.5);
      expectContrast('onSecondaryContainer', s.onSecondaryContainer, s.secondaryContainer, 4.5);
      expectContrast('onTertiaryContainer', s.onTertiaryContainer, s.tertiaryContainer, 4.5);
      expectContrast('onErrorContainer', s.onErrorContainer, s.errorContainer, 4.5);
      expectContrast('onSecondary/secondary', s.onSecondary, s.secondary, 4.5);
      expectContrast('onTertiary/tertiary', s.onTertiary, s.tertiary, 4.5);
    });

    test('الحدود والفواصل تُرى (3:1 يكفي لغير النصّ)', () {
      expectContrast('outline/surface', s.outline, s.surface, 2.0);
      expectContrast('dividerColor/surface', dark.dividerColor, s.surface, 1.15);
    });
  });

  group('🟣 ولا أثرَ للوحة Material البنفسجية', () {
    // 🔴 **الحارس الأدقّ**: القيم البنفسجية الافتراضية معروفةٌ بأرقامها، فيُمنَع رجوعها
    //    بالاسم لا بالتباين — إذ قد يعود لونٌ بنفسجيّ **مقروء** فيمرّ من حرّاس التباين
    //    ويبقى غريباً عن هويّة الكحليّ والذهبيّ.
    const purples = <String, int>{
      'onPrimary الافتراضي': 0xFF381E72,
      'primaryContainer الافتراضي': 0xFF4F378B,
      'inversePrimary الافتراضي': 0xFF6750A4,
      'tertiary الوردي الافتراضي': 0xFFEFB8C8,
      'onSurfaceVariant الافتراضي': 0xFFCAC4D0,
      'outline الافتراضي': 0xFF938F99,
      'surfaceContainerLow الافتراضي': 0xFF1D1B20,
      'surfaceContainerHigh الافتراضي': 0xFF2B2930,
    };

    test('لا يبقى دورٌ على قيمته البنفسجية الافتراضية', () {
      final actual = <String, Color>{
        'onPrimary': s.onPrimary,
        'primaryContainer': s.primaryContainer,
        'inversePrimary': s.inversePrimary,
        'tertiary': s.tertiary,
        'onSurfaceVariant': s.onSurfaceVariant,
        'outline': s.outline,
        'surfaceContainerLow': s.surfaceContainerLow,
        'surfaceContainerHigh': s.surfaceContainerHigh,
      };
      for (final v in actual.entries) {
        expect(purples.values.contains(v.value.toARGB32()), isFalse,
            reason: '${v.key} = ${hex(v.value)} — قيمةٌ بنفسجية من لوحة Material');
      }
    });

    test('🔴 والأسطح المنبثقة كحليّة كبقيّة التطبيق', () {
      // كانت `surfaceContainerLow/High` رماديّتين بنفسجيّتين — وهو سببُ أن الحوارات
      // وقائمة «تغيير الحالة» تبدو غريبةً عن التصميم.
      expect(dark.dialogTheme.backgroundColor, s.surface);
      expect(dark.bottomSheetTheme.backgroundColor, s.surface);
      expect(dark.bottomSheetTheme.modalBackgroundColor, s.surface);
    });
  });

  group('☀️ والوضع النهاري لم يُمسّ', () {
    // ⚠️ **شرطُ المالك حرفياً**: «في الوضع النهاري كل شي جيد». فالحارس يثبّت قيمَه.
    test('ألوانه الأساسية كما كانت', () {
      final l = light.colorScheme;
      expect(l.primary, AppColors.navy);
      expect(l.secondary, AppColors.gold);
      expect(l.surface, const Color(0xFFFFFFFF));
      expect(light.scaffoldBackgroundColor, const Color(0xFFE9EDF4));
      expect(light.dividerColor, const Color(0xFFE2E7EF));
    });

    test('و«لون الفعل» يبقى كحليّاً نهاراً وذهبياً ليلاً', () {
      expect(AppColors.goldBrightDark, const Color(0xFFEDCC73));
      expect(AppColors.navyDeep, const Color(0xFF0C1B33));
    });
  });

  group('🔒 حارس العائلة — لا نصَّ أبيض على خلفيةٍ ذهبية', () {
    // 🔴 **عيبٌ أدخلتُه ثم أمسكه الفحص**: حين صار `AppColors.action` ذهبياً ليلاً، بقيت
    //    أزرارٌ تكتب `foregroundColor: Colors.white` — **أبيضُ على ذهبيّ ≈ 1.6:1**، أسوأ
    //    ممّا كان. عُولجت عشرةُ مواضع، وهذا الحارس يمنع عودتها.
    test('كلُّ خلفيةٍ بلون الفعل يعلوها [AppColors.onAction] لا أبيضٌ ثابت', () {
      final offenders = <String>[];
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final lines = f.readAsStringSync().split(String.fromCharCode(10));
        for (var i = 0; i < lines.length; i++) {
          if (!lines[i].contains('backgroundColor: AppColors.action(context)')) continue;
          final from = i - 3 < 0 ? 0 : i - 3;
          final to = i + 5 > lines.length ? lines.length : i + 5;
          final window = lines.sublist(from, to).join(String.fromCharCode(10));
          if (window.contains('foregroundColor: Colors.white')) {
            offenders.add('${f.path}:${i + 1}');
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'نصٌّ أبيض على خلفية «لون الفعل» — استعمل AppColors.onAction(context)');
    });
  });
}
