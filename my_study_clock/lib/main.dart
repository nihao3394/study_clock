import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'dart:async';
import 'package:path_provider/path_provider.dart';

void main() {
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    WidgetsFlutterBinding.ensureInitialized();
  }
  runApp(const StudyClockApp());
}

// 主题配置：暗色系柔和风格 + Material Design 3
class StudyClockApp extends StatelessWidget {
  const StudyClockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '学习钟',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark, // 切换为暗模式
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2196F3), // 主色调：低饱和蓝（暗系友好）
          primary: const Color(0xFF42A5F5), // 主色：柔和亮蓝（暗背景中清晰可见）
          secondary: const Color(0xFF66BB6A), // 辅助色：低饱和绿
          surface: const Color(0xFF1A1A2E), // 背景色：深暗蓝紫
          background: const Color(0xFF161625), // 整体背景色
          onPrimary: Colors.white, // 主色上的文字色（修复按钮文字可见性）
          onSecondary: Colors.white,
          onSurface: Colors.white70,
        ),
        cardTheme: CardThemeData(
          elevation: 6,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          color: const Color(0xFF24243E), // 卡片暗色调
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
            foregroundColor: Colors.white, // 按钮文字默认白色（确保可见）
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
  late AnimationController _breathController; // 呼吸灯动画控制器

  @override
  void initState() {
    super.initState();
    _initLogFile();
    // 初始化呼吸灯动画（计时中时生效）
    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  // 初始化日志文件
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

  // 格式化时间（00:00:00）+ 数字平滑过渡
  String _formatTime(int seconds) {
    int h = seconds ~/ 3600;
    int m = (seconds % 3600) ~/ 60;
    int s = seconds % 60;
    return "${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
  }

  // 保存日志到本地
  Future<void> _saveLogToFile(String log) async {
    await _logFile.writeAsString('$log\n', mode: FileMode.append);
  }

  // 开始计时
  void _startTimer() {
    if (!_isRunning) {
      setState(() => _isRunning = true);
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() => _seconds++);
      });
      _breathController.forward(); // 启动呼吸灯
    }
  }

  // 暂停计时
  void _pauseTimer() {
    if (_isRunning) {
      setState(() => _isRunning = false);
      _timer.cancel();
      _breathController.stop(); // 停止呼吸灯
    }
  }

  // 结束计时 + 保存日志
  void _endTimer() {
    _pauseTimer();
    if (_seconds == 0) return;

    String timeNow = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    String log =
        "$timeNow | 学习时长：${_formatTime(_seconds)} | 备注：${_noteController.text.isEmpty ? '无' : _noteController.text}";

    setState(() {
      _studyLogs.add(log);
      _seconds = 0;
      _noteController.clear();
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

  // 删除单条日志
  void _deleteLog(int index) async {
    setState(() {
      _studyLogs.removeAt(index);
    });
    // 重新写入所有日志（覆盖原文件）
    await _logFile.writeAsString(_studyLogs.join('\n') + '\n');
  }

  @override
  void dispose() {
    _timer.cancel();
    _noteController.dispose();
    _breathController.dispose();
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
        backgroundColor: const Color(0xFF1A1A2E), // 导航栏暗色调
      ),
      body: Container(
        color: Theme.of(context).colorScheme.background, // 整体暗背景
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              // 计时显示区域（带呼吸灯效果）
              Expanded(
                flex: 2,
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
                            fontSize: 64,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.primary,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),

              // 备注输入区域
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
                cursorColor: Color(0xFF42A5F5),
              ),
              const SizedBox(height: 20),

              // 控制按钮区域（横向均匀分布）
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // 开始按钮：降低饱和度+白色文字，解决不可见问题
                  ElevatedButton(
                    onPressed: _startTimer,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3979E0), // 低饱和蓝（不刺眼）
                      foregroundColor: Colors.white, // 强制白色文字
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
                      backgroundColor: const Color(0xFFF57C00), // 低饱和橙
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
                      backgroundColor: const Color(0xFF4CAF50), // 低饱和绿
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

              // 日志列表区域（带标题和滚动）
              Expanded(
                flex: 3,
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
                          style: TextStyle(fontSize: 14, color: Colors.white54),
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
                                  Icon(
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
                                // 交替背景色（暗系中轻微区分）
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
                                        style: TextStyle(
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
