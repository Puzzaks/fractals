import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/material.dart' show BuildContext, Rect;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:share_plus/share_plus.dart';

/// Shares exported image bytes directly from memory on Web.
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
  await Share.shareXFiles(
    <XFile>[XFile.fromData(imageBytes, mimeType: mimeType, name: fileName)],
    text: shareText,
    sharePositionOrigin: shareOrigin,
  );
}

/// Video file path exports are unsupported on Web.
Future<String> createTempExportFilePath(String fileName) async {
  throw UnsupportedError('Temporary export files are not supported on web');
}

/// File-path sharing is unsupported on Web.
Future<void> shareExportedFile({
  required String filePath,
  required String mimeType,
  required String shareText,
  required Rect? shareOrigin,
}) async {
  throw UnsupportedError('File-path sharing is not supported on web');
}
