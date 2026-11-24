import 'dart:convert';

import 'fractal_engine.dart';
import 'fractal_models.dart';

/// Parsed deep-link / share-link fractal payload ready to apply to [FractalEngine].
class SharedFractalPayload {
  final FractalBookmark bookmark;
  final double rotation;
  final double colorOffset;
  final bool smoothColor;
  final String? author;

  const SharedFractalPayload({
    required this.bookmark,
    this.rotation = 0.0,
    this.colorOffset = 0.0,
    this.smoothColor = true,
    this.author,
  });
}

/// Encodes and parses shareable fractal coordinate links (`https://fractals.puzzak.page/v?d=...`,
/// `https://puzzak.page/fractals/v?d=...`, `fractals://v?d=...`, and Play Install
/// Referrer `d=...` query strings).
class FractalShareLink {
  FractalShareLink._();

  static const String _shareHost = 'fractals.puzzak.page';
  static const String _sharePath = '/v';
  static const String webBaseUrl = 'https://$_shareHost$_sharePath';
  static const String customScheme = 'fractals';
  static const String playStorePackage = 'page.puzzak.fractals';

  static Uri _encodePayload(Map<String, Object> payload) {
    final String encoded =
        base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '');
    return Uri.https(_shareHost, _sharePath, <String, String>{'d': encoded});
  }

  /// Encodes the live [engine] state into a shareable HTTPS URI.
  static Uri encode(FractalEngine engine, {String? name, String? author}) {
    final Map<String, Object> payload = <String, Object>{
      'f': engine.fractalType.name,
      'x': engine.centerXDecimal,
      'y': engine.centerYDecimal,
      'z': engine.zoom.toStringAsPrecision(12),
      if (engine.rotation.abs() > 1e-6)
        'r': engine.rotation.toStringAsFixed(5),
      'p': engine.palette.name,
      's': engine.smoothColor ? '1' : '0',
      if (engine.colorOffset.abs() > 1e-6)
        'co': engine.colorOffset.toStringAsFixed(4),
      if (engine.fractalType == FractalType.julia) ...<String, Object>{
        'jx': engine.juliaCx.toString(),
        'jy': engine.juliaCy.toString(),
      },
    };
    final String? trimmedName = name?.trim();
    if (trimmedName != null && trimmedName.isNotEmpty) {
      payload['n'] = trimmedName;
    }
    final String? trimmedAuthor = author?.trim();
    if (trimmedAuthor != null && trimmedAuthor.isNotEmpty) {
      payload['a'] = trimmedAuthor;
    }
    return _encodePayload(payload);
  }

  /// Encodes a saved [bookmark] into a shareable HTTPS URI.
  static Uri encodeBookmark(
    FractalBookmark bookmark, {
    String? name,
    String? author,
  }) {
    final Map<String, Object> payload = <String, Object>{
      'f': bookmark.fractalType.name,
      'x': bookmark.centerXDecimal ?? bookmark.centerX.toString(),
      'y': bookmark.centerYDecimal ?? bookmark.centerY.toString(),
      'z': bookmark.zoom.toStringAsPrecision(12),
      'p': bookmark.palette.name,
      if (bookmark.fractalType == FractalType.julia) ...<String, Object>{
        'jx': bookmark.juliaCx.toString(),
        'jy': bookmark.juliaCy.toString(),
      },
    };
    final String trimmedName = (name ?? bookmark.name).trim();
    if (trimmedName.isNotEmpty) {
      payload['n'] = trimmedName;
    }
    final String? trimmedAuthor = author?.trim();
    if (trimmedAuthor != null && trimmedAuthor.isNotEmpty) {
      payload['a'] = trimmedAuthor;
    }
    return _encodePayload(payload);
  }

  /// Wraps [shareUri]'s query string into a Google Play Store deferred
  /// deep-link URL via the `referrer` parameter.
  static Uri playStoreDeferredUrl(Uri shareUri) {
    return Uri.https(
      'play.google.com',
      '/store/apps/details',
      <String, String>{
        'id': playStorePackage,
        'referrer': shareUri.query,
      },
    );
  }

  static String? _asString(Object? value) {
    if (value is String) return value;
    if (value is num) return value.toString();
    return null;
  }

  /// Parses an incoming HTTPS App Link, custom-scheme URI, or raw Play Install
  /// Referrer query string (`?d=<base64url>`) into a [SharedFractalPayload],
  /// or `null` if invalid.
  static SharedFractalPayload? tryParse(String? raw) {
    if (raw == null) return null;
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    String? d;
    final Uri? parsedUri = Uri.tryParse(trimmed);
    if (parsedUri != null && parsedUri.hasScheme) {
      final String scheme = parsedUri.scheme.toLowerCase();
      if (scheme == customScheme) {
        final String host = parsedUri.host.toLowerCase();
        final String path = parsedUri.path.toLowerCase();
        if (host != 'v' && path != '/v' && path != 'v') {
          return null;
        }
        d = parsedUri.queryParameters['d'];
      } else if ((scheme == 'https' || scheme == 'http') &&
          ((parsedUri.host.toLowerCase() == _shareHost &&
                  (parsedUri.path == _sharePath ||
                      parsedUri.path.startsWith('$_sharePath/'))) ||
              (parsedUri.host.toLowerCase() == 'puzzak.page' &&
                  (parsedUri.path == '/fractals/v' ||
                      parsedUri.path.startsWith('/fractals/v/'))))) {
        d = parsedUri.queryParameters['d'];
      } else {
        return null;
      }
    } else {
      final String rawQuery =
          trimmed.startsWith('?') ? trimmed.substring(1) : trimmed;
      try {
        Map<String, String> params = Uri.splitQueryString(rawQuery);
        if (!params.containsKey('d')) {
          params = Uri.splitQueryString(Uri.decodeComponent(rawQuery));
        }
        d = params['d'];
      } catch (_) {
        return null;
      }
    }

    if (d == null || d.isEmpty) return null;

    final Map<String, dynamic> map;
    try {
      final int rem = d.length % 4;
      final String padded = rem == 0 ? d : d + ('=' * (4 - rem));
      final String jsonStr = utf8.decode(base64Url.decode(padded));
      final dynamic decoded = jsonDecode(jsonStr);
      if (decoded is! Map<String, dynamic>) return null;
      map = decoded;
    } catch (_) {
      return null;
    }

    final String? xStr = _asString(map['x']);
    final String? yStr = _asString(map['y']);
    final String? zStr = _asString(map['z']);
    if (xStr == null ||
        xStr.isEmpty ||
        yStr == null ||
        yStr.isEmpty ||
        zStr == null ||
        zStr.isEmpty) {
      return null;
    }

    final double? x = double.tryParse(xStr);
    final double? y = double.tryParse(yStr);
    final double? z = double.tryParse(zStr);
    if (x == null ||
        !x.isFinite ||
        y == null ||
        !y.isFinite ||
        z == null ||
        !z.isFinite ||
        z <= 0) {
      return null;
    }

    final FractalType fractalType = FractalType.fromName(_asString(map['f']));
    final FractalPalette palette = FractalPalette.fromName(_asString(map['p']));

    final double? parsedJx = double.tryParse(_asString(map['jx']) ?? '');
    final double? parsedJy = double.tryParse(_asString(map['jy']) ?? '');
    final double juliaCx = (parsedJx != null && parsedJx.isFinite)
        ? parsedJx.clamp(-2.0, 2.0)
        : -0.7269;
    final double juliaCy = (parsedJy != null && parsedJy.isFinite)
        ? parsedJy.clamp(-2.0, 2.0)
        : 0.1889;

    final double? parsedR = double.tryParse(_asString(map['r']) ?? '');
    final double rotation =
        (parsedR != null && parsedR.isFinite) ? parsedR : 0.0;

    final double? parsedCo = double.tryParse(_asString(map['co']) ?? '');
    final double colorOffset = (parsedCo != null && parsedCo.isFinite)
        ? parsedCo.clamp(0.0, 1.0)
        : 0.0;

    final Object? rawSmooth = map['s'];
    final bool smoothColor =
        rawSmooth != '0' && rawSmooth != false && rawSmooth != 0;

    final String? rawName = _asString(map['n'])?.trim();
    final String name =
        (rawName != null && rawName.isNotEmpty) ? rawName : 'Shared Fractal';

    final String? rawAuthor = _asString(map['a'])?.trim();
    final String? author =
        (rawAuthor != null && rawAuthor.isNotEmpty) ? rawAuthor : null;

    return SharedFractalPayload(
      bookmark: FractalBookmark(
        id: 'shared_${DateTime.now().microsecondsSinceEpoch}',
        name: name,
        fractalType: fractalType,
        centerX: x,
        centerY: y,
        centerXDecimal: xStr,
        centerYDecimal: yStr,
        zoom: z,
        juliaCx: juliaCx,
        juliaCy: juliaCy,
        palette: palette,
        isBuiltIn: false,
      ),
      rotation: rotation,
      colorOffset: colorOffset,
      smoothColor: smoothColor,
      author: author,
    );
  }
}
