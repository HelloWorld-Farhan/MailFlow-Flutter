import 'dart:io';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class PdfParser {
  /// Extracts all valid email addresses from a given PDF file path.
  static Future<List<String>> extractEmailsFromPdf(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        print('File does not exist: $filePath');
        return [];
      }

      final bytes = await file.readAsBytes();
      final PdfDocument document = PdfDocument(inputBytes: bytes);
      
      // Extract text from all pages
      final PdfTextExtractor extractor = PdfTextExtractor(document);
      final String text = extractor.extractText();
      
      document.dispose();

      // Regex to find email addresses
      final RegExp emailRegex = RegExp(
        r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}',
        caseSensitive: false,
      );

      final Iterable<RegExpMatch> matches = emailRegex.allMatches(text);
      final Set<String> uniqueEmails = {};
      
      for (final match in matches) {
        final email = match.group(0);
        if (email != null) {
          uniqueEmails.add(email.toLowerCase());
        }
      }

      return uniqueEmails.toList();
    } catch (e) {
      print('Error parsing PDF: $e');
      return [];
    }
  }
}
