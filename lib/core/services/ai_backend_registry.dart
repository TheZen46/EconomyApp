import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'ai_service.dart';

/// Privacy boundary classification for an AI extraction backend.
enum AiPrivacyClass {
  /// Executed 100% on-device with zero network I/O and zero telemetry egress.
  onDevice,

  /// Executed on an external cloud API requiring network I/O and explicit user consent.
  cloud,
}

/// Operational capability supported by an AI processing engine.
enum AiCapability {
  /// Multimodal vision OCR directly from raw receipt images.
  multimodalVision,

  /// Plain text extraction / transcription.
  textExtraction,

  /// Structured JSON mapping adhering to standard schema.
  structuredJson,

  /// Line-item itemization and sub-total parsing.
  lineItemParsing,

  /// Cloud-assisted reasoning and taxonomy classification.
  cloudReasoning,
}

/// User-configured backend selection preference.
enum AiSelectionPolicy {
  /// Privacy-first automatic selection: on-device VLM, then on-device LLM, then cloud (if consented), then heuristic fallback.
  auto,

  /// Strictly enforce on-device execution. Never transmit images or data to any cloud service.
  onDeviceOnly,

  /// Prefer cloud processing (e.g. Google Gemini) when configured and consented.
  cloudOnly,

  /// Force local heuristic extractor (testing or low-spec offline environments).
  localHeuristicOnly;

  static AiSelectionPolicy fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'ondeviceonly':
      case 'on_device_only':
        return AiSelectionPolicy.onDeviceOnly;
      case 'cloudonly':
      case 'cloud_only':
        return AiSelectionPolicy.cloudOnly;
      case 'localheuristiconly':
      case 'local_heuristic_only':
        return AiSelectionPolicy.localHeuristicOnly;
      case 'auto':
      default:
        return AiSelectionPolicy.auto;
    }
  }

  String toStorageString() {
    switch (this) {
      case AiSelectionPolicy.onDeviceOnly:
        return 'on_device_only';
      case AiSelectionPolicy.cloudOnly:
        return 'cloud_only';
      case AiSelectionPolicy.localHeuristicOnly:
        return 'local_heuristic_only';
      case AiSelectionPolicy.auto:
        return 'auto';
    }
  }
}

/// Provenance metadata attached to extraction results recording backend origin, version, and confidence.
@immutable
class ExtractionProvenance {
  /// Unique identifier of the executing AI backend (e.g. `on_device_vlm`, `cloud_gemini`).
  final String backendId;

  /// Specific model name or weight identifier (e.g. `Qwen2-VL-2B-Instruct`, `gemini-2.5-flash`).
  final String modelIdentifier;

  /// Engine or adapter release version.
  final String version;

  /// Privacy tier of the executing backend.
  final AiPrivacyClass privacyClass;

  /// Confidence score between 0.0 and 1.0.
  final double confidence;

  /// Exact UTC timestamp when extraction was completed.
  final DateTime extractedAt;

  /// Processing duration in milliseconds.
  final int latencyMs;

  const ExtractionProvenance({
    required this.backendId,
    required this.modelIdentifier,
    required this.version,
    required this.privacyClass,
    required this.confidence,
    required this.extractedAt,
    this.latencyMs = 0,
  });

  Map<String, dynamic> toJson() => {
        'backend_id': backendId,
        'model_identifier': modelIdentifier,
        'version': version,
        'privacy_class': privacyClass.name,
        'confidence': confidence,
        'extracted_at': extractedAt.toIso8601String(),
        'latency_ms': latencyMs,
      };

  factory ExtractionProvenance.fromJson(Map<String, dynamic> json) => ExtractionProvenance(
        backendId: json['backend_id'] as String? ?? 'unknown',
        modelIdentifier: json['model_identifier'] as String? ?? 'unknown',
        version: json['version'] as String? ?? '1.0.0',
        privacyClass: json['privacy_class'] == 'cloud' ? AiPrivacyClass.cloud : AiPrivacyClass.onDevice,
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.80,
        extractedAt: json['extracted_at'] != null
            ? (DateTime.tryParse(json['extracted_at'].toString()) ?? DateTime.now().toUtc())
            : DateTime.now().toUtc(),
        latencyMs: (json['latency_ms'] as num?)?.toInt() ?? 0,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExtractionProvenance &&
          runtimeType == other.runtimeType &&
          backendId == other.backendId &&
          modelIdentifier == other.modelIdentifier &&
          version == other.version &&
          privacyClass == other.privacyClass &&
          confidence == other.confidence &&
          extractedAt == other.extractedAt &&
          latencyMs == other.latencyMs;

  @override
  int get hashCode => Object.hash(
        backendId,
        modelIdentifier,
        version,
        privacyClass,
        confidence,
        extractedAt,
        latencyMs,
      );
}

/// Recorded user consent state for transmitting data to remote cloud AI endpoints.
@immutable
class AiCloudConsent {
  static const String keyConsentGranted = 'ai_cloud_consent_granted';
  static const String keyConsentTimestamp = 'ai_cloud_consent_timestamp';
  static const String keyConsentVersion = 'ai_cloud_consent_version';

  final bool isGranted;
  final DateTime? grantedAt;
  final String consentVersion;

  const AiCloudConsent({
    required this.isGranted,
    this.grantedAt,
    this.consentVersion = '1.0',
  });

  factory AiCloudConsent.fromBox(Box? settingsBox) {
    if (settingsBox == null) {
      return const AiCloudConsent(isGranted: false);
    }
    final storedGranted = settingsBox.get(keyConsentGranted);
    final granted = storedGranted is bool
        ? storedGranted
        : (settingsBox.get('enable_gemini_ai', defaultValue: false) as bool);
    final timestampStr = settingsBox.get(keyConsentTimestamp) as String?;
    final version = settingsBox.get(keyConsentVersion, defaultValue: '1.0') as String;
    DateTime? timestamp;
    if (timestampStr != null && timestampStr.isNotEmpty) {
      timestamp = DateTime.tryParse(timestampStr);
    } else if (granted) {
      timestamp = DateTime.now().toUtc();
    }
    return AiCloudConsent(
      isGranted: granted,
      grantedAt: timestamp,
      consentVersion: version,
    );
  }

  static Future<void> saveConsent(
    Box? settingsBox, {
    required bool granted,
    String version = '1.0',
  }) async {
    if (settingsBox == null) return;
    await settingsBox.put(keyConsentGranted, granted);
    await settingsBox.put(keyConsentVersion, version);
    if (granted) {
      await settingsBox.put(keyConsentTimestamp, DateTime.now().toUtc().toIso8601String());
    } else {
      await settingsBox.delete(keyConsentTimestamp);
    }
  }
}

/// Static and dynamic descriptor of an AI backend registered with the engine registry.
@immutable
class AiBackendDescriptor {
  final String id;
  final String name;
  final String modelIdentifier;
  final String version;
  final AiPrivacyClass privacyClass;
  final Set<AiCapability> capabilities;
  final bool isReady;
  final String? notReadyReason;

  const AiBackendDescriptor({
    required this.id,
    required this.name,
    required this.modelIdentifier,
    required this.version,
    required this.privacyClass,
    required this.capabilities,
    required this.isReady,
    this.notReadyReason,
  });

  bool get isCloud => privacyClass == AiPrivacyClass.cloud;
  bool get isOnDevice => privacyClass == AiPrivacyClass.onDevice;

  bool hasCapabilities(Set<AiCapability> required) => capabilities.containsAll(required);

  AiBackendDescriptor copyWith({
    String? id,
    String? name,
    String? modelIdentifier,
    String? version,
    AiPrivacyClass? privacyClass,
    Set<AiCapability>? capabilities,
    bool? isReady,
    String? notReadyReason,
  }) {
    return AiBackendDescriptor(
      id: id ?? this.id,
      name: name ?? this.name,
      modelIdentifier: modelIdentifier ?? this.modelIdentifier,
      version: version ?? this.version,
      privacyClass: privacyClass ?? this.privacyClass,
      capabilities: capabilities ?? this.capabilities,
      isReady: isReady ?? this.isReady,
      notReadyReason: notReadyReason ?? this.notReadyReason,
    );
  }
}

/// Immutable record of an AI backend negotiation decision.
@immutable
class BackendSelectionDecision {
  final AIService service;
  final AiBackendDescriptor descriptor;
  final AiSelectionPolicy policy;
  final bool consentGranted;
  final String rationale;

  const BackendSelectionDecision({
    required this.service,
    required this.descriptor,
    required this.policy,
    required this.consentGranted,
    required this.rationale,
  });
}

/// Central registry managing available AI extraction backends, capability negotiation, and consent governance.
class AiBackendRegistry {
  final Map<String, AIService> _registeredServices = {};

  AiBackendRegistry();

  /// Registers an [AIService] into the registry.
  void register(AIService service) {
    _registeredServices[service.descriptor.id] = service;
  }

  /// Unregisters an AI service by its backend ID.
  void unregister(String backendId) {
    _registeredServices.remove(backendId);
  }

  /// Clears all registered services.
  void clear() {
    _registeredServices.clear();
  }

  /// Returns descriptors for all currently registered backends.
  List<AiBackendDescriptor> getRegisteredDescriptors() {
    return _registeredServices.values.map((s) => s.descriptor).toList();
  }

  /// Finds a registered service by ID, or null if unregistered.
  AIService? getService(String backendId) => _registeredServices[backendId];

  /// Resolves the optimal [AIService] based on explicit policy, capability requirements, and cloud privacy consent.
  BackendSelectionDecision resolve({
    AiSelectionPolicy policy = AiSelectionPolicy.auto,
    Set<AiCapability>? requiredCapabilities,
    bool isCloudAllowed = true,
    AiCloudConsent? cloudConsent,
  }) {
    final consentGranted = cloudConsent?.isGranted ?? false;
    final canUseCloud = isCloudAllowed && consentGranted;

    // Filter by capabilities if specified
    Iterable<AIService> candidates = _registeredServices.values;
    if (requiredCapabilities != null && requiredCapabilities.isNotEmpty) {
      candidates = candidates.where((s) => s.descriptor.hasCapabilities(requiredCapabilities));
    }

    // 1. Policy: Local Heuristic Only
    if (policy == AiSelectionPolicy.localHeuristicOnly) {
      final heuristic = _findServiceById('local_heuristic') ?? _registeredServices.values.first;
      return BackendSelectionDecision(
        service: heuristic,
        descriptor: heuristic.descriptor,
        policy: policy,
        consentGranted: consentGranted,
        rationale: 'Local heuristic selected explicitly by policy.',
      );
    }

    // 2. Policy: Cloud Only
    if (policy == AiSelectionPolicy.cloudOnly) {
      final cloudService = _findFirstCloud(candidates);
      if (cloudService != null && cloudService.descriptor.isReady && canUseCloud) {
        return BackendSelectionDecision(
          service: cloudService,
          descriptor: cloudService.descriptor,
          policy: policy,
          consentGranted: consentGranted,
          rationale: 'Cloud backend selected explicitly by policy with verified consent.',
        );
      }
      // If cloud is unavailable or unconsented, fall back safely with diagnostic rationale
      final fallback = _findFallback(candidates);
      final reason = !isCloudAllowed
          ? 'Cloud processing prohibited by network isolation policy.'
          : !consentGranted
              ? 'Cloud processing requires explicit user consent.'
              : 'Cloud service is not configured or ready.';
      return BackendSelectionDecision(
        service: fallback,
        descriptor: fallback.descriptor,
        policy: policy,
        consentGranted: consentGranted,
        rationale: '$reason Falling back to on-device.',
      );
    }

    // 3. Policy: On-Device Only
    if (policy == AiSelectionPolicy.onDeviceOnly) {
      final onDeviceCandidates = candidates.where((s) => s.descriptor.isOnDevice);
      final readyOnDevice = onDeviceCandidates.where((s) => s.descriptor.isReady);

      // Prioritize on_device_vlm, then on_device_llm, then local_heuristic
      final selected = _pickPreferredOnDevice(readyOnDevice) ?? _findFallback(candidates);
      return BackendSelectionDecision(
        service: selected,
        descriptor: selected.descriptor,
        policy: policy,
        consentGranted: consentGranted,
        rationale: 'On-device engine selected under strict local privacy policy.',
      );
    }

    // 4. Policy: Auto (Privacy-First Cascade)
    // 4.1 On-device VLM (highest precision, zero data egress)
    final vlm = _findServiceById('on_device_vlm');
    if (vlm != null && vlm.descriptor.isReady) {
      return BackendSelectionDecision(
        service: vlm,
        descriptor: vlm.descriptor,
        policy: policy,
        consentGranted: consentGranted,
        rationale: 'On-device VLM ready and selected (zero network egress).',
      );
    }

    // 4.2 On-device LLM
    final llm = _findServiceById('on_device_llm');
    if (llm != null && llm.descriptor.isReady) {
      return BackendSelectionDecision(
        service: llm,
        descriptor: llm.descriptor,
        policy: policy,
        consentGranted: consentGranted,
        rationale: 'On-device hybrid LLM ready and selected.',
      );
    }

    // 4.3 Cloud Gemini (if configured, network allowed, and explicitly consented)
    final cloud = _findFirstCloud(candidates);
    if (cloud != null && cloud.descriptor.isReady && canUseCloud) {
      return BackendSelectionDecision(
        service: cloud,
        descriptor: cloud.descriptor,
        policy: policy,
        consentGranted: consentGranted,
        rationale: 'Cloud Gemini selected with verified user consent and allowed network policy.',
      );
    }

    // 4.4 Heuristic Fallback
    final fallback = _findFallback(candidates);
    return BackendSelectionDecision(
      service: fallback,
      descriptor: fallback.descriptor,
      policy: policy,
      consentGranted: consentGranted,
      rationale: 'Fallback heuristic extractor selected (no neural models ready or consented).',
    );
  }

  AIService? _findServiceById(String id) {
    return _registeredServices[id];
  }

  AIService? _findFirstCloud(Iterable<AIService> items) {
    for (final s in items) {
      if (s.descriptor.isCloud) return s;
    }
    return null;
  }

  AIService? _pickPreferredOnDevice(Iterable<AIService> items) {
    for (final id in ['on_device_vlm', 'on_device_llm', 'local_heuristic']) {
      for (final s in items) {
        if (s.descriptor.id == id) return s;
      }
    }
    return items.isEmpty ? null : items.first;
  }

  AIService _findFallback(Iterable<AIService> items) {
    return _findServiceById('local_heuristic') ??
        (items.isNotEmpty ? items.first : throw StateError('No AI backends registered in AiBackendRegistry.'));
  }
}
