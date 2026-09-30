import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/sync/qr_chunk_protocol.dart';
import 'package:t_aidy/core/sync/qr_chunk_reconstructor.dart';

void main() {
  group('Air-Gapped Optical QR Chunk Protocol Tests', () {
    test('encodes and reconstructs short payload cleanly in a single chunk', () {
      const payload = '{"vault":"secret_encrypted_data_123","version":1}';

      final frames = QrChunkProtocol.encodePayload(rawPayload: payload);
      expect(frames.length, 1);

      final reconstructor = QrChunkReconstructor();
      final wireString = frames.first.serialize();

      final progress = reconstructor.ingestFrameString(wireString);
      expect(progress, isNotNull);
      expect(progress!.isComplete, true);
      expect(progress.progressFraction, 1.0);

      final reconstructed = reconstructor.assemblePayload();
      expect(reconstructed, payload);
    });

    test('encodes and reconstructs large payload across multiple out-of-order chunks', () {
      // Create a large JSON payload simulating a complete receipt vault
      final largeData = {
        'timestamp': DateTime.now().toIso8601String(),
        'items': List.generate(50, (i) => {
          'id': 'rec_$i',
          'merchant': 'Merchant $i Corporation',
          'amount': (i + 1) * 12.50,
          'category': 'Equipment',
        }),
      };
      final rawPayload = jsonEncode(largeData);

      // Force small chunk size of 80 characters to create many chunks
      final frames = QrChunkProtocol.encodePayload(
        rawPayload: rawPayload,
        chunkSize: 80,
      );

      expect(frames.length, greaterThan(10));

      final reconstructor = QrChunkReconstructor();

      // Ingest frames in reverse order (simulating out-of-order optical scans)
      for (final frame in frames.reversed) {
        final wire = frame.serialize();
        final progress = reconstructor.ingestFrameString(wire);
        expect(progress, isNotNull);
      }

      expect(reconstructor.isComplete, true);
      final reconstructed = reconstructor.assemblePayload();
      expect(reconstructed, rawPayload);

      final decodedJson = jsonDecode(reconstructed!) as Map<String, dynamic>;
      expect(decodedJson['items'].length, 50);
    });

    test('rejects corrupted QR frame with invalid checksum', () {
      const payload = 'Confidential Air-Gapped Data';
      final frames = QrChunkProtocol.encodePayload(rawPayload: payload);
      final validWire = frames.first.serialize();

      // Tamper with base64 payload in the wire string
      final corruptedWire = validWire.replaceAll(RegExp(r'[A-Za-z0-9]'), 'Z');

      final reconstructor = QrChunkReconstructor();
      final progress = reconstructor.ingestFrameString(corruptedWire);

      expect(progress, isNull);
      expect(reconstructor.receivedCount, 0);
    });

    test('tracks missing chunk indices during partial reception', () {
      const payload = 'Multi-chunk test with missing frames simulation';
      final frames = QrChunkProtocol.encodePayload(rawPayload: payload, chunkSize: 10);

      expect(frames.length, greaterThan(3));

      final reconstructor = QrChunkReconstructor();

      // Ingest chunk 0 and chunk 2, skipping chunk 1
      reconstructor.ingestFrame(frames[0]);
      final progress = reconstructor.ingestFrame(frames[2]);

      expect(progress.isComplete, false);
      expect(progress.missingChunkIndices, contains(1));
      expect(reconstructor.assemblePayload(), isNull);
    });
  });
}
