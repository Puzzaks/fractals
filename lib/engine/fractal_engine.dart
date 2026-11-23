import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:m3x/m3x.dart' show M3x;
import 'package:m3x_core/m3x_core.dart';
import 'package:m3x_dict/m3x_dict.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fractal_models.dart';

/// Keyboard shortcut actions bound to customizable [LogicalKeyboardKey]s.
enum FractalKeyAction {
  panUp(
    translationKey: 'key_pan_up',
    defaultKey: LogicalKeyboardKey.keyW,
  ),
  panDown(
    translationKey: 'key_pan_down',
    defaultKey: LogicalKeyboardKey.keyS,
  ),
  panLeft(
    translationKey: 'key_pan_left',
    defaultKey: LogicalKeyboardKey.keyA,
  ),
  panRight(
    translationKey: 'key_pan_right',
    defaultKey: LogicalKeyboardKey.keyD,
  ),
  zoomIn(
    translationKey: 'key_zoom_in',
    defaultKey: LogicalKeyboardKey.equal,
  ),
  zoomOut(
    translationKey: 'key_zoom_out',
    defaultKey: LogicalKeyboardKey.minus,
  ),
  resetView(
    translationKey: 'key_reset_view',
    defaultKey: LogicalKeyboardKey.keyR,
  ),
  toggleHud(
    translationKey: 'key_toggle_hud',
    defaultKey: LogicalKeyboardKey.keyH,
  ),
  toggleInspector(
    translationKey: 'key_toggle_inspector',
    defaultKey: LogicalKeyboardKey.keyI,
  );

  final String translationKey;
  final LogicalKeyboardKey defaultKey;

  const FractalKeyAction({
    required this.translationKey,
    required this.defaultKey,
  });
}

/// Central state machine and camera controller for Fractal Viewer.
///
/// Owns fractal parameters, focal-point camera mathematics, persistence via
/// [SharedPreferences], localization via [Dictionary], and telemetry via
/// [AnalyticsService]. Never holds a [BuildContext].
class FractalEngine extends ChangeNotifier {
  static const double minZoom = 50.0;
  static const double maxZoom = 1e15;
  static const double df64ThresholdZoom = 5e4;
  static const double cpuDeepThresholdZoom = 2e12;

  static const String _prefFractalType = 'fv_fractal_type';
  static const String _prefCenterX = 'fv_center_x';
  static const String _prefCenterY = 'fv_center_y';
  static const String _prefZoom = 'fv_zoom';
  static const String _prefJuliaCx = 'fv_julia_cx';
  static const String _prefJuliaCy = 'fv_julia_cy';
  static const String _prefPalette = 'fv_palette';
  static const String _prefColorOffset = 'fv_color_offset';
  static const String _prefSmoothColor = 'fv_smooth_color';
  static const String _prefAutoIter = 'fv_auto_iter';
  static const String _prefManualIter = 'fv_manual_iter';
  static const String _prefQuality = 'fv_quality';
  static const String _prefBackend = 'fv_backend';
  static const String _prefShowHud = 'fv_show_hud';
  static const String _prefShowTelemetry = 'fv_show_telemetry';
  static const String _prefDragPreviewScale = 'fv_drag_preview_scale';
  static const String _prefOverscanMultiplier = 'fv_overscan_multiplier';
  static const String _prefFractalCameras = 'fv_fractal_cameras';
  static const String _prefKeybinds = 'fv_keybinds';
  static const String _prefCustomBookmarks = 'fv_custom_bookmarks';

  FractalType _fractalType = FractalType.mandelbrot;
  double _centerX = FractalType.mandelbrot.defaultCenterX;
  double _centerY = FractalType.mandelbrot.defaultCenterY;
  double _zoom = FractalType.mandelbrot.defaultZoom;
  double _juliaCx = -0.7269;
  double _juliaCy = 0.1889;
  FractalPalette _palette = FractalPalette.system;
  double _colorOffset = 0.0;
  bool _smoothColor = true;
  bool _autoIterations = true;
  int _manualMaxIterations = 300;
  RenderQuality _quality = RenderQuality.native;
  RenderBackend _backend = RenderBackend.auto;
  bool _showHud = true;
  bool _showTelemetry = true;
  double _dragPreviewScale = 0.20;
  double _overscanMultiplier = 2.0;
  bool _isInteracting = false;
  bool _isCpuRendering = false;
  bool _isExporting = false;
  bool _initialized = false;

  SharedPreferences? _prefs;
  late final AnalyticsService analytics;
  late Dictionary dictionary;

  final Map<FractalType, ({double centerX, double centerY, double zoom})>
      _fractalCameras =
      <FractalType, ({double centerX, double centerY, double zoom})>{};
  final Map<FractalKeyAction, LogicalKeyboardKey> _keybinds =
      <FractalKeyAction, LogicalKeyboardKey>{};
  final List<FractalBookmark> _customBookmarks = <FractalBookmark>[];
  final Queue<double> _recentFrameMs = Queue<double>();
  final List<double> _fpsHistory = <double>[];
  double _lastFrameTimeMs = 0.0;
  double _currentFps = 60.0;

  FractalEngine({
    Dictionary? dictionary,
  }) {
    analytics = AnalyticsService(
      notifyEngine: notifyListeners,
    );
    this.dictionary = dictionary ??
        Dictionary(
          path: 'assets/translations',
          debugHighlightFallbacks: kDebugMode,
        );
  }

  // Getters
  FractalType get fractalType => _fractalType;
  double get centerX => _centerX;
  double get centerY => _centerY;
  double get zoom => _zoom;
  double get juliaCx => _juliaCx;
  double get juliaCy => _juliaCy;
  FractalPalette get palette => _palette;
  double get colorOffset => _colorOffset;
  bool get smoothColor => _smoothColor;
  bool get autoIterations => _autoIterations;
  int get manualMaxIterations => _manualMaxIterations;
  RenderQuality get quality => _quality;
  RenderBackend get backend => _backend;
  bool get showHud => _showHud;
  bool get showTelemetry => _showTelemetry;
  double get dragPreviewScale => _dragPreviewScale;
  double get overscanMultiplier => _overscanMultiplier;
  bool get isInteracting => _isInteracting;
  bool get isCpuRendering => _isCpuRendering;
  bool get isExporting => _isExporting;
  bool get initialized => _initialized;

  double get lastFrameTimeMs => _lastFrameTimeMs;
  double get currentFps => _currentFps;
  List<double> get fpsHistory => List<double>.unmodifiable(_fpsHistory);
  List<FractalBookmark> get customBookmarks =>
      List<FractalBookmark>.unmodifiable(_customBookmarks);
  List<FractalBookmark> get allBookmarks =>
      <FractalBookmark>[...builtInBookmarks, ..._customBookmarks];

  LogicalKeyboardKey keybindFor(FractalKeyAction action) =>
      _keybinds[action] ?? action.defaultKey;

  Map<FractalKeyAction, LogicalKeyboardKey> get keybinds =>
      Map<FractalKeyAction, LogicalKeyboardKey>.unmodifiable(
        <FractalKeyAction, LogicalKeyboardKey>{
          for (final FractalKeyAction action in FractalKeyAction.values)
            action: keybindFor(action),
        },
      );

  /// Effective rendering mode derived from [backend] and current [zoom].
  ActiveRenderMode get activeRenderMode {
    switch (_backend) {
      case RenderBackend.cpuFloat64:
        return ActiveRenderMode.cpuFloat64;
      case RenderBackend.gpuShader:
        return _zoom >= df64ThresholdZoom
            ? ActiveRenderMode.gpuDf64
            : ActiveRenderMode.gpuFloat32;
      case RenderBackend.auto:
        if (_zoom >= cpuDeepThresholdZoom) {
          return ActiveRenderMode.cpuFloat64;
        }
        if (_zoom >= df64ThresholdZoom) {
          return ActiveRenderMode.gpuDf64;
        }
        return ActiveRenderMode.gpuFloat32;
    }
  }

  /// Dynamic iteration limit scaled logarithmically with [zoom] when
  /// [autoIterations] is enabled, or [manualMaxIterations] otherwise.
  int get effectiveMaxIterations {
    if (!_autoIterations) {
      return (_manualMaxIterations * _quality.iterationMultiplier)
          .round()
          .clamp(50, 2000);
    }
    final double ratio = math.max(1.0, _zoom / 200.0);
    final double logZoom = math.log(ratio) / math.ln10;
    final int base = (120.0 + 75.0 * logZoom).round();
    return (base * _quality.iterationMultiplier).round().clamp(80, 2000);
  }

  /// Localization shorthand delegating to [dictionary].
  String tr(String key) => dictionary.value(key);

  /// Initializes persisted preferences and bundled localization assets.
  Future<void> init() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      _prefs = prefs;
      dictionary = Dictionary(
        path: 'assets/translations',
        debugHighlightFallbacks: kDebugMode,
        storage: CallbackDictionaryStorage(
          getFn: (String k) => prefs.get(k),
          putFn: (String k, dynamic v) => prefs.setString(k, v.toString()),
          deleteFn: (String k) => prefs.remove(k),
          containsKeyFn: (String k) => prefs.containsKey(k),
        ),
      );
      _restoreFromPrefs(prefs);
    } catch (e) {
      analytics.log('Engine', 'Warning', 'Preferences unavailable: $e');
    }

    try {
      await dictionary.setup(backgroundRefresh: false);
    } catch (e) {
      analytics.log('Dict', 'Warning', 'Dictionary setup fallback: $e');
    }

    try {
      await M3x.init(enableMesh: false);
    } catch (_) {}

    _initialized = true;
    analytics.log('Engine', 'Info', 'FractalEngine initialized');
    notifyListeners();
  }

  void _restoreFromPrefs(SharedPreferences prefs) {
    _fractalType = FractalType.fromName(prefs.getString(_prefFractalType));
    _centerX =
        (prefs.getDouble(_prefCenterX) ?? _fractalType.defaultCenterX).clamp(-4.0, 4.0);
    _centerY =
        (prefs.getDouble(_prefCenterY) ?? _fractalType.defaultCenterY).clamp(-4.0, 4.0);
    _zoom =
        (prefs.getDouble(_prefZoom) ?? _fractalType.defaultZoom).clamp(minZoom, maxZoom);
    _juliaCx = (prefs.getDouble(_prefJuliaCx) ?? -0.7269).clamp(-2.0, 2.0);
    _juliaCy = (prefs.getDouble(_prefJuliaCy) ?? 0.1889).clamp(-2.0, 2.0);
    _palette = FractalPalette.fromName(prefs.getString(_prefPalette));
    _colorOffset = (prefs.getDouble(_prefColorOffset) ?? 0.0).clamp(0.0, 1.0);
    _smoothColor = prefs.getBool(_prefSmoothColor) ?? true;
    _autoIterations = prefs.getBool(_prefAutoIter) ?? true;
    _manualMaxIterations = (prefs.getInt(_prefManualIter) ?? 300).clamp(50, 2000);
    _quality = RenderQuality.fromName(prefs.getString(_prefQuality));
    _backend = RenderBackend.fromName(prefs.getString(_prefBackend));
    _showHud = prefs.getBool(_prefShowHud) ?? true;
    _showTelemetry = prefs.getBool(_prefShowTelemetry) ?? true;
    _dragPreviewScale =
        (prefs.getDouble(_prefDragPreviewScale) ?? 0.20).clamp(0.10, 1.00);
    _overscanMultiplier =
        (prefs.getDouble(_prefOverscanMultiplier) ?? 2.0).clamp(0.0, 5.0);

    final String? rawCameras = prefs.getString(_prefFractalCameras);
    _fractalCameras.clear();
    if (rawCameras != null && rawCameras.isNotEmpty) {
      try {
        final dynamic decoded = jsonDecode(rawCameras);
        if (decoded is Map) {
          for (final FractalType type in FractalType.values) {
            final dynamic entry = decoded[type.name];
            if (entry is Map) {
              final dynamic cx = entry['centerX'];
              final dynamic cy = entry['centerY'];
              final dynamic z = entry['zoom'];
              if (cx is num && cy is num && z is num) {
                _fractalCameras[type] = (
                  centerX: cx.toDouble().clamp(-4.0, 4.0),
                  centerY: cy.toDouble().clamp(-4.0, 4.0),
                  zoom: z.toDouble().clamp(minZoom, maxZoom),
                );
              }
            }
          }
        }
      } catch (_) {}
    }
    _fractalCameras[_fractalType] = (
      centerX: _centerX,
      centerY: _centerY,
      zoom: _zoom,
    );

    final String? rawKeybinds = prefs.getString(_prefKeybinds);
    _keybinds.clear();
    if (rawKeybinds != null && rawKeybinds.isNotEmpty) {
      try {
        final dynamic decoded = jsonDecode(rawKeybinds);
        if (decoded is Map) {
          for (final FractalKeyAction action in FractalKeyAction.values) {
            final dynamic rawId = decoded[action.name];
            if (rawId is int) {
              _keybinds[action] =
                  LogicalKeyboardKey.findKeyByKeyId(rawId) ??
                  LogicalKeyboardKey(rawId);
            }
          }
        }
      } catch (_) {}
    }

    final String? rawBookmarks = prefs.getString(_prefCustomBookmarks);
    if (rawBookmarks != null && rawBookmarks.isNotEmpty) {
      try {
        final dynamic decoded = jsonDecode(rawBookmarks);
        if (decoded is List) {
          _customBookmarks
            ..clear()
            ..addAll(
              decoded
                  .whereType<Map<String, dynamic>>()
                  .map(FractalBookmark.fromJson),
            );
        }
      } catch (_) {}
    }
  }

  void _persistCamera() {
    _fractalCameras[_fractalType] = (
      centerX: _centerX,
      centerY: _centerY,
      zoom: _zoom,
    );
    final SharedPreferences? prefs = _prefs;
    if (prefs == null) return;
    prefs.setDouble(_prefCenterX, _centerX);
    prefs.setDouble(_prefCenterY, _centerY);
    prefs.setDouble(_prefZoom, _zoom);
    _persistFractalCameras();
  }

  void _persistFractalCameras() {
    final SharedPreferences? prefs = _prefs;
    if (prefs == null) return;
    if (_fractalCameras.isEmpty) {
      prefs.remove(_prefFractalCameras);
      return;
    }
    final Map<String, Map<String, double>> encoded =
        <String, Map<String, double>>{
      for (final MapEntry<FractalType,
              ({double centerX, double centerY, double zoom})> entry
          in _fractalCameras.entries)
        entry.key.name: <String, double>{
          'centerX': entry.value.centerX,
          'centerY': entry.value.centerY,
          'zoom': entry.value.zoom,
        },
    };
    prefs.setString(_prefFractalCameras, jsonEncode(encoded));
  }

  void _persistKeybinds() {
    final SharedPreferences? prefs = _prefs;
    if (prefs == null) return;
    if (_keybinds.isEmpty) {
      prefs.remove(_prefKeybinds);
      return;
    }
    final Map<String, int> encoded = <String, int>{
      for (final MapEntry<FractalKeyAction, LogicalKeyboardKey> entry
          in _keybinds.entries)
        entry.key.name: entry.value.keyId,
    };
    prefs.setString(_prefKeybinds, jsonEncode(encoded));
  }

  void _persistAllSettings() {
    final SharedPreferences? prefs = _prefs;
    if (prefs == null) return;
    prefs.setString(_prefFractalType, _fractalType.name);
    prefs.setDouble(_prefCenterX, _centerX);
    prefs.setDouble(_prefCenterY, _centerY);
    prefs.setDouble(_prefZoom, _zoom);
    prefs.setDouble(_prefJuliaCx, _juliaCx);
    prefs.setDouble(_prefJuliaCy, _juliaCy);
    prefs.setString(_prefPalette, _palette.name);
    prefs.setDouble(_prefColorOffset, _colorOffset);
    prefs.setBool(_prefSmoothColor, _smoothColor);
    prefs.setBool(_prefAutoIter, _autoIterations);
    prefs.setInt(_prefManualIter, _manualMaxIterations);
    prefs.setString(_prefQuality, _quality.name);
    prefs.setString(_prefBackend, _backend.name);
    prefs.setBool(_prefShowHud, _showHud);
    prefs.setBool(_prefShowTelemetry, _showTelemetry);
    prefs.setDouble(_prefDragPreviewScale, _dragPreviewScale);
    prefs.setDouble(_prefOverscanMultiplier, _overscanMultiplier);
  }

  void _persistBookmarks() {
    final SharedPreferences? prefs = _prefs;
    if (prefs == null) return;
    final String encoded = jsonEncode(
      _customBookmarks.map((b) => b.toJson()).toList(),
    );
    prefs.setString(_prefCustomBookmarks, encoded);
  }

  // ---------------------------------------------------------------------------
  // Focal-Point Camera Math
  // ---------------------------------------------------------------------------

  /// Maps a logical viewport point [localPos] to complex-plane coordinates.
  Offset screenToWorld(Offset localPos, Size viewport) {
    if (viewport.isEmpty) {
      return Offset(_centerX, _centerY);
    }
    return Offset(
      _centerX + (localPos.dx - viewport.width * 0.5) / _zoom,
      _centerY + (localPos.dy - viewport.height * 0.5) / _zoom,
    );
  }

  /// Pans the camera 1:1 with pointer movement in logical pixels.
  void panBy(Offset screenDelta, {bool persist = true}) {
    if (screenDelta == Offset.zero) return;
    _centerX = (_centerX - screenDelta.dx / _zoom).clamp(-4.0, 4.0);
    _centerY = (_centerY - screenDelta.dy / _zoom).clamp(-4.0, 4.0);
    if (persist) {
      _persistCamera();
    }
    notifyListeners();
  }

  /// Zooms by [scaleFactor] keeping the world point under [localPos] pinned.
  void zoomAtFocalPoint(
    Offset localPos,
    Size viewport,
    double scaleFactor, {
    bool persist = true,
  }) {
    transformAtFocalPoint(
      focalPos: localPos,
      focalDelta: Offset.zero,
      scaleFactor: scaleFactor,
      viewport: viewport,
      persist: persist,
    );
  }

  /// Atomically applies incremental pan ([focalDelta]) and pinch/wheel zoom
  /// ([scaleFactor]) around [focalPos] so the fractal stays anchored under the
  /// user's fingers or cursor.
  void transformAtFocalPoint({
    required Offset focalPos,
    required Offset focalDelta,
    required double scaleFactor,
    required Size viewport,
    bool persist = true,
  }) {
    if (!scaleFactor.isFinite || scaleFactor <= 0) return;
    if (viewport.isEmpty) return;

    final Offset prevFocal = focalPos - focalDelta;
    final Offset anchoredWorld = screenToWorld(prevFocal, viewport);
    final double newZoom = (_zoom * scaleFactor).clamp(minZoom, maxZoom);

    _zoom = newZoom;
    _centerX = (anchoredWorld.dx - (focalPos.dx - viewport.width * 0.5) / newZoom)
        .clamp(-4.0, 4.0);
    _centerY = (anchoredWorld.dy - (focalPos.dy - viewport.height * 0.5) / newZoom)
        .clamp(-4.0, 4.0);

    if (persist) {
      _persistCamera();
    }
    notifyListeners();
  }

  void setInteracting(bool interacting) {
    if (_isInteracting == interacting) return;
    _isInteracting = interacting;
    if (!interacting) {
      _persistCamera();
    }
    logPerf('interact', <String, Object?>{'active': interacting});
    notifyListeners();
  }

  void setCpuRendering(bool rendering) {
    if (_isCpuRendering == rendering) return;
    _isCpuRendering = rendering;
    notifyListeners();
  }

  void setExporting(bool exporting) {
    if (_isExporting == exporting) return;
    _isExporting = exporting;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Mutators
  // ---------------------------------------------------------------------------

  void setFractalType(FractalType type, {bool resetCamera = false}) {
    if (_fractalType == type && !resetCamera) return;
    _fractalCameras[_fractalType] = (
      centerX: _centerX,
      centerY: _centerY,
      zoom: _zoom,
    );
    _fractalType = type;
    if (resetCamera) {
      _centerX = type.defaultCenterX;
      _centerY = type.defaultCenterY;
      _zoom = type.defaultZoom;
      _fractalCameras[type] = (
        centerX: _centerX,
        centerY: _centerY,
        zoom: _zoom,
      );
    } else {
      final ({double centerX, double centerY, double zoom})? saved =
          _fractalCameras[type];
      if (saved != null) {
        _centerX = saved.centerX;
        _centerY = saved.centerY;
        _zoom = saved.zoom;
      } else {
        _centerX = type.defaultCenterX;
        _centerY = type.defaultCenterY;
        _zoom = type.defaultZoom;
        _fractalCameras[type] = (
          centerX: _centerX,
          centerY: _centerY,
          zoom: _zoom,
        );
      }
    }
    _persistAllSettings();
    _persistFractalCameras();
    analytics.log('Fractal', 'Info', 'Selected ${type.name}');
    logPerf('fractal', <String, Object?>{'type': type.name});
    notifyListeners();
  }

  void setJuliaC(double cx, double cy) {
    _juliaCx = cx.clamp(-2.0, 2.0);
    _juliaCy = cy.clamp(-2.0, 2.0);
    _prefs?.setDouble(_prefJuliaCx, _juliaCx);
    _prefs?.setDouble(_prefJuliaCy, _juliaCy);
    notifyListeners();
  }

  void resetJuliaC() {
    _juliaCx = -0.7269;
    _juliaCy = 0.1889;
    _prefs?.setDouble(_prefJuliaCx, _juliaCx);
    _prefs?.setDouble(_prefJuliaCy, _juliaCy);
    notifyListeners();
  }

  void setPalette(FractalPalette value) {
    if (_palette == value) return;
    _palette = value;
    _prefs?.setString(_prefPalette, value.name);
    notifyListeners();
  }

  void cyclePalette() {
    final int next = (_palette.index + 1) % FractalPalette.values.length;
    setPalette(FractalPalette.values[next]);
  }

  void setColorOffset(double offset) {
    _colorOffset = offset.clamp(0.0, 1.0);
    _prefs?.setDouble(_prefColorOffset, _colorOffset);
    notifyListeners();
  }

  void setSmoothColor(bool smooth) {
    if (_smoothColor == smooth) return;
    _smoothColor = smooth;
    _prefs?.setBool(_prefSmoothColor, smooth);
    notifyListeners();
  }

  void setAutoIterations(bool auto) {
    if (_autoIterations == auto) return;
    _autoIterations = auto;
    _prefs?.setBool(_prefAutoIter, auto);
    notifyListeners();
  }

  void setManualMaxIterations(int iterations) {
    _manualMaxIterations = iterations.clamp(50, 2000);
    _prefs?.setInt(_prefManualIter, _manualMaxIterations);
    notifyListeners();
  }

  void setQuality(RenderQuality value) {
    if (_quality == value) return;
    _quality = value;
    _prefs?.setString(_prefQuality, value.name);
    logPerf('quality', <String, Object?>{'quality': value.name});
    notifyListeners();
  }

  void setBackend(RenderBackend value) {
    if (_backend == value) return;
    _backend = value;
    _prefs?.setString(_prefBackend, value.name);
    logPerf('mode', <String, Object?>{'backend': _backend.name});
    notifyListeners();
  }

  void setShowHud(bool show) {
    if (_showHud == show) return;
    _showHud = show;
    _prefs?.setBool(_prefShowHud, show);
    notifyListeners();
  }

  void toggleHud() => setShowHud(!_showHud);

  void setShowTelemetry(bool show) {
    if (_showTelemetry == show) return;
    _showTelemetry = show;
    _prefs?.setBool(_prefShowTelemetry, show);
    notifyListeners();
  }

  void setDragPreviewScale(double value) {
    final double clamped = value.clamp(0.10, 1.00);
    if ((_dragPreviewScale - clamped).abs() < 1e-4) return;
    _dragPreviewScale = clamped;
    _prefs?.setDouble(_prefDragPreviewScale, _dragPreviewScale);
    notifyListeners();
  }

  void setOverscanMultiplier(double value) {
    final double clamped = value.clamp(0.0, 5.0);
    if ((_overscanMultiplier - clamped).abs() < 1e-4) return;
    _overscanMultiplier = clamped;
    _prefs?.setDouble(_prefOverscanMultiplier, _overscanMultiplier);
    notifyListeners();
  }

  void setKeybind(FractalKeyAction action, LogicalKeyboardKey key) {
    if (keybindFor(action) == key) return;
    if (key == action.defaultKey) {
      _keybinds.remove(action);
    } else {
      _keybinds[action] = key;
    }
    _persistKeybinds();
    notifyListeners();
  }

  void resetKeybinds() {
    if (_keybinds.isEmpty) return;
    _keybinds.clear();
    _prefs?.remove(_prefKeybinds);
    notifyListeners();
  }

  void resetView() {
    _centerX = _fractalType.defaultCenterX;
    _centerY = _fractalType.defaultCenterY;
    _zoom = _fractalType.defaultZoom;
    _persistCamera();
    notifyListeners();
  }

  void resetAllSettings() {
    _fractalType = FractalType.mandelbrot;
    _centerX = _fractalType.defaultCenterX;
    _centerY = _fractalType.defaultCenterY;
    _zoom = _fractalType.defaultZoom;
    _juliaCx = -0.7269;
    _juliaCy = 0.1889;
    _palette = FractalPalette.system;
    _colorOffset = 0.0;
    _smoothColor = true;
    _autoIterations = true;
    _manualMaxIterations = 300;
    _quality = RenderQuality.native;
    _backend = RenderBackend.auto;
    _showHud = true;
    _showTelemetry = true;
    _dragPreviewScale = 0.20;
    _overscanMultiplier = 2.0;
    _fractalCameras.clear();
    _prefs?.remove(_prefFractalCameras);
    _persistAllSettings();
    notifyListeners();
  }

  void applyBookmark(FractalBookmark bookmark) {
    _fractalType = bookmark.fractalType;
    _centerX = bookmark.centerX.clamp(-4.0, 4.0);
    _centerY = bookmark.centerY.clamp(-4.0, 4.0);
    _zoom = bookmark.zoom.clamp(minZoom, maxZoom);
    _juliaCx = bookmark.juliaCx.clamp(-2.0, 2.0);
    _juliaCy = bookmark.juliaCy.clamp(-2.0, 2.0);
    _palette = bookmark.palette;
    _fractalCameras[_fractalType] = (
      centerX: _centerX,
      centerY: _centerY,
      zoom: _zoom,
    );
    _persistAllSettings();
    _persistFractalCameras();
    analytics.log('Bookmark', 'Info', 'Loaded ${bookmark.name}');
    notifyListeners();
  }

  void addCustomBookmark(String name) {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final FractalBookmark bookmark = FractalBookmark(
      id: 'user_${DateTime.now().microsecondsSinceEpoch}',
      name: trimmed,
      fractalType: _fractalType,
      centerX: _centerX,
      centerY: _centerY,
      zoom: _zoom,
      juliaCx: _juliaCx,
      juliaCy: _juliaCy,
      palette: _palette,
      isBuiltIn: false,
    );
    _customBookmarks.insert(0, bookmark);
    _persistBookmarks();
    notifyListeners();
  }

  void removeCustomBookmark(String id) {
    _customBookmarks.removeWhere((b) => b.id == id);
    _persistBookmarks();
    notifyListeners();
  }

  Future<void> setLanguage(String? code) async {
    if (code == null) {
      await dictionary.setSystemLanguage();
    } else {
      await dictionary.setLanguage(code);
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Telemetry & Formatting
  // ---------------------------------------------------------------------------

  /// Emits a structured `[FV_PERF]` debug log line for profiling.
  void logPerf(
    String event, [
    Map<String, Object?> fields = const <String, Object?>{},
  ]) {
    if (kReleaseMode) return;
    final StringBuffer sb = StringBuffer(
      '[FV_PERF] event=$event mode=${activeRenderMode.badge} zoom=${formatZoom(_zoom)} iter=$effectiveMaxIterations',
    );
    fields.forEach((String key, Object? value) {
      if (value != null) {
        sb.write(' $key=$value');
      }
    });
    debugPrint(sb.toString());
  }

  /// Clears the rolling frame-duration window so switching between GPU and CPU
  /// modes does not carry stale samples across renderers.
  void resetFrameTimingWindow() {
    _recentFrameMs.clear();
  }

  /// Records a single render frame duration in milliseconds and updates FPS +
  /// sparkline history (using a 4-sample rolling window capped at 120 FPS).
  void recordFrameDurationMs(
    double ms, {
    double? buildMs,
    double? rasterMs,
  }) {
    final double clampedMs = ms.isFinite ? ms.clamp(0.1, 10000.0) : 16.6;
    _lastFrameTimeMs = clampedMs;
    _recentFrameMs.addLast(clampedMs);
    while (_recentFrameMs.length > 4) {
      _recentFrameMs.removeFirst();
    }
    final double avgMs =
        _recentFrameMs.reduce((a, b) => a + b) / _recentFrameMs.length;
    _currentFps = (1000.0 / avgMs).clamp(0.1, 120.0);
    final double normalized = (_currentFps / 120.0).clamp(0.0, 1.0);
    _fpsHistory.add(normalized);
    if (_fpsHistory.length > 30) {
      _fpsHistory.removeAt(0);
    }
    notifyListeners();
  }

  /// Formats [z] relative to the default overview zoom (`240.0`) or absolute
  /// scale cleanly across 15 orders of magnitude.
  static String formatZoom(double z) {
    final double rel = z / 240.0;
    if (rel < 1000.0) {
      return rel < 10.0
          ? '${rel.toStringAsFixed(2)}×'
          : '${rel.toStringAsFixed(1)}×';
    }
    if (rel < 1e6) {
      return '${(rel / 1e3).toStringAsFixed(2)}K×';
    }
    final int exp = (math.log(rel) / math.ln10).floor();
    final double mantissa = rel / math.pow(10, exp);
    return '${mantissa.toStringAsFixed(2)}e$exp×';
  }

  /// Formats a complex-plane coordinate with precision matched to [z].
  static String formatCoord(double coord, double z) {
    final int digits =
        (4 + (math.log(math.max(1.0, z / 240.0)) / math.ln10).ceil())
            .clamp(4, 16);
    return coord.toStringAsFixed(digits);
  }

  /// Formats a frame duration [ms] as milliseconds or seconds.
  static String formatFrameTime(double ms) =>
      ms >= 1000.0 ? '${(ms / 1000.0).toStringAsFixed(2)} s' : '${ms.toStringAsFixed(1)} ms';

  /// Formats [fps] with one decimal place below 10 FPS and integer precision at
  /// or above 10 FPS.
  static String formatFps(double fps) =>
      fps < 10.0 ? fps.toStringAsFixed(1) : fps.toStringAsFixed(0);

  /// Formats a [LogicalKeyboardKey] into a concise, human-readable label.
  static String formatKeyLabel(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.equal) return '+';
    if (key == LogicalKeyboardKey.minus) return '-';
    if (key == LogicalKeyboardKey.arrowUp) return '↑';
    if (key == LogicalKeyboardKey.arrowDown) return '↓';
    if (key == LogicalKeyboardKey.arrowLeft) return '←';
    if (key == LogicalKeyboardKey.arrowRight) return '→';
    if (key == LogicalKeyboardKey.space) return 'Space';
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      return 'Enter';
    }
    if (key == LogicalKeyboardKey.escape) return 'Esc';
    if (key == LogicalKeyboardKey.tab) return 'Tab';
    if (key == LogicalKeyboardKey.backspace) return 'Backspace';
    if (key == LogicalKeyboardKey.delete) return 'Del';
    if (key == LogicalKeyboardKey.pageUp) return 'PgUp';
    if (key == LogicalKeyboardKey.pageDown) return 'PgDn';
    if (key == LogicalKeyboardKey.home) return 'Home';
    if (key == LogicalKeyboardKey.end) return 'End';
    if (key == LogicalKeyboardKey.numpadAdd) return 'Num +';
    if (key == LogicalKeyboardKey.numpadSubtract) return 'Num -';
    final String label = key.keyLabel.trim();
    if (label.isNotEmpty) {
      return label.length == 1 ? label.toUpperCase() : label;
    }
    return key.debugName ?? 'Key ${key.keyId}';
  }
}
