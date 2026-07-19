import 'dart:async';
import 'package:flutter/material.dart';
import '../models/scheduled_email.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

class EmailDetailScreen extends StatefulWidget {
  const EmailDetailScreen({Key? key}) : super(key: key);
  @override
  State<EmailDetailScreen> createState() => _EmailDetailScreenState();
}

class _EmailDetailScreenState extends State<EmailDetailScreen> {
  List<ScheduledEmail> _allEmails = [];
  bool _isLoading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadGroups();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) => _loadGroups());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadGroups() async {
    final allEmails = await StorageService.getEmails();
    if (!mounted) return;
    setState(() { _allEmails = allEmails; _isLoading = false; });
  }

  Future<void> _deleteGroup(String id) async {
    await StorageService.deleteEmail(id);
    _loadGroups();
  }

  Color _statusColor(String status) {
    if (status == 'Success') return AppTheme.successGreen;
    if (status == 'In Process') return AppTheme.primaryBlue;
    if (status == 'Failed') return AppTheme.errorRed;
    return AppTheme.warningAmber;
  }

  IconData _statusIcon(String status) {
    if (status == 'Success') return Icons.check_circle_rounded;
    if (status == 'In Process') return Icons.sync_rounded;
    if (status == 'Failed') return Icons.cancel_rounded;
    return Icons.schedule_rounded;
  }

  Color _typeColor(String type) {
    if (type == 'PDF') return Colors.deepOrange;
    if (type == 'Multiple') return AppTheme.primaryBlue;
    return AppTheme.successGreen;
  }

  void _showRecipients(ScheduledEmail email) {
    final name = (email.scheduleName != null && email.scheduleName!.isNotEmpty)
        ? email.scheduleName! : email.subject.isNotEmpty ? email.subject : 'Schedule Details';
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 12, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text(name, style: const TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold, fontSize: 18, color: AppTheme.textDark))),
              IconButton(icon: const Icon(Icons.close, color: AppTheme.textMid, size: 20), onPressed: () => Navigator.pop(context)),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: _typeColor(email.type).withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
                child: Text(email.type, style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: _typeColor(email.type), fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              Text(email.scheduledDate + '  |  ' + email.scheduledTime, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.textLight)),
            ]),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Divider(height: 20),
              Text('Recipients (' + email.recipients.length.toString() + ')',
                  style: const TextStyle(fontFamily: 'Outfit', fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.primaryBlue)),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: email.recipients.length,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      Icon(_statusIcon(email.status), color: _statusColor(email.status), size: 18),
                      const SizedBox(width: 10),
                      Expanded(child: Text(email.recipients[i], style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.textDark))),
                    ]),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close', style: TextStyle(color: AppTheme.primaryBlue, fontFamily: 'Inter', fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgWhite,
      appBar: AppBar(
        title: const Text('Email Groups', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold, color: AppTheme.textDark)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.textDark),
        surfaceTintColor: Colors.transparent,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _allEmails.isEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.group_off_outlined, size: 60, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  const Text('No scheduled emails yet.', style: TextStyle(fontFamily: 'Inter', fontSize: 16, color: Color(0xFF9E9E9E))),
                ]))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _allEmails.length,
                  itemBuilder: (context, index) {
                    final email = _allEmails[index];
                    final displayName = (email.scheduleName != null && email.scheduleName!.isNotEmpty)
                        ? email.scheduleName! : email.subject.isNotEmpty ? email.subject : '(No Name)';
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                      color: Colors.white,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => _showRecipients(email),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppTheme.divider),
                          ),
                          child: Row(children: [
                            Container(
                              width: 44, height: 44,
                              decoration: BoxDecoration(color: _typeColor(email.type).withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                              child: Icon(email.type == 'PDF' ? Icons.picture_as_pdf_rounded : Icons.email_rounded, color: _typeColor(email.type), size: 20),
                            ),
                            const SizedBox(width: 14),
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(displayName, style: const TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w600, fontSize: 15, color: AppTheme.textDark), maxLines: 1, overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 4),
                                Row(children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(color: _typeColor(email.type).withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                                    child: Text(email.type, style: TextStyle(fontFamily: 'Inter', fontSize: 10, color: _typeColor(email.type), fontWeight: FontWeight.bold)),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(child: Text(email.recipients.length.toString() + ' recipient' + (email.recipients.length == 1 ? '' : 's') + '  |  ' + email.scheduledDate,
                                    style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.textLight), maxLines: 1, overflow: TextOverflow.ellipsis)),
                                ]),
                              ],
                            )),
                            const SizedBox(width: 8),
                            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(color: _statusColor(email.status).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                                child: Text(email.status, style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: _statusColor(email.status), fontWeight: FontWeight.w600)),
                              ),
                              const SizedBox(height: 6),
                              GestureDetector(
                                onTap: () => _deleteGroup(email.id),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(color: AppTheme.errorRed.withOpacity(0.08), borderRadius: BorderRadius.circular(6)),
                                  child: const Icon(Icons.delete_rounded, color: AppTheme.errorRed, size: 16),
                                ),
                              ),
                            ]),
                          ]),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
