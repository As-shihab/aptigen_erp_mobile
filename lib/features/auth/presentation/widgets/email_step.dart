import 'package:flutter/material.dart';

class EmailStep extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const EmailStep({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: double.infinity,
        child: TextFormField(
          initialValue: value,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Email',
            hintText: 'name@company.com',
          ),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
