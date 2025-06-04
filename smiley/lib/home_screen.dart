// home_screen.dart

import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:smiley/src/face_detector_painter.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:path_provider/path_provider.dart';

class HomeScreen extends StatefulWidget {
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  CameraController? _controller;
  Future<void>? _initializeControllerFuture;
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,
      enableLandmarks: true,
      enableTracking: true,
      performanceMode: FaceDetectorMode.fast,
    ),
  );

  bool _isDetecting = false;
  List<Face> _faces = [];
  List<CameraDescription> cameras = [];
  int _selectedCameraIndex = 0;

  // New variables for photo capture
  bool _isCapturing = false;
  bool _smileToSnapEnabled = false;
  bool _hasSmiled = false;
  int _smileCounter = 0;
  static const int _smileThreshold =
      1; // Number of consecutive smile detections needed

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _initializeCamerasAvailable();
  }

  @override
  void dispose() {
    _controller?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    final cameraStatus = await Permission.camera.request();
    final storageStatus = await Permission.storage.request();

    if (cameraStatus != PermissionStatus.granted ||
        storageStatus != PermissionStatus.granted) {
      print("Permissions Denied");
      // Show dialog to user about required permissions
      _showPermissionDialog();
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Permissions Required'),
          content: Text(
            'This app needs camera and storage permissions to function properly.',
          ),
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
        print('No Cameras Found');
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
      ResolutionPreset.ultraHigh,
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
          print("Error initializing camera controller: $error");
        });
  }

  void _toggleCamera() async {
    if (cameras.isEmpty || cameras.length < 2) {
      print('Can\'t toggle camera. Not enough cameras available.');
      return;
    }
    if (_controller != null && _controller!.value.isStreamingImages) {
      await _controller!.stopImageStream();
      await _controller!.dispose();
    }

    _selectedCameraIndex = (_selectedCameraIndex + 1) % cameras.length;

    setState(() {
      _faces = [];
      _smileCounter = 0;
      _hasSmiled = false;
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
          setState(() {
            _faces = faces;
          });

          // Check for smile to snap
          if (_smileToSnapEnabled && !_isCapturing) {
            _checkForSmile(faces);
          }
        }
      } catch (e) {
        print("Error processing image: $e");
      } finally {
        _isDetecting = false;
      }
    });
  }

  void _checkForSmile(List<Face> faces) {
    if (faces.isEmpty) {
      _smileCounter = 0;
      _hasSmiled = false;
      return;
    }

    bool isSmiling = false;
    for (Face face in faces) {
      final smileProb = face.smilingProbability ?? 0;
      if (smileProb > 0.7) {
        // Threshold for detecting smile
        isSmiling = true;
        break;
      }
    }

    if (isSmiling) {
      _smileCounter++;
      if (_smileCounter >= _smileThreshold && !_hasSmiled) {
        _hasSmiled = true;
        _capturePhoto(isSmileSnap: true);
      }
    } else {
      _smileCounter = 0;
      if (_hasSmiled) {
        // Reset after a moment to allow for another smile capture
        Future.delayed(Duration(seconds: 2), () {
          if (mounted) {
            setState(() {
              _hasSmiled = false;
            });
          }
        });
      }
    }
  }

  Future<void> _capturePhoto({bool isSmileSnap = false}) async {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _isCapturing) {
      return;
    }

    try {
      setState(() {
        _isCapturing = true;
      });

      // Stop image stream temporarily
      if (_controller!.value.isStreamingImages) {
        await _controller!.stopImageStream();
      }

      // Take the picture
      final XFile picture = await _controller!.takePicture();

      // Save to gallery
      final result = await ImageGallerySaverPlus.saveFile(
        picture.path,
        name: isSmileSnap
            ? "smile_snap_${DateTime.now().millisecondsSinceEpoch}"
            : "face_photo_${DateTime.now().millisecondsSinceEpoch}",
      );

      // Show confirmation
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isSmileSnap
                  ? '😄 Smile captured! Photo saved to gallery'
                  : '📸 Photo saved to gallery',
            ),
            backgroundColor: isSmileSnap ? Colors.green : Colors.blue,
            duration: Duration(seconds: 2),
          ),
        );
      }

      // Restart image stream for face detection
      _startFaceDetection();
    } catch (e) {
      print("Error capturing photo: $e");
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

  void _toggleSmileToSnap() {
    setState(() {
      _smileToSnapEnabled = !_smileToSnapEnabled;
      _smileCounter = 0;
      _hasSmiled = false;
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
      print("Error converting camera image: $e");
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
      appBar: AppBar(
        title: Text("Face Detection Camera"),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          // Smile to snap toggle
          IconButton(
            onPressed: _toggleSmileToSnap,
            icon: Icon(
              _smileToSnapEnabled ? Icons.mood : Icons.mood_outlined,
              color: _smileToSnapEnabled ? Colors.yellow : Colors.white,
            ),
            tooltip: _smileToSnapEnabled
                ? 'Disable Smile to Snap'
                : 'Enable Smile to Snap',
          ),
          // Camera toggle
          if (cameras.length > 1)
            IconButton(
              onPressed: _toggleCamera,
              icon: Icon(CupertinoIcons.switch_camera_solid),
              color: Colors.white,
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
                  final double aspectRatio =
                      previewSize.height / previewSize.width;

                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      // Camera Preview
                      Center(
                        child: AspectRatio(
                          aspectRatio: aspectRatio,
                          child: CameraPreview(_controller!),
                        ),
                      ),
                      // Face Detection Overlay
                      CustomPaint(
                        painter: FaceDetectionPainter(
                          faces: _faces,
                          imageSize: Size(
                            previewSize.height,
                            previewSize.width,
                          ),
                          cameraLensDirection:
                              _controller!.description.lensDirection,
                        ),
                      ),
                      // Status indicators
                      Positioned(
                        top: 20,
                        left: 0,
                        right: 0,
                        child: Column(
                          children: [
                            if (_smileToSnapEnabled)
                              Container(
                                padding: EdgeInsets.symmetric(
                                  vertical: 8,
                                  horizontal: 16,
                                ),
                                decoration: BoxDecoration(
                                  color: _hasSmiled
                                      ? Colors.green
                                      : Colors.orange,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  _hasSmiled
                                      ? '😄 Smile Detected!'
                                      : '😊 Smile to Snap: ON',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            if (_isCapturing)
                              Container(
                                margin: EdgeInsets.only(top: 8),
                                padding: EdgeInsets.symmetric(
                                  vertical: 8,
                                  horizontal: 16,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.blue,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  '📸 Capturing...',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      // Face count indicator
                      Positioned(
                        bottom: 100,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 16,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'Wajah terdeteksi: ${_faces.length}',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Manual capture button
                      Positioned(
                        bottom: 30,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: GestureDetector(
                            onTap: _isCapturing ? null : () => _capturePhoto(),
                            child: Container(
                              width: 70,
                              height: 70,
                              decoration: BoxDecoration(
                                color: _isCapturing
                                    ? Colors.grey
                                    : Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.grey,
                                  width: 4,
                                ),
                              ),
                              child: Icon(
                                Icons.camera_alt,
                                size: 35,
                                color: _isCapturing
                                    ? Colors.white
                                    : Colors.grey[700],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                } else if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                } else {
                  return Center(child: CircularProgressIndicator());
                }
              },
            ),
    );
  }
}
