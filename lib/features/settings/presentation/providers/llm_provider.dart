import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/services/llm_service.dart';
import '../../../../core/services/telemetry_service.dart';

/// Singleton instance of the legacy on-device [LLMService].
///
/// **Lifetime:** App-scoped singleton.
/// **Dependencies:** None.
final llmServiceProvider = Provider<LLMService>((ref) {
  return LLMService();
});

/// Singleton instance of the next-generation native [VlmEngineService] for on-device multimodal OCR.
///
/// **Lifetime:** App-scoped singleton.
/// **Dependencies:** `telemetryServiceProvider`.
final vlmEngineServiceProvider = Provider<VlmEngineService>((ref) {
  final telemetry = ref.watch(telemetryServiceProvider);
  return VlmEngineService(telemetryService: telemetry);
});

/// Service managing anonymized user-contributed dataset samples for OCR model fine-tuning.
///
/// **Lifetime:** App-scoped singleton.
/// **Dependencies:** None.
final datasetContributionServiceProvider = Provider<DatasetContributionService>((ref) {
  return DatasetContributionService();
});

// ── State for Model Manager UI ──────────────────────────────────────────────

/// Tracks download progress fraction `[0.0, 1.0]` for on-device AI weights.
///
/// **Lifetime:** Transient UI state.
final modelDownloadProgressProvider = StateProvider<double>((ref) => 0.0);

/// Human-readable download transfer speed string (e.g. `12.4 MB/s`).
///
/// **Lifetime:** Transient UI state.
final modelDownloadSpeedProvider = StateProvider<String>((ref) => '');

/// Human-readable estimated time remaining for model weights download (e.g. `01:45`).
///
/// **Lifetime:** Transient UI state.
final modelDownloadEtaProvider = StateProvider<String>((ref) => '');

/// Indicates whether downloaded model weights are undergoing SHA-256 cryptographic verification.
///
/// **Lifetime:** Transient UI state.
final isModelVerifyingProvider = StateProvider<bool>((ref) => false);

/// Indicates whether an on-device model weights file is currently downloading.
///
/// **Lifetime:** Transient UI state.
final isModelDownloadingProvider = StateProvider<bool>((ref) => false);

/// Whether the legacy on-device LLM model is loaded in memory and ready for inference.
///
/// **Lifetime:** App-scoped mutable state.
final isLlmLoadedProvider = StateProvider<bool>((ref) => false);

/// Whether the native VLM engine is initialized with loaded weights and ready for vision inference.
///
/// **Lifetime:** App-scoped mutable state.
final isVlmReadyProvider = StateProvider<bool>((ref) => false);

// ── Live Token Stream & Terminal State for Scan/Review HUD ──────────────────

/// Streaming buffer of tokens emitted by the native VLM during live receipt inference.
///
/// **Lifetime:** Transient UI state.
final vlmLiveTokensProvider = StateProvider<String>((ref) => '');

/// Current execution phase name of the on-device inference pipeline (e.g. `IMAGE_PREPROCESS`, `DECODE`, `IDLE`).
///
/// **Lifetime:** Transient UI state.
final vlmActiveInferenceStepProvider = StateProvider<String>((ref) => 'IDLE');

