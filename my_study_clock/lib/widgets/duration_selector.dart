import 'package:flutter/material.dart';

class DurationSelector extends StatelessWidget {
  final int selectedMinutes;
  final ValueChanged<int> onChanged;
  const DurationSelector({
    required this.selectedMinutes,
    required this.onChanged,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ...[20, 40, 60].map(
          (min) => ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: selectedMinutes == min
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey[800],
              foregroundColor: Colors.white,
            ),
            onPressed: () => onChanged(min),
            child: Text('$min 分钟'),
          ),
        ),
        SizedBox(width: 10),
        // 自定义选择
        SizedBox(
          width: 80,
          child: TextField(
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: '自定义',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (v) {
              final min = int.tryParse(v);
              if (min != null && min > 0 && min <= 120) onChanged(min);
            },
          ),
        ),
      ],
    );
  }
}
