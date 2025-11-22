import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';

void main() {
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    WidgetsFlutterBinding.ensureInitialized();
  }
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
          primary: const Color(0xFF42A5F5),
          secondary: const Color(0xFF66BB6A),
          surface: const Color(0xFF1A1A2E),
          background: const Color(0xFF161625),
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: Colors.white70,
        ),
        cardTheme: CardThemeData(
          elevation: 6,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          color: const Color(0xFF24243E),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF3A3A5A)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF42A5F5), width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          labelStyle: const TextStyle(color: Colors.white60),
          hintStyle: const TextStyle(color: Colors.white54),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
            foregroundColor: Colors.white,
          ),
        ),
      ),
      home: const StudyClockPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// 学科数据模型
class Subject {
  final String name;
  final int priority; // 0:蓝色, 1:绿色, 2:黄色, 3:橙色, 4:红色
  final List<String> goals;

  Subject({required this.name, this.priority = 0, this.goals = const []});

  Map<String, dynamic> toJson() {
    return {'name': name, 'priority': priority, 'goals': goals};
  }

  factory Subject.fromJson(Map<String, dynamic> json) {
    return Subject(
      name: json['name'],
      priority: json['priority'],
      goals: List<String>.from(json['goals'] ?? []),
    );
  }
}

// 学科累计时长统计模型
class SubjectStat {
  final String subjectName;
  int totalSeconds; // 累计时长（秒）

  SubjectStat({required this.subjectName, this.totalSeconds = 0});

  Map<String, dynamic> toJson() {
    return {'subjectName': subjectName, 'totalSeconds': totalSeconds};
  }

  factory SubjectStat.fromJson(Map<String, dynamic> json) {
    return SubjectStat(
      subjectName: json['subjectName'],
      totalSeconds: json['totalSeconds'] ?? 0,
    );
  }
}

class StudyClockPage extends StatefulWidget {
  const StudyClockPage({super.key});

  @override
  State<StudyClockPage> createState() => _StudyClockPageState();
}

class _StudyClockPageState extends State<StudyClockPage>
    with SingleTickerProviderStateMixin {
  int _seconds = 0;
  bool _isRunning = false;
  Timer? _timer;
  final List<String> _studyLogs = [];
  final TextEditingController _noteController = TextEditingController();
  late File _logFile;
  late File _subjectsFile;
  late File _subjectStatsFile; // 学科累计时长文件
  late AnimationController _breathController;

  // 倒计时核心状态
  int? _targetDurationMinutes; // 目标时长（分钟），null表示自由计时
  int _selectedCustomMinutes = 30;
  FixedExtentScrollController? _customMinutesController;
  bool _enableRingtone = true;
  final AudioPlayer _audioPlayer = AudioPlayer();

  // 铃声状态
  List<Map<String, String>> _builtInRingtones = [
    {"name": "提示音1", "path": "sounds/clockstone_1.mp3"},
    {"name": "提示音2", "path": "sounds/clockstone_2.mp3"},
    {"name": "提示音3", "path": "sounds/clockstone_3.mp3"},
    {"name": "提示音4", "path": "sounds/clockstone_cs.mp3"},
  ];
  String? _selectedRingtonePath;
  String? _customRingtoneFilePath;
  bool _isPlayingPreview = false; // 预览播放状态
  PlayerState _audioPlayerState = PlayerState.stopped; // 音频播放器状态

  // 可折叠区域（设置区）
  bool _isSettingsExpanded = true;

  // 左侧侧边栏是否整体展开（与每个学科详情展开独立）
  bool _isSidebarExpanded = true;

  // 学科相关状态 - 支持多个同时展开
  List<Subject> _subjects = [];
  List<SubjectStat> _subjectStats = []; // 学科累计时长统计
  Subject? _currentSubject;
  final Set<String> _expandedSubjects = {}; // 使用学科 name 标识展开项

  // 计时开始时间（用于计算实际学习时长）
  DateTime? _timerStartTime;

  // 动画参数
  static const Duration _panelAnimDuration = Duration(milliseconds: 450);
  static const Curve _panelAnimCurve = Curves.easeInOutCubic;

  @override
  void initState() {
    super.initState();
    _initFiles();
    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _selectedRingtonePath = _builtInRingtones[0]["path"];
    _preloadRingtone();
    _customMinutesController = FixedExtentScrollController(
      initialItem: _selectedCustomMinutes - 1,
    );

    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _audioPlayerState = state;
          if (state == PlayerState.stopped) {
            _isPlayingPreview = false;
          }
        });
      }
    });
  }

  Future<void> _initFiles() async {
    final directory = await getApplicationDocumentsDirectory();
    _logFile = File('${directory.path}/StudyClockLogs.txt');
    _subjectsFile = File('${directory.path}/StudyClockSubjects.json');
    _subjectStatsFile = File('${directory.path}/StudyClockSubjectStats.json');
    await _initLogFile();
    await _initSubjects();
    await _initSubjectStats();
  }

  Future<void> _initLogFile() async {
    if (await _logFile.exists()) {
      final content = await _logFile.readAsString();
      if (content.isNotEmpty) {
        setState(() {
          _studyLogs.addAll(
            content.split('\n').where((line) => line.isNotEmpty),
          );
        });
      }
    }
  }

  Future<void> _initSubjects() async {
    if (await _subjectsFile.exists()) {
      final content = await _subjectsFile.readAsString();
      if (content.isNotEmpty) {
        final List<dynamic> jsonList = [];
        try {
          final data = json.decode(content);
          if (data is List) jsonList.addAll(data);
        } catch (e) {
          // ignore
        }
        setState(() {
          _subjects = jsonList.map((json) => Subject.fromJson(json)).toList();
        });
      }
    }
  }

  Future<void> _initSubjectStats() async {
    if (await _subjectStatsFile.exists()) {
      final content = await _subjectStatsFile.readAsString();
      if (content.isNotEmpty) {
        try {
          final List<dynamic> jsonList = json.decode(content);
          setState(() {
            _subjectStats = jsonList
                .map((json) => SubjectStat.fromJson(json))
                .toList();
          });
        } catch (e) {
          _subject_stats_init_fallback();
        }
      }
    }
  }

  void _subject_stats_init_fallback() {
    _subjectStats = [];
  }

  Future<void> _saveSubjects() async {
    final jsonList = _subjects.map((subject) => subject.toJson()).toList();
    await _subjectsFile.writeAsString(json.encode(jsonList));
  }

  Future<void> _saveSubjectStats() async {
    final jsonList = _subject_stats_to_json();
    await _subjectStatsFile.writeAsString(json.encode(jsonList));
  }

  List<Map<String, dynamic>> _subject_stats_to_json() {
    return _subjectStats.map((s) => s.toJson()).toList();
  }

  Future<void> _preloadRingtone() async {
    if (_selectedRingtonePath == null) return;
    try {
      if (_customRingtoneFilePath != null) {
        await _audio_player_set_source(
          DeviceFileSource(_customRingtoneFilePath!),
        );
      } else {
        await _audio_player_set_source(AssetSource(_selectedRingtonePath!));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("铃声加载失败：$e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _audio_player_set_source(Source src) async {
    try {
      await _audioPlayer.setSource(src);
    } catch (_) {}
  }

  Future<void> _togglePreviewRingtone() async {
    if (!_enableRingtone || _selectedRingtonePath == null) return;

    try {
      if (_isPlayingPreview) {
        await _audioPlayer.pause();
        setState(() => _isPlayingPreview = false);
      } else {
        if (_audioPlayerState == PlayerState.paused) {
          await _audioPlayer.resume();
        } else {
          if (_customRingtoneFilePath != null) {
            await _audioPlayer.play(DeviceFileSource(_customRingtoneFilePath!));
          } else {
            await _audioPlayer.play(AssetSource(_selectedRingtonePath!));
          }
        }
        setState(() => _isPlayingPreview = true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("铃声预览失败：$e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _selectCustomRingtone() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowedExtensions: ['mp3', 'wav', 'ogg'],
      dialogTitle: "选择本地铃声文件",
    );
    if (result != null && result.files.single.path != null) {
      if (_isPlayingPreview) {
        await _audioPlayer.stop();
        _isPlayingPreview = false;
      }
      setState(() {
        _customRingtoneFilePath = result.files.single.path;
        _selectedRingtonePath = "自定义铃声";
      });
      await _preloadRingtone();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("自定义铃声已选中"),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      }
    }
  }

  void _switchToBuiltInRingtone(String path) {
    if (_isPlayingPreview) {
      _audioPlayer.stop();
      _isPlayingPreview = false;
    }
    setState(() {
      _selectedRingtonePath = path;
      _customRingtoneFilePath = null;
    });
    _preloadRingtone();
  }

  String _formatTime(int seconds) {
    int h = seconds ~/ 3600;
    int m = (seconds % 3600) ~/ 60;
    int s = seconds % 60;
    return "${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
  }

  Future<void> _saveLogToFile(String log) async {
    await _logFile.writeAsString('$log\n', mode: FileMode.append);
  }

  void _selectFixedDuration(int minutes) {
    setState(() {
      _targetDurationMinutes = minutes;
      _seconds = minutes * 60;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("已选择 ${minutes}分钟学习时长"),
        backgroundColor: Theme.of(context).colorScheme.primary,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _confirmCustomDuration() {
    setState(() {
      _targetDurationMinutes = _selectedCustomMinutes;
      _seconds = _selectedCustomMinutes * 60;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("已选择自定义 ${_selectedCustomMinutes}分钟学习时长"),
        backgroundColor: Theme.of(context).colorScheme.primary,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _cancelDurationSelection() {
    setState(() {
      _targetDurationMinutes = null;
      _seconds = 0;
      _timerStartTime = null;
    });
  }

  // start should auto-collapse settings (user requested) and start timer
  void _startTimer() {
    if (!_isRunning) {
      setState(() {
        _isRunning = true;
        _timerStartTime = DateTime.now();
        // auto-collapse settings to give larger timer area
        if (_isSettingsExpanded) _isSettingsExpanded = false;
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) return;
        setState(() {
          if (_targetDurationMinutes != null) {
            if (_seconds > 0) {
              _seconds--;
            } else {
              _timer?.cancel();
              _isRunning = false;
              _playRingtone();
              _showCountdownCompleteDialog();
            }
          } else {
            _seconds++;
          }
        });
      });
      _breathController.forward();
    }
  }

  Future<void> _playRingtone() async {
    if (!_enableRingtone || _selectedRingtonePath == null) return;
    try {
      if (_customRingtoneFilePath != null) {
        await _audioPlayer.play(DeviceFileSource(_customRingtoneFilePath!));
      } else {
        await _audioPlayer.play(AssetSource(_selectedRingtonePath!));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("铃声播放失败：$e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showCountdownCompleteDialog() {
    final actualDurationSeconds = DateTime.now()
        .difference(_timerStartTime ?? DateTime.now())
        .inSeconds;
    final actualDuration = _formatTime(actualDurationSeconds);
    final TextEditingController dialogNoteController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF24243E),
        title: Text(
          _currentSubject != null
              ? '${_currentSubject!.name} 学习时长结束！'
              : '学习时长结束！',
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "目标时长：${_formatTime(_targetDurationMinutes! * 60)}\n实际学习时长：$actualDuration",
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: dialogNoteController,
              decoration: InputDecoration(
                labelText: '添加备注（可选）',
                hintText: '例如：数学刷题、英语背诵...',
                labelStyle: const TextStyle(color: Colors.white60),
                hintStyle: const TextStyle(color: Colors.white54),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF3A3A5A)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(
                    color: Color(0xFF42A5F5),
                    width: 2,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              style: const TextStyle(fontSize: 14, color: Colors.white),
              cursorColor: const Color(0xFF42A5F5),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              String timeNow = DateFormat(
                'yyyy-MM-dd HH:mm:ss',
              ).format(DateTime.now());
              String note = dialogNoteController.text.trim().isEmpty
                  ? '无'
                  : dialogNoteController.text.trim();
              String subjectText = _currentSubject != null
                  ? '| 学科：${_currentSubject!.name}'
                  : '';
              String log =
                  "$timeNow | 目标时长：${_formatTime(_targetDurationMinutes! * 60)} | 实际学习时长：$actualDuration $subjectText | 备注：$note";

              if (_currentSubject != null) {
                _updateSubjectTotalDuration(
                  _currentSubject!.name,
                  actualDurationSeconds,
                );
              }

              setState(() {
                _studyLogs.add(log);
                _noteController.clear();
                _targetDurationMinutes = null;
                _timerStartTime = null;
                _currentSubject = null;
              });
              _saveLogToFile(log);
              dialogNoteController.dispose();
            },
            child: const Text(
              "确认记录",
              style: TextStyle(color: Color(0xFF42A5F5)),
            ),
          ),
        ],
      ),
    );
  }

  void _pauseTimer() {
    if (_isRunning) {
      setState(() => _isRunning = false);
      _timer?.cancel();
      _breathController.stop();
    }
  }

  void _endTimer() {
    _pauseTimer();
    if (_timerStartTime == null ||
        (DateTime.now().difference(_timerStartTime!).inSeconds < 1)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("未检测到有效学习时长 ❌"),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final actualDurationSeconds = DateTime.now()
        .difference(_timerStartTime!)
        .inSeconds;
    final actualDuration = _formatTime(actualDurationSeconds);
    final targetDurationText = _targetDurationMinutes != null
        ? _formatTime(_targetDurationMinutes! * 60)
        : "无";
    final subjectText = _currentSubject != null
        ? '| 学科：${_currentSubject!.name}'
        : '';

    String timeNow = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    String log =
        "$timeNow | 目标时长：$targetDurationText | 实际学习时长：$actualDuration $subjectText | 备注：${_noteController.text.isEmpty ? '无' : _noteController.text}";

    if (_currentSubject != null) {
      _updateSubjectTotalDuration(_currentSubject!.name, actualDurationSeconds);
    }

    setState(() {
      _studyLogs.add(log);
      _seconds = 0;
      _noteController.clear();
      _targetDurationMinutes = null;
      _timerStartTime = null;
      _currentSubject = null;
    });

    _saveLogToFile(log)
        .then((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text("日志已保存 ✅"),
                backgroundColor: Theme.of(context).colorScheme.secondary,
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        })
        .catchError((e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("保存失败：$e ❌"), backgroundColor: Colors.red),
            );
          }
        });
  }

  void _updateSubjectTotalDuration(String subjectName, int addSeconds) {
    final index = _subjectStats.indexWhere(
      (stat) => stat.subjectName == subjectName,
    );
    if (index != -1) {
      _subjectStats[index].totalSeconds += addSeconds;
    } else {
      _subjectStats.add(
        SubjectStat(subjectName: subjectName, totalSeconds: addSeconds),
      );
    }
    _saveSubjectStats();
  }

  String _getSubjectTotalDuration(String subjectName) {
    final stat = _subjectStats.firstWhere(
      (s) => s.subjectName == subjectName,
      orElse: () => SubjectStat(subjectName: subjectName),
    );
    return _formatTime(stat.totalSeconds);
  }

  void _deleteLog(int index) async {
    setState(() {
      _studyLogs.removeAt(index);
    });
    await _logFile.writeAsString(_studyLogs.join('\n') + '\n');
  }

  // add subject dialog
  void _addSubject() {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController goalController = TextEditingController();
    int priority = 0;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, dialogSetState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF24243E),
            title: const Text('添加学科', style: TextStyle(color: Colors.white)),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: '学科名称',
                      labelStyle: const TextStyle(color: Colors.white60),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF3A3A5A)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: Color(0xFF42A5F5),
                          width: 2,
                        ),
                      ),
                    ),
                    style: const TextStyle(color: Colors.white),
                    cursorColor: const Color(0xFF42A5F5),
                  ),
                  const SizedBox(height: 16),
                  const Text('重要度', style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _PriorityColorButton(
                        color: Colors.blue,
                        isSelected: priority == 0,
                        onTap: () => dialogSetState(() => priority = 0),
                        showCheckmark: true,
                      ),
                      _PriorityColorButton(
                        color: Colors.green,
                        isSelected: priority == 1,
                        onTap: () => dialogSetState(() => priority = 1),
                        showCheckmark: true,
                      ),
                      _PriorityColorButton(
                        color: Colors.yellow,
                        isSelected: priority == 2,
                        onTap: () => dialogSetState(() => priority = 2),
                        showCheckmark: true,
                      ),
                      _PriorityColorButton(
                        color: Colors.orange,
                        isSelected: priority == 3,
                        onTap: () => dialogSetState(() => priority = 3),
                        showCheckmark: true,
                      ),
                      _PriorityColorButton(
                        color: Colors.red,
                        isSelected: priority == 4,
                        onTap: () => dialogSetState(() => priority = 4),
                        showCheckmark: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: goalController,
                    decoration: InputDecoration(
                      labelText: '学习目标（每行一条，以回车键分隔）',
                      labelStyle: const TextStyle(color: Colors.white60),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF3A3A5A)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: Color(0xFF42A5F5),
                          width: 2,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    minLines: 3,
                    maxLines: 6,
                    style: const TextStyle(color: Colors.white),
                    cursorColor: const Color(0xFF42A5F5),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  '取消',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
              TextButton(
                onPressed: () {
                  final name = nameController.text.trim();
                  if (name.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('学科名称不能为空'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }
                  if (_subjects.any((s) => s.name == name)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('该学科已存在'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }
                  final goals = goalController.text
                      .split('\n')
                      .map((g) => g.trim())
                      .where((g) => g.isNotEmpty)
                      .toList();
                  final subject = Subject(
                    name: name,
                    priority: priority,
                    goals: goals,
                  );
                  setState(() {
                    _subjects.add(subject);
                    _saveSubjects();
                  });
                  Navigator.pop(context);
                },
                child: const Text(
                  '确认',
                  style: TextStyle(color: Color(0xFF42A5F5)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _editSubject(Subject subject) {
    final TextEditingController nameController = TextEditingController(
      text: subject.name,
    );
    final TextEditingController goalController = TextEditingController(
      text: subject.goals.join('\n'),
    );
    int priority = subject.priority;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, dialogSetState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF24243E),
            title: const Text('编辑学科', style: TextStyle(color: Colors.white)),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: '学科名称',
                      labelStyle: const TextStyle(color: Colors.white60),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF3A3A5A)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: Color(0xFF42A5F5),
                          width: 2,
                        ),
                      ),
                    ),
                    style: const TextStyle(color: Colors.white),
                    cursorColor: const Color(0xFF42A5F5),
                  ),
                  const SizedBox(height: 16),
                  const Text('重要度', style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _PriorityColorButton(
                        color: Colors.blue,
                        isSelected: priority == 0,
                        onTap: () => dialogSetState(() => priority = 0),
                        showCheckmark: true,
                      ),
                      _PriorityColorButton(
                        color: Colors.green,
                        isSelected: priority == 1,
                        onTap: () => dialogSetState(() => priority = 1),
                        showCheckmark: true,
                      ),
                      _PriorityColorButton(
                        color: Colors.yellow,
                        isSelected: priority == 2,
                        onTap: () => dialogSetState(() => priority = 2),
                        showCheckmark: true,
                      ),
                      _PriorityColorButton(
                        color: Colors.orange,
                        isSelected: priority == 3,
                        onTap: () => dialogSetState(() => priority = 3),
                        showCheckmark: true,
                      ),
                      _PriorityColorButton(
                        color: Colors.red,
                        isSelected: priority == 4,
                        onTap: () => dialogSetState(() => priority = 4),
                        showCheckmark: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: goalController,
                    decoration: InputDecoration(
                      labelText: '学习目标（每行一条，以回车键分隔）',
                      labelStyle: const TextStyle(color: Colors.white60),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF3A3A5A)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: Color(0xFF42A5F5),
                          width: 2,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    minLines: 3,
                    maxLines: 6,
                    style: const TextStyle(color: Colors.white),
                    cursorColor: const Color(0xFF42A5F5),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      backgroundColor: const Color(0xFF24243E),
                      title: const Text(
                        '删除学科',
                        style: TextStyle(color: Colors.white),
                      ),
                      content: const Text(
                        '该学科将从列表移除，但您的学习日志和学习时长将保存，您可以通过timechecker进行查看统计，是否确认删除？',
                        style: TextStyle(color: Colors.white70),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text(
                            '取消',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text(
                            '确认',
                            style: TextStyle(color: Colors.redAccent),
                          ),
                        ),
                      ],
                    ),
                  );
                  if (confirmed ?? false) {
                    setState(() {
                      _subjects.removeWhere((s) => s.name == subject.name);
                      _expandedSubjects.remove(subject.name);
                      if (_currentSubject?.name == subject.name)
                        _currentSubject = null;
                      _saveSubjects();
                    });
                    Navigator.pop(context);
                  }
                },
                child: const Text(
                  '删除',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  '取消',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
              TextButton(
                onPressed: () {
                  final name = nameController.text.trim();
                  if (name.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('学科名称不能为空'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }
                  if (_subjects.any(
                    (s) => s.name == name && s.name != subject.name,
                  )) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('已存在同名学科'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }
                  final goals = goalController.text
                      .split('\n')
                      .map((g) => g.trim())
                      .where((g) => g.isNotEmpty)
                      .toList();
                  final updated = Subject(
                    name: name,
                    priority: priority,
                    goals: goals,
                  );
                  setState(() {
                    final index = _subjects.indexWhere(
                      (s) => s.name == subject.name,
                    );
                    if (index != -1) {
                      _subjects[index] = updated;
                      if (_currentSubject?.name == subject.name)
                        _currentSubject = updated;
                      if (name != subject.name) {
                        if (_expandedSubjects.remove(subject.name))
                          _expandedSubjects.add(name);
                      }
                      _saveSubjects();
                    }
                  });
                  Navigator.pop(context);
                },
                child: const Text(
                  '确认',
                  style: TextStyle(color: Color(0xFF42A5F5)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _selectSubject(Subject subject) {
    setState(() {
      _currentSubject = subject;
    });
  }

  void _toggleSubjectDetail(Subject subject) {
    setState(() {
      if (_expandedSubjects.contains(subject.name)) {
        _expandedSubjects.remove(subject.name);
      } else {
        _expandedSubjects.add(subject.name);
      }
      if (_expandedSubjects.contains(subject.name)) {
        _currentSubject = subject;
      } else {
        if (_currentSubject?.name == subject.name) _currentSubject = null;
      }
    });
  }

  void _updatePriority(Subject subject, int priority) {
    final index = _subjects.indexWhere((s) => s.name == subject.name);
    if (index != -1) {
      final updated = Subject(
        name: subject.name,
        priority: priority,
        goals: subject.goals,
      );
      setState(() {
        _subjects[index] = updated;
        _saveSubjects();
        if (_currentSubject?.name == subject.name) _currentSubject = updated;
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _noteController.dispose();
    _breathController.dispose();
    _audio_player_dispose_helper();
    _customMinutesController?.dispose();
    super.dispose();
  }

  void _audio_player_dispose_helper() {
    try {
      _audioPlayer.dispose();
    } catch (_) {}
  }

  Color _priorityColorByIndex(int idx) {
    switch (idx) {
      case 0:
        return Colors.blue;
      case 1:
        return Colors.green;
      case 2:
        return Colors.yellow;
      case 3:
        return Colors.orange;
      case 4:
        return Colors.red;
      default:
        return Colors.blue;
    }
  }

  // Timer container heights: when settings expanded we show smaller timer but still visible;
  // part of timer will be "buried" under the note & controls overlay to match your desired look.
  double _timerHeight(BuildContext c) {
    final h = MediaQuery.of(c).size.height;
    final normal = h * 0.36;
    final collapsedSettingsVisible =
        normal * 0.56; // when settings expanded show ~56% of normal
    return _isSettingsExpanded ? collapsedSettingsVisible : normal;
  }

  @override
  Widget build(BuildContext context) {
    final double sidebarExpandedWidth = 320;
    final double sidebarCollapsedWidth = 60;
    final double leftPanelWidth = _isSidebarExpanded
        ? sidebarExpandedWidth
        : sidebarCollapsedWidth;

    return Scaffold(
      appBar: AppBar(
        title: const Text('学习钟'),
        centerTitle: true,
        elevation: 2,
        shadowColor: Colors.black38,
        backgroundColor: const Color(0xFF1A1A2E),
      ),
      body: Row(
        children: [
          // Sidebar: width controlled independently; single chevron control only.
          AnimatedContainer(
            duration: _panelAnimDuration,
            curve: _panelAnimCurve,
            width: leftPanelWidth,
            color: const Color(0xFF1A1A2E),
            child: Column(
              children: [
                const SizedBox(height: 12),
                // Header: show title when expanded; when collapsed, header text hidden so single centered chevron appears in collapsed UI
                if (_isSidebarExpanded)
                  Row(
                    children: [
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          '学科',
                          style: TextStyle(color: Colors.white70, fontSize: 16),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.chevron_left,
                          color: Colors.white70,
                        ),
                        onPressed: () =>
                            setState(() => _isSidebarExpanded = false),
                        splashRadius: 20,
                      ),
                      const SizedBox(width: 6),
                    ],
                  )
                else
                  const SizedBox(
                    height: 44,
                  ), // spacing in collapsed header area

                const SizedBox(height: 4),

                Expanded(
                  child: AnimatedSwitcher(
                    duration: _panelAnimDuration,
                    switchInCurve: _panelAnimCurve,
                    switchOutCurve: _panelAnimCurve,
                    child: _isSidebarExpanded
                        ? Column(
                            key: const ValueKey('expanded_sidebar'),
                            children: [
                              Expanded(
                                child: _subjects.isEmpty
                                    ? Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const Text(
                                            '当前还没有添加学科，点击加号试试吧~',
                                            style: TextStyle(
                                              color: Colors.white54,
                                              fontSize: 14,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                          const SizedBox(height: 16),
                                          FloatingActionButton(
                                            onPressed: _addSubject,
                                            backgroundColor: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                            child: const Icon(Icons.add),
                                          ),
                                        ],
                                      )
                                    : ListView.builder(
                                        itemCount: _subjects.length,
                                        itemBuilder: (context, index) {
                                          final subject = _subjects[index];
                                          final priorityColors = [
                                            Colors.blue.withOpacity(0.02),
                                            Colors.green.withOpacity(0.02),
                                            Colors.yellow.withOpacity(0.02),
                                            Colors.orange.withOpacity(0.02),
                                            Colors.red.withOpacity(0.02),
                                          ];
                                          final isExpanded = _expandedSubjects
                                              .contains(subject.name);
                                          return Column(
                                            children: [
                                              ListTile(
                                                tileColor:
                                                    priorityColors[subject
                                                        .priority],
                                                // Gear to the left per your request (edit)
                                                leading: IconButton(
                                                  icon: const Icon(
                                                    Icons.settings,
                                                    color: Colors.white70,
                                                    size: 18,
                                                  ),
                                                  onPressed: () =>
                                                      _editSubject(subject),
                                                  padding: EdgeInsets.zero,
                                                  constraints:
                                                      const BoxConstraints(),
                                                ),
                                                title: Text(
                                                  subject.name,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                                trailing: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Container(
                                                      width: 14,
                                                      height: 14,
                                                      decoration: BoxDecoration(
                                                        color:
                                                            _priorityColorByIndex(
                                                              subject.priority,
                                                            ),
                                                        shape: BoxShape.circle,
                                                        border: Border.all(
                                                          color: Colors.white24,
                                                          width: 1,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    IconButton(
                                                      icon: Icon(
                                                        isExpanded
                                                            ? Icons.expand_less
                                                            : Icons.expand_more,
                                                        color: Colors.white70,
                                                        size: 18,
                                                      ),
                                                      onPressed: () =>
                                                          _toggleSubjectDetail(
                                                            subject,
                                                          ),
                                                      padding: EdgeInsets.zero,
                                                      constraints:
                                                          const BoxConstraints(),
                                                    ),
                                                  ],
                                                ),
                                                onTap: () =>
                                                    _selectSubject(subject),
                                                contentPadding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 10,
                                                    ),
                                              ),
                                              AnimatedCrossFade(
                                                firstChild:
                                                    const SizedBox.shrink(),
                                                secondChild: Container(
                                                  color: const Color(
                                                    0xFF24243E,
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                        vertical: 12,
                                                      ),
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      const Text(
                                                        '重要度',
                                                        style: TextStyle(
                                                          color: Colors.white70,
                                                          fontSize: 14,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 8),
                                                      Row(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .spaceEvenly,
                                                        children: [
                                                          _PriorityColorButton(
                                                            color: Colors.blue,
                                                            isSelected:
                                                                subject
                                                                    .priority ==
                                                                0,
                                                            onTap: () =>
                                                                _updatePriority(
                                                                  subject,
                                                                  0,
                                                                ),
                                                            showCheckmark: true,
                                                          ),
                                                          _PriorityColorButton(
                                                            color: Colors.green,
                                                            isSelected:
                                                                subject
                                                                    .priority ==
                                                                1,
                                                            onTap: () =>
                                                                _updatePriority(
                                                                  subject,
                                                                  1,
                                                                ),
                                                            showCheckmark: true,
                                                          ),
                                                          _PriorityColorButton(
                                                            color:
                                                                Colors.yellow,
                                                            isSelected:
                                                                subject
                                                                    .priority ==
                                                                2,
                                                            onTap: () =>
                                                                _updatePriority(
                                                                  subject,
                                                                  2,
                                                                ),
                                                            showCheckmark: true,
                                                          ),
                                                          _PriorityColorButton(
                                                            color:
                                                                Colors.orange,
                                                            isSelected:
                                                                subject
                                                                    .priority ==
                                                                3,
                                                            onTap: () =>
                                                                _updatePriority(
                                                                  subject,
                                                                  3,
                                                                ),
                                                            showCheckmark: true,
                                                          ),
                                                          _PriorityColorButton(
                                                            color: Colors.red,
                                                            isSelected:
                                                                subject
                                                                    .priority ==
                                                                4,
                                                            onTap: () =>
                                                                _updatePriority(
                                                                  subject,
                                                                  4,
                                                                ),
                                                            showCheckmark: true,
                                                          ),
                                                        ],
                                                      ),
                                                      const SizedBox(
                                                        height: 12,
                                                      ),
                                                      const Text(
                                                        '学习目标',
                                                        style: TextStyle(
                                                          color: Colors.white70,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 8),
                                                      if (subject.goals.isEmpty)
                                                        const Text(
                                                          '暂无目标',
                                                          style: TextStyle(
                                                            color:
                                                                Colors.white54,
                                                          ),
                                                        )
                                                      else
                                                        Column(
                                                          children: subject
                                                              .goals
                                                              .map(
                                                                (g) => Padding(
                                                                  padding:
                                                                      const EdgeInsets.symmetric(
                                                                        vertical:
                                                                            4,
                                                                      ),
                                                                  child: Row(
                                                                    children: [
                                                                      const Text(
                                                                        '• ',
                                                                        style: TextStyle(
                                                                          color:
                                                                              Colors.white70,
                                                                        ),
                                                                      ),
                                                                      Text(
                                                                        g,
                                                                        style: const TextStyle(
                                                                          color:
                                                                              Colors.white,
                                                                        ),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                ),
                                                              )
                                                              .toList(),
                                                        ),
                                                      const SizedBox(
                                                        height: 12,
                                                      ),
                                                      const Text(
                                                        '累计学习时长',
                                                        style: TextStyle(
                                                          color: Colors.white70,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 8),
                                                      Text(
                                                        _getSubjectTotalDuration(
                                                          subject.name,
                                                        ),
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 16,
                                                          fontWeight:
                                                              FontWeight.w500,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                crossFadeState: isExpanded
                                                    ? CrossFadeState.showSecond
                                                    : CrossFadeState.showFirst,
                                                duration: _panelAnimDuration,
                                                firstCurve: Curves.easeOut,
                                                secondCurve: Curves.easeIn,
                                              ),
                                              const Divider(
                                                color: Colors.white10,
                                                height: 1,
                                              ),
                                            ],
                                          );
                                        },
                                      ),
                              ),
                              // unified add button under the list
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12.0,
                                ),
                                child: FloatingActionButton(
                                  onPressed: _addSubject,
                                  backgroundColor: Theme.of(
                                    context,
                                  ).colorScheme.primary,
                                  child: const Icon(Icons.add),
                                ),
                              ),
                            ],
                          )
                        : // collapsed sidebar: show centered chevron and keep bottom plus
                          Column(
                            key: const ValueKey('collapsed_sidebar'),
                            children: [
                              const SizedBox(height: 6),
                              // center the expand chevron vertically
                              Expanded(
                                child: Center(
                                  child: IconButton(
                                    icon: const Icon(
                                      Icons.chevron_right,
                                      color: Colors.white70,
                                      size: 28,
                                    ),
                                    onPressed: () => setState(
                                      () => _isSidebarExpanded = true,
                                    ),
                                  ),
                                ),
                              ),
                              // keep bottom floating add visible when collapsed
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12.0),
                                child: FloatingActionButton(
                                  onPressed: _addSubject,
                                  backgroundColor: Theme.of(
                                    context,
                                  ).colorScheme.primary,
                                  child: const Icon(Icons.add),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),

          // 主内容区
          Expanded(
            child: Container(
              color: Theme.of(context).colorScheme.background,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    // Settings area - independent animation/controls
                    AnimatedSize(
                      duration: _panelAnimDuration,
                      curve: _panelAnimCurve,
                      child: _isSettingsExpanded
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 16,
                                horizontal: 20,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF24243E),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black12,
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        "设置",
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.white,
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.expand_less,
                                          color: Colors.white70,
                                        ),
                                        onPressed: () => setState(
                                          () => _isSettingsExpanded = false,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Divider(
                                    color: Colors.white10,
                                    height: 16,
                                  ),
                                  const Text(
                                    "选择学习时长（可选）",
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.white70,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      _DurationButton(
                                        minutes: 20,
                                        onTap: _selectFixedDuration,
                                        isSelected:
                                            _targetDurationMinutes == 20,
                                      ),
                                      _DurationButton(
                                        minutes: 40,
                                        onTap: _selectFixedDuration,
                                        isSelected:
                                            _targetDurationMinutes == 40,
                                      ),
                                      _DurationButton(
                                        minutes: 60,
                                        onTap: _selectFixedDuration,
                                        isSelected:
                                            _targetDurationMinutes == 60,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      const Text(
                                        "自定义：",
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: SizedBox(
                                          height: 110,
                                          child: Stack(
                                            alignment: Alignment.center,
                                            children: [
                                              Positioned(
                                                left: 0,
                                                right: 0,
                                                height: 50,
                                                child: Container(
                                                  margin:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .primary
                                                        .withOpacity(0.12),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                  ),
                                                ),
                                              ),
                                              ListWheelScrollView.useDelegate(
                                                controller:
                                                    _customMinutesController,
                                                itemExtent: 44,
                                                physics:
                                                    const FixedExtentScrollPhysics(),
                                                diameterRatio: 1.6,
                                                perspective: 0.005,
                                                useMagnifier: true,
                                                magnification: 1.25,
                                                onSelectedItemChanged: (i) {
                                                  setState(() {
                                                    _selectedCustomMinutes =
                                                        i + 1;
                                                  });
                                                },
                                                childDelegate: ListWheelChildBuilderDelegate(
                                                  builder: (context, index) {
                                                    if (index < 0 ||
                                                        index >= 120)
                                                      return null;
                                                    final minutes = index + 1;
                                                    final isSel =
                                                        _selectedCustomMinutes ==
                                                        minutes;
                                                    return AnimatedDefaultTextStyle(
                                                      duration: const Duration(
                                                        milliseconds: 220,
                                                      ),
                                                      style: TextStyle(
                                                        fontSize: isSel
                                                            ? 20
                                                            : 15,
                                                        fontWeight: isSel
                                                            ? FontWeight.bold
                                                            : FontWeight.normal,
                                                        color: isSel
                                                            ? Theme.of(context)
                                                                  .colorScheme
                                                                  .primary
                                                            : Colors.white70,
                                                      ),
                                                      child: Center(
                                                        child: Text(
                                                          "$minutes 分钟",
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                  childCount: 120,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      ElevatedButton(
                                        onPressed: _confirmCustomDuration,
                                        style: ElevatedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 8,
                                          ),
                                          backgroundColor: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                        ),
                                        child: const Text("确认"),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    "铃声设置",
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.white70,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Switch(
                                        value: _enableRingtone,
                                        onChanged: (value) => setState(
                                          () => _enableRingtone = value,
                                        ),
                                        activeColor: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                        inactiveTrackColor: Colors.grey[700],
                                      ),
                                      const SizedBox(width: 6),
                                      const Text(
                                        "启用铃声",
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(width: 20),
                                      ElevatedButton(
                                        onPressed: _enableRingtone
                                            ? _togglePreviewRingtone
                                            : null,
                                        style: ElevatedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                          backgroundColor: _enableRingtone
                                              ? Theme.of(
                                                  context,
                                                ).colorScheme.secondary
                                              : Colors.grey[700],
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              _isPlayingPreview
                                                  ? Icons.pause
                                                  : Icons.play_arrow,
                                              size: 16,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              _isPlayingPreview ? "暂停" : "预览",
                                              style: const TextStyle(
                                                fontSize: 14,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Text(
                                        "选择铃声：",
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: DropdownButtonFormField<String>(
                                          value: _selectedRingtonePath,
                                          items: [
                                            ..._builtInRingtones.map((
                                              ringtone,
                                            ) {
                                              return DropdownMenuItem<String>(
                                                value: ringtone["path"],
                                                child: Text(
                                                  ringtone["name"]!,
                                                  style: const TextStyle(
                                                    color: Colors.white70,
                                                  ),
                                                ),
                                              );
                                            }),
                                            const DropdownMenuItem<String>(
                                              value: "自定义铃声",
                                              child: Text(
                                                "自定义铃声",
                                                style: TextStyle(
                                                  color: Colors.white70,
                                                ),
                                              ),
                                            ),
                                          ],
                                          onChanged: (value) {
                                            if (value == "自定义铃声") {
                                              _selectCustomRingtone();
                                            } else if (value != null) {
                                              _switchToBuiltInRingtone(value);
                                            }
                                          },
                                          decoration: InputDecoration(
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              borderSide: const BorderSide(
                                                color: Color(0xFF3A3A5A),
                                              ),
                                            ),
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                  horizontal: 12,
                                                  vertical: 8,
                                                ),
                                          ),
                                          style: const TextStyle(
                                            color: Colors.white70,
                                          ),
                                          dropdownColor: const Color(
                                            0xFF24243E,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      ElevatedButton(
                                        onPressed: _selectCustomRingtone,
                                        style: ElevatedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                          backgroundColor: const Color(
                                            0xFF3A3A5A,
                                          ),
                                        ),
                                        child: const Row(
                                          children: [
                                            Icon(Icons.file_open, size: 16),
                                            SizedBox(width: 4),
                                            Text(
                                              "本地",
                                              style: TextStyle(fontSize: 14),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      onPressed: _cancelDurationSelection,
                                      child: const Text(
                                        "取消选择",
                                        style: TextStyle(
                                          color: Colors.redAccent,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 12,
                                horizontal: 20,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF24243E),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black12,
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    "设置（已折叠）",
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.white,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.expand_more,
                                      color: Colors.white70,
                                    ),
                                    onPressed: () => setState(
                                      () => _isSettingsExpanded = true,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),

                    const SizedBox(height: 12),

                    // Timer area with controlled overlap: when settings expanded we let note+controls overlay (higher z-order)
                    // Use Stack to render timer first then overlay note+controls with higher z-index.
                    AnimatedContainer(
                      duration: _panelAnimDuration,
                      curve: _panelAnimCurve,
                      height: _timerHeight(context),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Theme.of(
                              context,
                            ).colorScheme.primary.withOpacity(0.18),
                            Theme.of(
                              context,
                            ).colorScheme.secondary.withOpacity(0.12),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: _isRunning
                            ? [
                                BoxShadow(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.primary.withOpacity(0.18),
                                  blurRadius: 20,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // Timer main content (bottom layer)
                          Positioned.fill(
                            child: Center(
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  double fontSize = constraints.maxWidth < 400
                                      ? 48
                                      : (constraints.maxWidth < 600 ? 64 : 84);
                                  // Shrink font a bit when settings expanded so overlap looks like "buried" number
                                  if (_isSettingsExpanded) fontSize *= 0.9;
                                  return Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      if (_currentSubject != null)
                                        Text(
                                          _currentSubject!.name,
                                          style: const TextStyle(
                                            fontSize: 20,
                                            color: Colors.white70,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      const SizedBox(height: 12),
                                      Text(
                                        _formatTime(_seconds),
                                        style: TextStyle(
                                          fontSize: fontSize,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 3,
                                          color:
                                              _targetDurationMinutes != null &&
                                                  _seconds <= 60
                                              ? Colors.redAccent
                                              : Theme.of(
                                                  context,
                                                ).colorScheme.primary,
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ),

                          // Overlayed note input and controls: when settings expanded we place them overlapping bottom of timer (higher z-order)
                          Positioned(
                            left: 12,
                            right: 12,
                            bottom: _isSettingsExpanded
                                ? -36
                                : -4, // deeper overlap when settings open
                            child: Column(
                              children: [
                                // note input (higher z-order)
                                Material(
                                  color: Colors.transparent,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF24243E),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: const Color(0xFF3A3A5A),
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.25),
                                          blurRadius: 8,
                                          offset: const Offset(0, 3),
                                        ),
                                      ],
                                    ),
                                    child: TextField(
                                      controller: _noteController,
                                      decoration: const InputDecoration(
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 14,
                                        ),
                                        prefixIcon: Icon(
                                          Icons.note_add_outlined,
                                          color: Colors.white60,
                                        ),
                                        hintText: '例如：数学刷题、英语背诵...',
                                        hintStyle: TextStyle(
                                          color: Colors.white54,
                                        ),
                                        border: InputBorder.none,
                                      ),
                                      enabled: !_isRunning,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        color: Colors.white,
                                      ),
                                      cursorColor: Color(0xFF42A5F5),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                // controls row (also overlay): they must remain visible and above timer
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: [
                                    ElevatedButton(
                                      onPressed: () {
                                        // Start should collapse settings and start timer in one action
                                        setState(
                                          () => _isSettingsExpanded = false,
                                        );
                                        _startTimer();
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFF3979E0,
                                        ),
                                      ),
                                      child: const Row(
                                        children: [
                                          Icon(Icons.play_arrow),
                                          SizedBox(width: 8),
                                          Text('开始'),
                                        ],
                                      ),
                                    ),
                                    ElevatedButton(
                                      onPressed: _pauseTimer,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFFF57C00,
                                        ),
                                      ),
                                      child: const Row(
                                        children: [
                                          Icon(Icons.pause),
                                          SizedBox(width: 8),
                                          Text('暂停'),
                                        ],
                                      ),
                                    ),
                                    ElevatedButton(
                                      onPressed: _endTimer,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFF4CAF50,
                                        ),
                                      ),
                                      child: const Row(
                                        children: [
                                          Icon(Icons.check),
                                          SizedBox(width: 8),
                                          Text('结束记录'),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Logs
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '学习日志',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                ),
                              ),
                              Text(
                                '共 ${_studyLogs.length} 条',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.white54,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: _studyLogs.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const Icon(
                                          Icons.history_outlined,
                                          size: 60,
                                          color: Colors.white24,
                                        ),
                                        const SizedBox(height: 10),
                                        const Text(
                                          '暂无学习记录',
                                          style: TextStyle(
                                            fontSize: 16,
                                            color: Colors.white54,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : ListView.builder(
                                    itemCount: _studyLogs.length,
                                    itemBuilder: (context, index) {
                                      final isEven = index % 2 == 0;
                                      return Dismissible(
                                        key: Key(_studyLogs[index]),
                                        direction: DismissDirection.endToStart,
                                        background: Container(
                                          decoration: BoxDecoration(
                                            color: Colors.redAccent.withOpacity(
                                              0.2,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          alignment: Alignment.centerRight,
                                          padding: const EdgeInsets.only(
                                            right: 20,
                                          ),
                                          child: const Icon(
                                            Icons.delete_outline,
                                            color: Colors.redAccent,
                                            size: 28,
                                          ),
                                        ),
                                        onDismissed: (direction) =>
                                            _deleteLog(index),
                                        child: Card(
                                          color: isEven
                                              ? const Color(0xFF24243E)
                                              : const Color(0xFF2A2A42),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 14,
                                            ),
                                            child: Text(
                                              _studyLogs[index],
                                              style: const TextStyle(
                                                fontSize: 15,
                                                color: Colors.white70,
                                                height: 1.5,
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DurationButton extends StatelessWidget {
  final int minutes;
  final void Function(int) onTap;
  final bool isSelected;

  const _DurationButton({
    required this.minutes,
    required this.onTap,
    required this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () => onTap(minutes),
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected
            ? Theme.of(context).colorScheme.primary
            : const Color(0xFF3A3A5A),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text("$minutes 分钟"),
    );
  }
}

class _PriorityColorButton extends StatefulWidget {
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;
  final double size;
  final bool showCheckmark;

  const _PriorityColorButton({
    required this.color,
    required this.isSelected,
    required this.onTap,
    this.size = 24,
    this.showCheckmark = true,
  });

  @override
  State<_PriorityColorButton> createState() => _PriorityColorButtonState();
}

class _PriorityColorButtonState extends State<_PriorityColorButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<Color?> _colorAnimation;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.18).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _colorAnimation =
        ColorTween(
          begin: widget.color,
          end: HSLColor.fromColor(widget.color)
              .withLightness(
                (HSLColor.fromColor(widget.color).lightness + 0.28).clamp(
                  0.0,
                  1.0,
                ),
              )
              .toColor(),
        ).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeInOut,
          ),
        );
  }

  @override
  void didUpdateWidget(covariant _PriorityColorButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.color != widget.color) {
      _colorAnimation =
          ColorTween(
            begin: widget.color,
            end: HSLColor.fromColor(widget.color)
                .withLightness(
                  (HSLColor.fromColor(widget.color).lightness + 0.28).clamp(
                    0.0,
                    1.0,
                  ),
                )
                .toColor(),
          ).animate(
            CurvedAnimation(
              parent: _animationController,
              curve: Curves.easeInOut,
            ),
          );
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _onEnter(_) {
    setState(() => _isHovered = true);
    _animationController.forward();
  }

  void _onExit(_) {
    setState(() => _isHovered = false);
    _animationController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: _onEnter,
      onExit: _onExit,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: Listenable.merge([_scaleAnimation, _colorAnimation]),
          builder: (context, child) {
            return Transform.scale(
              scale: widget.isSelected
                  ? _scaleAnimation.value
                  : (_isHovered ? (_scaleAnimation.value) : 1.0),
              child: Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _colorAnimation.value,
                  border: widget.isSelected
                      ? Border.all(color: Colors.white, width: 2)
                      : null,
                  boxShadow: widget.isSelected || _isHovered
                      ? [
                          BoxShadow(
                            color: _colorAnimation.value!.withOpacity(0.45),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                child: widget.isSelected && widget.showCheckmark
                    ? const Icon(Icons.check, color: Colors.white, size: 16)
                    : null,
              ),
            );
          },
        ),
      ),
    );
  }
}
