// Complete main.dart
// Dependencies (pubspec.yaml):
//   path_provider: ^2.0.0
//   audioplayers: ^1.0.0
//   file_picker: ^4.0.0
//   intl: ^0.17.0

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

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
      ),
      home: const StudyClockPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// Data models
class Subject {
  final String name;
  final int priority;
  final List<String> goals;

  Subject({required this.name, this.priority = 0, this.goals = const []});

  Map<String, dynamic> toJson() => {
    'name': name,
    'priority': priority,
    'goals': goals,
  };

  factory Subject.fromJson(Map<String, dynamic> json) {
    return Subject(
      name: json['name'] as String,
      priority: json['priority'] as int? ?? 0,
      goals:
          (json['goals'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }
}

class SubjectStat {
  final String subjectName;
  int totalSeconds;
  SubjectStat({required this.subjectName, this.totalSeconds = 0});

  Map<String, dynamic> toJson() => {
    'subjectName': subjectName,
    'totalSeconds': totalSeconds,
  };

  factory SubjectStat.fromJson(Map<String, dynamic> json) {
    return SubjectStat(
      subjectName: json['subjectName'] as String,
      totalSeconds: json['totalSeconds'] as int? ?? 0,
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
  // Timer state
  int _seconds = 0;
  bool _isRunning = false;
  Timer? _timer;
  DateTime? _timerStartTime;

  // Logs & note
  final List<String> _studyLogs = [];
  final TextEditingController _noteController = TextEditingController();
  final FocusNode _noteFocusNode = FocusNode();
  late File _logFile;
  late File _subjectsFile;
  late File _subjectStatsFile;

  // Animations
  late final AnimationController _breathController;

  // Settings UI state
  bool _isSettingsExpanded = true;
  int? _targetDurationMinutes;
  int _selectedCustomMinutes = 30;
  FixedExtentScrollController? _customMinutesController;

  // Audio
  final AudioPlayer _audioPlayer = AudioPlayer();
  PlayerState _audioPlayerState = PlayerState.stopped;
  bool _isPlayingPreview = false;
  bool _enableRingtone = true;
  final List<Map<String, String>> _builtInRingtones = [
    {"name": "提示音1", "path": "sounds/clockstone_1.mp3"},
    {"name": "提示音2", "path": "sounds/clockstone_2.mp3"},
    {"name": "提示音3", "path": "sounds/clockstone_3.mp3"},
    {"name": "提示音4", "path": "sounds/clockstone_cs.mp3"},
  ];
  String? _selectedRingtonePath;
  String? _customRingtoneFilePath;

  // Sidebar / subjects
  bool _isSidebarExpanded = true; // logical state
  late final AnimationController
  _sidebarController; // drives smooth width & content effects
  List<Subject> _subjects = [];
  List<SubjectStat> _subjectStats = [];
  Subject? _currentSubject;
  final Set<String> _expandedSubjects = {};

  // Animation config
  static const Duration _panelAnimDuration = Duration(milliseconds: 420);
  static const Curve _panelAnimCurve = Curves.easeInOut;

  // sidebar sizes and blur intensity
  static const double _sidebarExpandedWidth = 320.0;
  static const double _sidebarCollapsedWidth = 60.0;
  static const double _sidebarMaxBlur = 8.0;

  @override
  void initState() {
    super.initState();
    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _selectedRingtonePath = _builtInRingtones.first['path'];
    _customMinutesController = FixedExtentScrollController(
      initialItem: _selectedCustomMinutes - 1,
    );
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _audioPlayerState = state;
          if (state == PlayerState.stopped) _isPlayingPreview = false;
        });
      }
    });
    _initFiles();
    _preloadRingtone();

    // sidebar controller: initialize based on _isSidebarExpanded
    _sidebarController = AnimationController(
      vsync: this,
      duration: _panelAnimDuration,
      value: _isSidebarExpanded ? 1.0 : 0.0,
    );

    // track focus to change label/border color
    _noteFocusNode.addListener(() {
      if (mounted) setState(() {});
    });
  }

  Future<void> _initFiles() async {
    final dir = await getApplicationDocumentsDirectory();
    _logFile = File('${dir.path}/StudyClockLogs.txt');
    _subjectsFile = File('${dir.path}/StudyClockSubjects.json');
    _subjectStatsFile = File('${dir.path}/StudyClockSubjectStats.json');

    if (await _logFile.exists()) {
      final content = await _logFile.readAsString();
      if (content.isNotEmpty) {
        _studyLogs.addAll(content.split('\n').where((l) => l.isNotEmpty));
      }
    }

    if (await _subjectsFile.exists()) {
      try {
        final raw = await _subjectsFile.readAsString();
        final data = json.decode(raw);
        if (data is List) {
          _subjects = data
              .map((e) => Subject.fromJson(e as Map<String, dynamic>))
              .toList();
        }
      } catch (_) {}
    }

    if (await _subjectStatsFile.exists()) {
      try {
        final raw = await _subjectStatsFile.readAsString();
        final data = json.decode(raw);
        if (data is List) _subject_stats_load(data);
      } catch (_) {}
    }
    setState(() {});
  }

  void _subject_stats_load(List<dynamic> data) {
    _subjectStats = data
        .map((e) => SubjectStat.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _saveSubjects() async {
    try {
      await _subjectsFile.writeAsString(
        json.encode(_subjects.map((s) => s.toJson()).toList()),
      );
    } catch (_) {}
  }

  Future<void> _saveSubjectStats() async {
    try {
      await _subjectStatsFile.writeAsString(
        json.encode(_subjectStats.map((s) => s.toJson()).toList()),
      );
    } catch (_) {}
  }

  Future<void> _preloadRingtone() async {
    final path = _selectedRingtonePath;
    if (path == null && _customRingtoneFilePath == null) return;
    try {
      if (_customRingtoneFilePath != null) {
        await _audioPlayer.setSource(
          DeviceFileSource(_customRingtoneFilePath!),
        );
      } else {
        await _audioPlayer.setSource(AssetSource(path!));
      }
    } catch (_) {}
  }

  Future<void> _togglePreviewRingtone() async {
    if (!_enableRingtone) return;
    try {
      if (_isPlayingPreview) {
        await _audioPlayer.pause();
        setState(() => _isPlayingPreview = false);
      } else {
        if (_audioPlayerState == PlayerState.paused) {
          await _audio_player_resume_safe();
        } else {
          if (_customRingtoneFilePath != null) {
            await _audioPlayer.play(DeviceFileSource(_customRingtoneFilePath!));
          } else if (_selectedRingtonePath != null) {
            await _audioPlayer.play(AssetSource(_selectedRingtonePath!));
          }
        }
        setState(() => _isPlayingPreview = true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('铃声预览失败：$e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _audio_player_resume_safe() async {
    try {
      await _audioPlayer.resume();
    } catch (_) {}
  }

  Future<void> _selectCustomRingtone() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowedExtensions: ['mp3', 'wav', 'ogg'],
    );
    if (res != null && res.files.single.path != null) {
      if (_isPlayingPreview) {
        await _audioPlayer.stop();
        _isPlayingPreview = false;
      }
      setState(() {
        _customRingtoneFilePath = res.files.single.path;
        _selectedRingtonePath = null;
      });
      await _preloadRingtone();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('自定义铃声已选中'),
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
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _saveLogToFile(String log) async {
    try {
      await _logFile.writeAsString('$log\n', mode: FileMode.append);
    } catch (_) {}
  }

  void _selectFixedDuration(int minutes) {
    setState(() {
      _targetDurationMinutes = minutes;
      _seconds = minutes * 60;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已选择 ${minutes}分钟学习时长'),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    }
  }

  void _confirmCustomDuration() {
    setState(() {
      _targetDurationMinutes = _selectedCustomMinutes;
      _seconds = _selectedCustomMinutes * 60;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已选择自定义 ${_selectedCustomMinutes}分钟学习时长'),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    }
  }

  void _cancelDurationSelection() {
    setState(() {
      _targetDurationMinutes = null;
      _seconds = 0;
      _timerStartTime = null;
    });
  }

  // Start behavior: collapse settings and start timer
  void _startTimer() {
    if (_isRunning) return;
    setState(() {
      _isRunning = true;
      _timerStartTime = DateTime.now();
      if (_isSettingsExpanded) _isSettingsExpanded = false;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
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

  Future<void> _playRingtone() async {
    if (!_enableRingtone) return;
    try {
      if (_customRingtoneFilePath != null) {
        await _audioPlayer.play(DeviceFileSource(_customRingtoneFilePath!));
      } else if (_selectedRingtonePath != null) {
        await _audioPlayer.play(AssetSource(_selectedRingtonePath!));
      }
    } catch (_) {}
  }

  void _showCountdownCompleteDialog() {
    final actualDurationSeconds = DateTime.now()
        .difference(_timerStartTime ?? DateTime.now())
        .inSeconds;
    final actualDuration = _formatTime(actualDurationSeconds);
    final dialogNoteController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF24243E),
          title: Text(
            _currentSubject != null
                ? '${_currentSubject!.name} 学习时长结束！'
                : '学习时长结束！',
            style: const TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '目标时长：${_formatTime((_targetDurationMinutes ?? 0) * 60)}\n实际学习时长：$actualDuration',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: dialogNoteController,
                decoration: InputDecoration(
                  labelText: '添加备注（可选）',
                  hintText: '例如：数学刷题、英语背诵...',
                  labelStyle: const TextStyle(color: Colors.white60),
                  hintStyle: const TextStyle(color: Colors.white54),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                final timeNow = DateFormat(
                  'yyyy-MM-dd HH:mm:ss',
                ).format(DateTime.now());
                final note = dialogNoteController.text.trim().isEmpty
                    ? '无'
                    : dialogNoteController.text.trim();
                final subjectText = _currentSubject != null
                    ? ' | 学科：${_currentSubject!.name}'
                    : '';
                final log =
                    '$timeNow | 目标时长：${_formatTime((_targetDurationMinutes ?? 0) * 60)} | 实际学习时长：$actualDuration$subjectText | 备注：$note';

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
                Navigator.of(ctx).pop();
              },
              child: const Text(
                '确认记录',
                style: TextStyle(color: Color(0xFF42A5F5)),
              ),
            ),
          ],
        );
      },
    );
  }

  void _pauseTimer() {
    if (!_isRunning) return;
    setState(() => _isRunning = false);
    _timer?.cancel();
    _breathController.stop();
  }

  void _endTimer() {
    _pauseTimer();
    if (_timerStartTime == null ||
        (DateTime.now().difference(_timerStartTime!).inSeconds < 1)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('未检测到有效学习时长 ❌'),
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
    final targetText = _targetDurationMinutes != null
        ? _formatTime(_targetDurationMinutes! * 60)
        : '无';
    final subjectText = _currentSubject != null
        ? ' | 学科：${_currentSubject!.name}'
        : '';
    final timeNow = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    final log =
        '$timeNow | 目标时长：$targetText | 实际学习时长：$actualDuration$subjectText | 备注：${_noteController.text.isEmpty ? '无' : _noteController.text}';

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

    _saveLogToFile(log);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('日志已保存 ✅'),
          backgroundColor: Theme.of(context).colorScheme.secondary,
        ),
      );
    }
  }

  void _updateSubjectTotalDuration(String name, int addSeconds) {
    final idx = _subjectStats.indexWhere((s) => s.subjectName == name);
    if (idx != -1) {
      _subjectStats[idx].totalSeconds += addSeconds;
    } else {
      _subjectStats.add(
        SubjectStat(subjectName: name, totalSeconds: addSeconds),
      );
    }
    _saveSubjectStats();
  }

  String _getSubjectTotalDuration(String name) {
    final s = _subjectStats.firstWhere(
      (st) => st.subjectName == name,
      orElse: () => SubjectStat(subjectName: name),
    );
    return _formatTime(s.totalSeconds);
  }

  void _deleteLog(int idx) async {
    setState(() => _studyLogs.removeAt(idx));
    try {
      await _logFile.writeAsString(_studyLogs.join('\n') + '\n');
    } catch (_) {}
  }

  // Subject management dialogs
  void _addSubject() {
    final nameController = TextEditingController();
    final goalsController = TextEditingController();
    int priority = 0;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setD) {
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
                      ),
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 12),
                  const Text('重要度', style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      PriorityColorButton(
                        color: Colors.blue,
                        isSelected: priority == 0,
                        onTap: () => setD(() => priority = 0),
                      ),
                      PriorityColorButton(
                        color: Colors.green,
                        isSelected: priority == 1,
                        onTap: () => setD(() => priority = 1),
                      ),
                      PriorityColorButton(
                        color: Colors.yellow,
                        isSelected: priority == 2,
                        onTap: () => setD(() => priority = 2),
                      ),
                      PriorityColorButton(
                        color: Colors.orange,
                        isSelected: priority == 3,
                        onTap: () => setD(() => priority = 3),
                      ),
                      PriorityColorButton(
                        color: Colors.red,
                        isSelected: priority == 4,
                        onTap: () => setD(() => priority = 4),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: goalsController,
                    decoration: InputDecoration(
                      labelText: '学习目标（回车键以分行）',
                      labelStyle: const TextStyle(color: Colors.white60),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    minLines: 2,
                    maxLines: 5,
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  '取消',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
              TextButton(
                onPressed: () {
                  final name = nameController.text.trim();
                  if (name.isEmpty) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('学科名称不能为空'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                    return;
                  }
                  if (_subjects.any((s) => s.name == name)) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('该学科已存在'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                    return;
                  }
                  final goals = goalsController.text
                      .split('\n')
                      .map((e) => e.trim())
                      .where((e) => e.isNotEmpty)
                      .toList();
                  setState(() {
                    _subjects.add(
                      Subject(name: name, priority: priority, goals: goals),
                    );
                    _saveSubjects();
                  });
                  Navigator.pop(ctx);
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
    final nameController = TextEditingController(text: subject.name);
    final goalsController = TextEditingController(
      text: subject.goals.join('\n'),
    );
    int priority = subject.priority;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setD) {
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
                      ),
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 12),
                  const Text('重要度', style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      PriorityColorButton(
                        color: Colors.blue,
                        isSelected: priority == 0,
                        onTap: () => setD(() => priority = 0),
                      ),
                      PriorityColorButton(
                        color: Colors.green,
                        isSelected: priority == 1,
                        onTap: () => setD(() => priority = 1),
                      ),
                      PriorityColorButton(
                        color: Colors.yellow,
                        isSelected: priority == 2,
                        onTap: () => setD(() => priority = 2),
                      ),
                      PriorityColorButton(
                        color: Colors.orange,
                        isSelected: priority == 3,
                        onTap: () => setD(() => priority = 3),
                      ),
                      PriorityColorButton(
                        color: Colors.red,
                        isSelected: priority == 4,
                        onTap: () => setD(() => priority = 4),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: goalsController,
                    decoration: InputDecoration(
                      labelText: '学习目标（回车键以分行）',
                      labelStyle: const TextStyle(color: Colors.white60),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    minLines: 2,
                    maxLines: 6,
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  '取消',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
              TextButton(
                onPressed: () {
                  final name = nameController.text.trim();
                  if (name.isEmpty) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('学科名称不能为空'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                    return;
                  }
                  if (_subjects.any(
                    (s) => s.name == name && s.name != subject.name,
                  )) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('已存在同名学科'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                    return;
                  }
                  final goals = goalsController.text
                      .split('\n')
                      .map((e) => e.trim())
                      .where((e) => e.isNotEmpty)
                      .toList();
                  final idx = _subjects.indexWhere(
                    (s) => s.name == subject.name,
                  );
                  if (idx != -1) {
                    setState(() {
                      _subjects[idx] = Subject(
                        name: name,
                        priority: priority,
                        goals: goals,
                      );
                      if (_currentSubject?.name == subject.name)
                        _currentSubject = _subjects[idx];
                      _saveSubjects();
                    });
                  }
                  Navigator.pop(ctx);
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

  void _selectSubject(Subject subject) =>
      setState(() => _currentSubject = subject);

  void _toggleSubjectDetail(Subject subj) {
    setState(() {
      if (_expandedSubjects.contains(subj.name))
        _expandedSubjects.remove(subj.name);
      else
        _expandedSubjects.add(subj.name);
      if (_expandedSubjects.contains(subj.name))
        _currentSubject = subj;
      else if (_currentSubject?.name == subj.name)
        _currentSubject = null;
    });
  }

  void _updatePriority(Subject subj, int p) {
    final idx = _subjects.indexWhere((s) => s.name == subj.name);
    if (idx != -1) {
      setState(() {
        _subjects[idx] = Subject(
          name: subj.name,
          priority: p,
          goals: subj.goals,
        );
        if (_currentSubject?.name == subj.name)
          _currentSubject = _subjects[idx];
        _saveSubjects();
      });
    }
  }

  double _timerHeight(BuildContext c) {
    final h = MediaQuery.of(c).size.height;
    final normal = h * 0.36;
    final shrunk = normal * 0.56;
    return _isSettingsExpanded ? shrunk : normal;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _noteController.dispose();
    _noteFocusNode.dispose();
    _breathController.dispose();
    try {
      _audioPlayer.dispose();
    } catch (_) {}
    _customMinutesController?.dispose();
    _sidebarController.dispose();
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

  void _toggleSidebar() {
    if (_sidebarController.isAnimating) return;
    if (_sidebarController.value > 0.5) {
      // close
      _sidebarController.reverse();
      setState(() => _isSidebarExpanded = false);
    } else {
      _sidebarController.forward();
      setState(() => _isSidebarExpanded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('学习钟'),
        centerTitle: true,
        elevation: 2,
        backgroundColor: const Color(0xFF1A1A2E),
      ),
      body: Row(
        children: [
          // Sidebar - smooth width animation driven by controller
          AnimatedBuilder(
            animation: _sidebarController,
            builder: (ctx, child) {
              final t = Curves.easeInOut.transform(_sidebarController.value);
              final width = lerpDouble(
                _sidebarCollapsedWidth,
                _sidebarExpandedWidth,
                t,
              )!;
              // opacity & blur for content: when collapsed (t->0) content should be blurred and transparent
              final contentOpacity = t.clamp(0.0, 1.0);
              final blurSigma = (1.0 - t) * _sidebarMaxBlur;
              final showFullHeader = t > 0.45;
              final isCollapsedVisual = t < 0.18;

              return SizedBox(
                width: width,
                child: Container(
                  color: const Color(0xFF1A1A2E),
                  child: Column(
                    children: [
                      const SizedBox(height: 12),
                      // Header: show full title when expanded visual, otherwise show empty area to match spacing
                      if (showFullHeader)
                        Row(
                          children: [
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                '学科',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.chevron_left,
                                color: Colors.white70,
                              ),
                              onPressed: _toggleSidebar,
                            ),
                            const SizedBox(width: 6),
                          ],
                        )
                      else
                        const SizedBox(height: 44),
                      const SizedBox(height: 4),

                      // IMPORTANT: when visually collapsed we must render the collapsed buttons without opacity/blur
                      Expanded(
                        child: isCollapsedVisual
                            ? _buildCollapsedSidebarContent() // render collapsed controls plainly so icons are visible
                            : ClipRect(
                                child: Opacity(
                                  opacity: contentOpacity,
                                  child: ImageFiltered(
                                    imageFilter: ImageFilter.blur(
                                      sigmaX: blurSigma,
                                      sigmaY: blurSigma,
                                    ),
                                    child: _isSidebarExpanded
                                        ? _buildExpandedSidebarContent()
                                        : _buildCollapsedSidebarContent(),
                                  ),
                                ),
                              ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              );
            },
          ),

          // Main area
          Expanded(
            child: Container(
              color: Theme.of(context).colorScheme.background,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    // Settings - animated in main area (keeps AnimatedSize)
                    AnimatedSize(
                      duration: _panelAnimDuration,
                      curve: _panelAnimCurve,
                      child: _isSettingsExpanded
                          ? _buildSettingsPanel()
                          : _buildSettingsCollapsed(),
                    ),

                    const SizedBox(height: 12),

                    // Timer area with conditional overlay behavior
                    if (_isSettingsExpanded) ...[
                      _buildTimerWithOverlay(context),
                      const SizedBox(height: 60),
                    ] else ...[
                      _buildTimerNormal(context),
                      const SizedBox(height: 12),
                      _buildNoteInputNormal(), // uses the refined floating outline TextField
                      const SizedBox(height: 12),
                      _buildControlsNormal(),
                      const SizedBox(height: 12),
                    ],

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
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '共 ${_studyLogs.length} 条',
                                style: const TextStyle(color: Colors.white54),
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
                                      children: const [
                                        Icon(
                                          Icons.history_outlined,
                                          size: 60,
                                          color: Colors.white24,
                                        ),
                                        SizedBox(height: 10),
                                        Text(
                                          '暂无学习记录',
                                          style: TextStyle(
                                            color: Colors.white54,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : ListView.builder(
                                    itemCount: _studyLogs.length,
                                    itemBuilder: (ctx, i) {
                                      final isEven = i % 2 == 0;
                                      return Dismissible(
                                        key: Key(_studyLogs[i]),
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
                                          ),
                                        ),
                                        onDismissed: (_) => _deleteLog(i),
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
                                              _studyLogs[i],
                                              style: const TextStyle(
                                                color: Colors.white70,
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

  // Sidebar content widgets (expanded/collapsed)
  Widget _buildExpandedSidebarContent() {
    return Column(
      children: [
        Expanded(
          child: _subjects.isEmpty
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      '当前还没有添加学科，点击加号试试吧~',
                      style: TextStyle(color: Colors.white54),
                    ),
                    const SizedBox(height: 16),
                    FloatingActionButton(
                      onPressed: _addSubject,
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      child: const Icon(Icons.add),
                    ),
                  ],
                )
              : ListView.builder(
                  itemCount: _subjects.length,
                  itemBuilder: (ctx, i) {
                    final subj = _subjects[i];
                    final isExpanded = _expandedSubjects.contains(subj.name);
                    return Column(
                      children: [
                        ListTile(
                          leading: IconButton(
                            icon: const Icon(
                              Icons.settings,
                              color: Colors.white70,
                              size: 18,
                            ),
                            onPressed: () => _editSubject(subj),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                          title: Text(
                            subj.name,
                            style: const TextStyle(color: Colors.white),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  color: _priorityColorByIndex(subj.priority),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white24),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: Icon(
                                  isExpanded
                                      ? Icons.expand_less
                                      : Icons.expand_more,
                                  color: Colors.white70,
                                ),
                                onPressed: () => _toggleSubjectDetail(subj),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ),
                          onTap: () => _selectSubject(subj),
                        ),
                        // Instant show/hide details (no animation)
                        if (isExpanded)
                          Container(
                            color: const Color(0xFF24243E),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '重要度',
                                  style: TextStyle(color: Colors.white70),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: [
                                    PriorityColorButton(
                                      color: Colors.blue,
                                      isSelected: subj.priority == 0,
                                      onTap: () => _updatePriority(subj, 0),
                                    ),
                                    PriorityColorButton(
                                      color: Colors.green,
                                      isSelected: subj.priority == 1,
                                      onTap: () => _updatePriority(subj, 1),
                                    ),
                                    PriorityColorButton(
                                      color: Colors.yellow,
                                      isSelected: subj.priority == 2,
                                      onTap: () => _updatePriority(subj, 2),
                                    ),
                                    PriorityColorButton(
                                      color: Colors.orange,
                                      isSelected: subj.priority == 3,
                                      onTap: () => _updatePriority(subj, 3),
                                    ),
                                    PriorityColorButton(
                                      color: Colors.red,
                                      isSelected: subj.priority == 4,
                                      onTap: () => _updatePriority(subj, 4),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  '学习目标',
                                  style: TextStyle(color: Colors.white70),
                                ),
                                const SizedBox(height: 8),
                                if (subj.goals.isEmpty)
                                  const Text(
                                    '暂无目标',
                                    style: TextStyle(color: Colors.white54),
                                  )
                                else
                                  Column(
                                    children: subj.goals
                                        .map(
                                          (g) => Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 2,
                                            ),
                                            child: Row(
                                              children: [
                                                const Text(
                                                  '• ',
                                                  style: TextStyle(
                                                    color: Colors.white70,
                                                  ),
                                                ),
                                                Flexible(
                                                  child: Text(
                                                    g,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        )
                                        .toList(),
                                  ),
                                const SizedBox(height: 8),
                                const Text(
                                  '累计学习时长',
                                  style: TextStyle(color: Colors.white70),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _getSubjectTotalDuration(subj.name),
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        const Divider(color: Colors.white10, height: 1),
                      ],
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          child: FloatingActionButton(
            onPressed: _addSubject,
            backgroundColor: Theme.of(context).colorScheme.primary,
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }

  Widget _buildCollapsedSidebarContent() {
    // Collapsed content must remain visible and clickable -> render plainly (no opacity/blur)
    return Column(
      children: [
        const SizedBox(height: 6),
        Expanded(
          child: Center(
            child: IconButton(
              icon: const Icon(
                Icons.chevron_right,
                color: Colors.white70,
                size: 28,
              ),
              onPressed: _toggleSidebar,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: FloatingActionButton(
            onPressed: _addSubject,
            backgroundColor: Theme.of(context).colorScheme.primary,
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsPanel() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF24243E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '设置',
                style: TextStyle(fontSize: 16, color: Colors.white),
              ),
              IconButton(
                icon: const Icon(Icons.expand_less, color: Colors.white70),
                onPressed: () => setState(() => _isSettingsExpanded = false),
              ),
            ],
          ),
          const Divider(color: Colors.white10, height: 16),
          const Text('选择学习时长（可选）', style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _DurationButton(
                minutes: 20,
                onTap: _selectFixedDuration,
                isSelected: _targetDurationMinutes == 20,
              ),
              _DurationButton(
                minutes: 40,
                onTap: _selectFixedDuration,
                isSelected: _targetDurationMinutes == 40,
              ),
              _DurationButton(
                minutes: 60,
                onTap: _selectFixedDuration,
                isSelected: _targetDurationMinutes == 60,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('自定义：', style: TextStyle(color: Colors.white70)),
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
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      ListWheelScrollView.useDelegate(
                        controller: _customMinutesController,
                        itemExtent: 44,
                        physics: const FixedExtentScrollPhysics(),
                        diameterRatio: 1.6,
                        perspective: 0.005,
                        useMagnifier: true,
                        magnification: 1.25,
                        onSelectedItemChanged: (i) =>
                            setState(() => _selectedCustomMinutes = i + 1),
                        childDelegate: ListWheelChildBuilderDelegate(
                          builder: (ctx, index) {
                            if (index < 0 || index >= 120) return null;
                            final m = index + 1;
                            final isSel = _selectedCustomMinutes == m;
                            return AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 200),
                              style: TextStyle(
                                fontSize: isSel ? 20 : 15,
                                color: isSel
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.white70,
                                fontWeight: isSel
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                              child: Center(child: Text('$m 分钟')),
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
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                ),
                child: const Text('确认'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('铃声设置', style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 8),
          Row(
            children: [
              Switch(
                value: _enableRingtone,
                onChanged: (v) => setState(() => _enableRingtone = v),
                activeColor: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 6),
              const Text('启用铃声', style: TextStyle(color: Colors.white70)),
              const SizedBox(width: 20),
              ElevatedButton(
                onPressed: _enableRingtone ? _togglePreviewRingtone : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _enableRingtone
                      ? Theme.of(context).colorScheme.secondary
                      : Colors.grey,
                  foregroundColor: Colors.white,
                ),
                child: Row(
                  children: [
                    Icon(
                      _isPlayingPreview ? Icons.pause : Icons.play_arrow,
                      size: 16,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _isPlayingPreview ? '暂停' : '预览',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('选择铃声：', style: TextStyle(color: Colors.white70)),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value:
                      _selectedRingtonePath ??
                      (_customRingtoneFilePath != null
                          ? '自定义铃声'
                          : _builtInRingtones.first['path']),
                  items: [
                    ..._builtInRingtones.map(
                      (r) => DropdownMenuItem<String>(
                        value: r['path'],
                        child: Text(
                          r['name']!,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                    ),
                    const DropdownMenuItem<String>(
                      value: '自定义铃声',
                      child: Text(
                        '自定义铃声',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ],
                  onChanged: (v) {
                    if (v == '自定义铃声')
                      _selectCustomRingtone();
                    else if (v != null)
                      _switchToBuiltInRingtone(v);
                  },
                  dropdownColor: const Color(0xFF24243E),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: _selectCustomRingtone,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3A3A5A),
                  foregroundColor: Colors.white,
                ),
                child: const Row(
                  children: [
                    Icon(Icons.file_open, size: 16, color: Colors.white),
                    SizedBox(width: 6),
                    Text('本地', style: TextStyle(color: Colors.white)),
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
              child: const Text('取消选择', style: TextStyle(color: Colors.red)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsCollapsed() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF24243E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('设置（已折叠）', style: TextStyle(color: Colors.white)),
          IconButton(
            icon: const Icon(Icons.expand_more, color: Colors.white70),
            onPressed: () => setState(() => _isSettingsExpanded = true),
          ),
        ],
      ),
    );
  }

  Widget _buildTimerWithOverlay(BuildContext context) {
    return AnimatedContainer(
      duration: _panelAnimDuration,
      curve: _panelAnimCurve,
      height: _timerHeight(context),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).colorScheme.primary.withOpacity(0.18),
            Theme.of(context).colorScheme.secondary.withOpacity(0.12),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Center(
              child: LayoutBuilder(
                builder: (ctx, cons) {
                  // 动态调整字体大小，适配展开状态的容器宽度，避免数字溢出
                  double maxFontSize = cons.maxWidth < 300
                      ? 36.0
                      : cons.maxWidth < 400
                      ? 42.0
                      : cons.maxWidth < 500
                      ? 48.0
                      : 56.0;
                  maxFontSize = maxFontSize.clamp(36.0, 56.0); // 限制字体大小范围
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_currentSubject != null)
                        Text(
                          _currentSubject!.name,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      const SizedBox(height: 12),
                      Text(
                        _formatTime(_seconds),
                        style: TextStyle(
                          fontSize: maxFontSize,
                          fontWeight: FontWeight.w800,
                          color:
                              _targetDurationMinutes != null && _seconds <= 60
                              ? Colors.redAccent
                              : Theme.of(context).colorScheme.primary,
                          letterSpacing: 1.5, // 优化数字间距，避免拥挤
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: -36,
            child: Column(
              children: [
                // 优化后的备注输入框（固定高度48px，与折叠状态设置面板一致）
                SizedBox(
                  height: 48,
                  child: Material(
                    color: Colors.transparent,
                    child: TextField(
                      focusNode: _noteFocusNode,
                      controller: _noteController,
                      decoration: InputDecoration(
                        labelText: '添加备注（可选）',
                        hintText: '例如：数学刷题、英语背诵...',
                        prefixIcon: const Icon(
                          Icons.note_add_outlined,
                          color: Colors.white60,
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14, // 垂直内边距优化，确保文本居中
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.white12),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.white12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: Theme.of(context).colorScheme.primary,
                            width: 2,
                          ),
                        ),
                        floatingLabelBehavior:
                            FloatingLabelBehavior.never, // 禁用浮动标签，避免高度变化
                        labelStyle: TextStyle(
                          color: _noteFocusNode.hasFocus
                              ? Theme.of(context).colorScheme.primary
                              : Colors.white60,
                          fontSize: 13,
                        ),
                        hintStyle: const TextStyle(
                          color: Colors.white38,
                          fontSize: 13,
                        ),
                      ),
                      enabled: !_isRunning,
                      style: const TextStyle(fontSize: 14, color: Colors.white),
                      cursorColor: Theme.of(context).colorScheme.primary,
                      textAlignVertical: TextAlignVertical.center, // 文本垂直居中
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton(
                      onPressed: () {
                        setState(() => _isSettingsExpanded = false);
                        _startTimer();
                      },
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
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimerNormal(BuildContext context) {
    return AnimatedContainer(
      duration: _panelAnimDuration,
      curve: _panelAnimCurve,
      height: _timerHeight(context),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).colorScheme.primary.withOpacity(0.18),
            Theme.of(context).colorScheme.secondary.withOpacity(0.12),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: LayoutBuilder(
          builder: (ctx, cons) {
            var fontSize = cons.maxWidth < 400
                ? 48.0
                : (cons.maxWidth < 600 ? 64.0 : 84.0);
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_currentSubject != null)
                  Text(
                    _currentSubject!.name,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                const SizedBox(height: 12),
                Text(
                  _formatTime(_seconds),
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w800,
                    color: _targetDurationMinutes != null && _seconds <= 60
                        ? Colors.redAccent
                        : Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildNoteInputNormal() {
    // 固定高度与折叠状态设置面板一致（48px），确保高度充足
    return SizedBox(
      height: 48,
      child: TextField(
        focusNode: _noteFocusNode,
        controller: _noteController,
        decoration: InputDecoration(
          labelText: '添加备注（可选）',
          hintText: '例如：数学刷题、英语背诵...',
          prefixIcon: const Icon(
            Icons.note_add_outlined,
            color: Colors.white60,
          ),
          isDense: true,
          // 调整垂直内边距，确保文本居中
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.white12),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.white12),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: Theme.of(context).colorScheme.primary,
              width: 2,
            ),
          ),
          // 禁用浮动标签，避免高度变化
          floatingLabelBehavior: FloatingLabelBehavior.never,
          labelStyle: TextStyle(
            color: _noteFocusNode.hasFocus
                ? Theme.of(context).colorScheme.primary
                : Colors.white60,
            fontSize: 13,
          ),
          hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
        ),
        enabled: !_isRunning,
        style: const TextStyle(fontSize: 14, color: Colors.white),
        cursorColor: Theme.of(context).colorScheme.primary,
        textAlignVertical: TextAlignVertical.center, // 文本垂直居中
      ),
    );
  }

  Widget _buildControlsNormal() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        ElevatedButton(
          onPressed: _startTimer,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF3979E0),
            foregroundColor: Colors.white,
          ),
          child: const Row(
            children: [Icon(Icons.play_arrow), SizedBox(width: 8), Text('开始')],
          ),
        ),
        ElevatedButton(
          onPressed: _pauseTimer,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFF57C00),
            foregroundColor: Colors.white,
          ),
          child: const Row(
            children: [Icon(Icons.pause), SizedBox(width: 8), Text('暂停')],
          ),
        ),
        ElevatedButton(
          onPressed: _endTimer,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4CAF50),
            foregroundColor: Colors.white,
          ),
          child: const Row(
            children: [Icon(Icons.check), SizedBox(width: 8), Text('结束记录')],
          ),
        ),
      ],
    );
  }
}

// Reusable small widgets

class _DurationButton extends StatelessWidget {
  final int minutes;
  final void Function(int) onTap;
  final bool isSelected;
  const _DurationButton({
    required this.minutes,
    required this.onTap,
    required this.isSelected,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () => onTap(minutes),
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected
            ? Theme.of(context).colorScheme.primary
            : const Color(0xFF3A3A5A),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text('$minutes 分钟', style: const TextStyle(color: Colors.white)),
    );
  }
}

class PriorityColorButton extends StatefulWidget {
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;
  final double size;
  final bool showCheckmark;

  const PriorityColorButton({
    required this.color,
    required this.isSelected,
    required this.onTap,
    this.size = 24,
    this.showCheckmark = true,
    super.key,
  });

  @override
  State<PriorityColorButton> createState() => _PriorityColorButtonState();
}

class _PriorityColorButtonState extends State<PriorityColorButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _scaleAnim;
  late Animation<Color?> _colorAnim;
  bool _hover = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 1.18).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
    _colorAnim =
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
          CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
        );
  }

  @override
  void didUpdateWidget(covariant PriorityColorButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.color != widget.color) {
      _colorAnim =
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
            CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
          );
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _onEnter(PointerEvent _) {
    setState(() => _hover = true);
    _animController.forward();
  }

  void _onExit(PointerEvent _) {
    setState(() => _hover = false);
    _animController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: _onEnter,
      onExit: _onExit,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: Listenable.merge([_scaleAnim, _animController]),
          builder: (ctx, child) {
            final scale = widget.isSelected
                ? _scaleAnim.value
                : (_hover ? _scaleAnim.value : 1.0);
            final color = _colorAnim.value ?? widget.color;
            return Transform.scale(
              scale: scale,
              child: Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  border: widget.isSelected
                      ? Border.all(color: Colors.white, width: 2)
                      : null,
                  boxShadow: widget.isSelected || _hover
                      ? [
                          BoxShadow(
                            color: color.withOpacity(0.45),
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
