import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/scheduled_email.dart';

class MailService {
  /// Sends an email via the Gmail API using the OAuth2 access token.
  static Future<bool> sendEmail({
    required ScheduledEmail emailConfig,
    required String accessToken,
  }) async {
    try {
      final String toHeader = emailConfig.recipients.join(', ');
      
      // Constructing RFC 2822 email format
      final StringBuffer rawEmail = StringBuffer();
      rawEmail.writeln('From: ${emailConfig.senderEmail}');
      rawEmail.writeln('To: $toHeader');
      final String encodedSubject = '=?utf-8?B?${base64Encode(utf8.encode(emailConfig.subject))}?=';
      rawEmail.writeln('Subject: $encodedSubject');
      rawEmail.writeln('Content-Type: text/html; charset="UTF-8"');
      rawEmail.writeln(''); // Empty line separates headers from body
      rawEmail.writeln(emailConfig.body);

      // Encode the raw email string in Base64 URL safe format
      final String base64Email = base64UrlEncode(utf8.encode(rawEmail.toString()));

      // Gmail API Endpoint
      final Uri url = Uri.parse('https://gmail.googleapis.com/gmail/v1/users/me/messages/send');

      // Make the POST request
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'raw': base64Email,
        }),
      );

      if (response.statusCode == 200) {
        print('Email sent successfully!');
        return true;
      } else {
        print('Failed to send email. Status code: ${response.statusCode}');
        print('Response body: ${response.body}');
        return false;
      }
    } catch (e) {
      print('Error sending email: $e');
      return false;
    }
  }

  static Future<String> sendEmailWithReason({
    required ScheduledEmail emailConfig,
    required String accessToken,
  }) async {
    try {
      final String toHeader = emailConfig.recipients.join(', ');
      
      final StringBuffer rawEmail = StringBuffer();
      rawEmail.writeln('From: ${emailConfig.senderEmail}');
      rawEmail.writeln('To: $toHeader');
      final String encodedSubject = '=?utf-8?B?${base64Encode(utf8.encode(emailConfig.subject))}?=';
      rawEmail.writeln('Subject: $encodedSubject');
      rawEmail.writeln('Content-Type: text/html; charset="UTF-8"');
      rawEmail.writeln(''); 
      rawEmail.writeln(emailConfig.body);

      final String base64Email = base64UrlEncode(utf8.encode(rawEmail.toString()));

      final Uri url = Uri.parse('https://gmail.googleapis.com/gmail/v1/users/me/messages/send');

      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'raw': base64Email,
        }),
      );

      if (response.statusCode == 200) {
        return 'Success';
      } else {
        final err = 'Code ${response.statusCode}: ${response.body}';
        print(err);
        return err;
      }
    } catch (e) {
      print('Exception: $e');
      return e.toString();
    }
  }
}
