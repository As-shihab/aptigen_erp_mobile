/// Shared numeric/date coercion helpers for the Store feature's ~15 model
/// files — every Store OData row can carry a String, num, bool or null for
/// the "same" logical field depending on how the generic OData layer
/// serialized it, so every model needs the same defensive parsing note/notes
/// already established do (see note_model.dart's top-level `toNum`).
int toNum(dynamic value) {
  final parsed = num.tryParse(value?.toString() ?? '');
  return parsed?.toInt() ?? 0;
}

int? toIntOrNull(dynamic value) {
  if (value == null) return null;
  return num.tryParse(value.toString())?.toInt();
}

double toDouble(dynamic value) {
  return num.tryParse(value?.toString() ?? '')?.toDouble() ?? 0;
}

double? toDoubleOrNull(dynamic value) {
  if (value == null) return null;
  return num.tryParse(value.toString())?.toDouble();
}

bool toBool(dynamic value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value == null) return fallback;
  final s = value.toString().toLowerCase();
  if (s == 'true' || s == '1') return true;
  if (s == 'false' || s == '0') return false;
  return fallback;
}

String? toStringOrNull(dynamic value) {
  if (value == null) return null;
  final s = value.toString();
  return s.isEmpty ? null : s;
}

/// `yyyy-MM-dd` — what OData `@db.Date` fields expect on write.
String formatDateOnly(DateTime date) {
  String p(int n) => n.toString().padLeft(2, '0');
  return '${date.year}-${p(date.month)}-${p(date.day)}';
}

/// Short display form for a date/datetime string coming back from the API.
String displayDate(dynamic value) {
  if (value == null) return '—';
  final date = DateTime.tryParse(value.toString());
  if (date == null) return '—';
  final local = date.toLocal();
  String p(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${p(local.month)}-${p(local.day)}';
}

int daysBetween(DateTime from, DateTime to) {
  final a = DateTime(from.year, from.month, from.day);
  final b = DateTime(to.year, to.month, to.day);
  return b.difference(a).inDays;
}
