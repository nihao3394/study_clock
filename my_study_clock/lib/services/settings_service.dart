import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/setting.dart';

class SettingsService {
  static final _instance = SettingsService._internal();
  factory SettingsService() => _instance;

  final ValueNotifier<AppThemeData?> themeNotifier =
      ValueNotifier<AppThemeData?>(null);
  bool experimentMode = false;
  int logCleanDays = 14;
  String logDefaultShow = "Y/M";
  // ...其余设置...

  SettingsService._internal();

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final themeJson = prefs.getString('theme');
    if (themeJson != null && themeJson.isNotEmpty && themeJson != '{}') {
      themeNotifier.value = AppThemeData.fromJson(json.decode(themeJson));
    } else {
      themeNotifier.value = AppThemeData.defaults[0]; // 默认主题
    }
    experimentMode = prefs.getBool('experimentMode') ?? false;
    logCleanDays = prefs.getInt('logCleanDays') ?? 14;
    logDefaultShow = prefs.getString('logDefaultShow') ?? "Y/M";
    // ...
  }

  Future<void> saveTheme(AppThemeData theme) async {
    final prefs = await SharedPreferences.getInstance();
    themeNotifier.value = theme;
    await prefs.setString('theme', json.encode(theme.toJson()));
  }

  Future<void> saveExperimentMode(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    experimentMode = v;
    await prefs.setBool('experimentMode', v);
  }

  // 其它设置同理
}
