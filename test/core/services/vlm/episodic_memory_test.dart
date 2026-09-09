import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/services/vlm/episodic_memory_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EpisodicMemoryService Tests', () {
    late EpisodicMemoryService memoryService;

    setUp(() {
      memoryService = EpisodicMemoryService();
    });

    tearDown(() {
      memoryService.dispose();
    });

    test('Initializes database and records corrections', () async {
      await memoryService.initialize(inMemory: true);
      await memoryService.recordCorrection(
        rawName: 'OATLY OAT MILK 64OZ',
        correctedName: 'Oat Milk 64oz',
        mainCategory: 'Proteins & Dairy',
        subCategory: 'Dairy & Alternatives',
        necessity: 'essential',
        merchantName: 'Target Supercenter',
      );

      final promptSection = await memoryService.buildFewShotPromptSection(
        merchantName: 'Target Supercenter',
        limit: 3,
      );

      expect(promptSection, isNotNull);
      expect(promptSection!.contains('OATLY OAT MILK 64OZ'), isTrue);
      expect(promptSection.contains('Proteins & Dairy'), isTrue);
      expect(promptSection.contains('Target Supercenter'), isTrue);
    });
  });
}
