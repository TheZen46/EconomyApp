import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:t_aidy/features/reconciliation/presentation/providers/reconciliation_provider.dart';

void main() {
  group('ReconciliationProvider & ReconciliationState', () {
    test('initial state is clean and not loading', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state = container.read(reconciliationProvider);
      expect(state.matches.isEmpty, true);
      expect(state.isLoading, false);
      expect(state.errorMessage, null);
      expect(state.matchedCount, 0);
      expect(state.totalCount, 0);
      expect(state.matchPercentage, 0);
    });

    test('loadSampleStatement parses transactions and sets matches', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(reconciliationProvider.notifier);
      notifier.loadSampleStatement();

      final state = container.read(reconciliationProvider);
      expect(state.isLoading, false);
      expect(state.errorMessage, null);
      expect(state.matches.length, 5);
      expect(state.totalCount, 5);
    });

    test('loadFromContent handles malformed/empty CSV gracefully', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(reconciliationProvider.notifier);
      final success = notifier.loadFromContent('Invalid,CSV,Without,Valid,Rows', 'csv');

      expect(success, false);
      final state = container.read(reconciliationProvider);
      expect(state.matches.isEmpty, true);
      expect(state.errorMessage, contains('No transactions could be parsed'));
      expect(state.isLoading, false);
    });

    test('reset clears state back to empty', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(reconciliationProvider.notifier);
      notifier.loadSampleStatement();
      expect(container.read(reconciliationProvider).matches.isNotEmpty, true);

      notifier.reset();
      expect(container.read(reconciliationProvider).matches.isEmpty, true);
    });
  });
}
