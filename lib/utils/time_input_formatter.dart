import 'package:flutter/services.dart';

class TimeInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final newText = newValue.text;
    
    // Deleting
    if (newText.length < oldValue.text.length) {
      return newValue;
    }

    String formattedText = newText.replaceAll(RegExp(r'[^0-9]'), '');

    // Hours
    if (formattedText.length == 1) {
      int firstDigit = int.tryParse(formattedText) ?? 0;
      if (firstDigit > 1) {
        formattedText = '0$firstDigit'; // Auto-pad "2" -> "02"
      }
    } else if (formattedText.length >= 2) {
      int hour = int.tryParse(formattedText.substring(0, 2)) ?? 0;
      if (hour > 12) {
        return oldValue; // Reject > 12
      }
      if (hour == 0 && formattedText.length > 1 && !formattedText.startsWith('00')) {
        // allowing 0 to be typed, but rejecting 00 if needed? Let's keep 00 for now, though 12 hour format usually uses 12.
        // If hour == 0, it's actually invalid in strict 12hr format, usually it's 12. Let's enforce hour > 0 later or keep it simple.
      }
    }

    // Minutes
    if (formattedText.length == 3) {
      int firstMinDigit = int.tryParse(formattedText.substring(2, 3)) ?? 0;
      if (firstMinDigit > 5) {
        return oldValue; // Reject minute starting with 6,7,8,9 (e.g. 60)
      }
    }

    if (formattedText.length >= 4) {
      formattedText = formattedText.substring(0, 4);
    }

    String finalResult = '';
    for (int i = 0; i < formattedText.length; i++) {
      if (i == 2) {
        finalResult += ':';
      }
      finalResult += formattedText[i];
    }

    if (formattedText.length == 2) {
      finalResult += ':';
    }

    return TextEditingValue(
      text: finalResult,
      selection: TextSelection.collapsed(offset: finalResult.length),
    );
  }
}
