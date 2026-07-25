import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../core/theme.dart';

/// عارض المرفقات داخل التطبيق — PDF وصور، بلا مغادرة الشاشة.
///
/// Hint: كانت المرفقات **تُنزَّل فقط**، وهو أثقل ما يكون في الوارد تحديداً لأن معظم
/// مرفقاته صور ممسوحة يريد الموظف إلقاء نظرة عليها لا حفظها. العارض هنا مشترك بين
/// الوارد والأرشيف والصادر حتى لا يتكرّر ثلاث مرات ويتباعد سلوكه.
class AttachmentViewer {
  /// الصيغ التي نعرضها داخلياً — ما عداها يُنزَّل (Word/Excel/ZIP/DWG لا عارض لها).
  static const _pdf = {'pdf'};
  static const _images = {'jpg', 'jpeg', 'png'};

  static String _ext(String fileName) {
    final i = fileName.lastIndexOf('.');
    return i < 0 ? '' : fileName.substring(i + 1).toLowerCase();
  }

  /// هل يمكن عرض هذا الملف داخلياً؟ (تُستخدم لإظهار زر «عرض» أو إخفائه)
  static bool canView(String fileName) {
    final e = _ext(fileName);
    return _pdf.contains(e) || _images.contains(e);
  }

  /// يفتح المرفق في نافذة عرض. [onDownload] يُضيف زر تنزيل داخل العارض.
  static Future<void> show(
    BuildContext context, {
    required Uint8List bytes,
    required String fileName,
    VoidCallback? onDownload,
  }) {
    final ext = _ext(fileName);
    final isPdf = _pdf.contains(ext);

    return showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 900),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _header(ctx, fileName, onDownload),
              Flexible(
                child: isPdf
                    ? PdfPreview(
                        build: (format) => bytes,
                        canChangeOrientation: false,
                        canChangePageFormat: false,
                        canDebug: false,
                        pdfFileName: fileName,
                      )
                    : _imageView(bytes),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _header(BuildContext ctx, String fileName, VoidCallback? onDownload) => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        color: AppColors.navyDeep,
        child: Row(
          children: [
            const Icon(Icons.visibility_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            if (onDownload != null)
              IconButton(
                icon: const Icon(Icons.download_rounded, color: Colors.white),
                tooltip: 'تنزيل',
                onPressed: onDownload,
              ),
            IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              tooltip: 'إغلاق',
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
      );

  /// عرض صورة مع تكبير/تصغير — لازم لأن المسح الضوئي غالباً بدقّة عالية.
  static Widget _imageView(Uint8List bytes) => InteractiveViewer(
        minScale: 0.5,
        maxScale: 5,
        child: Center(
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Padding(
              padding: EdgeInsets.all(32),
              child: Text('تعذّر عرض الصورة — قد يكون الملف تالفاً.',
                  style: TextStyle(color: AppColors.danger)),
            ),
          ),
        ),
      );
}
