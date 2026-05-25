import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';

bool get isBrowserCameraCaptureSupported => false;

Future<XFile?> captureWithBrowserCamera(
  BuildContext context, {
  String? initialError,
}) async {
  return null;
}
