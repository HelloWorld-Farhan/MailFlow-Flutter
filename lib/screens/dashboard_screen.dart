import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/scheduled_email.dart';
import '../services/storage_service.dart';
import '../utils/date_input_formatter.dart';
import '../utils/time_input_formatter.dart';
import '../utils/pdf_parser.dart';
import '../theme/app_theme.dart';
import 'settings_screen.dart';
import 'email_detail_screen.dart';
import 'email_limit_screen.dart';
import '../models/template_item.dart';
import '../services/dispatcher.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  DASHBOARD SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<ScheduledEmail> _history = [];
  bool _isLoading = true;
  int _totalDailySent = 0;

  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _loadHistory();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final history = await StorageService.getEmails();
    final limitsMap = await StorageService.getAllDailyLimits();
    final totalSent = limitsMap.values.fold<int>(0, (sum, val) => sum + val);
    
    if (!mounted) return;
    setState(() {
      _history = history;
      _totalDailySent = totalSent;
      _isLoading = false;
    });
  }

  void _openScheduleModal({ScheduledEmail? existingEmail}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (context) => _ScheduleModal(editEmail: existingEmail),
    ).then((_) => _loadHistory());
  }

  void _openResendModal(ScheduledEmail email) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ResendModal(email: email),
    ).then((_) => _loadHistory());
  }

  Future<void> _deleteEmail(String id) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Deletion', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w600)),
        content: const Text('Are you sure you want to delete this schedule? If you delete it, the process will be terminated and this info will be unrecoverable.', style: TextStyle(fontFamily: 'Inter')),
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

    await StorageService.deleteEmail(id);
    _loadHistory();
  }

  Future<void> _stopEmail(ScheduledEmail email) async {
    await StorageService.updateEmail(email.copyWith(status: 'Paused'));
    _loadHistory();
  }

  Future<void> _resumeEmail(ScheduledEmail email) async {
    final sentCount = email.sentCount;
    final total = email.recipients.length;
    final batchSize = email.dailyLimit > 0 ? email.dailyLimit : 40;
    String newStatus;
    if (sentCount == 0) {
      newStatus = 'Scheduled';
    } else {
      final daysDone = (sentCount / batchSize).ceil();
      newStatus = 'Day $daysDone: $sentCount/$total sent';
    }
    await StorageService.updateEmail(email.copyWith(status: newStatus));
    _loadHistory();
  }

  void _showAllContacts() async {
    final contacts = await StorageService.getExtractedEmails();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => _ContactsDialog(contacts: contacts),
    );
  }

  void _showEmailDetails(ScheduledEmail email) {
    showDialog(
      context: context,
      builder: (context) => _DetailsDialog(email: email, primaryColor: AppTheme.primaryBlue),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgWhite,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── App Bar ───────────────────────────────────────────────────
          SliverAppBar(
            floating: true,
            backgroundColor: AppTheme.bgWhite,
            elevation: 0,
            surfaceTintColor: Colors.transparent,
            title: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.divider),
                  ),
                  child: Image.asset('assets/Logo.png'),
                ),
                const SizedBox(width: 10),
                const Text(
                  'MailFlow',
                  style: TextStyle(
                    fontFamily: 'Outfit', fontSize: 20, fontWeight: FontWeight.w700,
                    color: AppTheme.textDark,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.group_outlined, color: AppTheme.textMid),
                tooltip: 'Email Groups',
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EmailDetailScreen())),
              ),
              IconButton(
                icon: const Icon(Icons.data_usage_rounded, color: AppTheme.textMid),
                tooltip: 'Email Limits',
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EmailLimitScreen())),
              ),
              IconButton(
                icon: const Icon(Icons.settings_outlined, color: AppTheme.textMid),
                tooltip: 'Settings',
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
              ),
              const SizedBox(width: 8),
            ],
            bottom: const PreferredSize(
              preferredSize: Size.fromHeight(1),
              child: Divider(height: 1, color: AppTheme.divider),
            ),
          ),

          // ── Header hero card ──────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: GestureDetector(
                onTap: () => _openScheduleModal(),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.primaryBlue, AppTheme.accentBlue],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryBlue.withOpacity(0.28),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(Icons.send_rounded, color: Colors.white, size: 26),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Schedule New Email',
                              style: TextStyle(
                                color: Colors.white, fontFamily: 'Outfit',
                                fontSize: 18, fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Tap to set up sender, recipients,\nsubject, body & time',
                              style: TextStyle(
                                color: Colors.white70, fontFamily: 'Inter', fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.18),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
                      ),
                    ],
                  ),
                ).animate().fade(duration: 500.ms).slideY(begin: 0.3, end: 0.0),
              ),
            ),
          ),

          // ── Stats row ─────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  _StatChip(
                    icon: Icons.schedule_rounded,
                    label: 'Scheduled',
                    value: '${_history.where((e) => e.status == 'Scheduled' || e.status.startsWith('Day') || e.status == 'Paused').length}',
                    color: AppTheme.primaryBlue,
                  ),
                  const SizedBox(width: 12),
                  _StatChip(
                    icon: Icons.check_circle_rounded,
                    label: 'Sent',
                    value: '${_history.where((e) => e.status == 'Success').length}',
                    color: AppTheme.successGreen,
                  ),
                  const SizedBox(width: 12),
                  _StatChip(
                    icon: Icons.speed_rounded,
                    label: 'Total Per Day',
                    value: '$_totalDailySent',
                    color: _totalDailySent >= 150 ? AppTheme.errorRed : (_totalDailySent >= 100 ? AppTheme.warningAmber : AppTheme.textMid),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EmailLimitScreen())),
                  ),
                ],
              ).animate(delay: 200.ms).fade(duration: 400.ms),
            ),
          ),

          // ── Section title ─────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
              child: Row(
                children: [
                  const Text(
                    'Scheduled Emails',
                    style: TextStyle(
                      fontFamily: 'Outfit', fontSize: 17, fontWeight: FontWeight.w700,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_history.length} total',
                    style: const TextStyle(
                      fontFamily: 'Inter', fontSize: 13, color: AppTheme.textLight,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Email list ────────────────────────────────────────────────
          _isLoading
              ? const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              : _history.isEmpty
                  ? SliverFillRemaining(
                      child: _EmptyState(onTap: () => _openScheduleModal()),
                    )
                  : SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final item = _history[index];
                            return _EmailCard(
                              item: item,
                              index: index,
                              onTap: () => _showEmailDetails(item),
                              onEdit: () => _openScheduleModal(existingEmail: item),
                              onResend: () => _openResendModal(item),
                              onDelete: () => _deleteEmail(item.id),
                              onStop: () => _stopEmail(item),
                              onResume: () => _resumeEmail(item),
                            );
                          },
                          childCount: _history.length,
                        ),
                      ),
                    ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  HELPER WIDGETS
// ─────────────────────────────────────────────────────────────────────────────
class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color color;
  final VoidCallback? onTap;
  const _StatChip({required this.icon, required this.label, required this.value, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.07),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.15)),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 6),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value, style: TextStyle(color: color, fontFamily: 'Outfit', fontSize: 17, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(label, style: const TextStyle(color: AppTheme.textLight, fontFamily: 'Inter', fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onTap;
  const _EmptyState({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.mail_outline_rounded, size: 36, color: AppTheme.primaryBlue),
          ).animate().fade().scale(),
          const SizedBox(height: 20),
          const Text(
            'No emails scheduled yet',
            style: TextStyle(fontFamily: 'Outfit', fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.textDark),
          ).animate(delay: 100.ms).fade(),
          const SizedBox(height: 8),
          const Text(
            'Tap the card above to schedule\nyour first automated email',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.textLight),
          ).animate(delay: 200.ms).fade(),
          const SizedBox(height: 28),
          ElevatedButton.icon(
            onPressed: onTap,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Schedule Email'),
          ).animate(delay: 300.ms).fade().scale(),
        ],
      ),
    );
  }
}

class _EmailCard extends StatelessWidget {
  final ScheduledEmail item;
  final int index;
  final VoidCallback onTap, onEdit, onResend, onDelete, onStop, onResume;
  const _EmailCard({
    required this.item,
    required this.index,
    required this.onTap,
    required this.onEdit,
    required this.onResend,
    required this.onDelete,
    required this.onStop,
    required this.onResume,
  });

  Color _statusColor() {
    if (item.status == 'Success') return AppTheme.successGreen;
    if (item.status == 'Failed') return AppTheme.errorRed;
    if (item.status == 'Paused') return Colors.grey;
    if (item.status.startsWith('Doing') || item.status.startsWith('Sending') || item.status.startsWith('Day')) return AppTheme.primaryBlue;
    return AppTheme.warningAmber;
  }

  String _statusLabel() {
    if (item.status.startsWith('Day ')) return item.status;
    if (item.status.startsWith('Doing it...')) return item.status;
    return item.status;
  }

  bool get _isActive => item.status.startsWith('Doing') || item.status.startsWith('Sending') || item.status.startsWith('Day ');
  bool get _isPaused => item.status == 'Paused';
  bool get _isSuccess => item.status == 'Success';
  bool get _isFailed => item.status == 'Failed';
  bool get _isPdfCampaign => item.type == 'PDF' && item.dailyLimit > 0;

  @override
  Widget build(BuildContext context) {
    final clr = _statusColor();
    final total = item.recipients.length;
    final sent = item.sentCount;
    final progress = total > 0 ? sent / total : 0.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48, height: 48,
                      decoration: BoxDecoration(
                        color: clr.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        item.type == 'PDF' ? Icons.picture_as_pdf_rounded : Icons.email_rounded,
                        color: clr, size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (item.scheduleName != null && item.scheduleName!.isNotEmpty)
                                ? item.scheduleName!
                                : (item.subject.isNotEmpty ? item.subject : '(No Subject)'),
                            style: const TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w600, fontSize: 15, color: AppTheme.textDark),
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: AppTheme.primaryBlue.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                              child: Text(item.type, style: const TextStyle(fontFamily: 'Inter', fontSize: 10, color: AppTheme.primaryBlue, fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(width: 6),
                            Expanded(child: Text(
                              '${item.recipients.length} recipient${item.recipients.length == 1 ? '' : 's'}  •  ${item.scheduledDate}',
                              style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.textLight),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                            )),
                          ]),
                          const SizedBox(height: 2),
                          Text(item.scheduledTime, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.textMid)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: clr.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _statusLabel(),
                            style: TextStyle(color: clr, fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 10),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(children: [
                          if (_isSuccess || _isFailed)
                            _ActionBtn(icon: Icons.replay_circle_filled_rounded, color: AppTheme.primaryBlue, onTap: onResend),
                          if (!_isPdfCampaign && !_isSuccess && !_isFailed && !_isActive && !_isPaused)
                            _ActionBtn(icon: Icons.edit_rounded, color: AppTheme.primaryBlue, onTap: onEdit),
                          if (_isPdfCampaign && _isActive)
                            _ActionBtn(icon: Icons.pause_circle_rounded, color: AppTheme.warningAmber, onTap: onStop),
                          if (_isPdfCampaign && _isPaused)
                            _ActionBtn(icon: Icons.play_circle_rounded, color: AppTheme.successGreen, onTap: onResume),
                          const SizedBox(width: 4),
                          _ActionBtn(icon: Icons.delete_rounded, color: AppTheme.errorRed, onTap: onDelete),
                        ]),
                      ],
                    ),
                  ],
                ),
                // Progress bar for PDF campaigns
                if (_isPdfCampaign && !_isSuccess && total > 0) ...[
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('$sent / $total sent', style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: clr, fontWeight: FontWeight.w600)),
                      Text('${(progress * 100).toStringAsFixed(1)}%', style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: clr)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: clr.withOpacity(0.12),
                      valueColor: AlwaysStoppedAnimation<Color>(clr),
                      minHeight: 5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ).animate().fade(duration: 350.ms, delay: (index * 60).ms).slideX(begin: 0.05, end: 0),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32, height: 32,
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color, size: 16),
      ),
    );
  }
}

class _ContactsDialog extends StatelessWidget {
  final List<String> contacts;
  const _ContactsDialog({required this.contacts});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(24),
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Contacts', style: TextStyle(fontFamily: 'Outfit', fontSize: 20, fontWeight: FontWeight.w700, color: AppTheme.textDark)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close, color: AppTheme.textMid), onPressed: () => Navigator.pop(context)),
              ],
            ),
            Text('${contacts.length} saved', style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.textLight)),
            const SizedBox(height: 16),
            const Divider(color: AppTheme.divider),
            Expanded(
              child: contacts.isEmpty
                  ? const Center(child: Text('No contacts yet.', style: TextStyle(color: AppTheme.textLight)))
                  : ListView.separated(
                      physics: const BouncingScrollPhysics(),
                      itemCount: contacts.length,
                      separatorBuilder: (_, __) => const Divider(color: AppTheme.divider, height: 1),
                      itemBuilder: (_, i) => ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppTheme.primaryBlue.withOpacity(0.08),
                          child: Text(contacts[i][0].toUpperCase(), style: const TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.w700)),
                        ),
                        title: Text(contacts[i], style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.textDark)),
                      ),
                    ),
            ),
          ],
        ),
      ),
    ).animate().scale(duration: 250.ms, curve: Curves.easeOutBack).fade();
  }
}

class _DetailsDialog extends StatefulWidget {
  final ScheduledEmail email;
  final Color primaryColor;
  const _DetailsDialog({required this.email, required this.primaryColor});

  @override
  State<_DetailsDialog> createState() => _DetailsDialogState();
}

class _DetailsDialogState extends State<_DetailsDialog> {
  bool _showBody = false;
  bool _showRecipients = false;

  @override
  Widget build(BuildContext context) {
    final email = widget.email;
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (email.scheduleName != null && email.scheduleName!.isNotEmpty)
                              ? email.scheduleName!
                              : 'Schedule Details',
                          style: const TextStyle(fontFamily: 'Outfit', fontSize: 20, fontWeight: FontWeight.w700, color: AppTheme.textDark),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryBlue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            email.type,
                            style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.primaryBlue, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.close, color: AppTheme.textMid), onPressed: () => Navigator.pop(context)),
                ],
              ),
              const SizedBox(height: 16),
              _infoRow(Icons.account_circle_outlined, 'Sender', email.senderEmail),
              _infoRow(Icons.calendar_today_rounded, 'Date', email.scheduledDate),
              _infoRow(Icons.access_time_rounded, 'Time', email.scheduledTime),
              _infoRow(Icons.subject_rounded, 'Subject', email.subject.isEmpty ? '(No Subject)' : email.subject),
              const SizedBox(height: 8),
              // Collapsible Body Section
              GestureDetector(
                onTap: () => setState(() => _showBody = !_showBody),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.bgSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.divider),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.article_outlined, size: 18, color: AppTheme.primaryBlue),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Body',
                          style: TextStyle(fontFamily: 'Outfit', fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.primaryBlue),
                        ),
                      ),
                      Icon(
                        _showBody ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                        color: AppTheme.textMid, size: 20,
                      ),
                    ],
                  ),
                ),
              ),
              if (_showBody) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: AppTheme.bgSurface, borderRadius: BorderRadius.circular(12)),
                  child: Text(email.body.isEmpty ? '(Empty body)' : email.body, style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.textDark)),
                ),
              ],
              const SizedBox(height: 16),
              // Collapsible Recipients Section
              GestureDetector(
                onTap: () => setState(() => _showRecipients = !_showRecipients),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.group_rounded, size: 18, color: AppTheme.primaryBlue),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Recipients (${email.recipients.length})',
                          style: const TextStyle(fontFamily: 'Outfit', fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.primaryBlue),
                        ),
                      ),
                      Icon(
                        _showRecipients ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                        color: AppTheme.primaryBlue, size: 20,
                      ),
                    ],
                  ),
                ),
              ),
              if (_showRecipients) ...[
                const SizedBox(height: 8),
                Container(
                  height: MediaQuery.of(context).size.height * 0.35,
                  decoration: BoxDecoration(
                    color: AppTheme.bgSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.divider),
                  ),
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    physics: const BouncingScrollPhysics(),
                    itemCount: email.recipients.length,
                    itemBuilder: (ctx, idx) {
                      final r = email.recipients[idx];
                      final rStatus = email.recipientStatuses[r];
                      IconData icon;
                      Color color;
                      if (rStatus == 'sent' || (rStatus == null && email.status == 'Success')) {
                        icon = Icons.check_circle_rounded; color = AppTheme.successGreen;
                      } else if (rStatus == 'inProcess') {
                        icon = Icons.sync_rounded; color = AppTheme.primaryBlue;
                      } else if (rStatus == 'failed') {
                        icon = Icons.cancel_rounded; color = AppTheme.errorRed;
                      } else {
                        icon = Icons.radio_button_unchecked_rounded; color = AppTheme.textLight;
                      }
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          children: [
                            Container(
                              width: 28, height: 28,
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(icon, size: 16, color: color),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                r,
                                style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.textDark, height: 1.3),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ).animate().scale(duration: 250.ms, curve: Curves.easeOutBack).fade();
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppTheme.textLight),
          const SizedBox(width: 16),
          SizedBox(width: 72, child: Text(label, style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.textLight))),
          const SizedBox(width: 8),
          Expanded(child: Text(value, style: const TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textDark, height: 1.4))),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: const TextStyle(fontFamily: 'Outfit', fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.primaryBlue)),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
//  SCHEDULE MODAL
// ─────────────────────────────────────────────────────────────────────────────
class _ScheduleModal extends StatefulWidget {
  final ScheduledEmail? editEmail;
  const _ScheduleModal({this.editEmail});

  @override
  State<_ScheduleModal> createState() => _ScheduleModalState();
}

class _ScheduleModalState extends State<_ScheduleModal> {
  late String _sendType;
  final _senderController = TextEditingController();
  List<String> _suggestedSenders = [];
  bool _isAuthenticated = false;
  final _googleSignIn = GoogleSignIn(
    clientId: '787471915530-sg4ul6fm6s1paqabljmksi9c61cf4c77.apps.googleusercontent.com',
    scopes: ['email', 'https://www.googleapis.com/auth/gmail.send'],
  );

  final _scheduleNameController = TextEditingController();

  List<TemplateItem> _savedSubjects = [];
  List<TemplateItem> _savedBodies = [];
  bool _useSavedFormat = false;
  TemplateItem? _selectedSubject;
  TemplateItem? _selectedBody;

  List<TextEditingController> _emailControllers = [TextEditingController()];
  String? _pdfPath;
  List<String> _pdfEmails = [];

  final _subjectController = TextEditingController();
  final _bodyController = TextEditingController();
  final _dailyLimitController = TextEditingController(text: '40');
  final _dateController = TextEditingController();
  final _timeController = TextEditingController();
  bool _isAm = true;
  String? _senderMsg; bool _isSenderErr = false;
  String? _recipientMsg; bool _isRecipientErr = false;
  String? _dateMsg; bool _isDateErr = false;
  String? _scheduleNameMsg; bool _isScheduleNameErr = false;
  String? _subjectMsg; bool _isSubjectErr = false;
  String? _bodyMsg; bool _isBodyErr = false;
  String? _dailyLimitMsg; bool _isDailyLimitErr = false;
  bool _showPdfEmails = false;
  // For inline editing of PDF emails
  final List<TextEditingController> _pdfEmailControllers = [];
  bool _isPdfEmailEditing = false;
  int _currentSenderUsage = 0;
  // Per-date quota for selected sender + date
  int _scheduledForDate = 0;
  bool _dateQuotaFull = false;

  @override
  void initState() {
    super.initState();
    _loadSenders();
    _loadTemplates();
    _senderController.addListener(_onSenderChanged);
    _dateController.addListener(_onSenderChanged); // recompute when date changes
    if (widget.editEmail != null) {
      final e = widget.editEmail!;
      _sendType = e.type;
      _senderController.text = e.senderEmail;
      _isAuthenticated = true;
      _subjectController.text = e.subject;
      _bodyController.text = e.body;
      _dateController.text = e.scheduledDate;
      _isAm = e.scheduledTime.contains('AM');
      _timeController.text = e.scheduledTime.replaceAll(RegExp(r' AM| PM'), '');
      if (_sendType == 'Single' || _sendType == 'Multiple') {
        _emailControllers = e.recipients.map((r) => TextEditingController(text: r)).toList();
      } else if (_sendType == 'PDF') {
        _pdfPath = 'Extracted (${e.recipients.length} emails)';
        _pdfEmails = e.recipients;
        _dailyLimitController.text = e.dailyLimit > 0 ? e.dailyLimit.toString() : '40';
      }
      _scheduleNameController.text = e.scheduleName ?? '';
    } else {
      _sendType = 'Single';
    }
  }

  Future<void> _loadTemplates() async {
    final templates = await StorageService.getTemplates();
    setState(() {
      _savedSubjects = templates.where((t) => t.type == 'Subject').toList();
      _savedBodies = templates.where((t) => t.type == 'Body').toList();
    });
  }

  Future<void> _loadSenders() async {
    final s = await StorageService.getSenderEmails();
    setState(() => _suggestedSenders = s);
  }

  void _onSenderChanged() async {
    final email = _senderController.text.trim();
    final date = _dateController.text.trim();
    if (_isValidEmail(email)) {
      // Count total scheduled emails from this account overall
      final allEmails = await StorageService.getEmails();
      final scheduledCount = allEmails.where((e) =>
        e.senderEmail == email &&
        e.status != 'Success' &&
        e.status != 'Failed' &&
        e.status != 'Paused'
      ).length;
      // Count total RECIPIENTS already scheduled for this sender on the chosen date
      int dateTotal = 0;
      if (date.length == 10) {
        final selectedDate = _parseDate(date);
        if (selectedDate != null) {
          for (final e in allEmails) {
            if (e.senderEmail != email) continue;
            if (e.status == 'Success' || e.status == 'Failed' || e.status == 'Paused') continue;
            // skip the email being edited
            if (widget.editEmail != null && e.id == widget.editEmail!.id) continue;
            
            final eDate = _parseDate(e.scheduledDate);
            if (eDate == null) continue;

            if (e.type == 'Single') {
              if (e.scheduledDate == date) dateTotal += 1;
            } else if (e.type == 'Multiple') {
              if (e.scheduledDate == date) dateTotal += e.recipients.length;
            } else if (e.type == 'PDF') {
              final dailyLimit = e.dailyLimit > 0 ? e.dailyLimit : 40;
              final totalEmails = e.recipients.length;
              if (totalEmails == 0) continue;
              
              final daysNeeded = (totalEmails / dailyLimit).ceil();
              final endDate = eDate.add(Duration(days: daysNeeded - 1));
              
              // Normalize dates to remove time parts just in case
              final sD = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
              final eD = DateTime(eDate.year, eDate.month, eDate.day);
              final enD = DateTime(endDate.year, endDate.month, endDate.day);

              if ((sD.isAfter(eD) || sD.isAtSameMomentAs(eD)) &&
                  (sD.isBefore(enD) || sD.isAtSameMomentAs(enD))) {
                
                // If it's the very last day, it might only use the remainder
                if (sD.isAtSameMomentAs(enD)) {
                  final remainder = totalEmails % dailyLimit;
                  dateTotal += (remainder == 0 ? dailyLimit : remainder);
                } else {
                  dateTotal += dailyLimit;
                }
              }
            }
          }
        }
      }
      if (mounted) setState(() {
        _currentSenderUsage = scheduledCount;
        _scheduledForDate = dateTotal;
        _dateQuotaFull = date.length == 10 && dateTotal >= 50;
      });
    } else {
      if (mounted) setState(() {
        _currentSenderUsage = 0;
        _scheduledForDate = 0;
        _dateQuotaFull = false;
      });
    }
  }

  @override
  void dispose() {
    _senderController.dispose();
    _scheduleNameController.dispose();
    for (var c in _emailControllers) c.dispose();
    _subjectController.dispose();
    _bodyController.dispose();
    _dailyLimitController.dispose();
    _dateController.dispose();
    _timeController.dispose();
    super.dispose();
  }

  Future<void> _authenticateWithGoogle(String currentEmail) async {
    if (!_isValidEmail(currentEmail)) {
      _showMsg('sender', 'Please enter a valid Sender Email first.');
      return;
    }
    try {
      // Force sign-out first so user can choose the correct account
      await _googleSignIn.signOut();
      final account = await _googleSignIn.signIn();
      if (account != null) {
        setState(() { _isAuthenticated = true; _senderController.text = account.email; });
        await StorageService.saveSenderEmail(account.email);
        // Register with dispatcher cache
        BackgroundDispatcher.registerSignedInAccount(account);
        _showMsg('sender', 'Authenticated as ${account.email}!', isError: false);
      }
    } catch (_) {
      setState(() { _isAuthenticated = true; _senderController.text = currentEmail; });
      await StorageService.saveSenderEmail(currentEmail);
      _showMsg('sender', 'Sender saved!', isError: false);
    }
  }

  bool _isValidEmail(String e) =>
      RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$').hasMatch(e.trim());

  Future<void> _pickPdf() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (result != null) {
      List<String> emails = [];
      if (result.files.single.bytes != null) {
        emails = await PdfParser.extractEmailsFromPdfBytes(result.files.single.bytes!);
      } else if (result.files.single.path != null) {
        final bytes = await File(result.files.single.path!).readAsBytes();
        emails = await PdfParser.extractEmailsFromPdfBytes(bytes);
      }
      // Build controllers for editing
      for (var c in _pdfEmailControllers) c.dispose();
      _pdfEmailControllers.clear();
      for (final e in emails) _pdfEmailControllers.add(TextEditingController(text: e));
      setState(() { _pdfPath = result.files.single.name; _pdfEmails = emails; _showPdfEmails = true; });
      if (emails.isNotEmpty) await StorageService.saveExtractedEmails(emails);
    }
  }

  void _showMsg(String field, String msg, {bool isError = true}) {
    if (!mounted) return;
    setState(() {
      if (field == 'sender') { _senderMsg = msg; _isSenderErr = isError; }
      else if (field == 'recipient') { _recipientMsg = msg; _isRecipientErr = isError; }
      else if (field == 'date') { _dateMsg = msg; _isDateErr = isError; }
      else if (field == 'scheduleName') { _scheduleNameMsg = msg; _isScheduleNameErr = isError; }
      else if (field == 'subject') { _subjectMsg = msg; _isSubjectErr = isError; }
      else if (field == 'body') { _bodyMsg = msg; _isBodyErr = isError; }
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          if (field == 'sender' && _senderMsg == msg) _senderMsg = null;
          else if (field == 'recipient' && _recipientMsg == msg) _recipientMsg = null;
          else if (field == 'date' && _dateMsg == msg) _dateMsg = null;
          else if (field == 'scheduleName' && _scheduleNameMsg == msg) _scheduleNameMsg = null;
          else if (field == 'subject' && _subjectMsg == msg) _subjectMsg = null;
          else if (field == 'body' && _bodyMsg == msg) _bodyMsg = null;
        });
      }
    });
  }

  Widget _buildFieldMsg(String? msg, bool isError) {
    if (msg == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isError ? AppTheme.errorRed.withOpacity(0.1) : AppTheme.successGreen.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isError ? AppTheme.errorRed.withOpacity(0.3) : AppTheme.successGreen.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
              color: isError ? AppTheme.errorRed : AppTheme.successGreen, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(msg, style: TextStyle(color: isError ? AppTheme.errorRed : AppTheme.successGreen, fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13))),
        ],
      ),
    ).animate().fade().slideY(begin: -0.2, end: 0);
  }

  DateTime? _parseDate(String d) {
    if (d.length != 10) return null;
    try {
      int day = int.parse(d.substring(0, 2));
      int month = int.parse(d.substring(3, 5));
      int year = int.parse(d.substring(6, 10));
      return DateTime(year, month, day);
    } catch (_) { return null; }
  }

  bool _isDateTimeValid(String d, String t, bool am) {
    if (d.length != 10 || t.length != 5) return false;
    try {
      int day = int.parse(d.substring(0, 2));
      int month = int.parse(d.substring(3, 5));
      int year = int.parse(d.substring(6, 10));
      int hour = int.parse(t.substring(0, 2));
      int minute = int.parse(t.substring(3, 5));
      if (!am && hour != 12) hour += 12;
      if (am && hour == 12) hour = 0;
      return DateTime(year, month, day, hour, minute).isAfter(DateTime.now());
    } catch (_) { return false; }
  }


  Future<void> _submit() async {
    final sender = _senderController.text.trim();
    if (!_isValidEmail(sender) || !_isAuthenticated) { _showMsg('sender', 'Authenticate a valid sender email first.'); return; }
    if (!_isDateTimeValid(_dateController.text, _timeController.text, _isAm)) { _showMsg('date', 'Enter a valid future date and time.'); return; }

    // Validate per-date quota: count how many this new schedule will add
    final date = _dateController.text.trim();
    if (date.length == 10) {
      int newCount = 0;
      if (_sendType == 'Single') {
        newCount = 1;
      } else if (_sendType == 'Multiple') {
        newCount = _emailControllers.where((c) => _isValidEmail(c.text.trim())).length;
      } else if (_sendType == 'PDF') {
        newCount = int.tryParse(_dailyLimitController.text.trim()) ?? 40;
      }
      if (_scheduledForDate + newCount > 50) {
        _showMsg('sender', 'Daily quota full for $date! $_scheduledForDate/50 already scheduled. Please use a different sender email.');
        return;
      }
    }

    List<String> recipients = [];
    if (_sendType == 'PDF') {
      if (_pdfEmails.isEmpty) { _showMsg('recipient', 'No emails extracted from PDF.'); return; }
      recipients = _pdfEmails;
    } else {
      for (var c in _emailControllers) {
        final e = c.text.trim();
        if (e.isNotEmpty) {
          if (!_isValidEmail(e)) { _showMsg('recipient', 'Invalid email: $e'); return; }
          recipients.add(e);
        }
      }
      if (recipients.isEmpty) { _showMsg('recipient', 'Add at least one recipient.'); return; }
    }
    
    if (_sendType == 'Multiple' || _sendType == 'PDF') {
      if (_scheduleNameController.text.trim().isEmpty) { _showMsg('scheduleName', 'Please provide a schedule name.'); return; }
    }
    
    if (_sendType == 'PDF') {
      final inputLimit = int.tryParse(_dailyLimitController.text.trim()) ?? 0;
      if (inputLimit > 50) {
        setState(() {
          _dailyLimitMsg = 'Max limit is 50.';
          _isDailyLimitErr = true;
        });
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) setState(() { _dailyLimitMsg = null; _isDailyLimitErr = false; });
        });
        return;
      }
    }
    
    if (!_useSavedFormat) {
      if (_subjectController.text.trim().isEmpty) { _showMsg('subject', 'Subject cannot be empty.'); return; }
      if (_bodyController.text.trim().isEmpty) { _showMsg('body', 'Body cannot be empty.'); return; }
      if (!RegExp(r'<[a-zA-Z][^>]*>').hasMatch(_bodyController.text)) { _showMsg('body', 'Body must contain HTML tags (e.g. <p>, <b>, <br>).'); return; }
    } else {
      if (_selectedSubject == null) { _showMsg('subject', 'Please select a saved subject.'); return; }
      if (_selectedBody == null) { _showMsg('body', 'Please select a saved body.'); return; }
    }
    await StorageService.saveExtractedEmails(recipients);

    final newEmail = ScheduledEmail(
      id: widget.editEmail?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      senderEmail: sender,
      type: _sendType,
      recipients: recipients,
      subject: _useSavedFormat ? (_selectedSubject?.content ?? '') : _subjectController.text,
      body: _useSavedFormat ? (_selectedBody?.content ?? '') : _bodyController.text,
      scheduledDate: _dateController.text,
      scheduledTime: '${_timeController.text} ${_isAm ? "AM" : "PM"}',
      scheduleName: _scheduleNameController.text.trim(),
      dailyLimit: _sendType == 'PDF' ? (int.tryParse(_dailyLimitController.text.trim()) ?? 40) : 0,
      sentCount: widget.editEmail?.sentCount ?? 0,
      lastSentDate: widget.editEmail?.lastSentDate,
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
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: AppTheme.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Scrollable content
          Flexible(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Row(
                    children: [
                      Text(
                        widget.editEmail != null ? 'Edit Schedule' : 'New Schedule',
                        style: const TextStyle(fontFamily: 'Outfit', fontSize: 22, fontWeight: FontWeight.w700, color: AppTheme.textDark),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 32, height: 32,
                          decoration: BoxDecoration(color: AppTheme.bgSurface, borderRadius: BorderRadius.circular(8)),
                          child: const Icon(Icons.close, size: 18, color: AppTheme.textMid),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ── Section 1: Name ──────────────────────────────
                  _SectionHeader(title: '1  Schedule Name', icon: Icons.label_outline),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _scheduleNameController,
                    decoration: const InputDecoration(
                      hintText: 'My Weekly Update Blast',
                      prefixIcon: Icon(Icons.label_outline, size: 18),
                    ),
                  ).animate().fade().slideY(),
                  _buildFieldMsg(_scheduleNameMsg, _isScheduleNameErr),
                  const SizedBox(height: 24),

                  // ── Section 2: Sender ──────────────────────────────
                  _SectionHeader(title: '2  Sender Account', icon: Icons.account_circle_rounded),
                  const SizedBox(height: 10),
                  Autocomplete<String>(
                    optionsBuilder: (v) => v.text.isEmpty
                        ? const Iterable<String>.empty()
                        : _suggestedSenders.where((s) => s.toLowerCase().contains(v.text.toLowerCase())),
                    onSelected: (s) => setState(() => _senderController.text = s),
                    optionsViewBuilder: (BuildContext ctx2, AutocompleteOnSelected<String> onSelected, Iterable<String> options) {
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          color: Colors.transparent,
                          child: Container(
                            width: MediaQuery.of(ctx2).size.width - 40,
                            constraints: const BoxConstraints(maxHeight: 220),
                            margin: const EdgeInsets.only(top: 4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(color: AppTheme.primaryBlue.withOpacity(0.15), blurRadius: 20, offset: const Offset(0, 8)),
                                BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6, offset: const Offset(0, 2)),
                              ],
                              border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.2)),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: ListView.separated(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                shrinkWrap: true,
                                itemCount: options.length,
                                separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFEEEEF5)),
                                itemBuilder: (BuildContext ctx3, int index) {
                                  final String option = options.elementAt(index);
                                  return InkWell(
                                    onTap: () => onSelected(option),
                                    borderRadius: BorderRadius.circular(12),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 32, height: 32,
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [AppTheme.primaryBlue, AppTheme.primaryBlue.withOpacity(0.7)],
                                                begin: Alignment.topLeft, end: Alignment.bottomRight,
                                              ),
                                              shape: BoxShape.circle,
                                            ),
                                            child: Center(
                                              child: Text(
                                                option.isNotEmpty ? option[0].toUpperCase() : '?',
                                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              option,
                                              style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.textDark, fontWeight: FontWeight.w500),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const Icon(Icons.north_west_rounded, size: 14, color: AppTheme.textLight),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ).animate().fade(duration: 200.ms).slideY(begin: -0.1, end: 0, duration: 200.ms, curve: Curves.easeOut),
                      );
                    },
                    fieldViewBuilder: (ctx, ctrl, focus, onSubmit) {
                      if (_senderController.text.isNotEmpty && ctrl.text.isEmpty) ctrl.text = _senderController.text;
                      ctrl.addListener(() => _senderController.text = ctrl.text);
                      return TextField(
                        controller: ctrl,
                        focusNode: focus,
                        enabled: !_isAuthenticated,
                        decoration: InputDecoration(
                          hintText: 'your@gmail.com',
                          prefixIcon: const Icon(Icons.alternate_email, size: 18),
                          suffixIcon: _isAuthenticated
                              ? const Icon(Icons.verified_rounded, color: AppTheme.successGreen)
                              : null,
                        ),
                      );
                    },
                  ),

                  if (!_isAuthenticated) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _authenticateWithGoogle(_senderController.text),
                        icon: const Icon(Icons.security_rounded, size: 18),
                        label: const Text('Authenticate with Google'),
                      ),
                    ),
                  ],
                  _buildFieldMsg(_senderMsg, _isSenderErr),
                  if (_isAuthenticated && _isValidEmail(_senderController.text) && _dateController.text.length == 10) ...[
                    const SizedBox(height: 10),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: _dateQuotaFull
                            ? AppTheme.errorRed.withOpacity(0.08)
                            : (_scheduledForDate >= 30
                                ? AppTheme.warningAmber.withOpacity(0.08)
                                : AppTheme.successGreen.withOpacity(0.08)),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _dateQuotaFull
                              ? AppTheme.errorRed.withOpacity(0.4)
                              : (_scheduledForDate >= 30
                                  ? AppTheme.warningAmber.withOpacity(0.4)
                                  : AppTheme.successGreen.withOpacity(0.4)),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _dateQuotaFull
                                    ? Icons.block_rounded
                                    : (_scheduledForDate >= 30
                                        ? Icons.warning_amber_rounded
                                        : Icons.check_circle_outline_rounded),
                                size: 15,
                                color: _dateQuotaFull
                                    ? AppTheme.errorRed
                                    : (_scheduledForDate >= 30
                                        ? AppTheme.warningAmber
                                        : AppTheme.successGreen),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _dateQuotaFull
                                      ? 'Quota FULL for ${_dateController.text}'
                                      : 'Quota for ${_dateController.text}: $_scheduledForDate / 50',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: _dateQuotaFull
                                        ? AppTheme.errorRed
                                        : (_scheduledForDate >= 30
                                            ? AppTheme.warningAmber
                                            : AppTheme.successGreen),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (_dateQuotaFull) ...[
                            const SizedBox(height: 6),
                            const Text(
                              '⚠️ This date already has 50 emails scheduled from this account. Please use a different sender email or choose a different date.',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 11,
                                color: AppTheme.errorRed,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ] else if (_scheduledForDate > 0) ...[
                            const SizedBox(height: 4),
                            Text(
                              '${50 - _scheduledForDate} slots remaining for this date.',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 11,
                                color: _scheduledForDate >= 30
                                    ? AppTheme.warningAmber
                                    : AppTheme.successGreen,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ).animate().fade(duration: 250.ms),
                  ],
                  const SizedBox(height: 24),

                  // ── Section 3: Recipients ──────────────────────────
                  _SectionHeader(title: '3  Recipients', icon: Icons.group_rounded),
                  const SizedBox(height: 10),
                  // Type selector
                  Row(
                    children: ['Single', 'Multiple', 'PDF'].map((type) {
                      final sel = _sendType == type;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _sendType = type),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: sel ? AppTheme.primaryBlue : AppTheme.bgSurface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: sel ? AppTheme.primaryBlue : AppTheme.divider,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                type,
                                style: TextStyle(
                                  fontFamily: 'Inter', fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: sel ? Colors.white : AppTheme.textMid,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),

                  // Recipient inputs

                  if (_sendType == 'Single' || _sendType == 'Multiple')
                    ...List.generate(_emailControllers.length, (i) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: TextField(
                        controller: _emailControllers[i],
                        decoration: InputDecoration(
                          hintText: 'Recipient ${i + 1} email',
                          prefixIcon: const Icon(Icons.email_outlined, size: 18),
                          suffixIcon: _sendType == 'Multiple' && _emailControllers.length > 1
                              ? IconButton(
                                  icon: const Icon(Icons.remove_circle_outline, color: AppTheme.errorRed, size: 18),
                                  onPressed: () => setState(() => _emailControllers.removeAt(i)),
                                )
                              : null,
                        ),
                      ).animate().fade().slideY(),
                    )),

                  if (_sendType == 'Multiple')
                    TextButton.icon(
                      onPressed: () => setState(() => _emailControllers.add(TextEditingController())),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add Recipient'),
                    ),

                  if (_sendType == 'PDF') ...[
                    GestureDetector(
                      onTap: _pickPdf,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppTheme.bgSurface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _pdfPath != null ? AppTheme.primaryBlue : AppTheme.divider,
                            width: _pdfPath != null ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              _pdfPath != null ? Icons.picture_as_pdf_rounded : Icons.upload_file_rounded,
                              size: 40,
                              color: _pdfPath != null ? AppTheme.primaryBlue : AppTheme.textLight,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _pdfPath ?? 'Tap to upload PDF',
                              style: TextStyle(
                                fontFamily: 'Inter', fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: _pdfPath != null ? AppTheme.textDark : AppTheme.textLight,
                              ),
                            ),
                            if (_pdfEmails.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text('${_pdfEmails.length} emails extracted', style: const TextStyle(color: AppTheme.successGreen, fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600)),
                            ],
                          ],
                        ),
                      ).animate().fade().scale(),
                    ),
                    // PDF Emails panel
                    if (_pdfEmails.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: () => setState(() => _showPdfEmails = !_showPdfEmails),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppTheme.successGreen.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppTheme.successGreen.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.list_alt_rounded, size: 18, color: AppTheme.successGreen),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '${_pdfEmails.length} emails extracted — tap to ${_showPdfEmails ? 'hide' : 'review & edit'}',
                                  style: const TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.successGreen),
                                ),
                              ),
                              Icon(_showPdfEmails ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, color: AppTheme.successGreen),
                            ],
                          ),
                        ),
                      ),
                      if (_showPdfEmails) ...[
                        const SizedBox(height: 8),
                        Container(
                          height: 260,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppTheme.divider),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
                          ),
                          child: ListView.separated(
                            padding: const EdgeInsets.all(8),
                            physics: const BouncingScrollPhysics(),
                            itemCount: _isPdfEmailEditing ? _pdfEmailControllers.length : _pdfEmails.length,
                            separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFEEEEF5)),
                            itemBuilder: (ctx, idx) {
                              if (_isPdfEmailEditing) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                                  child: Row(
                                    children: [
                                      Text('${idx + 1}.', style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.textLight, fontWeight: FontWeight.w600)),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: TextField(
                                          controller: _pdfEmailControllers[idx],
                                          style: const TextStyle(fontFamily: 'Inter', fontSize: 13),
                                          decoration: const InputDecoration(
                                            isDense: true,
                                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.remove_circle_outline, color: AppTheme.errorRed, size: 18),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        onPressed: () {
                                          final removed = _pdfEmailControllers.removeAt(idx);
                                          removed.dispose();
                                          setState(() => _pdfEmails.removeAt(idx));
                                        },
                                      ),
                                    ],
                                  ),
                                );
                              }
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 22, height: 22,
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryBlue.withOpacity(0.08),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: Text('${idx + 1}', style: const TextStyle(fontFamily: 'Inter', fontSize: 10, color: AppTheme.primaryBlue, fontWeight: FontWeight.w700)),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(child: Text(_pdfEmails[idx], style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.textDark))),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (_isPdfEmailEditing)
                              TextButton.icon(
                                onPressed: () {
                                  // Save edits back
                                  setState(() {
                                    _pdfEmails = _pdfEmailControllers.map((c) => c.text.trim()).where((e) => e.isNotEmpty).toList();
                                    _isPdfEmailEditing = false;
                                  });
                                },
                                icon: const Icon(Icons.check_rounded, size: 16),
                                label: const Text('Save Edits'),
                              )
                            else
                              TextButton.icon(
                                onPressed: () {
                                  // Build controllers from current emails
                                  for (var c in _pdfEmailControllers) c.dispose();
                                  _pdfEmailControllers.clear();
                                  for (final e in _pdfEmails) _pdfEmailControllers.add(TextEditingController(text: e));
                                  setState(() => _isPdfEmailEditing = true);
                                },
                                icon: const Icon(Icons.edit_rounded, size: 16),
                                label: const Text('Edit Emails'),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ],
                  _buildFieldMsg(_recipientMsg, _isRecipientErr),
                  if (_sendType == 'PDF') ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: _dailyLimitController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Emails per day',
                        hintText: '40',
                        prefixIcon: Icon(Icons.speed_rounded, size: 18),
                        helperText: 'Your limit is 50. Campaign will send this many emails each day.',
                      ),
                    ),
                    _buildFieldMsg(_dailyLimitMsg, _isDailyLimitErr),
                  ],
                  const SizedBox(height: 24),

                  // ── Section 4: Email content ───────────────────────
                  _SectionHeader(title: '4  Email Content', icon: Icons.edit_note_rounded),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() { _useSavedFormat = false; }),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: !_useSavedFormat ? AppTheme.primaryBlue : AppTheme.bgSurface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: !_useSavedFormat ? AppTheme.primaryBlue : AppTheme.divider),
                            ),
                            child: Center(child: Text('Make New', style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600, color: !_useSavedFormat ? Colors.white : AppTheme.textMid))),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() { _useSavedFormat = true; }),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: _useSavedFormat ? AppTheme.primaryBlue : AppTheme.bgSurface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: _useSavedFormat ? AppTheme.primaryBlue : AppTheme.divider),
                            ),
                            child: Center(child: Text('Use Saved', style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600, color: _useSavedFormat ? Colors.white : AppTheme.textMid))),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (!_useSavedFormat) ...[
                    TextField(
                      controller: _subjectController,
                      minLines: 4,
                      maxLines: 8,
                      decoration: const InputDecoration(
                        hintText: 'Subject line',
                        prefixIcon: Icon(Icons.subject_rounded, size: 18),
                      ),
                    ),
                    _buildFieldMsg(_subjectMsg, _isSubjectErr),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _bodyController,
                      minLines: 8,
                      maxLines: 15,
                      decoration: const InputDecoration(
                        hintText: 'Write your HTML email body here… (e.g. <b>Hello</b>)',
                        alignLabelWithHint: true,
                        contentPadding: EdgeInsets.all(16),
                      ),
                    ),
                    _buildFieldMsg(_bodyMsg, _isBodyErr),
                  ] else ...[
                    _AnimatedDropdownPicker(
                      icon: Icons.subject_rounded,
                      hint: 'Select Subject',
                      items: _savedSubjects,
                      selected: _selectedSubject,
                      onSelected: (v) => setState(() => _selectedSubject = v),
                    ),
                    _buildFieldMsg(_subjectMsg, _isSubjectErr),
                    const SizedBox(height: 10),
                    _AnimatedDropdownPicker(
                      icon: Icons.edit_note_rounded,
                      hint: 'Select Body',
                      items: _savedBodies,
                      selected: _selectedBody,
                      onSelected: (v) => setState(() => _selectedBody = v),
                    ),
                    _buildFieldMsg(_bodyMsg, _isBodyErr),
                  ],
                  const SizedBox(height: 24),

                  // ── Section 5: Schedule time ───────────────────────
                  _SectionHeader(title: '5  Schedule Date & Time', icon: Icons.schedule_rounded),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _dateController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [DateInputFormatter()],
                          decoration: const InputDecoration(
                            hintText: 'DD/MM/YYYY',
                            prefixIcon: Icon(Icons.calendar_today_rounded, size: 18),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
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
                            GestureDetector(
                              onTap: () => setState(() => _isAm = !_isAm),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 17),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryBlue.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.3)),
                                ),
                                child: Text(
                                  _isAm ? 'AM' : 'PM',
                                  style: const TextStyle(color: AppTheme.primaryBlue, fontFamily: 'Inter', fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  _buildFieldMsg(_dateMsg, _isDateErr),
                  const SizedBox(height: 28),

                  // Submit
                  if (_currentSenderUsage >= 50)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(color: AppTheme.errorRed.withOpacity(0.1), borderRadius: BorderRadius.circular(16)),
                      child: const Center(
                        child: Text(
                          'Daily limit 50 reached. Try again tomorrow.',
                          style: TextStyle(color: AppTheme.errorRed, fontFamily: 'Inter', fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _submit,
                        child: Text(
                          widget.editEmail != null ? 'Update Schedule' : 'Save & Schedule',
                          style: const TextStyle(fontFamily: 'Outfit', fontSize: 17, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.primaryBlue),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontFamily: 'Outfit', fontSize: 14, fontWeight: FontWeight.w700,
            color: AppTheme.primaryBlue,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  RESEND MODAL
// ─────────────────────────────────────────────────────────────────────────────
class _ResendModal extends StatefulWidget {
  final ScheduledEmail email;
  const _ResendModal({required this.email});

  @override
  State<_ResendModal> createState() => _ResendModalState();
}

class _ResendModalState extends State<_ResendModal> {
  final _dateController = TextEditingController();
  final _timeController = TextEditingController();
  bool _isAm = true;
  String? _dateMsg; bool _isDateErr = false;

  @override
  void dispose() {
    _dateController.dispose();
    _timeController.dispose();
    super.dispose();
  }

  bool _isDateTimeValid(String d, String t, bool am) {
    if (d.length != 10 || t.length != 5) return false;
    try {
      int day = int.parse(d.substring(0, 2));
      int month = int.parse(d.substring(3, 5));
      int year = int.parse(d.substring(6, 10));
      int hour = int.parse(t.substring(0, 2));
      int minute = int.parse(t.substring(3, 5));
      if (!am && hour != 12) hour += 12;
      if (am && hour == 12) hour = 0;
      return DateTime(year, month, day, hour, minute).isAfter(DateTime.now());
    } catch (_) { return false; }
  }

  void _showMsg(String msg, {bool isError = true}) {
    if (!mounted) return;
    setState(() {
      _dateMsg = msg; _isDateErr = isError;
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() { _dateMsg = null; });
    });
  }

  Widget _buildFieldMsg() {
    if (_dateMsg == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _isDateErr ? AppTheme.errorRed.withOpacity(0.1) : AppTheme.successGreen.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _isDateErr ? AppTheme.errorRed.withOpacity(0.3) : AppTheme.successGreen.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(_isDateErr ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
              color: _isDateErr ? AppTheme.errorRed : AppTheme.successGreen, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(_dateMsg!, style: TextStyle(color: _isDateErr ? AppTheme.errorRed : AppTheme.successGreen, fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13))),
        ],
      ),
    ).animate().fade().slideY(begin: -0.2, end: 0);
  }

  Future<void> _submit() async {
    if (!_isDateTimeValid(_dateController.text, _timeController.text, _isAm)) { _showMsg('Enter a valid future date and time.'); return; }
    
    final newEmail = widget.email.copyWith(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      status: 'Scheduled',
      scheduledDate: _dateController.text,
      scheduledTime: '${_timeController.text} ${_isAm ? "AM" : "PM"}',
      sentCount: 0,
    );
    
    await StorageService.saveEmail(newEmail);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 48, height: 6,
              decoration: BoxDecoration(
                color: AppTheme.textLight.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Resend Email',
                        style: TextStyle(fontFamily: 'Outfit', fontSize: 22, fontWeight: FontWeight.w700, color: AppTheme.textDark),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 32, height: 32,
                          decoration: BoxDecoration(color: AppTheme.bgSurface, borderRadius: BorderRadius.circular(8)),
                          child: const Icon(Icons.close, size: 18, color: AppTheme.textMid),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text('Schedule Date & Time', style: TextStyle(fontFamily: 'Outfit', fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.primaryBlue)),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _dateController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [DateInputFormatter()],
                          decoration: const InputDecoration(
                            hintText: 'DD/MM/YYYY',
                            prefixIcon: Icon(Icons.calendar_today_rounded, size: 18),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _timeController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [TimeInputFormatter()],
                          decoration: const InputDecoration(
                            hintText: 'HH:MM',
                            prefixIcon: Icon(Icons.access_time_rounded, size: 18),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _isAm = true),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: _isAm ? AppTheme.primaryBlue : AppTheme.bgSurface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: _isAm ? AppTheme.primaryBlue : AppTheme.divider),
                            ),
                            child: Center(child: Text('AM', style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, color: _isAm ? Colors.white : AppTheme.textMid))),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _isAm = false),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: !_isAm ? AppTheme.primaryBlue : AppTheme.bgSurface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: !_isAm ? AppTheme.primaryBlue : AppTheme.divider),
                            ),
                            child: Center(child: Text('PM', style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, color: !_isAm ? Colors.white : AppTheme.textMid))),
                          ),
                        ),
                      ),
                    ],
                  ),
                  _buildFieldMsg(),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryBlue,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text('Resend Schedule', style: TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedDropdownPicker extends StatelessWidget {
  final IconData icon;
  final String hint;
  final List<TemplateItem> items;
  final TemplateItem? selected;
  final ValueChanged<TemplateItem?> onSelected;

  const _AnimatedDropdownPicker({
    required this.icon,
    required this.hint,
    required this.items,
    required this.selected,
    required this.onSelected,
  });

  void _showPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppTheme.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text('Select ${hint.replaceAll('Select ', '')}', style: const TextStyle(fontFamily: 'Outfit', fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.textDark)),
              const SizedBox(height: 16),
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No saved items yet.', style: TextStyle(fontFamily: 'Inter', color: AppTheme.textLight)),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.divider),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final isSelected = selected == item;
                      return ListTile(
                        onTap: () {
                          onSelected(item);
                          Navigator.pop(context);
                        },
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isSelected ? AppTheme.primaryBlue.withOpacity(0.1) : AppTheme.bgSurface,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(icon, color: isSelected ? AppTheme.primaryBlue : AppTheme.textLight, size: 20),
                        ),
                        title: Text(
                          item.name,
                          style: TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500, color: isSelected ? AppTheme.primaryBlue : AppTheme.textDark),
                        ),
                        trailing: isSelected ? const Icon(Icons.check_circle_rounded, color: AppTheme.primaryBlue) : null,
                      );
                    },
                  ),
                ),
            ],
          ),
        ).animate().slideY(begin: 1, end: 0, curve: Curves.easeOutQuart).fade();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showPicker(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.bgSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected != null ? AppTheme.primaryBlue.withOpacity(0.5) : AppTheme.divider),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: selected != null ? AppTheme.primaryBlue : AppTheme.textLight),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                selected?.name ?? hint,
                style: TextStyle(
                  fontFamily: 'Inter', fontSize: 14,
                  fontWeight: selected != null ? FontWeight.w600 : FontWeight.w400,
                  color: selected != null ? AppTheme.textDark : AppTheme.textMid,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: AppTheme.textLight),
          ],
        ),
      ),
    );
  }
}
