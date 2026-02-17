import 'goal.dart';

class Subject {
  String name;
  int priority;
  List<GoalNode> goals;
  int order;
  List<String> experimentApps;

  Subject({
    required this.name,
    this.priority = 0,
    this.goals = const [],
    this.order = 0,
    this.experimentApps = const [],
  });

  factory Subject.fromJson(Map<String, dynamic> json) {
    // 向后兼容：若goals为list<string>自动转一级树，原goals全为一级目标
    List<GoalNode> gs;
    if (json['goals'] != null && json['goals'].isNotEmpty) {
      if (json['goals'].first is String) {
        gs = (json['goals'] as List)
            .map((s) => GoalNode(content: s as String))
            .toList();
      } else {
        gs = (json['goals'] as List).map((j) => GoalNode.fromJson(j)).toList();
      }
    } else {
      gs = [];
    }
    return Subject(
      name: json['name'],
      priority: json['priority'] ?? 0,
      goals: gs,
      order: json['order'] ?? 0,
      experimentApps: (json['experimentApps'] as List?)?.cast<String>() ?? [],
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'priority': priority,
    'goals': goals.map((g) => g.toJson()).toList(),
    'order': order,
    'experimentApps': experimentApps,
  };
}
