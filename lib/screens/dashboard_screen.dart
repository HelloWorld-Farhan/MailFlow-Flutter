import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
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

  void _openScheduleModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _ScheduleModal(),
    ).then((_) {
      // Refresh history when modal closes
      _loadHistory();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mail_outline_rounded, color: Theme.of(context).primaryColor),
            const SizedBox(width: 8),
            const Text('MailFlow'),
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
                      Icon(Icons.history_rounded, size: 64, color: Colors.white24),
                      const SizedBox(height: 16),
                      Text(
                        'No emails scheduled yet.',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
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
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(context).primaryColor.withOpacity(0.2),
                          child: Icon(
                            item.type == 'PDF' ? Icons.picture_as_pdf : Icons.person,
                            color: Theme.of(context).primaryColor,
                          ),
                        ),
                        title: Text(item.subject.isNotEmpty ? item.subject : '(No Subject)', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('\${item.scheduledDate} at \${item.scheduledTime}\n\${item.recipients.length} Recipient(s) • [\${item.type}]'),
                        isThreeLine: true,
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: item.status == 'Success' ? Colors.green.withOpacity(0.2) : Colors.orange.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            item.status,
                            style: TextStyle(
                              color: item.status == 'Success' ? Colors.greenAccent : Colors.orangeAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openScheduleModal,
        icon: const Icon(Icons.add),
        label: const Text('Schedule Email'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
    );
  }
}

class _ScheduleModal extends StatefulWidget {
  const _ScheduleModal();

  @override
  State<_ScheduleModal> createState() => _ScheduleModalState();
}

class _ScheduleModalState extends State<_ScheduleModal> {
  String _sendType = 'Single';
  
  // Single/Multiple logic
  final List<TextEditingController> _emailControllers = [TextEditingController()];
  
  // PDF logic
  String? _pdfPath;
  List<String> _pdfEmails = [];

  // Content logic
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _bodyController = TextEditingController();
  
  // Date/Time logic
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _timeController = TextEditingController();
  bool _isAm = true;

  @override
  void dispose() {
    for (var c in _emailControllers) { c.dispose(); }
    _subjectController.dispose();
    _bodyController.dispose();
    _dateController.dispose();
    _timeController.dispose();
    super.dispose();
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

  bool _isDateTimeValid(String dateString, String timeString, bool isAm) {
    if (dateString.length != 10 || timeString.length != 5) return false;
    try {
      int day = int.parse(dateString.substring(0, 2));
      int month = int.parse(dateString.substring(3, 5));
      int year = int.parse(dateString.substring(6, 10));
      
      int hour = int.parse(timeString.substring(0, 2));
      int minute = int.parse(timeString.substring(3, 5));
      
      // Convert to 24-hour format for correct DateTime comparison
      if (!isAm && hour != 12) hour += 12;
      if (isAm && hour == 12) hour = 0;
      
      DateTime entered = DateTime(year, month, day, hour, minute);
      DateTime now = DateTime.now();
      
      // Cannot schedule in the past
      return entered.isAfter(now);
    } catch (e) {
      return false;
    }
  }

  Future<void> _submit() async {
    if (_dateController.text.length != 10 || _timeController.text.length != 5) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter valid Date and Time')));
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
        if (c.text.trim().isNotEmpty) {
          recipients.add(c.text.trim());
        }
      }
      if (recipients.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter at least one recipient.')));
        return;
      }
    }

    final newEmail = ScheduledEmail(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: _sendType,
      recipients: recipients,
      subject: _subjectController.text,
      body: _bodyController.text,
      scheduledDate: _dateController.text,
      scheduledTime: '\${_timeController.text} \${_isAm ? "AM" : "PM"}',
    );

    await StorageService.saveEmail(newEmail);
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('New Schedule', style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 24),
            
            // TYPE
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

            // CONDITIONAL RECIPIENTS UI
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
                          ? IconButton(
                              icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
                              onPressed: () {
                                setState(() {
                                  _emailControllers.removeAt(index);
                                });
                              },
                            )
                          : null,
                    ),
                  ),
                );
              }),
              
            if (_sendType == 'Multiple')
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _emailControllers.add(TextEditingController());
                  });
                },
                icon: const Icon(Icons.add),
                label: const Text('Add More'),
              ),

            if (_sendType == 'PDF')
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).primaryColor, width: 2, style: BorderStyle.solid),
                  borderRadius: BorderRadius.circular(12),
                  color: Theme.of(context).cardTheme.color,
                ),
                child: Column(
                  children: [
                    Icon(Icons.picture_as_pdf, size: 48, color: Theme.of(context).primaryColor),
                    const SizedBox(height: 16),
                    Text(_pdfPath ?? 'No PDF Selected', style: const TextStyle(color: Colors.white70)),
                    if (_pdfEmails.isNotEmpty)
                      Text('\${_pdfEmails.length} emails found!', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _pickPdf,
                      child: const Text('Upload PDF'),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 24),
            
            // CONTENT
            TextField(
              controller: _subjectController,
              decoration: const InputDecoration(
                hintText: 'Subject',
                prefixIcon: Icon(Icons.subject, color: Colors.white54),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bodyController,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Email Body Content',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 24),

            // DATE & TIME
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _dateController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [DateInputFormatter()],
                    decoration: const InputDecoration(
                      hintText: 'DD/MM/YYYY',
                      prefixIcon: Icon(Icons.calendar_today, color: Colors.white54),
                    ),
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
                          decoration: const InputDecoration(
                            hintText: '12:00',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () => setState(() => _isAm = !_isAm),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardTheme.color,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(_isAm ? 'AM' : 'PM', style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // SUBMIT
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _submit,
                child: Text('Save Schedule', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
