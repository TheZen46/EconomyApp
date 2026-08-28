import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_theme.dart';

/// Immersive, kinetic progress indicator rendering an animated energy beam,
/// glowing particle pulses, and orbital geometric accents.
class KineticSyncProgressBar extends StatefulWidget {
  final double progress; // 0.0 to 1.0
  final bool isDark;
  final String? speedLabel;
  final double height;

  const KineticSyncProgressBar({
    super.key,
    required this.progress,
    required this.isDark,
    this.speedLabel,
    this.height = 14.0,
  });

  @override
  State<KineticSyncProgressBar> createState() => _KineticSyncProgressBarState();
}

class _KineticSyncProgressBarState extends State<KineticSyncProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Top Telemetry Readout ───────────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.accent.withOpacity(0.6),
                        blurRadius: 6,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'SYNC ENGINE',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    color: widget.isDark ? AppColors.darkFgDim : AppColors.lightMuted,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                if (widget.speedLabel != null) ...[
                  Text(
                    widget.speedLabel!,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Text(
                  '${(widget.progress * 100).toStringAsFixed(0)}%',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: widget.isDark ? AppColors.darkFg : AppColors.lightFg,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ── Custom Kinetic Painted Track ───────────────────────────────────
        AnimatedBuilder(
          animation: _animController,
          builder: (context, _) {
            return CustomPaint(
              size: Size(double.infinity, widget.height),
              painter: _KineticBarPainter(
                progress: widget.progress.clamp(0.0, 1.0),
                animationValue: _animController.value,
                isDark: widget.isDark,
              ),
            );
          },
        ),
      ],
    );
  }
}

class _KineticBarPainter extends CustomPainter {
  final double progress;
  final double animationValue;
  final bool isDark;

  _KineticBarPainter({
    required this.progress,
    required this.animationValue,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final trackRadius = Radius.circular(size.height / 2);
    final trackRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      trackRadius,
    );

    // 1. Draw Track Background
    final bgPaint = Paint()
      ..color = isDark
          ? Colors.white.withOpacity(0.06)
          : Colors.black.withOpacity(0.05)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(trackRRect, bgPaint);

    // 2. Draw Track Border
    final borderPaint = Paint()
      ..color = isDark
          ? Colors.white.withOpacity(0.12)
          : Colors.black.withOpacity(0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRRect(trackRRect, borderPaint);

    if (progress <= 0.001) return;

    final fillWidth = size.width * progress;
    final fillRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, fillWidth, size.height),
      trackRadius,
    );

    canvas.save();
    canvas.clipRRect(fillRRect);

    // 3. Draw Flowing Gradient Energy Beam
    final gradient = LinearGradient(
      begin: Alignment(-1.0 + (animationValue * 2.0), 0.0),
      end: Alignment(1.0 + (animationValue * 2.0), 0.0),
      colors: const [
        Color(0xFF001F70),
        Color(0xFF002FA7),
        Color(0xFF0080FF),
        Color(0xFF00E5FF),
        Color(0xFF002FA7),
      ],
      stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
    );

    final fillPaint = Paint()
      ..shader = gradient.createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    canvas.drawRect(Rect.fromLTWH(0, 0, fillWidth, size.height), fillPaint);

    // 4. Draw Shimmer Sweep Highlight
    final shimmerX = (animationValue * (size.width + 100)) - 50;
    final shimmerPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.white.withOpacity(0.0),
          Colors.white.withOpacity(0.4),
          Colors.white.withOpacity(0.0),
        ],
      ).createShader(Rect.fromLTWH(shimmerX, 0, 60, size.height))
      ..style = PaintingStyle.fill;

    canvas.drawRect(Rect.fromLTWH(shimmerX, 0, 60, size.height), shimmerPaint);
    canvas.restore();

    // 5. Draw Leading Edge Glow Orb & Kinetic Orbit
    if (fillWidth > 6) {
      final headX = fillWidth;
      final headY = size.height / 2;

      // Glow Halo
      final glowPaint = Paint()
        ..color = const Color(0xFF00E5FF).withOpacity(0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawCircle(Offset(headX, headY), 5, glowPaint);

      // Core Solid Center
      final corePaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(headX, headY), 2.5, corePaint);

      // Micro Geometric Orbit Accent
      final orbitAngle = animationValue * 2 * math.pi;
      final orbitX = headX + (math.cos(orbitAngle) * 7);
      final orbitY = headY + (math.sin(orbitAngle) * 4);
      final orbitPaint = Paint()
        ..color = const Color(0xFF00E5FF).withOpacity(0.8)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(orbitX, orbitY), 1.2, orbitPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _KineticBarPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.animationValue != animationValue ||
        oldDelegate.isDark != isDark;
  }
}
