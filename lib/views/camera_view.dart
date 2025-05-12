import 'dart:developer';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:image/image.dart' as img;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'package:visual_impaired_app/globals.dart' as globals;
import 'package:visual_impaired_app/views/text_to_speech.dart';
import 'package:visual_impaired_app/api_service.dart';

class CameraView extends StatefulWidget {
  CameraView(
      {Key? key,
      required this.customPaint,
      required this.onImage,
      this.onCameraFeedReady,
      this.onDetectorViewModeChanged,
      this.onCameraLensDirectionChanged,
      this.initialCameraLensDirection = CameraLensDirection.back})
      : super(key: key);

  final CustomPaint? customPaint;
  final Function(InputImage inputImage) onImage;
  final VoidCallback? onCameraFeedReady;
  final VoidCallback? onDetectorViewModeChanged;
  final Function(CameraLensDirection direction)? onCameraLensDirectionChanged;
  final CameraLensDirection initialCameraLensDirection;

  @override
  State<CameraView> createState() => _CameraViewState();
}

class _CameraViewState extends State<CameraView> {
  static List<CameraDescription> _cameras = [];
  CameraController? _controller;
  int _cameraIndex = -1;

  double _currentZoomLevel = 1.0;
  double _minAvailableZoom = 1.0;
  double _maxAvailableZoom = 1.0;
  double _minAvailableExposureOffset = 0.0;
  double _maxAvailableExposureOffset = 0.0;
  double _currentExposureOffset = 0.0;
  bool _changingCameraLens = false;

  final SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;
  String wordsSpoken = "";
  double confidenceLevel = 0;

  CameraImage? _latestImage;
  final OpenRouterService _openRouter = OpenRouterService(globals.openRouterApiKey);

  @override
  void initState() {
    super.initState();
    _initialize();
    // initSpeech();
  }

  void _initialize() async {
    if (_cameras.isEmpty) {
      _cameras = await availableCameras();
      _speechEnabled = await _speechToText.initialize();
      await speak("Tap the microphone in the bottom to start listening");
    }
    for (var i = 0; i < _cameras.length; i++) {
      if (_cameras[i].lensDirection == widget.initialCameraLensDirection) {
        _cameraIndex = i;
        break;
      }
    }
    if (_cameraIndex != -1) {
      _startLiveFeed();
    }
  }

  // void initSpeech() async{
  //   _speechEnabled = await _speechToText.initialize();
  //   setState(() {
  //   });
  // }

  void startListening() async {
    await _speechToText.listen(onResult: onSpeechResult);
    await speak("Listening");
    setState(() {
      confidenceLevel = 0;
    });
  }

  void stopListening() async {
    await _speechToText.stop();
    await speak("Stop listening, tap the microphone to start listening");
    setState(() {
      // globals.targetSearch = "";
      wordsSpoken = "";
    });
  }

  void onSpeechResult(SpeechRecognitionResult res) async {
    setState(() {
      wordsSpoken = _speechToText.isListening ? res.recognizedWords : "";
      confidenceLevel = res.confidence;
    });
    extractTargetObject(wordsSpoken);
    if (res.finalResult) {
      await _speechToText.stop();
      await _sendPromptWithFrame(res.recognizedWords);
    }
  }

  void extractTargetObject(String spokenText) {
    String tmpText = spokenText.toLowerCase();
    String cleanedText = tmpText.replaceAll("whereis", "").trim();
    List<String> words = cleanedText.split(" ");
    setState(() {
      globals.targetSearch = words.join("");
    });
  }

  @override
  void dispose() {
    _stopLiveFeed();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _liveFeedBody(),


      ],
    );
  }

  Widget _liveFeedBody() {
    if (_cameras.isEmpty) return Container();
    if (_controller == null) return Container();
    if (_controller?.value.isInitialized == false) return Container();
    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Center(
            child: _changingCameraLens
                ? const Center(
              child: Text('Changing camera lens'),
            )
                : CameraPreview(
              _controller!,
              child: widget.customPaint,
            ),
          ),
          // _backButton(),
          // _switchLiveCameraToggle(),
          // _detectionViewModeToggle(),
          // _zoomControl(),
          // _exposureControl(),
          _voiceButton(),
          _additionalText()
        ],
      ),
    );
  }

  // Widget _backButton() => Positioned(
  //       top: 40,
  //       left: 8,
  //       child: SizedBox(
  //         height: 50.0,
  //         width: 50.0,
  //         child: FloatingActionButton(
  //           heroTag: Object(),
  //           onPressed: () => Navigator.of(context).pop(),
  //           backgroundColor: Colors.black54,
  //           child: Icon(
  //             Icons.arrow_back_ios_outlined,
  //             size: 20,
  //           ),
  //         ),
  //       ),
  //     );

  Widget _detectionViewModeToggle() =>
      Positioned(
        bottom: 8,
        left: 8,
        child: SizedBox(
          height: 50.0,
          width: 50.0,
          child: FloatingActionButton(
            heroTag: Object(),
            onPressed: widget.onDetectorViewModeChanged,
            backgroundColor: Colors.black54,
            child: Icon(
              Icons.photo_library_outlined,
              size: 25,
            ),
          ),
        ),
      );
  bool _isModeActive = false;

  Widget _voiceButton() =>
      Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          height: MediaQuery
              .of(context)
              .size
              .height * 0.15, // 15% chiều cao màn hình
          width: MediaQuery
              .of(context)
              .size
              .width * 0.9, // 90% chiều rộng màn hình
          child: FloatingActionButton(
            heroTag: Object(),
            onPressed: () {
              _speechToText.isListening ? stopListening() : startListening();
              if (_isModeActive) {
                globals.targetSearch = "";
              }
              setState(() {
                _isModeActive = !_isModeActive;
              });
            },
            backgroundColor: Colors.white,
            child: Icon(
              _speechToText.isNotListening ? Icons.mic_off : Icons.mic,
              size: 25,
            ),
          ),
        ),
      );

  Widget _additionalText() =>
      Positioned(
        top: 64,
        left: 8,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _speechToText.isListening ? "Listening..." : _speechEnabled
                  ? "Tap the microphone to start listening..."
                  : "Speech not available",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16.0,
              ),
            ),
            // if (confidenceLevel > 0 && _speechToText.isNotListening)
            Text(
              globals.targetSearch,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10.0,
              ),
            ),

          ],
        ),
      );


  Widget _switchLiveCameraToggle() =>
      Positioned(
        bottom: 8,
        right: 8,
        child: SizedBox(
          height: 50.0,
          width: 50.0,
          child: FloatingActionButton(
            heroTag: Object(),
            onPressed: _switchLiveCamera,
            backgroundColor: Colors.white,
            child: Icon(
              Platform.isIOS
                  ? Icons.flip_camera_ios_outlined
                  : Icons.flip_camera_android_outlined,
              size: 25,
            ),
          ),
        ),
      );

  Widget _zoomControl() =>
      Positioned(
        bottom: 16,
        left: 0,
        right: 0,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: 250,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Slider(
                    value: _currentZoomLevel,
                    min: _minAvailableZoom,
                    max: _maxAvailableZoom,
                    activeColor: Colors.white,
                    inactiveColor: Colors.white30,
                    onChanged: (value) async {
                      setState(() {
                        _currentZoomLevel = value;
                      });
                      await _controller?.setZoomLevel(value);
                    },
                  ),
                ),
                Container(
                  width: 50,
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(10.0),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Center(
                      child: Text(
                        '${_currentZoomLevel.toStringAsFixed(1)}x',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _exposureControl() =>
      Positioned(
        top: 40,
        right: 8,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: 250,
          ),
          child: Column(children: [
            Container(
              width: 55,
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(10.0),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Center(
                  child: Text(
                    '${_currentExposureOffset.toStringAsFixed(1)}x',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
            Expanded(
              child: RotatedBox(
                quarterTurns: 3,
                child: SizedBox(
                  height: 30,
                  child: Slider(
                    value: _currentExposureOffset,
                    min: _minAvailableExposureOffset,
                    max: _maxAvailableExposureOffset,
                    activeColor: Colors.white,
                    inactiveColor: Colors.white30,
                    onChanged: (value) async {
                      setState(() {
                        _currentExposureOffset = value;
                      });
                      await _controller?.setExposureOffset(value);
                    },
                  ),
                ),
              ),
            )
          ]),
        ),
      );

  Future _startLiveFeed() async {
    final camera = _cameras[_cameraIndex];
    _controller = CameraController(
      camera,
      // Set to ResolutionPreset.high. Do NOT set it to ResolutionPreset.max because for some phones does NOT work.
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );
    _controller?.initialize().then((_) {
      if (!mounted) {
        return;
      }
      _controller?.getMinZoomLevel().then((value) {
        _currentZoomLevel = value;
        _minAvailableZoom = value;
      });
      _controller?.getMaxZoomLevel().then((value) {
        _maxAvailableZoom = value;
      });
      _currentExposureOffset = 0.0;
      _controller?.getMinExposureOffset().then((value) {
        _minAvailableExposureOffset = value;
      });
      _controller?.getMaxExposureOffset().then((value) {
        _maxAvailableExposureOffset = value;
      });
      _controller?.startImageStream(_processCameraImage).then((value) {
        if (widget.onCameraFeedReady != null) {
          widget.onCameraFeedReady!();
        }
        if (widget.onCameraLensDirectionChanged != null) {
          widget.onCameraLensDirectionChanged!(camera.lensDirection);
        }
      });
      setState(() {});
    });
  }

  Future _stopLiveFeed() async {
    await _controller?.stopImageStream();
    await _controller?.dispose();
    _controller = null;
  }

  Future _switchLiveCamera() async {
    setState(() => _changingCameraLens = true);
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;

    await _stopLiveFeed();
    await _startLiveFeed();
    setState(() => _changingCameraLens = false);
  }

  void _processCameraImage(CameraImage image) {
    _latestImage = image;
    final inputImage = _inputImageFromCameraImage(image);
    if (inputImage == null) return;
    widget.onImage(inputImage);
  }

  final _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    if (_controller == null) return null;

    // get image rotation
    // it is used in android to convert the InputImage from Dart to Java: https://github.com/flutter-ml/google_ml_kit_flutter/blob/master/packages/google_mlkit_commons/android/src/main/java/com/google_mlkit_commons/InputImageConverter.java
    // `rotation` is not used in iOS to convert the InputImage from Dart to Obj-C: https://github.com/flutter-ml/google_ml_kit_flutter/blob/master/packages/google_mlkit_commons/ios/Classes/MLKVisionImage%2BFlutterPlugin.m
    // in both platforms `rotation` and `camera.lensDirection` can be used to compensate `x` and `y` coordinates on a canvas: https://github.com/flutter-ml/google_ml_kit_flutter/blob/master/packages/example/lib/vision_detector_views/painters/coordinates_translator.dart
    final camera = _cameras[_cameraIndex];
    final sensorOrientation = camera.sensorOrientation;
    // print(
    //     'lensDirection: ${camera.lensDirection}, sensorOrientation: $sensorOrientation, ${_controller?.value.deviceOrientation} ${_controller?.value.lockedCaptureOrientation} ${_controller?.value.isCaptureOrientationLocked}');
    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      var rotationCompensation =
      _orientations[_controller!.value.deviceOrientation];
      if (rotationCompensation == null) return null;
      if (camera.lensDirection == CameraLensDirection.front) {
        // front-facing
        rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
      } else {
        // back-facing
        rotationCompensation =
            (sensorOrientation - rotationCompensation + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
      // print('rotationCompensation: $rotationCompensation');
    }
    if (rotation == null) return null;
    // print('final rotation: $rotation');

    // get image format
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    // validate format depending on platform
    // only supported formats:
    // * nv21 for Android
    // * bgra8888 for iOS
    if (format == null ||
        (Platform.isAndroid && format != InputImageFormat.nv21) ||
        (Platform.isIOS && format != InputImageFormat.bgra8888)) return null;

    // since format is constraint to nv21 or bgra8888, both only have one plane
    if (image.planes.length != 1) return null;
    final plane = image.planes.first;

    // compose InputImage using bytes
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation, // used only in Android
        format: format, // used only in iOS
        bytesPerRow: plane.bytesPerRow, // used only in iOS
      ),
    );
  }

  Future<void> _sendPromptWithFrame(String prompt) async {
    if (_latestImage == null) return;
    try {
      final Uint8List jpeg = _cameraImageToJpeg(_latestImage!);
      final reply = await _openRouter.sendPrompt(prompt: prompt, jpegBytes: jpeg);
      await speak(reply);
    } on DioException catch (d) {
      log('Dio error → ${d.type} | ${d.response?.statusCode}');
      log('Response data: ${d.response?.data}');
      await speak('Máy chủ trả về lỗi ${d.response?.statusCode}');
    } catch (e, st) {
      log('Other error: $e');
      log(st.toString());
      await speak('Lỗi: $e');
    }
  }

  /* ───── Chuyển CameraImage ➜ JPEG bytes ───── */
  Uint8List _cameraImageToJpeg(CameraImage imgCam) =>
      imgCam.format.group == ImageFormatGroup.bgra8888
          ? _convertBGRA8888(imgCam)
          : _convertNV21(imgCam);

  Uint8List _convertBGRA8888(CameraImage imgCam) {
    final w = imgCam.width,
        h = imgCam.height;
    final img.Image rgb = img.Image(width: w, height: h);
    final bytes = imgCam.planes[0].bytes;
    int i = 0;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final b = bytes[i++],
            g = bytes[i++],
            r = bytes[i++];
        i++; // skip alpha
        rgb.setPixelRgb(x, y, r, g, b);
      }
    }
    return Uint8List.fromList(img.encodeJpg(rgb, quality: 90));
  }

  Uint8List _convertNV21(CameraImage camImg) {
    final int width = camImg.width;
    final int height = camImg.height;
    final Uint8List nv21 = camImg.planes[0].bytes;
    final img.Image rgbImage = img.Image(width: width, height: height);

    final int frameSize = width * height;
    for (int y = 0; y < height; y++) {
      final int uvRowStart = frameSize + (y >> 1) * width;
      for (int x = 0; x < width; x++) {
        final int yIndex = y * width + x;
        // trong NV21, V và U xen kẽ: V at even, U at odd
        final int vIndex = uvRowStart + (x & ~1);
        final int uIndex = vIndex + 1;

        final int Y = nv21[yIndex] & 0xFF;
        final int V = nv21[vIndex] & 0xFF;
        final int U = nv21[uIndex] & 0xFF;

        // Công thức chuyển YUV ➔ RGB
        int r = (Y + 1.370705 * (V - 128)).round().clamp(0, 255);
        int g = (Y - 0.698001 * (V - 128) - 0.337633 * (U - 128)).round().clamp(0, 255);
        int b = (Y + 1.732446 * (U - 128)).round().clamp(0, 255);

        rgbImage.setPixelRgb(x, y, r, g, b);
      }
    }

    // Encode lại thành JPEG
    return Uint8List.fromList(img.encodeJpg(rgbImage, quality: 90));
  }
}

