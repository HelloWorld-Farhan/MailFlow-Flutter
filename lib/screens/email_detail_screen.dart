import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/scheduled_email.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

class EmailDetailScreen extends StatefulWidget {
  const EmailDetailScreen({Key? key}) : super(key: key);
  @override
  State<EmailDetailScreen> createState() => _EmailDetailScreenState();
}

class _EmailDetailScreenState extends State<EmailDetailScreen>
    with SingleTickerProviderStateMixin {
  List<ScheduledEmail> _allEmails = [];
  bool _isLoading = true;
  Timer? _refreshTimer;
  Timer? _midnightTimer;
  bool _quotaPanelOpen = true;
  late AnimationController _rotateCtrl;

  @override
  void initState() {
    super.initState();
    _rotateCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _rotateCtrl.forward();
    _loadGroups();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) => _loadGroups(silent: true));
    _scheduleMidnightRefresh();
  }

  void _scheduleMidnightRefresh() {
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day + 1);
    final diff = midnight.difference(now);
    _midnightTimer = Timer(diff, () {
      _loadGroups();
      _scheduleMidnightRefresh();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _midnightTimer?.cancel();
    _rotateCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadGroups({bool silent = false}) async {
    final allEmails = await StorageService.getEmails();
    if (!mounted) return;
    setState(() {
      // Filter out successfully sent emails from showing up in the group list
      _allEmails = allEmails.where((e) => e.status != 'Success').toList();
      if (!silent) _isLoading = false;
    });
  }

  Future<void> _deleteGroup(String id) async {
    await StorageService.deleteEmail(id);
    _loadGroups();
  }

  // ── Quota Panel Computation ─────────────────────────────────────────────

  DateTime? _parseDate(String d) {
    if (d.length != 10) return null;
    try {
      int day = int.parse(d.substring(0, 2));
      int month = int.parse(d.substring(3, 5));
      int year = int.parse(d.substring(6, 10));
      return DateTime(year, month, day);
    } catch (_) {
      return null;
    }
  }

  /// Returns a map: senderEmail -> { dateStr -> List<(scheduleName, contribution)> }
  /// Only includes dates >= today and where at least one schedule is active (not Success/Failed)
  Map<String, Map<String, List<_DateContribution>>> _computeQuota() {
    final today = DateTime.now();
    final todayNorm = DateTime(today.year, today.month, today.day);
    final result = <String, Map<String, List<_DateContribution>>>{};

    for (final email in _allEmails) {
      // Skip fully completed
      if (email.status == 'Success' || email.status == 'Failed') continue;
      final sender = email.senderEmail;

      if (email.type == 'Single' || email.type == 'Multiple') {
        final date = _parseDate(email.scheduledDate);
        if (date == null) continue;
        if (date.isBefore(todayNorm)) continue;
        final count = email.type == 'Single' ? 1 : email.recipients.length;
        final name = email.scheduleName?.isNotEmpty == true
            ? email.scheduleName!
            : email.subject.isNotEmpty ? email.subject : '(No Name)';
        result.putIfAbsent(sender, () => {});
        result[sender]!.putIfAbsent(email.scheduledDate, () => []);
        result[sender]![email.scheduledDate]!.add(_DateContribution(
          scheduleId: email.id,
          scheduleName: name,
          count: count,
          type: email.type,
          isMerged: email.isMerged,
        ));
      } else if (email.type == 'PDF') {
        final startDate = _parseDate(email.scheduledDate);
        if (startDate == null) continue;
        final dailyLimit = email.dailyLimit > 0 ? email.dailyLimit : 40;
        final totalEmails = email.recipients.length;
        if (totalEmails == 0) continue;
        final alreadySent = email.sentCount;
        final remaining = totalEmails - alreadySent;
        final daysLeft = (remaining / dailyLimit).ceil();
        final name = email.scheduleName?.isNotEmpty == true
            ? email.scheduleName!
            : email.subject.isNotEmpty ? email.subject : '(No Name)';

        // Find effective start date (today or later)
        final effectiveStart = startDate.isBefore(todayNorm) ? todayNorm : startDate;

        for (int d = 0; d < daysLeft; d++) {
          final thisDay = effectiveStart.add(Duration(days: d));
          if (thisDay.isBefore(todayNorm)) continue;
          final dateStr = '${thisDay.day.toString().padLeft(2, '0')}/${thisDay.month.toString().padLeft(2, '0')}/${thisDay.year}';

          // Calculate how many on this specific day
          int dayCount;
          if (d == daysLeft - 1) {
            // Last day: send remainder
            final rem = remaining % dailyLimit;
            dayCount = rem == 0 ? dailyLimit : rem;
          } else {
            dayCount = dailyLimit;
          }

          // Only include if this date has a conflict (another schedule on same date)
          // OR if it's within the next 7 days
          final dayDiff = thisDay.difference(todayNorm).inDays;

          // Include today + dates that have conflicts with other schedules
          // OR next 7 days for visibility
          if (dayDiff <= 7 || _hasOtherScheduleOnDate(email.id, sender, dateStr)) {
            result.putIfAbsent(sender, () => {});
            result[sender]!.putIfAbsent(dateStr, () => []);
            result[sender]![dateStr]!.add(_DateContribution(
              scheduleId: email.id,
              scheduleName: name,
              count: dayCount,
              type: 'PDF',
              isMerged: email.isMerged,
              dayInfo: 'Day ${d + 1} of ${(totalEmails / dailyLimit).ceil()}',
            ));
          }
        }
      }
    }
    return result;
  }

  bool _hasOtherScheduleOnDate(String excludeId, String sender, String dateStr) {
    final date = _parseDate(dateStr);
    if (date == null) return false;
    for (final email in _allEmails) {
      if (email.id == excludeId) continue;
      if (email.senderEmail != sender) continue;
      if (email.status == 'Success' || email.status == 'Failed') continue;
      if (email.type == 'Single' || email.type == 'Multiple') {
        if (email.scheduledDate == dateStr) return true;
      } else if (email.type == 'PDF') {
        final eStart = _parseDate(email.scheduledDate);
        if (eStart == null) continue;
        final eDailyLimit = email.dailyLimit > 0 ? email.dailyLimit : 40;
        final eTotalDays = (email.recipients.length / eDailyLimit).ceil();
        final eEnd = eStart.add(Duration(days: eTotalDays - 1));
        final norm = DateTime(date.year, date.month, date.day);
        final normStart = DateTime(eStart.year, eStart.month, eStart.day);
        final normEnd = DateTime(eEnd.year, eEnd.month, eEnd.day);
        if ((norm.isAfter(normStart) || norm.isAtSameMomentAs(normStart)) &&
            (norm.isBefore(normEnd) || norm.isAtSameMomentAs(normEnd))) {
          return true;
        }
      }
    }
    return false;
  }

  // ── Colors & Icons ─────────────────────────────────────────────────────

  Color _statusColor(String status) {
    if (status == 'Success') return AppTheme.successGreen;
    if (status.startsWith('Doing') || status.startsWith('Merge Day') || status.startsWith('Day ')) return AppTheme.primaryBlue;
    if (status == 'Failed') return AppTheme.errorRed;
    return AppTheme.warningAmber;
  }

  IconData _statusIcon(String status) {
    if (status == 'Success') return Icons.check_circle_rounded;
    if (status.startsWith('Doing') || status.startsWith('Merge Day') || status.startsWith('Day ')) return Icons.sync_rounded;
    if (status == 'Failed') return Icons.cancel_rounded;
    return Icons.schedule_rounded;
  }

  Color _typeColor(String type, bool isMerged) {
    if (isMerged) return const Color(0xFF8B5CF6); // purple for merge
    if (type == 'PDF') return Colors.deepOrange;
    if (type == 'Multiple') return AppTheme.primaryBlue;
    return AppTheme.successGreen;
  }

  Color _quotaColor(int total) {
    if (total >= 50) return AppTheme.errorRed;
    if (total >= 30) return AppTheme.warningAmber;
    if (total >= 20) return const Color(0xFFF97316);
    return AppTheme.successGreen;
  }

  // ── Recipient detail dialog ────────────────────────────────────────────

  void _showRecipients(ScheduledEmail email) {
    final name = (email.scheduleName != null && email.scheduleName!.isNotEmpty)
        ? email.scheduleName!
        : email.subject.isNotEmpty ? email.subject : 'Schedule Details';

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
              Expanded(child: Text(name,
                  style: const TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold, fontSize: 18, color: AppTheme.textDark))),
              IconButton(
                  icon: const Icon(Icons.close, color: AppTheme.textMid, size: 20),
                  onPressed: () => Navigator.pop(context)),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: _typeColor(email.type, email.isMerged).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6)),
                child: Text(email.isMerged ? 'Merged PDF' : email.type,
                    style: TextStyle(fontFamily: 'Inter', fontSize: 11,
                        color: _typeColor(email.type, email.isMerged), fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text('${email.scheduledDate}  |  ${email.scheduledTime}',
                  style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.textLight),
                  overflow: TextOverflow.ellipsis)),
            ]),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(height: 20),
                // Merge info section
                if (email.isMerged) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6).withOpacity(0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF8B5CF6).withOpacity(0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Icon(Icons.merge_rounded, size: 16, color: Color(0xFF8B5CF6)),
                          const SizedBox(width: 6),
                          const Text('Merged PDF Schedule', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF8B5CF6))),
                        ]),
                        const SizedBox(height: 8),
                        ...email.mergedSourceIds.map((sid) {
                          final sName = email.mergeSourceNames[sid] ?? sid;
                          final sAlloc = email.mergeContributions[sid] ?? 0;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(children: [
                              const Icon(Icons.subdirectory_arrow_right_rounded, size: 14, color: AppTheme.textMid),
                              const SizedBox(width: 4),
                              Expanded(child: Text('$sName', style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.textDark))),
                              Text('$sAlloc/day', style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.textMid, fontWeight: FontWeight.w600)),
                            ]),
                          );
                        }),
                        const SizedBox(height: 6),
                        Row(children: [
                          const Icon(Icons.calendar_today_rounded, size: 13, color: AppTheme.textMid),
                          const SizedBox(width: 5),
                          Text('Daily total: ${email.dailyLimit}/day  •  ${email.sentCount}/${email.recipients.length} sent',
                              style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.textMid)),
                        ]),
                      ],
                    ),
                  ),
                ],
                Text('Recipients (${email.recipients.length})',
                    style: const TextStyle(fontFamily: 'Outfit', fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.primaryBlue)),
                const SizedBox(height: 8),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: min(email.recipients.length, 200),
                  itemBuilder: (context, i) {
                    final r = email.recipients[i];
                    final rStatus = email.recipientStatuses[r] ?? 'pending';
                    final rColor = rStatus == 'sent'
                        ? AppTheme.successGreen
                        : rStatus == 'failed'
                            ? AppTheme.errorRed
                            : rStatus == 'inProcess'
                                ? AppTheme.primaryBlue
                                : AppTheme.textLight;
                    final rIcon = rStatus == 'sent'
                        ? Icons.check_circle_rounded
                        : rStatus == 'failed'
                            ? Icons.cancel_rounded
                            : rStatus == 'inProcess'
                                ? Icons.sync_rounded
                                : Icons.circle_outlined;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(children: [
                        Icon(rIcon, color: rColor, size: 16),
                        const SizedBox(width: 10),
                        Expanded(child: Text(r,
                            style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.textDark))),
                      ]),
                    );
                  },
                ),
                if (email.recipients.length > 200)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('... and ${email.recipients.length - 200} more',
                        style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.textMid)),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: AppTheme.primaryBlue, fontFamily: 'Inter', fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final quotaData = _computeQuota();
    final hasQuota = quotaData.isNotEmpty &&
        quotaData.values.any((m) => m.values.any((list) => list.isNotEmpty));

    return Scaffold(
      backgroundColor: AppTheme.bgWhite,
      appBar: AppBar(
        title: const Text('Email Groups',
            style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold, color: AppTheme.textDark)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.textDark),
        surfaceTintColor: Colors.transparent,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // ── Quota Panel ──────────────────────────────────────
                if (hasQuota) _buildQuotaPanel(quotaData),

                // ── Email list ───────────────────────────────────────
                Expanded(
                  child: _allEmails.isEmpty
                      ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.group_off_outlined, size: 60, color: Colors.grey.shade400),
                          const SizedBox(height: 16),
                          const Text('No scheduled emails yet.',
                              style: TextStyle(fontFamily: 'Inter', fontSize: 16, color: Color(0xFF9E9E9E))),
                        ]))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          itemCount: _allEmails.length,
                          itemBuilder: (context, index) {
                            final email = _allEmails[index];
                            return _buildEmailCard(email, index);
                          },
                        ),
                ),
              ],
            ),
    );
  }

  // ── Quota Panel Widget ──────────────────────────────────────────────────
  Widget _buildQuotaPanel(Map<String, Map<String, List<_DateContribution>>> quotaData) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppTheme.divider)),
      ),
      child: Column(
        children: [
          // Header toggle
          GestureDetector(
            onTap: () {
              setState(() => _quotaPanelOpen = !_quotaPanelOpen);
              if (_quotaPanelOpen) {
                _rotateCtrl.forward();
              } else {
                _rotateCtrl.reverse();
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Colors.white,
              child: Row(
                children: [
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBlue.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.bar_chart_rounded, size: 18, color: AppTheme.primaryBlue),
                  ),
                  const SizedBox(width: 10),
                  const Text('Scheduled Email Quota',
                      style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w700, fontSize: 15, color: AppTheme.textDark)),
                  const Spacer(),
                  RotationTransition(
                    turns: Tween(begin: 0.0, end: 0.5).animate(_rotateCtrl),
                    child: const Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.textMid),
                  ),
                ],
              ),
            ),
          ),

          // Content
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 250),
            crossFadeState: _quotaPanelOpen ? CrossFadeState.showFirst : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: quotaData.entries.map((senderEntry) {
                  final sender = senderEntry.key;
                  final dateMap = senderEntry.value;
                  // Sort dates
                  final sortedDates = dateMap.keys.toList()
                    ..sort((a, b) {
                      final dA = _parseDate(a);
                      final dB = _parseDate(b);
                      if (dA == null || dB == null) return 0;
                      return dA.compareTo(dB);
                    });

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8, top: 4),
                        child: Row(children: [
                          const Icon(Icons.email_rounded, size: 13, color: AppTheme.textMid),
                          const SizedBox(width: 5),
                          Flexible(child: Text(sender,
                              style: const TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textMid),
                              overflow: TextOverflow.ellipsis)),
                        ]),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: sortedDates.map((dateStr) {
                          final list = dateMap[dateStr]!;
                          final total = list.fold<int>(0, (s, c) => s + c.count);
                          final capped = min(total, 50);
                          return _QuotaDateChip(
                            dateStr: dateStr,
                            total: capped,
                            contributions: list,
                            color: _quotaColor(capped),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 8),
                    ],
                  );
                }).toList(),
              ),
            ),
            secondChild: const SizedBox.shrink(),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  // ── Email Card ─────────────────────────────────────────────────────────
  Widget _buildEmailCard(ScheduledEmail email, int index) {
    final displayName = (email.scheduleName != null && email.scheduleName!.isNotEmpty)
        ? email.scheduleName!
        : email.subject.isNotEmpty ? email.subject : '(No Name)';
    final isMerged = email.isMerged;
    final typeColor = _typeColor(email.type, isMerged);
    final statusColor = _statusColor(email.status);

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
            border: Border.all(
              color: isMerged
                  ? const Color(0xFF8B5CF6).withOpacity(0.3)
                  : AppTheme.divider,
              width: isMerged ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(color: typeColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                  child: Icon(
                    isMerged ? Icons.merge_rounded : (email.type == 'PDF' ? Icons.picture_as_pdf_rounded : Icons.email_rounded),
                    color: typeColor, size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(displayName,
                        style: const TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w600, fontSize: 15, color: AppTheme.textDark),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: typeColor.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                        child: Text(isMerged ? 'Merged PDF' : email.type,
                            style: TextStyle(fontFamily: 'Inter', fontSize: 10, color: typeColor, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 6),
                      Expanded(child: Text(
                          '${email.recipients.length} recipient${email.recipients.length == 1 ? '' : 's'}  |  ${email.scheduledDate}',
                          style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.textLight),
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ]),
                  ],
                )),
                const SizedBox(width: 8),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                    child: Text(email.status.length > 18 ? '${email.status.substring(0, 18)}...' : email.status,
                        style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: statusColor, fontWeight: FontWeight.w600)),
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

              // Merge contribution breakdown
              if (isMerged && email.mergeContributions.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withOpacity(0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF8B5CF6).withOpacity(0.15)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.merge_rounded, size: 12, color: Color(0xFF8B5CF6)),
                        const SizedBox(width: 5),
                        const Text('Proportional Merge', style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF8B5CF6))),
                        const Spacer(),
                        Text('${email.sentCount}/${email.recipients.length} sent',
                            style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.textMid)),
                      ]),
                      const SizedBox(height: 6),
                      ...email.mergedSourceIds.map((sid) {
                        final sName = email.mergeSourceNames[sid] ?? sid;
                        final sAlloc = email.mergeContributions[sid] ?? 0;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Row(children: [
                            const Icon(Icons.circle, size: 6, color: Color(0xFF8B5CF6)),
                            const SizedBox(width: 6),
                            Expanded(child: Text(sName,
                                style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.textDark),
                                overflow: TextOverflow.ellipsis)),
                            Text('$sAlloc/day',
                                style: const TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textMid)),
                          ]),
                        );
                      }),
                    ],
                  ),
                ),
              ],

              // Queue-after info
              if (email.queuedAfter != null && email.queuedAfter!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.2)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.schedule_rounded, size: 13, color: AppTheme.primaryBlue),
                    const SizedBox(width: 6),
                    const Expanded(child: Text('Queued — will start after previous PDF completes',
                        style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.primaryBlue))),
                  ]),
                ),
              ],
            ],
          ),
        ),
      ),
    ).animate(delay: Duration(milliseconds: index * 40)).fadeIn().slideY(begin: 0.05, end: 0);
  }
}

// ── Data classes ─────────────────────────────────────────────────────────────

class _DateContribution {
  final String scheduleId;
  final String scheduleName;
  final int count;
  final String type;
  final bool isMerged;
  final String? dayInfo;

  _DateContribution({
    required this.scheduleId,
    required this.scheduleName,
    required this.count,
    required this.type,
    required this.isMerged,
    this.dayInfo,
  });
}

// ── Quota Date Chip ───────────────────────────────────────────────────────────
class _QuotaDateChip extends StatefulWidget {
  final String dateStr;
  final int total;
  final List<_DateContribution> contributions;
  final Color color;
  const _QuotaDateChip({required this.dateStr, required this.total, required this.contributions, required this.color});
  @override
  State<_QuotaDateChip> createState() => _QuotaDateChipState();
}

class _QuotaDateChipState extends State<_QuotaDateChip> {
  bool _expanded = false;

  String _formatDate(String d) {
    try {
      final day = int.parse(d.substring(0, 2));
      final month = int.parse(d.substring(3, 5));
      const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return '$day ${months[month - 1]}';
    } catch (_) {
      return d;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        decoration: BoxDecoration(
          color: widget.color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: widget.color.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Chip header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_formatDate(widget.dateStr),
                      style: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w700, color: widget.color)),
                  const SizedBox(width: 6),
                  Text('${widget.total}/50',
                      style: TextStyle(fontFamily: 'Outfit', fontSize: 12, fontWeight: FontWeight.w800, color: widget.color)),
                  const SizedBox(width: 4),
                  Icon(_expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                      size: 14, color: widget.color),
                ],
              ),
            ),
            // Expanded breakdown
            if (_expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(height: 1, color: widget.color.withOpacity(0.15), margin: const EdgeInsets.only(bottom: 6)),
                    ...widget.contributions.map((c) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6, height: 6,
                            decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 6),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 140),
                            child: Text(c.scheduleName,
                                style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.textDark),
                                overflow: TextOverflow.ellipsis),
                          ),
                          const SizedBox(width: 4),
                          Text('→ ${c.count}${c.dayInfo != null ? ' (${c.dayInfo})' : ''}',
                              style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: widget.color, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    )),
                    const SizedBox(height: 2),
                    Text('Total: ${widget.total}/50',
                        style: TextStyle(fontFamily: 'Outfit', fontSize: 11, fontWeight: FontWeight.w700, color: widget.color)),
                  ],
                ),
              ).animate().fadeIn(duration: 200.ms).slideY(begin: -0.1, end: 0),
          ],
        ),
      ),
    );
  }
}
