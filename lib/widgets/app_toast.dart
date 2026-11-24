import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const MethodChannel _displayChannel =
    MethodChannel('page.puzzak.fractals/display');

/// Shows a native Android toast on Android, or a floating [SnackBar] fallback
/// on other platforms.
void showAppToast(
  BuildContext context,
  String message, {
  bool long = false,
}) {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    unawaited(_showAndroidToast(message, long));
    return;
  }
  if (!context.mounted) return;
  final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration:
            long ? const Duration(seconds: 4) : const Duration(seconds: 2),
      ),
    );
}

Future<void> _showAndroidToast(String message, bool long) async {
  try {
    await _displayChannel.invokeMethod<void>(
      'showToast',
      <String, dynamic>{
        'message': message,
        'long': long,
      },
    );
  } on MissingPluginException {
    // Expected in widget tests or environments without the Android plugin.
  } on PlatformException {
    // Ignore platform errors for fire-and-forget toast notifications.
  }
}
