import 'package:flutter/services.dart';

/// Holds lightweight application metadata parsed from `pubspec.yaml`.
class AppMetadata {
  AppMetadata._();

  static String appName = 'fractals';
  static String appDescription = 'GPU Fractal Explorer';
  static String versionDisplay = '1.0.9';

  /// Loads `pubspec.yaml` from bundled assets and updates [appName],
  /// [appDescription], and [versionDisplay], keeping safe defaults on failure.
  static Future<void> init() async {
    try {
      final String raw = await rootBundle.loadString('pubspec.yaml');
      for (final String line in raw.split('\n')) {
        final String trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
        if (trimmed.startsWith('name:')) {
          final String value = _stripYamlQuotes(
            trimmed.substring('name:'.length).trim(),
          );
          if (value.isNotEmpty) {
            appName = value;
          }
        } else if (trimmed.startsWith('description:')) {
          final String value = _stripYamlQuotes(
            trimmed.substring('description:'.length).trim(),
          );
          if (value.isNotEmpty) {
            appDescription = value;
          }
        } else if (trimmed.startsWith('version:')) {
          final String rawVersion = _stripYamlQuotes(
            trimmed.substring('version:'.length).trim(),
          );
          final String display = rawVersion.split('+').first.trim();
          if (display.isNotEmpty) {
            versionDisplay = display;
          }
        }
      }
    } catch (_) {
      // Keep default metadata values when pubspec.yaml is unavailable.
    }
  }

  static String _stripYamlQuotes(String value) {
    if (value.length >= 2) {
      final String first = value[0];
      final String last = value[value.length - 1];
      if ((first == '"' && last == '"') || (first == "'" && last == "'")) {
        return value.substring(1, value.length - 1).trim();
      }
    }
    return value;
  }
}
