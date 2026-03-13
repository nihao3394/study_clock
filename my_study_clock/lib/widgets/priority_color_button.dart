import 'package:flutter/material.dart';

class PriorityColorButton extends StatefulWidget {
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;
  final double size;
  final bool showCheckmark;

  const PriorityColorButton({
    required this.color,
    required this.isSelected,
    required this.onTap,
    this.size = 24,
    this.showCheckmark = true,
    super.key,
  });

  @override
  State<PriorityColorButton> createState() => _PriorityColorButtonState();
}

class _PriorityColorButtonState extends State<PriorityColorButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _scaleAnim;
  late Animation<Color?> _colorAnim;
  bool _hover = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 1.18).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
    _colorAnim =
        ColorTween(
          begin: widget.color,
          end: HSLColor.fromColor(widget.color)
              .withLightness(
                (HSLColor.fromColor(widget.color).lightness + 0.28).clamp(
                  0.0,
                  1.0,
                ),
              )
              .toColor(),
        ).animate(
          CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
        );
  }

  @override
  void didUpdateWidget(covariant PriorityColorButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.color != widget.color) {
      _colorAnim =
          ColorTween(
            begin: widget.color,
            end: HSLColor.fromColor(widget.color)
                .withLightness(
                  (HSLColor.fromColor(widget.color).lightness + 0.28).clamp(
                    0.0,
                    1.0,
                  ),
                )
                .toColor(),
          ).animate(
            CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
          );
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _onEnter(PointerEvent _) {
    setState(() => _hover = true);
    _animController.forward();
  }

  void _onExit(PointerEvent _) {
    setState(() => _hover = false);
    _animController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: _onEnter,
      onExit: _onExit,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: Listenable.merge([_scaleAnim, _animController]),
          builder: (ctx, child) {
            final scale = widget.isSelected
                ? _scaleAnim.value
                : (_hover ? _scaleAnim.value : 1.0);
            final color = _colorAnim.value ?? widget.color;
            return Transform.scale(
              scale: scale,
              child: Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  border: widget.isSelected
                      ? Border.all(color: Colors.white, width: 2)
                      : null,
                  boxShadow: widget.isSelected || _hover
                      ? [
                          BoxShadow(
                            color: color.withOpacity(0.45),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                child: widget.isSelected && widget.showCheckmark
                    ? const Icon(Icons.check, color: Colors.white, size: 16)
                    : null,
              ),
            );
          },
        ),
      ),
    );
  }
}
