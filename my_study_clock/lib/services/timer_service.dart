import 'dart:async';

class TimerService {
  DateTime? _start;
  int _accumulated = 0;
  bool get isRunning => _start != null;
  Function(int)? onTick;
  Timer? _timer;
  int get totalSeconds =>
      _accumulated +
      (isRunning ? DateTime.now().difference(_start!).inSeconds : 0);

  void start() {
    _start ??= DateTime.now();
    _timer ??= Timer.periodic(
      Duration(seconds: 1),
      (_) => onTick?.call(totalSeconds),
    );
  }

  void pause() {
    if (isRunning) {
      _accumulated += DateTime.now().difference(_start!).inSeconds;
      _start = null;
      _timer?.cancel();
      _timer = null;
    }
  }

  void resume() {
    if (!isRunning) start();
  }

  void stopSave(Function(int) writeLog) {
    int secs = totalSeconds;
    _accumulated = 0;
    _start = null;
    _timer?.cancel();
    _timer = null;
    writeLog(secs);
  }

  int saveOnCrash() {
    int secs = totalSeconds;
    _accumulated = 0;
    _start = null;
    _timer?.cancel();
    _timer = null;
    return secs > 0 ? secs : 0;
  }
}
