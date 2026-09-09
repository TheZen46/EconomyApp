import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/services/llm_service.dart';

// Singleton Services
final llmServiceProvider = Provider<LLMService>((ref) {
  return LLMService();
});

final vlmEngineServiceProvider = Provider<VlmEngineService>((ref) {
  return VlmEngineService();
});

final datasetContributionServiceProvider = Provider<DatasetContributionService>((ref) {
  return DatasetContributionService();
});

// State for Model Manager UI
final modelDownloadProgressProvider = StateProvider<double>((ref) => 0.0);
final modelDownloadSpeedProvider = StateProvider<String>((ref) => '');
final modelDownloadEtaProvider = StateProvider<String>((ref) => '');
final isModelVerifyingProvider = StateProvider<bool>((ref) => false);
final isModelDownloadingProvider = StateProvider<bool>((ref) => false);
final isLlmLoadedProvider = StateProvider<bool>((ref) => false);
final isVlmReadyProvider = StateProvider<bool>((ref) => false);

// Live Token Stream & Terminal State for Scan/Review HUD
final vlmLiveTokensProvider = StateProvider<String>((ref) => '');
final vlmActiveInferenceStepProvider = StateProvider<String>((ref) => 'IDLE');

