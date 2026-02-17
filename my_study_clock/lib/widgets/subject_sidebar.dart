import 'package:flutter/material.dart';
import '../models/subject.dart';

class SubjectSidebar extends StatelessWidget {
  final List<Subject> subjects;
  final Subject? selected;
  final void Function(int, int) onReorder;
  final void Function(Subject) onEdit;
  final void Function(Subject) onSelect;

  const SubjectSidebar({
    required this.subjects,
    required this.selected,
    required this.onReorder,
    required this.onEdit,
    required this.onSelect,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return ReorderableListView(
      onReorder: onReorder,
      children: [
        for (int i = 0; i < subjects.length; i++)
          ListTile(
            key: ValueKey(subjects[i].name),
            title: Text(
              subjects[i].name,
              style: TextStyle(
                color: selected == subjects[i] ? Colors.blue : Colors.white,
              ),
            ),
            trailing: IconButton(
              icon: Icon(Icons.settings),
              onPressed: () => onEdit(subjects[i]),
            ),
            onTap: () => onSelect(subjects[i]),
          ),
      ],
    );
  }
}
