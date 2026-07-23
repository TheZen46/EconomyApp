import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_theme.dart';
import '../providers/receipt_provider.dart';
import '../../../settings/presentation/providers/taxonomy_provider.dart';

enum ScanState { idle, capturing, analyzing }

class ScanPage extends ConsumerStatefulWidget {
  const ScanPage({super.key});

  @override
  ConsumerState<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends ConsumerState<ScanPage> with SingleTickerProviderStateMixin {
  ScanState _scanState = ScanState.idle;
  final ImagePicker _picker = ImagePicker();
  
  // For the hex counter animation
  Timer? _hexTimer;
  String _hexCounter = '0x000000';
  final Random _random = Random();
  
  // Animation controller for the analyzing scanner
  late final AnimationController _scannerController;

  @override
  void initState() {
    super.initState();
    _scannerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
  }

  @override
  void dispose() {
    _hexTimer?.cancel();
    _scannerController.dispose();
    super.dispose();
  }

  void _startHexCounter() {
    _hexTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (mounted) {
        setState(() {
          _hexCounter = '0x${_random.nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
        });
      }
    });
  }

  void _stopHexCounter() {
    _hexTimer?.cancel();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(source: source);
      if (image == null) {
        if (mounted) {
          setState(() {
            _scanState = ScanState.idle;
          });
        }
        return;
      }

      if (mounted) {
        setState(() {
          _scanState = ScanState.analyzing;
        });
        _startHexCounter();
        _scannerController.repeat();
      }

      final repository = ref.read(receiptRepositoryProvider);
      final taxonomy = ref.read(taxonomyProvider);
      final result = await repository.processReceiptImage(image.path, taxonomy: taxonomy);

      if (!mounted) return;

      _stopHexCounter();
      _scannerController.stop();

      result.fold(
        (failure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: ${failure.message}'),
              backgroundColor: AppTheme.error,
            ),
          );
          setState(() {
            _scanState = ScanState.idle;
          });
        },
        (receipt) {
          context.push('/review', extra: receipt);
          // Optional: reset state if user comes back
          setState(() {
            _scanState = ScanState.idle;
          });
        },
      );
    } catch (e) {
      if (!mounted) return;
      _stopHexCounter();
      _scannerController.stop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unexpected error: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
      setState(() {
        _scanState = ScanState.idle;
      });
    }
  }

  Future<void> _handleCapture() async {
    setState(() => _scanState = ScanState.capturing);
    await Future.delayed(const Duration(milliseconds: 200));
    await _pickImage(ImageSource.camera);
  }

  Future<void> _handleGallery() async {
    await _pickImage(ImageSource.gallery);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF050505) : const Color(0xFFF0F0F0);
    final accentColor = const Color(0xFF002FA7);
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF1A1A1A);

    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background Ghost Text
          Center(
            child: Text(
              'VISION',
              style: GoogleFonts.spaceGrotesk(
                fontSize: MediaQuery.of(context).size.width * 0.3,
                fontWeight: FontWeight.bold,
                height: 1.0,
                color: textColor.withOpacity(0.03),
                letterSpacing: -0.05,
              ),
              maxLines: 1,
              overflow: TextOverflow.clip,
            ),
          ),

          // Side HUD Data (absolute right)
          Positioned(
            right: 24,
            top: MediaQuery.of(context).size.height * 0.3,
            child: RotatedBox(
              quarterTurns: 1,
              child: Text(
                'LENS / 24MM   ISO / 400   FORMAT / RAW',
                style: GoogleFonts.jetBrainsMono(
                  color: textColor.withOpacity(0.5),
                  fontSize: 12,
                  letterSpacing: 2,
                ),
              ),
            ),
          ),

          // Main Viewfinder
          Center(
            child: _buildViewfinder(accentColor, textColor),
          ),

          // Header HUD
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 24,
            right: 24,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildBackButton(textColor),
                _buildHeaderLabel(accentColor, textColor),
              ],
            ),
          ),

          // Footer Controls
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 32,
            left: 24,
            right: 24,
            child: _buildFooterControls(accentColor, textColor),
          ),

          // Capturing Flash Overlay
          if (_scanState == ScanState.capturing)
            Container(
              color: Colors.white,
            ).animate().fadeOut(duration: const Duration(milliseconds: 300)),
        ],
      ),
    );
  }

  Widget _buildBackButton(Color textColor) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: textColor.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: Icon(Icons.close, color: textColor),
            onPressed: () => context.pop(),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderLabel(Color accentColor, Color textColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          'AI Optical Engine',
          style: GoogleFonts.spaceGrotesk(
            color: textColor,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: accentColor,
                shape: BoxShape.circle,
              ),
            ).animate(onPlay: (controller) => controller.repeat(reverse: true))
             .fade(duration: const Duration(milliseconds: 800)),
            const SizedBox(width: 6),
            Text(
              'Active',
              style: GoogleFonts.jetBrainsMono(
                color: accentColor,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildViewfinder(Color accentColor, Color textColor) {
    final maxWidth = min(MediaQuery.of(context).size.width - 48, 400.0);
    final maxHeight = maxWidth * (4 / 3);

    return Container(
      width: maxWidth,
      height: maxHeight,
      child: Stack(
        children: [
          // Corner Brackets
          _buildCornerBrackets(textColor),

          // Crosshair
          Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(width: 40, height: 1, color: textColor.withOpacity(0.3)),
                Container(width: 1, height: 40, color: textColor.withOpacity(0.3)),
              ],
            ),
          ),

          // Animated States
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 500),
            child: _scanState == ScanState.analyzing
                ? _buildAnalyzingState(accentColor, textColor)
                : _buildIdleState(accentColor, textColor),
          ),
        ],
      ),
    );
  }

  Widget _buildIdleState(Color accentColor, Color textColor) {
    return Container(
      key: const ValueKey('idle'),
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(
          color: accentColor.withOpacity(0.5),
          width: 2,
          style: BorderStyle.solid,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.document_scanner_outlined, color: accentColor, size: 48)
                .animate(onPlay: (controller) => controller.repeat(reverse: true))
                .moveY(begin: -5, end: 5, duration: const Duration(seconds: 1)),
            const SizedBox(height: 16),
            Text(
              'Align Document',
              style: GoogleFonts.spaceGrotesk(
                color: textColor.withOpacity(0.8),
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalyzingState(Color accentColor, Color textColor) {
    return Container(
      key: const ValueKey('analyzing'),
      child: Stack(
        children: [
          // Laser Scanner
          AnimatedBuilder(
            animation: _scannerController,
            builder: (context, child) {
              return Positioned(
                top: _scannerController.value * (MediaQuery.of(context).size.width * (4 / 3) - 200),
                left: 0,
                right: 0,
                child: Container(
                  height: 100,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        accentColor.withOpacity(0.0),
                        accentColor.withOpacity(0.3),
                        accentColor.withOpacity(0.8),
                      ],
                      stops: const [0.0, 0.8, 1.0],
                    ),
                  ),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      height: 2,
                      decoration: BoxDecoration(
                        color: accentColor,
                        boxShadow: [
                          BoxShadow(
                            color: accentColor,
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          
          // Data Overlay
          Positioned(
            top: 32,
            left: 32,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'EXTRACTING DATA',
                  style: GoogleFonts.spaceGrotesk(
                    color: accentColor,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ).animate(onPlay: (c) => c.repeat()).shimmer(duration: const Duration(seconds: 2)),
                const SizedBox(height: 8),
                Text(
                  _hexCounter,
                  style: GoogleFonts.jetBrainsMono(
                    color: textColor.withOpacity(0.7),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          
          // Floating Labels
          Positioned(
            bottom: 64,
            right: 32,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: textColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: accentColor.withOpacity(0.5)),
              ),
              child: Text(
                'MERCHANT DETECTED',
                style: GoogleFonts.jetBrainsMono(
                  color: textColor,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ).animate(onPlay: (c) => c.repeat(reverse: true))
             .fadeIn(duration: const Duration(milliseconds: 500))
             .moveY(begin: 5, end: -5, duration: const Duration(seconds: 2)),
          ),
          Positioned(
            bottom: 32,
            left: 32,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: accentColor),
              ),
              child: Text(
                'TOTAL: \$X.XX',
                style: GoogleFonts.jetBrainsMono(
                  color: accentColor,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ).animate(onPlay: (c) => c.repeat(reverse: true))
             .fadeIn(duration: const Duration(milliseconds: 700))
             .moveY(begin: -5, end: 5, duration: const Duration(seconds: 2, milliseconds: 200)),
          ),
        ],
      ),
    );
  }

  Widget _buildCornerBrackets(Color textColor) {
    final size = 30.0;
    final strokeWidth = 2.0;
    final color = textColor.withOpacity(0.5);

    return Stack(
      children: [
        // Top Left
        Positioned(
          top: 0,
          left: 0,
          child: CustomPaint(
            size: Size(size, size),
            painter: _BracketPainter(color, strokeWidth, Alignment.topLeft),
          ),
        ),
        // Top Right
        Positioned(
          top: 0,
          right: 0,
          child: CustomPaint(
            size: Size(size, size),
            painter: _BracketPainter(color, strokeWidth, Alignment.topRight),
          ),
        ),
        // Bottom Left
        Positioned(
          bottom: 0,
          left: 0,
          child: CustomPaint(
            size: Size(size, size),
            painter: _BracketPainter(color, strokeWidth, Alignment.bottomLeft),
          ),
        ),
        // Bottom Right
        Positioned(
          bottom: 0,
          right: 0,
          child: CustomPaint(
            size: Size(size, size),
            painter: _BracketPainter(color, strokeWidth, Alignment.bottomRight),
          ),
        ),
      ],
    );
  }

  Widget _buildFooterControls(Color accentColor, Color textColor) {
    if (_scanState == ScanState.analyzing) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Processing Neural Graph',
            style: GoogleFonts.spaceGrotesk(
              color: textColor,
              fontWeight: FontWeight.w500,
              letterSpacing: 1.2,
            ),
          ).animate(onPlay: (c) => c.repeat(reverse: true)).fadeIn(duration: const Duration(seconds: 1)),
          const SizedBox(height: 16),
          Container(
            height: 2,
            width: 100,
            decoration: BoxDecoration(
              color: accentColor,
              boxShadow: [
                BoxShadow(color: accentColor.withOpacity(0.5), blurRadius: 8, spreadRadius: 2),
              ],
            ),
          ).animate(onPlay: (c) => c.repeat()).scaleX(begin: 0.5, end: 1.5, duration: const Duration(seconds: 1)),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          onPressed: _handleGallery,
          icon: Icon(Icons.photo_library, color: textColor.withOpacity(0.8), size: 32),
        ),
        GestureDetector(
          onTap: _handleCapture,
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: accentColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: accentColor.withOpacity(0.3),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: accentColor, width: 2),
                  ),
                ),
                // Rotating dashed ring
                CustomPaint(
                  size: const Size(72, 72),
                  painter: _DashedRingPainter(Colors.white.withOpacity(0.5)),
                ).animate(onPlay: (c) => c.repeat()).rotate(duration: const Duration(seconds: 4)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 48), // Spacer to balance gallery button
      ],
    );
  }
}

class _BracketPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final Alignment alignment;

  _BracketPainter(this.color, this.strokeWidth, this.alignment);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final path = Path();

    if (alignment == Alignment.topLeft) {
      path.moveTo(0, size.height);
      path.lineTo(0, 0);
      path.lineTo(size.width, 0);
    } else if (alignment == Alignment.topRight) {
      path.moveTo(0, 0);
      path.lineTo(size.width, 0);
      path.lineTo(size.width, size.height);
    } else if (alignment == Alignment.bottomLeft) {
      path.moveTo(0, 0);
      path.lineTo(0, size.height);
      path.lineTo(size.width, size.height);
    } else if (alignment == Alignment.bottomRight) {
      path.moveTo(size.width, 0);
      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DashedRingPainter extends CustomPainter {
  final Color color;

  _DashedRingPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final radius = size.width / 2;
    final center = Offset(size.width / 2, size.height / 2);
    
    final dashCount = 20;
    final dashSweepAngle = (2 * pi) / (dashCount * 2);

    for (int i = 0; i < dashCount; i++) {
      final startAngle = i * 2 * dashSweepAngle;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        dashSweepAngle,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
