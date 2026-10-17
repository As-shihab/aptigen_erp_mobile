import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import '../../../sell/market/presentation/banners/form_kit.dart' show FieldBlock, MarketTextField;
import '../widgets/barcode_print_sheet.dart';
import '../widgets/store_ui.dart';

/// Barcode / QR lab — an ad-hoc code generator unrelated to any saved
/// packaging record, for quickly previewing and printing a one-off label
/// (mirrors desktop's `StoreProductPackagings.tsx` "Lab" dialog). CODE128
/// only, same as every real packaging/product barcode in this app.
class BarcodeLabPage extends StatefulWidget {
  const BarcodeLabPage({super.key});

  @override
  State<BarcodeLabPage> createState() => _BarcodeLabPageState();
}

class _BarcodeLabPageState extends State<BarcodeLabPage> {
  final _codeController = TextEditingController(text: '123456789012');
  final _titleController = TextEditingController();
  final _subtitleController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    _titleController.dispose();
    _subtitleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    final code = _codeController.text.trim();
    var section = 0;
    Widget block(Widget child) => FadeSlideIn(index: section++, child: child);

    return MarketScaffold(
      title: 'Barcode lab',
      subtitle: 'Preview and print a one-off CODE128 label',
      bottom: _printBar(p, code),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            block(const SectionHeader('Preview')),
            block(MarketCard(
              padding: const EdgeInsets.all(14),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                // The label itself stays black on white in every theme.
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.line)),
                child: Column(
                  children: [
                    if (_titleController.text.trim().isNotEmpty)
                      Text(_titleController.text.trim(), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.black87)),
                    SizedBox(
                      height: 110,
                      child: code.isEmpty
                          ? const Center(child: Icon(Icons.qr_code_2_outlined, color: Colors.black26, size: 40))
                          : BarcodeWidget(
                              barcode: Barcode.code128(),
                              data: code,
                              drawText: true,
                              style: const TextStyle(fontSize: 12, color: Colors.black87),
                              errorBuilder: (context, error) => const Center(child: Text('Invalid barcode value', style: TextStyle(color: Colors.black45))),
                            ),
                    ),
                    if (_subtitleController.text.trim().isNotEmpty)
                      Text(_subtitleController.text.trim(), style: const TextStyle(fontSize: 11, color: Colors.black54)),
                  ],
                ),
              ),
            )),
            block(const SectionHeader('Label content')),
            block(MarketCard(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                FieldBlock(
                  label: 'Barcode value',
                  required: true,
                  help: 'Any text or number, encoded as CODE128',
                  child: MarketTextField(
                    controller: _codeController,
                    hint: 'e.g. 123456789012',
                    icon: Icons.qr_code_2_outlined,
                    capitalization: TextCapitalization.none,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                FieldBlock(
                  label: 'Label title',
                  help: 'Optional, printed above the barcode',
                  child: MarketTextField(controller: _titleController, hint: 'Title', onChanged: (_) => setState(() {})),
                ),
                FieldBlock(
                  label: 'Label subtitle',
                  help: 'Optional, printed below the barcode',
                  child: MarketTextField(controller: _subtitleController, hint: 'Subtitle', onChanged: (_) => setState(() {})),
                ),
              ]),
            )),
          ],
        ),
      ),
    );
  }

  Widget _printBar(MarketPalette p, String code) => Container(
        decoration: BoxDecoration(color: p.card, border: Border(top: BorderSide(color: p.line))),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                onPressed: code.isEmpty
                    ? null
                    : () => showBarcodePrintSheet(
                          context,
                          code: code,
                          title: _titleController.text.trim().isEmpty ? null : _titleController.text.trim(),
                          infoLines: _subtitleController.text.trim().isEmpty ? const {} : {'Note': _subtitleController.text.trim()},
                        ),
                icon: const Icon(Icons.print_outlined, size: 20),
                label: const Text('Print label'),
              ),
            ),
          ),
        ),
      );
}
