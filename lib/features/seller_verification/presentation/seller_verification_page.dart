import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../core/network/http_client.dart';
import '../../../core/theme/app_theme.dart';
import '../data/nid_parser.dart';
import '../data/seller_verification_service.dart';
import 'code_scanner_page.dart';

/// Verify the seller's store with their NID: scan the barcode on the back of
/// the card, confirm the details, photograph both sides and take a selfie.
/// An Aptigen admin reviews it; approval gives the store its verified badge.
class SellerVerificationPage extends StatefulWidget {
  const SellerVerificationPage({super.key});

  @override
  State<SellerVerificationPage> createState() => _SellerVerificationPageState();
}

enum _Step { status, details, photos, done }

class _SellerVerificationPageState extends State<SellerVerificationPage> {
  final _service = SellerVerificationService(ApiClient());
  final _picker = ImagePicker();

  final _nidCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  SellerVerificationStatus? _status;
  bool _loading = true;
  String? _error;
  _Step _step = _Step.status;

  String? _scannedRaw;
  Uint8List? _front;
  Uint8List? _back;
  Uint8List? _selfie;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nidCtrl.dispose();
    _nameCtrl.dispose();
    _dobCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await _service.status();
      if (!mounted) return;
      setState(() => _status = s);
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiException ? e.message : 'Could not load your verification status.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  /// Optional: the desktop "Verify with phone" QR — confirms both devices
  /// are working on the same store before the seller starts.
  Future<void> _scanDesktopCode() async {
    final raw = await Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => const CodeScannerPage(
        title: 'Scan code',
        hint: 'Point the camera at the QR code shown on your computer',
        formats: [BarcodeFormat.qrCode],
      ),
    ));
    if (raw == null || !mounted) return;
    final storeId = parseVerifyQr(raw);
    if (storeId == null) {
      _toast("That isn't an Aptigen verification code.");
      return;
    }
    if (storeId != _status?.storeId) {
      _toast('This code is for a different store — switch to that workplace in the app first.');
      return;
    }
    _toast('Linked to ${_status?.storeName ?? 'your store'}');
    await _scanNid();
  }

  Future<void> _scanNid() async {
    final raw = await Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => const CodeScannerPage(
        title: 'Scan your NID',
        hint: 'Turn the card over and fit the barcode on the back inside the frame',
        formats: [BarcodeFormat.pdf417, BarcodeFormat.qrCode, BarcodeFormat.code128],
      ),
    ));
    if (!mounted) return;
    if (raw != null) {
      final parsed = parseNidBarcode(raw);
      _scannedRaw = raw;
      if (parsed.nidNumber != null) _nidCtrl.text = parsed.nidNumber!;
      if (parsed.fullName != null) _nameCtrl.text = parsed.fullName!;
      if (parsed.dateOfBirth != null) _dobCtrl.text = parsed.dateOfBirth!;
      if (!parsed.hasAny) _toast("Couldn't read the details — please type them in.");
    }
    setState(() => _step = _Step.details);
  }

  Future<void> _pickDob() async {
    final initial = DateTime.tryParse(_dobCtrl.text) ?? DateTime(1990);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      _dobCtrl.text = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _capture(String which) async {
    final shot = await _picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: which == 'selfie' ? CameraDevice.front : CameraDevice.rear,
      imageQuality: 85,
      maxWidth: 2000,
    );
    if (shot == null) return;
    final bytes = await shot.readAsBytes();
    if (!mounted) return;
    setState(() {
      if (which == 'front') _front = bytes;
      if (which == 'back') _back = bytes;
      if (which == 'selfie') _selfie = bytes;
    });
  }

  Future<void> _submit() async {
    if (_front == null || _back == null || _selfie == null || _submitting) return;
    setState(() => _submitting = true);
    try {
      await _service.submit(
        nidNumber: _nidCtrl.text.replaceAll(RegExp(r'[\s-]'), ''),
        fullName: _nameCtrl.text.trim(),
        dateOfBirth: _dobCtrl.text.trim(),
        scannedData: _scannedRaw,
        front: _front!,
        back: _back!,
        selfie: _selfie!,
      );
      if (!mounted) return;
      setState(() => _step = _Step.done);
    } catch (e) {
      if (mounted) _toast(e is ApiException ? e.message : 'Upload failed — check your connection and try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: Text('Verify seller', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 17)),
        leading: _step == _Step.details || _step == _Step.photos
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _step = _step == _Step.photos ? _Step.details : _Step.status),
              )
            : null,
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _Message(
                    icon: Icons.wifi_off_rounded,
                    title: "Couldn't load",
                    body: _error!,
                    action: FilledButton(onPressed: _load, child: const Text('Try again')),
                  )
                : switch (_step) {
                    _Step.status => _statusView(isDark),
                    _Step.details => _detailsView(),
                    _Step.photos => _photosView(isDark),
                    _Step.done => _Message(
                        icon: Icons.verified_user_outlined,
                        color: AppColors.success,
                        title: 'Submitted for review',
                        body: 'The Aptigen team will check your NID — usually within one working day. You\'ll get a notification and an email when it\'s done.',
                        action: FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
                      ),
                  },
      ),
    );
  }

  Widget _statusView(bool isDark) {
    final s = _status;
    if (s == null || !s.hasProfile) {
      return const _Message(
        icon: Icons.storefront_outlined,
        title: 'No seller profile yet',
        body: 'Create your creator profile in Aptigen ERP (Sales → Online → Profile) first, then verify it here.',
      );
    }
    if (s.isVerified) {
      return _Message(
        icon: Icons.verified_rounded,
        color: AppColors.brand,
        title: '${s.storeName ?? 'Your store'} is verified',
        body: 'Buyers see the verified badge on your storefront and listings.',
      );
    }
    if (s.pending) {
      return _Message(
        icon: Icons.hourglass_top_rounded,
        color: AppColors.info,
        title: 'Under review',
        body: 'NID ${s.maskedNid ?? ''} for ${s.fullName ?? ''} is being checked by the Aptigen team.',
        action: OutlinedButton(onPressed: _load, child: const Text('Refresh')),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (s.rejected)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: Text(
              'Your last request was not approved: ${s.rejectionReason ?? 'no reason given'}. Please scan again.',
              style: GoogleFonts.poppins(fontSize: 13, color: AppColors.error),
            ),
          ),
        Text('Get the verified seller badge', style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(
          'Verify ${s.storeName ?? 'your store'} with your national ID card. It takes about two minutes.',
          style: GoogleFonts.poppins(fontSize: 14, color: isDark ? AppColors.slate400 : AppColors.slate600),
        ),
        const SizedBox(height: 20),
        for (final (icon, text) in [
          (Icons.qr_code_scanner_rounded, 'Scan the barcode on the back of your NID'),
          (Icons.edit_note_rounded, 'Check your NID number, name and date of birth'),
          (Icons.photo_camera_outlined, 'Take photos of the front and back, and a selfie'),
          (Icons.verified_user_outlined, 'The Aptigen team reviews it and you get the badge'),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: AppColors.brand.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, size: 19, color: AppColors.brand),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(text, style: GoogleFonts.poppins(fontSize: 14))),
              ],
            ),
          ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _scanNid,
          icon: const Icon(Icons.badge_outlined),
          label: const Text('Scan my NID'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _scanDesktopCode,
          icon: const Icon(Icons.qr_code_2_rounded),
          label: const Text('Scan code from computer'),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
        const SizedBox(height: 16),
        Text(
          'Your NID photos are stored privately and only seen by the Aptigen verification team.',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(fontSize: 12, color: AppColors.slate400),
        ),
      ],
    );
  }

  Widget _detailsView() {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Check your details', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Make sure they match your NID exactly.', style: GoogleFonts.poppins(fontSize: 13, color: AppColors.slate400)),
          const SizedBox(height: 18),
          TextFormField(
            controller: _nidCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'NID number', hintText: '10, 13 or 17 digits'),
            validator: (v) {
              final digits = (v ?? '').replaceAll(RegExp(r'[\s-]'), '');
              return RegExp(r'^(\d{10}|\d{13}|\d{17})$').hasMatch(digits) ? null : 'Enter a valid NID number (10, 13 or 17 digits)';
            },
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _nameCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Full name (as on the NID)'),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Enter your name' : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _dobCtrl,
            readOnly: true,
            onTap: _pickDob,
            decoration: const InputDecoration(labelText: 'Date of birth', suffixIcon: Icon(Icons.calendar_today_outlined)),
          ),
          const SizedBox(height: 10),
          TextButton.icon(onPressed: _scanNid, icon: const Icon(Icons.qr_code_scanner_rounded), label: const Text('Scan the barcode again')),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: () {
              if (_formKey.currentState?.validate() ?? false) setState(() => _step = _Step.photos);
            },
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  Widget _photosView(bool isDark) {
    final ready = _front != null && _back != null && _selfie != null;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Take three photos', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(
          'Use good light, keep the whole card in the frame and make sure the text is sharp.',
          style: GoogleFonts.poppins(fontSize: 13, color: AppColors.slate400),
        ),
        const SizedBox(height: 18),
        _PhotoTile(label: 'NID front', hint: 'The side with your photo', bytes: _front, isDark: isDark, onTap: () => _capture('front')),
        _PhotoTile(label: 'NID back', hint: 'The side with the barcode', bytes: _back, isDark: isDark, onTap: () => _capture('back')),
        _PhotoTile(label: 'Selfie', hint: 'Your face, clearly visible', bytes: _selfie, isDark: isDark, onTap: () => _capture('selfie')),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: ready && !_submitting ? _submit : null,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          child: _submitting
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Submit for verification'),
        ),
      ],
    );
  }
}

class _PhotoTile extends StatelessWidget {
  final String label;
  final String hint;
  final Uint8List? bytes;
  final bool isDark;
  final VoidCallback onTap;

  const _PhotoTile({required this.label, required this.hint, required this.bytes, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final done = bytes != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: isDark ? AppColors.slate900 : AppColors.slate50,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 84,
                    height: 60,
                    child: done
                        ? Image.memory(bytes!, fit: BoxFit.cover)
                        : Container(color: AppColors.brand.withValues(alpha: 0.1), child: const Icon(Icons.photo_camera_outlined, color: AppColors.brand)),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600)),
                      Text(done ? 'Tap to retake' : hint, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.slate400)),
                    ],
                  ),
                ),
                Icon(done ? Icons.check_circle_rounded : Icons.chevron_right_rounded, color: done ? AppColors.success : AppColors.slate400),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Color color;
  final Widget? action;

  const _Message({required this.icon, required this.title, required this.body, this.color = AppColors.slate400, this.action});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(icon, size: 36, color: color),
            ),
            const SizedBox(height: 18),
            Text(title, textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(body, textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 14, height: 1.45, color: AppColors.slate400)),
            if (action != null) ...[const SizedBox(height: 22), action!],
          ],
        ),
      ),
    );
  }
}
