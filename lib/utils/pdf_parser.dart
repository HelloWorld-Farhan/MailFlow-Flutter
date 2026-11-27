import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

List<String> _extractEmailsSync(Uint8List bytes) {
  final document = PdfDocument(inputBytes: bytes);
  try {
    final text = PdfTextExtractor(document).extractText();
    final emailRegex = RegExp(
      r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}',
      caseSensitive: false,
    );
    return {
      for (final m in emailRegex.allMatches(text))
        if (m.group(0) != null) m.group(0)!.toLowerCase(),
    }.toList();
  } finally {
    document.dispose();
  }
}

class PdfParser {
  /// Extracts unique lowercase email addresses from PDF bytes off the UI thread.
  static Future<List<String>> extractEmailsFromPdfBytes(Uint8List bytes) async {
    try {
      return await compute(_extractEmailsSync, bytes);
    } catch (_) {
      return [];
    }
  }
}
