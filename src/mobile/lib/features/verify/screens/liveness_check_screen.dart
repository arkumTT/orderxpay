import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../../../core/design/app_colors.dart';
import '../../../core/design/widgets.dart';

enum _Step { lookStraight, blink, turnHead, capturing, done }

/// Section 4.1/7.1's liveness check: an active on-device challenge (look
/// straight → blink → turn your head) run against the live front-camera
/// feed with Google ML Kit face detection — free, on-device, no cloud
/// account and no per-check cost. The frame captured right after the
/// challenge completes becomes the submitted selfie; there is no gallery
/// picker anywhere in this screen.
///
/// Honest limitation: this defeats someone holding up a static printed or
/// on-screen photo (a photo can't blink or turn its head on command), but
/// it does NOT defeat a sophisticated pre-recorded video timed to the
/// prompts — that level of anti-spoofing (3D depth, texture analysis) is
/// what paid vendors like Smile Identity/Onfido/Jumio specialize in.
/// Choosing a vendor is a procurement decision for later; this stops the
/// low-effort case, which is the overwhelming majority of it, for free.
///
/// Pops with an [XFile] (the captured selfie) on success, or `null` if the
/// user backs out.
class LivenessCheckScreen extends StatefulWidget {
  const LivenessCheckScreen({super.key});

  @override
  State<LivenessCheckScreen> createState() => _LivenessCheckScreenState();
}

class _LivenessCheckScreenState extends State<LivenessCheckScreen> {
  CameraController? _controller;
  final _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true, // eye-open probabilities, for blink
      performanceMode: FaceDetectorMode.fast,
    ),
  );

  _Step _step = _Step.lookStraight;
  String? _error;
  bool _busyOnFrame = false;
  Timer? _timeoutTimer;
  Timer? _debounceTimer;

  // Blink sub-state: waiting to see eyes close, then waiting to see them
  // open again — a still photo can fake "closed" but not a close-then-open
  // transition inside a few seconds.
  bool _sawEyesClosed = false;
  // Head-turn sub-state: waiting to see a turn past the threshold, then a
  // return toward center — same close-then-return shape as the blink.
  bool _sawHeadTurned = false;

  static const _straightAngleMax = 8.0;
  static const _turnAngleMin = 20.0;
  static const _returnAngleMax = 12.0;
  static const _eyeClosedMax = 0.4;
  static const _eyeOpenMin = 0.6;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _timeoutTimer = Timer(const Duration(seconds: 60), () {
      if (mounted && _step != _Step.done) {
        setState(() => _error = "Taking too long — let's try again.");
        _stopStream();
      }
    });
    _init();
  }

  Future<void> _init() async {
    try {
      final cameras = await availableCameras();
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
      await controller.startImageStream(_onFrame);
    } on CameraException catch (e) {
      if (mounted) {
        setState(() => _error = e.description ?? 'Camera unavailable (${e.code}).');
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Camera unavailable.');
    }
  }

  void _onFrame(CameraImage image) {
    if (_busyOnFrame || _controller == null) return;
    if (_step == _Step.capturing || _step == _Step.done) return;
    _busyOnFrame = true;
    _detect(image).whenComplete(() => _busyOnFrame = false);
  }

  Future<void> _detect(CameraImage image) async {
    final input = _toInputImage(image, _controller!.description);
    if (input == null) return;
    List<Face> faces;
    try {
      faces = await _faceDetector.processImage(input);
    } catch (_) {
      return;
    }
    if (!mounted || faces.length != 1) return;
    _evaluate(faces.first);
  }

  void _evaluate(Face face) {
    switch (_step) {
      case _Step.lookStraight:
        final straight =
            (face.headEulerAngleY?.abs() ?? 99) < _straightAngleMax &&
            (face.headEulerAngleX?.abs() ?? 99) < _straightAngleMax;
        if (straight) _debounceAdvance(_Step.blink);
        break;

      case _Step.blink:
        final leftOpen = face.leftEyeOpenProbability;
        final rightOpen = face.rightEyeOpenProbability;
        if (leftOpen == null || rightOpen == null) return;
        final avgOpen = (leftOpen + rightOpen) / 2;
        if (!_sawEyesClosed && avgOpen < _eyeClosedMax) {
          _sawEyesClosed = true;
        } else if (_sawEyesClosed && avgOpen > _eyeOpenMin) {
          _advance(_Step.turnHead);
        }
        break;

      case _Step.turnHead:
        final yaw = face.headEulerAngleY?.abs() ?? 0;
        if (!_sawHeadTurned && yaw > _turnAngleMin) {
          _sawHeadTurned = true;
        } else if (_sawHeadTurned && yaw < _returnAngleMax) {
          _capture();
        }
        break;

      case _Step.capturing:
      case _Step.done:
        break;
    }
  }

  // A brief hold on "look straight" avoids advancing on a single lucky
  // frame — the same debounce shape isn't needed for blink/turn since
  // those already require a two-phase transition.
  void _debounceAdvance(_Step next) {
    _debounceTimer ??= Timer(const Duration(milliseconds: 400), () {
      _debounceTimer = null;
      _advance(next);
    });
  }

  void _advance(_Step next) {
    if (!mounted || _step == next) return;
    setState(() => _step = next);
  }

  Future<void> _capture() async {
    if (_controller == null || _step == _Step.capturing) return;
    setState(() => _step = _Step.capturing);
    await _stopStream();
    try {
      final file = await _controller!.takePicture();
      _timeoutTimer?.cancel();
      if (mounted) {
        setState(() => _step = _Step.done);
        Navigator.of(context).pop(file);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not capture the photo — try again.';
          _step = _Step.turnHead;
        });
      }
    }
  }

  Future<void> _stopStream() async {
    final c = _controller;
    if (c != null && c.value.isStreamingImages) {
      try {
        await c.stopImageStream();
      } catch (_) {
        // already stopped
      }
    }
  }

  void _retry() {
    _sawEyesClosed = false;
    _sawHeadTurned = false;
    setState(() {
      _error = null;
      _step = _Step.lookStraight;
    });
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(seconds: 60), () {
      if (mounted && _step != _Step.done) {
        setState(() => _error = "Taking too long — let's try again.");
        _stopStream();
      }
    });
    final c = _controller;
    if (c != null && !c.value.isStreamingImages) {
      c.startImageStream(_onFrame);
    }
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _timeoutTimer?.cancel();
    _debounceTimer?.cancel();
    _faceDetector.close();
    _controller?.dispose();
    super.dispose();
  }

  String get _instructions {
    if (_error != null) return _error!;
    switch (_step) {
      case _Step.lookStraight:
        return 'Center your face in the oval and look straight ahead';
      case _Step.blink:
        return 'Blink naturally';
      case _Step.turnHead:
        return 'Slowly turn your head, then return to center';
      case _Step.capturing:
        return 'Capturing…';
      case _Step.done:
        return 'Done';
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Liveness check'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (controller != null && controller.value.isInitialized)
                    ClipRect(
                      child: FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: controller.value.previewSize?.height ?? 0,
                          height: controller.value.previewSize?.width ?? 0,
                          child: CameraPreview(controller),
                        ),
                      ),
                    )
                  else
                    const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  Center(
                    child: Container(
                      width: 240,
                      height: 300,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: _error != null
                              ? AppColors.statusDeclined
                              : Colors.white70,
                          width: 3,
                        ),
                        borderRadius: BorderRadius.circular(140),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              color: Colors.black,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _StepDots(step: _step, hasError: _error != null),
                  const SizedBox(height: 14),
                  Text(
                    _instructions,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _error != null ? AppColors.statusDeclined : Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    OxpButton(label: 'Try again', onPressed: _retry),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepDots extends StatelessWidget {
  const _StepDots({required this.step, required this.hasError});
  final _Step step;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    const order = [_Step.lookStraight, _Step.blink, _Step.turnHead];
    final currentIndex = order.indexOf(
      step == _Step.capturing || step == _Step.done ? _Step.turnHead : step,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(order.length, (i) {
        final active = i <= currentIndex && !hasError;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 5),
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? AppColors.accent : Colors.white24,
          ),
        );
      }),
    );
  }
}

// Standard camera→ML Kit conversion (see the google_mlkit_face_detection
// example): the screen is locked to portrait (see initState), so device
// orientation is always portraitUp — no extra sensor/orientation plugin
// needed to compute rotation compensation.
//
// Requesting ImageFormatGroup.nv21 makes the camera plugin hand back a
// single already-NV21 plane on most Android devices, but some camera HALs
// (confirmed on this app's MediaTek-based Samsung test device) ignore that
// and still deliver 3-plane YUV_420_888 — silently dropping every one of
// those frames (as an earlier version of this function did) meant face
// detection never ran at all, so the challenge just sat on step one until
// it timed out. Converting the 3-plane case to NV21 ourselves covers both.
InputImage? _toInputImage(CameraImage image, CameraDescription camera) {
  final sensorOrientation = camera.sensorOrientation;
  InputImageRotation? rotation;
  if (Platform.isIOS) {
    rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
  } else if (Platform.isAndroid) {
    var rotationCompensation = 0; // portraitUp
    if (camera.lensDirection == CameraLensDirection.front) {
      rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
    } else {
      rotationCompensation = (sensorOrientation - rotationCompensation + 360) % 360;
    }
    rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
  }
  if (rotation == null) return null;

  if (Platform.isAndroid) {
    if (image.planes.length == 1) {
      final plane = image.planes.first;
      return InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: plane.bytesPerRow,
        ),
      );
    }
    if (image.planes.length == 3) {
      return InputImage.fromBytes(
        bytes: _yuv420ToNv21(image),
        metadata: InputImageMetadata(
          // The manual conversion below packs rows with no padding, so
          // bytesPerRow is exactly the image width, unlike plane.bytesPerRow
          // (which may include HAL row-stride padding on the source planes).
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: image.width,
        ),
      );
    }
    return null;
  }

  // iOS: bgra8888, single plane — unaffected by the Android HAL quirk above.
  if (InputImageFormatValue.fromRawValue(image.format.raw) !=
          InputImageFormat.bgra8888 ||
      image.planes.length != 1) {
    return null;
  }
  final plane = image.planes.first;
  return InputImage.fromBytes(
    bytes: plane.bytes,
    metadata: InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format: InputImageFormat.bgra8888,
      bytesPerRow: plane.bytesPerRow,
    ),
  );
}

// Manual YUV_420_888 (3-plane: Y, U, V — each with its own row stride and
// pixel stride) → NV21 (single plane: all Y bytes, then interleaved V,U
// pairs) conversion. This is the standard shape of this conversion; see
// e.g. the google_mlkit_face_detection example app's camera_view.dart.
Uint8List _yuv420ToNv21(CameraImage image) {
  final width = image.width;
  final height = image.height;
  final yPlane = image.planes[0];
  final uPlane = image.planes[1];
  final vPlane = image.planes[2];

  final ySize = width * height;
  final nv21 = Uint8List(ySize + (width * height ~/ 2));

  var offset = 0;
  if (yPlane.bytesPerRow == width) {
    nv21.setRange(0, ySize, yPlane.bytes);
    offset = ySize;
  } else {
    for (var row = 0; row < height; row++) {
      final start = row * yPlane.bytesPerRow;
      nv21.setRange(offset, offset + width, yPlane.bytes, start);
      offset += width;
    }
  }

  final uvPixelStride = uPlane.bytesPerPixel ?? 1;
  final vPixelStride = vPlane.bytesPerPixel ?? 1;
  for (var row = 0; row < height ~/ 2; row++) {
    for (var col = 0; col < width ~/ 2; col++) {
      final uIndex = row * uPlane.bytesPerRow + col * uvPixelStride;
      final vIndex = row * vPlane.bytesPerRow + col * vPixelStride;
      nv21[offset++] = vPlane.bytes[vIndex];
      nv21[offset++] = uPlane.bytes[uIndex];
    }
  }
  return nv21;
}
