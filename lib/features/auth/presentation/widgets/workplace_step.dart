import 'package:flutter/material.dart';

class WorkplaceStep extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const WorkplaceStep({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: TextFormField(
        initialValue: value,
        autofocus: true,
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(
          labelText: 'Workplace name',
          hintText: 'My Workplace',
        ),
        onChanged: onChanged,
      ),
    );
  }
}
