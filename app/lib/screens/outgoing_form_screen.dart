import 'package:flutter/material.dart';

import 'outgoing_editor_screen.dart';

/// إنشاء كتابٍ صادر — أو إكمال مسوّدةٍ من «مسوّداتي» (ADR-051).
///
/// ⚠️ **غلافٌ رفيع** فوق [OutgoingEditorScreen] (ADR-057): الشاشات الثلاث صارت شاشةً واحدة، وبقي الاسم لمن يفتحها.
class OutgoingFormScreen extends StatelessWidget {
  const OutgoingFormScreen({super.key, this.draftId});

  final String? draftId;

  @override
  Widget build(BuildContext context) => OutgoingEditorScreen(mode: OutgoingEditorMode.create, draftId: draftId);
}
