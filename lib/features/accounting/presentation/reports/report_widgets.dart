import 'package:flutter/material.dart';
import '../../../../core/utils/currency.dart';
import '../../../../shared/ui/motion_kit.dart';

// Small pieces shared by the accounting report pages (Profit & loss,
// Balance sheet, Analytics) — panel card, empty state, account amount row
// and the date range picker.

String reportMoney(num v) => formatMoney(v);
String reportMoneyWhole(num v) => formatMoney(v, decimalDigits: 0);

DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

// ── Panel ───────────────────────────────────────────────────────────────

class ReportPanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? sub;
  final Accent accent;
  final Widget? trailing;
  final Widget child;
  const ReportPanel({super.key, required this.icon, required this.title, this.sub, this.accent = Accent.ocean, this.trailing, required this.child});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return GlowCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          AccentIcon(icon, accent: accent, size: 32),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
              if (sub != null) Text(sub!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: p.label)),
            ]),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ]),
        const SizedBox(height: 12),
        child,
      ]),
    );
  }
}

class ReportEmpty extends StatelessWidget {
  final IconData icon;
  final String text;
  const ReportEmpty({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(children: [
        Icon(icon, size: 26, color: p.label.withValues(alpha: 0.5)),
        const SizedBox(height: 6),
        Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: p.label)),
      ]),
    );
  }
}

/// "code — name" on the left, amount on the right, hairline between rows.
class AccountAmountList extends StatelessWidget {
  final List<({String code, String name, double amount})> rows;
  final Color? amountColor;
  const AccountAmountList({super.key, required this.rows, this.amountColor});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Column(children: [
      for (var i = 0; i < rows.length; i++) ...[
        if (i > 0) Divider(height: 1, color: p.line),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(rows[i].name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.text)),
                if (rows[i].code.isNotEmpty) Text(rows[i].code, style: TextStyle(fontSize: 11.5, color: p.label)),
              ]),
            ),
            const SizedBox(width: 8),
            Text(reportMoney(rows[i].amount), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: amountColor ?? p.text)),
          ]),
        ),
      ],
    ]);
  }
}

// ── Date range ──────────────────────────────────────────────────────────

enum ReportRangePreset { thisMonth, last30, thisYear, custom }

/// Preset chips plus, for "Custom", a from/to pair of DatePickFields.
/// Reports `(start, end)` as whole local days (both inclusive).
class ReportDateRange extends StatelessWidget {
  final ReportRangePreset preset;
  final DateTime start;
  final DateTime end;
  final void Function(ReportRangePreset preset, DateTime start, DateTime end) onChanged;
  const ReportDateRange({super.key, required this.preset, required this.start, required this.end, required this.onChanged});

  static (DateTime, DateTime) rangeFor(ReportRangePreset preset, {DateTime? now}) {
    final today = dayOnly(now ?? DateTime.now());
    return switch (preset) {
      ReportRangePreset.thisMonth => (DateTime(today.year, today.month, 1), today),
      ReportRangePreset.last30 => (today.subtract(const Duration(days: 29)), today),
      ReportRangePreset.thisYear => (DateTime(today.year, 1, 1), today),
      ReportRangePreset.custom => (today, today),
    };
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ChipFilter<ReportRangePreset>(
        padding: EdgeInsets.zero,
        value: preset,
        options: const [
          (id: ReportRangePreset.thisMonth, label: 'This month', count: null),
          (id: ReportRangePreset.last30, label: 'Last 30 days', count: null),
          (id: ReportRangePreset.thisYear, label: 'This year', count: null),
          (id: ReportRangePreset.custom, label: 'Custom', count: null),
        ],
        onChanged: (v) {
          if (v == ReportRangePreset.custom) {
            onChanged(v, start, end);
          } else {
            final (s, e) = rangeFor(v);
            onChanged(v, s, e);
          }
        },
      ),
      if (preset == ReportRangePreset.custom) ...[
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: DatePickField(
              value: start,
              hint: 'From',
              lastDate: end,
              onChanged: (d) {
                if (d != null) onChanged(preset, dayOnly(d), end);
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: DatePickField(
              value: end,
              hint: 'To',
              firstDate: start,
              onChanged: (d) {
                if (d != null) onChanged(preset, start, dayOnly(d));
              },
            ),
          ),
        ]),
      ] else ...[
        const SizedBox(height: 6),
        Text('${fmtDate(start)} – ${fmtDate(end)}', style: TextStyle(fontSize: 11.5, color: p.label)),
      ],
    ]);
  }
}

/// True when [date] falls on a day within [start]..[end] (both inclusive).
bool inDayRange(DateTime? date, DateTime start, DateTime end) {
  if (date == null) return false;
  final d = dayOnly(date);
  return !d.isBefore(start) && !d.isAfter(end);
}
