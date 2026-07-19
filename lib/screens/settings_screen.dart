import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/template_item.dart';
import '../services/storage_service.dart';

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
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildList(_subjects, 'Subject'),
          _buildList(_bodies, 'Body'),
        ],
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
