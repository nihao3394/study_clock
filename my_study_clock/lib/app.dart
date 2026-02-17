import 'package:flutter/material.dart';
import 'pages/study_clock_page.dart';
import 'services/settings_service.dart';
import 'models/setting.dart';

class StudyClockApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppThemeData?>(
      valueListenable: SettingsService().themeNotifier,
      builder: (_, theme, __) => MaterialApp(
        title: '学习钟',
        theme: (theme ?? AppThemeData.defaults[0]).toThemeData(),
        home: StudyClockPage(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
