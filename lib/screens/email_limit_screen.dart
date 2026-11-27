import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/scheduled_email.dart';
import '../services/backend_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../utils/date_helpers.dart';
import '../widgets/glass_widgets.dart';

class EmailLimitScreen extends StatefulWidget {
  const EmailLimitScreen({super.key});

  @override
  State<EmailLimitScreen> createState() => _EmailLimitScreenState();
}

class _EmailLimitScreenState extends State<EmailLimitScreen>
    with TickerProviderStateMixin {
  static const int _dailyCap = 50;

  Map<String, int> _todayLimits = {};
  Map<String, Map<String, int>> _history = {};
  String _selectedDate = 'Today'; // 'Today' | 'DD/MM/YYYY' | 'All'
  String _statusFilter = 'All'; // 'All' | 'Active' | 'Near' | 'Full' | 'Unused'
  final TextEditingController _searchCtrl = TextEditingController();

  bool _isLoading = true;
  Timer? _refreshTimer;
  StreamSubscription<void>? _realtimeSub;
  late AnimationController _spinController;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _searchCtrl.addListener(() => setState(() {}));
    _loadLimits();
    _realtimeSub = BackendService.onDataChanged.listen((_) => _loadLimits(silent: true));
    _refreshTimer = Timer.periodic(const Duration(seconds: 12), (_) => _loadLimits(silent: true));
    _scheduleMidnightReset();
  }

  void _scheduleMidnightReset() {
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day + 1, 0, 0, 1);
    Future.delayed(midnight.difference(now), () {
      if (mounted) {
        _loadLimits();
        _scheduleMidnightReset();
      }
    });
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    _refreshTimer?.cancel();
    _spinController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLimits({bool silent = false}) async {
    if (!silent && mounted) setState(() => _isLoading = true);

    try {
      final results = await Future.wait([
        BackendService.fetchDailyLimits(),
        StorageService.getSenderEmails(),
        BackendService.fetchCampaigns().catchError((_) => <ScheduledEmail>[]),
        StorageService.getDailyLimitsHistory(),
      ]);

      final live = results[0] as Map<String, int>;
      final savedSenders = results[1] as List<String>;
      final campaigns = results[2] as List<dynamic>;
      final savedHistory = results[3] as Map<String, Map<String, int>>;

      final merged = <String, int>{};
      for (final s in savedSenders) {
        final key = s.trim().toLowerCase();
        if (key.isNotEmpty) merged.putIfAbsent(key, () => 0);
      }
      for (final c in campaigns) {
        final key = (c.senderEmail as String).trim().toLowerCase();
        if (key.isNotEmpty) merged.putIfAbsent(key, () => 0);
      }
      for (final e in live.entries) {
        final key = e.key.trim().toLowerCase();
        if (key.isNotEmpty) merged[key] = e.value;
      }

      final todayKey = DateHelpers.todayDmy();
      await StorageService.saveDailyLimitsSnapshot(todayKey, merged);
      savedHistory[todayKey] = merged;

      if (mounted) {
        setState(() {
          _todayLimits = merged;
          _history = savedHistory;
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    } catch (_) {
      final fallbackHistory = await StorageService.getDailyLimitsHistory();
      final todayKey = DateHelpers.todayDmy();
      if (mounted) {
        setState(() {
          _history = fallbackHistory;
          _todayLimits = fallbackHistory[todayKey] ?? {};
          _isLoading = false;
          _isRefreshing = false;
        });
      }
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

  Color _colorFor(int count) {
    if (count >= _dailyCap) return AppTheme.errorRed;
    if (count >= 31) return AppTheme.warningAmber;
    if (count >= 21) return const Color(0xFFF97316);
    if (count > 0) return AppTheme.successGreen;
    return AppTheme.primaryBlue;
  }

  String _todayLabel() {
    final now = DateTime.now();
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    const weekdays = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
    ];
    return '${weekdays[now.weekday - 1]}, ${now.day} ${months[now.month - 1]} ${now.year}';
  }

  Map<String, int> get _activeDataset {
    if (_selectedDate == 'Today') {
      return _todayLimits;
    }
    if (_selectedDate == 'All') {
      final totals = <String, int>{};
      for (final dayMap in _history.values) {
        for (final entry in dayMap.entries) {
          totals[entry.key] = (totals[entry.key] ?? 0) + entry.value;
        }
      }
      for (final k in _todayLimits.keys) {
        totals.putIfAbsent(k, () => 0);
      }
      return totals;
    }
    return _history[_selectedDate] ?? _todayLimits;
  }

  List<MapEntry<String, int>> get _filteredEntries {
    final q = _searchCtrl.text.trim().toLowerCase();
    final entries = _activeDataset.entries.where((e) {
      if (q.isNotEmpty && !e.key.contains(q)) return false;
      final v = e.value;
      switch (_statusFilter) {
        case 'Active':
          return v > 0;
        case 'Near':
          return v >= 31 && v < _dailyCap;
        case 'Full':
          return v >= _dailyCap;
        case 'Unused':
          return v == 0;
        default:
          return true;
      }
    }).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final todayKey = DateHelpers.todayDmy();
    final pastDates = _history.keys.where((d) => d != todayKey).toList().reversed.toList();
    final dateOptions = ['Today', ...pastDates, 'All'];
    final entries = _filteredEntries;
    final dataset = _activeDataset;
    final totalSent = dataset.values.fold<int>(0, (sum, v) => sum + v);
    final isAllDays = _selectedDate == 'All';
    final maxCapacity = isAllDays
        ? math.max(1, dataset.length * _dailyCap * math.max(1, _history.length))
        : math.max(1, dataset.length * _dailyCap);
    final capacityPct = dataset.isEmpty ? 0.0 : (totalSent / maxCapacity).clamp(0.0, 1.0);
    final accent = AppTheme.isDark(context) ? AppTheme.lightBlue : AppTheme.primaryBlue;

    return Scaffold(
      backgroundColor: AppTheme.surfaceBg(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        flexibleSpace: buildGlassAppBarBackground(),
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: AppTheme.textPrimary(context)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Email Limits & Analytics',
              style: TextStyle(
                fontFamily: 'Outfit',
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: AppTheme.textPrimary(context),
              ),
            ),
            Row(
              children: [
                Icon(Icons.calendar_today_rounded, size: 11, color: accent),
                const SizedBox(width: 4),
                Text(
                  _todayLabel(),
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: accent,
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
              icon: Icon(Icons.refresh_rounded, color: accent),
              onPressed: _refresh,
              tooltip: 'Refresh',
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: AppTheme.border(context)),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ResponsiveCenter(
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  // ── Power BI Summary + Animated Donut Gauge ─────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppTheme.primaryBlue, AppTheme.accentBlue],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primaryBlue.withValues(alpha: 0.28),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0, end: capacityPct),
                              duration: const Duration(milliseconds: 850),
                              curve: Curves.easeOutCubic,
                              builder: (context, val, _) => SizedBox(
                                width: 76,
                                height: 76,
                                child: CustomPaint(
                                  painter: _CapacityRingPainter(progress: val),
                                  child: Center(
                                    child: Text(
                                      '${(val * 100).toStringAsFixed(0)}%',
                                      style: const TextStyle(
                                        fontFamily: 'Outfit',
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _selectedDate == 'Today'
                                        ? 'Today Sent'
                                        : (_selectedDate == 'All' ? 'All Saved Days Sent' : 'Sent on $_selectedDate'),
                                    style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: Colors.white70),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '$totalSent emails',
                                    style: const TextStyle(
                                      fontFamily: 'Outfit',
                                      fontSize: 26,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    children: [
                                      _kpiBadge('${dataset.length} Accounts'),
                                      _kpiBadge('Cap $_dailyCap / day'),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ).animate().fade(duration: 380.ms).slideY(begin: 0.14),
                    ),
                  ),

                  // ── Date Filter Chips (Today + Saved Days + All) ────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: dateOptions.map((d) {
                            final selected = _selectedDate == d;
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                label: Text(
                                  d == 'All' ? 'All Days' : d,
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: selected ? Colors.white : AppTheme.textPrimary(context),
                                  ),
                                ),
                                selected: selected,
                                selectedColor: AppTheme.primaryBlue,
                                backgroundColor: AppTheme.cardBg(context),
                                side: BorderSide(color: selected ? AppTheme.primaryBlue : AppTheme.border(context)),
                                showCheckmark: false,
                                onSelected: (_) => setState(() => _selectedDate = d),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),

                  // ── Search + Status Filter Chips ─────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                      child: Column(
                        children: [
                          TextField(
                            controller: _searchCtrl,
                            decoration: InputDecoration(
                              hintText: 'Filter by sender email...',
                              prefixIcon: const Icon(Icons.search_rounded, size: 18),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              suffixIcon: _searchCtrl.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear_rounded, size: 16),
                                      onPressed: () => _searchCtrl.clear(),
                                    )
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                ('All', 'All'),
                                ('Active', 'Active (>0)'),
                                ('Near', '31–49'),
                                ('Full', 'Limit 50'),
                                ('Unused', 'Unused (0)'),
                              ].map((pair) {
                                final selected = _statusFilter == pair.$1;
                                return Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: ChoiceChip(
                                    label: Text(
                                      pair.$2,
                                      style: TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: selected ? Colors.white : AppTheme.textPrimary(context),
                                      ),
                                    ),
                                    selected: selected,
                                    selectedColor: AppTheme.accentBlue,
                                    backgroundColor: AppTheme.cardBg(context),
                                    side: BorderSide(color: selected ? AppTheme.accentBlue : AppTheme.border(context)),
                                    showCheckmark: false,
                                    onSelected: (_) => setState(() => _statusFilter = pair.$1),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── Power BI Animated Bar Chart ─────────────────────────
                  if (entries.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
                        child: GlassContainer(
                          borderRadius: 20,
                          blurSigma: 12,
                          color: AppTheme.cardBg(context).withValues(alpha: 0.90),
                          borderColor: AppTheme.border(context),
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.bar_chart_rounded, size: 18, color: accent),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Sender Quota Chart (${isAllDays ? "Total" : "Limit $_dailyCap"})',
                                    style: TextStyle(
                                      fontFamily: 'Outfit',
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: AppTheme.textPrimary(context),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              SizedBox(
                                height: 150,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: entries.length,
                                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                                  itemBuilder: (context, idx) {
                                    final item = entries[idx];
                                    final cap = isAllDays
                                        ? math.max(_dailyCap, entries.first.value)
                                        : _dailyCap;
                                    final ratio = (item.value / cap).clamp(0.0, 1.0);
                                    final c = _colorFor(item.value);
                                    final shortName = item.key.split('@').first;
                                    return SizedBox(
                                      width: 54,
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          Text(
                                            '${item.value}',
                                            style: TextStyle(
                                              fontFamily: 'Outfit',
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: c,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Expanded(
                                            child: Container(
                                              width: 24,
                                              alignment: Alignment.bottomCenter,
                                              decoration: BoxDecoration(
                                                color: c.withValues(alpha: 0.12),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: TweenAnimationBuilder<double>(
                                                tween: Tween(begin: 0, end: ratio),
                                                duration: Duration(milliseconds: 550 + (idx * 60).clamp(0, 400)),
                                                curve: Curves.easeOutCubic,
                                                builder: (ctx, animVal, _) => FractionallySizedBox(
                                                  heightFactor: animVal > 0 ? animVal.clamp(0.06, 1.0) : 0.0,
                                                  widthFactor: 1,
                                                  child: Container(
                                                    decoration: BoxDecoration(
                                                      gradient: LinearGradient(
                                                        colors: [c, c.withValues(alpha: 0.7)],
                                                        begin: Alignment.topCenter,
                                                        end: Alignment.bottomCenter,
                                                      ),
                                                      borderRadius: BorderRadius.circular(8),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            shortName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontFamily: 'Inter',
                                              fontSize: 10,
                                              color: AppTheme.textSecondary(context),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ).animate().fade(duration: 360.ms),
                      ),
                    ),

                  // ── Per-account cards ────────────────────────────────────
                  entries.isEmpty
                      ? SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                dataset.isEmpty
                                    ? 'No sender accounts saved yet.\nAuthenticate or schedule an email to track its 50/day limit.'
                                    : 'No accounts match the selected filter.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  color: AppTheme.textSecondary(context),
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        )
                      : SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final sender = entries[index].key;
                                final count = entries[index].value;
                                final double progress = (count / _dailyCap).clamp(0.0, 1.0);
                                final bool limitReached = !isAllDays && count >= _dailyCap;
                                final color = _colorFor(count);

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: GlassContainer(
                                    borderRadius: 20,
                                    blurSigma: 12,
                                    color: AppTheme.cardBg(context).withValues(alpha: 0.88),
                                    borderColor: limitReached
                                        ? AppTheme.errorRed.withValues(alpha: 0.35)
                                        : AppTheme.border(context),
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              width: 42,
                                              height: 42,
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  colors: [color, color.withValues(alpha: 0.6)],
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                ),
                                                shape: BoxShape.circle,
                                              ),
                                              child: Center(
                                                child: Text(
                                                  sender.isNotEmpty ? sender[0].toUpperCase() : '?',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 17,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    sender,
                                                    style: TextStyle(
                                                      fontFamily: 'Outfit',
                                                      fontWeight: FontWeight.w600,
                                                      fontSize: 14,
                                                      color: AppTheme.textPrimary(context),
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    limitReached
                                                        ? 'Daily Limit Reached'
                                                        : (isAllDays ? 'Total across saved days' : 'Daily quota'),
                                                    style: TextStyle(
                                                      fontFamily: 'Inter',
                                                      fontSize: 12,
                                                      color: limitReached
                                                          ? AppTheme.errorRed
                                                          : AppTheme.textSecondary(context),
                                                      fontWeight: limitReached ? FontWeight.w600 : FontWeight.normal,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                              decoration: BoxDecoration(
                                                color: color.withValues(alpha: 0.12),
                                                borderRadius: BorderRadius.circular(20),
                                                border: Border.all(color: color.withValues(alpha: 0.3)),
                                              ),
                                              child: Text(
                                                isAllDays ? '$count sent' : '$count / $_dailyCap',
                                                style: TextStyle(
                                                  fontFamily: 'Outfit',
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 15,
                                                  color: color,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (!isAllDays) ...[
                                          const SizedBox(height: 12),
                                          LayoutBuilder(
                                            builder: (context, constraints) => Stack(
                                              children: [
                                                Container(
                                                  height: 10,
                                                  decoration: BoxDecoration(
                                                    color: color.withValues(alpha: 0.12),
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                ),
                                                AnimatedContainer(
                                                  duration: const Duration(milliseconds: 600),
                                                  curve: Curves.easeOutCubic,
                                                  height: 10,
                                                  width: constraints.maxWidth * progress,
                                                  decoration: BoxDecoration(
                                                    gradient: LinearGradient(
                                                      colors: [color, color.withValues(alpha: 0.7)],
                                                    ),
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                                                '${math.max(0, _dailyCap - count)} remaining',
                                                style: TextStyle(
                                                  fontFamily: 'Inter',
                                                  fontSize: 11,
                                                  color: AppTheme.textSecondary(context),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ],
                                    ),
                                  ).animate().fade(duration: 320.ms, delay: (index * 45).ms),
                                );
                              },
                              childCount: entries.length,
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
                          color: AppTheme.primaryBlue.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppTheme.primaryBlue.withValues(alpha: 0.18)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline_rounded, size: 16, color: accent),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Every sender has a 50/day limit. Daily snapshots are saved locally and reset at 12:00 AM.',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 12,
                                  color: accent,
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
            ),
    );
  }

  Widget _kpiBadge(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      );
}

class _CapacityRingPainter extends CustomPainter {
  final double progress;
  const _CapacityRingPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - 10) / 2;
    const stroke = 8.0;

    final trackPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;

    final fillPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke;

    canvas.drawCircle(center, radius, trackPaint);
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        fillPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_CapacityRingPainter old) => old.progress != progress;
}
