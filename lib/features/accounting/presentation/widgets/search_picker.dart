import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

/// A searchable bottom-sheet list picker — mirrors erp/desktop's ComboBox
/// (type-to-filter account/bank-account/party pickers used across
/// ChartOfAccounts.tsx, JournalEntries.tsx, PaymentVouchers.tsx) as a mobile
/// bottom sheet instead of an inline dropdown, since these lists (accounts,
/// especially) can run into the hundreds.
Future<T?> showSearchPicker<T>({
  required BuildContext context,
  required String title,
  required List<T> items,
  required String Function(T) labelOf,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (context) => _SearchPickerSheet<T>(title: title, items: items, labelOf: labelOf),
  );
}

class _SearchPickerSheet<T> extends StatefulWidget {
  final String title;
  final List<T> items;
  final String Function(T) labelOf;
  const _SearchPickerSheet({required this.title, required this.items, required this.labelOf});

  @override
  State<_SearchPickerSheet<T>> createState() => _SearchPickerSheetState<T>();
}

class _SearchPickerSheetState<T> extends State<_SearchPickerSheet<T>> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.items.where((item) => widget.labelOf(item).toLowerCase().contains(_query.toLowerCase())).toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  autofocus: false,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search'),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: filtered.isEmpty
                    ? Center(child: Text('No matches', style: TextStyle(color: AppColors.slate600)))
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, index) => ListTile(
                          title: Text(widget.labelOf(filtered[index])),
                          onTap: () => Navigator.of(context).pop(filtered[index]),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
