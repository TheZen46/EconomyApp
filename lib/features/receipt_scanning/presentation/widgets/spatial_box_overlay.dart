import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Spatial Bounding Box representation [ymin, xmin, ymax, xmax] (normalized 0.0 to 1.0)
class SpatialBox {
  final String label;
  final String category;
  final double ymin;
  final double xmin;
  final double ymax;
  final double xmax;
  final Color color;
  final String? value;

  const SpatialBox({
    required this.label,
    required this.category,
    required this.ymin,
    required this.xmin,
    required this.ymax,
    required this.xmax,
    required this.color,
    this.value,
  });
}

/// Interactive Spatial Bounding Box Overlay rendered on top of receipt images.
class SpatialBoxOverlay extends StatelessWidget {
  final String? imagePath;
  final Uint8List? imageBytes;
  final List<SpatialBox> boxes;
  final Function(SpatialBox)? onBoxSelected;
  final SpatialBox? selectedBox;
  final bool enableZoom;

  const SpatialBoxOverlay({
    super.key,
    this.imagePath,
    this.imageBytes,
    required this.boxes,
    this.onBoxSelected,
    this.selectedBox,
    this.enableZoom = true,
  });

  @override
  Widget build(BuildContext context) {
    Widget imageWidget;
    if (imageBytes != null) {
      imageWidget = Image.memory(imageBytes!, fit: BoxFit.contain);
    } else if (imagePath != null && imagePath!.isNotEmpty && !kIsWeb) {
      imageWidget = Image.file(File(imagePath!), fit: BoxFit.contain);
    } else {
      imageWidget = Container(
        color: const Color(0xFF13131A),
        child: const Center(
          child: Icon(Icons.receipt_long, color: Colors.white24, size: 64),
        ),
      );
    }

    final content = LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          fit: StackFit.expand,
          children: [
            // Receipt image background
            Center(child: imageWidget),

            // Spatial bounding box painter
            CustomPaint(
              size: Size(constraints.maxWidth, constraints.maxHeight),
              painter: _SpatialBoxPainter(
                boxes: boxes,
                selectedBox: selectedBox,
              ),
            ),

            // Interactive touch zones
            ...boxes.map((box) {
              final left = box.xmin * constraints.maxWidth;
              final top = box.ymin * constraints.maxHeight;
              final width = (box.xmax - box.xmin) * constraints.maxWidth;
              final height = (box.ymax - box.ymin) * constraints.maxHeight;

              return Positioned(
                left: left,
                top: top,
                width: width,
                height: height,
                child: GestureDetector(
                  onTap: () {
                    if (onBoxSelected != null) {
                      onBoxSelected!(box);
                    }
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              );
            }),
          ],
        );
      },
    );

    if (enableZoom) {
      return InteractiveViewer(
        maxScale: 4.0,
        minScale: 1.0,
        child: content,
      );
    }

    return content;
  }
}

class _SpatialBoxPainter extends CustomPainter {
  final List<SpatialBox> boxes;
  final SpatialBox? selectedBox;

  _SpatialBoxPainter({
    required this.boxes,
    this.selectedBox,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final box in boxes) {
      final isSelected = selectedBox?.label == box.label;
      final rect = Rect.fromLTRB(
        box.xmin * size.width,
        box.ymin * size.height,
        box.xmax * size.width,
        box.ymax * size.height,
      );

      final strokePaint = Paint()
        ..color = isSelected ? Colors.white : box.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected ? 2.5 : 1.5;

      final fillPaint = Paint()
        ..color = (isSelected ? box.color : box.color).withOpacity(isSelected ? 0.25 : 0.1)
        ..style = PaintingStyle.fill;

      // Draw box fill and outline
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));
      canvas.drawRRect(rrect, fillPaint);
      canvas.drawRRect(rrect, strokePaint);

      // Draw label badge
      final textSpan = TextSpan(
        text: box.value != null ? '${box.label}: ${box.value}' : box.label,
        style: GoogleFonts.jetBrainsMono(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.bold,
          backgroundColor: box.color.withOpacity(0.85),
        ),
      );

      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      final badgeTop = (rect.top - textPainter.height - 2).clamp(0.0, size.height);
      final badgeLeft = rect.left.clamp(0.0, size.width - textPainter.width);

      textPainter.paint(canvas, Offset(badgeLeft, badgeTop));
    }
  }

  @override
  bool shouldRepaint(covariant _SpatialBoxPainter oldDelegate) {
    return oldDelegate.boxes != boxes || oldDelegate.selectedBox != selectedBox;
  }
}
