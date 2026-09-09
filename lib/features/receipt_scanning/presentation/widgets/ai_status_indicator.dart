import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/receipt_provider.dart';
import '../../../settings/presentation/providers/llm_provider.dart';

class AIStatusIndicator extends ConsumerWidget {
  const AIStatusIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updateState = ref.watch(modelUpdateServiceProvider);
    final isVlmReady = ref.watch(isVlmReadyProvider);
    final isLlmLoaded = ref.watch(isLlmLoadedProvider);
    final isDownloading = ref.watch(isModelDownloadingProvider);
    final downloadProgress = ref.watch(modelDownloadProgressProvider);

    Color statusColor;
    String statusText;
    String engineTag;
    bool isAnimating = false;

    if (updateState.error != null) {
      statusColor = AppColors.destructive;
      statusText = 'AI Core Error';
      engineTag = 'ERR';
    } else if (isDownloading || updateState.isDownloading) {
      statusColor = const Color(0xFFF59E0B); // Amber
      final pct = ((isDownloading ? downloadProgress : updateState.progress) * 100).toInt();
      statusText = 'Downloading OTA $pct%';
      engineTag = 'SYNC';
      isAnimating = true;
    } else if (updateState.isChecking) {
      statusColor = const Color(0xFF0891B2);
      statusText = 'Checking Updates...';
      engineTag = 'OTA';
      isAnimating = true;
    } else if (isVlmReady) {
      statusColor = const Color(0xFF10B981); // Emerald
      statusText = 'VLM Engine (Qwen2-VL)';
      engineTag = '4-BIT';
    } else if (isLlmLoaded) {
      statusColor = const Color(0xFF0891B2); // Cyan
      statusText = 'OCR Engine (ML Kit)';
      engineTag = 'HYBRID';
    } else {
      statusColor = Colors.grey;
      statusText = 'AI Idle / Offline';
      engineTag = 'OFF';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withOpacity(0.35)),
        boxShadow: [
          BoxShadow(
            color: statusColor.withOpacity(0.12),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: statusColor.withOpacity(0.6),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          ).animate(target: isAnimating ? 1 : 0, onPlay: (c) => isAnimating ? c.repeat(reverse: true) : null)
           .scale(begin: const Offset(0.8, 0.8), end: const Offset(1.3, 1.3), duration: 800.ms),
          const SizedBox(width: 6),
          Text(
            statusText,
            style: GoogleFonts.spaceGrotesk(
              color: AppTheme.textDim,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              engineTag,
              style: GoogleFonts.jetBrainsMono(
                color: statusColor,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
