// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

bool get isBrowserCameraCaptureSupported => true;

Future<XFile?> captureWithBrowserCamera(
  BuildContext context, {
  String? initialError,
}) {
  return showDialog<XFile>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _BrowserCameraCaptureDialog(
      initialError: initialError,
    ),
  );
}

class _BrowserCameraCaptureDialog extends StatefulWidget {
  const _BrowserCameraCaptureDialog({this.initialError});

  final String? initialError;

  @override
  State<_BrowserCameraCaptureDialog> createState() =>
      _BrowserCameraCaptureDialogState();
}

class _BrowserCameraCaptureDialogState
    extends State<_BrowserCameraCaptureDialog> {
  late final String _viewType;
  late final html.VideoElement _videoElement;

  List<html.MediaDeviceInfo> _videoDevices = [];
  String? _selectedDeviceId;
  html.MediaStream? _stream;
  bool _isStarting = false;
  bool _isCapturing = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _viewType =
        'browser-camera-${DateTime.now().microsecondsSinceEpoch.toString()}';
    _videoElement = html.VideoElement()
      ..autoplay = true
      ..muted = true
      ..setAttribute('playsinline', 'true')
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'contain'
      ..style.backgroundColor = 'black';
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int viewId) => _videoElement,
    );
    _errorMessage = widget.initialError;
    unawaited(_startCamera());
  }

  @override
  void dispose() {
    _stopStream();
    super.dispose();
  }

  Future<void> _startCamera({String? deviceId}) async {
    if (_isStarting) {
      return;
    }

    setState(() {
      _isStarting = true;
      _errorMessage = widget.initialError;
    });

    _stopStream();

    try {
      final constraints = <String, dynamic>{
        'audio': false,
        'video': deviceId == null || deviceId.isEmpty
            ? true
            : <String, dynamic>{
                'deviceId': <String, dynamic>{'exact': deviceId},
              },
      };

      final mediaDevices = html.window.navigator.mediaDevices;
      final stream = await mediaDevices?.getUserMedia(constraints);
      if (stream == null) {
        throw StateError('Browser media devices are not available.');
      }

      _stream = stream;
      _videoElement.srcObject = stream;
      await _videoElement.play();
      await _loadVideoDevices();

      if (!mounted) {
        return;
      }

      setState(() {
        _selectedDeviceId = deviceId ?? _selectedDeviceId;
        _isStarting = false;
        _errorMessage = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isStarting = false;
        _errorMessage = _formatCameraError(error);
      });
    }
  }

  Future<void> _loadVideoDevices() async {
    final mediaDevices = html.window.navigator.mediaDevices;
    final devices = await mediaDevices?.enumerateDevices();
    final videoDevices = devices
            ?.cast<html.MediaDeviceInfo>()
            .where((device) => device.kind == 'videoinput')
            .toList(growable: false) ??
        <html.MediaDeviceInfo>[];

    if (!mounted) {
      return;
    }

    setState(() {
      _videoDevices = videoDevices;
      if (_selectedDeviceId == null && videoDevices.isNotEmpty) {
        _selectedDeviceId = videoDevices.first.deviceId;
      }
    });
  }

  void _stopStream() {
    final tracks = _stream?.getTracks() ?? <html.MediaStreamTrack>[];
    for (final track in tracks) {
      track.stop();
    }
    _stream = null;
    _videoElement.srcObject = null;
  }

  String _formatCameraError(Object error) {
    if (error is html.DomException) {
      final message = error.message;
      return message == null || message.isEmpty
          ? error.name
          : '${error.name}: $message';
    }
    return error.toString();
  }

  Future<void> _selectDevice(String? deviceId) async {
    if (deviceId == null || deviceId == _selectedDeviceId || _isStarting) {
      return;
    }
    setState(() {
      _selectedDeviceId = deviceId;
    });
    await _startCamera(deviceId: deviceId);
  }

  Future<void> _retryCamera() async {
    await _startCamera(deviceId: _selectedDeviceId);
  }

  Future<void> _captureImage() async {
    if (_isCapturing || _isStarting) {
      return;
    }

    final width = _videoElement.videoWidth;
    final height = _videoElement.videoHeight;
    if (width <= 0 || height <= 0) {
      setState(() {
        _errorMessage = 'Camera preview is not ready yet.';
      });
      return;
    }

    setState(() {
      _isCapturing = true;
      _errorMessage = null;
    });

    try {
      final canvas = html.CanvasElement(width: width, height: height);
      canvas.context2D.drawImage(_videoElement, 0, 0);
      final dataUrl = canvas.toDataUrl('image/png');
      final commaIndex = dataUrl.indexOf(',');
      final bytes = base64Decode(dataUrl.substring(commaIndex + 1));
      final file = XFile.fromData(
        bytes,
        name: 'browser_camera_capture.png',
        mimeType: 'image/png',
        length: bytes.length,
      );

      if (mounted) {
        Navigator.of(context).pop<XFile>(file);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _isCapturing = false;
          _errorMessage = error.toString();
        });
      }
    }
  }

  String _deviceLabel(int index) {
    final label = (_videoDevices[index].label ?? '').trim();
    return label.isEmpty ? 'Camera ${index + 1}' : label;
  }

  @override
  Widget build(BuildContext context) {
    final canCapture = !_isStarting && !_isCapturing && _stream != null;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Browser camera',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    onPressed:
                        _isStarting || _isCapturing ? null : _retryCamera,
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Retry camera',
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_videoDevices.isNotEmpty) ...[
                DropdownButtonFormField<String>(
                  key: ValueKey(_selectedDeviceId),
                  initialValue: _selectedDeviceId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Camera device',
                  ),
                  items: [
                    for (var index = 0; index < _videoDevices.length; index++)
                      DropdownMenuItem<String>(
                        value: _videoDevices[index].deviceId,
                        child: Text(
                          _deviceLabel(index),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _isStarting || _isCapturing ? null : _selectDevice,
                ),
                const SizedBox(height: 12),
              ],
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: ColoredBox(
                  color: Colors.black,
                  child: AspectRatio(
                    aspectRatio: 4 / 3,
                    child: _stream == null && !_isStarting
                        ? const Center(
                            child: Icon(
                              Icons.videocam_off,
                              color: Colors.white,
                              size: 48,
                            ),
                          )
                        : Stack(
                            alignment: Alignment.center,
                            children: [
                              HtmlElementView(viewType: _viewType),
                              if (_isStarting)
                                const CircularProgressIndicator(),
                            ],
                          ),
                  ),
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        _isCapturing ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: canCapture ? _captureImage : null,
                    icon: _isCapturing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.camera_alt),
                    label: Text(_isCapturing ? 'Capturing' : 'Capture'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
