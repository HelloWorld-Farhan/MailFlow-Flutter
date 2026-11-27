import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/template_item.dart';
import '../services/app_config.dart';
import '../services/backend_service.dart';
import '../services/dispatcher.dart';
import '../services/storage_service.dart';
import 'package:flutter/services.dart' as import_services;

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<TemplateItem> _subjects = [];
  List<TemplateItem> _bodies = [];

  final _supabaseUrlCtrl = TextEditingController();
  final _supabaseAnonKeyCtrl = TextEditingController();
  final _backendUrlCtrl = TextEditingController();
  final _backendSecretCtrl = TextEditingController();
  final _googleWebClientIdCtrl = TextEditingController();
  bool _testingBackend = false;
  String? _backendStatusMsg;
  bool _backendStatusOk = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _supabaseUrlCtrl.text = AppConfig.supabaseUrl;
    _supabaseAnonKeyCtrl.text = AppConfig.supabaseAnonKey;
    _backendUrlCtrl.text = AppConfig.backendApiUrl;
    _backendSecretCtrl.text = AppConfig.backendApiSecret;
    _googleWebClientIdCtrl.text = AppConfig.googleWebClientId;
    _loadTemplates();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _supabaseUrlCtrl.dispose();
    _supabaseAnonKeyCtrl.dispose();
    _backendUrlCtrl.dispose();
    _backendSecretCtrl.dispose();
    _googleWebClientIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTemplates() async {
    final templates = await StorageService.getTemplates();
    setState(() {
      _subjects = templates.where((t) => t.type == 'Subject').toList();
      _bodies = templates.where((t) => t.type == 'Body').toList();
    });
  }

  void _showTemplateModal({TemplateItem? editItem, required String type}) {
    final nameController = TextEditingController(text: editItem?.name);
    final contentController = TextEditingController(text: editItem?.content);

    bool _containsHtml(String text) {
      return RegExp(r'<[a-zA-Z][^>]*>').hasMatch(text);
    }

    showDialog(
      context: context,
      builder: (context) {
        String? bodyError;
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        editItem == null ? 'New $type' : 'Edit $type',
                        style: const TextStyle(fontFamily: 'Outfit', fontSize: 20, fontWeight: FontWeight.w700, color: AppTheme.textDark),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: nameController,
                        decoration: InputDecoration(
                          labelText: 'Template Name',
                          labelStyle: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.textMid),
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                          filled: true,
                          fillColor: AppTheme.primaryBlue.withOpacity(0.04),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.primaryBlue.withOpacity(0.2))),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.primaryBlue.withOpacity(0.2))),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primaryBlue, width: 2)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: contentController,
                        minLines: type == 'Body' ? 8 : 4,
                        maxLines: type == 'Body' ? 15 : 8,
                        onChanged: (_) {
                          if (type == 'Body' && bodyError != null) {
                            setModalState(() => bodyError = null);
                          }
                        },
                        decoration: InputDecoration(
                          labelText: type == 'Subject' ? 'Subject Line' : 'Email Body (HTML)',
                          hintText: type == 'Subject' ? 'Enter subject template...' : 'Enter HTML body... (e.g. <b>Hello</b><br>World)',
                          labelStyle: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.textMid),
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                          alignLabelWithHint: true,
                          filled: true,
                          fillColor: AppTheme.primaryBlue.withOpacity(0.04),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.primaryBlue.withOpacity(0.2))),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: (type == 'Body' && bodyError != null) ? AppTheme.errorRed : AppTheme.primaryBlue.withOpacity(0.2)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: (type == 'Body' && bodyError != null) ? AppTheme.errorRed : AppTheme.primaryBlue, width: 2),
                          ),
                        ),
                      ),
                      if (type == 'Body' && bodyError != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppTheme.errorRed.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.errorRed.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline_rounded, color: AppTheme.errorRed, size: 16),
                              const SizedBox(width: 8),
                              Expanded(child: Text(bodyError!, style: const TextStyle(color: AppTheme.errorRed, fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600))),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryBlue,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            elevation: 0,
                          ),
                          onPressed: () async {
                            final name = nameController.text.trim();
                            final content = contentController.text;
                            if (name.isEmpty || content.trim().isEmpty) return;

                            // HTML validation for Body only
                            if (type == 'Body' && !_containsHtml(content)) {
                              setModalState(() => bodyError = 'Body must contain valid HTML tags (e.g. <p>, <b>, <br>).');
                              return;
                            }

                            final template = TemplateItem(
                              id: editItem?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
                              name: name,
                              content: content,
                              type: type,
                            );

                            if (editItem != null) {
                              await StorageService.updateTemplate(template);
                            } else {
                              await StorageService.saveTemplate(template);
                            }

                            if (mounted) {
                              Navigator.pop(context);
                              _loadTemplates();
                            }
                          },
                          child: Text('Save $type', style: const TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }


  Future<void> _deleteTemplate(String id) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Deletion', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w600)),
        content: const Text('Are you sure you want to delete this? This information will be permanently deleted and cannot be recovered.', style: TextStyle(fontFamily: 'Inter')),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(fontFamily: 'Inter', color: AppTheme.textMid)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorRed, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(fontFamily: 'Inter', color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await StorageService.deleteTemplate(id);
    _loadTemplates();
  }

  Widget _buildList(List<TemplateItem> items, String type) {
    if (items.isEmpty) {
      return Center(
        child: Text('No saved ${type.toLowerCase()} templates yet.', style: const TextStyle(color: AppTheme.textLight)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return Card(
          elevation: 0,
          color: AppTheme.bgSurface,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            title: Text(item.name, style: const TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w600, color: AppTheme.textDark)),
            subtitle: Text(item.content, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'Inter', color: AppTheme.textMid)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.copy_rounded, color: AppTheme.textMid),
                  onPressed: () {
                    import_services.Clipboard.setData(import_services.ClipboardData(text: item.content));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Content copied to clipboard', style: TextStyle(fontFamily: 'Inter'))),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.edit_rounded, color: AppTheme.primaryBlue),
                  onPressed: () => _showTemplateModal(editItem: item, type: type),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_rounded, color: AppTheme.errorRed),
                  onPressed: () => _deleteTemplate(item.id),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(color: AppTheme.textDark, fontFamily: 'Outfit', fontWeight: FontWeight.w700)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.textDark),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primaryBlue,
          unselectedLabelColor: AppTheme.textMid,
          indicatorColor: AppTheme.primaryBlue,
          tabs: const [
            Tab(text: 'Subjects'),
            Tab(text: 'Bodies'),
            Tab(text: 'Backend'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildList(_subjects, 'Subject'),
          _buildList(_bodies, 'Body'),
          _buildBackendTab(),
        ],
      ),
      floatingActionButton: _tabController.index < 2
          ? FloatingActionButton.extended(
              onPressed: () => _showTemplateModal(type: _tabController.index == 0 ? 'Subject' : 'Body'),
              label: const Text('New Template', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w600)),
              icon: const Icon(Icons.add_rounded),
              backgroundColor: AppTheme.primaryBlue,
            )
          : null,
    );
  }

  Future<void> _saveBackendConfig({bool testHealth = false}) async {
    setState(() {
      _testingBackend = true;
      _backendStatusMsg = null;
    });
    await AppConfig.saveOverrides(
      supabaseUrlValue: _supabaseUrlCtrl.text,
      supabaseAnonKeyValue: _supabaseAnonKeyCtrl.text,
      backendApiUrlValue: _backendUrlCtrl.text,
      backendApiSecretValue: _backendSecretCtrl.text,
      googleWebClientIdValue: _googleWebClientIdCtrl.text,
    );
    if (AppConfig.isBackendEnabled) {
      BackgroundDispatcher.stop();
      await BackendService.startRealtime();
    } else {
      await BackendService.stopRealtime();
    }

    if (testHealth) {
      try {
        final health = await BackendService.checkHealth();
        if (mounted) {
          setState(() {
            _backendStatusOk = true;
            _backendStatusMsg = 'Connected! Max ${health['maxDailyPerSender'] ?? 50}/day per sender.';
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _backendStatusOk = false;
            _backendStatusMsg = e.toString().replaceFirst('Exception: ', '');
          });
        }
      }
    } else if (mounted) {
      setState(() {
        _backendStatusOk = AppConfig.isBackendEnabled;
        _backendStatusMsg = AppConfig.isBackendEnabled
            ? 'Backend configuration saved & Realtime started.'
            : 'Saved. Fill all Backend & Supabase fields to enable cloud scheduling.';
      });
    }
    if (mounted) setState(() => _testingBackend = false);
  }

  Widget _buildBackendTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.primaryBlue.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.primaryBlue.withValues(alpha: 0.2)),
          ),
          child: const Text(
            'Cloudflare Worker + Supabase Realtime runs campaigns 24/7 with parallel per-sender dispatch and zero polling. Values stay local on your device.',
            style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.textDark),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _backendUrlCtrl,
          decoration: const InputDecoration(labelText: 'Backend Worker URL', hintText: 'https://...workers.dev'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _backendSecretCtrl,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Backend API Secret'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _supabaseUrlCtrl,
          decoration: const InputDecoration(labelText: 'Supabase Project URL', hintText: 'https://...supabase.co'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _supabaseAnonKeyCtrl,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Supabase Anon Key'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _googleWebClientIdCtrl,
          decoration: const InputDecoration(labelText: 'Google OAuth Web Client ID'),
        ),
        if (_backendStatusMsg != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (_backendStatusOk ? AppTheme.successGreen : AppTheme.errorRed).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: (_backendStatusOk ? AppTheme.successGreen : AppTheme.errorRed).withValues(alpha: 0.3)),
            ),
            child: Text(
              _backendStatusMsg!,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _backendStatusOk ? AppTheme.successGreen : AppTheme.errorRed,
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _testingBackend ? null : () => _saveBackendConfig(testHealth: true),
                child: Text(_testingBackend ? 'Testing...' : 'Test Connection'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _testingBackend ? null : () => _saveBackendConfig(testHealth: false),
                child: const Text('Save & Connect'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
