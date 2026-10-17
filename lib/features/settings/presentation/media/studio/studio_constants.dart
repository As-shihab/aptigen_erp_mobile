import 'dart:math' as math;

import 'package:flutter/material.dart';

// Port of erp/desktop's image-studio/constants.ts.
//
// Literal colors and gradients in this file depict *image content*
// (background swatches, scene thumbnails, filter looks) — they are what ends
// up inside the edited picture, not UI chrome, so they deliberately don't use
// MarketPalette.

typedef StudioOption = ({String id, String label});

// ── Filter looks (approximate thumbnails; the server preview is exact) ──

typedef _Matrix = List<double>;

const _Matrix _identity = [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0];

_Matrix _saturate(double s) => [
      0.213 + 0.787 * s, 0.715 - 0.715 * s, 0.072 - 0.072 * s, 0, 0,
      0.213 - 0.213 * s, 0.715 + 0.285 * s, 0.072 - 0.072 * s, 0, 0,
      0.213 - 0.213 * s, 0.715 - 0.715 * s, 0.072 + 0.928 * s, 0, 0,
      0, 0, 0, 1, 0,
    ];

_Matrix _grayscale(double a) => _saturate(1 - a);

_Matrix _sepia(double a) {
  final k = 1 - a;
  return [
    0.393 + 0.607 * k, 0.769 - 0.769 * k, 0.189 - 0.189 * k, 0, 0,
    0.349 - 0.349 * k, 0.686 + 0.314 * k, 0.168 - 0.168 * k, 0, 0,
    0.272 - 0.272 * k, 0.534 - 0.534 * k, 0.131 + 0.869 * k, 0, 0,
    0, 0, 0, 1, 0,
  ];
}

_Matrix _contrast(double c) {
  final o = (0.5 - 0.5 * c) * 255;
  return [c, 0, 0, 0, o, 0, c, 0, 0, o, 0, 0, c, 0, o, 0, 0, 0, 1, 0];
}

_Matrix _brightness(double b) => [b, 0, 0, 0, 0, 0, b, 0, 0, 0, 0, 0, b, 0, 0, 0, 0, 0, 1, 0];

_Matrix _hueRotate(double deg) {
  final r = deg * math.pi / 180;
  final c = math.cos(r);
  final s = math.sin(r);
  return [
    0.213 + c * 0.787 - s * 0.213, 0.715 - c * 0.715 - s * 0.715, 0.072 - c * 0.072 + s * 0.928, 0, 0,
    0.213 - c * 0.213 + s * 0.143, 0.715 + c * 0.285 + s * 0.140, 0.072 - c * 0.072 - s * 0.283, 0, 0,
    0.213 - c * 0.213 - s * 0.787, 0.715 - c * 0.715 + s * 0.715, 0.072 + c * 0.928 + s * 0.072, 0, 0,
    0, 0, 0, 1, 0,
  ];
}

/// Applies [first], then [then] (CSS filter lists apply left to right).
_Matrix _chain(_Matrix first, _Matrix then) {
  final out = List<double>.filled(20, 0);
  for (var row = 0; row < 4; row++) {
    for (var col = 0; col < 5; col++) {
      var v = 0.0;
      for (var k = 0; k < 4; k++) {
        v += then[row * 5 + k] * first[k * 5 + col];
      }
      if (col == 4) v += then[row * 5 + 4];
      out[row * 5 + col] = v;
    }
  }
  return out;
}

_Matrix _all(List<_Matrix> steps) => steps.fold(_identity, _chain);

final List<({String id, String label, ColorFilter? look})> studioFilters = [
  (id: 'none', label: 'None', look: null),
  (id: 'mono', label: 'Mono', look: ColorFilter.matrix(_grayscale(1))),
  (id: 'sepia', label: 'Sepia', look: ColorFilter.matrix(_sepia(0.85))),
  (id: 'vivid', label: 'Vivid', look: ColorFilter.matrix(_all([_saturate(1.6), _contrast(1.1)]))),
  (id: 'warm', label: 'Warm', look: ColorFilter.matrix(_all([_sepia(0.3), _saturate(1.35), _hueRotate(-10)]))),
  (id: 'cool', label: 'Cool', look: ColorFilter.matrix(_all([_saturate(1.1), _hueRotate(15), _brightness(1.03)]))),
  (id: 'fade', label: 'Fade', look: ColorFilter.matrix(_all([_contrast(0.8), _brightness(1.1), _saturate(0.7)]))),
  (id: 'noir', label: 'Noir', look: ColorFilter.matrix(_all([_grayscale(1), _contrast(1.5), _brightness(0.9)]))),
];

// ── Colors / gradients ──

Color hexColor(String hex) {
  final h = hex.replaceFirst('#', '');
  final v = int.tryParse(h.length == 6 ? 'ff$h' : h, radix: 16);
  return v == null ? Colors.white : Color(v);
}

final RegExp hexRe = RegExp(r'^#[0-9a-fA-F]{6}$');

/// CSS `linear-gradient(<angle>deg, ...)` as a Flutter gradient.
LinearGradient cssLinear(double angle, List<Color> colors, [List<double>? stops, TileMode tileMode = TileMode.clamp]) {
  final r = angle * math.pi / 180;
  final end = Alignment(math.sin(r), -math.cos(r));
  return LinearGradient(begin: -end, end: end, colors: colors, stops: stops, tileMode: tileMode);
}

final List<({String id, String label, Gradient look})> studioScenes = [
  (
    id: 'studio_white',
    label: 'Studio white',
    look: const RadialGradient(
        center: Alignment(0, -0.2), radius: 0.9, colors: [Color(0xFFFFFFFF), Color(0xFFF1F1F1), Color(0xFFDCDCDC)], stops: [0, 0.6, 1]),
  ),
  (
    id: 'studio_gray',
    label: 'Studio gray',
    look: const RadialGradient(
        center: Alignment(0, -0.2), radius: 0.9, colors: [Color(0xFFC9CBCF), Color(0xFF9A9DA3), Color(0xFF6F7278)], stops: [0, 0.65, 1]),
  ),
  (
    id: 'spotlight',
    label: 'Spotlight',
    look: const RadialGradient(
        center: Alignment(0, -0.3), radius: 0.8, colors: [Color(0xFFFDF6E3), Color(0xFF8A8478), Color(0xFF1F1D1A)], stops: [0, 0.35, 0.75]),
  ),
  (id: 'pastel_pink', label: 'Pastel pink', look: cssLinear(160, const [Color(0xFFFFE4EC), Color(0xFFFBCFE0), Color(0xFFF6B8CF)], const [0, 0.55, 1])),
  (id: 'mint', label: 'Mint', look: cssLinear(160, const [Color(0xFFE6FBF3), Color(0xFFBDF0DC), Color(0xFF94E2C4)], const [0, 0.55, 1])),
  (id: 'sunset', label: 'Sunset', look: cssLinear(180, const [Color(0xFFFFB36B), Color(0xFFFF7A7A), Color(0xFF8C4DBB)], const [0, 0.5, 1])),
  (
    id: 'night',
    label: 'Night',
    look: const RadialGradient(
        center: Alignment(0, -0.6), radius: 1, colors: [Color(0xFF33416B), Color(0xFF141A33), Color(0xFF070910)], stops: [0, 0.6, 1]),
  ),
  (
    id: 'marble',
    label: 'Marble',
    look: cssLinear(125, const [Color(0xFFF5F5F3), Color(0xFFE4E3DF), Color(0xFFF8F8F6), Color(0xFFD6D5D0), Color(0xFFF2F1EE)],
        const [0, 0.3, 0.45, 0.6, 1]),
  ),
  (
    id: 'wood',
    label: 'Wood',
    look: const LinearGradient(
      begin: Alignment(-1, 0),
      end: Alignment(-0.7, 0),
      colors: [Color(0xFFA0703F), Color(0xFFB5834D), Color(0xFF8F6234), Color(0xFFA87745)],
      tileMode: TileMode.repeated,
    ),
  ),
  (
    id: 'gradient_glow',
    label: 'Gradient glow',
    look: const RadialGradient(
        center: Alignment(-0.4, -0.4), radius: 1.1, colors: [Color(0xFF7DD3FC), Color(0xFFC084FC), Color(0xFF1E1B4B)], stops: [0, 0.45, 0.9]),
  ),
];

const List<String> colorSwatches = [
  '#ffffff', '#f4f4f5', '#d4d4d8', '#71717a', '#18181b', '#000000',
  '#fee2e2', '#fecaca', '#ef4444', '#ffedd5', '#fdba74', '#f97316',
  '#fef9c3', '#fde047', '#eab308', '#dcfce7', '#86efac', '#22c55e',
  '#dbeafe', '#93c5fd', '#3b82f6', '#ede9fe', '#c4b5fd', '#8b5cf6',
];

const List<({String from, String to, String label})> gradientPresets = [
  (from: '#ffffff', to: '#d4d4d8', label: 'Soft gray'),
  (from: '#e0f2fe', to: '#7dd3fc', label: 'Sky'),
  (from: '#fce7f3', to: '#f9a8d4', label: 'Blush'),
  (from: '#dcfce7', to: '#4ade80', label: 'Spring'),
  (from: '#fef3c7', to: '#fb923c', label: 'Peach'),
  (from: '#ede9fe', to: '#8b5cf6', label: 'Lavender'),
  (from: '#1e293b', to: '#475569', label: 'Slate'),
  (from: '#0f172a', to: '#7c3aed', label: 'Midnight'),
];

const List<StudioOption> backgroundTypes = [
  (id: 'original', label: 'Keep original'),
  (id: 'transparent', label: 'Transparent'),
  (id: 'color', label: 'Color'),
  (id: 'gradient', label: 'Gradient'),
  (id: 'blur', label: 'Blur'),
  (id: 'image', label: 'Image'),
  (id: 'scene', label: 'Scene'),
];

const List<StudioOption> canvasAspects = [
  (id: 'original', label: 'Original'),
  (id: '1:1', label: '1:1'),
  (id: '4:5', label: '4:5'),
  (id: '3:4', label: '3:4'),
  (id: '16:9', label: '16:9'),
  (id: '9:16', label: '9:16'),
];

const List<({String id, String label, double? ratio})> cropAspects = [
  (id: 'free', label: 'Free', ratio: null),
  (id: '1:1', label: '1:1', ratio: 1),
  (id: '4:5', label: '4:5', ratio: 4 / 5),
  (id: '3:4', label: '3:4', ratio: 3 / 4),
  (id: '16:9', label: '16:9', ratio: 16 / 9),
  (id: '9:16', label: '9:16', ratio: 9 / 16),
];

const List<({String key, String label, double min, double max, double step, double neutral})> adjustSliders = [
  (key: 'brightness', label: 'Brightness', min: 0, max: 2, step: 0.05, neutral: 1),
  (key: 'contrast', label: 'Contrast', min: 0, max: 2, step: 0.05, neutral: 1),
  (key: 'saturation', label: 'Saturation', min: 0, max: 2, step: 0.05, neutral: 1),
  (key: 'sharpness', label: 'Sharpness', min: 0, max: 2, step: 0.05, neutral: 1),
  (key: 'blur', label: 'Blur', min: 0, max: 20, step: 0.5, neutral: 0),
];

const List<StudioOption> outputFormats = [
  (id: 'auto', label: 'Auto'),
  (id: 'png', label: 'PNG'),
  (id: 'webp', label: 'WebP'),
  (id: 'jpeg', label: 'JPEG'),
];

const String defaultColor = '#ffffff';
const double defaultBlurRadius = 20;
const double defaultShadowStrength = 0.5;
const int defaultQuality = 85;
const double defaultGradientAngle = 180;

const List<int> compressTargets = [50, 100, 200, 500];

String formatBytes(int bytes) {
  if (bytes <= 0) return '—';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String pct(double v) => '${(v * 100).round()}%';
