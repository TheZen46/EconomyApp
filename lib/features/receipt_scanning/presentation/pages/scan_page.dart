import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../../core/theme/app_theme.dart';
import '../providers/receipt_provider.dart';
import '../widgets/neuromorphic_button.dart';
import '../../../settings/presentation/providers/taxonomy_provider.dart';

class ScanPage extends ConsumerStatefulWidget {
  const ScanPage({super.key});

  @override
  ConsumerState<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends ConsumerState<ScanPage> {
  bool _isProcessing = false;
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(source: source);
      if (image == null) return;

      setState(() {
        _isProcessing = true;
      });

      // Use the repository via the provider
      final repository = ref.read(receiptRepositoryProvider);
      final taxonomy = ref.read(taxonomyProvider);
      final result = await repository.processReceiptImage(image.path, taxonomy: taxonomy);

      if (!mounted) return;

      result.fold(
        (failure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: ${failure.message}'),
              backgroundColor: AppTheme.error,
            ),
          );
        },
        (receipt) {
          context.push('/review', extra: receipt);
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unexpected error: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Receipt'),
        backgroundColor: Colors.transparent,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
             if (_isProcessing)
               const Column(
                 children: [
                   Text('AI is thinking...', style: TextStyle(color: AppTheme.primary, fontSize: 18)),
                   SizedBox(height: 32),
                 ],
               ).animate().fadeIn()
             else
               const Text(
                 'Tap to Scan', 
                 style: TextStyle(color: AppTheme.textDim, fontSize: 16)
               ).animate().fadeIn(),
             
             const SizedBox(height: 24),
             
             NeuromorphicScanButton(
               onPressed: () => _pickImage(ImageSource.camera),
               isProcessing: _isProcessing,
             ),
             
             const SizedBox(height: 48),
             
             TextButton.icon(
               onPressed: _isProcessing ? null : () => _pickImage(ImageSource.gallery),
               icon: const Icon(Icons.photo_library),
               label: const Text('Or pick from Gallery'),
               style: TextButton.styleFrom(
                 foregroundColor: AppTheme.textDim,
               ),
             ),
          ],
        ),
      ),
    );
  }
}
