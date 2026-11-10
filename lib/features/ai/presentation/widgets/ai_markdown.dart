import 'package:flutter/material.dart';

/// Minimal markdown for Aptigen AI replies — the model answers with
/// **bold**, *italic*, `code`, `#` headings and `-`/`1.` lists, which plain
/// Text showed as raw asterisks. Line-based; no tables/links (row results
/// already render as _AiResultTable).
class AiMarkdown extends StatelessWidget {
  final String text;
  final TextStyle style;
  const AiMarkdown(this.text, {super.key, required this.style});

  static final _bullet = RegExp(r'^\s*[-*•]\s+(.*)$');
  static final _numbered = RegExp(r'^\s*(\d+)[.)]\s+(.*)$');
  static final _heading = RegExp(r'^\s*#{1,6}\s+(.*)$');

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (final raw in text.replaceAll('\r\n', '\n').split('\n')) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        if (children.isNotEmpty) children.add(const SizedBox(height: 6));
        continue;
      }
      final heading = _heading.firstMatch(line);
      final bullet = _bullet.firstMatch(line);
      final numbered = _numbered.firstMatch(line);
      if (heading != null) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 2),
          child: Text.rich(TextSpan(children: _inline(heading.group(1)!, style)), style: style.copyWith(fontWeight: FontWeight.w700, fontSize: (style.fontSize ?? 13.5) + 1)),
        ));
      } else if (bullet != null || numbered != null) {
        final marker = bullet != null ? '•' : '${numbered!.group(1)}.';
        final body = bullet != null ? bullet.group(1)! : numbered!.group(2)!;
        final indent = (line.length - line.trimLeft().length) >= 2 ? 14.0 : 0.0;
        children.add(Padding(
          padding: EdgeInsets.only(left: indent, top: 1, bottom: 1),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 18, child: Text(marker, style: style)),
            Expanded(child: Text.rich(TextSpan(children: _inline(body, style)), style: style)),
          ]),
        ));
      } else {
        children.add(Text.rich(TextSpan(children: _inline(line, style)), style: style));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }

  // **bold** / __bold__, *italic* / _italic_, `code`.
  static final _inlinePattern = RegExp(r'(\*\*|__)(.+?)\1|`([^`]+)`|(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?!\w)|(?<!\w)_(?!\s)(.+?)(?<!\s)_(?!\w)');

  static List<InlineSpan> _inline(String source, TextStyle base) {
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _inlinePattern.allMatches(source)) {
      if (m.start > last) spans.add(TextSpan(text: source.substring(last, m.start)));
      if (m.group(2) != null) {
        spans.add(TextSpan(children: _inline(m.group(2)!, base), style: const TextStyle(fontWeight: FontWeight.w700)));
      } else if (m.group(3) != null) {
        spans.add(TextSpan(
          text: m.group(3),
          style: TextStyle(fontFamily: 'monospace', fontSize: (base.fontSize ?? 13.5) - 1, backgroundColor: (base.color ?? Colors.grey).withValues(alpha: 0.1)),
        ));
      } else {
        spans.add(TextSpan(text: m.group(4) ?? m.group(5), style: const TextStyle(fontStyle: FontStyle.italic)));
      }
      last = m.end;
    }
    if (last < source.length) spans.add(TextSpan(text: source.substring(last)));
    return spans;
  }
}

/// Plain text for TTS — drops the markdown markers so the voice doesn't
/// read out "asterisk asterisk".
String stripAiMarkdown(String text) => text
    .replaceAllMapped(RegExp(r'(\*\*|__)(.+?)\1'), (m) => m.group(2)!)
    .replaceAllMapped(RegExp(r'`([^`]+)`'), (m) => m.group(1)!)
    .replaceAllMapped(RegExp(r'(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?!\w)'), (m) => m.group(1)!)
    .replaceAll(RegExp(r'^\s*#{1,6}\s+', multiLine: true), '')
    .replaceAll(RegExp(r'^\s*[-*•]\s+', multiLine: true), '');
