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

  // 可折叠区域状态
  bool _isSettingsExpanded = true;

  // 学科相关状态 - 支持多个同时展开
  List<Subject> _subjects = [];
  List<SubjectStat> _subjectStats = []; // 学科累计时长统计
  Subject? _currentSubject;
  final Set<String> _expandedSubjects = {}; // 使用学科 name 标识展开项

  // 计时开始时间（用于计算实际学习时长）
  DateTime? _timerStartTime;

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

    // 监听音频播放器状态变化
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _audioPlayerState = state;
          // 播放结束自动重置预览状态
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
    _subjectStatsFile = File(
      '${directory.path}/StudyClockSubjectStats.json',
    ); // 初始化统计文件
    await _initLogFile();
    await _initSubjects();
    await _initSubjectStats(); // 初始化学科累计时长
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
          if (data is List) {
            jsonList.addAll(data);
          }
        } catch (e) {
          // 忽略解析错误
        }
        setState(() {
          _subjects = jsonList.map((json) => Subject.fromJson(json)).toList();
        });
      }
    }
  }

  // 初始化学科累计时长统计
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
          _subjectStats = []; // 解析失败初始化空列表
        }
      }
    }
  }

  // 保存学科数据
  Future<void> _saveSubjects() async {
    final jsonList = _subjects.map((subject) => subject.toJson()).toList();
    await _subjectsFile.writeAsString(json.encode(jsonList));
  }

  // 保存学科累计时长统计
  Future<void> _saveSubjectStats() async {
    final jsonList = _subjectStats.map((stat) => stat.toJson()).toList();
    await _subjectStatsFile.writeAsString(json.encode(jsonList));
  }

  Future<void> _preloadRingtone() async {
    if (_selectedRingtonePath == null) return;
    try {
      if (_customRingtoneFilePath != null) {
        await _audioPlayer.setSource(
          DeviceFileSource(_customRingtoneFilePath!),
        );
      } else {
        await _audioPlayer.setSource(AssetSource(_selectedRingtonePath!));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("铃声加载失败：$e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  // 播放/暂停预览铃声
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
          SnackBar(
            content: Text("铃声预览失败：$e"),
            backgroundColor: Colors.redAccent,
          ),
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

  // 开始计时（自动折叠设置区域）
  void _startTimer() {
    if (!_isRunning) {
      setState(() {
        _isRunning = true;
        _timerStartTime = DateTime.now();
        if (_isSettingsExpanded) {
          _isSettingsExpanded = false;
        }
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

  // 播放结束铃声
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
          SnackBar(
            content: Text("铃声播放失败：$e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  // 倒计时结束弹窗（带备注输入）
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

              // 更新学科累计时长
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

  // 结束计时 + 保存日志
  void _endTimer() {
    _pauseTimer();
    if (_timerStartTime == null ||
        (DateTime.now().difference(_timerStartTime!).inSeconds < 1)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("未检测到有效学习时长 ❌"),
            backgroundColor: Colors.redAccent,
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

    // 更新学科累计时长
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        })
        .catchError((e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("保存失败：$e ❌"),
                backgroundColor: Colors.redAccent,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            );
          }
        });
  }

  // 核心：更新学科累计时长
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
    _saveSubjectStats(); // 持久化保存
  }

  // 获取学科累计时长并格式化
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

  // 添加新学科（使用 StatefulBuilder 管理对话框内部状态）
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
                        backgroundColor: Colors.redAccent,
                      ),
                    );
                    return;
                  }
                  if (_subjects.any((s) => s.name == name)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('该学科已存在'),
                        backgroundColor: Colors.redAccent,
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

  // 编辑学科（齿轮对话框），包含删除按钮与删除确认
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
              // 删除按钮（左侧）
              TextButton(
                onPressed: () async {
                  // show delete confirmation
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
                    // perform deletion
                    setState(() {
                      _subjects.removeWhere((s) => s.name == subject.name);
                      _expandedSubjects.remove(subject.name);
                      if (_currentSubject?.name == subject.name) {
                        _currentSubject = null;
                      }
                      _saveSubjects();
                    });
                    Navigator.pop(context); // close edit dialog
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
                        backgroundColor: Colors.redAccent,
                      ),
                    );
                    return;
                  }
                  // check for duplicate name (excluding self)
                  if (_subjects.any(
                    (s) => s.name == name && s.name != subject.name,
                  )) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('已存在同名学科'),
                        backgroundColor: Colors.redAccent,
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
                      // 保证当前选中学科引用也是更新的实例
                      if (_currentSubject?.name == subject.name) {
                        _currentSubject = updated;
                      }
                      // 若学科 name 修改，则调整 expanded 集合：移除旧名，展开用新名
                      if (name != subject.name) {
                        if (_expandedSubjects.remove(subject.name)) {
                          _expandedSubjects.add(name);
                        }
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

  // 选择学科（不影响展开多个）
  void _selectSubject(Subject subject) {
    setState(() {
      _currentSubject = subject;
    });
  }

  // 展开/收起学科详情（支持多个同时展开）
  void _toggleSubjectDetail(Subject subject) {
    setState(() {
      if (_expandedSubjects.contains(subject.name)) {
        _expandedSubjects.remove(subject.name);
      } else {
        _expandedSubjects.add(subject.name);
      }
      // 保持 currentSubject 指向当前展开的 subject（如果是展开）
      if (_expandedSubjects.contains(subject.name)) {
        _currentSubject = subject;
      } else {
        if (_currentSubject?.name == subject.name) _currentSubject = null;
      }
    });
  }

  // 修改学科重要度，同时更新当前学科引用（如果匹配）
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
        if (_currentSubject?.name == subject.name) {
          _currentSubject = updated;
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _noteController.dispose();
    _breathController.dispose();
    _audioPlayer.dispose();
    _customMinutesController?.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    // 计算左侧面板宽度，避免重复命名参数错误
    final double leftPanelWidth = _expandedSubjects.isNotEmpty
        ? 320
        : (_isSettingsExpanded ? 320 : 60);

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
          // 左侧折叠栏 - 支持多展开 & 齿轮编辑
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: leftPanelWidth,
            color: const Color(0xFF1A1A2E),
            child: Column(
              children: [
                const SizedBox(height: 20),
                if (!_expandedSubjects.any((_) => true) &&
                    !_subjectsPanelForcedOpen())
                  Expanded(
                    child: Center(
                      child: GestureDetector(
                        onTap: () => setState(
                          () => _expandedSubjects.clear() /* trigger open */,
                        ),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(
                            Icons.arrow_forward_ios,
                            color: Colors.white70,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: Column(
                      children: [
                        // 收起按钮
                        Align(
                          alignment: Alignment.centerRight,
                          child: IconButton(
                            icon: const Icon(
                              Icons.arrow_back_ios,
                              color: Colors.white70,
                            ),
                            onPressed: () =>
                                setState(() => _expandedSubjects.clear()),
                          ),
                        ),
                        // 学科列表
                        Expanded(
                          child: _subjects.isEmpty
                              ? Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
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
                                    // 重要度对应颜色（轻透明用于背景）
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
                                              priorityColors[subject.priority],
                                          leading: IconButton(
                                            icon: const Icon(
                                              Icons.settings,
                                              color: Colors.white70,
                                              size: 18,
                                            ),
                                            onPressed: () =>
                                                _editSubject(subject),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                          ),
                                          title: Text(
                                            subject.name,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                            ),
                                          ),
                                          trailing: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              // 单独做一个小圆点作为该学科的 priority 标识（会根据 subject.priority 更新）
                                              Container(
                                                width: 14,
                                                height: 14,
                                                decoration: BoxDecoration(
                                                  color: _priorityColorByIndex(
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
                                          onTap: () => _selectSubject(subject),
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 16,
                                                vertical: 10,
                                              ),
                                        ),
                                        // 学科详情面板（可同时展开多个）
                                        if (isExpanded)
                                          Container(
                                            color: const Color(0xFF24243E),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 12,
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
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
                                                          subject.priority == 0,
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
                                                          subject.priority == 1,
                                                      onTap: () =>
                                                          _updatePriority(
                                                            subject,
                                                            1,
                                                          ),
                                                      showCheckmark: true,
                                                    ),
                                                    _PriorityColorButton(
                                                      color: Colors.yellow,
                                                      isSelected:
                                                          subject.priority == 2,
                                                      onTap: () =>
                                                          _updatePriority(
                                                            subject,
                                                            2,
                                                          ),
                                                      showCheckmark: true,
                                                    ),
                                                    _PriorityColorButton(
                                                      color: Colors.orange,
                                                      isSelected:
                                                          subject.priority == 3,
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
                                                          subject.priority == 4,
                                                      onTap: () =>
                                                          _updatePriority(
                                                            subject,
                                                            4,
                                                          ),
                                                      showCheckmark: true,
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 16),
                                                const Text(
                                                  '学习目标',
                                                  style: TextStyle(
                                                    color: Colors.white70,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                if (subject.goals.isEmpty)
                                                  const Text(
                                                    '暂无目标',
                                                    style: TextStyle(
                                                      color: Colors.white54,
                                                      fontSize: 14,
                                                    ),
                                                  )
                                                else
                                                  Column(
                                                    children: subject.goals.map((
                                                      goal,
                                                    ) {
                                                      return Padding(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              vertical: 4,
                                                            ),
                                                        child: Row(
                                                          children: [
                                                            const Text(
                                                              '• ',
                                                              style: TextStyle(
                                                                color: Colors
                                                                    .white70,
                                                              ),
                                                            ),
                                                            Text(
                                                              goal,
                                                              style:
                                                                  const TextStyle(
                                                                    color: Colors
                                                                        .white,
                                                                  ),
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                    }).toList(),
                                                  ),
                                                // 累计学习时长展示
                                                const SizedBox(height: 16),
                                                const Text(
                                                  '累计学习时长',
                                                  style: TextStyle(
                                                    color: Colors.white70,
                                                    fontSize: 14,
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
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ],
                                            ),
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
                      ],
                    ),
                  ),
                const SizedBox(height: 20),
                // 展开状态显示加号按钮（底部FAB）
                if (_subjects.isNotEmpty)
                  FloatingActionButton(
                    onPressed: _addSubject,
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    child: const Icon(Icons.add),
                  ),
                const SizedBox(height: 20),
              ],
            ),
          ),
          // 主内容区 - 根据示例调整：使用 Column + Transform 来确保备注在时间上方覆盖
          Expanded(
            child: Container(
              color: Theme.of(context).colorScheme.background,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    // 可折叠设置区域 (unchanged)
                    AnimatedSize(
                      duration: const Duration(milliseconds: 300),
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
                                  // 时长选择
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
                                          height: 100,
                                          child: Stack(
                                            children: [
                                              Positioned(
                                                left: 0,
                                                right: 0,
                                                top: 25,
                                                height: 50,
                                                child: Container(
                                                  decoration: BoxDecoration(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .primary
                                                        .withOpacity(0.3),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                  ),
                                                ),
                                              ),
                                              ListWheelScrollView.useDelegate(
                                                itemExtent: 50,
                                                physics:
                                                    const ClampingScrollPhysics(),
                                                controller:
                                                    _customMinutesController,
                                                onSelectedItemChanged: (int index) {
                                                  setState(
                                                    () =>
                                                        _selectedCustomMinutes =
                                                            index + 1,
                                                  );
                                                },
                                                childDelegate: ListWheelChildBuilderDelegate(
                                                  childCount: 120,
                                                  builder: (context, index) {
                                                    final minutes = index + 1;
                                                    final isSelected =
                                                        _selectedCustomMinutes ==
                                                        minutes;
                                                    return Center(
                                                      child: Text(
                                                        "$minutes 分钟",
                                                        style: TextStyle(
                                                          fontSize: isSelected
                                                              ? 20
                                                              : 16,
                                                          fontWeight: isSelected
                                                              ? FontWeight.bold
                                                              : FontWeight
                                                                    .normal,
                                                          color: isSelected
                                                              ? Theme.of(
                                                                      context,
                                                                    )
                                                                    .colorScheme
                                                                    .primary
                                                              : Colors.white70,
                                                        ),
                                                      ),
                                                    );
                                                  },
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
                                  const SizedBox(height: 16),
                                  // 铃声设置
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
                                          foregroundColor: Colors.white,
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
                                            DropdownMenuItem<String>(
                                              value: "自定义铃声",
                                              child: const Text(
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
                                        child: Row(
                                          children: [
                                            const Icon(
                                              Icons.file_open,
                                              size: 16,
                                            ),
                                            const SizedBox(width: 4),
                                            const Text(
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
                    const SizedBox(height: 20),

                    // 使用 Column + Transform 的覆盖实现（参考你给的示例）
                    // 先渲染时间容器，并给出底部内间距以腾出被覆盖的空间；
                    // 随后渲染备注输入，并通过 Transform.translate 将其向上移动覆盖在时间容器上方。
                    Expanded(
                      flex: 3,
                      child: Column(
                        children: [
                          // 时间容器：我们在 padding 下方留出足够空间（例如 40）以便备注覆盖
                          Expanded(
                            child: AnimatedBuilder(
                              animation: _breathController,
                              builder: (context, child) {
                                return Container(
                                  padding: const EdgeInsets.only(bottom: 40),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Theme.of(
                                          context,
                                        ).colorScheme.primary.withOpacity(0.2),
                                        Theme.of(context).colorScheme.secondary
                                            .withOpacity(0.2),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: _isRunning
                                        ? [
                                            BoxShadow(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary
                                                  .withOpacity(
                                                    _breathController.value *
                                                        0.4,
                                                  ),
                                              blurRadius: 25,
                                              spreadRadius: 3,
                                            ),
                                          ]
                                        : [],
                                  ),
                                  child: Center(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 30,
                                      ),
                                      child: LayoutBuilder(
                                        builder: (context, constraints) {
                                          double fontSize = 80;
                                          if (constraints.maxWidth < 400) {
                                            fontSize = 48;
                                          } else if (constraints.maxWidth <
                                              500) {
                                            fontSize = 56;
                                          }
                                          return Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              if (_currentSubject != null)
                                                Text(
                                                  _currentSubject!.name,
                                                  style: TextStyle(
                                                    fontSize: 24,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.white70,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              const SizedBox(height: 16),
                                              Text(
                                                _formatTime(_seconds),
                                                style: TextStyle(
                                                  fontSize: fontSize,
                                                  fontWeight: FontWeight.w800,
                                                  color:
                                                      _targetDurationMinutes !=
                                                              null &&
                                                          _seconds <= 60
                                                      ? Colors.redAccent
                                                      : Theme.of(
                                                          context,
                                                        ).colorScheme.primary,
                                                  letterSpacing: 4,
                                                ),
                                                overflow: TextOverflow.visible,
                                              ),
                                            ],
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),

                          // 通过 Transform.translate 向上位移，覆盖在时间容器上方
                          Transform.translate(
                            offset: const Offset(0, -28),
                            child: SizedBox(
                              // 与示例保持类似的视觉样式
                              height: 56,
                              child: Material(
                                color: Colors.transparent,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF24243E),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: const Color(0xFF3A3A5A),
                                    ),
                                  ),
                                  child: TextField(
                                    controller: _noteController,
                                    decoration: InputDecoration(
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 14,
                                          ),
                                      prefixIcon: const Icon(
                                        Icons.note_add_outlined,
                                        color: Colors.white60,
                                      ),
                                      hintText: '例如：数学刷题、英语背诵...',
                                      hintStyle: const TextStyle(
                                        color: Colors.white54,
                                      ),
                                      border: InputBorder.none,
                                    ),
                                    enabled: !_isRunning,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      color: Colors.white,
                                    ),
                                    cursorColor: const Color(0xFF42A5F5),
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // 给覆盖后退回布局的间距（避免被下方按钮/内容遮挡）
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),

                    const SizedBox(height: 8),

                    // 控制按钮
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton(
                          onPressed: _startTimer,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3979E0),
                            foregroundColor: Colors.white,
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
                            backgroundColor: const Color(0xFFF57C00),
                            foregroundColor: Colors.white,
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
                            backgroundColor: const Color(0xFF4CAF50),
                            foregroundColor: Colors.white,
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
                    const SizedBox(height: 25),

                    // 学习日志
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

  // helper to decide initial left panel open state (keeps previous behavior if desired)
  bool _subjectsPanelForcedOpen() {
    // In previous code the panel was controlled by _isSubjectsPanelExpanded; we replicate a simple heuristic:
    return _subjects.isNotEmpty;
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

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    // 创建颜色动画：从原始颜色到更亮的颜色
    _colorAnimation =
        ColorTween(
          begin: widget.color,
          end: HSLColor.fromColor(widget.color)
              .withLightness(
                (HSLColor.fromColor(widget.color).lightness + 0.3).clamp(
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
    // 当 color 改变时，重建 color tween 以匹配新颜色
    if (oldWidget.color != widget.color) {
      _colorAnimation =
          ColorTween(
            begin: widget.color,
            end: HSLColor.fromColor(widget.color)
                .withLightness(
                  (HSLColor.fromColor(widget.color).lightness + 0.3).clamp(
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

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        setState(() => _isHovered = true);
        _animationController.forward();
      },
      onExit: (_) {
        setState(() => _isHovered = false);
        _animationController.reverse();
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: Listenable.merge([_scaleAnimation, _colorAnimation]),
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnimation.value,
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
                            color: _colorAnimation.value!.withOpacity(0.5),
                            blurRadius: 4,
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
