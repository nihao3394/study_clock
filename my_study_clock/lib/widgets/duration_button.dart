import 'package:flutter/material.dart';

class DurationButton extends StatelessWidget {
  final int minutes;
  final void Function(int) onTap;
  final bool isSelected;
  const DurationButton({
    required this.minutes,
    required this.onTap,
    required this.isSelected,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () => onTap(minutes),
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected
            ? Theme.of(context).colorScheme.primary
            : const Color(0xFF3A3A5A),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text('$minutes 分钟', style: const TextStyle(color: Colors.white)),
    );
  }
}
