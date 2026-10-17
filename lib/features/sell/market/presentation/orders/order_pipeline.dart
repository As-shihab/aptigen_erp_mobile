import 'package:flutter/material.dart';
import '../widgets/market_ui.dart';

/// Horizontal fulfilment pipeline: placed → accepted → packed → delivered.
/// The connecting line fills to the current step (animating on status
/// changes) and each node lights up as the fill passes it. Cancelled
/// orders show the track muted with the reached steps in the error tone.
class OrderPipeline extends StatelessWidget {
  final String status;
  const OrderPipeline({super.key, required this.status});

  static const _steps = [
    (label: 'Placed', icon: Icons.receipt_long_outlined),
    (label: 'Accepted', icon: Icons.thumb_up_alt_outlined),
    (label: 'Packed', icon: Icons.inventory_2_outlined),
    (label: 'Delivered', icon: Icons.local_shipping_outlined),
  ];

  static int stepIndex(String s) => switch (s) {
        'pending' => 0,
        'paid' => 1,
        'packaged' => 2,
        'delivered' => 3,
        _ => 0,
      };

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final cancelled = status == 'cancelled';
    final idx = stepIndex(status);
    final last = _steps.length - 1;
    final done = status == 'delivered';
    final accent = cancelled ? p.error : (done ? p.ok : p.brand);
    const node = 30.0;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: cancelled ? 0 : idx / last),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) => LayoutBuilder(builder: (context, c) {
        final seg = c.maxWidth / _steps.length;
        final track = c.maxWidth - seg;
        return Stack(children: [
          Positioned(
            top: node / 2 - 1.5,
            left: seg / 2,
            right: seg / 2,
            child: Container(height: 3, decoration: BoxDecoration(color: p.line, borderRadius: BorderRadius.circular(2))),
          ),
          Positioned(
            top: node / 2 - 1.5,
            left: seg / 2,
            width: track * t,
            child: Container(height: 3, decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(2))),
          ),
          Row(children: [
            for (var i = 0; i < _steps.length; i++)
              Expanded(child: _node(p, i, t, idx, last, cancelled, accent, node)),
          ]),
        ]);
      }),
    );
  }

  Widget _node(MarketPalette p, int i, double t, int idx, int last, bool cancelled, Color accent, double size) {
    final reached = cancelled ? i == 0 : t >= i / last - 0.001;
    final current = !cancelled && i == idx;
    final complete = reached && !current;
    final step = _steps[i];
    final icon = cancelled && i == 0 ? Icons.close : (complete ? Icons.check : step.icon);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: reached ? accent : p.card,
          border: Border.all(color: reached ? accent : p.line, width: 2),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Icon(icon, key: ValueKey(icon), size: 15, color: reached ? Colors.white : p.label),
        ),
      ),
      const SizedBox(height: 6),
      AnimatedDefaultTextStyle(
        duration: const Duration(milliseconds: 220),
        style: TextStyle(
          fontSize: 11,
          fontWeight: current ? FontWeight.w700 : FontWeight.w500,
          color: current ? p.text : (reached ? p.text : p.label),
        ),
        child: Text(cancelled && i == 0 ? 'Cancelled' : step.label, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
      ),
    ]);
  }
}
