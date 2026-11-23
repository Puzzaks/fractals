import 'fractal_engine.dart';
import 'fractal_models.dart';

/// Parsed deep-link / share-link fractal payload ready to apply to [FractalEngine].
class SharedFractalPayload {
  final FractalBookmark bookmark;
  final double rotation;
  final double colorOffset;
  final bool smoothColor;

  const SharedFractalPayload({
    required this.bookmark,
    this.rotation = 0.0,
    this.colorOffset = 0.0,
    this.smoothColor = true,
  });
}

/// Encodes and parses shareable fractal coordinate links (`https://fractals.puzzak.page/v?...`,
/// `https://puzzak.page/fractals/v?...`, `fractals://v?...`, and Play Install
/// Referrer query strings).
class FractalShareLink {
  FractalShareLink._();

  static const String webBaseUrl = 'https://fractals.puzzak.page/v';
  static const String customScheme = 'fractals';
  static const String playStorePackage = 'page.puzzak.fractals';

  /// Encodes the live [engine] state into a shareable HTTPS URI.
  static Uri encode(FractalEngine engine, {String? name}) {
    final Map<String, String> queryParams = <String, String>{
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
      if (engine.fractalType == FractalType.julia) ...<String, String>{
        'jx': engine.juliaCx.toString(),
        'jy': engine.juliaCy.toString(),
      },
    };
    final String? trimmedName = name?.trim();
    if (trimmedName != null && trimmedName.isNotEmpty) {
      queryParams['n'] = trimmedName;
    }
    return Uri.https('fractals.puzzak.page', '/v', queryParams);
  }

  /// Encodes a saved [bookmark] into a shareable HTTPS URI.
  static Uri encodeBookmark(FractalBookmark bookmark) {
    final Map<String, String> queryParams = <String, String>{
      'f': bookmark.fractalType.name,
      'x': bookmark.centerXDecimal ?? bookmark.centerX.toString(),
      'y': bookmark.centerYDecimal ?? bookmark.centerY.toString(),
      'z': bookmark.zoom.toStringAsPrecision(12),
      'p': bookmark.palette.name,
      if (bookmark.fractalType == FractalType.julia) ...<String, String>{
        'jx': bookmark.juliaCx.toString(),
        'jy': bookmark.juliaCy.toString(),
      },
    };
    final String trimmedName = bookmark.name.trim();
    if (trimmedName.isNotEmpty) {
      queryParams['n'] = trimmedName;
    }
    return Uri.https('fractals.puzzak.page', '/v', queryParams);
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

  /// Parses an incoming HTTPS App Link, custom-scheme URI, or raw Play Install
  /// Referrer query string into a [SharedFractalPayload], or `null` if invalid.
  static SharedFractalPayload? tryParse(String? raw) {
    if (raw == null) return null;
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    Map<String, String> params;
    final Uri? parsedUri = Uri.tryParse(trimmed);
    if (parsedUri != null && parsedUri.hasScheme) {
      final String scheme = parsedUri.scheme.toLowerCase();
      if (scheme == customScheme) {
        final String host = parsedUri.host.toLowerCase();
        final String path = parsedUri.path.toLowerCase();
        if (host != 'v' && path != '/v' && path != 'v') {
          return null;
        }
        params = parsedUri.queryParameters;
      } else if ((scheme == 'https' || scheme == 'http') &&
          ((parsedUri.host.toLowerCase() == 'fractals.puzzak.page' &&
                  (parsedUri.path == '/v' ||
                      parsedUri.path.startsWith('/v/'))) ||
              (parsedUri.host.toLowerCase() == 'puzzak.page' &&
                  (parsedUri.path == '/fractals/v' ||
                      parsedUri.path.startsWith('/fractals/v/'))))) {
        params = parsedUri.queryParameters;
      } else {
        return null;
      }
    } else {
      final String rawQuery =
          trimmed.startsWith('?') ? trimmed.substring(1) : trimmed;
      try {
        params = Uri.splitQueryString(rawQuery);
        if (!params.containsKey('f') &&
            !params.containsKey('x') &&
            !params.containsKey('z')) {
          final String decoded = Uri.decodeComponent(rawQuery);
          params = Uri.splitQueryString(decoded);
        }
      } catch (_) {
        return null;
      }
    }

    final String? xStr = params['x'];
    final String? yStr = params['y'];
    final String? zStr = params['z'];
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

    final FractalType fractalType = FractalType.fromName(params['f']);
    final FractalPalette palette = FractalPalette.fromName(params['p']);

    final double? parsedJx = double.tryParse(params['jx'] ?? '');
    final double? parsedJy = double.tryParse(params['jy'] ?? '');
    final double juliaCx = (parsedJx != null && parsedJx.isFinite)
        ? parsedJx.clamp(-2.0, 2.0)
        : -0.7269;
    final double juliaCy = (parsedJy != null && parsedJy.isFinite)
        ? parsedJy.clamp(-2.0, 2.0)
        : 0.1889;

    final double? parsedR = double.tryParse(params['r'] ?? '');
    final double rotation =
        (parsedR != null && parsedR.isFinite) ? parsedR : 0.0;

    final double? parsedCo = double.tryParse(params['co'] ?? '');
    final double colorOffset = (parsedCo != null && parsedCo.isFinite)
        ? parsedCo.clamp(0.0, 1.0)
        : 0.0;

    final bool smoothColor = params['s'] != '0';

    final String? rawName = params['n']?.trim();
    final String name =
        (rawName != null && rawName.isNotEmpty) ? rawName : 'Shared Fractal';

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
    );
  }
}
