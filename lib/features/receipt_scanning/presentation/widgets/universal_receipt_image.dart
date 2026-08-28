import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Universal widget capable of resolving and displaying receipt images regardless
/// of where they originate:
/// - Absolute device storage path (Android / iOS / Desktop)
/// - Relative sandbox paths or replicated filenames in Documents directory
/// - Direct HTTP / HTTPS URLs (e.g. Supabase Storage public CDN or S3)
/// - Supabase relative storage paths (e.g. `training_data/<userId>/images/<uuid>.jpg` or `<userId>/images/<uuid>.jpg`)
/// - Inferred remote paths via [receiptId]
class UniversalReceiptImage extends StatefulWidget {
  final String? imagePath;
  final String? receiptId;
  final BoxFit fit;
  final Alignment alignment;
  final Color? color;
  final BlendMode? colorBlendMode;
  final Widget Function(BuildContext, Object, StackTrace?)? errorBuilder;
  final Widget? placeholder;

  const UniversalReceiptImage({
    super.key,
    required this.imagePath,
    this.receiptId,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.color,
    this.colorBlendMode,
    this.errorBuilder,
    this.placeholder,
  });

  @override
  State<UniversalReceiptImage> createState() => _UniversalReceiptImageState();
}

class _UniversalReceiptImageState extends State<UniversalReceiptImage> {
  String? _resolvedHttpUrl;
  File? _resolvedLocalFile;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _resolveImage();
  }

  @override
  void didUpdateWidget(covariant UniversalReceiptImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imagePath != widget.imagePath || oldWidget.receiptId != widget.receiptId) {
      _resolveImage();
    }
  }

  Future<void> _resolveImage() async {
    setState(() {
      _isLoading = true;
      _resolvedHttpUrl = null;
      _resolvedLocalFile = null;
    });

    final rawPath = widget.imagePath?.trim();

    // 1. Direct Web/Network URL
    if (rawPath != null && (rawPath.startsWith('http://') || rawPath.startsWith('https://') || rawPath.startsWith('blob:'))) {
      if (mounted) {
        setState(() {
          _resolvedHttpUrl = rawPath;
          _isLoading = false;
        });
      }
      return;
    }

    // 2. Check Local File on Native Platforms
    if (!kIsWeb && rawPath != null && rawPath.isNotEmpty) {
      try {
        final directFile = File(rawPath);
        if (directFile.existsSync() && directFile.lengthSync() > 0) {
          if (mounted) {
            setState(() {
              _resolvedLocalFile = directFile;
              _isLoading = false;
            });
          }
          return;
        }

        // Check if file exists under Application Documents Directory (replicated sandbox)
        final docsDir = await getApplicationDocumentsDirectory();
        final fileName = rawPath.split(RegExp(r'[/\\]')).last;
        final docFile = File('${docsDir.path}/$fileName');
        if (docFile.existsSync() && docFile.lengthSync() > 0) {
          if (mounted) {
            setState(() {
              _resolvedLocalFile = docFile;
              _isLoading = false;
            });
          }
          return;
        }
      } catch (e) {
        debugPrint('UniversalReceiptImage: Local file check error: $e');
      }
    }

    // 3. Resolve from Supabase Storage CDN URL
    final remoteUrl = _resolveSupabaseUrl(rawPath, widget.receiptId);
    if (remoteUrl != null) {
      if (mounted) {
        setState(() {
          _resolvedHttpUrl = remoteUrl;
          _isLoading = false;
        });
      }
      return;
    }

    // 4. Nothing resolved
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  String? _resolveSupabaseUrl(String? path, String? receiptId) {
    try {
      final client = Supabase.instance.client;
      String? currentUserId;
      try {
        currentUserId = client.auth.currentUser?.id;
      } catch (_) {}

      // Case A: Storage relative path provided
      if (path != null && path.isNotEmpty) {
        String cleanPath = path;
        String bucket = 'training_data';

        if (cleanPath.startsWith('training_data/')) {
          cleanPath = cleanPath.substring('training_data/'.length);
        } else if (cleanPath.startsWith('receipts/')) {
          cleanPath = cleanPath.substring('receipts/'.length);
          bucket = 'receipts';
        }

        // If it looks like a remote storage path
        if (cleanPath.contains('/images/') || cleanPath.endsWith('.jpg') || cleanPath.endsWith('.png') || cleanPath.endsWith('.jpeg')) {
          return client.storage.from(bucket).getPublicUrl(cleanPath);
        }
      }

      // Case B: Resolve using receiptId and current user
      if (receiptId != null && receiptId.isNotEmpty) {
        if (currentUserId != null && currentUserId.isNotEmpty) {
          return client.storage.from('training_data').getPublicUrl('$currentUserId/images/$receiptId.jpg');
        }
        return client.storage.from('training_data').getPublicUrl('images/$receiptId.jpg');
      }
    } catch (e) {
      debugPrint('UniversalReceiptImage: Supabase resolution notice: $e');
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return widget.placeholder ??
          Container(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
    }

    if (_resolvedLocalFile != null) {
      return Image.file(
        _resolvedLocalFile!,
        fit: widget.fit,
        alignment: widget.alignment,
        color: widget.color,
        colorBlendMode: widget.colorBlendMode,
        errorBuilder: (context, error, stackTrace) {
          // If local file failed, try remote fallback before giving up
          final remoteUrl = _resolveSupabaseUrl(widget.imagePath, widget.receiptId);
          if (remoteUrl != null) {
            return Image.network(
              remoteUrl,
              fit: widget.fit,
              alignment: widget.alignment,
              color: widget.color,
              colorBlendMode: widget.colorBlendMode,
              errorBuilder: widget.errorBuilder ?? _defaultFallback,
            );
          }
          return widget.errorBuilder?.call(context, error, stackTrace) ?? _defaultFallback(context, error, stackTrace);
        },
      );
    }

    if (_resolvedHttpUrl != null) {
      return Image.network(
        _resolvedHttpUrl!,
        fit: widget.fit,
        alignment: widget.alignment,
        color: widget.color,
        colorBlendMode: widget.colorBlendMode,
        errorBuilder: widget.errorBuilder ?? _defaultFallback,
      );
    }

    return _defaultFallback(context, 'No image source', null);
  }

  Widget _defaultFallback(BuildContext context, Object error, StackTrace? stackTrace) {
    if (widget.errorBuilder != null) {
      return widget.errorBuilder!(context, error, stackTrace);
    }
    final theme = Theme.of(context);
    return Container(
      color: theme.scaffoldBackgroundColor,
      alignment: Alignment.center,
      child: Icon(
        Icons.receipt_long_outlined,
        size: 48,
        color: theme.colorScheme.onSurfaceVariant.withOpacity(0.35),
      ),
    );
  }
}
