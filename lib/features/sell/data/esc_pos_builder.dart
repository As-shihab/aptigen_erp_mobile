import 'dart:convert';

/// Raw ESC/POS command bytes for a generic thermal receipt printer — hand
/// rolled (not a library) so the exact bytes match the requested command
/// set one-to-one:
///
/// | Command  | Purpose            |
/// |----------|--------------------|
/// | ESC @    | Initialize printer |
/// | ESC a 0  | Align left         |
/// | ESC a 1  | Align center       |
/// | ESC a 2  | Align right        |
/// | ESC E 1  | Bold ON            |
/// | ESC E 0  | Bold OFF           |
/// | GS V     | Cut paper          |
/// | LF       | Line feed          |
/// | GS !     | Change text size   |
/// | ESC d    | Feed paper         |
///
/// Text is encoded as Latin-1 (ISO-8859-1) — the common single-byte
/// encoding thermal printers' default code page (CP437/CP1252-ish) is
/// closest to; characters outside it (e.g. non-Latin currency signs) are
/// replaced with '?' rather than corrupting the byte stream. This mirrors
/// `invoice_pdf_builder.dart`'s same ASCII-safe-money simplification for the
/// same reason — no bundled code-page transcoding here.
class EscPosBuilder {
  final List<int> _bytes = [];

  List<int> build() => List.unmodifiable(_bytes);

  /// `ESC @` — resets the printer to its power-on defaults. Always call
  /// this first.
  EscPosBuilder initialize() {
    _bytes.addAll([0x1B, 0x40]);
    return this;
  }

  EscPosBuilder alignLeft() => _align(0x00);
  EscPosBuilder alignCenter() => _align(0x01);
  EscPosBuilder alignRight() => _align(0x02);

  EscPosBuilder _align(int n) {
    _bytes.addAll([0x1B, 0x61, n]);
    return this;
  }

  EscPosBuilder boldOn() {
    _bytes.addAll([0x1B, 0x45, 0x01]);
    return this;
  }

  EscPosBuilder boldOff() {
    _bytes.addAll([0x1B, 0x45, 0x00]);
    return this;
  }

  /// `GS !` — n packs width/height as `((width-1) << 4) | (height-1)`, each
  /// 1-8 (1 = normal size). Resets back to normal (1,1) with no args.
  EscPosBuilder textSize({int width = 1, int height = 1}) {
    final w = width.clamp(1, 8) - 1;
    final h = height.clamp(1, 8) - 1;
    _bytes.addAll([0x1D, 0x21, (w << 4) | h]);
    return this;
  }

  /// `LF` — repeated line feed, [times] blank lines.
  EscPosBuilder lineFeed([int times = 1]) {
    for (var i = 0; i < times; i++) {
      _bytes.add(0x0A);
    }
    return this;
  }

  /// `ESC d n` — feeds n lines without printing (distinct from `LF`, which
  /// is a full print+feed cycle for the current line buffer).
  EscPosBuilder feedPaper(int lines) {
    _bytes.addAll([0x1B, 0x64, lines.clamp(0, 255)]);
    return this;
  }

  /// `GS V` — cuts the paper. `full` selects the full-cut variant (`GS V
  /// 0`); partial cut (`GS V 1`) leaves a small connecting strip, the more
  /// common default on cheaper printers that can jam on a full cut.
  EscPosBuilder cut({bool full = false}) {
    _bytes.addAll([0x1D, 0x56, full ? 0x00 : 0x01]);
    return this;
  }

  /// `GS h n` — sets the barcode's module height in dots (1-255).
  EscPosBuilder barcodeHeight(int dots) {
    _bytes.addAll([0x1D, 0x68, dots.clamp(1, 255)]);
    return this;
  }

  /// `GS w n` — sets the barcode's module (bar) width, 2-6 dots.
  EscPosBuilder barcodeWidth(int dots) {
    _bytes.addAll([0x1D, 0x77, dots.clamp(2, 6)]);
    return this;
  }

  /// `GS H n` — where the human-readable text prints relative to the bars:
  /// 0 none, 1 above, 2 below, 3 both.
  EscPosBuilder barcodeTextPosition(int position) {
    _bytes.addAll([0x1D, 0x48, position.clamp(0, 3)]);
    return this;
  }

  /// `GS k m n d1...dn` (function-B form) — prints [data] as a CODE128
  /// barcode. CODE128 requires its payload to open with a code-set
  /// selector; `{B` (Code Set B) covers the full printable-ASCII range,
  /// which is what every barcode/SKU value in this app actually contains.
  EscPosBuilder printBarcodeCode128(String data) {
    final payload = _encode('{B$data');
    _bytes.addAll([0x1D, 0x6B, 73, payload.length, ...payload]);
    return this;
  }

  EscPosBuilder text(String value) {
    _bytes.addAll(_encode(value));
    return this;
  }

  /// `text()` + a trailing `LF` — the common case (`text().lineFeed()`).
  EscPosBuilder line([String value = '']) {
    text(value);
    return lineFeed();
  }

  /// A two-column row (label left, value right) padded to [width]
  /// characters — the usual receipt line shape ("Subtotal .......  12.00").
  EscPosBuilder row(String left, String right, {int width = 32}) {
    final space = width - left.length - right.length;
    final padded = space > 0 ? '$left${' ' * space}$right' : '$left $right';
    return line(padded);
  }

  List<int> _encode(String value) {
    try {
      return latin1.encode(value);
    } catch (_) {
      final sanitized = String.fromCharCodes(value.codeUnits.map((c) => c <= 0xFF ? c : 0x3F));
      return latin1.encode(sanitized);
    }
  }
}
