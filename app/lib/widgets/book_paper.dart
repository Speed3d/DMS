import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models.dart';
import 'book_table/bt_table_view.dart';

/// صور القالب للورقة — الترويسة والتذييل والعلامة المائية (بشفافيتها من القالب).
class PaperAssets {
  const PaperAssets({this.header, this.footer, this.watermark, this.watermarkOpacity = 10});
  final Uint8List? header;
  final Uint8List? footer;
  final Uint8List? watermark;
  final int watermarkOpacity;
  static const empty = PaperAssets();
}

/// «الورقة» (ADR-057، قرار المالك ت١٢ ب) — صفحة A4 **بأبعادها الحقيقية بالنقاط** (595 × 842) تُرسم ثم تُكبَّر كلُّها
/// بالتناسب لتملأ المساحة: فالخطّ 12 هنا هو 12 في الطباعة، والهوامش والترويسة والتذييل بمقاسات الـPDF نفسها.
///
/// ⚠️ **تدفّقٌ واحد بلا فواصل صفحات** (كـ«تخطيط الويب» في Word) — والمعاينة بجانبها تُري التقسيم الحقيقيّ. ومطابقةُ
/// تقسيم الصفحات بين محرّكين (Flutter و QuestPDF) سطراً بسطر غير ممكنةٍ بدقّة، فلا نَعِد بها.
///
/// 🎨 **الورقة بيضاء دائماً** ولو كان الوضع ليلياً — هي صورةُ ما يُطبع لا جزءٌ من الواجهة.
class BookPaper extends StatelessWidget {
  const BookPaper({
    super.key,
    required this.assets,
    required this.numberText,
    required this.dateText,
    this.headerPhrase,
    this.entityLine,
    this.subjectLine,
    this.signatoryName,
    this.signatoryTitle,
    this.placement = SignaturePlacement.lastPage,
    required this.body,
  });

  /// عرض A4 وطوله بالنقاط — وهي وحدة الورقة كلّها.
  static const double pageWidth = 595;
  static const double pageHeight = 842;
  static const double headerHeight = 140;
  static const double footerHeight = 100;
  static const double sideMargin = 40;

  final PaperAssets assets;
  final String numberText;
  final String dateText;
  final String? headerPhrase;

  /// `null` ⟵ لا يُطبع (خيار الطباعة) — والقيمة تبقى مسجّلة في النظام.
  final String? entityLine;
  final String? subjectLine;
  final String? signatoryName;
  final String? signatoryTitle;
  final SignaturePlacement placement;
  final Widget body;

  static const _head = TextStyle(fontFamily: 'Amiri', fontWeight: FontWeight.w600, color: Color(0xFF111111));

  @override
  Widget build(BuildContext context) {
    final page = Theme(
      data: ThemeData.light(useMaterial3: true),
      child: Material(
        color: Colors.white,
        elevation: 3,
        shadowColor: Colors.black38,
        child: SizedBox(
          width: pageWidth,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: pageHeight),
            child: Stack(
              children: [
                if (assets.watermark != null)
                  Positioned.fill(
                    top: headerHeight,
                    bottom: footerHeight,
                    child: IgnorePointer(
                      child: Center(
                        child: Opacity(
                          opacity: (assets.watermarkOpacity.clamp(0, 100)) / 100,
                          child: Image.memory(assets.watermark!, width: 300, height: 300, fit: BoxFit.contain, gaplessPlayback: true),
                        ),
                      ),
                    ),
                  ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _band(assets.header, headerHeight, 'الترويسة'),
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: pageHeight - headerHeight - footerHeight),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(sideMargin, 5, sideMargin, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _topRow(),
                            if (entityLine != null || subjectLine != null) ...[
                              const SizedBox(height: 10),
                              if (entityLine != null)
                                Text(entityLine!, textAlign: TextAlign.center, style: _head.copyWith(fontSize: 15)),
                              if (subjectLine != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 5),
                                  child: Text('الموضوع / $subjectLine', textAlign: TextAlign.center, style: _head.copyWith(fontSize: 14)),
                                ),
                            ],
                            const SizedBox(height: 15),
                            DefaultTextStyle(style: kPaperBase.copyWith(height: 1.6), child: body),
                            const SizedBox(height: 24),
                            _signatureRow(),
                          ],
                        ),
                      ),
                    ),
                    _band(assets.footer, footerHeight, 'التذييل'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    // تكبيرٌ بالتناسب لعرض المساحة المتاحة — والإدخال والتحديد يعملان داخل التكبير (أُثبت في تجربة الدفعة ٠).
    return FittedBox(fit: BoxFit.fitWidth, alignment: Alignment.topCenter, child: page);
  }

  Widget _band(Uint8List? image, double height, String label) => SizedBox(
        height: height,
        child: image != null
            ? Image.memory(image, fit: BoxFit.contain, gaplessPlayback: true)
            : Container(
                color: const Color(0xFFF1F3F6),
                alignment: Alignment.center,
                child: Text('صورة $label — من القالب', style: const TextStyle(fontSize: 9, color: Color(0xFF9AA0A6))),
              ),
      );

  /// السطر الأوّل كالـPDF: فراغ يميناً · العبارة في الوسط · الرقم والتاريخ يساراً.
  Widget _topRow() => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Expanded(child: SizedBox()),
          Expanded(
            flex: 2,
            child: headerPhrase == null || headerPhrase!.trim().isEmpty
                ? const SizedBox()
                : Padding(
                    padding: const EdgeInsets.only(top: 35),
                    child: Text(headerPhrase!, textAlign: TextAlign.center, style: _head.copyWith(fontSize: 15)),
                  ),
          ),
          Expanded(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // FSI…PDI يعزل القيمة: «يُولَّد عند الاعتماد» العربية داخل سطرٍ LTR كانت تنقلب مع «No:».
                  Text('No: \u2068$numberText\u2069', style: _head.copyWith(fontSize: 13)),
                  Text('Date: \u2068$dateText\u2069', style: _head.copyWith(fontSize: 13)),
                ],
              ),
            ),
          ),
        ],
      );

  /// التوقيع يساراً والختم يميناً — بموضعهما في الـPDF. (الورقة متّصلة: في أيّ صفحاتٍ يظهران تُريه المعاينة.)
  Widget _signatureRow() => Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const SizedBox(width: 50),
            Expanded(
              child: signatoryName == null || signatoryName!.trim().isEmpty
                  ? const SizedBox()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(signatoryName!, textDirection: TextDirection.rtl, style: _head.copyWith(fontSize: 15)),
                        if (signatoryTitle != null && signatoryTitle!.trim().isNotEmpty)
                          Text(signatoryTitle!,
                              textDirection: TextDirection.rtl,
                              style: _head.copyWith(fontSize: 13, fontWeight: FontWeight.w400, color: const Color(0xFF555555))),
                      ],
                    ),
            ),
            Tooltip(
              message: placement.label,
              child: Container(
                width: 70,
                height: 70,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  border: Border.all(color: const Color(0xFFBDBDBD)),
                ),
                child: const Text('الختم\nعند الاعتماد',
                    textAlign: TextAlign.center, textDirection: TextDirection.rtl, style: TextStyle(fontSize: 8, color: Color(0xFF616161))),
              ),
            ),
          ],
        ),
      );
}
