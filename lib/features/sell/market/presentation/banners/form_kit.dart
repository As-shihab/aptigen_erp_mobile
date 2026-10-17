import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../../core/network/http_client.dart';
import '../widgets/market_ui.dart';

// Small form kit shared by the payment methods, banners and storefront
// editors: labelled fields, switch rows, a sort-order stepper and a
// combined date + time picker field.

String errorText(Object e, String fallback) => e is ApiException && e.message.trim().isNotEmpty ? e.message : fallback;

String? orNull(String s) => s.trim().isEmpty ? null : s.trim();

InputDecoration marketInput(BuildContext context, {String? hint, Widget? prefixIcon, String? prefixText, Widget? suffix}) {
  final p = MarketPalette.of(context);
  OutlineInputBorder b(Color c, [double w = 1]) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c, width: w));
  return InputDecoration(
    isDense: true,
    hintText: hint,
    hintStyle: TextStyle(color: p.label.withValues(alpha: 0.75), fontSize: 13.5),
    prefixIcon: prefixIcon,
    prefixText: prefixText,
    prefixStyle: TextStyle(color: p.label, fontSize: 13.5),
    suffixIcon: suffix,
    filled: true,
    fillColor: p.surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    enabledBorder: b(p.line),
    border: b(p.line),
    focusedBorder: b(p.brand, 1.5),
    errorBorder: b(p.error),
    focusedErrorBorder: b(p.error, 1.5),
  );
}

/// Label above a field, with an optional required marker and help line.
class FieldBlock extends StatelessWidget {
  final String label;
  final bool required;
  final String? help;
  final Widget child;
  const FieldBlock({super.key, required this.label, required this.child, this.required = false, this.help});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text.rich(
          TextSpan(children: [
            TextSpan(text: label),
            if (required) TextSpan(text: ' *', style: TextStyle(color: p.error)),
          ]),
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.label),
        ),
        const SizedBox(height: 6),
        child,
        if (help != null) ...[
          const SizedBox(height: 5),
          Text(help!, style: TextStyle(fontSize: 11.5, color: p.label, height: 1.35)),
        ],
      ]),
    );
  }
}

/// Text field with the market decoration.
class MarketTextField extends StatelessWidget {
  final TextEditingController controller;
  final String? hint;
  final int maxLines;
  final TextInputType? keyboardType;
  final IconData? icon;
  final String? prefixText;
  final ValueChanged<String>? onChanged;
  final TextCapitalization capitalization;
  const MarketTextField({
    super.key,
    required this.controller,
    this.hint,
    this.maxLines = 1,
    this.keyboardType,
    this.icon,
    this.prefixText,
    this.onChanged,
    this.capitalization = TextCapitalization.sentences,
  });

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return TextField(
      controller: controller,
      minLines: maxLines > 1 ? 2 : 1,
      maxLines: maxLines,
      keyboardType: maxLines > 1 ? TextInputType.multiline : keyboardType,
      textCapitalization: capitalization,
      onChanged: onChanged,
      style: TextStyle(fontSize: 14, color: p.text),
      decoration: marketInput(
        context,
        hint: hint,
        prefixText: prefixText,
        prefixIcon: icon == null ? null : Icon(icon, size: 18, color: p.label),
      ),
    );
  }
}

/// Bordered row with a title, sub line and a switch.
class SwitchRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const SwitchRow({super.key, required this.title, this.subtitle, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.line)),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.text)),
            if (subtitle != null) Text(subtitle!, style: TextStyle(fontSize: 11.5, color: p.label)),
          ]),
        ),
        Switch.adaptive(value: value, onChanged: onChanged),
      ]),
    );
  }
}

/// Compact − value + stepper for sort order.
class StepperField extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  const StepperField({super.key, required this.value, required this.onChanged, this.min = 0});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    Widget btn(IconData i, VoidCallback? on) => IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: on,
          icon: Icon(i, size: 18, color: on == null ? p.line : p.brand),
        );
    return Container(
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.line)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        btn(Icons.remove, value > min ? () => onChanged(value - 1) : null),
        SizedBox(
          width: 40,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            child: Text('$value',
                key: ValueKey(value),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
          ),
        ),
        btn(Icons.add, () => onChanged(value + 1)),
      ]),
    );
  }
}

// ── Date + time ───────────────────────────────────────────────────────

final _dtFormat = DateFormat('d MMM yyyy, HH:mm');

String formatDateTime(DateTime d) => _dtFormat.format(d.toLocal());

DateTime? parseDate(dynamic v) => v == null || '$v'.isEmpty ? null : DateTime.tryParse('$v')?.toLocal();

/// Date picker followed by a time picker; null when cancelled.
Future<DateTime?> pickDateTime(BuildContext context, {DateTime? initial}) async {
  final now = DateTime.now();
  final base = initial ?? DateTime(now.year, now.month, now.day, now.hour + 1);
  final date = await showDatePicker(
    context: context,
    initialDate: base,
    firstDate: DateTime(now.year - 2),
    lastDate: DateTime(now.year + 5),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(base));
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

/// Tappable field showing a date-time with a clear button.
class DateTimeField extends StatelessWidget {
  final DateTime? value;
  final String hint;
  final ValueChanged<DateTime?> onChanged;
  const DateTimeField({super.key, required this.value, required this.onChanged, this.hint = 'Not set'});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Material(
      color: p.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () async {
          final v = await pickDateTime(context, initial: value);
          if (v != null) onChanged(v);
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
          constraints: const BoxConstraints(minHeight: 46),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: p.line)),
          child: Row(children: [
            Icon(Icons.event_outlined, size: 18, color: p.label),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                value == null ? hint : formatDateTime(value!),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13.5, color: value == null ? p.label : p.text),
              ),
            ),
            if (value != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Clear',
                onPressed: () => onChanged(null),
                icon: Icon(Icons.close, size: 18, color: p.label),
              )
            else
              const SizedBox(height: 38),
          ]),
        ),
      ),
    );
  }
}

/// Sheet header: title, sub line and a close button.
class SheetHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  const SheetHeader({super.key, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      const SizedBox(height: 8),
      Container(width: 36, height: 4, decoration: BoxDecoration(color: p.line, borderRadius: BorderRadius.circular(2))),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 8, 10),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
              if (subtitle != null) Text(subtitle!, style: TextStyle(fontSize: 12, color: p.label)),
            ]),
          ),
          IconButton(onPressed: () => Navigator.maybePop(context), icon: Icon(Icons.close, color: p.label)),
        ]),
      ),
      Divider(height: 1, color: p.line),
    ]);
  }
}

/// Sticky sheet footer with a primary save button.
class SheetFooter extends StatelessWidget {
  final String label;
  final bool busy;
  final VoidCallback? onPressed;
  const SheetFooter({super.key, required this.label, required this.busy, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return Container(
      decoration: BoxDecoration(color: p.card, border: Border(top: BorderSide(color: p.line))),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          height: 46,
          child: FilledButton(
            onPressed: busy ? null : onPressed,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: busy
                  ? const SizedBox(key: ValueKey('b'), width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(label, key: const ValueKey('l')),
            ),
          ),
        ),
      ),
    );
  }
}

/// Selectable chip used for option sets (methods, placements, tones).
class OptionChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final Color? dot;
  const OptionChip({super.key, required this.label, required this.selected, required this.onTap, this.icon, this.dot});

  @override
  Widget build(BuildContext context) {
    final p = MarketPalette.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? p.brandSoft : p.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? p.brand : p.line, width: selected ? 1.4 : 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (dot != null) ...[
            Container(width: 12, height: 12, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
            const SizedBox(width: 7),
          ],
          if (icon != null) ...[Icon(icon, size: 16, color: selected ? p.brand : p.label), const SizedBox(width: 6)],
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? p.brand : p.text)),
          ),
        ]),
      ),
    );
  }
}
