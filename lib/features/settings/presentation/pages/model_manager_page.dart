import 'dart:io';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  final LocalModelInfo _modelInfo = LocalModelInfo.gemma2b;
  bool _isChecking = true;
  bool _exists = false;
  String _modelPath = '';
  String _partPath = '';
  Directory? _modelDir;

  @override
  void initState() {
    super.initState();
    _checkModel();
  }

  Future<void> _checkModel() async {
    final dir = await getApplicationDocumentsDirectory();
    _modelDir = Directory('${dir.path}/models');
    if (!await _modelDir!.exists()) {
      await _modelDir!.create(recursive: true);
    }
    _modelPath = '${_modelDir!.path}/${_modelInfo.fileName}';
    _partPath = '${_modelDir!.path}/${_modelInfo.fileName}.part';

    final modelFile = File(_modelPath);
    bool isValid = false;

    if (await modelFile.exists()) {
      final len = await modelFile.length();
      if (len > 0) {
        isValid = true;
      } else {
        // Purge 0-byte corrupt file
        await modelFile.delete();
      }
    }

    setState(() {
      _exists = isValid;
      _isChecking = false;
    });

    if (_exists) {
      // Auto-load if exists
      await ref.read(llmServiceProvider).initialize();
      if (mounted) {
        ref.read(isLlmLoadedProvider.notifier).state =
            ref.read(llmServiceProvider).isModelLoaded;
      }
    } else {
      if (mounted) {
        ref.read(isLlmLoadedProvider.notifier).state = false;
      }
    }
  }

  Future<void> _downloadModel() async {
    if (_modelDir == null) return;

    ref.read(isModelDownloadingProvider.notifier).state = true;
    ref.read(modelDownloadProgressProvider.notifier).state = 0.0;

    final repo = ref.read(modelRepositoryProvider);
    final result = await repo.downloadModelWithResume(
      modelInfo: _modelInfo,
      destinationDirectory: _modelDir!,
      onProgress: (received, total) {
        if (total > 0 && mounted) {
          ref.read(modelDownloadProgressProvider.notifier).state =
              (received / total).clamp(0.0, 1.0);
        }
      },
    );

    if (result.isRight()) {
      await ref.read(llmServiceProvider).initialize();
      if (mounted) {
        ref.read(isLlmLoadedProvider.notifier).state = true;
        await _checkModel();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Model Downloaded and Verified! 🧠')),
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

      // Unload service
      ref.read(llmServiceProvider).unload();
      await _checkModel();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Model Deleted')),
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Brain Manager 🧠'),
        backgroundColor: Colors.transparent,
      ),
      body: _isChecking
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildStatusCard(),
                  const SizedBox(height: 32),
                  if (isDownloading) ...[
                    LinearProgressIndicator(
                      value: progress,
                      minHeight: 10,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${(progress * 100).toStringAsFixed(1)}%',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppTheme.textDim),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Creating neural pathways... please wait.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: AppTheme.textDim, fontStyle: FontStyle.italic),
                    ),
                  ] else if (_exists) ...[
                    ElevatedButton.icon(
                      onPressed: _deleteModel,
                      icon: const Icon(Icons.delete),
                      label: const Text('Delete Model (Free Space)'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.error.withAlpha(51),
                        foregroundColor: AppTheme.error,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Your local AI is ready. Receipts will now be '
                      'processed privately on your device.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.secondary),
                    ),
                  ] else ...[
                    Text(
                      'To enable Privacy-First Scanning, you need to '
                      'download the AI Model (${_modelInfo.name}).',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppTheme.textMain),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Size: ${_modelInfo.sizeLabel}\nRecommendation: Use Wi-Fi',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppTheme.textDim),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _downloadModel,
                      icon: const Icon(Icons.download),
                      label: const Text('Download Brain'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: AppTheme.background,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildStatusCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _exists ? const Color(0xFF1E293B) : Colors.red.withAlpha(25),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
            color: _exists ? AppTheme.secondary : Colors.red, width: 1),
      ),
      child: Column(
        children: [
          Icon(
            _exists ? Icons.check_circle : Icons.warning_amber_rounded,
            size: 48,
            color: _exists ? AppTheme.secondary : Colors.red,
          ),
          const SizedBox(height: 16),
          Text(
            _exists ? 'Brain Installed' : 'Brain Missing',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: _exists ? AppTheme.secondary : Colors.red,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _exists ? '${_modelInfo.name} (Q4_K_M)' : 'No local model found.',
            style: const TextStyle(color: AppTheme.textDim),
          ),
        ],
      ),
    );
  }
}
