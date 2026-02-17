import 'package:flutter/material.dart';

class TimerDisplay extends StatelessWidget {
  final int seconds;
  TimerDisplay(this.seconds);

  String formatTime(int s) {
    final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) =>
      Center(child: Text(formatTime(seconds), style: TextStyle(fontSize: 48)));
}
