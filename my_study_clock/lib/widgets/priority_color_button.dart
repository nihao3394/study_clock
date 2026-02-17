import 'package:flutter/material.dart';

class PriorityColorButton extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final double size;
  final bool showCheckmark;
  const PriorityColorButton({
    required this.color,
    required this.selected,
    required this.onTap,
    this.size = 24,
    this.showCheckmark = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: selected ? Border.all(color: Colors.white, width: 2) : null,
        ),
        child: selected && showCheckmark
            ? Center(
                child: Icon(Icons.check, color: Colors.white, size: size * 0.6),
              )
            : null,
      ),
    );
  }
}
