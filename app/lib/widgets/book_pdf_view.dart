import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../core/api_client.dart';
import '../core/theme.dart';

/// الكتاب كما يُطبع داخل شاشة التفاصيل (ADR-057، قرار المالك س٤١) — بدل نصٍّ مجرّدٍ من وسومه.
///
/// 🔑 كان المتن يُعرض نصّاً بعد حذف كل الوسوم: **جدولٌ من 70 صفّاً كان سيظهر سطراً واحداً من الأرقام المتلاصقة**، وبلا
/// قالبٍ ولا توقيع. الآن ما يُرى هو ما يُطبع: **المعتمد من ملفّه المخزَّن** (النسخة الرسمية نفسها التي حملها QR)، **والمسودّة
/// من المعاينة** (`preview-draft`).
///
/// [load] يُستدعى مرّةً لكل [reloadKey] — فتعديلٌ أو اعتمادٌ يُعيد الجلب، والتمرير وإعادة البناء لا يُعيدانه.
class BookPdfView extends StatefulWidget {
  const BookPdfView({super.key, required this.load, required this.reloadKey, required this.fileName, this.draft = false});

  final Future<Uint8List> Function() load;
  final Object reloadKey;
  final String fileName;

  /// مسودّة: يُذكر أن الرقم والتاريخ والختم تُولَّد عند الاعتماد.
  final bool draft;

  @override
  State<BookPdfView> createState() => _BookPdfViewState();
}

class _BookPdfViewState extends State<BookPdfView> {
  late Future<Uint8List> _future = widget.load();

  @override
  void didUpdateWidget(covariant BookPdfView old) {
    super.didUpdateWidget(old);
    if (old.reloadKey != widget.reloadKey) _future = widget.load();
  }

  // ⚠️ جسمٌ لا سهم: `setState(() => _future = …)` يُعيد قيمة الإسناد (Future) وFlutter يرفض ذلك فيرمي قبل إعادة البناء —
  //    فكان «إعادة المحاولة» يطلب ولا يتغيّر شيءٌ على الشاشة (كشفه الحارس).
  void _retry() => setState(() {
        _future = widget.load();
      });

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.6);
    return LayoutBuilder(builder: (context, c) {
      // صفحة A4 كاملة بعرض البطاقة (نسبة 1.414) — وشريط أدوات العارض فوقها
      final height = (c.maxWidth * 1.45 + 56).clamp(420.0, 1300.0);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.draft)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text('معاينة المسودّة — الرقم والتاريخ وختم QR تُولَّد عند الاعتماد.',
                  key: const Key('book-pdf-draft-note'), style: TextStyle(fontSize: 12, color: muted)),
            ),
          SizedBox(
            height: height,
            child: FutureBuilder<Uint8List>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator(color: AppColors.gold));
                }
                if (snap.hasError) {
                  final e = snap.error;
                  return Center(
                    key: const Key('book-pdf-error'),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(e is ApiException ? e.message : 'تعذّر عرض الكتاب.',
                          textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger)),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        key: const Key('book-pdf-retry'),
                        onPressed: _retry,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('إعادة المحاولة'),
                      ),
                    ]),
                  );
                }
                final bytes = snap.data!;
                return ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: PdfPreview(
                    key: const Key('book-pdf'),
                    // ⚠️ نسخةٌ جديدة في كل استدعاء — على الويب تُنقل البايتات إلى Web Worker فيصير المخزن الأصليّ منفصلاً.
                    build: (format) => Uint8List.fromList(bytes),
                    canChangeOrientation: false,
                    canChangePageFormat: false,
                    canDebug: false,
                    pdfFileName: widget.fileName,
                  ),
                );
              },
            ),
          ),
        ],
      );
    });
  }
}
