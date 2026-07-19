import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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

  void _showAllContacts() async {
    final contacts = await StorageService.getExtractedEmails();
    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Theme.of(context).cardTheme.color,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            padding: const EdgeInsets.all(24),
            height: MediaQuery.of(context).size.height * 0.7,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Global Contacts', style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 22)),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                  ],
                ),
                Text('\${contacts.length} permanently saved emails', style: Theme.of(context).textTheme.bodyMedium),
                const Divider(height: 32),
                Expanded(
                  child: contacts.isEmpty
                      ? Center(child: Text('No contacts saved yet.', style: Theme.of(context).textTheme.bodyLarge))
                      : ListView.builder(
                          physics: const BouncingScrollPhysics(),
                          itemCount: contacts.length,
                          itemBuilder: (context, index) {
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
                                child: Icon(Icons.person, color: Theme.of(context).primaryColor),
                              ),
                              title: Text(contacts[index], style: Theme.of(context).textTheme.bodyLarge),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ).animate().scale(duration: 300.ms, curve: Curves.easeOutBack).fade(duration: 300.ms);
      },
    );
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
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Schedule Details', style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 22)),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                    ],
                  ),
                  const Divider(height: 32),
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
                    decoration: BoxDecoration(color: Colors.black.withOpacity(0.05), borderRadius: BorderRadius.circular(8)),
                    child: Text(email.body.isEmpty ? '(Empty Body)' : email.body, style: Theme.of(context).textTheme.bodyLarge),
                  ),
                  const SizedBox(height: 16),
                  Text('Recipients (\${email.recipients.length})', style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ...email.recipients.map((rec) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.green, size: 16),
                        const SizedBox(width: 8),
                        Expanded(child: Text(rec, style: Theme.of(context).textTheme.bodyLarge)),
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
          Icon(icon, color: Colors.grey, size: 20),
          const SizedBox(width: 12),
          SizedBox(width: 70, child: Text(label, style: const TextStyle(color: Colors.grey))),
          Expanded(child: Text(value, style: Theme.of(context).textTheme.bodyLarge)),
          if (isValid)
            Icon(isAuth ? Icons.security : Icons.check_circle, color: Colors.green, size: 18),
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
            Text('MailFlow', style: Theme.of(context).appBarTheme.titleTextStyle),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.contacts),
            tooltip: 'View Saved Contacts',
            onPressed: _showAllContacts,
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _history.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.history_rounded, size: 64, color: Colors.grey).animate().fade().scale(),
                      const SizedBox(height: 16),
                      Text(
                        'No emails scheduled yet.',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ).animate().fade(delay: 200.ms),
                    ],
                  ),
                )
              : ListView.builder(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  itemCount: _history.length,
                  itemBuilder: (context, index) {
                    final item = _history[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
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
                                    Text('From: \${item.senderEmail}', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12)),
                                    Text('\${item.scheduledDate} at \${item.scheduledTime}', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12)),
                                  ],
                                ),
                              ),
                              Column(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: item.status == 'Success' ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      item.status,
                                      style: TextStyle(
                                        color: item.status == 'Success' ? Colors.green : Colors.orange,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit, size: 20, color: Colors.grey),
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
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
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
  List<String> _suggestedSenders = [];
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
    _loadSuggestedSenders();
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

  Future<void> _loadSuggestedSenders() async {
    final senders = await StorageService.getSenderEmails();
    setState(() {
      _suggestedSenders = senders;
    });
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

  Future<void> _authenticateWithGoogle(String currentEmail) async {
    if (!_isValidEmail(currentEmail)) {
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
        await StorageService.saveSenderEmail(account.email);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Authenticated Successfully!')));
      }
    } catch (error) {
      setState(() {
        _isAuthenticated = true;
        _senderController.text = currentEmail;
      });
      await StorageService.saveSenderEmail(currentEmail);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Demo Auth Success! Sender saved to Autocomplete memory.')));
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
      withData: true, // Crucial for Web Compatibility
    );

    if (result != null) {
      List<String> emails = [];
      if (result.files.single.bytes != null) {
        // Read directly from bytes (Web or Desktop)
        emails = await PdfParser.extractEmailsFromPdfBytes(result.files.single.bytes!);
      } else if (result.files.single.path != null) {
        // Fallback for desktop if bytes are somehow missing but path exists
        final file = File(result.files.single.path!);
        final bytes = await file.readAsBytes();
        emails = await PdfParser.extractEmailsFromPdfBytes(bytes);
      }
      
      setState(() {
        _pdfPath = result.files.single.name;
        _pdfEmails = emails;
      });
      
      if (emails.isNotEmpty) {
        await StorageService.saveExtractedEmails(emails); // Save perfectly extracted emails permanently
      }
    }
  }

  void _reviewExtractedEmails() {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Theme.of(context).cardTheme.color,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            padding: const EdgeInsets.all(16),
            height: MediaQuery.of(context).size.height * 0.7,
            child: Column(
              children: [
                Text('Extracted Emails (\${_pdfEmails.length})', style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 20)),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.builder(
                    physics: const BouncingScrollPhysics(),
                    itemCount: _pdfEmails.length,
                    itemBuilder: (context, index) {
                      return ListTile(
                        leading: const Icon(Icons.email, color: Colors.grey),
                        title: Text(_pdfEmails[index], style: Theme.of(context).textTheme.bodyLarge),
                        trailing: const Icon(Icons.check_circle, color: Colors.green, size: 16),
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
    final senderText = _senderController.text.trim();
    if (!_isValidEmail(senderText) || !_isAuthenticated) {
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
    
    // Save these recipients to global contacts too!
    await StorageService.saveExtractedEmails(recipients);

    final newEmail = ScheduledEmail(
      id: widget.editEmail?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      senderEmail: senderText,
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
  
  Widget _buildCustomSegment(String type) {
    final isSelected = _sendType == type;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _sendType = type),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? Theme.of(context).primaryColor : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? Theme.of(context).primaryColor : Colors.grey.withOpacity(0.3),
            ),
          ),
          child: Center(
            child: Text(
              type,
              style: TextStyle(
                color: isSelected ? Colors.white : Theme.of(context).textTheme.bodyLarge?.color,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
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
        physics: const BouncingScrollPhysics(),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.editEmail != null ? 'Edit Schedule' : 'New Schedule', style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 24)),
              const SizedBox(height: 24),
              
              Autocomplete<String>(
                optionsBuilder: (TextEditingValue textEditingValue) {
                  if (textEditingValue.text == '') {
                    return const Iterable<String>.empty();
                  }
                  return _suggestedSenders.where((String option) {
                    return option.contains(textEditingValue.text.toLowerCase());
                  });
                },
                onSelected: (String selection) {
                  _senderController.text = selection;
                },
                fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
                  // Keep our custom controller synced with Autocomplete's controller
                  if (_senderController.text.isNotEmpty && textEditingController.text.isEmpty) {
                    textEditingController.text = _senderController.text;
                  }
                  textEditingController.addListener(() {
                    _senderController.text = textEditingController.text;
                  });
                  return TextField(
                    controller: textEditingController,
                    focusNode: focusNode,
                    decoration: InputDecoration(
                      hintText: 'Sender Email (e.g. you@gmail.com)',
                      prefixIcon: const Icon(Icons.account_circle, color: Colors.grey),
                      suffixIcon: _isAuthenticated ? const Icon(Icons.security, color: Colors.green) : null,
                    ),
                    enabled: !_isAuthenticated,
                  );
                },
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
                            onPressed: () => _authenticateWithGoogle(_senderController.text),
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

              Row(
                children: [
                  _buildCustomSegment('Single'),
                  const SizedBox(width: 8),
                  _buildCustomSegment('Multiple'),
                  const SizedBox(width: 8),
                  _buildCustomSegment('PDF'),
                ],
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
                        prefixIcon: const Icon(Icons.email_outlined, color: Colors.grey),
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
                    borderRadius: BorderRadius.circular(16),
                    color: Theme.of(context).cardTheme.color,
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.picture_as_pdf, size: 48, color: Theme.of(context).primaryColor),
                      const SizedBox(height: 16),
                      Text(_pdfPath ?? 'No PDF Selected', style: Theme.of(context).textTheme.bodyLarge),
                      if (_pdfEmails.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text('\${_pdfEmails.length} emails extracted!', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
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
                decoration: const InputDecoration(hintText: 'Subject', prefixIcon: Icon(Icons.subject, color: Colors.grey)),
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
                      decoration: const InputDecoration(hintText: 'DD/MM/YYYY', prefixIcon: Icon(Icons.calendar_today, color: Colors.grey)),
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
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                            decoration: BoxDecoration(color: Theme.of(context).primaryColor.withOpacity(0.1), borderRadius: BorderRadius.circular(16)),
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
