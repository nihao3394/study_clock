import 'package:flutter/material.dart';

class StudyGoal {
  final String content;
  bool isCompleted;

  StudyGoal({required this.content, this.isCompleted = false});

  Map<String, dynamic> toJson() => {
    'content': content,
    'isCompleted': isCompleted,
  };

  factory StudyGoal.fromJson(Map<String, dynamic> json) {
    return StudyGoal(
      content: json['content'] as String,
      isCompleted: json['isCompleted'] as bool? ?? false,
    );
  }
}

class Subject {
  final String name;
  final int priority;
  final List<StudyGoal> goals;

  Subject({required this.name, this.priority = 0, this.goals = const []});

  Map<String, dynamic> toJson() => {
    'name': name,
    'priority': priority,
    'goals': goals.map((e) => e.toJson()).toList(),
  };

  factory Subject.fromJson(Map<String, dynamic> json) {
    return Subject(
      name: json['name'] as String,
      priority: json['priority'] as int? ?? 0,
      goals:
          (json['goals'] as List<dynamic>?)
              ?.map((e) => StudyGoal.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  double get completionRate {
    if (goals.isEmpty) return 0.0;
    final completedCount = goals.where((goal) => goal.isCompleted).length;
    return (completedCount / goals.length) * 100;
  }

  Color get progressColor {
    final rate = completionRate;
    if (rate <= 20) return const Color(0xFF8BC34A);
    if (rate <= 40) return const Color(0xFF03A9F4);
    if (rate <= 60) return const Color(0xFF9C27B0);
    if (rate <= 80) return const Color(0xFFFF9800);
    return const Color(0xFFF44336);
  }
}

class SubjectStat {
  final String subjectName;
  int totalSeconds;
  SubjectStat({required this.subjectName, this.totalSeconds = 0});

  Map<String, dynamic> toJson() => {
    'subjectName': subjectName,
    'totalSeconds': totalSeconds,
  };

  factory SubjectStat.fromJson(Map<String, dynamic> json) {
    return SubjectStat(
      subjectName: json['subjectName'] as String,
      totalSeconds: json['totalSeconds'] as int? ?? 0,
    );
  }
}
