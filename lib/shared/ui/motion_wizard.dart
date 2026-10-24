import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'motion_kit.dart';

// Multi-step form wizard shared by every large form (store documents,
// products, listings, employees, ...). One step at a time with an animated
// numbered stepper, directional slide between steps, per-step validation,
// a sticky back / next / submit footer and a discard guard. Use
// [MotionWizardPage] for full-screen forms and [MotionWizardSheet] inside
// a bottom sheet.

class WizardStep {
  final String title;
  final IconData? icon;

  /// Short line under the step heading.
  final String? caption;
  final WidgetBuilder builder;

  /// Return an error message to block moving on, or null when valid.
  final String? Function()? validate;
  const WizardStep({required this.title, required this.builder, this.icon, this.caption, this.validate});
}

/// Animated numbered stepper: filled progress line, check marks for done
/// steps, a soft glow on the current one. Tap a done step to jump back.
class StepHeader extends StatelessWidget {
  final List<String> steps;
  final int step;
  final ValueChanged<int>? onStep;
  final bool onDark;
  const StepHeader({super.key, required this.steps, required this.step, this.onStep, this.onDark = false});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final active = onDark ? Colors.white : p.brand;
    final track = onDark ? Colors.white.withValues(alpha: 0.28) : p.line;
    final idle = onDark ? Colors.white.withValues(alpha: 0.7) : p.label;
    final current = onDark ? Colors.white : p.text;
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
            child: Container(height: 3, decoration: BoxDecoration(color: track, borderRadius: BorderRadius.circular(2))),
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
                decoration: BoxDecoration(color: active, borderRadius: BorderRadius.circular(2)),
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
                          color: i < step ? active : (onDark ? Colors.white.withValues(alpha: 0.12) : p.card),
                          border: Border.all(color: i <= step ? active : track, width: 2),
                
                        ),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
                          child: i < step
                              ? Icon(Icons.check_rounded, key: const ValueKey('done'), size: 17, color: onDark ? p.brand : Colors.white)
                              : Text('${i + 1}',
                                  key: ValueKey('n$i'),
                                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: i == step ? active : idle)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(steps[i],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, fontWeight: i == step ? FontWeight.w700 : FontWeight.w500, color: i == step ? current : idle)),
                  ]),
                ),
              ),
          ]),
        ]),
      );
    });
  }
}

/// Read-only summary tile for review steps.
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
        decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(10)),
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

/// Shared step state + navigation for page and sheet variants.
mixin _WizardLogic<T extends StatefulWidget> on State<T> {
  int step = 0;
  int direction = 1;
  bool busy = false;

  List<WizardStep> get steps;
  Future<bool> Function() get submit;

  bool get isLast => step == steps.length - 1;

  bool _validate(int i) {
    final err = steps[i].validate?.call();
    if (err != null) {
      HapticFeedback.mediumImpact();
      marketToast(context, err, error: true);
      return false;
    }
    return true;
  }

  void goTo(int i) {
    if (i == step || busy) return;
    if (i > step) {
      for (var k = step; k < i; k++) {
        if (!_validate(k)) {
          setState(() {
            direction = k >= step ? 1 : -1;
            step = k;
          });
          return;
        }
      }
    }
    FocusScope.of(context).unfocus();
    setState(() {
      direction = i > step ? 1 : -1;
      step = i;
    });
  }

  Future<void> next() async {
    if (busy || !_validate(step)) return;
    if (!isLast) {
      HapticFeedback.selectionClick();
      goTo(step + 1);
      return;
    }
    for (var k = 0; k < steps.length; k++) {
      if (!_validate(k)) {
        goTo(k);
        return;
      }
    }
    FocusScope.of(context).unfocus();
    setState(() => busy = true);
    var ok = false;
    try {
      ok = await submit();
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (ok) HapticFeedback.lightImpact();
  }

  Widget body({required EdgeInsets padding}) {
    final p = MarketPalette.of(context);
    final s = steps[step];
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (current, previous) => Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
      transitionBuilder: (child, anim) {
        final inbound = child.key == ValueKey(step);
        final dx = (inbound ? 0.14 : -0.14) * direction;
        return FadeTransition(
          opacity: anim,
          child: SlideTransition(position: Tween(begin: Offset(dx, 0), end: Offset.zero).animate(anim), child: child),
        );
      },
      child: KeyedSubtree(
        key: ValueKey(step),
        child: SingleChildScrollView(
          padding: padding,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            FadeSlideIn(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(children: [
                  if (s.icon != null) ...[AccentIcon(s.icon!, size: 36), const SizedBox(width: 12)],
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(s.title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: p.text)),
                      if (s.caption != null) Text(s.caption!, style: TextStyle(fontSize: 12.5, color: p.label)),
                    ]),
                  ),
                ]),
              ),
            ),
            FadeSlideIn(index: 1, child: Builder(builder: s.builder)),
          ]),
        ),
      ),
    );
  }

  Widget footer({required String submitLabel, required VoidCallback onCancel}) {
    final p = MarketPalette.of(context);
    return Container(
      decoration: BoxDecoration(color: p.card, border: Border(top: BorderSide(color: p.line))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Row(children: [
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                onPressed: busy ? null : (step == 0 ? onCancel : () => goTo(step - 1)),
                icon: Icon(step == 0 ? Icons.close_rounded : Icons.arrow_back_rounded, size: 18),
                label: Text(step == 0 ? 'Cancel' : 'Back'),
                style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), side: BorderSide(color: p.line)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GradientButton(
                label: isLast ? submitLabel : 'Next',
                icon: isLast ? Icons.check_rounded : Icons.arrow_forward_rounded,
                busy: busy,
                accent: isLast ? Accent.emerald : Accent.ocean,
                onTap: next,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Full-screen wizard with a gradient header holding the stepper.
/// [onSubmit] returns true when saved (the caller pops / navigates).
class MotionWizardPage extends StatefulWidget {
  final String title;
  final String? subtitle;
  final Accent accent;
  final List<WizardStep> steps;
  final String submitLabel;
  final Future<bool> Function() onSubmit;

  /// Ask before leaving when the user has typed something.
  final bool Function()? isDirty;
  final List<Widget>? actions;
  final int initialStep;
  const MotionWizardPage({
    super.key,
    required this.title,
    this.subtitle,
    this.accent = Accent.ocean,
    required this.steps,
    this.submitLabel = 'Save',
    required this.onSubmit,
    this.isDirty,
    this.actions,
    this.initialStep = 0,
  });

  @override
  State<MotionWizardPage> createState() => _MotionWizardPageState();
}

class _MotionWizardPageState extends State<MotionWizardPage> with _WizardLogic<MotionWizardPage> {
  @override
  List<WizardStep> get steps => widget.steps;
  @override
  Future<bool> Function() get submit => widget.onSubmit;

  @override
  void initState() {
    super.initState();
    step = widget.initialStep.clamp(0, widget.steps.length - 1);
  }

  Future<void> _leave() async {
    if (widget.isDirty?.call() == true) {
      final ok = await confirmMarket(context, title: 'Discard changes?', message: 'What you entered will be lost.', confirm: 'Discard');
      if (!ok || !mounted) return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final top = MediaQuery.of(context).padding.top;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || busy) return;
        if (step > 0) {
          goTo(step - 1);
        } else {
          _leave();
        }
      },
      child: Scaffold(
        backgroundColor: p.bg,
        body: Column(children: [
          Container(
            decoration: BoxDecoration(color: p.card, border: Border(bottom: BorderSide(color: p.line))),
            padding: EdgeInsets.fromLTRB(4, top + 4, 8, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                IconButton(onPressed: busy ? null : _leave, icon: Icon(Icons.close_rounded, color: p.text)),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.text, fontSize: 16, fontWeight: FontWeight.w700)),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: Text(
                        widget.subtitle ?? 'Step ${step + 1} of ${steps.length} · ${steps[step].title}',
                        key: ValueKey(step),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.label, fontSize: 11.5),
                      ),
                    ),
                  ]),
                ),
                ...?widget.actions,
              ]),
              if (steps.length > 1)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 0),
                  child: StepHeader(steps: [for (final s in steps) s.title], step: step, onStep: goTo),
                ),
            ]),
          ),
          Expanded(child: body(padding: const EdgeInsets.fromLTRB(18, 20, 18, 24))),
          footer(submitLabel: widget.submitLabel, onCancel: _leave),
        ]),
      ),
    );
  }
}

/// Bottom-sheet wizard (for medium forms opened from a list).
class MotionWizardSheet extends StatefulWidget {
  final String title;
  final String? subtitle;
  final List<WizardStep> steps;
  final String submitLabel;
  final Future<bool> Function() onSubmit;
  const MotionWizardSheet({super.key, required this.title, this.subtitle, required this.steps, this.submitLabel = 'Save', required this.onSubmit});

  @override
  State<MotionWizardSheet> createState() => _MotionWizardSheetState();
}

class _MotionWizardSheetState extends State<MotionWizardSheet> with _WizardLogic<MotionWizardSheet> {
  @override
  List<WizardStep> get steps => widget.steps;
  @override
  Future<bool> Function() get submit => widget.onSubmit;

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.9,
      child: Column(children: [
        const SheetGrabber(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.text)),
                Text(widget.subtitle ?? 'Step ${step + 1} of ${steps.length} · ${steps[step].title}', style: TextStyle(fontSize: 12.5, color: p.label)),
              ]),
            ),
            IconButton(onPressed: busy ? null : () => Navigator.pop(context), icon: Icon(Icons.close_rounded, color: p.label)),
          ]),
        ),
        if (steps.length > 1) Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 6), child: StepHeader(steps: [for (final s in steps) s.title], step: step, onStep: goTo)),
        Divider(height: 1, color: p.line),
        Expanded(child: body(padding: const EdgeInsets.fromLTRB(20, 16, 20, 16))),
        footer(submitLabel: widget.submitLabel, onCancel: () => Navigator.pop(context)),
      ]),
    );
  }
}
