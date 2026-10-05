import 'package:flutter/material.dart';

import '../models.dart';
import 'outgoing_editor_screen.dart';

/// تعديل مسودّة كتابٍ صادر.
///
/// ⚠️ **غلافٌ رفيع** فوق [OutgoingEditorScreen] (ADR-057).
class OutgoingEditDraftScreen extends StatelessWidget {
  const OutgoingEditDraftScreen({super.key, required this.book});

  final OutgoingDetail book;

  @override
  Widget build(BuildContext context) => OutgoingEditorScreen(mode: OutgoingEditorMode.editDraft, book: book);
}
