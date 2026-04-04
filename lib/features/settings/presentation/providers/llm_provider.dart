import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/services/llm_service.dart';

// Singleton Service
final llmServiceProvider = Provider<LLMService>((ref) {
  return LLMService();
});

// State for Model Manager UI
final modelDownloadProgressProvider = StateProvider<double>((ref) => 0.0);
final isModelDownloadingProvider = StateProvider<bool>((ref) => false);
final isLlmLoadedProvider = StateProvider<bool>((ref) => false);
