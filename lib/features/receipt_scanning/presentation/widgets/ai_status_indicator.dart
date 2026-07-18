import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/receipt_provider.dart';

class AIStatusIndicator extends ConsumerWidget {
  const AIStatusIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updateState = ref.watch(modelUpdateServiceProvider);
    
    // Determine Status
    // Green: Idle (assuming download done if not checking/downloading/error)
    // Yellow: Checking or Downloading
    // Red: Error
    
    Color statusColor;
    String statusText;
    bool isAnimating = false;

    if (updateState.error != null) {
      statusColor = AppTheme.error;
      statusText = 'AI Error';
    } else if (updateState.isDownloading) {
      statusColor = Colors.amber;
      statusText = 'Downloading ${(updateState.progress * 100).toInt()}%';
      isAnimating = true;
    } else if (updateState.isChecking) {
      statusColor = Colors.amber;
      statusText = 'Checking...';
      isAnimating = true;
    } else {
      statusColor = AppTheme.secondary; // Green
      statusText = 'AI Ready';
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.surface.withOpacity(0.8),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
            boxShadow: [
               BoxShadow(
                 color: Colors.black.withOpacity(0.2),
                 blurRadius: 10,
               )
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: statusColor.withOpacity(0.5),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          ).animate(target: isAnimating ? 1 : 0)
           .fade(duration: 500.ms)
           .then()
           .fade(delay: 200.ms, begin: 1, end: 0.5), // Pulse effect if animating
          const SizedBox(width: 12),
          Text(
            statusText,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    )));
  }
}
