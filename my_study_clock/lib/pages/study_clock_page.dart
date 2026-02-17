import 'package:flutter/material.dart';
import '../services/timer_service.dart';
import '../services/log_service.dart';
import '../services/settings_service.dart';
import '../widgets/subject_sidebar.dart';
import '../widgets/duration_selector.dart';
import '../widgets/log_filter_bar.dart';
import '../widgets/timer_display.dart';
import '../widgets/main_controls.dart';
import '../pages/settings_page.dart';
import '../models/subject.dart';
import '../widgets/log_viewer.dart'; // <- 补充导入日志组件

class StudyClockPage extends StatefulWidget {
  const StudyClockPage({Key? key}) : super(key: key);

  @override
  _StudyClockPageState createState() => _StudyClockPageState();
}

class _StudyClockPageState extends State<StudyClockPage>
    with WidgetsBindingObserver {
  final TimerService timerService = TimerService();
  final LogService logService = LogService();
  final SettingsService settingsService = SettingsService();
  List<Subject> subjects = [];
  Subject? currentSubject;
  DateTime selectedDay = DateTime.now();
  int? filterYear;
  int? filterMonth;
  int? filterDay;
  List<String> logs = [];

  // 补齐日志选择变量
  List<int> years = [];
  List<int> months = [];
  List<int> days = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    logService.init(settingsService.logCleanDays);

    (() async {
      // 假如 logs 目录结构为 /logs/年/月/log_日.txt 可自动补全这些变量
      // 简单例子，近五年/年/月皆有，否则可通过logService扫描目录得到
      final now = DateTime.now();
      years = [for (int y = now.year - 4; y <= now.year; ++y) y];
      months = [for (int m = 1; m <= 12; ++m) m];
      days = [
        for (int d = 1; d <= 31; ++d) d,
      ]; // 或 logService.getDaysWithLogs(filterYear, filterMonth)

      // logs = await logService.readLogs(year: filterYear, month: filterMonth, day: filterDay);
      // subjects = await SubjectService().loadSubjects(); // 根据你的结构实现
      setState(() {});
    })();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached ||
        state == AppLifecycleState.paused) {
      final secs = timerService.saveOnCrash();
      if (secs > 0) logService.writeLog("意外关闭自动记录,时长${secs}s", DateTime.now());
    }
  }

  void _onSubjectReordered(int oldIndex, int newIndex) {
    setState(() {
      final item = subjects.removeAt(oldIndex);
      subjects.insert(newIndex, item);
      // 保存顺序到Subject文件
    });
  }

  void _onLogFilterChanged({int? year, int? month, int? day}) async {
    setState(() {
      filterYear = year;
      filterMonth = month;
      filterDay = day;
      // 查询日志async
      // logs = await logService.readLogs(year: year, month: month, day: day);
    });
  }

  void _onOpenCalendar() {
    // showDialog(日历), 选中某天时调用 _onLogFilterChanged(day: ...)
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.settings),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => SettingsPage()),
          ),
        ),
        title: Text("学习钟"),
        backgroundColor: theme.colorScheme.surface,
      ),
      body: Row(
        children: [
          Flexible(
            flex: 2,
            child: SubjectSidebar(
              subjects: subjects,
              selected: currentSubject,
              onReorder: _onSubjectReordered,
              onEdit: (subj) {
                /*...*/
              },
              onSelect: (subj) {
                setState(() => currentSubject = subj);
              },
            ),
          ),
          Expanded(
            flex: 7,
            child: Column(
              children: [
                Row(
                  children: [
                    LogFilterBar(
                      years: years,
                      months: months,
                      days: days,
                      year: filterYear,
                      month: filterMonth,
                      day: filterDay,
                      onChanged: (y, m, d) =>
                          _onLogFilterChanged(year: y, month: m, day: d),
                    ),
                    IconButton(
                      icon: Icon(Icons.calendar_today),
                      onPressed: _onOpenCalendar,
                    ),
                  ],
                ),
                Expanded(child: LogViewer(logLines: logs)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
