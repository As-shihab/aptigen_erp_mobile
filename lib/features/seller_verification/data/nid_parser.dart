/// What could be read from a national ID barcode. Every field is optional —
/// the seller confirms or fills them in before submitting.
class NidScanResult {
  final String raw;
  final String? nidNumber;
  final String? fullName;
  final String? dateOfBirth; // yyyy-MM-dd when it could be parsed

  const NidScanResult({required this.raw, this.nidNumber, this.fullName, this.dateOfBirth});

  bool get hasAny => nidNumber != null || fullName != null || dateOfBirth != null;
}

const _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

String _two(int n) => n.toString().padLeft(2, '0');

String? _normalizeDate(String? input) {
  if (input == null) return null;
  final s = input.trim();
  // 19900131
  var m = RegExp(r'^(\d{4})(\d{2})(\d{2})$').firstMatch(s);
  if (m != null) return '${m[1]}-${m[2]}-${m[3]}';
  // 1990-01-31 / 1990/01/31
  m = RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})$').firstMatch(s);
  if (m != null) return '${m[1]}-${_two(int.parse(m[2]!))}-${_two(int.parse(m[3]!))}';
  // 31-01-1990 / 31/01/1990
  m = RegExp(r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})$').firstMatch(s);
  if (m != null) return '${m[3]}-${_two(int.parse(m[2]!))}-${_two(int.parse(m[1]!))}';
  // 31 Jan 1990
  m = RegExp(r'^(\d{1,2})\s+([A-Za-z]{3})[A-Za-z]*\s+(\d{4})$').firstMatch(s);
  if (m != null) {
    final month = _months[m[2]!.toLowerCase()];
    if (month != null) return '${m[3]}-${_two(month)}-${_two(int.parse(m[1]!))}';
  }
  return null;
}

String? _clean(String? s) {
  final v = s?.replaceAll(RegExp(r'\s+'), ' ').trim();
  return (v == null || v.isEmpty) ? null : v;
}

/// Reads the barcode on a Bangladesh NID card:
/// - Old laminated NID (PDF417): XML-like tags `<pin>…</pin><name>…</name><DOB>…</DOB>`.
/// - Smart NID (PDF417): key-prefixed text `NM<name>NW<10-digit NID>OL<old no>BR<yyyyMMdd>…`.
/// Falls back to picking out a 10/13/17-digit number and a date.
NidScanResult parseNidBarcode(String raw) {
  final text = raw.trim();

  // Old NID — XML-ish tags.
  String? tag(String name) =>
      RegExp('<$name>(.*?)</$name>', caseSensitive: false, dotAll: true).firstMatch(text)?.group(1);
  final pin = tag('pin');
  if (pin != null || tag('name') != null) {
    return NidScanResult(
      raw: text,
      nidNumber: _clean(pin)?.replaceAll(RegExp(r'\D'), ''),
      fullName: _clean(tag('name')),
      dateOfBirth: _normalizeDate(tag('DOB') ?? tag('dob')),
    );
  }

  // Smart NID — NM…NW…OL…BR…
  final smart = RegExp(r'NM(.+?)NW(\d{10})').firstMatch(text);
  if (smart != null) {
    final br = RegExp(r'BR(\d{8})').firstMatch(text)?.group(1);
    return NidScanResult(
      raw: text,
      nidNumber: smart.group(2),
      fullName: _clean(smart.group(1)),
      dateOfBirth: _normalizeDate(br),
    );
  }

  // Fallback — longest plausible NID number and the first date-looking token.
  final numbers = RegExp(r'(?<!\d)(\d{17}|\d{13}|\d{10})(?!\d)').allMatches(text).map((m) => m.group(1)!).toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  final dateToken = RegExp(r'(\d{4}[-/.]\d{1,2}[-/.]\d{1,2}|\d{1,2}[-/.]\d{1,2}[-/.]\d{4}|\d{1,2}\s+[A-Za-z]{3,9}\s+\d{4})')
      .firstMatch(text)
      ?.group(1);
  return NidScanResult(
    raw: text,
    nidNumber: numbers.isEmpty ? null : numbers.first,
    dateOfBirth: _normalizeDate(dateToken),
  );
}

/// The desktop "Verify with phone" QR: `aptigen-erp://verify-seller?store=12`.
int? parseVerifyQr(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || uri.scheme != 'aptigen-erp' || uri.host != 'verify-seller') return null;
  return int.tryParse(uri.queryParameters['store'] ?? '');
}
