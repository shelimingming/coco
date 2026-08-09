import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 统一输入框，默认大字号友好。
class CocoTextField extends StatelessWidget {
  const CocoTextField({
    super.key,
    required this.controller,
    this.label,
    this.hint,
    this.keyboardType,
    this.maxLength,
    this.inputFormatters,
    this.autofocus = false,
    this.onChanged,
    this.textInputAction,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String? label;
  final String? hint;
  final TextInputType? keyboardType;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLength: maxLength,
      inputFormatters: inputFormatters,
      autofocus: autofocus,
      onChanged: onChanged,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      style: Theme.of(context).textTheme.bodyLarge,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        counterText: '',
      ),
    );
  }
}
