import 'package:flutter/material.dart';
import '../../sell/market/presentation/widgets/market_ui.dart';

// Notes use the same SAP Horizon kit as Sales / Store (market_ui.dart), plus
// a few note-specific bits shared by the board and the editor.
export '../../sell/market/presentation/widgets/market_ui.dart';

/// Category colour from its stored hex (`#2563eb`), falling back to a stable
/// palette pick by name so uncoloured categories still differ.
Color noteCategoryColor(String? hex, String name, MarketPalette p) {
  final raw = (hex ?? '').replaceAll('#', '').trim();
  if (raw.length == 6) {
    final v = int.tryParse('FF$raw', radix: 16);
    if (v != null) return Color(v);
  }
  const fallback = [Color(0xFF0A6ED1), Color(0xFF188918), Color(0xFFE76500), Color(0xFF7858FF), Color(0xFF0E7490), Color(0xFFC026D3)];
  if (name.isEmpty) return p.neutral;
  return fallback[name.codeUnits.fold<int>(0, (a, b) => a + b) % fallback.length];
}

IconData noteVisibilityIcon(String visibility) => switch (visibility) {
      'private' => Icons.lock_outline,
      'specific' => Icons.group_outlined,
      _ => Icons.public,
    };

String noteVisibilityLabel(String visibility) => switch (visibility) {
      'private' => 'Only me',
      'specific' => 'Selected people',
      _ => 'Everyone in workspace',
    };

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "Today, 14:05" / "Tomorrow, 09:00" / "12 Oct, 14:05".
String noteReminderLabel(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = day.difference(today).inDays;
  final time = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  if (diff == 0) return 'Today, $time';
  if (diff == 1) return 'Tomorrow, $time';
  if (diff == -1) return 'Yesterday, $time';
  return '${d.day} ${_months[d.month - 1]}${d.year != now.year ? ' ${d.year}' : ''}, $time';
}

/// Small pill with a coloured dot — category tags on cards and filters.
class NoteTag extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  const NoteTag(this.label, {super.key, required this.color, this.selected = false, this.onTap, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? p.brandSoft : p.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? p.brand : p.line),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12.5, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? p.brand : p.text)),
        ]),
      ),
    );
  }
}
