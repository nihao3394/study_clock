import 'package:flutter/material.dart';

class NoteInput extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  NoteInput({required this.controller, this.enabled = true, super.key});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      decoration: InputDecoration(
        labelText: '添加备注（可选）',
        prefixIcon: Icon(Icons.note_outlined, color: Colors.white),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        filled: true,
        fillColor: Colors.grey[900],
      ),
      style: TextStyle(color: Colors.white),
    );
  }
}
