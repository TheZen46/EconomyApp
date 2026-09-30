import 'dart:convert';
import 'package:crypto/crypto.dart';

/// A single atomic visual frame within an animated QR transfer stream.
class QrChunkFrame {
  final int version;
  final String transferId;
  final int chunkIndex;
  final int totalChunks;
  final String chunkSha256;
  final String payloadBase64;

  const QrChunkFrame({
    this.version = 1,
    required this.transferId,
    required this.chunkIndex,
    required this.totalChunks,
    required this.chunkSha256,
    required this.payloadBase64,
  });

  /// Serializes the chunk into a compact QR-readable wire string:
  /// `TAIDY_V1|<transferId>|<index>|<total>|<sha256_8char>|<base64>`
  String serialize() {
    final shortHash = chunkSha256.length >= 8 ? chunkSha256.substring(0, 8) : chunkSha256;
    return 'TAIDY_V1|$transferId|$chunkIndex|$totalChunks|$shortHash|$payloadBase64';
  }

  /// Parses an animated QR wire string. Returns null if malformed.
  static QrChunkFrame? deserialize(String raw) {
    if (!raw.startsWith('TAIDY_V1|')) return null;
    final parts = raw.split('|');
    if (parts.length < 6) return null;

    final transferId = parts[1];
    final chunkIndex = int.tryParse(parts[2]);
    final totalChunks = int.tryParse(parts[3]);
    final shortHash = parts[4];
    final payloadBase64 = parts[5];

    if (chunkIndex == null || totalChunks == null || chunkIndex < 0 || chunkIndex >= totalChunks) {
      return null;
    }

    // Verify payload integrity hash
    final computedHash = sha256.convert(utf8.encode(payloadBase64)).toString();
    if (!computedHash.startsWith(shortHash)) {
      return null; // Checksum integrity mismatch
    }

    return QrChunkFrame(
      version: 1,
      transferId: transferId,
      chunkIndex: chunkIndex,
      totalChunks: totalChunks,
      chunkSha256: computedHash,
      payloadBase64: payloadBase64,
    );
  }
}

/// [UNIQUE] Air-Gapped Animated QR Chunk Protocol & Serializer.
///
/// Encodes arbitrarily sized encrypted financial ledger blobs into a sequence of
/// animated QR code frames for zero-cloud, 100% optical device-to-device data migration.
class QrChunkProtocol {
  /// Default max characters per QR code chunk for optimal optical camera scanning
  static const int defaultChunkSize = 250;

  /// Splits an arbitrary raw JSON/binary string payload into sequenced QR chunk frames.
  static List<QrChunkFrame> encodePayload({
    required String rawPayload,
    String? transferId,
    int chunkSize = defaultChunkSize,
  }) {
    final bytes = utf8.encode(rawPayload);
    final base64Full = base64.encode(bytes);

    final actualTransferId = transferId ?? sha256.convert(bytes).toString().substring(0, 8);
    final totalChunks = (base64Full.length / chunkSize).ceil();
    final safeTotal = totalChunks == 0 ? 1 : totalChunks;

    final frames = <QrChunkFrame>[];

    for (int i = 0; i < safeTotal; i++) {
      final start = i * chunkSize;
      final end = (start + chunkSize > base64Full.length) ? base64Full.length : start + chunkSize;
      final chunkData = base64Full.isNotEmpty ? base64Full.substring(start, end) : '';
      final chunkHash = sha256.convert(utf8.encode(chunkData)).toString();

      frames.add(QrChunkFrame(
        transferId: actualTransferId,
        chunkIndex: i,
        totalChunks: safeTotal,
        chunkSha256: chunkHash,
        payloadBase64: chunkData,
      ));
    }

    return frames;
  }
}
