import 'package:flutter/material.dart';

import '../models.dart';
import 'outgoing_editor_screen.dart';

/// تعديل كتابٍ معتمد — يُنشئ إصداراً جديداً ويعيد توليد الـPDF والختم، والرقم لا يتغيّر.
///
/// ⚠️ **غلافٌ رفيع** فوق [OutgoingEditorScreen] (ADR-057).
class OutgoingEditApprovedScreen extends StatelessWidget {
  const OutgoingEditApprovedScreen({super.key, required this.book});

  final OutgoingDetail book;

  @override
  Widget build(BuildContext context) => OutgoingEditorScreen(mode: OutgoingEditorMode.editApproved, book: book);
}
