import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_ml_kit/google_ml_kit.dart';

const smileThreshold = 3; // Should match the constant from home_screen

class FaceDetectionPainter extends CustomPainter {
  final List<Face> faces;
  final Map<int, dynamic>? trackedFaces;
  final Size imageSize;
  final CameraLensDirection cameraLensDirection;
  final bool showSnowEffect;

  FaceDetectionPainter({
    super.repaint,
    required this.faces,
    this.trackedFaces,
    required this.imageSize,
    required this.cameraLensDirection,
    this.showSnowEffect = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double scaleX = size.width / imageSize.width;
    final double scaleY = size.height / imageSize.height;

    // Different paints for different face states
    final Paint normalFacePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = Colors.green;

    final Paint smilingFacePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..color = showSnowEffect ? Colors.cyan : Colors.orange;

    final Paint triggeredFacePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0
      ..color = showSnowEffect ? Colors.lightBlue : Colors.red;

    final Paint landmarkPaint = Paint()
      ..style = PaintingStyle.fill
      ..strokeWidth = 3.0
      ..color = showSnowEffect ? Colors.lightBlue : Colors.blue;

    final Paint eyePaint = Paint()
      ..style = PaintingStyle.fill
      ..color = showSnowEffect ? Colors.cyan[100]! : Colors.cyan;

    final Paint mouthPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = showSnowEffect ? Colors.pinkAccent : Colors.pink;

    final Paint textBackgroundPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = showSnowEffect ? Colors.black.withOpacity(0.8) : Colors.black87;

    final Paint progressBackgroundPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.black54;

    for (var i = 0; i < faces.length; i++) {
      final Face face = faces[i];
      
      // Find corresponding tracked face data
      dynamic trackedFace;
      if (face.trackingId != null && trackedFaces != null && trackedFaces!.containsKey(face.trackingId)) {
        trackedFace = trackedFaces![face.trackingId];
      }

      // Calculate face position
      double leftOffset = face.boundingBox.left;
      if (cameraLensDirection == CameraLensDirection.front) {
        leftOffset = imageSize.width - face.boundingBox.right;
      }

      final double left = leftOffset * scaleX;
      final double top = face.boundingBox.top * scaleY;
      final double right = (leftOffset + face.boundingBox.width) * scaleX;
      final double bottom = (face.boundingBox.top + face.boundingBox.height) * scaleY;

      // Choose paint based on tracking state
      Paint facePaint = normalFacePaint;
      int smileFrames = 0;
      bool hasTriggered = false;

      if (trackedFace != null) {
        try {
          // Try to access properties safely
          smileFrames = trackedFace.smileConsecutiveFrames ?? 0;
          hasTriggered = trackedFace.hasTriggeredSmileSnap ?? false;
          
          if (hasTriggered) {
            facePaint = triggeredFacePaint;
          } else if (smileFrames > 0) {
            facePaint = smilingFacePaint;
          }
        } catch (e) {
          // Fallback to normal paint if properties don't exist
          facePaint = normalFacePaint;
        }
      }

      // Draw face bounding box
      canvas.drawRect(Rect.fromLTRB(left, top, right, bottom), facePaint);

      // Draw tracking ID if available
      if (face.trackingId != null) {
        final trackingIdSpan = TextSpan(
          text: 'ID: ${face.trackingId}',
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        );

        final trackingIdPainter = TextPainter(
          text: trackingIdSpan,
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
        );

        trackingIdPainter.layout();

        final trackingIdRect = Rect.fromLTWH(
          left,
          bottom + 5,
          trackingIdPainter.width + 8,
          trackingIdPainter.height + 4,
        );

        canvas.drawRRect(
          RRect.fromRectAndRadius(trackingIdRect, Radius.circular(8)),
          progressBackgroundPaint,
        );

        trackingIdPainter.paint(canvas, Offset(left + 4, bottom + 7));
      }

      // Draw landmarks
      void drawLandmark(FaceLandmarkType type, Paint paint) {
        if (face.landmarks[type] != null) {
          final point = face.landmarks[type]!.position;
          double pointX = point.x.toDouble();
          if (cameraLensDirection == CameraLensDirection.front) {
            pointX = imageSize.width - pointX;
          }

          canvas.drawCircle(
            Offset(pointX * scaleX, point.y * scaleY),
            4.0,
            paint,
          );
        }
      }

      // Draw eye landmarks
      drawLandmark(FaceLandmarkType.leftEye, eyePaint);
      drawLandmark(FaceLandmarkType.rightEye, eyePaint);
      
      // Draw nose landmark
      drawLandmark(FaceLandmarkType.noseBase, landmarkPaint);
      
      // Draw mouth landmarks
      drawLandmark(FaceLandmarkType.leftMouth, mouthPaint);
      drawLandmark(FaceLandmarkType.rightMouth, mouthPaint);
      drawLandmark(FaceLandmarkType.bottomMouth, mouthPaint);

      // Determine mood based on smile probability
      String mood = 'Netral 🐱';
      final smileProb = face.smilingProbability ?? 0;
      if (showSnowEffect && smileProb > 0.8) {
        mood = 'Tertawa dengan Salju ❄️😹';
      } else if (showSnowEffect && smileProb > 0.5) {
        mood = 'Senyum Dingin ❄️😄';
      } else if (smileProb > 0.8) {
        mood = 'Tertawa, Tapi Terluka 😹😹';
      } else if (smileProb > 0.5) {
        mood = 'Senyum 😄';
      } else if (smileProb < 0.1) {
        mood = showSnowEffect ? 'Beku Serius ❄️🥵' : 'Pura-Pura Serius 🥵';
      }

      // Add tracking info if available
      String displayText = 'Face ${i + 1}\n$mood';
      if (smileFrames > 0) {
        displayText += '\nSmile: $smileFrames/3';
        if (showSnowEffect) {
          displayText += ' ❄️';
        }
      }
      if (hasTriggered) {
        displayText += showSnowEffect ? '\n❄️✅ Snow Captured!' : '\n✅ Captured!';
      }

      final TextSpan faceIdSpan = TextSpan(
        text: displayText,
        style: TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      );

      final TextPainter textPainter = TextPainter(
        text: faceIdSpan,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );

      textPainter.layout();

      final textRect = Rect.fromLTWH(
        left,
        top - textPainter.height - 8,
        textPainter.width + 16,
        textPainter.height + 8,
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(textRect, Radius.circular(10)),
        textBackgroundPaint,
      );

      textPainter.paint(canvas, Offset(left + 8, top - textPainter.height - 4));

      // Draw snow indicators around smiling faces if snow effect is active
      if (showSnowEffect && smileFrames > 0) {
        _drawSnowIndicators(canvas, Rect.fromLTRB(left, top, right, bottom));
      }
    }
  }

  void _drawSnowIndicators(Canvas canvas, Rect faceRect) {
    final Paint snowIndicatorPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.white.withOpacity(0.8);

    // Draw snowflakes around the face
    final random = Random(42); // Fixed seed for consistent positioning
    for (int i = 0; i < 8; i++) {
      final angle = (i * 45) * (pi / 180); // 45 degrees apart
      final radius = max(faceRect.width, faceRect.height) * 0.6;
      
      final x = faceRect.center.dx + cos(angle) * radius;
      final y = faceRect.center.dy + sin(angle) * radius;
      
      // Draw snowflake shape
      _drawSnowflake(canvas, Offset(x, y), snowIndicatorPaint, 8.0);
    }
  }

  void _drawSnowflake(Canvas canvas, Offset center, Paint paint, double size) {
    // Draw a more complex snowflake with multiple lines
    for (int i = 0; i < 6; i++) {
      final angle = (i * 60) * (pi / 180);
      
      // Main line
      canvas.drawLine(
        Offset(center.dx + cos(angle) * size, center.dy + sin(angle) * size),
        Offset(center.dx - cos(angle) * size, center.dy - sin(angle) * size),
        paint..strokeWidth = 2.0,
      );
      
      // Side branches
      for (int j = 1; j <= 2; j++) {
        final branchLength = size * 0.3;
        final branchPoint = Offset(
          center.dx + cos(angle) * (size * j / 3),
          center.dy + sin(angle) * (size * j / 3),
        );
        
        // Left branch
        canvas.drawLine(
          branchPoint,
          Offset(
            branchPoint.dx + cos(angle + pi/2) * branchLength,
            branchPoint.dy + sin(angle + pi/2) * branchLength,
          ),
          paint..strokeWidth = 1.5,
        );
        
        // Right branch
        canvas.drawLine(
          branchPoint,
          Offset(
            branchPoint.dx + cos(angle - pi/2) * branchLength,
            branchPoint.dy + sin(angle - pi/2) * branchLength,
          ),
          paint..strokeWidth = 1.5,
        );
      }
    }
    
    // Center dot
    canvas.drawCircle(center, size * 0.2, paint);
  }

  @override
  bool shouldRepaint(FaceDetectionPainter oldDelegate) {
    return oldDelegate.faces != faces || 
           oldDelegate.trackedFaces != trackedFaces ||
           oldDelegate.imageSize != imageSize ||
           oldDelegate.cameraLensDirection != cameraLensDirection ||
           oldDelegate.showSnowEffect != showSnowEffect;
  }
}