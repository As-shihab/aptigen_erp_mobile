import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import '../../sell/data/esc_pos_builder.dart';

// Label bitmap → 1-bit monochrome → ESC/POS raster (`GS v 0`). The thermal
// printer gets the exact bitmap shown in the print preview, so whatever the
// designer draws (any symbology, fonts, logos, currency signs) prints as is.

/// 1 bit per pixel image, stored one byte per pixel (1 = black dot).
class MonoBitmap {
  final int width;
  final int height;
  final Uint8List pixels;
  const MonoBitmap(this.width, this.height, this.pixels);

  /// Rows packed MSB first, [rowBytes] bytes per row, image placed at
  /// [offsetX] dots from the left edge (for centering on the paper).
  Uint8List pack({required int rowBytes, int offsetX = 0}) {
    final out = Uint8List(rowBytes * height);
    final maxX = rowBytes * 8;
    for (var y = 0; y < height; y++) {
      final row = y * width;
      final outRow = y * rowBytes;
      for (var x = 0; x < width; x++) {
        if (pixels[row + x] == 0) continue;
        final px = x + offsetX;
        if (px < 0 || px >= maxX) continue;
        out[outRow + (px >> 3)] |= 0x80 >> (px & 7);
      }
    }
    return out;
  }
}

Map<String, Object> _monoWorker(Map<String, Object> args) {
  final rgba = args['rgba'] as Uint8List;
  final w = args['w'] as int;
  final h = args['h'] as int;
  final threshold = args['threshold'] as int;
  final dither = args['dither'] as bool;
  final n = w * h;
  final gray = Float32List(n);
  for (var i = 0; i < n; i++) {
    final o = i * 4;
    final a = rgba[o + 3] / 255.0;
    final lum = 0.299 * rgba[o] + 0.587 * rgba[o + 1] + 0.114 * rgba[o + 2];
    gray[i] = lum * a + 255 * (1 - a); // composite over white paper
  }
  final out = Uint8List(n);
  if (!dither) {
    for (var i = 0; i < n; i++) {
      out[i] = gray[i] < threshold ? 1 : 0;
    }
  } else {
    // Floyd–Steinberg error diffusion.
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        final old = gray[i];
        final black = old < threshold;
        out[i] = black ? 1 : 0;
        final err = old - (black ? 0 : 255);
        if (x + 1 < w) gray[i + 1] += err * 7 / 16;
        if (y + 1 < h) {
          if (x > 0) gray[i + w - 1] += err * 3 / 16;
          gray[i + w] += err * 5 / 16;
          if (x + 1 < w) gray[i + w + 1] += err * 1 / 16;
        }
      }
    }
  }
  return {'pixels': out};
}

/// Converts a rendered label to monochrome. [threshold] 0-255 (darker than
/// it prints black); [dither] uses Floyd–Steinberg for photos/logos.
Future<MonoBitmap> imageToMono(ui.Image img, {int threshold = 160, bool dither = false}) async {
  final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  final rgba = bd!.buffer.asUint8List();
  final res = await compute(_monoWorker, <String, Object>{
    'rgba': rgba,
    'w': img.width,
    'h': img.height,
    'threshold': threshold.clamp(1, 254),
    'dither': dither,
  });
  return MonoBitmap(img.width, img.height, res['pixels'] as Uint8List);
}

/// The monochrome bitmap as a displayable image (black on white).
Future<ui.Image> monoToImage(MonoBitmap m) {
  final rgba = Uint8List(m.width * m.height * 4);
  for (var i = 0; i < m.pixels.length; i++) {
    final v = m.pixels[i] == 1 ? 0 : 255;
    final o = i * 4;
    rgba[o] = v;
    rgba[o + 1] = v;
    rgba[o + 2] = v;
    rgba[o + 3] = 255;
  }
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(rgba, m.width, m.height, ui.PixelFormat.rgba8888, done.complete);
  return done.future;
}

/// Printable dots across the head for common roll widths at 203 dpi.
int paperDotsForWidth(int paperWidthMm) => paperWidthMm >= 80 ? 576 : 384;

enum LabelCutMode { none, each, end }

/// `GS v 0 m xL xH yL yH d1…dk` raster bit image, sent in bands so small
/// printers with tiny buffers don't drop data.
List<int> escPosRasterImage(MonoBitmap bmp, {required int paperDots, int bandRows = 128}) {
  final rowBytes = (paperDots + 7) ~/ 8;
  final offsetX = bmp.width < paperDots ? (paperDots - bmp.width) ~/ 2 : 0;
  final packed = bmp.pack(rowBytes: rowBytes, offsetX: offsetX);
  final out = <int>[];
  for (var y = 0; y < bmp.height; y += bandRows) {
    final rows = (bmp.height - y) < bandRows ? bmp.height - y : bandRows;
    out.addAll([0x1D, 0x76, 0x30, 0x00, rowBytes & 0xFF, (rowBytes >> 8) & 0xFF, rows & 0xFF, (rows >> 8) & 0xFF]);
    out.addAll(packed.sublist(y * rowBytes, (y + rows) * rowBytes));
  }
  return out;
}

/// `ESC J n` — feeds [dots] dot rows (split into ≤255 chunks).
List<int> escPosFeedDots(int dots) {
  final out = <int>[];
  var left = dots;
  while (left > 0) {
    final n = left > 255 ? 255 : left;
    out.addAll([0x1B, 0x4A, n]);
    left -= n;
  }
  return out;
}

/// One complete print job: every label bitmap in order (copies already
/// expanded by the caller via [copies]), with a feed gap after each label
/// and optional cuts.
List<int> buildLabelRasterJob({
  required List<({MonoBitmap bitmap, int copies})> labels,
  required int paperDots,
  int feedDots = 24,
  LabelCutMode cut = LabelCutMode.none,
  bool fullCut = false,
}) {
  final out = <int>[...(EscPosBuilder()..initialize()..alignLeft()).build()];
  for (final l in labels) {
    final raster = escPosRasterImage(l.bitmap, paperDots: paperDots);
    for (var i = 0; i < l.copies; i++) {
      out.addAll(raster);
      out.addAll(escPosFeedDots(feedDots));
      if (cut == LabelCutMode.each) out.addAll((EscPosBuilder()..cut(full: fullCut)).build());
    }
  }
  if (cut == LabelCutMode.end) {
    out.addAll((EscPosBuilder()
          ..feedPaper(3)
          ..cut(full: fullCut))
        .build());
  }
  return out;
}
