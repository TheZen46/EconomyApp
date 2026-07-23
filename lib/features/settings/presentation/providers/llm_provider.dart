// ignore_for_file: deprecated_member_use, deprecated_member_use_from_same_package, unused_local_variable, unnecessary_underscores, invalid_annotation_target, unused_element, non_constant_identifier_names, use_build_context_synchronously
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
