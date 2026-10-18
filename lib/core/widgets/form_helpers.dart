import 'package:flutter/material.dart';

/// Validation shared by the forms.
class Validators {
  Validators._();

  static String? Function(String?) required(String label) =>
      (v) => (v == null || v.trim().isEmpty) ? '$label is required' : null;

  /// Kenyan mobile numbers: 07xx/01xx xxx xxx or +254 7xx xxx xxx.
  static final _phone = RegExp(r'^(?:\+?254|0)[17]\d{8}$');

  static String? phone(String? v, {bool optional = false}) {
    final value = (v ?? '').replaceAll(RegExp(r'[\s-]'), '');
    if (value.isEmpty) return optional ? null : 'Phone number is required';
    if (!_phone.hasMatch(value)) return 'Enter a valid phone number, e.g. 0712345678';
    return null;
  }

  static String? nationalId(String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return 'National ID number is required';
    if (!RegExp(r'^\d{6,10}$').hasMatch(value)) return 'ID number should be 6 to 10 digits';
    return null;
  }

  static String? email(String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return null;
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)) return 'Enter a valid email address';
    return null;
  }

  static String? Function(String?) positiveNumber(String label, {double? max, String? maxMessage}) => (v) {
        final value = double.tryParse((v ?? '').replaceAll(',', '').trim());
        if (value == null) return '$label is required';
        if (value <= 0) return '$label must be greater than zero';
        if (max != null && value > max) return maxMessage ?? '$label cannot exceed $max';
        return null;
      };
}

double? parseAmount(String text) => double.tryParse(text.replaceAll(',', '').trim());

class DialogField {
  const DialogField(this.key, this.label, {this.validator, this.keyboardType, this.initial = ''});
  final String key;
  final String label;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final String initial;
}

/// Small form in a dialog; returns the entered values or null if cancelled.
Future<Map<String, String>?> showFieldsDialog(BuildContext context,
    {required String title, required List<DialogField> fields}) {
  final formKey = GlobalKey<FormState>();
  final controllers = {for (final f in fields) f.key: TextEditingController(text: f.initial)};
  return showDialog<Map<String, String>>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Form(
        key: formKey,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final f in fields)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextFormField(
                  controller: controllers[f.key],
                  decoration: InputDecoration(labelText: f.label),
                  keyboardType: f.keyboardType,
                  textCapitalization:
                      f.keyboardType == null ? TextCapitalization.words : TextCapitalization.none,
                  validator: f.validator,
                ),
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (!formKey.currentState!.validate()) return;
            Navigator.pop(ctx, {for (final e in controllers.entries) e.key: e.value.text.trim()});
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
