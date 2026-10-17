import '../../sell/data/esc_pos_builder.dart';

/// Builds the raw ESC/POS bytes for a barcode label — an optional bold
/// title line, the CODE128 barcode itself (printer-rendered, not an image —
/// matches desktop's `StoreProductPackagings.tsx` label which also
/// hardcodes CODE128), then any number of plain [footerLines] (price, qty,
/// product name, etc. — each individually toggle-able from the print
/// sheet), repeated [copies] times. The barcode is always horizontally
/// centered (`alignCenter()` before the barcode command) regardless of the
/// label's physical width.
List<int> buildBarcodeLabelEscPosBytes({
  required String code,
  String? title,
  List<String> footerLines = const [],
  bool showBarcodeText = true,
  int copies = 1,
  bool fullCut = false,
  int barHeight = 120,
  int barWidth = 2,
}) {
  final b = EscPosBuilder()..initialize();
  for (var i = 0; i < copies; i++) {
    b.alignCenter();
    if ((title ?? '').isNotEmpty) {
      b.boldOn();
      b.line(title!);
      b.boldOff();
    }
    b.barcodeWidth(barWidth);
    b.barcodeHeight(barHeight);
    b.barcodeTextPosition(showBarcodeText ? 2 : 0);
    b.printBarcodeCode128(code);
    for (final line in footerLines) {
      if (line.isNotEmpty) b.line(line);
    }
    b.feedPaper(2);
  }
  b.cut(full: fullCut);
  return b.build();
}
