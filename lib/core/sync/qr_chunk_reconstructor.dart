import 'dart:convert';
import 'qr_chunk_protocol.dart';

/// Progress state of an active optical QR stream reception.
class QrReconstructionProgress {
  final String transferId;
  final int receivedCount;
  final int totalExpected;
  final double progressFraction; // 0.0 to 1.0
  final List<int> missingChunkIndices;
  final bool isComplete;

  const QrReconstructionProgress({
    required this.transferId,
    required this.receivedCount,
    required this.totalExpected,
    required this.progressFraction,
    required this.missingChunkIndices,
    required this.isComplete,
  });

  Map<String, dynamic> toJson() => {
        'transferId': transferId,
        'receivedCount': receivedCount,
        'totalExpected': totalExpected,
        'progressFraction': progressFraction,
        'missingChunkIndices': missingChunkIndices,
        'isComplete': isComplete,
      };
}

/// [UNIQUE] Optical QR Stream Reconstructor & Frame Assembler.
///
/// Collects arbitrary out-of-order animated QR frames from a device camera stream,
/// validates mathematical checksums, tracks missing frames, and reconstructs the payload.
class QrChunkReconstructor {
  String? _activeTransferId;
  int _totalExpected = 0;
  final Map<int, String> _chunks = {};

  String? get activeTransferId => _activeTransferId;
  int get totalExpected => _totalExpected;
  int get receivedCount => _chunks.length;
  bool get isComplete => _totalExpected > 0 && _chunks.length == _totalExpected;

  /// Ingests a raw scanned QR string.
  /// Returns updated reconstruction progress, or null if the frame was invalid.
  QrReconstructionProgress? ingestFrameString(String rawFrameString) {
    final frame = QrChunkFrame.deserialize(rawFrameString);
    if (frame == null) return null;
    return ingestFrame(frame);
  }

  /// Ingests a deserialized QrChunkFrame.
  QrReconstructionProgress ingestFrame(QrChunkFrame frame) {
    // If a new transfer ID is received, reset state
    if (_activeTransferId == null || _activeTransferId != frame.transferId) {
      _activeTransferId = frame.transferId;
      _totalExpected = frame.totalChunks;
      _chunks.clear();
    }

    // Record chunk
    _chunks[frame.chunkIndex] = frame.payloadBase64;

    return getProgress();
  }

  /// Calculates current progress and list of missing indices.
  QrReconstructionProgress getProgress() {
    if (_activeTransferId == null || _totalExpected == 0) {
      return const QrReconstructionProgress(
        transferId: '',
        receivedCount: 0,
        totalExpected: 0,
        progressFraction: 0.0,
        missingChunkIndices: [],
        isComplete: false,
      );
    }

    final missing = <int>[];
    for (int i = 0; i < _totalExpected; i++) {
      if (!_chunks.containsKey(i)) {
        missing.add(i);
      }
    }

    final fraction = _totalExpected > 0 ? (_chunks.length / _totalExpected).clamp(0.0, 1.0) : 0.0;

    return QrReconstructionProgress(
      transferId: _activeTransferId!,
      receivedCount: _chunks.length,
      totalExpected: _totalExpected,
      progressFraction: fraction,
      missingChunkIndices: missing,
      isComplete: isComplete,
    );
  }

  /// Assembles and decodes the final payload once all chunks have arrived.
  /// Returns null if incomplete or if decoding fails.
  String? assemblePayload() {
    if (!isComplete) return null;

    final buffer = StringBuffer();
    for (int i = 0; i < _totalExpected; i++) {
      final chunkData = _chunks[i];
      if (chunkData == null) return null;
      buffer.write(chunkData);
    }

    try {
      final fullBase64 = buffer.toString();
      final bytes = base64.decode(fullBase64);
      return utf8.decode(bytes);
    } catch (_) {
      return null;
    }
  }

  /// Resets the reconstructor state for a fresh transfer.
  void reset() {
    _activeTransferId = null;
    _totalExpected = 0;
    _chunks.clear();
  }
}
