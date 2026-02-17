class LogEntry {
  final DateTime time;
  final String subject;
  final String duration;
  final String notes;

  LogEntry({
    required this.time,
    required this.subject,
    required this.duration,
    required this.notes,
  });

  @override
  String toString() =>
      "${time.toIso8601String()} | $subject | $duration | 备注:$notes";
}
