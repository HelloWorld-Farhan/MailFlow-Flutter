import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

class EmailLimitScreen extends StatefulWidget {
  const EmailLimitScreen({Key? key}) : super(key: key);

  @override
  State<EmailLimitScreen> createState() => _EmailLimitScreenState();
}

class _EmailLimitScreenState extends State<EmailLimitScreen> {
  Map<String, int> _limits = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLimits();
  }

  Future<void> _loadLimits() async {
    final limits = await StorageService.getAllDailyLimits();
    
    // Also add saved senders that might have 0 usage today
    final savedSenders = await StorageService.getSenderEmails();
    for (final sender in savedSenders) {
      if (!limits.containsKey(sender)) {
        limits[sender] = 0;
      }
    }
    
    setState(() {
      _limits = limits;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: AppTheme.textDark),
        title: const Text('Email Limits', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold, color: AppTheme.textDark)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.primaryBlue),
            onPressed: () {
              setState(() => _isLoading = true);
              _loadLimits();
            },
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppTheme.divider),
        ),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : _limits.isEmpty
          ? const Center(
              child: Text(
                'No sender accounts found.',
                style: TextStyle(fontFamily: 'Inter', color: AppTheme.textMid, fontSize: 16),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _limits.length,
              itemBuilder: (context, index) {
                final sender = _limits.keys.elementAt(index);
                final count = _limits[sender]!;
                final double progress = (count / 50.0).clamp(0.0, 1.0);
                final bool limitReached = count >= 50;

                return Card(
                  elevation: 0,
                  color: Colors.white,
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: limitReached ? AppTheme.errorRed.withOpacity(0.1) : AppTheme.primaryBlue.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                limitReached ? Icons.warning_rounded : Icons.email_rounded,
                                color: limitReached ? AppTheme.errorRed : AppTheme.primaryBlue,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    sender,
                                    style: const TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w600, fontSize: 16, color: AppTheme.textDark),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    limitReached ? 'Daily Limit Reached' : 'Daily Limit Usage',
                                    style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: limitReached ? AppTheme.errorRed : AppTheme.textMid, fontWeight: limitReached ? FontWeight.w600 : FontWeight.normal),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '$count / 50',
                              style: TextStyle(
                                fontFamily: 'Outfit', 
                                fontWeight: FontWeight.bold, 
                                fontSize: 18, 
                                color: limitReached ? AppTheme.errorRed : AppTheme.textDark,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 8,
                            backgroundColor: AppTheme.bgLight,
                            valueColor: AlwaysStoppedAnimation<Color>(limitReached ? AppTheme.errorRed : AppTheme.primaryBlue),
                          ),
                        ),
                      ],
                    ),
                  ),
                ).animate().fade(duration: 400.ms, delay: (index * 50).ms).slideY(begin: 0.2, end: 0.0);
              },
            ),
    );
  }
}
