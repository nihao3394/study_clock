import 'package:flutter/material.dart';

class MainControls extends StatelessWidget {
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onEnd;
  final bool isRunning;
  const MainControls({
    required this.onStart,
    required this.onPause,
    required this.onEnd,
    required this.isRunning,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ElevatedButton.icon(
          icon: Icon(Icons.play_arrow),
          label: Text('开始'),
          onPressed: isRunning ? null : onStart,
        ),
        SizedBox(width: 12),
        ElevatedButton.icon(
          icon: Icon(Icons.pause),
          label: Text('暂停'),
          onPressed: isRunning ? onPause : null,
        ),
        SizedBox(width: 12),
        ElevatedButton.icon(
          icon: Icon(Icons.stop),
          label: Text('结束记录'),
          onPressed: isRunning ? onEnd : null,
        ),
      ],
    );
  }
}
