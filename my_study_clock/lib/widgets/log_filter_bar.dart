import 'package:flutter/material.dart';

class LogFilterBar extends StatelessWidget {
  final List<int> years;
  final List<int> months;
  final List<int> days;
  final int? year, month, day;
  final Function(int? year, int? month, int? day) onChanged;
  LogFilterBar({
    required this.years,
    required this.months,
    required this.days,
    this.year,
    this.month,
    this.day,
    required this.onChanged,
  });

  Widget _drop<T>(
    List<T> items,
    T? value,
    void Function(T?) setFunc,
    String label,
  ) {
    return DropdownButton<T>(
      value: value,
      hint: Text(label),
      items: items
          .map((v) => DropdownMenuItem(value: v, child: Text('$v')))
          .toList(),
      onChanged: setFunc,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _drop(years, year, (v) => onChanged(v, month, day), '年'),
        _drop(months, month, (v) => onChanged(year, v, day), '月'),
        _drop(days, day, (v) => onChanged(year, month, v), '日'),
      ],
    );
  }
}
