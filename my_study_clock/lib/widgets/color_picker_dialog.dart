import 'package:flutter/material.dart';
// 可使用 flutter_colorpicker 包
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

class ColorPickerDialog extends StatelessWidget {
  final Color initialColor;
  final ValueChanged<Color> onColorChanged;

  ColorPickerDialog({required this.initialColor, required this.onColorChanged});

  @override
  Widget build(BuildContext context) {
    Color sel = initialColor;
    return Dialog(
      child: Container(
        padding: EdgeInsets.all(16),
        height: 370,
        child: Column(
          children: [
            ColorPicker(
              pickerColor: initialColor,
              onColorChanged: (c) => sel = c,
              colorPickerWidth: 300,
              pickerAreaHeightPercent: 0.4,
            ),
            SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text("取消"),
                ),
                TextButton(
                  onPressed: () => onColorChanged(sel),
                  child: Text("确定"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
