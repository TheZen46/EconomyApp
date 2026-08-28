import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class HoverScale extends StatefulWidget {
  final Widget child;
  final double scale;
  final Duration duration;

  const HoverScale({
    super.key,
    required this.child,
    this.scale = 1.02,
    this.duration = const Duration(milliseconds: 200),
  });

  @override
  State<HoverScale> createState() => _HoverScaleState();
}

class _HoverScaleState extends State<HoverScale> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: widget.child.animate(target: _isHovered ? 1 : 0)
        .scaleXY(
          begin: 1,
          end: widget.scale,
          duration: widget.duration,
          curve: Curves.easeOutCubic,
        ),
    );
  }
}
