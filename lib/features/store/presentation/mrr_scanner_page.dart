import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../core/network/socket_client.dart';
import 'widgets/store_ui.dart';

/// Turns the phone into a wireless barcode scanner for one specific MRR —
/// every detected code is relayed over the socket (`mrr:scan`) to
/// erp/desktop's StoreMrrsView.tsx, which runs it through the exact same
/// matching/logging path (`handleProgressScan`) a physical USB scanner
/// triggers. This screen never talks to `store_mrr_receive_logs` directly —
/// desktop stays the single source of truth for what actually got logged;
/// this is purely a remote input device riding the existing socket
/// infrastructure (see cloud's chat.gateway.ts mrr:scanner:join/leave/scan).
class MrrScannerPage extends StatefulWidget {
  final int mrrId;
  final String mrrNo;

  const MrrScannerPage({super.key, required this.mrrId, required this.mrrNo});

  @override
  State<MrrScannerPage> createState() => _MrrScannerPageState();
}

class _MrrScannerPageState extends State<MrrScannerPage> {
  final MobileScannerController _controller = MobileScannerController();

  String? _lastCode;
  DateTime? _lastScanAt;
  String? _lastSentLabel;

  /// Display-only history of codes relayed this session (newest first).
  final List<({String code, DateTime at})> _sent = [];

  @override
  void initState() {
    super.initState();
    AppSocket.instance?.emit('mrr:scanner:join', {'mrrId': widget.mrrId});
  }

  @override
  void dispose() {
    AppSocket.instance?.emit('mrr:scanner:leave', {'mrrId': widget.mrrId});
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;
    final code = barcodes.first.rawValue;
    if (code == null || code.isEmpty) return;

    final now = DateTime.now();
    // The camera keeps re-firing every frame while pointed at the same
    // barcode — ignore repeats of the same code within a short window
    // instead of relaying one scan per frame.
    if (_lastCode == code && _lastScanAt != null && now.difference(_lastScanAt!) < const Duration(seconds: 2)) {
      return;
    }
    _lastCode = code;
    _lastScanAt = now;

    AppSocket.instance?.emit('mrr:scan', {'mrrId': widget.mrrId, 'code': code});
    setState(() {
      _lastSentLabel = code;
      _sent.insert(0, (code: code, at: now));
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return MarketScaffold(
      title: 'Scan items',
      subtitle: 'Receipt ${widget.mrrNo} · sent to desktop',
      body: Column(children: [
        Expanded(
          flex: 3,
          child: ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: Colors.black, child: MobileScanner(controller: _controller, onDetect: _onDetect)),
                const _ScannerFrame(),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 18,
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: Container(
                        key: ValueKey(_lastSentLabel),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(20)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(_lastSentLabel != null ? Icons.check_circle : Icons.qr_code_scanner, size: 16, color: _lastSentLabel != null ? p.ok : Colors.white70),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              _lastSentLabel != null ? 'Sent $_lastSentLabel' : 'Point the camera at a barcode',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          flex: 2,
          child: Container(
            decoration: BoxDecoration(color: p.bg, border: Border(top: BorderSide(color: p.line))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: SectionHeader(
                  'Scanned items',
                  subtitle: 'Desktop matches each code against the receipt',
                  trailing: _sent.isEmpty ? null : StatusPill('${_sent.length} sent', tone: MarketTone.brand),
                ),
              ),
              Expanded(
                child: _sent.isEmpty
                    ? SingleChildScrollView(
                        child: MarketEmpty(
                          icon: Icons.qr_code_2_outlined,
                          title: 'Nothing scanned yet',
                          message: 'Codes you scan appear here as they are sent.',
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: _sent.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final s = _sent[i];
                          return FadeSlideIn(
                            key: ValueKey('${s.code}-${s.at.microsecondsSinceEpoch}'),
                            child: MarketCard(
                              padding: const EdgeInsets.all(12),
                              child: Row(children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(color: p.brandSoft, borderRadius: BorderRadius.circular(9)),
                                  child: Icon(Icons.qr_code_2, size: 19, color: p.brand),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(s.code, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.text)),
                                    const SizedBox(height: 2),
                                    Text(_time(s.at), style: TextStyle(fontSize: 11.5, color: p.label)),
                                  ]),
                                ),
                                StatusPill(i == 0 ? 'Just sent' : 'Sent', tone: i == 0 ? MarketTone.ok : MarketTone.neutral),
                              ]),
                            ),
                          );
                        },
                      ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

String _time(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}';

/// Viewfinder: dimmed surround, a clear window with brand corner brackets
/// and a short caption above it.
class _ScannerFrame extends StatelessWidget {
  const _ScannerFrame();

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return LayoutBuilder(builder: (context, c) {
      final w = (c.maxWidth * 0.72).clamp(200.0, 300.0);
      final h = (w * 0.62).clamp(120.0, c.maxHeight * 0.6);
      final window = Rect.fromCenter(center: Offset(c.maxWidth / 2, c.maxHeight / 2), width: w, height: h);
      return Stack(children: [
        Positioned.fill(child: CustomPaint(painter: _FramePainter(window: window, color: p.brand))),
        Positioned(
          left: 0,
          right: 0,
          top: window.top - 30,
          child: const Text(
            'Align the barcode inside the frame',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w500),
          ),
        ),
      ]);
    });
  }
}

class _FramePainter extends CustomPainter {
  final Rect window;
  final Color color;
  const _FramePainter({required this.window, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const radius = Radius.circular(14);
    final rrect = RRect.fromRectAndRadius(window, radius);
    final dim = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(rrect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(dim, Paint()..color = Colors.black.withValues(alpha: 0.45));

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const len = 26.0;
    final l = window.left, t = window.top, r = window.right, b = window.bottom;
    const k = 14.0; // matches the corner radius
    canvas.drawPath(
        Path()
          ..moveTo(l, t + len)
          ..lineTo(l, t + k)
          ..arcToPoint(Offset(l + k, t), radius: radius)
          ..lineTo(l + len, t),
        stroke);
    canvas.drawPath(
        Path()
          ..moveTo(r - len, t)
          ..lineTo(r - k, t)
          ..arcToPoint(Offset(r, t + k), radius: radius)
          ..lineTo(r, t + len),
        stroke);
    canvas.drawPath(
        Path()
          ..moveTo(r, b - len)
          ..lineTo(r, b - k)
          ..arcToPoint(Offset(r - k, b), radius: radius)
          ..lineTo(r - len, b),
        stroke);
    canvas.drawPath(
        Path()
          ..moveTo(l + len, b)
          ..lineTo(l + k, b)
          ..arcToPoint(Offset(l, b - k), radius: radius)
          ..lineTo(l, b - len),
        stroke);
    // Hairline guide across the middle of the window.
    canvas.drawLine(
      Offset(l + 18, window.center.dy),
      Offset(r - 18, window.center.dy),
      Paint()
        ..color = color.withValues(alpha: 0.7)
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_FramePainter old) => old.window != window || old.color != color;
}
