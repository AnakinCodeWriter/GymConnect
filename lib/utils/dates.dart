// Shared short date formatting for screen labels (Phase 11). Replaces three
// identical private month-name tables that had drifted into home, progress
// and weekly review screens.

const List<String> _monthNames = [
  '',
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Abbreviated English month name, 1-based ('Jan'..'Dec').
String monthAbbreviation(int month) => _monthNames[month];

/// "4 Jul" - day-of-month plus abbreviated month.
String formatDayMonth(DateTime d) => '${d.day} ${_monthNames[d.month]}';

/// "4 Jul 2026" - day, abbreviated month and year.
String formatDayMonthYear(DateTime d) =>
    '${d.day} ${_monthNames[d.month]} ${d.year}';
