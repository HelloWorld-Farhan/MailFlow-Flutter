import 'package:flutter/material.dart';
import 'package:flutter/services.dart' as import_services;
import 'package:flutter_animate/flutter_animate.dart';
import '../models/template_item.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<TemplateItem> _subjects = [];
  List<TemplateItem> _bodies = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadTemplates();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadTemplates() async {
    final templates = await StorageService.getTemplates();
    if (!mounted) return;
    setState(() {
      _subjects = templates.where((t) => t.type == 'Subject').toList();
      _bodies = templates.where((t) => t.type == 'Body').toList();
    });
  }

  void _showTemplateModal({TemplateItem? editItem, required String type}) {
    final nameController = TextEditingController(text: editItem?.name);
    final contentController = TextEditingController(text: editItem?.content);

    bool containsHtml(String text) {
      return RegExp(r'<[a-zA-Z][^>]*>').hasMatch(text);
    }

    showBlurredDialog(
      context: context,
      builder: (dialogContext) {
        String? bodyError;
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog(
              backgroundColor: AppTheme.cardBg(context),
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
                        style: TextStyle(fontFamily: 'Outfit', fontSize: 20, fontWeight: FontWeight.w700, color: AppTheme.textPrimary(context)),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: nameController,
                        decoration: InputDecoration(
                          labelText: 'Template Name',
                          labelStyle: TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.textSecondary(context)),
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                          filled: true,
                          fillColor: AppTheme.inputBg(context),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.primaryBlue.withValues(alpha: 0.25))),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.primaryBlue.withValues(alpha: 0.25))),
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
                          labelStyle: TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.textSecondary(context)),
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                          alignLabelWithHint: true,
                          filled: true,
                          fillColor: AppTheme.inputBg(context),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.primaryBlue.withValues(alpha: 0.2))),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: (type == 'Body' && bodyError != null) ? AppTheme.errorRed : AppTheme.primaryBlue.withValues(alpha: 0.2)),
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
                            color: AppTheme.errorRed.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.errorRed.withValues(alpha: 0.3)),
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

                            if (type == 'Body' && !containsHtml(content)) {
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

                            if (!dialogContext.mounted) return;
                            Navigator.pop(dialogContext);
                            _loadTemplates();
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
    final bool? confirm = await showBlurredDialog<bool>(
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
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GlassContainer(
            borderRadius: 16,
            blurSigma: 10,
            color: AppTheme.surfaceBg(context).withValues(alpha: 0.88),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              title: Text(item.name, style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w600, color: AppTheme.textPrimary(context))),
              subtitle: Text(item.content, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: 'Inter', color: AppTheme.textSecondary(context))),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(Icons.copy_rounded, color: AppTheme.textSecondary(context)),
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
          ).animate().fade(duration: 240.ms).blur(begin: const Offset(5, 5), end: Offset.zero, duration: 240.ms),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.isDark(context) ? AppTheme.lightBlue : AppTheme.primaryBlue;
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg(context),
      appBar: AppBar(
        title: Text('Settings & Templates', style: TextStyle(color: AppTheme.textPrimary(context), fontFamily: 'Outfit', fontWeight: FontWeight.w700)),
        backgroundColor: Colors.transparent,
        flexibleSpace: buildGlassAppBarBackground(),
        elevation: 0,
        iconTheme: IconThemeData(color: AppTheme.textPrimary(context)),
        bottom: TabBar(
          controller: _tabController,
          labelColor: accent,
          unselectedLabelColor: AppTheme.textSecondary(context),
          indicatorColor: accent,
          tabs: const [
            Tab(text: 'Subjects'),
            Tab(text: 'Bodies'),
          ],
        ),
      ),
      body: ResponsiveCenter(
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildList(_subjects, 'Subject'),
            _buildList(_bodies, 'Body'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showTemplateModal(type: _tabController.index == 0 ? 'Subject' : 'Body'),
        label: const Text('New Template', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w600)),
        icon: const Icon(Icons.add_rounded),
        backgroundColor: AppTheme.primaryBlue,
      ),
    );
  }
}
