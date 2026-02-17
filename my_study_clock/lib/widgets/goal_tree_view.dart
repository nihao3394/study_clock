import 'package:flutter/material.dart';
import '../models/goal.dart';

/// 多级目标显示，为每级缩进
class GoalTreeView extends StatelessWidget {
  final List<GoalNode> nodes;
  final Function(GoalNode) onToggle;
  GoalTreeView({required this.nodes, required this.onToggle});

  Widget buildNode(GoalNode node, int depth) {
    return Padding(
      padding: EdgeInsets.only(left: depth * 24.0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => onToggle(node),
            child: Icon(
              node.isCompleted
                  ? Icons.check_box
                  : Icons.check_box_outline_blank,
              color: node.isCompleted ? Colors.green : Colors.grey,
            ),
          ),
          SizedBox(width: 6),
          Expanded(
            child: Text(
              node.content,
              style: TextStyle(
                decoration: node.isCompleted
                    ? TextDecoration.lineThrough
                    : TextDecoration.none,
                color: node.isCompleted ? Colors.grey : Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> buildRecursive(List<GoalNode> list, int lvl) {
    List<Widget> res = [];
    for (final n in list) {
      res.add(buildNode(n, lvl));
      res.addAll(buildRecursive(n.children, lvl + 1));
    }
    return res;
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: buildRecursive(nodes, 0));
  }
}
