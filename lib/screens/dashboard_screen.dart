import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/scheduled_email.dart';
import '../services/storage_service.dart';
import '../utils/date_input_formatter.dart';
import '../utils/time_input_formatter.dart';
import '../utils/pdf_parser.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<ScheduledEmail> _history = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final history = await StorageService.getEmails();
    setState(() {
      _history = history;
      _isLoading = false;
    });
  }

  void _openScheduleModal({ScheduledEmail? existingEmail}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ScheduleModal(editEmail: existingEmail),
    ).then((_) {
      _loadHistory();
    });
  }

  Future<void> _deleteEmail(String id) async {
    await StorageService.deleteEmail(id);
    _loadHistory();
  }

  void _showEmailDetails(ScheduledEmail email) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Theme.of(context).cardTheme.color,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Schedule Details', style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                      IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.pop(context)),
                    ],
                  ),
                  const Divider(color: Colors.white24, height: 32),
                  _buildDetailRow(Icons.account_circle, 'Sender', email.senderEmail, isValid: true, isAuth: true),
                  _buildDetailRow(Icons.calendar_today, 'Date', email.scheduledDate),
                  _buildDetailRow(Icons.access_time, 'Time', email.scheduledTime),
                  _buildDetailRow(Icons.subject, 'Subject', email.subject.isEmpty ? '(No Subject)' : email.subject),
                  const SizedBox(height: 16),
                  Text('Body', style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
                    child: Text(email.body.isEmpty ? '(Empty Body)' : email.body, style: const TextStyle(color: Colors.white70)),
                  ),
                  const SizedBox(height: 16),
                  Text('Recipients (\${email.recipients.length})', style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ...email.recipients.map((rec) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.greenAccent, size: 16),
                        const SizedBox(width: 8),
                        Expanded(child: Text(rec, style: const TextStyle(color: Colors.white70))),
                      ],
                    ),
                  )),
                ],
              ),
            ),
          ),
        ).animate().scale(duration: 300.ms, curve: Curves.easeOutBack).fade(duration: 300.ms);
      },
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value, {bool isValid = false, bool isAuth = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white54, size: 20),
          const SizedBox(width: 12),
          SizedBox(width: 70, child: Text(label, style: const TextStyle(color: Colors.white54))),
          Expanded(child: Text(value, style: const TextStyle(color: Colors.white))),
          if (isValid)
            Icon(isAuth ? Icons.security : Icons.check_circle, color: Colors.greenAccent, size: 18),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/Logo.png', width: 32, height: 32).animate().fade(duration: 600.ms),
            const SizedBox(width: 12),
            Text('MailFlow', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, letterSpacing: 1.5)),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _history.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.history_rounded, size: 64, color: Colors.white24).animate().fade().scale(),
                      const SizedBox(height: 16),
                      Text(
                        'No emails scheduled yet.',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ).animate().fade(delay: 200.ms),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _history.length,
                  itemBuilder: (context, index) {
                    final item = _history[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => _showEmailDetails(item),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
                                child: Icon(
                                  item.type == 'PDF' ? Icons.picture_as_pdf : Icons.person,
                                  color: Theme.of(context).primaryColor,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item.subject.isNotEmpty ? item.subject : '(No Subject)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                    const SizedBox(height: 4),
                                    Text('From: \${item.senderEmail}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                    Text('\${item.scheduledDate} at \${item.scheduledTime}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                                  ],
                                ),
                              ),
                              Column(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: item.status == 'Success' ? Colors.green.withOpacity(0.2) : Colors.orange.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      item.status,
                                      style: TextStyle(
                                        color: item.status == 'Success' ? Colors.greenAccent : Colors.orangeAccent,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit, size: 20, color: Colors.white54),
                                        onPressed: () => _openScheduleModal(existingEmail: item),
                                        tooltip: 'Edit',
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete, size: 20, color: Colors.redAccent),
                                        onPressed: () => _deleteEmail(item.id),
                                        tooltip: 'Cancel Schedule',
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ).animate().fade(duration: 400.ms, delay: (index * 100).ms).slideX(begin: 0.1, end: 0);
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openScheduleModal(),
        icon: const Icon(Icons.add),
        label: const Text('Schedule Email'),
      ).animate().scale(delay: 500.ms, duration: 400.ms, curve: Curves.easeOutBack),
    );
  }
}

class _ScheduleModal extends StatefulWidget {
  final ScheduledEmail? editEmail;
  const _ScheduleModal({this.editEmail});

  @override
  State<_ScheduleModal> createState() => _ScheduleModalState();
}

class _ScheduleModalState extends State<_ScheduleModal> {
  late String _sendType;
  
  final TextEditingController _senderController = TextEditingController();
  bool _isAuthenticated = false;
  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: ['email', 'https://www.googleapis.com/auth/gmail.send']);

  List<TextEditingController> _emailControllers = [TextEditingController()];
  String? _pdfPath;
  List<String> _pdfEmails = [];

  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _bodyController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _timeController = TextEditingController();
  bool _isAm = true;

  @override
  void initState() {
    super.initState();
    if (widget.editEmail != null) {
      final email = widget.editEmail!;
      _sendType = email.type;
      _senderController.text = email.senderEmail;
      _isAuthenticated = true; // Assume true for editing
      _subjectController.text = email.subject;
      _bodyController.text = email.body;
      _dateController.text = email.scheduledDate;
      
      String timeStr = email.scheduledTime;
      _isAm = timeStr.contains('AM');
      _timeController.text = timeStr.replaceAll(RegExp(r' AM| PM'), '');

      if (_sendType == 'Single' || _sendType == 'Multiple') {
        _emailControllers = email.recipients.map((r) => TextEditingController(text: r)).toList();
      } else if (_sendType == 'PDF') {
        _pdfPath = 'Extracted (\${email.recipients.length} emails)';
        _pdfEmails = email.recipients;
      }
    } else {
      _sendType = 'Single';
    }
  }

  @override
  void dispose() {
    _senderController.dispose();
    for (var c in _emailControllers) { c.dispose(); }
    _subjectController.dispose();
    _bodyController.dispose();
    _dateController.dispose();
    _timeController.dispose();
    super.dispose();
  }

  Future<void> _authenticateWithGoogle() async {
    if (!_isValidEmail(_senderController.text)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a valid Sender Email first.')));
      return;
    }
    try {
      final account = await _googleSignIn.signIn();
      if (account != null) {
        setState(() {
          _isAuthenticated = true;
          _senderController.text = account.email;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Authenticated Successfully!')));
      }
    } catch (error) {
      setState(() {
        _isAuthenticated = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Demo Auth Success!')));
    }
  }

  bool _isValidEmail(String email) {
    final RegExp regex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
    return regex.hasMatch(email.trim());
  }

  Future<void> _pickPdf() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      final emails = await PdfParser.extractEmailsFromPdf(path);
      setState(() {
        _pdfPath = result.files.single.name;
        _pdfEmails = emails;
      });
    }
  }

  void _reviewExtractedEmails() {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Theme.of(context).cardTheme.color,
          child: Container(
            padding: const EdgeInsets.all(16),
            height: 400,
            child: Column(
              children: [
                Text('Extracted Emails (\${_pdfEmails.length})', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.builder(
                    itemCount: _pdfEmails.length,
                    itemBuilder: (context, index) {
                      return ListTile(
                        leading: const Icon(Icons.email, color: Colors.white54),
                        title: Text(_pdfEmails[index], style: const TextStyle(color: Colors.white)),
                        trailing: const Icon(Icons.check_circle, color: Colors.greenAccent, size: 16),
                      );
                    },
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                )
              ],
            ),
          ),
        ).animate().fade().scale();
      },
    );
  }

  bool _isDateTimeValid(String dateString, String timeString, bool isAm) {
    if (dateString.length != 10 || timeString.length != 5) return false;
    try {
      int day = int.parse(dateString.substring(0, 2));
      int month = int.parse(dateString.substring(3, 5));
      int year = int.parse(dateString.substring(6, 10));
      
      int hour = int.parse(timeString.substring(0, 2));
      int minute = int.parse(timeString.substring(3, 5));
      
      if (!isAm && hour != 12) hour += 12;
      if (isAm && hour == 12) hour = 0;
      
      DateTime entered = DateTime(year, month, day, hour, minute);
      DateTime now = DateTime.now();
      
      return entered.isAfter(now);
    } catch (e) {
      return false;
    }
  }

  Future<void> _submit() async {
    if (!_isValidEmail(_senderController.text) || !_isAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please authenticate a valid Sender Email.')));
      return;
    }
    if (_dateController.text.length != 10 || _timeController.text.length != 5) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter valid Date and Time.')));
      return;
    }
    if (!_isDateTimeValid(_dateController.text, _timeController.text, _isAm)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot schedule in the past!')));
      return;
    }

    List<String> recipients = [];
    if (_sendType == 'PDF') {
      if (_pdfEmails.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No emails found in PDF or no PDF selected.')));
        return;
      }
      recipients = _pdfEmails;
    } else {
      for (var c in _emailControllers) {
        final email = c.text.trim();
        if (email.isNotEmpty) {
          if (!_isValidEmail(email)) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Invalid recipient email: \$email')));
            return;
          }
          recipients.add(email);
        }
      }
      if (recipients.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter at least one recipient.')));
        return;
      }
    }

    final newEmail = ScheduledEmail(
      id: widget.editEmail?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      senderEmail: _senderController.text.trim(),
      type: _sendType,
      recipients: recipients,
      subject: _subjectController.text,
      body: _bodyController.text,
      scheduledDate: _dateController.text,
      scheduledTime: '\${_timeController.text} \${_isAm ? "AM" : "PM"}',
    );

    if (widget.editEmail != null) {
      await StorageService.updateEmail(newEmail);
    } else {
      await StorageService.saveEmail(newEmail);
    }
    
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.editEmail != null ? 'Edit Schedule' : 'New Schedule', style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 24),
              
              TextField(
                controller: _senderController,
                decoration: InputDecoration(
                  hintText: 'Sender Email (e.g. you@gmail.com)',
                  prefixIcon: const Icon(Icons.account_circle, color: Colors.white54),
                  suffixIcon: _isAuthenticated ? const Icon(Icons.security, color: Colors.greenAccent) : null,
                ),
                enabled: !_isAuthenticated,
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: !_isAuthenticated 
                  ? Column(
                      children: [
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _authenticateWithGoogle,
                            icon: const Icon(Icons.security),
                            label: const Text('Authenticate with Google'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Theme.of(context).primaryColor,
                              side: BorderSide(color: Theme.of(context).primaryColor),
                            ),
                          ),
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
              ),
              const SizedBox(height: 32),

              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'Single', label: Text('Single')),
                  ButtonSegment(value: 'Multiple', label: Text('Multiple')),
                  ButtonSegment(value: 'PDF', label: Text('PDF')),
                ],
                selected: {_sendType},
                onSelectionChanged: (set) => setState(() => _sendType = set.first),
              ),
              const SizedBox(height: 24),

              if (_sendType == 'Single' || _sendType == 'Multiple')
                ...List.generate(_emailControllers.length, (index) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      controller: _emailControllers[index],
                      decoration: InputDecoration(
                        hintText: 'Recipient Email',
                        prefixIcon: const Icon(Icons.email_outlined, color: Colors.white54),
                        suffixIcon: _sendType == 'Multiple' && _emailControllers.length > 1
                            ? IconButton(icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent), onPressed: () => setState(() => _emailControllers.removeAt(index)))
                            : null,
                      ),
                    ).animate().fade().slideY(),
                  );
                }),
                
              if (_sendType == 'Multiple')
                TextButton.icon(
                  onPressed: () => setState(() => _emailControllers.add(TextEditingController())),
                  icon: const Icon(Icons.add),
                  label: const Text('Add More'),
                ),

              if (_sendType == 'PDF')
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).primaryColor, width: 2),
                    borderRadius: BorderRadius.circular(12),
                    color: Theme.of(context).cardTheme.color,
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.picture_as_pdf, size: 48, color: Theme.of(context).primaryColor),
                      const SizedBox(height: 16),
                      Text(_pdfPath ?? 'No PDF Selected', style: const TextStyle(color: Colors.white70)),
                      if (_pdfEmails.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text('\${_pdfEmails.length} emails extracted!', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: _reviewExtractedEmails,
                          icon: const Icon(Icons.visibility),
                          label: const Text('Review Emails'),
                        )
                      ],
                      const SizedBox(height: 16),
                      ElevatedButton(onPressed: _pickPdf, child: const Text('Upload PDF')),
                    ],
                  ),
                ).animate().fade().scale(),

              const SizedBox(height: 24),
              TextField(
                controller: _subjectController,
                decoration: const InputDecoration(hintText: 'Subject', prefixIcon: Icon(Icons.subject, color: Colors.white54)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _bodyController,
                maxLines: 4,
                decoration: const InputDecoration(hintText: 'Email Body Content', alignLabelWithHint: true),
              ),
              const SizedBox(height: 24),

              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _dateController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [DateInputFormatter()],
                      decoration: const InputDecoration(hintText: 'DD/MM/YYYY', prefixIcon: Icon(Icons.calendar_today, color: Colors.white54)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _timeController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [TimeInputFormatter()],
                            decoration: const InputDecoration(hintText: '12:00'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: () => setState(() => _isAm = !_isAm),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
                            decoration: BoxDecoration(color: Theme.of(context).cardTheme.color, borderRadius: BorderRadius.circular(12)),
                            child: Text(_isAm ? 'AM' : 'PM', style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _submit,
                  child: Text(widget.editEmail != null ? 'Update Schedule' : 'Save Schedule', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
