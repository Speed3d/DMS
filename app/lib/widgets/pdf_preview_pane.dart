import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../core/theme.dart';

/// لوحة معاينة الكتاب الصادر — تُعرَض بجانب المحرر (شاشة عريضة) أو في تبويب (شاشة ضيقة).
///
/// Hint: مشتركة بين شاشات الصادر الثلاث (إنشاء · تعديل مسودّة · تعديل بعد الاعتماد).
/// نُسخت أولاً في شاشة الإنشاء وحدها فغابت عن شاشتَي التعديل — وهو ما لاحظه المالك. وحّدناها
/// هنا لأن نفس النمط تكرّر في هذا المشروع مرتين قبلها (شريط أدوات المحرر · عارض المرفقات).
///
/// **التحديث عند الطلب لا مع كل حرف:** قياسٌ فعلي أظهر أن توليد المعاينة ~1.5 ثانية في
/// السيرفر، فالتلقائية تعني ~3.5 ثانية بعد كل توقّف عن الكتابة وحِملاً دائماً على السيرفر
/// الداخلي (ADR-016).
class PdfPreviewPane extends StatelessWidget {
  final Uint8List? bytes;
  final bool busy;

  /// المعاينة المعروضة لم تعد تطابق المدخلات.
  final bool stale;
  final String? error;
  final VoidCallback onRefresh;

  const PdfPreviewPane({
    super.key,
    required this.bytes,
    required this.busy,
    required this.stale,
    required this.error,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          decoration: const BoxDecoration(
            color: AppColors.navyDeep,
            borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Row(
            children: [
              const Icon(Icons.picture_as_pdf_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              const Text('معاينة الكتاب',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              const Spacer(),
              // مؤشّر التقادم: يمنع أن يُصدّق المستخدم معاينةً لم تَعُد تطابق ما كتبه.
              if (stale)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('غير محدَّثة',
                      style: TextStyle(color: AppColors.gold, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              const SizedBox(width: 4),
              if (busy)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(color: AppColors.gold, strokeWidth: 2),
                  ),
                )
              else
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                  tooltip: 'تحديث المعاينة',
                  onPressed: onRefresh,
                ),
            ],
          ),
        ),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() {
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(error!,
              textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger)),
        ),
      );
    }
    if (bytes == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.description_outlined, size: 48, color: Colors.grey.withValues(alpha: 0.5)),
              const SizedBox(height: 12),
              const Text(
                'اضغط «تحديث المعاينة» لترى شكل الكتاب النهائي\nبالقالب والخط والحجم كما سيُطبع.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }
    final data = bytes!;
    return PdfPreview(
      // ⚠️ نسخة جديدة في كل استدعاء — لا نُمرّر نفس المخزن.
      // على الويب تُرسِل المكتبة البايتات إلى Web Worker بـ«نقل» (transfer) فيصير المخزن
      // الأصلي **منفصلاً**، فأي إعادة رسم تالية تفشل بـ
      // `DataCloneError: ArrayBuffer at index 0 is already detached`.
      build: (format) => Uint8List.fromList(data),
      canChangeOrientation: false,
      canChangePageFormat: false,
      canDebug: false,
      allowPrinting: false,
      pdfFileName: 'preview-outgoing.pdf',
    );
  }
}
