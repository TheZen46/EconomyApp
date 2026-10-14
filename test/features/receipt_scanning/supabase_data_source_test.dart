import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:t_aidy/core/error/failures.dart';
import 'package:t_aidy/features/receipt_scanning/data/datasources/supabase_data_source.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';

class FakeSupabaseClientForBatch extends Fake implements SupabaseClient {
  final List<List<String>> deletedIdBatches = [];
  final List<List<String>> deletedStorageBatches = [];
  final List<Map<String, dynamic>> mockDatabaseRows;

  /// Object names returned when a folder is listed; listing fails when null.
  List<String>? storedImageNames;

  FakeSupabaseClientForBatch({List<Map<String, dynamic>>? mockRows})
      : mockDatabaseRows = mockRows ?? [];

  @override
  SupabaseStorageClient get storage => FakeStorageClient(this);

  @override
  SupabaseQueryBuilder from(String table) {
    return FakeSupabaseQueryBuilder(this, table);
  }
}

class FakeStorageClient extends Fake implements SupabaseStorageClient {
  final FakeSupabaseClientForBatch parent;
  FakeStorageClient(this.parent);

  @override
  StorageFileApi from(String id) => FakeStorageFileApi(parent);
}

class FakeStorageFileApi extends Fake implements StorageFileApi {
  final FakeSupabaseClientForBatch parent;
  FakeStorageFileApi(this.parent);

  @override
  Future<List<FileObject>> remove(List<String> paths) async {
    parent.deletedStorageBatches.add(List<String>.from(paths));
    return [];
  }

  @override
  Future<List<FileObject>> list({String? path, SearchOptions searchOptions = const SearchOptions()}) async {
    final names = parent.storedImageNames;
    if (names == null) throw const StorageException('listing unavailable');
    final offset = searchOptions.offset ?? 0;
    return names.skip(offset).take(searchOptions.limit ?? 100).map((n) => FileObject.fromJson({'name': n})).toList();
  }
}

class FakeSupabaseQueryBuilder extends Fake implements SupabaseQueryBuilder {
  final FakeSupabaseClientForBatch parent;
  final String table;

  FakeSupabaseQueryBuilder(this.parent, this.table);

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> delete({
    dynamic options,
  }) {
    return FakePostgrestFilterBuilder<List<Map<String, dynamic>>>(parent, isDelete: true);
  }

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> select([String columns = '*']) {
    return FakePostgrestFilterBuilder<List<Map<String, dynamic>>>(parent, isDelete: false);
  }
}

class FakePostgrestFilterBuilder<T> extends Fake implements PostgrestFilterBuilder<T> {
  final FakeSupabaseClientForBatch parent;
  final bool isDelete;

  FakePostgrestFilterBuilder(this.parent, {required this.isDelete});

  @override
  PostgrestFilterBuilder<T> inFilter(String column, List<dynamic> values) {
    if (isDelete) {
      parent.deletedIdBatches.add(values.map((e) => e.toString()).toList());
    }
    return this;
  }

  @override
  PostgrestTransformBuilder<T> range(int from, int to, {String? referencedTable}) {
    return FakePostgrestTransformBuilder<T>(parent, from, to);
  }

  @override
  Future<R> then<R>(FutureOr<R> Function(T value) onValue, {Function? onError}) async {
    final result = <Map<String, dynamic>>[] as T;
    return onValue(result);
  }
}

class FakePostgrestTransformBuilder<T> extends Fake implements PostgrestTransformBuilder<T> {
  final FakeSupabaseClientForBatch parent;
  final int from;
  final int to;

  FakePostgrestTransformBuilder(this.parent, this.from, this.to);

  @override
  Future<R> then<R>(FutureOr<R> Function(T value) onValue, {Function? onError}) async {
    final start = from.clamp(0, parent.mockDatabaseRows.length);
    final end = (to + 1).clamp(0, parent.mockDatabaseRows.length);
    final slice = parent.mockDatabaseRows.sublist(start, end);
    return onValue(slice as T);
  }
}

void main() {
  group('SupabaseDataSourceImpl - Batch Operations & Cursor Pagination', () {
    test('chunkList correctly partitions large lists into chunks of max 100 items', () {
      final items = List.generate(285, (i) => 'item-$i');
      final chunks = SupabaseDataSourceImpl.chunkList(items, 100);

      expect(chunks.length, 3);
      expect(chunks[0].length, 100);
      expect(chunks[1].length, 100);
      expect(chunks[2].length, 85);
      expect(chunks[0].first, 'item-0');
      expect(chunks[2].last, 'item-284');
    });

    test('deleteReceipts executes batch SQL IN (...) queries in chunks of 100 IDs on 250+ items', () async {
      final fakeClient = FakeSupabaseClientForBatch();
      final dataSource = SupabaseDataSourceImpl(fakeClient);

      final idsToDelete = List.generate(265, (i) => 'receipt-id-$i');

      await dataSource.deleteReceipts(idsToDelete);

      expect(fakeClient.deletedIdBatches.length, 3);
      expect(fakeClient.deletedIdBatches[0].length, 100);
      expect(fakeClient.deletedIdBatches[1].length, 100);
      expect(fakeClient.deletedIdBatches[2].length, 65);

      final flattened = fakeClient.deletedIdBatches.expand((x) => x).toList();
      expect(flattened, idsToDelete);
    });

    test('deleteData chunks storage file deletion requests into batches of 100 paths', () async {
      final fakeClient = FakeSupabaseClientForBatch();
      final dataSource = SupabaseDataSourceImpl(fakeClient);

      // 120 receipt IDs -> 240 storage files (image + label)
      final idsToDelete = List.generate(120, (i) => 'rec-$i');

      await dataSource.deleteData(idsToDelete, imagePaths: [for (final id in idsToDelete) '/docs/$id.jpg']);

      expect(fakeClient.deletedStorageBatches.length, 3);
      expect(fakeClient.deletedStorageBatches[0].length, 100);
      expect(fakeClient.deletedStorageBatches[1].length, 100);
      expect(fakeClient.deletedStorageBatches[2].length, 40);

      final totalFilesDeleted = fakeClient.deletedStorageBatches.fold(0, (sum, b) => sum + b.length);
      expect(totalFilesDeleted, 240);
    });

    test('deleteData removes images by the extension they were uploaded with', () async {
      final fakeClient = FakeSupabaseClientForBatch();
      final dataSource = SupabaseDataSourceImpl(fakeClient);

      await dataSource.deleteData(
        ['a', 'b', 'c', 'd'],
        imagePaths: ['/docs/receipt_images/a.png', '/cache/b.jpeg', '/x/c.HEIC', '/x/d.webp'],
      );

      final removed = fakeClient.deletedStorageBatches.expand((b) => b).toList();
      expect(removed, containsAll(['images/a.png', 'images/b.jpeg', 'images/c.heic', 'images/d.webp']));
      expect(removed, isNot(contains('images/a.jpg')));
    });

    test('deleteData finds images of unknown extension by listing the folder', () async {
      final fakeClient = FakeSupabaseClientForBatch()..storedImageNames = ['a.png', 'ab.jpg', 'b.heic', 'z.jpg'];
      final dataSource = SupabaseDataSourceImpl(fakeClient);

      await dataSource.deleteData(['a', 'b']);

      final removed = fakeClient.deletedStorageBatches.expand((b) => b).toList();
      expect(removed, unorderedEquals(['images/a.png', 'images/b.heic', 'labels/a.json', 'labels/b.json']));
    });

    test('deleteData targets every known extension when the folder cannot be listed', () async {
      final fakeClient = FakeSupabaseClientForBatch();
      final dataSource = SupabaseDataSourceImpl(fakeClient);

      await dataSource.deleteData(['a']);

      final removed = fakeClient.deletedStorageBatches.expand((b) => b).toList();
      expect(removed, containsAll([for (final ext in SupabaseDataSourceImpl.knownImageExtensions) 'images/a$ext']));
    });

    test('fetchAllReceipts paginates seamlessly through datasets exceeding 100 items using .range(from, to)', () async {
      final mockData = List.generate(
        340,
        (i) => {
          'id': 'rec-$i',
          'merchant_name': 'Store $i',
          'total_amount': (i + 1) * 5.0,
        },
      );

      final fakeClient = FakeSupabaseClientForBatch(mockRows: mockData);
      final dataSource = SupabaseDataSourceImpl(fakeClient);

      final results = await dataSource.fetchAllReceipts(pageSize: 100);

      expect(results.length, 340);
      expect(results.first['id'], 'rec-0');
      expect(results.last['id'], 'rec-339');
    });
  });

  group('SupabaseDataSourceImpl - training upload', () {
    test('refuses to upload without a signed-in user instead of using a shared prefix', () async {
      // The fake client has no auth session, so the current user id resolves to null.
      final dataSource = SupabaseDataSourceImpl(FakeSupabaseClientForBatch());
      final receipt = Receipt(
        id: 'rec-anon',
        merchantName: 'Store',
        totalAmount: 1.0,
        date: DateTime.utc(2026, 9, 1),
        items: const [],
        currency: 'EUR',
      );

      await expectLater(
        dataSource.uploadTrainingData(receipt, ''),
        throwsA(isA<ServerFailure>()),
      );
    });
  });
}
