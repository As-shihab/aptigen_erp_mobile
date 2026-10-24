import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

// PDF output for the Barcode lab: either one label-sized page per label
// (for label printers driven by the OS print dialog) or an A4 sheet of
// labels (rows × columns, margins, gaps, start position).

class A4SheetLayout {
  final int columns;
  final int rows;
  final double marginTopMm;
  final double marginLeftMm;
  final double gapXMm;
  final double gapYMm;

  /// 1-based cell to start at (skip used labels on a partly used sheet).
  final int startPosition;
  const A4SheetLayout({
    this.columns = 3,
    this.rows = 8,
    this.marginTopMm = 10,
    this.marginLeftMm = 7,
    this.gapXMm = 2,
    this.gapYMm = 2,
    this.startPosition = 1,
  });

  /// Whether a [labelW] × [labelH] mm grid fits on A4 with this layout.
  bool fits(double labelW, double labelH) {
    final w = marginLeftMm + columns * labelW + (columns - 1) * gapXMm;
    final h = marginTopMm + rows * labelH + (rows - 1) * gapYMm;
    return w <= 210.01 && h <= 297.01;
  }

  /// Most columns/rows that fit A4 for the label size and current margins/gaps.
  static ({int columns, int rows}) maxFit(double labelW, double labelH, {double marginTop = 10, double marginLeft = 7, double gapX = 2, double gapY = 2}) {
    final c = ((210 - marginLeft + gapX) / (labelW + gapX)).floor();
    final r = ((297 - marginTop + gapY) / (labelH + gapY)).floor();
    return (columns: c < 1 ? 1 : c, rows: r < 1 ? 1 : r);
  }
}

/// [labels] — each distinct label image (PNG) with how many copies to place.
Future<Uint8List> buildLabelPdf({
  required List<({Uint8List png, int copies})> labels,
  required double labelWidthMm,
  required double labelHeightMm,
  A4SheetLayout? sheet,
}) async {
  final doc = pw.Document(title: 'Labels', creator: 'Aptigen');
  final images = [for (final l in labels) pw.MemoryImage(l.png)];
  final sequence = <int>[
    for (var i = 0; i < labels.length; i++)
      for (var c = 0; c < labels[i].copies; c++) i,
  ];
  final lw = labelWidthMm * PdfPageFormat.mm;
  final lh = labelHeightMm * PdfPageFormat.mm;

  if (sheet == null) {
    final format = PdfPageFormat(lw, lh, marginAll: 0);
    for (final idx in sequence) {
      doc.addPage(pw.Page(
        pageFormat: format,
        build: (_) => pw.SizedBox(width: lw, height: lh, child: pw.Image(images[idx], fit: pw.BoxFit.fill)),
      ));
    }
    return doc.save();
  }

  final perPage = sheet.columns * sheet.rows;
  final cells = <int?>[
    for (var i = 1; i < sheet.startPosition.clamp(1, perPage); i++) null,
    ...sequence,
  ];
  for (var start = 0; start < cells.length; start += perPage) {
    final page = cells.sublist(start, (start + perPage).clamp(0, cells.length));
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4.copyWith(marginTop: 0, marginBottom: 0, marginLeft: 0, marginRight: 0),
      build: (_) => pw.SizedBox(
        width: PdfPageFormat.a4.width,
        height: PdfPageFormat.a4.height,
        child: pw.Stack(children: [
        for (var i = 0; i < page.length; i++)
          if (page[i] != null)
            pw.Positioned(
              left: (sheet.marginLeftMm + (i % sheet.columns) * (labelWidthMm + sheet.gapXMm)) * PdfPageFormat.mm,
              top: (sheet.marginTopMm + (i ~/ sheet.columns) * (labelHeightMm + sheet.gapYMm)) * PdfPageFormat.mm,
              child: pw.SizedBox(width: lw, height: lh, child: pw.Image(images[page[i]!], fit: pw.BoxFit.fill)),
            ),
        ]),
      ),
    ));
  }
  return doc.save();
}

PdfPageFormat labelPageFormat(double wMm, double hMm) => PdfPageFormat(wMm * PdfPageFormat.mm, hMm * PdfPageFormat.mm, marginAll: 0);
