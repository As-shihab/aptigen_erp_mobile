import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/network/http_client.dart';
import '../../../../shared/ui/motion_kit.dart';

// Small helpers shared by the attendance, shift, roster and biometrics
// pages (HR → attendance and shifts). Kept out of shared/ on purpose.

/// Parses "#RRGGBB" / "RRGGBB" / "#RGB" into a colour.
Color hexColor(dynamic v, [Color fallback = const Color(0xFF5D36FF)]) {
  var s = str(v).trim().replaceFirst('#', '');
  if (s.length == 3) s = s.split('').map((c) => '$c$c').join();
  if (s.length == 6) s = 'FF$s';
  if (s.length != 8) return fallback;
  final n = int.tryParse(s, radix: 16);
  return n == null ? fallback : Color(n);
}

/// "HH:mm" / "HH:mm:ss" → minutes after midnight.
int? minutesOfDay(dynamic t) {
  final parts = str(t).split(':');
  if (parts.length < 2) return null;
  final h = int.tryParse(parts[0].trim());
  final m = int.tryParse(parts[1].trim());
  if (h == null || m == null) return null;
  return h * 60 + m;
}

/// "13:30" → "1:30 PM".
String clock(dynamic t) {
  final m = minutesOfDay(t);
  if (m == null) return str(t);
  return DateFormat('h:mm a').format(DateTime(2000, 1, 1, m ~/ 60, m % 60));
}

/// Shift wraps past midnight (start later than end).
bool wrapsMidnight(dynamic start, dynamic end) {
  final s = minutesOfDay(start);
  final e = minutesOfDay(end);
  return s != null && e != null && s > e;
}

String ymd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

/// Calendar day of a @db.Date value ("2026-10-24T00:00:00.000Z") without
/// the local-timezone shift toLocal() would apply.
DateTime? calDate(dynamic v) {
  final d = parseDate(v);
  return d == null ? null : DateTime(d.year, d.month, d.day);
}

DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// "Xh 05m".
String fmtMinutes(int mins) {
  final m = mins < 0 ? 0 : mins;
  return '${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}m';
}

/// first_name + last_name of an expanded employee map.
String personName(dynamic e) {
  if (e is! Map) return '';
  return '${str(e['first_name'])} ${str(e['last_name'])}'.trim();
}

List<Map<String, dynamic>> rowsOf(dynamic res) => unwrapList(res).whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();

/// Employee picker option: "Name (EMP-01)".
PickOption employeeOption(Map<String, dynamic> e) {
  final name = personName(e);
  final no = str(e['employee_no']);
  return PickOption(e['id'], name.isEmpty ? 'Employee #${e['id']}' : name, sub: no.isEmpty ? null : no);
}

/// Coloured shift chip with a sun / moon glyph.
class ShiftChip extends StatelessWidget {
  final String name;
  final Color color;
  final bool night;
  final String? trailing;
  const ShiftChip({super.key, required this.name, required this.color, this.night = false, this.trailing});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(12)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(night ? Icons.dark_mode_rounded : Icons.wb_sunny_rounded, size: 11, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(trailing == null ? name : '$name  $trailing',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
          ),
        ]),
      );
}

/// Neutral rounded chip (department, group, ...).
class SoftChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color? color;
  const SoftChip(this.label, {super.key, this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final fg = color ?? p.label;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color == null ? p.surface : fg.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(12)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 11, color: fg), const SizedBox(width: 4)],
        Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg))),
      ]),
    );
  }
}

/// Pulsing dot (used for "still checked in" / "online").
class PulseDot extends StatefulWidget {
  final Color color;
  final bool active;
  final double size;
  const PulseDot({super.key, required this.color, this.active = true, this.size = 8});

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.repeat();
  }

  @override
  void didUpdateWidget(PulseDot old) {
    super.didUpdateWidget(old);
    if (widget.active && !_c.isAnimating) _c.repeat();
    if (!widget.active && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s * 2.4,
      height: s * 2.4,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Stack(alignment: Alignment.center, children: [
          if (widget.active)
            Container(
              width: s + s * 1.4 * _c.value,
              height: s + s * 1.4 * _c.value,
              decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color.withValues(alpha: 0.35 * (1 - _c.value))),
            ),
          Container(width: s, height: s, decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color)),
        ]),
      ),
    );
  }
}

/// Segmented two/three-way toggle with a sliding highlight.
class SegmentToggle<T> extends StatelessWidget {
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;
  const SegmentToggle({super.key, required this.value, required this.options, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(12)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final o in options)
          PressScale(
            onTap: () => onChanged(o.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: o.$1 == value ? p.brand : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(o.$2, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: o.$1 == value ? Colors.white : p.label)),
            ),
          ),
      ]),
    );
  }
}

/// Round icon button for header rows (prev / next, etc.).
class RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color? color;
  const RoundIconButton(this.icon, {super.key, this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return PressScale(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(color: p.card, shape: BoxShape.circle, border: Border.all(color: p.line)),
        child: Icon(icon, size: 20, color: onTap == null ? p.label.withValues(alpha: 0.4) : (color ?? p.text)),
      ),
    );
  }
}
