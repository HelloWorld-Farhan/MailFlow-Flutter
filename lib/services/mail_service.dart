import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/scheduled_email.dart';

class MailService {
  static final http.Client _client = http.Client();

  /// Sends an email via the Gmail REST API and returns `'Success'` or an error reason.
  static Future<String> sendEmailWithReason({
    required ScheduledEmail emailConfig,
    required String accessToken,
  }) async {
    try {
      final rawEmail = StringBuffer()
        ..writeln('From: ${emailConfig.senderEmail}')
        ..writeln('To: ${emailConfig.recipients.join(', ')}')
        ..writeln(
          'Subject: =?utf-8?B?${base64Encode(utf8.encode(emailConfig.subject))}?=',
        )
        ..writeln('Content-Type: text/html; charset="UTF-8"')
        ..writeln('')
        ..writeln(emailConfig.body);

      final response = await _client.post(
        Uri.parse('https://gmail.googleapis.com/gmail/v1/users/me/messages/send'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'raw': base64UrlEncode(utf8.encode(rawEmail.toString())),
        }),
      );

      if (response.statusCode == 200) return 'Success';
      return 'Code ${response.statusCode}: ${response.body}';
    } catch (e) {
      return e.toString();
    }
  }
}
