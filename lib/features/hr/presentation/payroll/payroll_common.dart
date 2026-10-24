import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../../core/storage/app_storage.dart';
import '../../../../core/utils/currency.dart';
import '../../../../shared/ui/motion_kit.dart';

// Helpers shared by the payroll screens: status tones, name formatting,
// the payslip / batch PDFs (desktop prints an HTML payslip and exports the
// batch to Excel — on a phone both become shareable PDFs) and a few small
// breakdown widgets.

const kMonths = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

String ymd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

/// Local midnight of [d] as a UTC ISO string — mirrors desktop's
/// `moment(date).utc().toISOString()` used in the OData overlap filters.
String isoUtc(DateTime d) => DateTime(d.year, d.month, d.day).toUtc().toIso8601String();

double n(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

String plain(num v) => NumberFormat('#,##0.##').format(v);

String employeeName(Map<String, dynamic>? emp, [Object? fallbackId]) {
  if (emp == null) return fallbackId == null ? 'Unknown employee' : 'Employee #$fallbackId';
  final s = [str(emp['first_name']), str(emp['last_name'])].where((x) => x.isNotEmpty).join(' ');
  return s.isEmpty ? 'Employee #${emp['id'] ?? fallbackId ?? ''}' : s;
}

Map<String, dynamic>? asMap(dynamic v) => v is Map ? v.cast<String, dynamic>() : null;

/// Employee payroll row status → pill tone (desktop STATUS_META).
MarketTone payrollTone(String? status) => switch ((status ?? 'PENDING').toUpperCase()) {
      'PAID' => MarketTone.ok,
      'APPROVED' => MarketTone.ok,
      'GENERATED' => MarketTone.info,
      'PENDING' => MarketTone.warn,
      'CANCELLED' => MarketTone.error,
      _ => MarketTone.neutral,
    };

/// Payroll batch (payroll_historys) status → tone (desktop STATUS_COLORS).
MarketTone batchTone(String? status) => switch ((status ?? 'GENERATED').toUpperCase()) {
      'PAID' => MarketTone.ok,
      'CANCELLED' => MarketTone.error,
      _ => MarketTone.warn,
    };

Future<String> workplaceName() async {
  try {
    final u = await AppStorage.getUser();
    final w = asMap(u?['selectedWorkplace']) ?? asMap(u?['workplace']);
    final name = str(w?['name']);
    return name.isEmpty ? 'Company' : name;
  } catch (_) {
    return 'Company';
  }
}

String _d(dynamic v) {
  final d = parseDate(v);
  return d == null ? '-' : DateFormat('d MMM yyyy').format(d);
}

/// Builds and opens the share sheet for one employee's payslip.
Future<void> sharePayslip(Map<String, dynamic> row) async {
  final company = await workplaceName();
  final emp = asMap(row['employee']);
  final name = employeeName(emp, row['employee_id']);
  final teal = PdfColor.fromHex('#0f766e');
  final grey = PdfColor.fromHex('#6b7280');
  final doc = pw.Document();

  pw.Widget detail(String l, String v) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(l, style: pw.TextStyle(color: grey, fontSize: 10)),
          pw.Text(v, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
        ]),
      );
  pw.Widget amount(String l, num v) => pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 7),
        decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColor.fromHex('#f1f5f9')))),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(l, style: const pw.TextStyle(fontSize: 11)),
          pw.Text(formatMoneyAscii(v), style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        ]),
      );

  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(36),
    build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 14),
        decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: teal, width: 3))),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(company, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 3),
            pw.Text('Employee payslip', style: pw.TextStyle(fontSize: 11, color: teal, fontWeight: pw.FontWeight.bold)),
          ]),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text('Generated ${DateFormat('d MMM yyyy').format(DateTime.now())}', style: pw.TextStyle(fontSize: 9, color: grey)),
            pw.Text('Pay period: ${_d(row['start_date'])} - ${_d(row['end_date'])}', style: pw.TextStyle(fontSize: 9, color: grey)),
          ]),
        ]),
      ),
      pw.SizedBox(height: 20),
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: pw.BoxDecoration(color: PdfColor.fromHex('#f8fafc'), border: pw.Border.all(color: PdfColor.fromHex('#e2e8f0')), borderRadius: pw.BorderRadius.circular(6)),
        child: pw.Row(children: [
          pw.Expanded(child: pw.Column(children: [detail('Employee name', name), detail('Employee no.', str(emp?['employee_no']).isEmpty ? '-' : str(emp?['employee_no']))])),
          pw.SizedBox(width: 24),
          pw.Expanded(
              child: pw.Column(children: [
            detail('Designation', nested(emp ?? const {}, 'designation').isEmpty ? '-' : nested(emp ?? const {}, 'designation')),
            detail('Status', humanize(str(row['status']).isEmpty ? 'PENDING' : str(row['status']))),
          ])),
        ]),
      ),
      pw.SizedBox(height: 20),
      pw.Text('Earnings and deductions', style: pw.TextStyle(fontSize: 10, color: grey, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 6),
      amount('Gross salary', n(row['gross_salary'])),
      amount('Bonuses', n(row['bonuses'])),
      amount('Total deductions', -n(row['total_deductions'])),
      pw.SizedBox(height: 20),
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: pw.BoxDecoration(color: teal, borderRadius: pw.BorderRadius.circular(6)),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('Net pay', style: const pw.TextStyle(color: PdfColors.white, fontSize: 12)),
          pw.Text(formatMoneyAscii(n(row['net_salary'])), style: pw.TextStyle(color: PdfColors.white, fontSize: 20, fontWeight: pw.FontWeight.bold)),
        ]),
      ),
      pw.Spacer(),
      pw.Divider(color: PdfColor.fromHex('#e5e7eb')),
      pw.Center(
        child: pw.Text('This is a system-generated payslip issued by $company and does not require a signature.', style: pw.TextStyle(fontSize: 8, color: grey)),
      ),
    ]),
  ));
  final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-');
  await Printing.sharePdf(bytes: await doc.save(), filename: 'payslip-$safe-${str(row['id'])}.pdf');
}

/// Batch export (desktop: styled Excel) — one row per employee payroll.
Future<void> shareBatchReport(Map<String, dynamic> history, List<Map<String, dynamic>> rows) async {
  final company = await workplaceName();
  final start = parseDate(history['start_date']);
  final end = parseDate(history['end_date']);
  final doc = pw.Document();
  final headers = ['Employee', 'Employee no', 'Gross salary', 'Bonuses', 'Total deductions', 'Net salary', 'Payable days', 'Status'];
  final data = [
    for (final r in rows)
      [
        employeeName(asMap(r['employee']), r['employee_id']),
        str(asMap(r['employee'])?['employee_no']).isEmpty ? '-' : str(asMap(r['employee'])?['employee_no']),
        plain(n(r['gross_salary'])),
        plain(n(r['bonuses'])),
        plain(n(r['total_deductions'])),
        plain(n(r['net_salary'])),
        str(r['total_payable_days']),
        humanize(str(r['status'])),
      ],
  ];
  final total = rows.fold<double>(0, (a, r) => a + n(r['net_salary']));
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4.landscape,
    margin: const pw.EdgeInsets.all(28),
    build: (_) => [
      pw.Text(company, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 3),
      pw.Text(
          'Payroll batch ${start == null ? '-' : DateFormat('d MMM yyyy').format(start)} - ${end == null ? '-' : DateFormat('d MMM yyyy').format(end)}  ·  Generated ${DateFormat('d MMM yyyy, h:mm a').format(DateTime.now())}',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
      pw.SizedBox(height: 14),
      pw.TableHelper.fromTextArray(
        headers: headers,
        data: data,
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 9),
        headerDecoration: pw.BoxDecoration(color: PdfColor.fromHex('#0f766e')),
        cellStyle: const pw.TextStyle(fontSize: 9),
        cellAlignments: {for (var i = 2; i <= 6; i++) i: pw.Alignment.centerRight},
        oddRowDecoration: pw.BoxDecoration(color: PdfColor.fromHex('#f8fafc')),
      ),
      pw.SizedBox(height: 10),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Total net: ${formatMoneyAscii(total)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
      ),
    ],
  ));
  await Printing.sharePdf(
    bytes: await doc.save(),
    filename: 'payroll-${start == null ? '' : ymd(start)}-to-${end == null ? '' : ymd(end)}.pdf',
  );
}

/// One label / amount line in a salary breakdown card.
class AmountLine extends StatelessWidget {
  final String label;
  final num? value;
  final MarketTone? tone;
  final bool bold;
  final bool count;
  const AmountLine(this.label, this.value, {super.key, this.tone, this.bold = false, this.count = false});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final color = tone == null ? p.text : p.tone(tone!).fg;
    final style = TextStyle(fontSize: bold ? 15 : 13.5, fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: color);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: p.label, fontWeight: bold ? FontWeight.w700 : FontWeight.w500))),
        count ? CountUp(value: value ?? 0, format: (v) => plain(v), style: style) : Text(plain(value ?? 0), style: style),
      ]),
    );
  }
}

/// Titled card section used in detail sheets.
class SectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final IconData? icon;
  const SectionCard({super.key, required this.title, this.subtitle, required this.child, this.icon});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return GlowCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          if (icon != null) ...[Icon(icon, size: 17, color: p.brand), const SizedBox(width: 8)],
          Expanded(child: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text))),
        ]),
        if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(subtitle!, style: TextStyle(fontSize: 11.5, color: p.label))),
        const SizedBox(height: 10),
        child,
      ]),
    );
  }
}

/// Small label-over-value cell for 2/3-column info grids.
class InfoCell extends StatelessWidget {
  final String label;
  final String value;
  const InfoCell(this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: p.label, fontWeight: FontWeight.w600)),
        const SizedBox(height: 3),
        Text(value.isEmpty ? '-' : value, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: p.text, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// Grid of [InfoCell]s, [columns] across.
class InfoGrid extends StatelessWidget {
  final List<Widget> cells;
  final int columns;
  const InfoGrid({super.key, required this.cells, this.columns = 2});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        const gap = 8.0;
        final w = (c.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(spacing: gap, runSpacing: gap, children: [for (final cell in cells) SizedBox(width: w, child: cell)]);
      });
}

/// Animated horizontal bar used by the payroll report cards.
class AnimatedBar extends StatelessWidget {
  final String label;
  final double value;
  final double max;
  final Color color;
  final String Function(num v) format;
  const AnimatedBar({super.key, required this.label, required this.value, required this.max, required this.color, required this.format});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final frac = max <= 0 ? 0.0 : (value / max).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(label, style: TextStyle(fontSize: 12.5, color: p.label))),
          Text(format(value), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.text)),
        ]),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Container(
            height: 8,
            color: p.surface,
            alignment: Alignment.centerLeft,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: frac),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (_, v, _) => FractionallySizedBox(
                widthFactor: v,
                child: Container(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6))),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
