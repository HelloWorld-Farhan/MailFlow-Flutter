/// Shared date/time formatting and schedule validation helpers.
class DateHelpers {
  static const List<String> _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  static String formatDmy(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';

  static String todayDmy() => formatDmy(DateTime.now());

  static DateTime? parseDmy(String dateStr) {
    final parts = dateStr.split('/');
    if (parts.length != 3) return null;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) return null;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final dt = DateTime(year, month, day);
    if (dt.year != year || dt.month != month || dt.day != day) return null;
    return dt;
  }

  static String weekdayName(String dateStr) {
    final dt = parseDmy(dateStr);
    if (dt == null) return '';
    return _weekdays[dt.weekday - 1];
  }

  /// Parses `dd/MM/yyyy` + `hh:mm AM/PM` into a local [DateTime].
  static DateTime parseScheduleDateTime(String dateStr, String timeStr) {
    final dParts = dateStr.split('/');
    final tParts = timeStr.split(' ');
    final hm = tParts[0].split(':');
    int hour = int.parse(hm[0]);
    final minute = int.parse(hm[1]);
    final isPm = tParts.length > 1 && tParts[1].toUpperCase() == 'PM';
    if (isPm && hour != 12) hour += 12;
    if (!isPm && hour == 12) hour = 0;
    return DateTime(
      int.parse(dParts[2]),
      int.parse(dParts[1]),
      int.parse(dParts[0]),
      hour,
      minute,
    );
  }

  static bool isFutureDateTime(String dateStr, String timeStr) {
    try {
      final scheduled = parseScheduleDateTime(dateStr, timeStr);
      final now = DateTime.now();
      return !scheduled.isBefore(DateTime(now.year, now.month, now.day, now.hour, now.minute));
    } catch (_) {
      return false;
    }
  }

  static bool isFutureDmyTime(String d, String t, bool am) {
    if (parseDmy(d) == null || t.length != 5) return false;
    return isFutureDateTime(d, '$t ${am ? "AM" : "PM"}');
  }
}
