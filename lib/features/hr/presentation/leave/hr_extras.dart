import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../shared/ui/motion_kit.dart';

// Small helpers shared by the leave / calendar / kpi / recruitment / notify
// screens: name + html helpers, colour parsing, a step wizard shell and a
// swipeable month calendar (no extra packages).

// ── Text helpers ────────────────────────────────────────────────────────

String empName(dynamic e) {
  if (e is! Map) return '';
  return '${str(e['first_name'])} ${str(e['last_name'])}'.trim();
}

String empLabel(Map e) {
  final n = empName(e);
  final no = str(e['employee_no']);
  return no.isEmpty ? n : '$n ($no)';
}

/// Stored rich-text (html) → plain text for display / editing.
String htmlToText(String? html) {
  if (html == null || html.isEmpty) return '';
  var s = html
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</(p|div|li|h[1-6])>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '• ')
      .replaceAll(RegExp(r'<[^>]*>'), '');
  s = s
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");
  return s.replaceAll(RegExp(r'[ \t]+'), ' ').replaceAll(RegExp(r'\n\s*\n+'), '\n').trim();
}

/// Plain text typed on mobile → simple paragraphs, so desktop / careers
/// pages that render the html keep line breaks.
String textToHtml(String text) {
  const esc = HtmlEscape(HtmlEscapeMode.element);
  return text.trim().split(RegExp(r'\n')).where((l) => l.trim().isNotEmpty).map((l) => '<p>${esc.convert(l.trim())}</p>').join();
}

/// Json array column (may arrive as a list or a json string).
List<dynamic> jsonList(dynamic v) {
  if (v is List) return v;
  if (v is String && v.isNotEmpty) {
    try {
      final d = jsonDecode(v);
      if (d is List) return d;
    } catch (_) {}
  }
  return const [];
}

num? toNum(dynamic v) => v == null ? null : (v is num ? v : num.tryParse(v.toString()));

String fmtNum(num? v) => v == null ? '—' : NumberFormat.decimalPattern().format(v);

// ── Dates ───────────────────────────────────────────────────────────────

DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Date-only value from the API (`@db.Date` arrives as midnight UTC).
DateTime? apiDay(dynamic v) {
  final d = parseDate(v);
  if (d == null) return null;
  final u = d.isUtc ? d : d.toUtc();
  return DateTime(u.year, u.month, u.day);
}

String ymd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

/// ISO for a date-only column: midnight UTC of that calendar day.
String isoDay(DateTime d) => DateTime.utc(d.year, d.month, d.day).toIso8601String();

String fmtDay(DateTime? d) => d == null ? '—' : DateFormat('d MMM yyyy').format(d);

String rangeText(List<DateTime> days) {
  if (days.isEmpty) return '—';
  final s = [...days]..sort();
  final a = s.first, b = s.last;
  if (s.length == 1) return DateFormat('d MMM yyyy').format(a);
  return '${DateFormat(a.year == b.year ? 'd MMM' : 'd MMM yyyy').format(a)} – ${DateFormat('d MMM yyyy').format(b)}';
}

// ── Colours ─────────────────────────────────────────────────────────────

const eventPalette = <Color>[
  Color(0xFF168EFF), Color(0xFFC87B00), Color(0xFF75980B), Color(0xFFDF1278), Color(0xFF8B47D7), Color(0xFF049F9A),
  Color(0xFF0070F2), Color(0xFFCC00DC), Color(0xFF798C77), Color(0xFFDA6C6C),
];

Color colorForEventType(int id) => eventPalette[id.abs() % eventPalette.length];

Color? hexColor(String? hex) {
  if (hex == null) return null;
  var h = hex.trim().replaceFirst('#', '');
  if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
  if (h.length != 6) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

String colorHex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

// ── Wizard shell ────────────────────────────────────────────────────────

/// Animated numbered stepper: filled progress line, check marks for done
/// steps and a soft pulse on the current one.
class StepHeader extends StatelessWidget {
  final List<String> steps;
  final int step;
  final ValueChanged<int>? onStep;
  const StepHeader({super.key, required this.steps, required this.step, this.onStep});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return LayoutBuilder(builder: (context, c) {
      final n = steps.length;
      final slot = c.maxWidth / n;
      return SizedBox(
        height: 58,
        child: Stack(children: [
          Positioned(
            left: slot / 2,
            right: slot / 2,
            top: 15,
            child: Container(height: 3, decoration: BoxDecoration(color: p.line, borderRadius: BorderRadius.circular(2))),
          ),
          Positioned(
            left: slot / 2,
            top: 15,
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: n <= 1 ? 0 : step / (n - 1)),
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutCubic,
              builder: (_, v, _) => Container(
                width: (c.maxWidth - slot) * v,
                height: 3,
                decoration: BoxDecoration(color: p.brand, borderRadius: BorderRadius.circular(2)),
              ),
            ),
          ),
          Row(children: [
            for (var i = 0; i < n; i++)
              SizedBox(
                width: slot,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onStep == null ? null : () => onStep!(i),
                  child: Column(children: [
                    AnimatedScale(
                      scale: i == step ? 1.12 : 1,
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutBack,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 240),
                        width: 32,
                        height: 32,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i < step ? p.brand : p.card,
                          border: Border.all(color: i <= step ? p.brand : p.line, width: 2),
                        ),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
                          child: i < step
                              ? const Icon(Icons.check_rounded, key: ValueKey('done'), size: 17, color: Colors.white)
                              : Text('${i + 1}',
                                  key: ValueKey('n$i'),
                                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: i == step ? p.brand : p.label)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(steps[i],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, fontWeight: i == step ? FontWeight.w700 : FontWeight.w500, color: i == step ? p.text : p.label)),
                  ]),
                ),
              ),
          ]),
        ]),
      );
    });
  }
}

/// Bottom-sheet shell for multi-step forms: title, stepper, sliding body
/// and a footer with back / next (or custom final actions).
class WizardShell extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<String> steps;
  final int step;
  final int direction;
  final Widget body;
  final ValueChanged<int>? onStep;
  final VoidCallback onBack;
  final VoidCallback? onNext;
  final List<Widget>? finalActions;
  final bool busy;
  const WizardShell({
    super.key,
    required this.title,
    this.subtitle,
    required this.steps,
    required this.step,
    this.direction = 1,
    required this.body,
    this.onStep,
    required this.onBack,
    this.onNext,
    this.finalActions,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final last = step == steps.length - 1;
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.9,
      child: Column(children: [
        const SheetGrabber(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 6),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.text)),
                Text(subtitle ?? 'Step ${step + 1} of ${steps.length} · ${steps[step]}', style: TextStyle(fontSize: 12.5, color: p.label)),
              ]),
            ),
            IconButton(onPressed: () => Navigator.pop(context), icon: Icon(Icons.close_rounded, color: p.label)),
          ]),
        ),
        Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 8), child: StepHeader(steps: steps, step: step, onStep: onStep)),
        Divider(height: 1, color: p.line),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, anim) {
              final inbound = child.key == ValueKey(step);
              final dx = (inbound ? 0.12 : -0.12) * direction;
              return FadeTransition(
                opacity: anim,
                child: SlideTransition(position: Tween(begin: Offset(dx, 0), end: Offset.zero).animate(anim), child: child),
              );
            },
            child: KeyedSubtree(
              key: ValueKey(step),
              child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 16), child: body),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(children: [
              TextButton(onPressed: busy ? null : onBack, child: Text(step == 0 ? 'Cancel' : 'Back')),
              const SizedBox(width: 8),
              if (last && finalActions != null)
                ...finalActions!
              else
                Expanded(child: GradientButton(label: 'Next', icon: Icons.arrow_forward_rounded, onTap: onNext, busy: busy && last)),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Read-only summary tile used on wizard review steps.
class ReviewTile extends StatelessWidget {
  final String label;
  final String value;
  final int index;
  const ReviewTile(this.label, this.value, {super.key, this.index = 0});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return FadeSlideIn(
      index: index,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 11.5, color: p.label)),
          const SizedBox(height: 3),
          Text(value.isEmpty ? '—' : value, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.text)),
        ]),
      ),
    );
  }
}

/// Two-column grid of [ReviewTile]s.
Widget reviewGrid(List<(String, String)> items) => LayoutBuilder(
      builder: (_, c) => Wrap(spacing: 10, runSpacing: 10, children: [
        for (var i = 0; i < items.length; i++) SizedBox(width: (c.maxWidth - 10) / 2, child: ReviewTile(items[i].$1, items[i].$2, index: i)),
      ]),
    );

// ── Month calendar ──────────────────────────────────────────────────────

const _weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

/// One month as a 6×7 grid. Days get a selection fill, a today ring,
/// optional background mark (e.g. already-taken leave) and event dots.
class MonthGrid extends StatelessWidget {
  final DateTime month;
  final bool Function(DateTime day)? isSelected;
  final ValueChanged<DateTime>? onTap;
  final List<Color> Function(DateTime day)? dotsFor;
  final Color? Function(DateTime day)? markFor;
  final double cellHeight;
  const MonthGrid({super.key, required this.month, this.isSelected, this.onTap, this.dotsFor, this.markFor, this.cellHeight = 46});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final first = DateTime(month.year, month.month, 1);
    final lead = first.weekday % 7; // Sunday first
    final today = dayOnly(DateTime.now());
    return Column(children: [
      for (var r = 0; r < 6; r++)
        SizedBox(
          height: cellHeight,
          child: Row(children: [
            for (var c = 0; c < 7; c++)
              Expanded(child: _cell(context, p, DateTime(first.year, first.month, 1 + r * 7 + c - lead), today)),
          ]),
        ),
    ]);
  }

  Widget _cell(BuildContext context, MarketPalette p, DateTime day, DateTime today) {
    final inMonth = day.month == month.month;
    final sel = isSelected?.call(day) ?? false;
    final isToday = day == today;
    final mark = inMonth ? markFor?.call(day) : null;
    final dots = inMonth ? (dotsFor?.call(day) ?? const <Color>[]) : const <Color>[];
    final weekend = day.weekday == DateTime.friday || day.weekday == DateTime.saturday;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap == null || !inMonth ? null : () => onTap!(day),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: sel ? p.brand : (mark?.withValues(alpha: 0.18)),
              border: isToday && !sel ? Border.all(color: p.brand, width: 1.6) : null,
            ),
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: sel || isToday ? FontWeight.w700 : FontWeight.w500,
                color: sel
                    ? Colors.white
                    : !inMonth
                        ? p.label.withValues(alpha: 0.35)
                        : mark ?? (weekend ? p.label : p.text),
              ),
              child: Text('${day.day}'),
            ),
          ),
          SizedBox(
            height: 6,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (final c in dots.take(3))
                Container(width: 4.5, height: 4.5, margin: const EdgeInsets.symmetric(horizontal: 1), decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Month header + weekday row + swipeable [MonthGrid] pages.
class SwipeCalendar extends StatefulWidget {
  final DateTime initialMonth;
  final ValueChanged<DateTime>? onMonthChanged;
  final bool Function(DateTime day)? isSelected;
  final ValueChanged<DateTime>? onTap;
  final List<Color> Function(DateTime day)? dotsFor;
  final Color? Function(DateTime day)? markFor;
  final double cellHeight;
  const SwipeCalendar({
    super.key,
    required this.initialMonth,
    this.onMonthChanged,
    this.isSelected,
    this.onTap,
    this.dotsFor,
    this.markFor,
    this.cellHeight = 46,
  });

  @override
  State<SwipeCalendar> createState() => SwipeCalendarState();
}

class SwipeCalendarState extends State<SwipeCalendar> {
  static const _base = 1200;
  late final DateTime _origin = DateTime(widget.initialMonth.year, widget.initialMonth.month);
  late final PageController _pc = PageController(initialPage: _base);
  late DateTime _month = _origin;

  DateTime _monthFor(int page) => DateTime(_origin.year, _origin.month + page - _base);

  void jumpTo(DateTime month) {
    final diff = (month.year - _origin.year) * 12 + month.month - _origin.month;
    _pc.animateToPage(_base + diff, duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(position: Tween(begin: const Offset(0, 0.3), end: Offset.zero).animate(a), child: child),
            ),
            child: Align(
              key: ValueKey(_month),
              alignment: Alignment.centerLeft,
              child: Text(DateFormat('MMMM yyyy').format(_month), style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700, color: p.text)),
            ),
          ),
        ),
        _navBtn(p, Icons.chevron_left_rounded, () => _pc.previousPage(duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic)),
        const SizedBox(width: 6),
        _navBtn(p, Icons.chevron_right_rounded, () => _pc.nextPage(duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic)),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        for (final w in _weekdays)
          Expanded(child: Center(child: Text(w, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: p.label)))),
      ]),
      const SizedBox(height: 4),
      SizedBox(
        height: widget.cellHeight * 6,
        child: PageView.builder(
          controller: _pc,
          onPageChanged: (i) {
            setState(() => _month = _monthFor(i));
            widget.onMonthChanged?.call(_month);
          },
          itemBuilder: (_, i) => MonthGrid(
            month: _monthFor(i),
            isSelected: widget.isSelected,
            onTap: widget.onTap,
            dotsFor: widget.dotsFor,
            markFor: widget.markFor,
            cellHeight: widget.cellHeight,
          ),
        ),
      ),
    ]);
  }

  Widget _navBtn(MarketPalette p, IconData icon, VoidCallback onTap) => PressScale(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: p.text),
        ),
      );
}

/// Wrapping multi-choice chips (e.g. weekdays, stages).
class ToggleChips<T> extends StatelessWidget {
  final List<(T, String)> options;
  final bool Function(T) isOn;
  final ValueChanged<T> onTap;
  final Color? color;
  const ToggleChips({super.key, required this.options, required this.isOn, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final c = color ?? p.brand;
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final o in options)
        PressScale(
          onTap: () => onTap(o.$1),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isOn(o.$1) ? c : p.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isOn(o.$1) ? c : p.line),
            ),
            child: Text(o.$2, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: isOn(o.$1) ? Colors.white : p.text)),
          ),
        ),
    ]);
  }
}

/// Number field with − / + buttons.
class StepperField extends StatelessWidget {
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  const StepperField({super.key, required this.value, required this.onChanged, this.min = 0, this.max = 9999});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    Widget btn(IconData i, int next) => PressScale(
          onTap: next < min || next > max ? null : () => onChanged(next),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(14)),
            child: Icon(i, color: next < min || next > max ? p.label.withValues(alpha: 0.4) : p.brand),
          ),
        );
    return Row(children: [
      btn(Icons.remove_rounded, value - 1),
      Expanded(
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
            child: Text('$value', key: ValueKey(value), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: p.text)),
          ),
        ),
      ),
      btn(Icons.add_rounded, value + 1),
    ]);
  }
}
