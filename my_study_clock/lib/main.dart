import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'dart:async';
import 'package:path_provider/path_provider.dart'; // 用于获取本地存储路径

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
      title: '简易学习钟',
      theme: ThemeData(primarySwatch: Colors.blue),
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

class _StudyClockPageState extends State<StudyClockPage> {
  int _seconds = 0;
  bool _isRunning = false;
  late Timer _timer;
  final List<String> _studyLogs = [];
  final TextEditingController _noteController = TextEditingController();
  late File _logFile; // 日志文件对象

  @override
  void initState() {
    super.initState();
    _initLogFile(); // 初始化日志文件（创建+读取历史日志）
  }

  // 初始化日志文件：创建文件+读取历史日志
  Future<void> _initLogFile() async {
    // 1. 获取Windows用户文档目录（如：C:\Users\你的用户名\Documents）
    final directory = await getApplicationDocumentsDirectory();
    // 2. 创建日志文件（文件名：StudyClockLogs.txt）
    _logFile = File('${directory.path}/StudyClockLogs.txt');

    // 3. 若文件存在，读取历史日志并显示
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

  // 格式化时间（00:00:00）
  String _formatTime(int seconds) {
    int h = seconds ~/ 3600;
    int m = (seconds % 3600) ~/ 60;
    int s = seconds % 60;
    return "${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
  }

  // 保存日志到本地文件
  Future<void> _saveLogToFile(String log) async {
    // 追加写入日志（每行一条，末尾加换行符）
    await _logFile.writeAsString('$log\n', mode: FileMode.append);
  }

  // 开始计时
  void _startTimer() {
    if (!_isRunning) {
      setState(() => _isRunning = true);
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() => _seconds++);
      });
    }
  }

  // 暂停计时
  void _pauseTimer() {
    if (_isRunning) {
      setState(() => _isRunning = false);
      _timer.cancel();
    }
  }

  // 结束计时（生成日志+保存到本地）
  void _endTimer() {
    _pauseTimer();
    if (_seconds == 0) return;

    // 生成带时间戳的日志
    String timeNow = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    String log =
        "$timeNow | 学习时长：${_formatTime(_seconds)} | 备注：${_noteController.text.isEmpty ? '无' : _noteController.text}";

    setState(() {
      _studyLogs.add(log);
      _seconds = 0;
      _noteController.clear();
    });

    // 保存日志到本地文件
    _saveLogToFile(log)
        .then((_) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("日志已保存到本地！")));
        })
        .catchError((e) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text("日志保存失败：$e")));
        });
  }

  @override
  void dispose() {
    _timer.cancel();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('学习钟（日志持久化）')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // 计时显示区域
            Expanded(
              flex: 2,
              child: Center(
                child: Text(
                  _formatTime(_seconds),
                  style: const TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            // 备注输入区域
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(
                labelText: '添加备注（可选）',
                border: OutlineInputBorder(),
              ),
              enabled: !_isRunning,
            ),

            // 控制按钮区域
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(onPressed: _startTimer, child: const Text('开始')),
                const SizedBox(width: 20),
                ElevatedButton(onPressed: _pauseTimer, child: const Text('暂停')),
                const SizedBox(width: 20),
                ElevatedButton(
                  onPressed: _endTimer,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                  ),
                  child: const Text('结束并记录'),
                ),
              ],
            ),

            // 学习日志区域
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '学习日志（本地保存）',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _studyLogs.length,
                      itemBuilder: (context, index) {
                        return ListTile(
                          title: Text(_studyLogs[index]),
                          leading: const Icon(
                            Icons.check_circle,
                            color: Colors.green,
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
    );
  }
}
