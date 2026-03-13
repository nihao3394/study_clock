import 'package:flutter/material.dart';
import 'pages/study_clock_page.dart';

void main() {
  runApp(const StudyClockApp());
}

class StudyClockApp extends StatelessWidget {
  const StudyClockApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '学习钟',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2196F3),
          brightness: Brightness.dark,
          primary: const Color(0xFF42A5F5),
          secondary: const Color(0xFF66BB6A),
          surface: const Color(0xFF1A1A2E),
          background: const Color(0xFF161625),
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: Colors.white70,
        ),
      ),
      home: const StudyClockPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}
