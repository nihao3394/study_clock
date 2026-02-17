import 'dart:io';
import 'package:path_provider/path_provider.dart';

class LogService {
  static final _instance = LogService._internal();
  factory LogService() => _instance;
  LogService._internal();

  late Directory _baseDir;
  int clearDays = 14;

  Future<void> init([int? clearDaysSetting]) async {
    final docDir = await getApplicationDocumentsDirectory();
    _baseDir = Directory('${docDir.path}/study_clock/logs');
    if (clearDaysSetting != null) clearDays = clearDaysSetting;
    await _baseDir.create(recursive: true);
    await migrateOldLogsIfNeeded();
    await autoClearOldLogs();
  }

  String _filePath(DateTime dt) =>
      "${_baseDir.path}/${dt.year}/${dt.month.toString().padLeft(2, '0')}/log_${dt.day.toString().padLeft(2, '0')}.txt";
  Directory _monthDir(int y, int m) =>
      Directory("${_baseDir.path}/$y/${m.toString().padLeft(2, '0')}");

  Future<void> writeLog(String log, DateTime when) async {
    final f = File(_filePath(when));
    await f.parent.create(recursive: true);
    await f.writeAsString(
      "${log.trim()}\n",
      mode: FileMode.append,
      flush: true,
    );
  }

  // 按年/月/日读取
  Future<List<String>> readLogs({int? year, int? month, int? day}) async {
    List<String> logs = [];
    if (year == null) {
      for (var y in _baseDir.listSync().whereType<Directory>()) {
        logs.addAll(await readLogs(year: int.parse(y.path.split('/').last)));
      }
      return logs;
    }
    if (month == null) {
      final d = Directory('${_baseDir.path}/$year');
      if (!d.existsSync()) return [];
      for (var m in d.listSync().whereType<Directory>()) {
        logs.addAll(
          await readLogs(year: year, month: int.parse(m.path.split('/').last)),
        );
      }
      return logs;
    }
    if (day == null) {
      final d = _monthDir(year, month);
      if (!d.existsSync()) return [];
      for (var f in d.listSync().whereType<File>()) {
        logs.addAll(await f.readAsLines());
      }
      return logs;
    }
    final f = File(
      '${_monthDir(year, month).path}/log_${day.toString().padLeft(2, '0')}.txt',
    );
    if (await f.exists()) logs.addAll(await f.readAsLines());
    return logs;
  }

  // 日历用：获取某年某月哪些天有日志
  Future<Set<int>> getDaysWithLogs(int year, int month) async {
    final dir = _monthDir(year, month);
    if (!dir.existsSync()) return {};
    return dir
        .listSync()
        .whereType<File>()
        .where((e) => RegExp(r'log_(\d+)\.txt$').hasMatch(e.path))
        .map(
          (f) => int.parse(
            RegExp(r'log_(\d+)\.txt$').firstMatch(f.path)!.group(1)!,
          ),
        )
        .toSet();
  }

  // 启动时自动清理
  Future<void> autoClearOldLogs() async {
    if (!_baseDir.existsSync()) return;
    final now = DateTime.now();
    for (var y in _baseDir.listSync().whereType<Directory>()) {
      for (var m in y.listSync().whereType<Directory>()) {
        for (var f in m.listSync().whereType<File>()) {
          final match = RegExp(r'log_(\d+)\.txt$').firstMatch(f.path);
          if (match == null) continue;
          final day = int.parse(match.group(1)!);
          final month = int.parse(m.path.split('/').last);
          final year = int.parse(y.path.split('/').last);
          final dt = DateTime(year, month, day);
          if (now.difference(dt).inDays > clearDays) {
            try {
              await f.delete();
            } catch (_) {}
          }
        }
      }
    }
  }
}

Future<void> migrateOldLogsIfNeeded() async {
  final docDir = await getApplicationDocumentsDirectory();
  final oldFile = File('${docDir.path}/studyclock/StudyClockLogs.txt');
  final flagFile = File('${docDir.path}/studyclock/logs_migrated.flag');
  final failFile = File('${docDir.path}/studyclock/migration_failed_lines.txt');

  if (oldFile.existsSync() && !flagFile.existsSync()) {
    final lines = await oldFile.readAsLines();
    List<String> failed = [];
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      DateTime? dt;
      // 1. 尝试标准格式
      try {
        var timePart = line.substring(0, 19);
        dt = DateTime.tryParse(timePart.replaceAll('/', '-'));
      } catch (_) {}
      if (dt == null) {
        final match = RegExp(
          r'\d{4}[-/]\d{2}[-/]\d{2} \d{2}:\d{2}:\d{2}',
        ).firstMatch(line);
        if (match != null) {
          try {
            dt = DateTime.tryParse(match.group(0)!.replaceAll('/', '-'));
          } catch (_) {}
        }
      }
      if (dt != null) {
        await LogService().writeLog(line, dt);
      } else {
        failed.add(line);
      }
    }
    if (failed.isNotEmpty) await failFile.writeAsString(failed.join('\n'));
    await flagFile.writeAsString('migrated!');
  }
}
