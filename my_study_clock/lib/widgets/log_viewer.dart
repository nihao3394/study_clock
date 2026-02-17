import 'package:flutter/material.dart';

class LogViewer extends StatelessWidget {
  final List<String> logLines;
  LogViewer({required this.logLines});

  @override
  Widget build(BuildContext context) {
    if (logLines.isEmpty) {
      return Center(
        child: Text("暂无日志", style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.builder(
      itemCount: logLines.length,
      itemBuilder: (_, i) =>
          ListTile(title: Text(logLines[i], style: TextStyle(fontSize: 14))),
    );
  }
}
