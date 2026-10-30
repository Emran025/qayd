import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Decimal amount entry with LTR digit flow inside RTL shells; enforces one separator and scale.
class QaydAmountField extends StatelessWidget {
  const QaydAmountField({
    super.key,
    required this.controller,
    this.label,
    this.hint,
    this.helperText,
    this.suffixText,
    this.errorText,
    this.validator,
    this.onChanged,
    this.onFieldSubmitted,
    this.textInputAction,
    this.autofocus = false,
    this.enabled = true,
    this.focusNode,
    this.fractionalDigits = 2,
    this.autovalidateMode,
  });

  final TextEditingController controller;
  final String? label;
  final String? hint;
  final String? helperText;
  final String? suffixText;
  final String? errorText;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onFieldSubmitted;
  final TextInputAction? textInputAction;
  final bool autofocus;
  final bool enabled;
  final FocusNode? focusNode;
  final int fractionalDigits;
  final AutovalidateMode? autovalidateMode;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: TextFormField(
        controller: controller,
        focusNode: focusNode,
        autofocus: autofocus,
        enabled: enabled,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: textInputAction,
        textAlign: TextAlign.start,
        validator: validator,
        onChanged: onChanged,
        onFieldSubmitted: onFieldSubmitted,
        autovalidateMode: autovalidateMode,
        inputFormatters: [
          _AmountInputFormatter(fractionalDigits: fractionalDigits),
        ],
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          helperText: helperText,
          suffixText: suffixText,
          errorText: errorText,
        ),
      ),
    );
  }
}

final class _AmountInputFormatter extends TextInputFormatter {
  _AmountInputFormatter({required this.fractionalDigits})
      : _valid = RegExp(
          r'^\d{0,14}(\.\d{0,' + fractionalDigits.toString() + r'})?$',
        );

  final int fractionalDigits;
  final RegExp _valid;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final t = newValue.text.replaceAll(',', '.');
    if (t.isEmpty) {
      return newValue.copyWith(text: '');
    }
    if (t == '.') {
      return oldValue;
    }
    if (!_valid.hasMatch(t)) {
      return oldValue;
    }
    return newValue.copyWith(text: t, composing: TextRange.empty);
  }
}
