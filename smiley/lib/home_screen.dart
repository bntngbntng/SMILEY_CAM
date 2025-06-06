// home_screen.dart

import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:smiley/src/face_detector_painter.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:path_provider/path_provider.dart';

// Class untuk tracking face yang lebih persisten
class TrackedFace {
  final int trackingId;
  final Rect boundingBox;
  final Map<FaceLandmarkType, FaceLandmark?>? landmarks;
  final double? smilingProbability;
  final double? leftEyeOpenProbability;
  final double? rightEyeOpenProbability;
  
  // Tracking data
  int smileConsecutiveFrames;
  int neutralConsecutiveFrames;
  DateTime lastDetected;
  bool hasTriggeredSmileSnap;
  
  TrackedFace({
    required this.trackingId,
    required this.boundingBox,
    this.landmarks,
    this.smilingProbability,
    this.leftEyeOpenProbability,
    this.rightEyeOpenProbability,
    this.smileConsecutiveFrames = 0,
    this.neutralConsecutiveFrames = 0,
    DateTime? lastDetected,
    this.hasTriggeredSmileSnap = false,
  }) : lastDetected = lastDetected ?? DateTime.now();

  TrackedFace copyWith({
    Rect? boundingBox,
    Map<FaceLandmarkType, FaceLandmark?>? landmarks,
    double? smilingProbability,
    double? leftEyeOpenProbability,
    double? rightEyeOpenProbability,
    int? smileConsecutiveFrames,
    int? neutralConsecutiveFrames,
    DateTime? lastDetected,
    bool? hasTriggeredSmileSnap,
  }) {
    return TrackedFace(
      trackingId: this.trackingId,
      boundingBox: boundingBox ?? this.boundingBox,
      landmarks: landmarks ?? this.landmarks,
      smilingProbability: smilingProbability ?? this.smilingProbability,
      leftEyeOpenProbability: leftEyeOpenProbability ?? this.leftEyeOpenProbability,
      rightEyeOpenProbability: rightEyeOpenProbability ?? this.rightEyeOpenProbability,
      smileConsecutiveFrames: smileConsecutiveFrames ?? this.smileConsecutiveFrames,
      neutralConsecutiveFrames: neutralConsecutiveFrames ?? this.neutralConsecutiveFrames,
      lastDetected: lastDetected ?? this.lastDetected,
      hasTriggeredSmileSnap: hasTriggeredSmileSnap ?? this.hasTriggeredSmileSnap,
    );
  }
}

// Snow particle class for the snow effect
class SnowParticle {
  double x;
  double y;
  double size;
  double speed;
  double opacity;
  
  SnowParticle({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.opacity,
  });
}

// Custom painter for snow effect
class SnowfallPainter extends CustomPainter {
  final List<SnowParticle> particles;
  final double animationValue;
  
  SnowfallPainter({
    required this.particles,
    required this.animationValue,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    final Paint snowPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.white;
    
    for (SnowParticle particle in particles) {
      snowPaint.color = Colors.white.withOpacity(particle.opacity);
      // Draw snowflake shape
      _drawFallingSnowflake(canvas, Offset(particle.x, particle.y), snowPaint, particle.size);
    }
  }
  
  @override
  bool shouldRepaint(SnowfallPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }

  // Draw a snowflake shape
  void _drawFallingSnowflake(Canvas canvas, Offset center, Paint paint, double size) {
    // Draw a more complex snowflake with multiple lines
    for (int i = 0; i < 6; i++) {
      final angle = (i * 60) * (pi / 180);
      
      // Main line
      canvas.drawLine(
        Offset(center.dx + cos(angle) * size, center.dy + sin(angle) * size),
        Offset(center.dx - cos(angle) * size, center.dy - sin(angle) * size),
        paint..strokeWidth = 1.5,
      );
      
      // Side branches
      for (int j = 1; j <= 2; j++) {
        final branchLength = size * 0.4;
        final branchPoint = Offset(
          center.dx + cos(angle) * (size * j / 3),
          center.dy + sin(angle) * (size * j / 3),
        );
        
        // Left branch
        canvas.drawLine(
          branchPoint,
          Offset(
            branchPoint.dx + cos(angle + pi/2.5) * branchLength,
            branchPoint.dy + sin(angle + pi/2.5) * branchLength,
          ),
          paint..strokeWidth = 1.0,
        );
        
        // Right branch
        canvas.drawLine(
          branchPoint,
          Offset(
            branchPoint.dx + cos(angle - pi/2.5) * branchLength,
            branchPoint.dy + sin(angle - pi/2.5) * branchLength,
          ),
          paint..strokeWidth = 1.0,
        );
      }
    }
    
    // Center dot
    canvas.drawCircle(center, size * 0.15, paint);
  }
}

class HomeScreen extends StatefulWidget {
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  CameraController? _controller;
  Future<void>? _initializeControllerFuture;
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,
      enableLandmarks: true,
      enableTracking: true,
      performanceMode: FaceDetectorMode.accurate,
      minFaceSize: 0.1,
    ),
  );

  bool _isDetecting = false;
  List<Face> _faces = [];
  Map<int, TrackedFace> _trackedFaces = {};
  List<CameraDescription> cameras = [];
  int _selectedCameraIndex = 0;

  bool _isCapturing = false;
  bool _smileToSnapEnabled = false;
  
  // Snow filter variables
  bool _snowFilterEnabled = false;
  bool _showSnowEffect = false;
  late AnimationController _snowAnimationController;
  late Animation<double> _snowAnimation;
  List<SnowParticle> _snowParticles = [];
  
  // Improved tracking parameters
  static const int _smileThreshold = 3;
  static const double _smileConfidenceThreshold = 0.7;
  static const int _maxTrackingAge = 15;
  static const double _faceMatchThreshold = 0.4;

  @override
  void initState() {
    super.initState();
    _initializeSnowAnimation();
    _requestPermissions();
    _initializeCamerasAvailable();
  }

  void _initializeSnowAnimation() {
    _snowAnimationController = AnimationController(
      duration: Duration(seconds: 2),
      vsync: this,
    );
    
    _snowAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _snowAnimationController,
      curve: Curves.linear,
    ));
    
    _snowAnimationController.addListener(_updateSnowParticles);
  }

  void _initializeSnowParticles(Size screenSize) {
    _snowParticles.clear();
    final random = Random();
    
    // Create 50 snow particles
    for (int i = 0; i < 50; i++) {
      _snowParticles.add(SnowParticle(
        x: random.nextDouble() * screenSize.width,
        y: random.nextDouble() * screenSize.height - screenSize.height,
        size: random.nextDouble() * 3 + 2, // Size between 2-5
        speed: random.nextDouble() * 2 + 1, // Speed between 1-3
        opacity: random.nextDouble() * 0.8 + 0.2, // Opacity between 0.2-1.0
      ));
    }
  }

  void _updateSnowParticles() {
    if (!_showSnowEffect || _snowParticles.isEmpty) return;
    
    final screenSize = MediaQuery.of(context).size;
    
    for (SnowParticle particle in _snowParticles) {
      particle.y += particle.speed;
      
      // Reset particle if it goes off screen
      if (particle.y > screenSize.height) {
        particle.y = -10;
        particle.x = Random().nextDouble() * screenSize.width;
      }
    }
    
    setState(() {});
  }

  void _startSnowEffect() {
    if (!_snowFilterEnabled) return;
    
    setState(() {
      _showSnowEffect = true;
    });
    
    final screenSize = MediaQuery.of(context).size;
    _initializeSnowParticles(screenSize);
    _snowAnimationController.repeat();
  }

  void _stopSnowEffect() {
    if (!_snowFilterEnabled) {
      setState(() {
        _showSnowEffect = false;
      });
      _snowAnimationController.stop();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _faceDetector.close();
    _snowAnimationController.dispose();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    final cameraStatus = await Permission.camera.request();
    final storageStatus = await Permission.storage.request();

    if (cameraStatus != PermissionStatus.granted ||
        storageStatus != PermissionStatus.granted) {
      print("Izin ditolak!");
      _showPermissionDialog();
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Akses membutuhkan izin!'),
          content: Text('App ini butuh izin akses ke kamera dan penyimpanan.'),
          actions: [
            TextButton(
              child: Text('OK'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

  Future<void> _initializeCamerasAvailable() async {
    try {
      cameras = await availableCameras();
      if (cameras.isEmpty) {
        print('Kamera tidak ditemukan.');
        return;
      }

      _selectedCameraIndex = cameras.indexWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
      );
      if (_selectedCameraIndex == -1) {
        _selectedCameraIndex = 0;
      }

      await _initializeCamera(cameras[_selectedCameraIndex]);
    } catch (e) {
      print("Error initializing cameras: $e");
    }
  }

  Future<void> _initializeCamera(CameraDescription cameraDescription) async {
    final controller = CameraController(
      cameraDescription,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isIOS
          ? ImageFormatGroup.bgra8888
          : ImageFormatGroup.yuv420,
    );
    _controller = controller;

    _initializeControllerFuture = controller
        .initialize()
        .then((_) {
          if (!mounted) return;
          setState(() {
            _startFaceDetection();
          });
        })
        .catchError((error) {
          print("Error saat inisialisasi kamera: $error");
        });
  }

  void _toggleCamera() async {
    if (cameras.isEmpty || cameras.length < 2) {
      print('Tidak bisa mengganti kamera. Kamera tidak tersedia.');
      return;
    }
    if (_controller != null && _controller!.value.isStreamingImages) {
      await _controller!.stopImageStream();
      await _controller!.dispose();
    }

    _selectedCameraIndex = (_selectedCameraIndex + 1) % cameras.length;

    setState(() {
      _faces = [];
      _trackedFaces.clear();
    });

    await _initializeCamera(cameras[_selectedCameraIndex]);
  }

  void _startFaceDetection() {
    if (_controller == null || !_controller!.value.isInitialized) return;

    _controller!.startImageStream((CameraImage image) async {
      if (_isDetecting) return;

      _isDetecting = true;

      final inputImage = _convertCameraImageToInputImage(image);
      if (inputImage == null) {
        _isDetecting = false;
        return;
      }
      try {
        final List<Face> faces = await _faceDetector.processImage(inputImage);

        if (mounted) {
          _updateTrackedFaces(faces);
          
          setState(() {
            _faces = faces;
          });

          // Check for smile
          if (_snowFilterEnabled || _smileToSnapEnabled) {
            _checkForSmileImproved();
          }
        }
      } catch (e) {
        print("Error saat proses mengambil gambar. $e");
      } finally {
        _isDetecting = false;
      }
    });
  }

  void _updateTrackedFaces(List<Face> detectedFaces) {
    final now = DateTime.now();
    Map<int, TrackedFace> updatedTrackedFaces = {};

    // Process detected faces
    for (Face face in detectedFaces) {
      TrackedFace? matchedFace;
      
      // Try to match with existing tracked faces
      if (face.trackingId != null) {
        matchedFace = _trackedFaces[face.trackingId!];
      }
      
      // If no tracking ID match, try to match by position
      if (matchedFace == null) {
        double bestMatch = double.infinity;
        for (TrackedFace tracked in _trackedFaces.values) {
          double distance = _calculateFaceDistance(face.boundingBox, tracked.boundingBox);
          if (distance < bestMatch && distance < _faceMatchThreshold) {
            bestMatch = distance;
            matchedFace = tracked;
          }
        }
      }

      if (matchedFace != null) {
        // Update existing tracked face
        final isSmiling = (face.smilingProbability ?? 0) > _smileConfidenceThreshold;
        
        updatedTrackedFaces[matchedFace.trackingId] = matchedFace.copyWith(
          boundingBox: face.boundingBox,
          landmarks: face.landmarks,
          smilingProbability: face.smilingProbability,
          leftEyeOpenProbability: face.leftEyeOpenProbability,
          rightEyeOpenProbability: face.rightEyeOpenProbability,
          smileConsecutiveFrames: isSmiling 
              ? matchedFace.smileConsecutiveFrames + 1 
              : 0,
          neutralConsecutiveFrames: !isSmiling 
              ? matchedFace.neutralConsecutiveFrames + 1 
              : 0,
          lastDetected: now,
          hasTriggeredSmileSnap: isSmiling && matchedFace.smileConsecutiveFrames >= _smileThreshold
              ? true 
              : (!isSmiling && matchedFace.neutralConsecutiveFrames > 30)
                  ? false 
                  : matchedFace.hasTriggeredSmileSnap,
        );
      } else {
        // Create new tracked face
        final trackingId = face.trackingId ?? _generateTrackingId();
        updatedTrackedFaces[trackingId] = TrackedFace(
          trackingId: trackingId,
          boundingBox: face.boundingBox,
          landmarks: face.landmarks,
          smilingProbability: face.smilingProbability,
          leftEyeOpenProbability: face.leftEyeOpenProbability,
          rightEyeOpenProbability: face.rightEyeOpenProbability,
          lastDetected: now,
        );
      }
    }

    // Keep faces that were recently detected
    for (TrackedFace tracked in _trackedFaces.values) {
      if (!updatedTrackedFaces.containsKey(tracked.trackingId)) {
        final age = now.difference(tracked.lastDetected).inMilliseconds ~/ 33;
        if (age < _maxTrackingAge) {
          updatedTrackedFaces[tracked.trackingId] = tracked.copyWith(
            neutralConsecutiveFrames: tracked.neutralConsecutiveFrames + 1,
          );
        }
      }
    }

    _trackedFaces = updatedTrackedFaces;
  }

  double _calculateFaceDistance(Rect face1, Rect face2) {
    final center1 = face1.center;
    final center2 = face2.center;
    final dx = center1.dx - center2.dx;
    final dy = center1.dy - center2.dy;
    return sqrt(dx * dx + dy * dy) / max(face1.width, face1.height);
  }

  int _generateTrackingId() {
    return DateTime.now().millisecondsSinceEpoch % 10000;
  }

  void _checkForSmileImproved() {
    for (TrackedFace trackedFace in _trackedFaces.values) {
      if (trackedFace.smileConsecutiveFrames >= _smileThreshold && 
          !trackedFace.hasTriggeredSmileSnap) {
        
        print("Smile detected for face ${trackedFace.trackingId}: "
              "${trackedFace.smileConsecutiveFrames} consecutive frames, "
              "confidence: ${trackedFace.smilingProbability?.toStringAsFixed(2)}");
        
        // Trigger snow effect if snow filter is enabled
        if (_snowFilterEnabled) {
          _startSnowEffect();
        }
        
        // Capture photo if smile to snap is enabled
        if (_smileToSnapEnabled && !_isCapturing) {
          _capturePhoto(isSmileSnap: true, trackingId: trackedFace.trackingId);
        }
        
        break; // Only trigger once per detection cycle
      }
    }
  }

  Future<void> _capturePhoto({bool isSmileSnap = false, int? trackingId}) async {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _isCapturing) {
      return;
    }

    try {
      setState(() {
        _isCapturing = true;
      });

      if (_controller!.value.isStreamingImages) {
        await _controller!.stopImageStream();
      }

      final XFile capturedImage = await _controller!.takePicture();
      
      // Add snow effect to the photo if snow filter is enabled
      if (_snowFilterEnabled) {
        final bytes = await File(capturedImage.path).readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        final frameInfo = await codec.getNextFrame();
        final image = frameInfo.image;
        
        // Create a recorder to draw the image with snow
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        
        // Draw the original image
        canvas.drawImage(image, Offset.zero, Paint());
        
        // Draw snow particles
        final snowPaint = Paint()
          ..style = PaintingStyle.fill
          ..color = Colors.white;
        
        final random = Random();
        for (int i = 0; i < 200; i++) {
          final x = random.nextDouble() * image.width;
          final y = random.nextDouble() * image.height;
          final size = random.nextDouble() * 8 + 4;
          final opacity = random.nextDouble() * 0.8 + 0.2;
          
          snowPaint.color = Colors.white.withOpacity(opacity);
          _drawSnowflakeOnCanvas(canvas, Offset(x, y), snowPaint, size);
        }
        
        // Convert the canvas to an image
        final picture = recorder.endRecording();
        final snowImage = await picture.toImage(image.width, image.height);
        final snowBytes = await snowImage.toByteData(format: ui.ImageByteFormat.png);
        
        // Save the snow image
        if (snowBytes != null) {
          await File(capturedImage.path).writeAsBytes(snowBytes.buffer.asUint8List());
        }
      }

      final result = await ImageGallerySaverPlus.saveFile(
        capturedImage.path,
        name: isSmileSnap
            ? "smile_snap_${trackingId ?? 'unknown'}_${DateTime.now().millisecondsSinceEpoch}"
            : "face_photo_${DateTime.now().millisecondsSinceEpoch}",
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isSmileSnap
                  ? _showSnowEffect
                      ? '❄️😄 Tertangkap basah sedang tersenyum dengan efek salju! (Face ID: ${trackingId ?? 'unknown'})'
                      : '😄 Tertangkap basah sedang tersenyum! (Face ID: ${trackingId ?? 'unknown'})'
                  : _snowFilterEnabled
                      ? '❄️📸 Foto dengan efek salju telah tersimpan di gallery.'
                      : '📸 Foto telah tersimpan di gallery.',
            ),
            backgroundColor: isSmileSnap ? Colors.green : Colors.blue,
            duration: Duration(seconds: 3),
          ),
        );
      }

      // Delay before restart detection
      await Future.delayed(Duration(milliseconds: 500));
      _startFaceDetection();
    } catch (e) {
      print("Error saat mengambil foto: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error capturing photo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isCapturing = false;
      });
    }
  }

  void _drawSnowflakeOnCanvas(Canvas canvas, Offset center, Paint paint, double size) {
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

  void _toggleSmileToSnap() {
    setState(() {
      _smileToSnapEnabled = !_smileToSnapEnabled;
      // Reset tracking data when toggling
      for (int key in _trackedFaces.keys) {
        _trackedFaces[key] = _trackedFaces[key]!.copyWith(
          smileConsecutiveFrames: 0,
          neutralConsecutiveFrames: 0,
          hasTriggeredSmileSnap: false,
        );
      }
    });
  }

  void _toggleSnowFilter() {
    setState(() {
      _snowFilterEnabled = !_snowFilterEnabled;
      if (!_snowFilterEnabled) {
        _stopSnowEffect();
      }
      // Reset tracking data when toggling
      for (int key in _trackedFaces.keys) {
        _trackedFaces[key] = _trackedFaces[key]!.copyWith(
          smileConsecutiveFrames: 0,
          neutralConsecutiveFrames: 0,
          hasTriggeredSmileSnap: false,
        );
      }
    });
  }

  InputImage? _convertCameraImageToInputImage(CameraImage image) {
    try {
      final format = Platform.isIOS
          ? InputImageFormat.bgra8888
          : InputImageFormat.nv21;

      final inputImageMetadata = InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: InputImageRotation.values.firstWhere(
          (element) =>
              element.rawValue == _controller!.description.sensorOrientation,
          orElse: () => InputImageRotation.rotation0deg,
        ),
        format: format,
        bytesPerRow: image.planes[0].bytesPerRow,
      );

      final bytes = _concatenatePlanes(image.planes);
      return InputImage.fromBytes(bytes: bytes, metadata: inputImageMetadata);
    } catch (e) {
      print("Error saat mengkonversi kamera: $e");
      return null;
    }
  }

  Uint8List _concatenatePlanes(List<Plane> planes) {
    final allBytes = WriteBuffer();
    for (Plane plane in planes) {
      allBytes.putUint8List(plane.bytes);
    }
    return allBytes.done().buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          "SMILEY",
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        actions: [
          // Snow Filter Button
          Container(
            margin: EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: _snowFilterEnabled ? Colors.cyan.withOpacity(0.3) : Colors.blueGrey[800]!.withOpacity(0.5),
              borderRadius: BorderRadius.circular(20),
            ),
            child: IconButton(
              onPressed: _toggleSnowFilter,
              icon: Icon(
                _snowFilterEnabled ? Icons.ac_unit : Icons.ac_unit_outlined,
                color: _snowFilterEnabled ? Colors.cyan : Colors.white,
              ),
              tooltip: _snowFilterEnabled
                  ? 'Disable Snow Filter'
                  : 'Enable Snow Filter',
            ),
          ),
          // Smile to Snap Button
          Container(
            margin: EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: _smileToSnapEnabled ? Colors.orangeAccent.withOpacity(0.3) : Colors.blueGrey[800]!.withOpacity(0.5),
              borderRadius: BorderRadius.circular(20),
            ),
            child: IconButton(
              onPressed: _toggleSmileToSnap,
              icon: Icon(
                _smileToSnapEnabled ? Icons.mood : Icons.mood_outlined,
                color: _smileToSnapEnabled ? Colors.orangeAccent : Colors.white,
              ),
              tooltip: _smileToSnapEnabled
                  ? 'Disable Smile to Snap'
                  : 'Enable Smile to Snap',
            ),
          ),
          // Camera Switch Button
          if (cameras.length > 1)
            Container(
              margin: EdgeInsets.only(right: 16),
              decoration: BoxDecoration(
                color: Colors.blueGrey[800]!.withOpacity(0.5),
                borderRadius: BorderRadius.circular(20),
              ),
              child: IconButton(
                onPressed: _toggleCamera,
                icon: Icon(CupertinoIcons.switch_camera_solid),
                color: Colors.white,
              ),
            ),
        ],
      ),
      body: _initializeControllerFuture == null
          ? Center(child: Text("No Camera Available"))
          : FutureBuilder<void>(
              future: _initializeControllerFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done &&
                    _controller != null &&
                    _controller!.value.isInitialized) {
                  if (_controller!.value.previewSize == null) {
                    return Center(
                      child: Text("Camera preview size not available."),
                    );
                  }

                  final Size previewSize = _controller!.value.previewSize!;
                  final double aspectRatio = previewSize.height / previewSize.width;

                  return Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.blue[900]!.withOpacity(0.7),
                          Colors.blue[700]!.withOpacity(0.5),
                          Colors.blue[900]!.withOpacity(0.7),
                        ],
                      ),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Center(
                          child: AspectRatio(
                            aspectRatio: aspectRatio,
                            child: Transform(
                              alignment: Alignment.center,
                              transform: Matrix4.identity()
                                ..scale(_controller!.description.lensDirection == CameraLensDirection.front ? -1.0 : 1.0, 1.0),
                              child: CameraPreview(_controller!),
                            ),
                          ),
                        ),
                        CustomPaint(
                          painter: FaceDetectionPainter(
                            faces: _faces,
                            trackedFaces: _trackedFaces,
                            imageSize: Size(
                              previewSize.height,
                              previewSize.width,
                            ),
                            cameraLensDirection: _controller!.description.lensDirection,
                            showSnowEffect: _showSnowEffect,
                          ),
                        ),
                        // Snow Effect Overlay
                        if (_showSnowEffect)
                          CustomPaint(
                            painter: SnowfallPainter(
                              particles: _snowParticles,
                              animationValue: _snowAnimation.value,
                            ),
                            size: Size.infinite,
                          ),
                        // Status indicators
                        if (_snowFilterEnabled)
                          Positioned(
                            top: 100,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: Container(
                                padding: EdgeInsets.symmetric(
                                  vertical: 12,
                                  horizontal: 24,
                                ),
                                decoration: BoxDecoration(
                                  color: _getSnowFilterColor().withOpacity(0.8),
                                  borderRadius: BorderRadius.circular(30),
                                  boxShadow: [
                                    BoxShadow(
                                      color: _getSnowFilterColor().withOpacity(0.3),
                                      blurRadius: 10,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: Text(
                                  _getSnowFilterText(),
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (_smileToSnapEnabled)
                          Positioned(
                            top: _snowFilterEnabled ? 160 : 100,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: Container(
                                padding: EdgeInsets.symmetric(
                                  vertical: 12,
                                  horizontal: 24,
                                ),
                                decoration: BoxDecoration(
                                  color: _getSmileToSnapColor().withOpacity(0.8),
                                  borderRadius: BorderRadius.circular(30),
                                  boxShadow: [
                                    BoxShadow(
                                      color: _getSmileToSnapColor().withOpacity(0.3),
                                      blurRadius: 10,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: Text(
                                  _getSmileToSnapText(),
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (_isCapturing)
                          Positioned(
                            top: _snowFilterEnabled && _smileToSnapEnabled ? 220 : _snowFilterEnabled || _smileToSnapEnabled ? 160 : 100,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: Container(
                                padding: EdgeInsets.symmetric(
                                  vertical: 12,
                                  horizontal: 24,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.cyan[700]!.withOpacity(0.8),
                                  borderRadius: BorderRadius.circular(30),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.cyan[700]!.withOpacity(0.3),
                                      blurRadius: 10,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.camera_alt, color: Colors.white),
                                    SizedBox(width: 8),
                                    Text(
                                      'Capturing...',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        Positioned(
                          bottom: 100,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                vertical: 12,
                                horizontal: 24,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blueGrey[800]!.withOpacity(0.7),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.blueGrey[800]!.withOpacity(0.3),
                                    blurRadius: 10,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: Text(
                                'Wajah terdeteksi: ${_faces.length} | Tracked: ${_trackedFaces.length}',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 30,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: GestureDetector(
                              onTap: _isCapturing ? null : () => _capturePhoto(),
                              child: Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  color: _isCapturing ? Colors.grey : Colors.white,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 10,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  Icons.camera_alt,
                                  size: 40,
                                  color: _isCapturing ? Colors.white : Colors.blue[700],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                } else if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                } else {
                  return Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  );
                }
              },
            ),
    );
  }

  Color _getSmileToSnapColor() {
    if (_trackedFaces.values.any((face) => face.hasTriggeredSmileSnap)) {
      return Colors.green;
    }
    
    int maxSmileFrames = 0;
    for (TrackedFace face in _trackedFaces.values) {
      if (face.smileConsecutiveFrames > maxSmileFrames) {
        maxSmileFrames = face.smileConsecutiveFrames;
      }
    }
    
    if (maxSmileFrames > 0) {
      return Colors.amberAccent[700]!;
    }
    
    return Colors.blueAccent[400]!;
  }

  String _getSmileToSnapText() {
    if (_trackedFaces.values.any((face) => face.hasTriggeredSmileSnap)) {
      return '😄 Terdeteksi sedang tersenyum!';
    }
    
    int maxSmileFrames = 0;
    for (TrackedFace face in _trackedFaces.values) {
      if (face.smileConsecutiveFrames > maxSmileFrames) {
        maxSmileFrames = face.smileConsecutiveFrames;
      }
    }
    
    if (maxSmileFrames > 0) {
      return '😊 Detecting smile... (${maxSmileFrames}/${_smileThreshold})';
    }
    
    return '😊 Smile to Snap: ON';
  }

  Color _getSnowFilterColor() {
    if (_showSnowEffect) {
      return Colors.cyan;
    }
    
    int maxSmileFrames = 0;
    for (TrackedFace face in _trackedFaces.values) {
      if (face.smileConsecutiveFrames > maxSmileFrames) {
        maxSmileFrames = face.smileConsecutiveFrames;
      }
    }
    
    if (maxSmileFrames > 0) {
      return Colors.lightBlue[300]!;
    }
    
    return Colors.blueAccent[400]!;
  }

  String _getSnowFilterText() {
    if (_showSnowEffect) {
      return '❄️ Snow Effect Active!';
    }
    
    int maxSmileFrames = 0;
    for (TrackedFace face in _trackedFaces.values) {
      if (face.smileConsecutiveFrames > maxSmileFrames) {
        maxSmileFrames = face.smileConsecutiveFrames;
      }
    }
    
    if (maxSmileFrames > 0) {
      return '❄️ Preparing snow... (${maxSmileFrames}/${_smileThreshold})';
    }
    
    return '❄️ Snow Filter: ON';
  }
}