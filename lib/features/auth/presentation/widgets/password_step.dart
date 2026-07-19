import 'package:flutter/material.dart';

class PasswordStep extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final VoidCallback? onSubmitted;

  const PasswordStep({super.key, required this.value, required this.onChanged, this.onSubmitted});

  @override
  State<PasswordStep> createState() => _PasswordStepState();
}

class _PasswordStepState extends State<PasswordStep> {
  bool _showPassword = false;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: TextFormField(
        initialValue: widget.value,
        autofocus: true,
        obscureText: !_showPassword,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: 'Password',
          hintText: 'Enter your password',
          suffixIcon: IconButton(
            icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
            onPressed: () => setState(() => _showPassword = !_showPassword),
          ),
        ),
        onChanged: widget.onChanged,
        onFieldSubmitted: (_) => widget.onSubmitted?.call(),
      ),
    );
  }
}
