import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/features/receipt_scanning/data/datasources/receipt_image_store.dart';

void main() {
  late Directory docs;
  late Directory cache;
  late ReceiptImageStore store;

  setUp(() async {
    docs = await Directory.systemTemp.createTemp('image_store_docs_');
    cache = await Directory.systemTemp.createTemp('image_store_cache_');
    store = ReceiptImageStore(documentsDirectory: () async => docs);
  });

  tearDown(() {
    for (final dir in [docs, cache]) {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  });

  test('copies a picker file into the documents directory, keeping its extension', () async {
    final picked = File('${cache.path}/image_picker_123.PNG')..writeAsBytesSync([1, 2, 3]);

    final stored = await store.persist('rec-1', picked.path);

    expect(stored, '${docs.path}/${ReceiptImageStore.folderName}/rec-1.png');
    expect(File(stored).readAsBytesSync(), [1, 2, 3]);

    // The cache may now be purged without losing the image.
    cache.deleteSync(recursive: true);
    expect(File(stored).existsSync(), isTrue);

    // Saving the receipt again keeps the stored path.
    expect(await store.persist('rec-1', stored), stored);
  });

  test('leaves empty, remote and missing paths unchanged', () async {
    expect(await store.persist('rec-1', ''), '');
    expect(await store.persist('rec-1', 'https://example.com/a.jpg'), 'https://example.com/a.jpg');
    expect(await store.persist('rec-1', '${cache.path}/missing.jpg'), '${cache.path}/missing.jpg');
  });

  test('deletes only files inside the store', () async {
    final stored = await store.persist('rec-1', (File('${cache.path}/a.jpg')..writeAsBytesSync([1])).path);
    final outside = File('${cache.path}/b.jpg')..writeAsBytesSync([2]);

    await store.delete(stored);
    await store.delete(outside.path);

    expect(File(stored).existsSync(), isFalse);
    expect(outside.existsSync(), isTrue);
  });
}
