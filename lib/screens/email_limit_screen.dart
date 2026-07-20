import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

class EmailLimitScreen extends StatefulWidget {
  const EmailLimitScreen({Key? key}) : super(key: key);

  @override
  State<EmailLimitScreen> createState() => _EmailLimitScreenState();
}

class _EmailLimitScreenState extends State<EmailLimitScreen>
    with TickerProviderStateMixin {
  Map<String, int> _limits = {};
  bool _isLoading = true;
  Timer? _refreshTimer;
  late AnimationController _spinController;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _loadLimits();
    // Auto-refresh every 5 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _loadLimits(silent: true);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _spinController.dispose();
    super.dispose();
  }

  Future<void> _loadLimits({bool silent = false}) async {
    if (!silent && mounted) setState(() => _isLoading = true);

    final limits = await StorageService.getAllDailyLimits();

    // Also add saved senders with 0 usage
    final savedSenders = await StorageService.getSenderEmails();
    for (final sender in savedSenders) {
      if (!limits.containsKey(sender)) {
        limits[sender] = 0;
      }
    }

    if (mounted) {
      setState(() {
        _limits = Map.fromEntries(
          limits.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
        );
        _isLoading = false;
        _isRefreshing = false;
      });
    }
  }

  Future<void> _refresh() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    _spinController.repeat();
    await _loadLimits();
    _spinController.stop();
    _spinController.reset();
  }

  /// Returns a color for the given sent count
  Color _colorFor(int count) {
    if (count >= 50) return AppTheme.errorRed;
    if (count >= 31) return AppTheme.warningAmber;
    if (count >= 21) return const Color(0xFFF97316); // Orange
    return AppTheme.successGreen;
  }

  String _todayLabel() {
    final now = DateTime.now();
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${now.day} ${months[now.month - 1]} ${now.year}';
  }

  @override
  Widget build(BuildContext context) {
    final totalSent = _limits.values.fold<int>(0, (sum, v) => sum + v);

    return Scaffold(
      backgroundColor: AppTheme.bgSurface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: AppTheme.textDark),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Email Limits',
              style: TextStyle(
                fontFamily: 'Outfit',
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: AppTheme.textDark,
              ),
            ),
            Row(
              children: [
                const Icon(Icons.calendar_today_rounded,
                    size: 11, color: AppTheme.primaryBlue),
                const SizedBox(width: 4),
                Text(
                  _todayLabel(),
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.primaryBlue,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          AnimatedBuilder(
            animation: _spinController,
            builder: (_, child) => Transform.rotate(
              angle: _spinController.value * 6.283,
              child: child,
            ),
            child: IconButton(
              icon: const Icon(Icons.refresh_rounded, color: AppTheme.primaryBlue),
              onPressed: _refresh,
              tooltip: 'Refresh',
            ),
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppTheme.divider),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                // ── Summary card ────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppTheme.primaryBlue, AppTheme.accentBlue],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryBlue.withOpacity(0.3),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(Icons.speed_rounded,
                                color: Colors.white, size: 28),
                          ),
                          const SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Total Sent Today',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 13,
                                  color: Colors.white70,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$totalSent emails',
                                style: const TextStyle(
                                  fontFamily: 'Outfit',
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text(
                                'Accounts',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 12,
                                  color: Colors.white60,
                                ),
                              ),
                              Text(
                                '${_limits.length}',
                                style: const TextStyle(
                                  fontFamily: 'Outfit',
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ).animate().fade(duration: 400.ms).slideY(begin: 0.2),
                  ),
                ),

                // ── Legend ───────────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Row(
                      children: [
                        _LegendDot(color: AppTheme.successGreen, label: '0–20'),
                        const SizedBox(width: 12),
                        _LegendDot(color: const Color(0xFFF97316), label: '21–30'),
                        const SizedBox(width: 12),
                        _LegendDot(color: AppTheme.warningAmber, label: '31–49'),
                        const SizedBox(width: 12),
                        _LegendDot(color: AppTheme.errorRed, label: '50'),
                      ],
                    ),
                  ),
                ),

                // ── Per-account cards ────────────────────────────────────
                _limits.isEmpty
                    ? const SliverFillRemaining(
                        child: Center(
                          child: Text(
                            'No sender accounts found.\nSchedule an email to see data.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              color: AppTheme.textMid,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      )
                    : SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final sender =
                                  _limits.keys.elementAt(index);
                              final count = _limits[sender]!;
                              final double progress =
                                  (count / 50.0).clamp(0.0, 1.0);
                              final bool limitReached = count >= 50;
                              final color = _colorFor(count);

                              return Padding(
                                padding:
                                    const EdgeInsets.only(bottom: 12),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius:
                                        BorderRadius.circular(20),
                                    border: Border.all(
                                      color: limitReached
                                          ? AppTheme.errorRed
                                              .withOpacity(0.3)
                                          : AppTheme.divider,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: color.withOpacity(0.06),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(18),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            // Avatar circle
                                            Container(
                                              width: 44,
                                              height: 44,
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  colors: [
                                                    color,
                                                    color.withOpacity(0.6)
                                                  ],
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                ),
                                                shape: BoxShape.circle,
                                              ),
                                              child: Center(
                                                child: Text(
                                                  sender.isNotEmpty
                                                      ? sender[0]
                                                          .toUpperCase()
                                                      : '?',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight:
                                                        FontWeight.w800,
                                                    fontSize: 18,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 14),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment
                                                        .start,
                                                children: [
                                                  Text(
                                                    sender,
                                                    style: const TextStyle(
                                                      fontFamily: 'Outfit',
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize: 14,
                                                      color:
                                                          AppTheme.textDark,
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    limitReached
                                                        ? '🚫 Daily Limit Reached'
                                                        : 'Emails sent today',
                                                    style: TextStyle(
                                                      fontFamily: 'Inter',
                                                      fontSize: 12,
                                                      color: limitReached
                                                          ? AppTheme.errorRed
                                                          : AppTheme.textMid,
                                                      fontWeight: limitReached
                                                          ? FontWeight.w600
                                                          : FontWeight.normal,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            // Count badge
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 6),
                                              decoration: BoxDecoration(
                                                color:
                                                    color.withOpacity(0.1),
                                                borderRadius:
                                                    BorderRadius.circular(
                                                        20),
                                                border: Border.all(
                                                    color: color
                                                        .withOpacity(0.3)),
                                              ),
                                              child: Text(
                                                '$count / 50',
                                                style: TextStyle(
                                                  fontFamily: 'Outfit',
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 16,
                                                  color: color,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 14),
                                        // Animated progress bar
                                        Stack(
                                          children: [
                                            // Background
                                            Container(
                                              height: 10,
                                              decoration: BoxDecoration(
                                                color: color.withOpacity(0.1),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                            ),
                                            // Foreground
                                            AnimatedContainer(
                                              duration: const Duration(
                                                  milliseconds: 600),
                                              curve: Curves.easeOutCubic,
                                              height: 10,
                                              width: (MediaQuery.of(context)
                                                              .size
                                                              .width -
                                                          68) *
                                                      progress,
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  colors: [
                                                    color,
                                                    color.withOpacity(0.7),
                                                  ],
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: color
                                                        .withOpacity(0.4),
                                                    blurRadius: 4,
                                                    offset:
                                                        const Offset(0, 2),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              '${(progress * 100).toStringAsFixed(0)}% used',
                                              style: TextStyle(
                                                fontFamily: 'Inter',
                                                fontSize: 11,
                                                color: color,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            Text(
                                              '${50 - count} remaining',
                                              style: const TextStyle(
                                                fontFamily: 'Inter',
                                                fontSize: 11,
                                                color: AppTheme.textLight,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ).animate().fade(
                                    duration: 400.ms,
                                    delay: (index * 60).ms),
                              );
                            },
                            childCount: _limits.length,
                          ),
                        ),
                      ),

                // ── Reset info ───────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryBlue.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: AppTheme.primaryBlue.withOpacity(0.15)),
                      ),
                      child: Row(
                        children: const [
                          Icon(Icons.info_outline_rounded,
                              size: 16, color: AppTheme.primaryBlue),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Limits reset automatically at 12:00 AM every day.',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 12,
                                color: AppTheme.primaryBlue,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
              fontFamily: 'Inter', fontSize: 11, color: AppTheme.textMid),
        ),
      ],
    );
  }
}
