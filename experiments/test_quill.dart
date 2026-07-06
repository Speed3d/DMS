import 'package:vsc_quill_delta_to_html/vsc_quill_delta_to_html.dart';

void main() {
  final delta = [
    {"insert": "Hello "},
    {"insert": "Red", "attributes": {"color": "#e60000"}},
    {"insert": "\n"}
  ];
  final converter = QuillDeltaToHtmlConverter(
    delta,
    ConverterOptions(
      converterOptions: OpConverterOptions(inlineStylesFlag: true),
    ),
  );
  print(converter.convert());
}
