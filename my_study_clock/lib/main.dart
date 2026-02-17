/// 入口，负责日志迁移/初始化，runApp(App)
import 'package:flutter/material.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(StudyClockApp());
}