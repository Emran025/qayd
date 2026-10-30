import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/utils/text_sanitizer.dart';

/// RTL-aware text field using [InputDecorationTheme] from [AppTheme].
class QaydTextField extends StatelessWidget {
  const QaydTextField({
    super.key,
    this.controller,
    this.initialValue,
    this.label,
    this.hint,
    this.helperText,
    this.errorText,
    this.validator,
    this.onChanged,
    this.onTap,
    this.onFieldSubmitted,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.keyboardType,
    this.autofocus = false,
    this.readOnly = false,
    this.enabled = true,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.focusNode,
    this.prefixIcon,
    this.suffixIcon,
    this.inputFormatters,
    this.autovalidateMode,
    this.obscureText = false,
    this.isPassword = false,
  });

  final TextEditingController? controller;
  final String? initialValue;
  final String? label;
  final String? hint;
  final String? helperText;
  final String? errorText;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;
  final ValueChanged<String>? onFieldSubmitted;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final TextInputType? keyboardType;
  final bool autofocus;
  final bool readOnly;
  final bool enabled;
  final int maxLines;
  final int? minLines;
  final int? maxLength;
  final FocusNode? focusNode;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final List<TextInputFormatter>? inputFormatters;
  final AutovalidateMode? autovalidateMode;
  final bool obscureText;
  final bool isPassword;

  @override
  Widget build(BuildContext context) {
    final field = TextFormField(
      obscureText: obscureText,
      controller: controller,
      initialValue: controller == null ? initialValue : null,
      focusNode: focusNode,
      autofocus: autofocus,
      readOnly: readOnly,
      enabled: enabled,
      maxLines: maxLines,
      minLines: minLines,
      maxLength: maxLength,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      textCapitalization: textCapitalization,
      textAlign: TextAlign.start,
      validator: validator,
      onChanged: onChanged,
      onTap: onTap,
      onFieldSubmitted: onFieldSubmitted,
      inputFormatters: [
        FilteringTextInputFormatter.deny(TextSanitizer.emojiRegex,
            replacementString: ' '),
        ...?inputFormatters,
      ],
      autovalidateMode: autovalidateMode,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helperText,
        errorText: errorText,
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
      ),
    );

    final isLtrType = obscureText || isPassword ||
        keyboardType == TextInputType.number ||
        keyboardType == const TextInputType.numberWithOptions(decimal: true) ||
        keyboardType == const TextInputType.numberWithOptions(signed: true) ||
        keyboardType == TextInputType.phone ||
        keyboardType == TextInputType.emailAddress ||
        keyboardType == TextInputType.url;

    return Directionality(
      textDirection: isLtrType ? TextDirection.ltr : Directionality.of(context),
      child: field,
    );
  }
}
