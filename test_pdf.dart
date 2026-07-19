import 'dart:io';
import 'package:mailflow/utils/pdf_parser.dart';

void main() async {
  final path = 'C:\\Project\\MailFlow\\HR_Contact_List.pdf';
  print('Starting extraction from: \$path');
  final emails = await PdfParser.extractEmailsFromPdf(path);
  print('Extracted \${emails.length} emails:');
  for (var email in emails) {
    print(email);
  }
}
