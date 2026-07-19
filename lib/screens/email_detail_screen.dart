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
  List<ScheduledEmail> _groups = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    final allEmails = await StorageService.getEmails();
    setState(() {
      _groups = allEmails.where((e) => (e.type == 'Multiple' || e.type == 'PDF') && (e.scheduleName != null && e.scheduleName!.isNotEmpty)).toList();
      _isLoading = false;
    });
  }

  Future<void> _deleteGroup(String id) async {
    await StorageService.deleteEmail(id);
    _loadGroups();
  }

  void _showRecipients(ScheduledEmail group) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: Colors.white,
          title: Text(group.scheduleName ?? 'Group', style: const TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: group.recipients.length,
              itemBuilder: (context, i) {
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.email_outlined, color: AppTheme.primaryBlue, size: 20),
                  title: Text(group.recipients[i], style: const TextStyle(fontFamily: 'Inter', fontSize: 14)),
                );
              }
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close', style: TextStyle(color: AppTheme.primaryBlue)),
            )
          ],
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Email Groups', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold, color: Colors.black)),
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : _groups.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.group_off_outlined, size: 60, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text('No saved groups found.', style: TextStyle(fontFamily: 'Inter', fontSize: 16, color: Colors.grey.shade600)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: _groups.length,
              itemBuilder: (context, index) {
                final group = _groups[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                  child: ListTile(
                    title: Text(group.scheduleName ?? 'Unnamed Group', style: const TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold, color: AppTheme.textDark)),
                    subtitle: Text('${group.recipients.length} Recipients • ${group.type}', style: TextStyle(fontFamily: 'Inter', color: Colors.grey.shade600)),
                    onTap: () => _showRecipients(group),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _deleteGroup(group.id),
                    ),
                  ),
                );
              }
            ),
    );
  }
}
