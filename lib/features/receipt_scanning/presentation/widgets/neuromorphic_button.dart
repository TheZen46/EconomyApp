import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_theme.dart';

class NeuromorphicScanButton extends StatefulWidget {
  final VoidCallback onPressed;
  final bool isProcessing;

  const NeuromorphicScanButton({
    super.key,
    required this.onPressed,
    this.isProcessing = false,
  });

  @override
  State<NeuromorphicScanButton> createState() => _NeuromorphicScanButtonState();
}

class _NeuromorphicScanButtonState extends State<NeuromorphicScanButton>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late AnimationController _breathingController;
  late Animation<double> _breathingAnimation;

  @override
  void initState() {
    super.initState();
    // Press animation
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 150));
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    // Breathing animation (looping)
    _breathingController = AnimationController(
      vsync: this, 
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    
    _breathingAnimation = Tween<double>(begin: 0.0, end: 10.0).animate(
      CurvedAnimation(parent: _breathingController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _breathingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapUp: (_) {
        _controller.reverse();
        if (!widget.isProcessing) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
             // Use minimal haptic for "click" feel
             await HapticFeedback.selectionClick(); 
          });
          widget.onPressed();
        }
      },
      onTapDown: (_) {
        _controller.forward();
        HapticFeedback.lightImpact(); // Feedback on touch start
      },
      onTapCancel: () => _controller.reverse(),
      child: AnimatedBuilder(
        animation: Listenable.merge([_scaleAnimation, _breathingAnimation]),
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.surface,
                boxShadow: [
                  // Light source top-left
                  BoxShadow(
                    color: Colors.white.withOpacity(0.05),
                    offset: const Offset(-10, -10),
                    blurRadius: 20,
                  ),
                  // Shadow bottom-right
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    offset: const Offset(10, 10),
                    blurRadius: 20,
                  ),
                  // Breathing Glow (only when idle)
                  if (!widget.isProcessing)
                    BoxShadow(
                      color: AppTheme.primary.withOpacity(0.2),
                      blurRadius: 20 + _breathingAnimation.value,
                      spreadRadius: _breathingAnimation.value,
                    ),
                ],
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppTheme.surface,
                    AppTheme.background,
                  ],
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Icon / Loading
                  Center(
                    child: widget.isProcessing
                        ? const CircularProgressIndicator(color: AppTheme.primary)
                        : Icon(
                            Icons.camera_rounded,
                            size: 80,
                            color: AppTheme.primary,
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
