import 'package:flutter/services.dart';

class DateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final newText = newValue.text;
    
    // Deleting character
    if (newText.length < oldValue.text.length) {
      return newValue;
    }

    String formattedText = newText.replaceAll(RegExp(r'[^0-9]'), '');
    
    // Auto-pad single digit if next char is entered, but for live auto-padding '2' -> '02/':
    if (formattedText.length == 1) {
      int firstDigit = int.tryParse(formattedText) ?? 0;
      if (firstDigit > 3) {
        // Auto pad to 0X/
        formattedText = '0$firstDigit';
      }
    } else if (formattedText.length >= 2) {
      int day = int.tryParse(formattedText.substring(0, 2)) ?? 0;
      if (day > 31) {
        return oldValue; // Invalid day
      }
    }

    if (formattedText.length >= 3) {
      int firstMonthDigit = int.tryParse(formattedText.substring(2, 3)) ?? 0;
      if (firstMonthDigit > 1) {
        formattedText = '${formattedText.substring(0, 2)}0$firstMonthDigit';
      }
    }
    
    if (formattedText.length >= 4) {
      int month = int.tryParse(formattedText.substring(2, 4)) ?? 0;
      if (month > 12 || month == 0) {
        return oldValue; // Invalid month
      }
    }

    // Full Date Validation
    if (formattedText.length >= 8) {
      formattedText = formattedText.substring(0, 8);
      int day = int.parse(formattedText.substring(0, 2));
      int month = int.parse(formattedText.substring(2, 4));
      int year = int.parse(formattedText.substring(4, 8));

      bool isLeapYear = (year % 4 == 0) && ((year % 100 != 0) || (year % 400 == 0));
      int maxDays = 31;
      
      if (month == 4 || month == 6 || month == 9 || month == 11) {
        maxDays = 30;
      } else if (month == 2) {
        maxDays = isLeapYear ? 29 : 28;
      }
      
      if (day > maxDays || day == 0) {
        return oldValue; // Reject if day exceeds max days for that month/year
      }
    }

    // Add slashes
    String finalResult = '';
    for (int i = 0; i < formattedText.length; i++) {
      if (i == 2 || i == 4) {
        finalResult += '/';
      }
      finalResult += formattedText[i];
    }

    // Handle auto-slash addition at boundaries
    if ((formattedText.length == 2 || formattedText.length == 4) && newValue.text.endsWith('/')) {
      // Allow the user to type '/' naturally
    } else if (formattedText.length == 2 || formattedText.length == 4) {
      finalResult += '/';
    }

    return TextEditingValue(
      text: finalResult,
      selection: TextSelection.collapsed(offset: finalResult.length),
    );
  }
}
