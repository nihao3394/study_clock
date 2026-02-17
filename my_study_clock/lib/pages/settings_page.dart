import 'package:flutter/material.dart';
import '../services/settings_service.dart';
import '../models/setting.dart';

class SettingsPage extends StatefulWidget {
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool experimentMode = false;
  int logCleanDays = 14;
  String logDefaultShow = "Y/M";
  AppThemeData currentTheme = AppThemeData.defaults[0];

  @override
  void initState() {
    super.initState();
    final service = SettingsService();
    experimentMode = service.experimentMode;
    logCleanDays = service.logCleanDays;
    logDefaultShow = service.logDefaultShow;
    // null 安全赋值
    currentTheme = service.themeNotifier.value ?? AppThemeData.defaults[0];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("设置")),
      body: ListView(
        children: [
          SwitchListTile(
            title: Text("实验模式"),
            value: experimentMode,
            onChanged: (v) {
              setState(() {
                experimentMode = v;
              });
              SettingsService().saveExperimentMode(v);
            },
          ),
          ListTile(
            title: Text("日志清理周期/天"),
            trailing: DropdownButton<int>(
              value: logCleanDays,
              items: [7, 14, 30, 90]
                  .map(
                    (v) => DropdownMenuItem<int>(value: v, child: Text("$v")),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null)
                  setState(() {
                    logCleanDays = v;
                  });
              },
            ),
          ),
          ListTile(
            title: Text("日志展示模式"),
            trailing: DropdownButton<String>(
              value: logDefaultShow,
              items: [
                "Y",
                "Y/M",
                "Y/M/D",
              ].map((s) => DropdownMenuItem(child: Text(s), value: s)).toList(),
              onChanged: (v) {
                if (v != null) setState(() => logDefaultShow = v);
              },
            ),
          ),
          ListTile(
            title: Text("主题设置"),
            subtitle: Row(
              children: [
                ...AppThemeData.defaults.map(
                  (t) => Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          currentTheme = t;
                        });
                        SettingsService().saveTheme(t);
                      },
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [t.background, t.foreground],
                          ),
                          border: currentTheme.name == t.name
                              ? Border.all(width: 2, color: Colors.white)
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
