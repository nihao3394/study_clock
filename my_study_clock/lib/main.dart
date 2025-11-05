import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'dart:async';
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

class StudyClockPage extends StatefulWidget {
  const StudyClockPage({super.key});

  @override
  State<StudyClockPage> createState() => _StudyClockPageState();
}

class _StudyClockPageState extends State<StudyClockPage>
    with SingleTickerProviderStateMixin {
  int _seconds = 0;
  bool _isRunning = false;
  late Timer _timer;
  final List<String> _studyLogs = [];
  final TextEditingController _noteController = TextEditingController();
  late File _logFile;
  late AnimationController _breathController;

  // 倒计时核心状态
  int? _targetDurationMinutes; // 目标时长（分钟），null表示自由计时
  int _selectedCustomMinutes = 30;
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

  // 计时开始时间（用于计算实际学习时长）
  DateTime? _timerStartTime;

  @override
  void initState() {
    super.initState();
    _initLogFile();
    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _selectedRingtonePath = _builtInRingtones[0]["path"];
    _preloadRingtone();
    // 监听音频播放器状态变化
    _audioPlayer.onPlayerStateChanged.listen((state) {
      setState(() {
        _audioPlayerState = state;
        // 播放结束自动重置预览状态
        if (state == PlayerState.stopped) {
          _isPlayingPreview = false;
        }
      });
    });
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

  // 播放/暂停预览铃声（核心优化：支持随时启停）
  Future<void> _togglePreviewRingtone() async {
    if (!_enableRingtone || _selectedRingtonePath == null) return;

    try {
      if (_isPlayingPreview) {
        // 正在播放 → 暂停
        await _audioPlayer.pause();
        setState(() => _isPlayingPreview = false);
      } else {
        // 未播放 → 播放（重新播放时重置到开头）
        if (_audioPlayerState == PlayerState.paused) {
          await _audioPlayer.resume();
        } else {
          // 首次播放或已停止，重新设置源并播放
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
      // 切换自定义铃声时停止当前预览
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
    // 切换内置铃声时停止当前预览
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

  Future<void> _initLogFile() async {
    final directory = await getApplicationDocumentsDirectory();
    _logFile = File('${directory.path}/StudyClockLogs.txt');
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
      _seconds = minutes * 60; // 初始化为目标时长（秒）
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
      _seconds = _selectedCustomMinutes * 60; // 初始化为目标时长（秒）
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
      _timerStartTime = null; // 重置开始时间
    });
  }

  // 开始计时（核心新增：倒计时启动时自动折叠设置区域）
  void _startTimer() {
    if (!_isRunning) {
      setState(() {
        _isRunning = true;
        _timerStartTime = DateTime.now(); // 记录计时开始时间
        // 核心新增：如果设置区域是展开状态，自动折叠
        if (_isSettingsExpanded) {
          _isSettingsExpanded = false;
        }
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() {
          if (_targetDurationMinutes != null) {
            // 倒计时模式：秒数递减
            if (_seconds > 0) {
              _seconds--;
            } else {
              // 倒计时结束
              _timer.cancel();
              _isRunning = false;
              _playRingtone();
              _showCountdownCompleteDialog();
            }
          } else {
            // 自由计时：秒数递增
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

  // 倒计时结束弹窗（核心优化：添加备注输入框）
  void _showCountdownCompleteDialog() {
    // 计算实际学习时长（当前时间 - 开始时间）
    final actualDurationSeconds = DateTime.now()
        .difference(_timerStartTime!)
        .inSeconds;
    final actualDuration = _formatTime(actualDurationSeconds);
    // 弹窗专用备注控制器（避免与主界面控制器冲突）
    final TextEditingController dialogNoteController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF24243E),
        title: const Text(
          "学习时长结束！",
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min, // 自适应高度
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 时长信息
            Text(
              "目标时长：${_formatTime(_targetDurationMinutes! * 60)}\n实际学习时长：$actualDuration",
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            // 备注输入框（新增）
            TextField(
              controller: dialogNoteController,
              decoration: InputDecoration(
                labelText: '添加备注（可选）',
                hintText: '例如：数学刷题、英语背诵...',
                labelStyle: TextStyle(color: Colors.white60),
                hintStyle: TextStyle(color: Colors.white54),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Color(0xFF3A3A5A)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Color(0xFF42A5F5), width: 2),
                ),
                contentPadding: EdgeInsets.symmetric(
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
              // 优先使用弹窗内的备注，为空则显示"无"
              String note = dialogNoteController.text.trim().isEmpty
                  ? '无'
                  : dialogNoteController.text.trim();
              String log =
                  "$timeNow | 目标时长：${_formatTime(_targetDurationMinutes! * 60)} | 实际学习时长：$actualDuration | 备注：$note";
              setState(() {
                _studyLogs.add(log);
                _noteController.clear(); // 清空主界面备注框
                _targetDurationMinutes = null;
                _timerStartTime = null; // 重置开始时间
              });
              _saveLogToFile(log);
              // 释放弹窗控制器
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
      _timer.cancel();
      _breathController.stop();
    }
  }

  // 结束计时 + 保存日志（核心优化：统一计算实际学习时长）
  void _endTimer() {
    _pauseTimer();
    if (_timerStartTime == null ||
        (DateTime.now().difference(_timerStartTime!).inSeconds < 1)) {
      // 未有效计时，不保存
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

    // 计算实际学习时长（当前时间 - 开始时间）
    final actualDurationSeconds = DateTime.now()
        .difference(_timerStartTime!)
        .inSeconds;
    final actualDuration = _formatTime(actualDurationSeconds);
    final targetDurationText = _targetDurationMinutes != null
        ? _formatTime(_targetDurationMinutes! * 60)
        : "无";

    String timeNow = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    String log =
        "$timeNow | 目标时长：$targetDurationText | 实际学习时长：$actualDuration | 备注：${_noteController.text.isEmpty ? '无' : _noteController.text}";

    setState(() {
      _studyLogs.add(log);
      _seconds = 0;
      _noteController.clear();
      _targetDurationMinutes = null;
      _timerStartTime = null; // 重置开始时间
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

  void _deleteLog(int index) async {
    setState(() {
      _studyLogs.removeAt(index);
    });
    await _logFile.writeAsString(_studyLogs.join('\n') + '\n');
  }

  @override
  void dispose() {
    _timer.cancel();
    _noteController.dispose();
    _breathController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('学习钟'),
        centerTitle: true,
        elevation: 2,
        shadowColor: Colors.black38,
        backgroundColor: const Color(0xFF1A1A2E),
      ),
      body: Container(
        color: Theme.of(context).colorScheme.background,
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              // 可折叠设置区域
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
                            BoxShadow(color: Colors.black12, blurRadius: 8),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                            const Divider(color: Colors.white10, height: 16),
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
                                    height: 100, // 增加高度，提升滚动体验
                                    child: ListWheelScrollView.useDelegate(
                                      itemExtent: 50, // 增大item高度，滚动更明显
                                      physics:
                                          const ClampingScrollPhysics(), // 平滑滚动（替代Bouncing，适配全平台）
                                      controller: FixedExtentScrollController(
                                        initialItem: _selectedCustomMinutes - 1,
                                      ),
                                      onSelectedItemChanged: (int index) {
                                        setState(
                                          () => _selectedCustomMinutes =
                                              index + 1,
                                        );
                                      },
                                      childDelegate:
                                          ListWheelChildBuilderDelegate(
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
                                                        : FontWeight.normal,
                                                    color: isSelected
                                                        ? Theme.of(
                                                            context,
                                                          ).colorScheme.primary
                                                        : Colors.white70,
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
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
                                  onChanged: (value) =>
                                      setState(() => _enableRingtone = value),
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
                                      // 核心优化：根据播放状态切换图标
                                      Icon(
                                        _isPlayingPreview
                                            ? Icons.pause
                                            : Icons.play_arrow,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _isPlayingPreview ? "暂停" : "预览",
                                        style: const TextStyle(fontSize: 14),
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
                                      ..._builtInRingtones.map((ringtone) {
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
                                        borderRadius: BorderRadius.circular(8),
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
                                    dropdownColor: const Color(0xFF24243E),
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
                                    backgroundColor: const Color(0xFF3A3A5A),
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
                                  style: TextStyle(color: Colors.redAccent),
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
                            BoxShadow(color: Colors.black12, blurRadius: 8),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                              onPressed: () =>
                                  setState(() => _isSettingsExpanded = true),
                            ),
                          ],
                        ),
                      ),
              ),
              const SizedBox(height: 20),

              // 时间显示区域（居中突出）
              Expanded(
                flex: 3,
                child: AnimatedBuilder(
                  animation: _breathController,
                  builder: (context, child) {
                    return Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Theme.of(
                              context,
                            ).colorScheme.primary.withOpacity(0.2),
                            Theme.of(
                              context,
                            ).colorScheme.secondary.withOpacity(0.2),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: _isRunning
                            ? [
                                BoxShadow(
                                  color: Theme.of(context).colorScheme.primary
                                      .withOpacity(
                                        _breathController.value * 0.4,
                                      ),
                                  blurRadius: 25,
                                  spreadRadius: 3,
                                ),
                              ]
                            : [],
                      ),
                      child: Center(
                        child: Text(
                          _formatTime(_seconds),
                          style: TextStyle(
                            fontSize: 80,
                            fontWeight: FontWeight.w800,
                            color:
                                _targetDurationMinutes != null && _seconds <= 60
                                ? Colors.redAccent
                                : Theme.of(context).colorScheme.primary,
                            letterSpacing: 4,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),

              // 备注输入
              TextField(
                controller: _noteController,
                decoration: const InputDecoration(
                  labelText: '添加备注（可选）',
                  hintText: '例如：数学刷题、英语背诵...',
                  prefixIcon: Icon(
                    Icons.note_add_outlined,
                    color: Colors.white60,
                  ),
                ),
                enabled: !_isRunning,
                style: const TextStyle(fontSize: 16, color: Colors.white),
                cursorColor: const Color(0xFF42A5F5),
              ),
              const SizedBox(height: 20),

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

              // 日志列表
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
                            color: Theme.of(context).colorScheme.onSurface,
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
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.history_outlined,
                                    size: 60,
                                    color: Colors.white24,
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
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
                                      color: Colors.redAccent.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    alignment: Alignment.centerRight,
                                    padding: const EdgeInsets.only(right: 20),
                                    child: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.redAccent,
                                      size: 28,
                                    ),
                                  ),
                                  onDismissed: (direction) => _deleteLog(index),
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
