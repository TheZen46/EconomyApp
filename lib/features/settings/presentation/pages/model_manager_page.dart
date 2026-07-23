// ignore_for_file: deprecated_member_use, deprecated_member_use_from_same_package, unused_local_variable, unnecessary_underscores, invalid_annotation_target, unused_element, non_constant_identifier_names, use_build_context_synchronously
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/llm_provider.dart';

class ModelManagerPage extends ConsumerStatefulWidget {
  const ModelManagerPage({super.key});

  @override
  ConsumerState<ModelManagerPage> createState() => _ModelManagerPageState();
}

class _ModelManagerPageState extends ConsumerState<ModelManagerPage> {
  bool _isChecking = true;
  bool _exists = false;
  String _modelPath = '';

  @override
  void initState() {
    super.initState();
    _checkModel();
  }

  Future<void> _checkModel() async {
    final dir = await getApplicationDocumentsDirectory();
    final modelDir = Directory('${dir.path}/models');
    if (!await modelDir.exists()) {
      await modelDir.create(recursive: true);
    }
    _modelPath = '${modelDir.path}/gemma-2b-it-q4_k_m.gguf';
    setState(() {
      _exists = File(_modelPath).existsSync();
      _isChecking = false;
    });

    if (_exists) {
      // Auto-load if exists
      await ref.read(llmServiceProvider).initialize();
      if (mounted) {
         ref.read(isLlmLoadedProvider.notifier).state = ref.read(llmServiceProvider).isModelLoaded;
      }
    } else {
       if (mounted) {
         ref.read(isLlmLoadedProvider.notifier).state = false;
       }
    }
  }

  Future<void> _downloadModel() async {
    ref.read(isModelDownloadingProvider.notifier).state = true;
    final dio = Dio();
    
    try {
      await dio.download(
        'https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf?download=true',
        _modelPath,
        onReceiveProgress: (rec, total) {
           if (total != -1) {
             ref.read(modelDownloadProgressProvider.notifier).state = rec / total;
           }
        }
      );
      
      // Init service after download
      await ref.read(llmServiceProvider).initialize();
      ref.read(isLlmLoadedProvider.notifier).state = true;
      
      if (mounted) {
        _checkModel();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Model Downloaded Successfully! 🧠')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download Failed: $e'), backgroundColor: AppTheme.error));
      }
    } finally {
      ref.read(isModelDownloadingProvider.notifier).state = false;
    }
  }

  Future<void> _deleteModel() async {
    try {
      if (File(_modelPath).existsSync()) {
        await File(_modelPath).delete();
        // Unload service
        ref.read(llmServiceProvider).unload();
        _checkModel();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Model Deleted')));
        }
      }
    } catch (e) {
       // Ignore
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
                  LinearProgressIndicator(value: progress, minHeight: 10, borderRadius: BorderRadius.circular(5)),
                  const SizedBox(height: 8),
                  Text('${(progress * 100).toStringAsFixed(1)}%', textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.textDim)),
                  const SizedBox(height: 24),
                  const Text('Creating neural pathways... please wait.', textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textDim, fontStyle: FontStyle.italic)),
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
                    'Your local AI is ready. Receipts will now be processed privately on your device.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.secondary),
                  ),
                ] else ...[
                  const Text(
                    'To enable Privacy-First Scanning, you need to download the AI Model (Gemma 2B).',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.textMain),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Size: ~1.6 GB\nRecommendation: Use Wi-Fi',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.textDim),
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
        border: Border.all(color: _exists ? AppTheme.secondary : Colors.red, width: 1),
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
            _exists ? 'TinyLlama 1.1B Quantized' : 'No local model found.',
            style: const TextStyle(color: AppTheme.textDim),
          ),
        ],
      ),
    );
  }
}
