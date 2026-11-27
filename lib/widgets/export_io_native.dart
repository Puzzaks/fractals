import 'dart:io' show Directory, File, Platform;

import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/material.dart' show BuildContext, Rect;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'app_toast.dart';

/// Writes exported image bytes to a temporary file, saves to the Android
/// gallery when supported, and opens the system share sheet.
Future<void> saveAndShareExportedImage({
  required BuildContext context,
  required Uint8List imageBytes,
  required String fileName,
  required String mimeType,
  required String shareText,
  required Rect? shareOrigin,
  required MethodChannel displayChannel,
  required String savedToPicturesMessage,
}) async {
  final Directory tempDir = await getTemporaryDirectory();
  final File file =
      File('${tempDir.path}${Platform.pathSeparator}$fileName');
  await file.writeAsBytes(imageBytes, flush: true);
  if (Platform.isAndroid) {
    String? savedUri;
    try {
      savedUri = await displayChannel.invokeMethod<String>(
        'saveImageToGallery',
        <String, dynamic>{
          'filePath': file.path,
          'displayName': fileName,
          'mimeType': mimeType,
        },
      );
    } catch (_) {}
    if (savedUri != null && savedUri.isNotEmpty && context.mounted) {
      showAppToast(context, savedToPicturesMessage);
    }
  }
  await Share.shareXFiles(
    <XFile>[XFile(file.path, mimeType: mimeType)],
    text: shareText,
    sharePositionOrigin: shareOrigin,
  );
}

/// Allocates a temporary file path for native media exports.
Future<String> createTempExportFilePath(String fileName) async {
  final Directory tempDir = await getTemporaryDirectory();
  return '${tempDir.path}${Platform.pathSeparator}$fileName';
}

/// Shares an exported native file via the system share sheet.
Future<void> shareExportedFile({
  required String filePath,
  required String mimeType,
  required String shareText,
  required Rect? shareOrigin,
}) async {
  await Share.shareXFiles(
    <XFile>[XFile(filePath, mimeType: mimeType)],
    text: shareText,
    sharePositionOrigin: shareOrigin,
  );
}
