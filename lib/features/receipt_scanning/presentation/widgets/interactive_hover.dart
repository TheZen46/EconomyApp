import 'package:flutter/material.dart';

class HoverCardWrapper extends StatefulWidget {
  final Widget child;
  final bool isDark;
  const HoverCardWrapper({super.key, required this.child, required this.isDark});

  @override
  State<HoverCardWrapper> createState() => _HoverCardWrapperState();
}

class _HoverCardWrapperState extends State<HoverCardWrapper> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border.all(
            color: _isHovered 
              ? colorScheme.outlineVariant
              : colorScheme.outline,
            width: _isHovered ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: _isHovered ? [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, 10),
            )
          ] : [],
        ),
        child: widget.child,
      ),
    );
  }
}

class InteractiveHover extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const InteractiveHover({super.key, required this.child, this.onTap});
  
  @override
  State<InteractiveHover> createState() => _InteractiveHoverState();
}

class _InteractiveHoverState extends State<InteractiveHover> {
  bool _isHovered = false;
  bool _isPressed = false;
  
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isPressed ? 0.95 : (_isHovered ? 1.05 : 1.0),
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}
