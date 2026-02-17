import 'package:flutter/material.dart';

class AppThemeData {
  final String name;
  final Color background, foreground;
  final String? bgImagePath;
  final bool blurBg;
  // 可扩展

  const AppThemeData(
    this.name,
    this.background,
    this.foreground, {
    this.bgImagePath,
    this.blurBg = false,
  });

  // 默认主题
  static const List<AppThemeData> defaults = [
    AppThemeData('蓝紫', Color(0xFF161625), Color(0xFF6A88FF)),
    AppThemeData('粉白', Color(0xFFFFCAD4), Color(0xFFF9F2ED)),
    AppThemeData('墨绿', Color(0xFF053B06), Color(0xFF79AC78)),
    AppThemeData('深蓝', Color(0xFF08143A), Color(0xFF35C2FF)),
  ];

  ThemeData toThemeData() => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme(
      brightness: Brightness.dark,
      primary: foreground,
      onPrimary: Colors.white,
      secondary: foreground,
      onSecondary: Colors.white,
      error: Colors.red,
      onError: Colors.white,
      background: background,
      onBackground: Colors.white70,
      surface: background,
      onSurface: foreground,
    ),
    scaffoldBackgroundColor: background,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'background': background.value,
    'foreground': foreground.value,
    'bgImagePath': bgImagePath,
    'blurBg': blurBg,
  };
  static AppThemeData fromJson(Map<String, dynamic> json) => AppThemeData(
    json['name'],
    Color(json['background']),
    Color(json['foreground']),
    bgImagePath: json['bgImagePath'],
    blurBg: json['blurBg'] ?? false,
  );
}
