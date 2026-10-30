import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Unified numeric field that enforces LTR direction even in RTL contexts.
/// Suitable for PINs, IDs, phone numbers, or any numeric input.
class QaydNumericField extends StatelessWidget {
  const QaydNumericField({
    super.key,
    this.controller,
    this.initialValue,
    this.label,
    this.hint,
    this.helperText,
    this.errorText,
    this.validator,
    this.onChanged,
    this.onFieldSubmitted,
    this.textInputAction,
    this.autofocus = false,
    this.readOnly = false,
    this.enabled = true,
    this.focusNode,
    this.prefixIcon,
    this.suffixIcon,
    this.suffixText,
    this.isDecimal = false,
    this.isSigned = false,
    this.maxLength,
    this.autovalidateMode,
    this.obscureText = false,
    this.textAlign = TextAlign.start,
  });

  final TextEditingController? controller;
  final String? initialValue;
  final String? label;
  final String? hint;
  final String? helperText;
  final String? errorText;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onFieldSubmitted;
  final TextInputAction? textInputAction;
  final bool autofocus;
  final bool readOnly;
  final bool enabled;
  final FocusNode? focusNode;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final String? suffixText;
  final bool isDecimal;
  final bool isSigned;
  final int? maxLength;
  final AutovalidateMode? autovalidateMode;
  final bool obscureText;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: TextFormField(
        controller: controller,
        initialValue: controller == null ? initialValue : null,
        focusNode: focusNode,
        autofocus: autofocus,
        readOnly: readOnly,
        enabled: enabled,
        obscureText: obscureText,
        keyboardType: TextInputType.numberWithOptions(
          decimal: isDecimal,
          signed: isSigned,
        ),
        textInputAction: textInputAction,
        textAlign: textAlign,
        maxLength: maxLength,
        validator: validator,
        onChanged: onChanged,
        onFieldSubmitted: onFieldSubmitted,
        autovalidateMode: autovalidateMode,
        inputFormatters: [
          _NumericInputFormatter(isDecimal: isDecimal, isSigned: isSigned),
          if (maxLength != null) LengthLimitingTextInputFormatter(maxLength),
        ],
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          helperText: helperText,
          errorText: errorText,
          prefixIcon: prefixIcon,
          suffixIcon: suffixIcon,
          suffixText: suffixText,
          counterText: '', // Hide default counter for compact look
        ),
      ),
    );
  }
}

class _NumericInputFormatter extends TextInputFormatter {
  _NumericInputFormatter({required this.isDecimal, required this.isSigned});

  final bool isDecimal;
  final bool isSigned;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;

    // Build regex based on requirements
    String pattern = r'^\d*';
    if (isDecimal) pattern += r'(\.\d*)?';
    if (isSigned) pattern = r'^-?' + pattern.substring(1);
    pattern += r'$';

    final regExp = RegExp(pattern);

    // Normalize comma to dot for decimal inputs
    String text = newValue.text;
    if (isDecimal) {
      text = text.replaceAll(',', '.');
    }

    if (regExp.hasMatch(text)) {
      return newValue.copyWith(text: text);
    }
    return oldValue;
  }
}
