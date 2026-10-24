import 'package:flutter/material.dart';
import '../../../../core/network/http_client.dart';
import '../../../../shared/ui/motion_kit.dart';
import '../../data/approval_service.dart';

// Shared pieces for the purchase order / requisition / approvals pages:
// approval chain timeline + chips, the approve / reject notes sheet, the
// receipt progress bar and the list filter sheet.

({IconData icon, MarketTone tone}) _stepLook(String status) => switch (status) {
      'APPROVED' => (icon: Icons.check_rounded, tone: MarketTone.ok),
      'REJECTED' => (icon: Icons.close_rounded, tone: MarketTone.error),
      'SKIPPED' => (icon: Icons.remove_rounded, tone: MarketTone.neutral),
      _ => (icon: Icons.schedule_rounded, tone: MarketTone.neutral),
    };

(Color, Color) toneColors(MarketPalette p, MarketTone t) => switch (t) {
      MarketTone.ok => (p.ok, p.okBg),
      MarketTone.warn => (p.warn, p.warnBg),
      MarketTone.error => (p.error, p.errorBg),
      MarketTone.info => (p.info, p.infoBg),
      MarketTone.brand => (p.brand, p.brandSoft),
      MarketTone.neutral => (p.neutral, p.neutralBg),
    };

/// Compact chain progress: one chip per step, the current one outlined.
class ApprovalChips extends StatelessWidget {
  final List<ApprovalStep> steps;
  final int currentSerial;
  const ApprovalChips({super.key, required this.steps, required this.currentSerial});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Wrap(spacing: 6, runSpacing: 6, children: [
      for (final s in steps)
        Builder(builder: (_) {
          final look = _stepLook(s.status);
          final (fg, bg) = toneColors(p, look.tone);
          final current = s.serial == currentSerial && s.status == 'PENDING';
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: s.status == 'PENDING' ? p.surface : bg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: current ? p.brand : Colors.transparent),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(look.icon, size: 12, color: s.status == 'PENDING' ? p.label : fg),
              const SizedBox(width: 4),
              Text('${s.serial}. ${s.label}${s.isRequired ? '' : ' (optional)'}',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: s.status == 'PENDING' ? p.label : fg)),
            ]),
          );
        }),
    ]);
  }
}

/// Vertical approval chain: who acted, when, and their note.
class ApprovalTimeline extends StatelessWidget {
  final List<ApprovalStep> steps;
  final int currentSerial;
  final String docStatus;
  const ApprovalTimeline({super.key, required this.steps, required this.currentSerial, required this.docStatus});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Column(children: [
      for (var i = 0; i < steps.length; i++)
        FadeSlideIn(
          index: i,
          offsetY: 8,
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                width: 30,
                child: Column(children: [
                  Builder(builder: (_) {
                    final s = steps[i];
                    final look = _stepLook(s.status);
                    final (fg, bg) = toneColors(p, look.tone);
                    final current = s.serial == currentSerial && s.status == 'PENDING' && docStatus == 'PENDING';
                    return Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: s.status == 'PENDING' ? (current ? p.brandSoft : p.surface) : bg,
                        border: Border.all(color: current ? p.brand : (s.status == 'PENDING' ? p.line : fg.withValues(alpha: 0.4))),
                      ),
                      child: Icon(look.icon, size: 14, color: s.status == 'PENDING' ? (current ? p.brand : p.label) : fg),
                    );
                  }),
                  if (i < steps.length - 1) Expanded(child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 2), color: p.line)),
                ]),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(bottom: i < steps.length - 1 ? 14 : 0, top: 3),
                  child: _StepBody(step: steps[i], current: steps[i].serial == currentSerial && steps[i].status == 'PENDING' && docStatus == 'PENDING'),
                ),
              ),
            ]),
          ),
        ),
    ]);
  }
}

class _StepBody extends StatelessWidget {
  final ApprovalStep step;
  final bool current;
  const _StepBody({required this.step, required this.current});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final s = step;
    final statusText = switch (s.status) {
      'APPROVED' => 'Approved',
      'REJECTED' => 'Rejected',
      'SKIPPED' => 'Skipped',
      _ => current ? 'Waiting for decision' : 'Not reached yet',
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: Text('${s.serial}. ${s.label}', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.text)),
        ),
        if (!s.isRequired) Text('Optional', style: TextStyle(fontSize: 11, color: p.label)),
      ]),
      const SizedBox(height: 2),
      Text(
        [statusText, if (s.actorName != null) 'by ${s.actorName}', if (s.actedAt != null) fmtDateTime(s.actedAt)].join(' · '),
        style: TextStyle(fontSize: 11.5, color: current ? p.brand : p.label),
      ),
      if (s.notes != null) ...[
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(8)),
          child: Text(s.notes!, style: TextStyle(fontSize: 12.5, color: p.text, height: 1.3)),
        ),
      ],
    ]);
  }
}

/// Thin receipt progress bar (green when complete, orange when partial).
class ReceiptBar extends StatelessWidget {
  final int pct;
  final double height;
  const ReceiptBar({super.key, required this.pct, this.height = 6});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final color = pct >= 100 ? p.ok : (pct > 0 ? p.warn : p.neutral);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Stack(children: [
          Container(color: p.surface),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: (pct.clamp(0, 100)) / 100),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (_, v, _) => FractionallySizedBox(widthFactor: v, child: Container(color: color)),
          ),
        ]),
      ),
    );
  }
}

/// Approve / reject sheet with a note. Returns the note ('' when left
/// empty) or null when dismissed. A note is required to reject a required step.
Future<String?> showDecisionSheet(BuildContext context, {required bool approve, required bool stepRequired, required String docNo}) {
  return showMotionSheet<String>(context, (_) => _DecisionSheet(approve: approve, stepRequired: stepRequired, docNo: docNo));
}

class _DecisionSheet extends StatefulWidget {
  final bool approve;
  final bool stepRequired;
  final String docNo;
  const _DecisionSheet({required this.approve, required this.stepRequired, required this.docNo});

  @override
  State<_DecisionSheet> createState() => _DecisionSheetState();
}

class _DecisionSheetState extends State<_DecisionSheet> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final note = _ctrl.text.trim();
    if (!widget.approve && widget.stepRequired && note.isEmpty) {
      marketToast(context, 'Add a note explaining why ${widget.docNo} is rejected', error: true);
      return;
    }
    Navigator.pop(context, note);
  }

  @override
  Widget build(BuildContext context) {
    final rejectLabel = widget.stepRequired ? 'Reject' : 'Skip step';
    return FormSheet(
      title: widget.approve ? 'Approve ${widget.docNo}' : '$rejectLabel ${widget.docNo}',
      subtitle: widget.approve
          ? 'Moves it to the next approver, or approves it on the last step.'
          : (widget.stepRequired ? 'This step is required, rejecting ends the chain.' : 'This step is optional, it is skipped and the chain moves on.'),
      submitLabel: widget.approve ? 'Approve' : rejectLabel,
      onSubmit: _submit,
      children: [
        FormLabel(
          label: widget.approve || !widget.stepRequired ? 'Note (optional)' : 'Note',
          required: !widget.approve && widget.stepRequired,
          child: TextField(controller: _ctrl, minLines: 3, maxLines: 6, autofocus: true, decoration: motionInput(context, hint: 'Add a note for the record')),
        ),
      ],
    );
  }
}

/// Runs one approval decision end to end (sheet → API → toast). Returns
/// true when the document changed and the caller should reload.
Future<bool> runApprovalDecision(
  BuildContext context, {
  required ApprovalDoc doc,
  required int docId,
  required String docNo,
  required int currentSerial,
  required List<ApprovalStep> steps,
  required bool approve,
  required CurrentApprover me,
}) async {
  final step = currentStep(steps, currentSerial);
  if (step == null) return false;
  final note = await showDecisionSheet(context, approve: approve, stepRequired: step.isRequired, docNo: docNo);
  if (note == null || !context.mounted) return false;
  try {
    final outcome = await ApprovalService(ApiClient()).act(
      doc,
      docId: docId,
      currentSerial: currentSerial,
      steps: steps,
      approve: approve,
      notes: note.isEmpty ? null : note,
      me: me,
    );
    if (context.mounted) {
      marketToast(
        context,
        switch (outcome) {
          ApprovalOutcome.approved => doc == ApprovalDoc.spr ? '$docNo approved, purchasing can now raise an RFQ' : '$docNo fully approved',
          ApprovalOutcome.rejected => '$docNo rejected',
          ApprovalOutcome.advanced => '$docNo moved to the next approver',
        },
      );
    }
    return true;
  } catch (e) {
    if (context.mounted) marketToast(context, errorMessage(e, 'Approval action failed'), error: true);
    return false;
  }
}

/// Filter sheet: optional party picker plus a date range.
class ListFilter {
  final Object? partyId;
  final DateTime? from;
  final DateTime? to;
  const ListFilter({this.partyId, this.from, this.to});
  bool get isEmpty => partyId == null && from == null && to == null;

  bool matchesDate(DateTime? d) {
    if (from == null && to == null) return true;
    if (d == null) return false;
    final day = DateTime(d.toLocal().year, d.toLocal().month, d.toLocal().day);
    if (from != null && day.isBefore(DateTime(from!.year, from!.month, from!.day))) return false;
    if (to != null && day.isAfter(DateTime(to!.year, to!.month, to!.day))) return false;
    return true;
  }
}

Future<ListFilter?> showListFilterSheet(
  BuildContext context, {
  required ListFilter current,
  String? partyLabel,
  List<PickOption> partyOptions = const [],
  String dateLabel = 'Date',
}) {
  return showMotionSheet<ListFilter>(context, (_) => _FilterSheet(current: current, partyLabel: partyLabel, partyOptions: partyOptions, dateLabel: dateLabel));
}

class _FilterSheet extends StatefulWidget {
  final ListFilter current;
  final String? partyLabel;
  final List<PickOption> partyOptions;
  final String dateLabel;
  const _FilterSheet({required this.current, this.partyLabel, required this.partyOptions, required this.dateLabel});

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late Object? _party = widget.current.partyId;
  late DateTime? _from = widget.current.from;
  late DateTime? _to = widget.current.to;

  @override
  Widget build(BuildContext context) {
    return FormSheet(
      title: 'Filter',
      submitLabel: 'Apply',
      extraAction: TextButton(onPressed: () => Navigator.pop(context, const ListFilter()), child: const Text('Clear')),
      onSubmit: () {
        if (_from != null && _to != null && _to!.isBefore(_from!)) {
          marketToast(context, 'The end date is before the start date', error: true);
          return;
        }
        Navigator.pop(context, ListFilter(partyId: _party, from: _from, to: _to));
      },
      children: [
        if (widget.partyLabel != null)
          FormLabel(
            label: widget.partyLabel!,
            child: PickerField(value: _party, options: widget.partyOptions, hint: 'Any ${widget.partyLabel!.toLowerCase()}', icon: Icons.storefront_outlined, onChanged: (v) => setState(() => _party = v)),
          ),
        FormLabel(label: '${widget.dateLabel} from', child: DatePickField(value: _from, onChanged: (d) => setState(() => _from = d))),
        FormLabel(label: '${widget.dateLabel} to', child: DatePickField(value: _to, onChanged: (d) => setState(() => _to = d))),
      ],
    );
  }
}

/// Small label / value block for detail info grids.
class InfoCell extends StatelessWidget {
  final String label;
  final String value;
  const InfoCell(this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 11.5, color: p.label)),
      const SizedBox(height: 2),
      Text(value.isEmpty ? '—' : value, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.text)),
    ]);
  }
}

/// Two-column grid of [InfoCell]s.
Widget infoGrid(List<(String, String)> cells) => LayoutBuilder(
      builder: (_, c) => Wrap(runSpacing: 12, children: [
        for (final cell in cells) SizedBox(width: c.maxWidth / 2, child: Padding(padding: const EdgeInsets.only(right: 8), child: InfoCell(cell.$1, cell.$2))),
      ]),
    );

/// Sticky bottom action bar for detail pages (secondary + primary).
class DetailActionBar extends StatelessWidget {
  final List<Widget> children;
  const DetailActionBar({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Container(
      decoration: BoxDecoration(color: p.card, border: Border(top: BorderSide(color: p.line))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Row(children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: children[i]),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Outlined secondary button sized to match [GradientButton].
class OutlineAction extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool destructive;
  const OutlineAction({super.key, required this.label, this.icon, this.onTap, this.destructive = false});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final c = destructive ? p.error : p.brand;
    return SizedBox(
      height: 48,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon ?? Icons.chevron_right_rounded, size: 18),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        style: OutlinedButton.styleFrom(
          foregroundColor: c,
          side: BorderSide(color: destructive ? p.error.withValues(alpha: 0.5) : p.line),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }
}
