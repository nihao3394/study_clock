import 'dart:async';

class SyncService {
  Timer? _timer;
  void startPolling(Function onChange) {
    _timer = Timer.periodic(Duration(minutes: 1), (_) async {
      bool changed = await checkFilesChanged();
      if (changed) onChange();
    });
  }

  Future<bool> checkFilesChanged() async {
    // 检查文件md5或mTime变化，略
    return false;
  }

  void dispose() => _timer?.cancel();
}
