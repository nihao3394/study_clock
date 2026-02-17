/// 多级目标节点，兼容原String目标单层格式
class GoalNode {
  String content;
  bool isCompleted;
  int level; // 用于树结构，最多4
  List<GoalNode> children;

  GoalNode({
    required this.content,
    this.isCompleted = false,
    this.level = 0,
    this.children = const [],
  });

  /// 解析多级文本，每一行为一节点，前导 '-' 表示层级，最多四级
  static List<GoalNode> parse(String text) {
    final lines = text.split('\n').where((l) => l.trim().isNotEmpty).toList();
    List<GoalNode> roots = [], stack = [];
    for (final line in lines) {
      final hyph = RegExp(r'^(-{1,4})\s*').firstMatch(line);
      int depth = hyph?.group(1)?.length ?? 0;
      depth = depth > 4 ? 4 : depth;
      var node = GoalNode(
        content: line.replaceFirst(RegExp(r'^-+\s*'), ''),
        level: depth,
      );
      if (depth == 0) {
        roots.add(node);
        stack = [node];
      } else {
        while (stack.isNotEmpty && stack.last.level >= depth)
          stack.removeLast();
        if (stack.isNotEmpty) stack.last.children.add(node);
        stack.add(node);
      }
    }
    return roots;
  }

  Map<String, dynamic> toJson() => {
    'content': content,
    'isCompleted': isCompleted,
    'level': level,
    'children': children.map((c) => c.toJson()).toList(),
  };

  static GoalNode fromJson(Map<String, dynamic> json) => GoalNode(
    content: json['content'],
    isCompleted: json['isCompleted'] ?? false,
    level: json['level'] ?? 0,
    children: (json['children'] as List<dynamic>? ?? [])
        .map((c) => GoalNode.fromJson(c))
        .toList(),
  );
}
