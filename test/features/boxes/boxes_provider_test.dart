import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:t_aidy/features/boxes/data/providers/boxes_provider.dart';

void main() {
  group('BoxesNotifier - Active Box Deletion Handling', () {
    test('resets activeBoxId to main when the active custom box is deleted', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(boxesProvider.notifier);

      // Create a custom box
      final customBox = await notifier.createNew(
        name: 'Travel 2024',
        budget: 1500,
        currency: 'USD',
        color: Colors.blue,
      );

      // Set active box to the custom box
      container.read(activeBoxIdProvider.notifier).state = customBox.id;
      expect(container.read(activeBoxIdProvider), customBox.id);

      // Delete the active custom box
      await notifier.deleteBox(customBox.id);

      // Verify active box falls back immediately to 'main'
      expect(container.read(activeBoxIdProvider), 'main');
      expect(container.read(boxesProvider).any((b) => b.id == customBox.id), isFalse);
    });

    test('retains activeBoxId if a different non-active box is deleted', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(boxesProvider.notifier);

      final boxA = await notifier.createNew(
        name: 'Groceries',
        budget: 400,
        currency: 'USD',
        color: Colors.green,
      );
      final boxB = await notifier.createNew(
        name: 'Tech Setup',
        budget: 800,
        currency: 'USD',
        color: Colors.purple,
      );

      // Set active box to boxA
      container.read(activeBoxIdProvider.notifier).state = boxA.id;

      // Delete boxB
      await notifier.deleteBox(boxB.id);

      // Verify active box remains boxA
      expect(container.read(activeBoxIdProvider), boxA.id);
    });
  });
}
