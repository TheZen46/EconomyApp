import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:t_aidy/core/constants/taxonomy_constants.dart';
import 'package:t_aidy/core/error/failures.dart';
import 'package:t_aidy/core/services/ai_service.dart';
import 'package:t_aidy/core/services/ai_backend_registry.dart';
import 'package:t_aidy/features/receipt_scanning/data/datasources/mock_ai_service.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/providers/receipt_provider.dart';

class _FakeAiService implements AIService {
  @override
  final AiBackendDescriptor descriptor;
  final Receipt? receiptToReturn;

  const _FakeAiService({
    required this.descriptor,
    this.receiptToReturn,
  });

  @override
  Future<Either<Failure, Receipt>> extractReceiptData(
    String imagePath, {
    Map<String, Map<String, List<TaxonomyItem>>>? taxonomy,
  }) async {
    if (receiptToReturn != null) {
      return Right(receiptToReturn!);
    }
    return const Left(AIProcessingFailure('Fake extraction error'));
  }
}

void main() {
  group('AiBackendRegistry Unit Tests', () {
    late AiBackendRegistry registry;

    final vlmReady = _FakeAiService(
      descriptor: const AiBackendDescriptor(
        id: 'on_device_vlm',
        name: 'VLM Engine (Qwen2-VL)',
        modelIdentifier: 'Qwen2-VL-2B-Instruct',
        version: '2.0.0',
        privacyClass: AiPrivacyClass.onDevice,
        capabilities: {
          AiCapability.multimodalVision,
          AiCapability.structuredJson,
          AiCapability.lineItemParsing,
        },
        isReady: true,
      ),
    );

    final vlmNotReady = _FakeAiService(
      descriptor: const AiBackendDescriptor(
        id: 'on_device_vlm',
        name: 'VLM Engine (Qwen2-VL)',
        modelIdentifier: 'Qwen2-VL-2B-Instruct',
        version: '2.0.0',
        privacyClass: AiPrivacyClass.onDevice,
        capabilities: {
          AiCapability.multimodalVision,
          AiCapability.structuredJson,
          AiCapability.lineItemParsing,
        },
        isReady: false,
        notReadyReason: 'Model weights not loaded',
      ),
    );

    final llmReady = _FakeAiService(
      descriptor: const AiBackendDescriptor(
        id: 'on_device_llm',
        name: 'On-Device LLM (Legacy)',
        modelIdentifier: 'gemma-2b-it.Q4_K_M.gguf',
        version: '1.2.0',
        privacyClass: AiPrivacyClass.onDevice,
        capabilities: {
          AiCapability.textExtraction,
          AiCapability.structuredJson,
          AiCapability.lineItemParsing,
        },
        isReady: true,
      ),
    );

    final geminiReady = _FakeAiService(
      descriptor: const AiBackendDescriptor(
        id: 'cloud_gemini',
        name: 'Google Gemini',
        modelIdentifier: 'gemini-2.5-flash',
        version: '2.5.0',
        privacyClass: AiPrivacyClass.cloud,
        capabilities: {
          AiCapability.multimodalVision,
          AiCapability.textExtraction,
          AiCapability.structuredJson,
          AiCapability.lineItemParsing,
          AiCapability.cloudReasoning,
        },
        isReady: true,
      ),
    );

    final heuristicFallback = FallbackAIService();

    setUp(() {
      registry = AiBackendRegistry();
    });

    test('registers, retrieves, and unregisters backends properly', () {
      registry.register(vlmReady);
      registry.register(geminiReady);

      expect(registry.getRegisteredDescriptors().length, equals(2));
      expect(registry.getService('on_device_vlm'), equals(vlmReady));
      expect(registry.getService('cloud_gemini'), equals(geminiReady));

      registry.unregister('cloud_gemini');
      expect(registry.getService('cloud_gemini'), isNull);
      expect(registry.getRegisteredDescriptors().length, equals(1));

      registry.clear();
      expect(registry.getRegisteredDescriptors(), isEmpty);
    });

    group('Policy: Auto (Privacy-First Cascade)', () {
      test('selects on_device_vlm when ready, regardless of cloud consent', () {
        registry.register(vlmReady);
        registry.register(llmReady);
        registry.register(geminiReady);
        registry.register(heuristicFallback);

        final decision = registry.resolve(
          policy: AiSelectionPolicy.auto,
          isCloudAllowed: true,
          cloudConsent: const AiCloudConsent(isGranted: true),
        );

        expect(decision.descriptor.id, equals('on_device_vlm'));
        expect(decision.descriptor.isOnDevice, isTrue);
        expect(decision.rationale, contains('On-device VLM ready and selected'));
      });

      test('cascades to on_device_llm when vlm is not ready', () {
        registry.register(vlmNotReady);
        registry.register(llmReady);
        registry.register(geminiReady);
        registry.register(heuristicFallback);

        final decision = registry.resolve(
          policy: AiSelectionPolicy.auto,
          isCloudAllowed: true,
          cloudConsent: const AiCloudConsent(isGranted: true),
        );

        expect(decision.descriptor.id, equals('on_device_llm'));
        expect(decision.rationale, contains('On-device hybrid LLM ready and selected'));
      });

      test('cascades to cloud Gemini when local models not ready and consent granted', () {
        registry.register(vlmNotReady);
        registry.register(geminiReady);
        registry.register(heuristicFallback);

        final decision = registry.resolve(
          policy: AiSelectionPolicy.auto,
          isCloudAllowed: true,
          cloudConsent: const AiCloudConsent(isGranted: true),
        );

        expect(decision.descriptor.id, equals('cloud_gemini'));
        expect(decision.descriptor.isCloud, isTrue);
        expect(decision.consentGranted, isTrue);
      });

      test('falls back to local heuristic if cloud consent is denied', () {
        registry.register(vlmNotReady);
        registry.register(geminiReady);
        registry.register(heuristicFallback);

        final decision = registry.resolve(
          policy: AiSelectionPolicy.auto,
          isCloudAllowed: true,
          cloudConsent: const AiCloudConsent(isGranted: false),
        );

        expect(decision.descriptor.id, equals('local_heuristic'));
        expect(decision.rationale, contains('Fallback heuristic extractor selected'));
      });

      test('falls back to local heuristic if network isolation prohibits cloud', () {
        registry.register(vlmNotReady);
        registry.register(geminiReady);
        registry.register(heuristicFallback);

        final decision = registry.resolve(
          policy: AiSelectionPolicy.auto,
          isCloudAllowed: false,
          cloudConsent: const AiCloudConsent(isGranted: true),
        );

        expect(decision.descriptor.id, equals('local_heuristic'));
      });
    });

    group('Policy: onDeviceOnly', () {
      test('never selects cloud even when consented and cloud ready', () {
        registry.register(vlmReady);
        registry.register(geminiReady);
        registry.register(heuristicFallback);

        final decision = registry.resolve(
          policy: AiSelectionPolicy.onDeviceOnly,
          isCloudAllowed: true,
          cloudConsent: const AiCloudConsent(isGranted: true),
        );

        expect(decision.descriptor.isOnDevice, isTrue);
        expect(decision.descriptor.id, equals('on_device_vlm'));
      });

      test('selects local heuristic when neural local models are not ready', () {
        registry.register(vlmNotReady);
        registry.register(geminiReady);
        registry.register(heuristicFallback);

        final decision = registry.resolve(
          policy: AiSelectionPolicy.onDeviceOnly,
          isCloudAllowed: true,
          cloudConsent: const AiCloudConsent(isGranted: true),
        );

        expect(decision.descriptor.id, equals('local_heuristic'));
      });
    });

    group('Policy: cloudOnly', () {
      test('selects cloud when ready and consented', () {
        registry.register(vlmReady);
        registry.register(geminiReady);
        registry.register(heuristicFallback);

        final decision = registry.resolve(
          policy: AiSelectionPolicy.cloudOnly,
          isCloudAllowed: true,
          cloudConsent: const AiCloudConsent(isGranted: true),
        );

        expect(decision.descriptor.id, equals('cloud_gemini'));
        expect(decision.descriptor.isCloud, isTrue);
      });

      test('falls back safely to on-device when consent is not granted', () {
        registry.register(vlmReady);
        registry.register(geminiReady);
        registry.register(heuristicFallback);

        final decision = registry.resolve(
          policy: AiSelectionPolicy.cloudOnly,
          isCloudAllowed: true,
          cloudConsent: const AiCloudConsent(isGranted: false),
        );

        expect(decision.descriptor.id, equals('local_heuristic'));
        expect(decision.rationale, contains('Cloud processing requires explicit user consent'));
      });

      test('falls back safely to on-device when network isolation is active', () {
        registry.register(vlmReady);
        registry.register(geminiReady);
        registry.register(heuristicFallback);

        final decision = registry.resolve(
          policy: AiSelectionPolicy.cloudOnly,
          isCloudAllowed: false,
          cloudConsent: const AiCloudConsent(isGranted: true),
        );

        expect(decision.descriptor.id, equals('local_heuristic'));
        expect(decision.rationale, contains('prohibited by network isolation'));
      });
    });

    group('Policy: localHeuristicOnly', () {
      test('strictly selects heuristic even if VLM and Cloud are ready', () {
        registry.register(vlmReady);
        registry.register(geminiReady);
        registry.register(heuristicFallback);

        final decision = registry.resolve(
          policy: AiSelectionPolicy.localHeuristicOnly,
          isCloudAllowed: true,
          cloudConsent: const AiCloudConsent(isGranted: true),
        );

        expect(decision.descriptor.id, equals('local_heuristic'));
        expect(decision.rationale, contains('Local heuristic selected explicitly by policy'));
      });
    });

    group('Capability Negotiation', () {
      test('filters out backends lacking required capabilities', () {
        registry.register(llmReady); // lacks multimodalVision
        registry.register(vlmReady); // has multimodalVision
        registry.register(heuristicFallback);

        final decision = registry.resolve(
          policy: AiSelectionPolicy.auto,
          requiredCapabilities: const {AiCapability.multimodalVision},
        );

        expect(decision.descriptor.id, equals('on_device_vlm'));
      });
    });

    group('Provenance Metadata Attachment', () {
      test('FallbackAIService attaches ExtractionProvenance to parsed receipts', () {
        const ocr = '''
SUPERMERCATO TEST
27/09/2026 14:30
PANE 2.50 EUR
TOTALE 2.50 EUR
''';
        final receipt = FallbackAIService().parseOcrText(ocr);
        expect(receipt, isNotNull);
        expect(receipt!.provenance, isNotNull);

        final prov = receipt.provenance!;
        expect(prov.backendId, equals('local_heuristic'));
        expect(prov.modelIdentifier, equals('mlkit_regex_heuristics'));
        expect(prov.privacyClass, equals(AiPrivacyClass.onDevice));
        expect(prov.confidence, closeTo(0.70, 0.01));
        expect(prov.extractedAt, isNotNull);
      });

      test('ExtractionProvenance roundtrips via JSON serialization', () {
        final prov = ExtractionProvenance(
          backendId: 'on_device_vlm',
          modelIdentifier: 'Qwen2-VL-2B-Instruct',
          version: '2.0.0',
          privacyClass: AiPrivacyClass.onDevice,
          confidence: 0.95,
          extractedAt: DateTime.utc(2026, 10, 14, 12, 0, 0),
          latencyMs: 1420,
        );

        final json = prov.toJson();
        final reconstituted = ExtractionProvenance.fromJson(json);

        expect(reconstituted, equals(prov));
        expect(reconstituted.backendId, equals('on_device_vlm'));
        expect(reconstituted.privacyClass, equals(AiPrivacyClass.onDevice));
        expect(reconstituted.latencyMs, equals(1420));
      });
    });

    group('Riverpod Provider Container Resolution', () {
      test('aiServiceProvider forwards to activeAiDecisionProvider.service', () {
        final container = ProviderContainer(
          overrides: [
            activeAiDecisionProvider.overrideWithValue(
              BackendSelectionDecision(
                service: vlmReady,
                descriptor: vlmReady.descriptor,
                policy: AiSelectionPolicy.auto,
                consentGranted: false,
                rationale: 'Overridden for testing',
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        final resolvedService = container.read(aiServiceProvider);
        expect(resolvedService.descriptor.id, equals('on_device_vlm'));
        expect(resolvedService.descriptor.name, equals('VLM Engine (Qwen2-VL)'));
      });
    });
  });
}
