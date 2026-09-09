import 'dart:io';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/error_handler.dart';
import '../../../receipt_scanning/data/repositories/model_repository.dart';
import '../../../receipt_scanning/presentation/providers/receipt_provider.dart';
import '../providers/llm_provider.dart';

class ModelManagerPage extends ConsumerStatefulWidget {
  const ModelManagerPage({super.key});

  @override
  ConsumerState<ModelManagerPage> createState() => _ModelManagerPageState();
}

class _ModelManagerPageState extends ConsumerState<ModelManagerPage> {
  LocalModelInfo _selectedModel = LocalModelInfo.qwen2vl2b;
  bool _isChecking = true;
  bool _exists = false;
  bool _isLowMemoryTier = false;
  int _deviceRamMB = 0;
  String _modelPath = '';
  String _partPath = '';
  Directory? _modelDir;

  final List<LocalModelInfo> _availableModels = [
    LocalModelInfo.qwen2vl2b,
    LocalModelInfo.smolVlm500m,
    LocalModelInfo.gemma2b,
  ];

  @override
  void initState() {
    super.initState();
    _initDeviceAndModel();
  }

  Future<void> _initDeviceAndModel() async {
    _deviceRamMB = await DeviceMemoryHelper.getTotalRamMB();
    _isLowMemoryTier = await DeviceMemoryHelper.isLowMemoryDevice();
    _selectedModel = await DeviceMemoryHelper.getRecommendedModel();

    final dir = await getApplicationDocumentsDirectory();
    _modelDir = Directory('${dir.path}/models');
    if (!await _modelDir!.exists()) {
      await _modelDir!.create(recursive: true);
    }

    await _checkCurrentModel();
  }

  Future<void> _checkCurrentModel() async {
    if (_modelDir == null) return;

    _modelPath = '${_modelDir!.path}/${_selectedModel.fileName}';
    _partPath = '${_modelDir!.path}/${_selectedModel.fileName}.part';

    final modelFile = File(_modelPath);
    bool isValid = false;

    if (await modelFile.exists()) {
      final len = await modelFile.length();
      if (len > 0) {
        isValid = true;
      } else {
        await modelFile.delete();
      }
    }

    if (mounted) {
      setState(() {
        _exists = isValid;
        _isChecking = false;
      });
    }

    if (_exists) {
      final vlmSuccess = await ref.read(vlmEngineServiceProvider).initialize(
        modelPath: _modelPath,
      );
      if (mounted) {
        ref.read(isVlmReadyProvider.notifier).state = vlmSuccess;
      }
      await ref.read(llmServiceProvider).initialize();
      if (mounted) {
        ref.read(isLlmLoadedProvider.notifier).state =
            ref.read(llmServiceProvider).isModelLoaded || vlmSuccess;
      }
    } else {
      if (mounted) {
        ref.read(isVlmReadyProvider.notifier).state = false;
        ref.read(isLlmLoadedProvider.notifier).state = false;
      }
    }
  }

  Future<void> _selectModel(LocalModelInfo model) async {
    if (ref.read(isModelDownloadingProvider)) return;
    setState(() {
      _selectedModel = model;
      _isChecking = true;
    });
    await _checkCurrentModel();
  }

  Future<void> _downloadModel() async {
    if (_modelDir == null) return;

    ref.read(isModelDownloadingProvider.notifier).state = true;
    ref.read(modelDownloadProgressProvider.notifier).state = 0.0;
    ref.read(modelDownloadSpeedProvider.notifier).state = '';
    ref.read(modelDownloadEtaProvider.notifier).state = '';
    ref.read(isModelVerifyingProvider.notifier).state = false;

    final repo = ref.read(modelRepositoryProvider);
    final result = await repo.downloadModelWithResume(
      modelInfo: _selectedModel,
      destinationDirectory: _modelDir!,
      onProgress: (received, total) {
        if (total > 0 && mounted) {
          ref.read(modelDownloadProgressProvider.notifier).state =
              (received / total).clamp(0.0, 1.0);
        }
      },
      onSpeedAndEta: (speed, eta) {
        if (mounted) {
          ref.read(modelDownloadSpeedProvider.notifier).state = speed;
          ref.read(modelDownloadEtaProvider.notifier).state = eta;
        }
      },
      onVerifying: (isVerifying) {
        if (mounted) {
          ref.read(isModelVerifyingProvider.notifier).state = isVerifying;
        }
      },
    );

    if (result.isRight()) {
      await ref.read(llmServiceProvider).initialize();
      if (mounted) {
        ref.read(isLlmLoadedProvider.notifier).state = true;
        await _checkCurrentModel();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_selectedModel.name} Downloaded and SHA-256 Verified! 🧠'),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    } else {
      final failure = (result as Left<Failure, File>).value;
      if (mounted) {
        final message = failure is ModelValidationFailure
            ? 'Integrity Error: ${failure.message}'
            : 'Download Failed: ${failure.message}';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }

    if (mounted) {
      ref.read(isModelDownloadingProvider.notifier).state = false;
      ref.read(isModelVerifyingProvider.notifier).state = false;
    }
  }

  Future<void> _deleteModel() async {
    try {
      final file = File(_modelPath);
      if (await file.exists()) {
        await file.delete();
      }
      final partFile = File(_partPath);
      if (await partFile.exists()) {
        await partFile.delete();
      }

      await ref.read(vlmEngineServiceProvider).unload();
      ref.read(llmServiceProvider).unload();
      await _checkCurrentModel();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Model weights removed from local disk.')),
        );
      }
    } catch (e) {
      debugPrint('ModelManager: Failed to delete model: $e');
      if (mounted) {
        ErrorHandler.showErrorSnackBar(
          context: context,
          error: e,
          actionLabel: 'Retry',
          onAction: _deleteModel,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDownloading = ref.watch(isModelDownloadingProvider);
    final progress = ref.watch(modelDownloadProgressProvider);
    final speed = ref.watch(modelDownloadSpeedProvider);
    final eta = ref.watch(modelDownloadEtaProvider);
    final isVerifying = ref.watch(isModelVerifyingProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0E),
      appBar: AppBar(
        title: Text(
          'AI NEURAL CORE MANAGER',
          style: GoogleFonts.spaceGrotesk(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            fontSize: 16,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _isChecking
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF002FA7)))
          : ListView(
              padding: const EdgeInsets.all(20.0),
              children: [
                _buildDeviceHardwareCard(),
                const SizedBox(height: 20),
                _buildModelSelector(isDownloading),
                const SizedBox(height: 20),
                _buildActiveModelCard(
                  isDownloading: isDownloading,
                  progress: progress,
                  speed: speed,
                  eta: eta,
                  isVerifying: isVerifying,
                ),
              ],
            ),
    );
  }

  Widget _buildDeviceHardwareCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF13131A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF002FA7).withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.memory, color: Color(0xFF38BDF8), size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'HARDWARE MEMORY TIER',
                  style: GoogleFonts.spaceGrotesk(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _deviceRamMB > 0
                      ? 'Detected Physical RAM: ~${(_deviceRamMB / 1024).toStringAsFixed(1)} GB'
                      : 'Physical Memory Profile: Standard',
                  style: GoogleFonts.jetBrainsMono(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isLowMemoryTier
                      ? '⚡ Low-Memory device. SmolVLM-500M recommended to avoid OOM.'
                      : '🚀 Standard device. Qwen2-VL 2B fully supported.',
                  style: TextStyle(
                    color: _isLowMemoryTier ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModelSelector(bool isDownloading) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'AVAILABLE NEURAL MODELS',
          style: GoogleFonts.spaceGrotesk(
            color: Colors.white.withOpacity(0.6),
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        ..._availableModels.map((model) {
          final isSelected = model.id == _selectedModel.id;
          final isRecommended = (_isLowMemoryTier && model.id == LocalModelInfo.smolVlm500m.id) ||
              (!_isLowMemoryTier && model.id == LocalModelInfo.qwen2vl2b.id);

          return Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: InkWell(
              onTap: isDownloading ? null : () => _selectModel(model),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF181824) : const Color(0xFF101016),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected ? const Color(0xFF002FA7) : Colors.white.withOpacity(0.06),
                    width: isSelected ? 1.5 : 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                      color: isSelected ? const Color(0xFF38BDF8) : Colors.white24,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                model.name,
                                style: GoogleFonts.spaceGrotesk(
                                  color: isSelected ? Colors.white : Colors.white70,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              if (isRecommended) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981).withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'RECOMMENDED',
                                    style: GoogleFonts.jetBrainsMono(
                                      color: const Color(0xFF10B981),
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            model.sizeLabel,
                            style: GoogleFonts.jetBrainsMono(
                              color: Colors.white38,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildActiveModelCard({
    required bool isDownloading,
    required double progress,
    required String speed,
    required String eta,
    required bool isVerifying,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF13131A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _exists ? const Color(0xFF10B981).withOpacity(0.4) : const Color(0xFFF59E0B).withOpacity(0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                _exists ? Icons.check_circle : Icons.cloud_download,
                color: _exists ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _exists ? 'ACTIVE NEURAL WEIGHTS READY' : 'MODEL WEIGHTS PENDING',
                      style: GoogleFonts.spaceGrotesk(
                        color: _exists ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 1.0,
                      ),
                    ),
                    Text(
                      _selectedModel.fileName,
                      style: GoogleFonts.jetBrainsMono(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (isDownloading) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: Colors.white.withOpacity(0.08),
                valueColor: const AlwaysStoppedAnimation(Color(0xFF002FA7)),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${(progress * 100).toStringAsFixed(1)}% (${speed.isNotEmpty ? speed : "--"})',
                  style: GoogleFonts.jetBrainsMono(
                    color: const Color(0xFF38BDF8),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  eta.isNotEmpty ? 'ETA: $eta' : (isVerifying ? 'VERIFYING SHA-256...' : 'STREAMING GGUF'),
                  style: GoogleFonts.jetBrainsMono(
                    color: isVerifying ? const Color(0xFFF59E0B) : Colors.white38,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (isVerifying)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFF59E0B)),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Validating SHA-256 Checksum...',
                      style: GoogleFonts.jetBrainsMono(color: const Color(0xFFF59E0B), fontSize: 11),
                    ),
                  ],
                ),
              ),
          ] else if (_exists) ...[
            Text(
              'Zero-copy memory mapping active. All receipt inference executes on-device with zero cloud roundtrips.',
              style: GoogleFonts.spaceGrotesk(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _deleteModel,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('PURGE WEIGHTS TO FREE SPACE'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD4183D).withOpacity(0.15),
                foregroundColor: const Color(0xFFD4183D),
                side: const BorderSide(color: Color(0xFFD4183D), width: 0.8),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ] else ...[
            Text(
              'Download the quantized neural brain to enable fully private, offline receipt processing.',
              style: GoogleFonts.spaceGrotesk(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _downloadModel,
              icon: const Icon(Icons.download, size: 18),
              label: Text('DOWNLOAD ${_selectedModel.name.toUpperCase()}'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF002FA7),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
