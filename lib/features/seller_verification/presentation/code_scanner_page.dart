import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Full-screen camera that returns the first barcode it reads — used for the
/// NID barcode (PDF417 on the back of the card) and the desktop's QR code.
class CodeScannerPage extends StatefulWidget {
  final String title;
  final String hint;
  final List<BarcodeFormat> formats;

  const CodeScannerPage({
    super.key,
    required this.title,
    required this.hint,
    this.formats = const [BarcodeFormat.all],
  });

  @override
  State<CodeScannerPage> createState() => _CodeScannerPageState();
}

class _CodeScannerPageState extends State<CodeScannerPage> {
  late final MobileScannerController _controller = MobileScannerController(formats: widget.formats);
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    final code = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstWhere((v) => v.isNotEmpty, orElse: () => '');
    if (code.isEmpty) return;
    _done = true;
    Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Torch',
            icon: const Icon(Icons.flash_on_rounded),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Center(
            child: Container(
              width: MediaQuery.sizeOf(context).width * 0.82,
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 48,
            child: Text(
              widget.hint,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
