import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/llm_provider.dart';

class DatasetExportDialog extends ConsumerStatefulWidget {
  const DatasetExportDialog({super.key});

  @override
  ConsumerState<DatasetExportDialog> createState() => _DatasetExportDialogState();
}

class _DatasetExportDialogState extends ConsumerState<DatasetExportDialog> {
  int _sampleCount = 0;
  int _sizeBytes = 0;
  bool _isLoading = true;
  bool _isCopied = false;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final service = ref.read(datasetContributionServiceProvider);
    final count = await service.getSampleCount();
    final bytes = await service.getTotalSizeBytes();

    if (mounted) {
      setState(() {
        _sampleCount = count;
        _sizeBytes = bytes;
        _isLoading = false;
      });
    }
  }

  Future<void> _exportToClipboard() async {
    final service = ref.read(datasetContributionServiceProvider);
    final content = await service.exportJsonlContent();
    if (content.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: content));
      if (mounted) {
        setState(() => _isCopied = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dataset JSONL copied to clipboard! 📋'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) setState(() => _isCopied = false);
        });
      }
    }
  }

  Future<void> _clearDataset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF13131A),
        title: Text(
          'Clear Continuous Learning Corpus?',
          style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'This will permanently delete all locally staged training samples.',
          style: GoogleFonts.spaceGrotesk(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4183D)),
            child: const Text('PURGE', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final service = ref.read(datasetContributionServiceProvider);
      await service.clearStagedData();
      await _loadStats();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Staged dataset cleared.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sizeKb = (_sizeBytes / 1024).toStringAsFixed(1);

    return Dialog(
      backgroundColor: const Color(0xFF0D0D12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFF002FA7), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF002FA7).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.school_outlined, color: Color(0xFF38BDF8), size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CONTINUOUS LEARNING CORPUS',
                        style: GoogleFonts.spaceGrotesk(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      ),
                      Text(
                        'HuggingFace QLoRA JSONL Export',
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
            const SizedBox(height: 20),

            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(color: Color(0xFF002FA7)),
                ),
              )
            else ...[
              // Stats Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF13131A),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        Text(
                          'STAGED SAMPLES',
                          style: GoogleFonts.spaceGrotesk(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$_sampleCount',
                          style: GoogleFonts.jetBrainsMono(
                            color: const Color(0xFF10B981),
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    Container(width: 1, height: 36, color: Colors.white12),
                    Column(
                      children: [
                        Text(
                          'CORPUS SIZE',
                          style: GoogleFonts.spaceGrotesk(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$sizeKb KB',
                          style: GoogleFonts.jetBrainsMono(
                            color: const Color(0xFF38BDF8),
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Privacy Redaction Guarantee Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.shield_outlined, color: Color(0xFF10B981), size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '100% PII Scrubbed (Emails, IBANs, Cards & Addresses Redacted)',
                        style: GoogleFonts.spaceGrotesk(
                          color: const Color(0xFF10B981),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Actions
              ElevatedButton.icon(
                onPressed: _sampleCount > 0 ? _exportToClipboard : null,
                icon: Icon(_isCopied ? Icons.check : Icons.copy, size: 16),
                label: Text(_isCopied ? 'DATASET COPIED!' : 'COPY JSONL CORPUS'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF002FA7),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 8),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: _sampleCount > 0 ? _clearDataset : null,
                    icon: const Icon(Icons.delete_sweep_outlined, size: 16, color: Color(0xFFD4183D)),
                    label: Text(
                      'Clear Staged',
                      style: GoogleFonts.spaceGrotesk(color: const Color(0xFFD4183D), fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'CLOSE',
                      style: GoogleFonts.spaceGrotesk(color: Colors.white54, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
