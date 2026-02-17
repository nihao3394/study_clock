import 'package:flutter/material.dart';
// 注意写法: 下划线连接!
import 'package:table_calendar/table_calendar.dart';

class CalendarPopup extends StatelessWidget {
  final int year, month;
  final Set<int> logDays;
  final void Function(DateTime) onDaySelected;
  CalendarPopup({
    required this.year,
    required this.month,
    required this.logDays,
    required this.onDaySelected,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final firstDay = DateTime(year, month, 1);
    final lastDay = (month < 12)
        ? DateTime(year, month + 1, 0)
        : DateTime(year + 1, 1, 0);

    return Dialog(
      child: SizedBox(
        width: 380,
        height: 420,
        child: TableCalendar(
          firstDay: firstDay,
          lastDay: lastDay,
          focusedDay: DateTime.now(),
          calendarFormat: CalendarFormat.month,
          selectedDayPredicate: (d) => logDays.contains(d.day),
          onDaySelected: (selectedDay, focusedDay) =>
              onDaySelected(selectedDay),
          calendarBuilders: CalendarBuilders(
            defaultBuilder: (ctx, day, focusedDay) {
              final hasLog = logDays.contains(day.day);
              return Center(
                child: Text(
                  '${day.day}',
                  style: TextStyle(
                    color: hasLog ? Colors.white : Colors.white38,
                    fontWeight: hasLog ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
