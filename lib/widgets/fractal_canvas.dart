import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../engine/big_float.dart';
import '../engine/cpu_renderer.dart';
import '../engine/fractal_engine.dart';
import '../engine/fractal_models.dart';
import '../engine/perturbation_solver.dart';

/// Interactive fractal viewport supporting real-time GPU fragment shader
/// rendering (`float32` and `df64` double-float) plus progressive multi-isolate
/// CPU `float64` deep-zoom rendering, pinch/pan/wheel gestures, double-tap
/// zoom, and desktop keyboard shortcuts.
class FractalCanvas extends StatefulWidget {
  final VoidCallback? onTap;
  final VoidCallback? onToggleInspector;
  final VoidCallback? onLongPress;
  final ValueChanged<Size>? onViewportChanged;

  const FractalCanvas({
    super.key,
    this.onTap,
    this.onToggleInspector,
    this.onLongPress,
    this.onViewportChanged,
  });

  @override
  State<FractalCanvas> createState() => _FractalCanvasState();
}

class _FractalCanvasState extends State<FractalCanvas>
    with TickerProviderStateMixin {
  static const Set<FractalKeyAction> _continuousActions = <FractalKeyAction>{
    FractalKeyAction.panUp,
    FractalKeyAction.panDown,
    FractalKeyAction.panLeft,
    FractalKeyAction.panRight,
    FractalKeyAction.zoomIn,
    FractalKeyAction.zoomOut,
    FractalKeyAction.rotateLeft,
    FractalKeyAction.rotateRight,
  };

  static const List<double> _lodStages = <double>[0.04, 0.10, 0.25, 0.50];

  static double _nextProgressiveScale(double currentScale, double fullScale) {
    for (final double stage in _lodStages) {
      if (stage < fullScale - 1e-4 && stage > currentScale + 1e-4) {
        return stage;
      }
    }
    return fullScale;
  }

  ui.FragmentProgram? _program;
  ui.FragmentShader? _shader;
  ui.FragmentShader? _bakeShader;
  ui.FragmentProgram? _ptProgram;
  ui.FragmentShader? _ptShader;
  ui.FragmentShader? _ptBakeShader;
  bool _shaderLoadFailed = false;

  FractalEngine? _engine;
  Size _viewportSize = Size.zero;

  // Gesture state kept exclusively on State (never inside build).
  double _lastScale = 1.0;
  double _lastRotation = 0.0;
  Offset? _doubleTapPosition;

  // Smooth 60 FPS keyboard navigation state.
  final Set<FractalKeyAction> _heldActions = <FractalKeyAction>{};
  late final Ticker _keyboardTicker;
  Duration _lastTickElapsed = Duration.zero;

  // CPU float64 progressive rendering state.
  int _renderToken = 0;
  Timer? _cpuDebounceTimer;
  ui.Image? _cpuImage;
  _CpuRenderSnapshot? _cpuImageSnapshot;
  double _cpuImageScale = 0.0;
  _CpuRenderSnapshot? _lastScheduledSnapshot;
  bool _cpuInFlight = false;
  bool _cpuInFlightIsPreview = false;
  CpuRenderCancellationToken? _activeCpuCancelToken;
  ui.Image? _cpuOverscanImage;
  _CpuRenderSnapshot? _cpuOverscanSnapshot;
  double _cpuOverscanMultiplier = 2.0;
  int _overscanToken = 0;
  final List<ui.Image> _retiredImages = <ui.Image>[];

  // Offscreen GPU frame baking state (eliminates UI animation shader stutter
  // and enables true resolution scaling for Performance / Balanced presets).
  Timer? _gpuBakeTimer;
  int _gpuBakeToken = 0;
  ui.Image? _gpuBakedImage;
  _GpuBakeKey? _gpuBakedKey;
  double _gpuBakedScale = 1.0;
  _GpuBakeKey? _lastScheduledGpuKey;
  bool _gpuBakeInFlight = false;

  // Perturbation reference orbit & GPU texture state.
  PerturbationOrbitResult? _ptOrbit;
  ui.Image? _ptOrbitTexture;
  BigFixed? _ptOrbitCenterXBig;
  BigFixed? _ptOrbitCenterYBig;
  double _ptOrbitZoom = 0.0;
  int _ptOrbitRequestedMaxIter = 0;
  int _ptOrbitFractalType = -1;
  double _ptOrbitJuliaCx = 0.0;
  double _ptOrbitJuliaCy = 0.0;
  int _ptOrbitToken = 0;
  bool _ptOrbitInFlight = false;

  // Idle progressive sharpening crossfade state.
  late final AnimationController _fadeController;
  ui.Image? _prevFadeImage;
  double _prevFadeScale = 0.0;

  // Unified progressive-LOD refinement progress state.
  _CpuRenderSnapshot? _refinementSnapshot;
  double _refinementTotalWeight = 0.0;
  double _refinementDoneWeight = 0.0;

  // Frame telemetry state (throttled and loop-free).
  _VisualKey? _lastVisualKey;
  ActiveRenderMode? _lastActiveMode;
  bool _awaitingTimingSample = false;
  DateTime _lastTelemetryAt = DateTime.fromMillisecondsSinceEpoch(0);
  Color _lastPrimary = const Color(0xFF008080);
  Color _lastTertiary = const Color(0xFF008080);

  @override
  void initState() {
    super.initState();
    _keyboardTicker = createTicker(_onKeyboardTick);
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 320),
      value: 1.0,
      vsync: this,
    )..addStatusListener((AnimationStatus status) {
        if (status == AnimationStatus.completed) {
          _clearCrossfade();
        }
      });
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
    _loadShader();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ColorScheme scheme = Theme.of(context).colorScheme;
    _lastPrimary = scheme.primary;
    _lastTertiary = scheme.tertiary;

    final FractalEngine nextEngine = context.read<FractalEngine>();
    if (!identical(_engine, nextEngine)) {
      _engine?.removeListener(_onEngineChanged);
      _engine = nextEngine;
      _engine!.addListener(_onEngineChanged);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _syncVisualAndSchedule();
        }
      });
    }
  }

  Future<void> _loadShader() async {
    try {
      final ui.FragmentProgram program =
          await ui.FragmentProgram.fromAsset('shaders/fractal.frag');
      final ui.FragmentProgram ptProgram =
          await ui.FragmentProgram.fromAsset('shaders/perturbation.frag');
      if (!mounted) return;
      final ui.FragmentShader shader = program.fragmentShader();
      final ui.FragmentShader bakeShader = program.fragmentShader();
      final ui.FragmentShader ptShader = ptProgram.fragmentShader();
      final ui.FragmentShader ptBakeShader = ptProgram.fragmentShader();
      setState(() {
        _program = program;
        _shader = shader;
        _bakeShader = bakeShader;
        _ptProgram = ptProgram;
        _ptShader = ptShader;
        _ptBakeShader = ptBakeShader;
        _shaderLoadFailed = false;
      });
      _syncVisualAndSchedule();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _shaderLoadFailed = true;
      });
    }
  }

  void _onEngineChanged() {
    if (!mounted) return;
    _syncVisualAndSchedule();
  }

  void _syncVisualAndSchedule() {
    final FractalEngine? engine = _engine;
    if (engine == null || !mounted) return;

    final ActiveRenderMode currentMode = engine.activeRenderMode;
    if (_lastActiveMode != null && _lastActiveMode != currentMode) {
      engine.resetFrameTimingWindow();
      _clearCrossfade();
    }
    _lastActiveMode = currentMode;

    final _VisualKey visualKey = _VisualKey.from(
      engine: engine,
      viewport: _viewportSize,
      primary: _lastPrimary,
      tertiary: _lastTertiary,
      cpuImageId: _cpuImage?.hashCode ?? 0,
      gpuBakedImageId: _gpuBakedImage?.hashCode ?? 0,
    );

    if (visualKey != _lastVisualKey) {
      _lastVisualKey = visualKey;
      _awaitingTimingSample = true;
    }

    _maybeScheduleCpuRender(engine);
    _maybeSchedulePtOrbit(engine);
    _maybeScheduleGpuBake(engine);
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    if (!mounted || timings.isEmpty || !_awaitingTimingSample) return;
    final FractalEngine? engine = _engine;
    if (engine == null) return;

    final DateTime now = DateTime.now();
    if (now.difference(_lastTelemetryAt).inMilliseconds < 250 &&
        engine.isInteracting) {
      return;
    }

    _awaitingTimingSample = false;
    _lastTelemetryAt = now;

    final FrameTiming latest = timings.last;
    final double buildMs = latest.buildDuration.inMicroseconds / 1000.0;
    final double rasterMs = latest.rasterDuration.inMicroseconds / 1000.0;
    final double totalMs = buildMs + rasterMs;
    if (!engine.activeRenderMode.isCpu) {
      engine.recordFrameDurationMs(
        totalMs,
        updateLod: !((engine.activeRenderMode == ActiveRenderMode.gpuDf64 ||
                engine.activeRenderMode == ActiveRenderMode.gpuPerturbation) &&
            engine.isInteracting),
      );
    }
    engine.logPerf('frame', <String, Object?>{
      'buildMs': buildMs.toStringAsFixed(1),
      'rasterMs': rasterMs.toStringAsFixed(1),
      'totalMs': totalMs.toStringAsFixed(1),
      'fps': engine.currentFps.toStringAsFixed(0),
      'quality': engine.quality.name,
      'interacting': engine.isInteracting,
    });
  }

  void _maybeScheduleCpuRender(FractalEngine engine) {
    if (_viewportSize.isEmpty) return;

    final bool needCpu = engine.activeRenderMode.isCpu;
    if (!needCpu) {
      _cancelCpuRenders(engine);
      return;
    }

    if (engine.overscanMultiplier < 1.05 && _cpuOverscanImage != null) {
      _clearCpuOverscan();
    }

    final double dpr = MediaQuery.devicePixelRatioOf(context);
    final _CpuRenderSnapshot current = _CpuRenderSnapshot.from(
      engine: engine,
      viewport: _viewportSize,
      devicePixelRatio: dpr,
      primary: _lastPrimary,
      tertiary: _lastTertiary,
    );

    final bool matchesCompletedFull = _cpuImage != null &&
        _cpuImageSnapshot == current &&
        (_cpuImageScale - current.fullScale).abs() < 1e-4;
    if (matchesCompletedFull) {
      _cpuDebounceTimer?.cancel();
      if (engine.isCpuRendering) {
        engine.setCpuRendering(false);
      }
      return;
    }

    final bool sameInFlight = _cpuInFlight && _lastScheduledSnapshot == current;
    if (sameInFlight && (engine.isInteracting || !_cpuInFlightIsPreview)) {
      return;
    }

    _lastScheduledSnapshot = current;
    _cpuDebounceTimer?.cancel();

    // During active pan/zoom/twist, throttle preview passes at effectiveDragScale.
    if (engine.isInteracting) {
      if (!_cpuInFlight) {
        final double dragScale =
            math.min(engine.effectiveDragScale, current.fullScale);
        _startCpuPass(
          engine,
          current,
          passScale: dragScale,
          isPreview: dragScale < current.fullScale - 1e-4,
        );
      }
      return;
    }

    // Idle: refine progressively through [0.10, 0.25, 0.50, fullScale].
    final double matchedScale =
        (_cpuImage != null && _cpuImageSnapshot == current)
            ? _cpuImageScale
            : 0.0;
    final double nextScale =
        _nextProgressiveScale(matchedScale, current.fullScale);

    if (matchedScale < 0.12 - 1e-4 &&
        !_cpuInFlight &&
        nextScale < current.fullScale - 1e-4) {
      _startCpuPass(
        engine,
        current,
        passScale: nextScale,
        isPreview: true,
      );
      return;
    }

    if (sameInFlight) {
      return;
    }

    final int scheduledToken = _renderToken;
    _cpuDebounceTimer = Timer(const Duration(milliseconds: 100), () {
      if (!mounted ||
          scheduledToken != _renderToken ||
          engine.isInteracting ||
          !engine.activeRenderMode.isCpu) {
        return;
      }
      final double currentScale =
          (_cpuImage != null && _cpuImageSnapshot == current)
              ? _cpuImageScale
              : 0.0;
      final double stageScale =
          _nextProgressiveScale(currentScale, current.fullScale);
      _startCpuPass(
        engine,
        current,
        passScale: stageScale,
        isPreview: stageScale < current.fullScale - 1e-4,
      );
    });
  }

  void _initRefinementWeights(_CpuRenderSnapshot snapshot, double startScale) {
    double total = 0.0;
    double s = startScale;
    for (int i = 0; i < 16; i++) {
      final double next = _nextProgressiveScale(s, snapshot.fullScale);
      if (next <= s + 1e-6 && next < snapshot.fullScale - 1e-4) {
        break;
      }
      total += next * next;
      if (next >= snapshot.fullScale - 1e-4) {
        break;
      }
      s = next;
    }
    _refinementSnapshot = snapshot;
    _refinementTotalWeight = total;
    _refinementDoneWeight = 0.0;
  }

  void _abortActiveCpuPass() {
    _activeCpuCancelToken?.cancel();
    _activeCpuCancelToken = null;
    _renderToken++;
    _cpuInFlight = false;
    _cpuInFlightIsPreview = false;
    _refinementSnapshot = null;
    _refinementTotalWeight = 0.0;
    _refinementDoneWeight = 0.0;
    _engine?.setRenderProgress(null);
  }

  void _cancelCpuRenders(FractalEngine engine) {
    _clearCrossfade();
    _abortActiveCpuPass();
    _overscanToken++;
    _cpuDebounceTimer?.cancel();
    _cpuDebounceTimer = null;
    _lastScheduledSnapshot = null;
    if (engine.isCpuRendering) {
      engine.setCpuRendering(false);
    }
    if (_cpuImage != null || _cpuOverscanImage != null) {
      final ui.Image? old = _cpuImage;
      final ui.Image? oldOverscan = _cpuOverscanImage;
      setState(() {
        _cpuImage = null;
        _cpuImageSnapshot = null;
        _cpuImageScale = 0.0;
        _cpuOverscanImage = null;
        _cpuOverscanSnapshot = null;
      });
      if (old != null) {
        _scheduleImageDispose(old);
      }
      if (oldOverscan != null) {
        _scheduleImageDispose(oldOverscan);
      }
    }
  }

  Future<void> _startCpuPass(
    FractalEngine engine,
    _CpuRenderSnapshot snapshot, {
    required double passScale,
    required bool isPreview,
  }) async {
    final int token = ++_renderToken;
    _activeCpuCancelToken?.cancel();
    final CpuRenderCancellationToken cancelToken =
        CpuRenderCancellationToken();
    _activeCpuCancelToken = cancelToken;
    _cpuInFlight = true;
    _cpuInFlightIsPreview = isPreview;
    engine.setCpuRendering(true);

    final double pixelRatio = snapshot.devicePixelRatio * passScale;
    final int targetW =
        (snapshot.viewport.width * pixelRatio).round().clamp(16, 3840);
    final int targetH =
        (snapshot.viewport.height * pixelRatio).round().clamp(16, 3840);

    final CpuRenderRequest request = CpuRenderRequest(
      width: targetW,
      height: targetH,
      logicalWidth: snapshot.viewport.width,
      logicalHeight: snapshot.viewport.height,
      centerX: snapshot.centerX,
      centerY: snapshot.centerY,
      zoom: snapshot.zoom,
      rotCos: math.cos(snapshot.rotation),
      rotSin: math.sin(snapshot.rotation),
      maxIterations: snapshot.maxIterations,
      fractalTypeIndex: snapshot.fractalTypeIndex,
      juliaCx: snapshot.juliaCx,
      juliaCy: snapshot.juliaCy,
      paletteIndex: snapshot.paletteIndex,
      primaryR: snapshot.primaryR,
      primaryG: snapshot.primaryG,
      primaryB: snapshot.primaryB,
      secondaryR: snapshot.secondaryR,
      secondaryG: snapshot.secondaryG,
      secondaryB: snapshot.secondaryB,
      colorOffset: snapshot.colorOffset,
      smoothColor: snapshot.smoothColor,
    );

    final bool trackProgress = !engine.isInteracting;
    double stageWeight = 0.0;
    if (trackProgress) {
      final double matchedScale =
          (_cpuImage != null && _cpuImageSnapshot == snapshot)
              ? _cpuImageScale
              : 0.0;
      if (_refinementSnapshot != snapshot || _refinementTotalWeight <= 0) {
        _initRefinementWeights(snapshot, matchedScale);
      }
      stageWeight = passScale * passScale;
    }
    final Stopwatch sw = Stopwatch()..start();
    try {
      final ui.Image image = await CpuFractalRenderer.renderImage(
        request,
        onProgress: trackProgress
            ? (double p) {
                if (mounted && token == _renderToken) {
                  final double unified = _refinementTotalWeight > 0
                      ? ((_refinementDoneWeight + p * stageWeight) /
                              _refinementTotalWeight)
                          .clamp(0.0, 1.0)
                      : p.clamp(0.0, 1.0);
                  engine.setRenderProgress(unified);
                }
              }
            : null,
        cancellationToken: cancelToken,
      );
      sw.stop();

      if (!mounted || token != _renderToken || !engine.activeRenderMode.isCpu) {
        image.dispose();
        return;
      }

      final ui.Image? oldImage = _cpuImage;
      final double prevScale = _cpuImageScale;
      final bool shouldCrossfade = !engine.isInteracting &&
          oldImage != null &&
          _cpuImageSnapshot == snapshot &&
          passScale > prevScale + 1e-4;
      setState(() {
        _cpuImage = image;
        _cpuImageSnapshot = snapshot;
        _cpuImageScale = passScale;
        if (oldImage != null) {
          if (shouldCrossfade) {
            _startCrossfadeFrom(oldImage, prevScale);
          } else {
            if (_prevFadeImage != null) {
              _clearCrossfade();
            }
            _scheduleImageDispose(oldImage);
          }
        } else if (_prevFadeImage != null) {
          _clearCrossfade();
        }
      });

      final double cpuMs = sw.elapsedMicroseconds / 1000.0;
      engine.recordRenderCostSample(
        mode: ActiveRenderMode.cpuFloat64,
        pixelCount: targetW * targetH,
        iterations: snapshot.maxIterations,
        durationMs: cpuMs,
      );
      engine.logPerf('cpu_pass', <String, Object?>{
        'cpuMs': cpuMs.toStringAsFixed(1),
        'preview': isPreview,
        'scale': passScale.toStringAsFixed(2),
        'res': '${targetW}x$targetH',
      });
      if (engine.activeRenderMode.isCpu) {
        engine.recordFrameDurationMs(cpuMs);
      }
      if (!isPreview) {
        if (engine.overscanMultiplier < 1.05) {
          _clearCpuOverscan();
        } else {
          unawaited(_startCpuOverscanPass(engine, snapshot));
        }
      }
      if (trackProgress) {
        _refinementDoneWeight += stageWeight;
      }
    } on CpuRenderCancelledException {
      // Cancelled intentionally on new interaction or disposal.
    } catch (_) {
      // Ignore render interruptions on isolate cancellation or disposal.
    } finally {
      if (identical(_activeCpuCancelToken, cancelToken)) {
        _activeCpuCancelToken = null;
      }
      if (token == _renderToken) {
        _cpuInFlight = false;
        _cpuInFlightIsPreview = false;
        if (mounted && engine.activeRenderMode.isCpu) {
          final double dpr = MediaQuery.devicePixelRatioOf(context);
          final _CpuRenderSnapshot latest = _CpuRenderSnapshot.from(
            engine: engine,
            viewport: _viewportSize,
            devicePixelRatio: dpr,
            primary: _lastPrimary,
            tertiary: _lastTertiary,
          );
          if (engine.isInteracting) {
            if (latest != snapshot) {
              _lastScheduledSnapshot = latest;
              final double dragScale =
                  math.min(engine.effectiveDragScale, latest.fullScale);
              unawaited(_startCpuPass(
                engine,
                latest,
                passScale: dragScale,
                isPreview: dragScale < latest.fullScale - 1e-4,
              ));
            }
          } else if (latest != snapshot) {
            _lastScheduledSnapshot = latest;
            final double nextScale =
                _nextProgressiveScale(0.0, latest.fullScale);
            unawaited(_startCpuPass(
              engine,
              latest,
              passScale: nextScale,
              isPreview: nextScale < latest.fullScale - 1e-4,
            ));
          } else if (passScale < latest.fullScale - 1e-4) {
            final double nextScale =
                _nextProgressiveScale(passScale, latest.fullScale);
            unawaited(_startCpuPass(
              engine,
              latest,
              passScale: nextScale,
              isPreview: nextScale < latest.fullScale - 1e-4,
            ));
          } else {
            _refinementSnapshot = null;
            _refinementTotalWeight = 0.0;
            _refinementDoneWeight = 0.0;
            engine.setCpuRendering(false);
          }
        } else {
          engine.setCpuRendering(false);
        }
      }
    }
  }

  void _clearCpuOverscan() {
    _overscanToken++;
    if (_cpuOverscanImage != null) {
      final ui.Image? oldOverscan = _cpuOverscanImage;
      setState(() {
        _cpuOverscanImage = null;
        _cpuOverscanSnapshot = null;
      });
      if (oldOverscan != null) {
        _scheduleImageDispose(oldOverscan);
      }
    }
  }

  Future<void> _startCpuOverscanPass(
    FractalEngine engine,
    _CpuRenderSnapshot snapshot,
  ) async {
    if (!mounted || !engine.activeRenderMode.isCpu) return;
    final double overscanMult = engine.overscanMultiplier;
    if (overscanMult < 1.05) {
      _clearCpuOverscan();
      return;
    }
    final int token = ++_overscanToken;
    final double overscanScale = math.min(0.20, engine.dragPreviewScale);
    final double overscanW = snapshot.viewport.width * overscanMult;
    final double overscanH = snapshot.viewport.height * overscanMult;
    final int targetW = (overscanW * snapshot.devicePixelRatio * overscanScale)
        .round()
        .clamp(16, 1440);
    final int targetH = (overscanH * snapshot.devicePixelRatio * overscanScale)
        .round()
        .clamp(16, 1440);

    final CpuRenderRequest request = CpuRenderRequest(
      width: targetW,
      height: targetH,
      logicalWidth: overscanW,
      logicalHeight: overscanH,
      centerX: snapshot.centerX,
      centerY: snapshot.centerY,
      zoom: snapshot.zoom,
      rotCos: math.cos(snapshot.rotation),
      rotSin: math.sin(snapshot.rotation),
      maxIterations: snapshot.maxIterations,
      fractalTypeIndex: snapshot.fractalTypeIndex,
      juliaCx: snapshot.juliaCx,
      juliaCy: snapshot.juliaCy,
      paletteIndex: snapshot.paletteIndex,
      primaryR: snapshot.primaryR,
      primaryG: snapshot.primaryG,
      primaryB: snapshot.primaryB,
      secondaryR: snapshot.secondaryR,
      secondaryG: snapshot.secondaryG,
      secondaryB: snapshot.secondaryB,
      colorOffset: snapshot.colorOffset,
      smoothColor: snapshot.smoothColor,
    );

    final Stopwatch sw = Stopwatch()..start();
    try {
      final ui.Image image = await CpuFractalRenderer.renderImage(request);
      sw.stop();

      if (!mounted || token != _overscanToken || !engine.activeRenderMode.isCpu) {
        image.dispose();
        return;
      }

      final ui.Image? oldOverscan = _cpuOverscanImage;
      setState(() {
        _cpuOverscanImage = image;
        _cpuOverscanSnapshot = snapshot;
        _cpuOverscanMultiplier = overscanMult;
      });
      if (oldOverscan != null) {
        _scheduleImageDispose(oldOverscan);
      }

      final double cpuMs = sw.elapsedMicroseconds / 1000.0;
      engine.logPerf('cpu_overscan', <String, Object?>{
        'cpuMs': cpuMs.toStringAsFixed(1),
        'res': '${targetW}x$targetH',
      });
    } catch (_) {
      // Ignore overscan interruptions on isolate cancellation or disposal.
    }
  }

  void _maybeSchedulePtOrbit(FractalEngine engine) {
    if (!engine.activeRenderMode.isPerturbation) {
      _cancelPtOrbits();
      return;
    }
    if (_viewportSize.isEmpty) return;

    final int fType = engine.fractalType.shaderIndex;
    final bool juliaChanged = engine.fractalType == FractalType.julia &&
        (_ptOrbitJuliaCx != engine.juliaCx || _ptOrbitJuliaCy != engine.juliaCy);

    bool needsOrbit = _ptOrbit == null ||
        _ptOrbitTexture == null ||
        _ptOrbitCenterXBig == null ||
        _ptOrbitCenterYBig == null ||
        _ptOrbitFractalType != fType ||
        juliaChanged;

    if (!needsOrbit && !engine.isInteracting) {
      final double zoomRatio =
          _ptOrbitZoom > 0.0 ? engine.zoom / _ptOrbitZoom : double.infinity;
      final bool zoomChanged = zoomRatio > 2.0 || zoomRatio < 0.5;
      final bool iterIncreased =
          engine.effectiveMaxIterations > _ptOrbitRequestedMaxIter &&
              _ptOrbitRequestedMaxIter < PerturbationSolver.maxOrbitSteps;
      final bool centerShiftedX =
          (_ptOrbitCenterXBig! - engine.centerXBig).toDouble().abs() *
                  engine.zoom >
              _viewportSize.width * 0.35;
      final bool centerShiftedY =
          (_ptOrbitCenterYBig! - engine.centerYBig).toDouble().abs() *
                  engine.zoom >
              _viewportSize.height * 0.35;
      needsOrbit =
          zoomChanged || iterIncreased || centerShiftedX || centerShiftedY;
    }

    if (needsOrbit && !_ptOrbitInFlight) {
      unawaited(_startPtOrbit(engine));
    }
  }

  void _cancelPtOrbits() {
    _ptOrbitToken++;
    _ptOrbitInFlight = false;
    if (_ptOrbitTexture != null || _ptOrbit != null) {
      final ui.Image? oldTex = _ptOrbitTexture;
      setState(() {
        _ptOrbit = null;
        _ptOrbitTexture = null;
        _ptOrbitCenterXBig = null;
        _ptOrbitCenterYBig = null;
        _ptOrbitZoom = 0.0;
        _ptOrbitRequestedMaxIter = 0;
        _ptOrbitFractalType = -1;
        _ptOrbitJuliaCx = 0.0;
        _ptOrbitJuliaCy = 0.0;
      });
      if (oldTex != null) {
        _scheduleImageDispose(oldTex);
      }
    }
  }

  Future<void> _startPtOrbit(FractalEngine engine) async {
    final int token = ++_ptOrbitToken;
    _ptOrbitInFlight = true;

    final BigFixed centerXBig = engine.centerXBig;
    final BigFixed centerYBig = engine.centerYBig;
    final double zoom = engine.zoom;
    final int maxIter = engine.effectiveMaxIterations;
    final int fType = engine.fractalType.shaderIndex;
    final double jCx = engine.juliaCx;
    final double jCy = engine.juliaCy;
    final int fracBits = requiredPrecisionBits(zoom);
    final int decimalDigits = (fracBits * 0.30103).ceil() + 4;
    final double halfDiag = 0.5 *
        math.sqrt(_viewportSize.width * _viewportSize.width +
            _viewportSize.height * _viewportSize.height);

    final PerturbationOrbitRequest req = PerturbationOrbitRequest(
      centerXDecimal: centerXBig.toDecimalString(decimalDigits),
      centerYDecimal: centerYBig.toDecimalString(decimalDigits),
      zoom: zoom,
      maxIterations: maxIter,
      fractalTypeIndex: fType,
      juliaCx: jCx,
      juliaCy: jCy,
      viewportHalfDiagPx: halfDiag,
      fracBits: fracBits,
    );

    try {
      final PerturbationOrbitResult result =
          await PerturbationSolver.computeOrbit(req);
      if (!mounted ||
          token != _ptOrbitToken ||
          !engine.activeRenderMode.isPerturbation) {
        return;
      }

      final ui.Image tex = await PerturbationSolver.decodeOrbitTexture(result);
      if (!mounted ||
          token != _ptOrbitToken ||
          !engine.activeRenderMode.isPerturbation) {
        tex.dispose();
        return;
      }

      final BigFixed refCenterXBig =
          BigFixed.parseDecimal(result.refCenterXDecimal, fracBits);
      final BigFixed refCenterYBig =
          BigFixed.parseDecimal(result.refCenterYDecimal, fracBits);

      final ui.Image? oldTex = _ptOrbitTexture;
      setState(() {
        _ptOrbit = result;
        _ptOrbitTexture = tex;
        _ptOrbitCenterXBig = refCenterXBig;
        _ptOrbitCenterYBig = refCenterYBig;
        _ptOrbitZoom = zoom;
        _ptOrbitRequestedMaxIter = maxIter;
        _ptOrbitFractalType = fType;
        _ptOrbitJuliaCx = jCx;
        _ptOrbitJuliaCy = jCy;
      });
      if (oldTex != null) {
        _scheduleImageDispose(oldTex);
      }
      _maybeScheduleGpuBake(engine);
    } catch (_) {
      // Ignore orbit interruptions on mode switch or disposal.
    } finally {
      if (token == _ptOrbitToken) {
        _ptOrbitInFlight = false;
        if (mounted && engine.activeRenderMode.isPerturbation) {
          _maybeSchedulePtOrbit(engine);
        }
      }
    }
  }

  void _maybeScheduleGpuBake(FractalEngine engine) {
    final bool isPt = engine.activeRenderMode.isPerturbation;
    if (_viewportSize.isEmpty || engine.activeRenderMode.isCpu) {
      _cancelGpuBakes(clearImage: engine.activeRenderMode.isCpu);
      return;
    }
    if (isPt) {
      if (_ptProgram == null ||
          _ptBakeShader == null ||
          _ptOrbit == null ||
          _ptOrbitTexture == null ||
          _ptOrbitCenterXBig == null ||
          _ptOrbitCenterYBig == null) {
        return;
      }
    } else if (_program == null || _bakeShader == null) {
      _cancelGpuBakes(clearImage: false);
      return;
    }

    final double dpr = MediaQuery.devicePixelRatioOf(context);
    final _GpuBakeKey fullKey = _GpuBakeKey.from(
      engine: engine,
      viewport: _viewportSize,
      devicePixelRatio: dpr,
      scale: engine.quality.resolutionScale,
      primary: _lastPrimary,
      tertiary: _lastTertiary,
      orbitId: isPt ? (_ptOrbit?.hashCode ?? 0) : 0,
    );

    if (_gpuBakedImage != null && _gpuBakedKey == fullKey) {
      _gpuBakeTimer?.cancel();
      return;
    }

    final bool usePotatoLodDuringDrag = engine.isInteracting &&
        (engine.activeRenderMode == ActiveRenderMode.gpuDf64 ||
            engine.activeRenderMode == ActiveRenderMode.gpuPerturbation ||
            engine.effectiveDragScale < 0.95);
    final double liveScale = usePotatoLodDuringDrag
        ? math.min(engine.effectiveDragScale, engine.quality.resolutionScale)
        : engine.quality.resolutionScale;

    if (engine.isInteracting) {
      _gpuBakeTimer?.cancel();
      if (usePotatoLodDuringDrag && liveScale < 1.0) {
        final _GpuBakeKey liveKey = fullKey.withScale(liveScale);
        if (_gpuBakedImage != null && _gpuBakedKey == liveKey) {
          return;
        }
        if (!_gpuBakeInFlight) {
          unawaited(_startGpuBake(engine, liveKey));
        }
      }
      return;
    }

    final bool progressive =
        (engine.activeRenderMode == ActiveRenderMode.gpuDf64 ||
                engine.activeRenderMode == ActiveRenderMode.gpuPerturbation) &&
            fullKey.scale > 0.25;
    final double matchedScale = (_gpuBakedImage != null &&
            _gpuBakedKey != null &&
            _gpuBakedKey!.matchesFrameExceptScale(fullKey))
        ? _gpuBakedScale
        : 0.0;
    final double targetScale = progressive
        ? _nextProgressiveScale(matchedScale, fullKey.scale)
        : fullKey.scale;
    final _GpuBakeKey scheduledKey = fullKey.withScale(targetScale);

    if (_gpuBakeTimer?.isActive == true && _lastScheduledGpuKey == scheduledKey) {
      return;
    }

    _lastScheduledGpuKey = scheduledKey;
    _gpuBakeTimer?.cancel();
    final int scheduledToken = _gpuBakeToken;
    _gpuBakeTimer = Timer(const Duration(milliseconds: 120), () {
      if (!mounted ||
          scheduledToken != _gpuBakeToken ||
          engine.isInteracting ||
          engine.activeRenderMode.isCpu) {
        return;
      }
      unawaited(_startGpuBake(engine, scheduledKey));
    });
  }

  void _cancelGpuBakes({bool clearImage = false}) {
    _gpuBakeToken++;
    _gpuBakeTimer?.cancel();
    _gpuBakeTimer = null;
    _lastScheduledGpuKey = null;
    _gpuBakeInFlight = false;
    if (clearImage) {
      _clearCrossfade();
    }
    if (clearImage && _gpuBakedImage != null) {
      final ui.Image? old = _gpuBakedImage;
      setState(() {
        _gpuBakedImage = null;
        _gpuBakedKey = null;
        _gpuBakedScale = 1.0;
      });
      if (old != null) {
        _scheduleImageDispose(old);
      }
    }
  }

  Future<void> _startGpuBake(FractalEngine engine, _GpuBakeKey key) async {
    final bool isPt = key.usePerturbation;
    final ui.FragmentShader? shader = isPt ? _ptBakeShader : _bakeShader;
    if (shader == null || engine.activeRenderMode.isCpu) {
      return;
    }
    final PerturbationOrbitResult? ptOrbit = _ptOrbit;
    final ui.Image? ptOrbitTexture = _ptOrbitTexture;
    final BigFixed? ptOrbitCenterXBig = _ptOrbitCenterXBig;
    final BigFixed? ptOrbitCenterYBig = _ptOrbitCenterYBig;
    if (isPt) {
      if (_ptProgram == null ||
          ptOrbit == null ||
          ptOrbitTexture == null ||
          ptOrbitCenterXBig == null ||
          ptOrbitCenterYBig == null) {
        return;
      }
    } else if (_program == null) {
      return;
    }

    final int token = ++_gpuBakeToken;
    _gpuBakeInFlight = true;
    final Stopwatch sw = Stopwatch()..start();

    final double pixelRatio = key.devicePixelRatio * key.scale;
    final int targetW = (key.viewport.width * pixelRatio).round().clamp(16, 4096);
    final int targetH = (key.viewport.height * pixelRatio).round().clamp(16, 4096);
    final Size bakedSize = Size(targetW.toDouble(), targetH.toDouble());
    final double bakedScaleUniform = (1.0 / key.zoom) * (key.viewport.width / targetW);

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    if (isPt) {
      _applyPerturbationUniforms(
        shader: shader,
        uSize: bakedSize,
        viewportWidth: key.viewport.width,
        centerXBig: key.centerXBig ?? engine.centerXBig,
        centerYBig: key.centerYBig ?? engine.centerYBig,
        orbitCenterXBig: ptOrbitCenterXBig!,
        orbitCenterYBig: ptOrbitCenterYBig!,
        zoom: key.zoom,
        rotation: key.rotation,
        maxIter: key.maxIterations,
        fractalTypeIndex: key.fractalTypeIndex,
        juliaCx: key.juliaCx,
        juliaCy: key.juliaCy,
        paletteIndex: key.paletteIndex,
        primary: Color(key.primaryArgb),
        tertiary: Color(key.tertiaryArgb),
        colorOffset: key.colorOffset,
        smoothColor: key.smoothColor,
        orbit: ptOrbit!,
        orbitTexture: ptOrbitTexture!,
      );
    } else {
      _applyShaderUniforms(
        shader: shader,
        uSize: bakedSize,
        centerX: key.centerX,
        centerY: key.centerY,
        uScale: bakedScaleUniform,
        rotation: key.rotation,
        maxIter: key.maxIterations,
        fractalTypeIndex: key.fractalTypeIndex,
        juliaCx: key.juliaCx,
        juliaCy: key.juliaCy,
        paletteIndex: key.paletteIndex,
        primary: Color(key.primaryArgb),
        tertiary: Color(key.tertiaryArgb),
        colorOffset: key.colorOffset,
        smoothColor: key.smoothColor,
        useDf64: key.useDf64,
        useSsaa: key.useSsaa,
      );
    }
    canvas.drawRect(Offset.zero & bakedSize, Paint()..shader = shader);
    final ui.Picture picture = recorder.endRecording();

    try {
      final ui.Image image = await picture.toImage(targetW, targetH);
      sw.stop();
      if (!mounted || token != _gpuBakeToken || engine.activeRenderMode.isCpu) {
        image.dispose();
        return;
      }
      final double bakeMs = sw.elapsedMicroseconds / 1000.0;
      engine.recordRenderCostSample(
        mode: key.usePerturbation
            ? ActiveRenderMode.gpuPerturbation
            : (key.useDf64
                ? ActiveRenderMode.gpuDf64
                : ActiveRenderMode.gpuFloat32),
        pixelCount: targetW * targetH,
        iterations: key.maxIterations,
        durationMs: bakeMs,
      );
      engine.logPerf('gpu_bake', <String, Object?>{
        'bakeMs': bakeMs.toStringAsFixed(1),
        'res': '${targetW}x$targetH',
        'scale': key.scale,
      });
      final ui.Image? oldImage = _gpuBakedImage;
      final _GpuBakeKey? oldKey = _gpuBakedKey;
      final double prevScale = _gpuBakedScale;
      final bool shouldCrossfade = !engine.isInteracting &&
          oldImage != null &&
          oldKey != null &&
          oldKey.matchesFrameExceptScale(key) &&
          key.scale > prevScale + 1e-4;
      setState(() {
        _gpuBakedImage = image;
        _gpuBakedKey = key;
        _gpuBakedScale = key.scale;
        if (oldImage != null) {
          if (shouldCrossfade) {
            _startCrossfadeFrom(oldImage, prevScale);
          } else {
            if (_prevFadeImage != null) {
              _clearCrossfade();
            }
            _scheduleImageDispose(oldImage);
          }
        } else if (_prevFadeImage != null) {
          _clearCrossfade();
        }
      });
    } catch (_) {
      // Ignore bake interruptions on disposal or mode switch.
    } finally {
      picture.dispose();
      if (token == _gpuBakeToken) {
        _gpuBakeInFlight = false;
        if (mounted &&
            engine.activeRenderMode.isGpu &&
            !_viewportSize.isEmpty) {
          final bool activeIsPt = engine.activeRenderMode.isPerturbation;
          final bool shadersReady = activeIsPt
              ? (_ptProgram != null &&
                  _ptBakeShader != null &&
                  _ptOrbit != null &&
                  _ptOrbitTexture != null &&
                  _ptOrbitCenterXBig != null &&
                  _ptOrbitCenterYBig != null)
              : (_program != null && _bakeShader != null);
          if (shadersReady) {
            final int orbitId = activeIsPt ? (_ptOrbit?.hashCode ?? 0) : 0;
            final double dpr = MediaQuery.devicePixelRatioOf(context);
            if (engine.isInteracting) {
              final bool usePotatoLodDuringDrag =
                  engine.activeRenderMode == ActiveRenderMode.gpuDf64 ||
                      engine.activeRenderMode ==
                          ActiveRenderMode.gpuPerturbation ||
                      engine.effectiveDragScale < 0.95;
              final double liveScale = usePotatoLodDuringDrag
                  ? math.min(
                      engine.effectiveDragScale,
                      engine.quality.resolutionScale,
                    )
                  : engine.quality.resolutionScale;
              if (usePotatoLodDuringDrag && liveScale < 1.0) {
                final _GpuBakeKey latest = _GpuBakeKey.from(
                  engine: engine,
                  viewport: _viewportSize,
                  devicePixelRatio: dpr,
                  scale: liveScale,
                  primary: _lastPrimary,
                  tertiary: _lastTertiary,
                  orbitId: orbitId,
                );
                if (latest != key) {
                  unawaited(_startGpuBake(engine, latest));
                }
              }
            } else if ((engine.activeRenderMode == ActiveRenderMode.gpuDf64 ||
                    engine.activeRenderMode ==
                        ActiveRenderMode.gpuPerturbation) &&
                engine.quality.resolutionScale > 0.25) {
              final _GpuBakeKey latestFullKey = _GpuBakeKey.from(
                engine: engine,
                viewport: _viewportSize,
                devicePixelRatio: dpr,
                scale: engine.quality.resolutionScale,
                primary: _lastPrimary,
                tertiary: _lastTertiary,
                orbitId: orbitId,
              );
              if (key.scale < latestFullKey.scale - 1e-4 &&
                  key.matchesFrameExceptScale(latestFullKey)) {
                final double nextScale =
                    _nextProgressiveScale(key.scale, latestFullKey.scale);
                final _GpuBakeKey nextKey = latestFullKey.withScale(nextScale);
                _lastScheduledGpuKey = nextKey;
                unawaited(_startGpuBake(engine, nextKey));
              }
            }
          }
        }
      }
    }
  }

  void _clearCrossfade({bool retireImage = true}) {
    _fadeController.stop();
    _fadeController.value = 1.0;
    final ui.Image? old = _prevFadeImage;
    _prevFadeImage = null;
    _prevFadeScale = 0.0;
    if (retireImage &&
        old != null &&
        !identical(old, _cpuImage) &&
        !identical(old, _gpuBakedImage)) {
      _scheduleImageDispose(old);
    }
  }

  void _startCrossfadeFrom(ui.Image previous, double previousScale) {
    _clearCrossfade();
    _prevFadeImage = previous;
    _prevFadeScale = previousScale;
    _fadeController.forward(from: 0.0);
  }

  void _scheduleImageDispose(ui.Image image) {
    _retiredImages.add(image);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_retiredImages.remove(image)) {
        image.dispose();
      }
    });
  }

  void _updateViewportSize(Size nextSize, double dpr) {
    final FractalEngine? engine = _engine;
    if (engine != null && !nextSize.isEmpty) {
      engine.updateViewportPixelArea(
        (nextSize.width * dpr).round() * (nextSize.height * dpr).round(),
      );
    }
    if (_viewportSize == nextSize || nextSize.isEmpty) return;
    _viewportSize = nextSize;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onViewportChanged?.call(nextSize);
      _syncVisualAndSchedule();
    });
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
    _engine?.removeListener(_onEngineChanged);
    _keyboardTicker.dispose();
    _fadeController.dispose();
    if (_prevFadeImage != null &&
        !identical(_prevFadeImage, _cpuImage) &&
        !identical(_prevFadeImage, _gpuBakedImage)) {
      _prevFadeImage!.dispose();
    }
    _prevFadeImage = null;
    _prevFadeScale = 0.0;
    _cpuDebounceTimer?.cancel();
    _gpuBakeTimer?.cancel();
    _abortActiveCpuPass();
    _overscanToken++;
    _gpuBakeToken++;
    _ptOrbitToken++;
    _shader?.dispose();
    _shader = null;
    _bakeShader?.dispose();
    _bakeShader = null;
    _ptShader?.dispose();
    _ptShader = null;
    _ptBakeShader?.dispose();
    _ptBakeShader = null;
    _ptOrbitTexture?.dispose();
    _ptOrbitTexture = null;
    _ptOrbit = null;
    _ptOrbitCenterXBig = null;
    _ptOrbitCenterYBig = null;
    _cpuImage?.dispose();
    _cpuImage = null;
    _cpuOverscanImage?.dispose();
    _cpuOverscanImage = null;
    _cpuOverscanSnapshot = null;
    _gpuBakedImage?.dispose();
    _gpuBakedImage = null;
    for (final ui.Image img in _retiredImages) {
      img.dispose();
    }
    _retiredImages.clear();
    // Note: FragmentProgram does not require explicit disposal when retained,
    // though dereferencing it allows GC after _shader is disposed.
    _program = null;
    _ptProgram = null;
    super.dispose();
  }

  Set<FractalKeyAction> _resolveActionsForKey(
    FractalEngine engine,
    LogicalKeyboardKey key,
  ) {
    final Set<FractalKeyAction> matched = <FractalKeyAction>{};
    for (final FractalKeyAction action in FractalKeyAction.values) {
      if (engine.keybindFor(action) == key) {
        matched.add(action);
      }
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      matched.add(FractalKeyAction.panUp);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      matched.add(FractalKeyAction.panDown);
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      matched.add(FractalKeyAction.panLeft);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      matched.add(FractalKeyAction.panRight);
    } else if (key == LogicalKeyboardKey.numpadAdd ||
        key == LogicalKeyboardKey.add) {
      matched.add(FractalKeyAction.zoomIn);
    } else if (key == LogicalKeyboardKey.numpadSubtract ||
        key == LogicalKeyboardKey.minus) {
      matched.add(FractalKeyAction.zoomOut);
    }
    return matched;
  }

  void _stopKeyboardTicker(FractalEngine? engine) {
    _heldActions.clear();
    if (_keyboardTicker.isActive) {
      _keyboardTicker.stop();
    }
    _lastTickElapsed = Duration.zero;
    if (engine != null && engine.isInteracting) {
      engine.setInteracting(false);
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final FractalEngine? engine = _engine;
    if (engine == null) return KeyEventResult.ignored;

    final Set<FractalKeyAction> actions =
        _resolveActionsForKey(engine, event.logicalKey);
    if (actions.isEmpty) return KeyEventResult.ignored;

    if (event is KeyDownEvent) {
      bool addedContinuous = false;
      for (final FractalKeyAction action in actions) {
        switch (action) {
          case FractalKeyAction.resetView:
            engine.resetView();
          case FractalKeyAction.toggleHud:
            engine.toggleHud();
          case FractalKeyAction.toggleInspector:
            widget.onToggleInspector?.call();
          case FractalKeyAction.panUp:
          case FractalKeyAction.panDown:
          case FractalKeyAction.panLeft:
          case FractalKeyAction.panRight:
          case FractalKeyAction.zoomIn:
          case FractalKeyAction.zoomOut:
          case FractalKeyAction.rotateLeft:
          case FractalKeyAction.rotateRight:
            _heldActions.add(action);
            addedContinuous = true;
        }
      }
      if (addedContinuous) {
        _clearCrossfade();
        if (_cpuInFlight && !_cpuInFlightIsPreview) {
          _abortActiveCpuPass();
        }
        engine.setInteracting(true);
        if (!_keyboardTicker.isActive) {
          _lastTickElapsed = Duration.zero;
          _keyboardTicker.start();
        }
      }
      return KeyEventResult.handled;
    }

    if (event is KeyRepeatEvent) {
      return KeyEventResult.handled;
    }

    if (event is KeyUpEvent) {
      bool removedContinuous = false;
      for (final FractalKeyAction action in actions) {
        if (_continuousActions.contains(action)) {
          if (_heldActions.remove(action)) {
            removedContinuous = true;
          }
        }
      }
      if (removedContinuous && _heldActions.isEmpty) {
        if (_keyboardTicker.isActive) {
          _keyboardTicker.stop();
        }
        _lastTickElapsed = Duration.zero;
        engine.setInteracting(false);
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _onKeyboardTick(Duration elapsed) {
    final FractalEngine? engine = _engine;
    if (!mounted ||
        engine == null ||
        _heldActions.isEmpty ||
        _viewportSize.isEmpty) {
      return;
    }

    final double rawDt = _lastTickElapsed == Duration.zero
        ? 1.0 / 60.0
        : (elapsed - _lastTickElapsed).inMicroseconds / 1000000.0;
    _lastTickElapsed = elapsed;
    final double dt = rawDt.clamp(0.001, 0.05);

    final double panStep = 320.0 * dt;
    double dx = 0.0;
    double dy = 0.0;
    if (_heldActions.contains(FractalKeyAction.panLeft)) dx += panStep;
    if (_heldActions.contains(FractalKeyAction.panRight)) dx -= panStep;
    if (_heldActions.contains(FractalKeyAction.panUp)) dy += panStep;
    if (_heldActions.contains(FractalKeyAction.panDown)) dy -= panStep;

    final bool zoomIn = _heldActions.contains(FractalKeyAction.zoomIn);
    final bool zoomOut = _heldActions.contains(FractalKeyAction.zoomOut);
    double zoomFactor = 1.0;
    if (zoomIn && !zoomOut) {
      zoomFactor = math.pow(2.2, dt).toDouble();
    } else if (zoomOut && !zoomIn) {
      zoomFactor = math.pow(2.2, -dt).toDouble();
    }

    final bool rotateLeft = _heldActions.contains(FractalKeyAction.rotateLeft);
    final bool rotateRight = _heldActions.contains(FractalKeyAction.rotateRight);
    double rotationDelta = 0.0;
    if (rotateLeft && !rotateRight) {
      rotationDelta = 1.2 * dt;
    } else if (rotateRight && !rotateLeft) {
      rotationDelta = -1.2 * dt;
    }

    if (dx != 0.0 ||
        dy != 0.0 ||
        zoomFactor != 1.0 ||
        rotationDelta != 0.0) {
      engine.transformAtFocalPoint(
        focalPos: _viewportSize.center(Offset.zero),
        focalDelta: Offset(dx, dy),
        scaleFactor: zoomFactor,
        rotationDelta: rotationDelta,
        viewport: _viewportSize,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final FractalEngine engine = context.watch<FractalEngine>();
    final ColorScheme scheme = Theme.of(context).colorScheme;
    _lastPrimary = scheme.primary;
    _lastTertiary = scheme.tertiary;

    return Focus(
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      onFocusChange: (bool hasFocus) {
        if (!hasFocus && _heldActions.isNotEmpty) {
          _stopKeyboardTicker(engine);
        }
      },
      child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerSignal: (PointerSignalEvent event) {
            if (event is PointerScrollEvent && !_viewportSize.isEmpty) {
              _clearCrossfade();
              if (_cpuInFlight && !_cpuInFlightIsPreview) {
                _abortActiveCpuPass();
              }
              final double factor =
                  math.exp(-event.scrollDelta.dy * 0.0018).clamp(0.25, 4.0);
              engine.zoomAtFocalPoint(
                event.localPosition,
                _viewportSize,
                factor,
              );
            }
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            onScaleStart: (ScaleStartDetails details) {
              _clearCrossfade();
              if (_cpuInFlight && !_cpuInFlightIsPreview) {
                _abortActiveCpuPass();
              }
              engine.setInteracting(true);
              _lastScale = 1.0;
              _lastRotation = 0.0;
            },
            onScaleUpdate: (ScaleUpdateDetails details) {
              if (_viewportSize.isEmpty) return;
              final double stepScale =
                  (_lastScale > 0 && details.scale > 0)
                      ? details.scale / _lastScale
                      : 1.0;
              _lastScale = details.scale > 0 ? details.scale : 1.0;
              final double stepRotation = engine.enableGestureRotation
                  ? -(details.rotation - _lastRotation)
                  : 0.0;
              _lastRotation = details.rotation;
              engine.transformAtFocalPoint(
                focalPos: details.localFocalPoint,
                focalDelta: details.focalPointDelta,
                scaleFactor: stepScale,
                rotationDelta: stepRotation,
                viewport: _viewportSize,
              );
            },
            onScaleEnd: (_) {
              engine.setInteracting(false);
            },
            onDoubleTapDown: (TapDownDetails details) {
              _doubleTapPosition = details.localPosition;
            },
            onDoubleTap: () {
              if (_viewportSize.isEmpty) return;
              final Offset target =
                  _doubleTapPosition ?? _viewportSize.center(Offset.zero);
              engine.zoomAtFocalPoint(target, _viewportSize, 2.5);
            },
            onLongPress: widget.onLongPress == null
                ? null
                : () {
                    HapticFeedback.mediumImpact();
                    widget.onLongPress!();
                  },
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final Size logicalSize = constraints.biggest;
                final double dpr = MediaQuery.devicePixelRatioOf(context);
                _updateViewportSize(logicalSize, dpr);

                return RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _fadeController,
                    builder: (BuildContext context, Widget? child) {
                      return CustomPaint(
                        size: logicalSize,
                        isComplex: true,
                        willChange: engine.isInteracting,
                        painter: _FractalViewportPainter(
                          shader: _shader,
                          ptShader: _ptShader,
                          programLoaded: _program != null,
                          shaderLoadFailed: _shaderLoadFailed,
                          engine: engine,
                          devicePixelRatio: dpr,
                          primary: scheme.primary,
                          tertiary: scheme.tertiary,
                          ptOrbit: _ptOrbit,
                          ptOrbitTexture: _ptOrbitTexture,
                          ptOrbitCenterXBig: _ptOrbitCenterXBig,
                          ptOrbitCenterYBig: _ptOrbitCenterYBig,
                          cpuImage: _cpuImage,
                          cpuSnapshot: _cpuImageSnapshot,
                          cpuScale: _cpuImageScale,
                          cpuOverscanImage: _cpuOverscanImage,
                          cpuOverscanSnapshot: _cpuOverscanSnapshot,
                          overscanMultiplier: _cpuOverscanImage != null
                              ? _cpuOverscanMultiplier
                              : engine.overscanMultiplier,
                          gpuBakedImage: _gpuBakedImage,
                          gpuBakedKey: _gpuBakedKey,
                          gpuBakedScale: _gpuBakedScale,
                          prevFadeImage: _prevFadeImage,
                          prevFadeScale: _prevFadeScale,
                          fadeProgress: Curves.easeInOutCubic
                              .transform(_fadeController.value),
                          background: scheme.surface,
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ),
    );
  }
}

void _applyShaderUniforms({
  required ui.FragmentShader shader,
  required Size uSize,
  required double centerX,
  required double centerY,
  required double uScale,
  required double rotation,
  required int maxIter,
  required int fractalTypeIndex,
  required double juliaCx,
  required double juliaCy,
  required int paletteIndex,
  required Color primary,
  required Color tertiary,
  required double colorOffset,
  required bool smoothColor,
  required bool useDf64,
  required bool useSsaa,
}) {
  final (double cxHi, double cxLo) = splitDoubleToDf64(centerX);
  final (double cyHi, double cyLo) = splitDoubleToDf64(centerY);
  final (double scHi, double scLo) = splitDoubleToDf64(uScale);

  shader.setFloat(0, uSize.width);
  shader.setFloat(1, uSize.height);
  shader.setFloat(2, cxHi);
  shader.setFloat(3, cxLo);
  shader.setFloat(4, cyHi);
  shader.setFloat(5, cyLo);
  shader.setFloat(6, scHi);
  shader.setFloat(7, scLo);
  shader.setFloat(8, maxIter.toDouble());
  shader.setFloat(9, fractalTypeIndex.toDouble());
  shader.setFloat(10, juliaCx);
  shader.setFloat(11, juliaCy);
  shader.setFloat(12, paletteIndex.toDouble());
  shader.setFloat(13, primary.r);
  shader.setFloat(14, primary.g);
  shader.setFloat(15, primary.b);
  shader.setFloat(16, tertiary.r);
  shader.setFloat(17, tertiary.g);
  shader.setFloat(18, tertiary.b);
  shader.setFloat(19, colorOffset);
  shader.setFloat(20, smoothColor ? 1.0 : 0.0);
  shader.setFloat(21, useDf64 ? 1.0 : 0.0);
  shader.setFloat(22, useSsaa ? 1.0 : 0.0);
  shader.setFloat(23, math.cos(rotation));
  shader.setFloat(24, math.sin(rotation));
}

void _applyPerturbationUniforms({
  required ui.FragmentShader shader,
  required Size uSize,
  required double viewportWidth,
  required BigFixed centerXBig,
  required BigFixed centerYBig,
  required BigFixed orbitCenterXBig,
  required BigFixed orbitCenterYBig,
  required double zoom,
  required double rotation,
  required int maxIter,
  required int fractalTypeIndex,
  required double juliaCx,
  required double juliaCy,
  required int paletteIndex,
  required Color primary,
  required Color tertiary,
  required double colorOffset,
  required bool smoothColor,
  required PerturbationOrbitResult orbit,
  required ui.Image orbitTexture,
}) {
  final double scaleRatio = viewportWidth > 0.0 ? viewportWidth / uSize.width : 1.0;
  final double invScale = (1.0 / zoom) * scaleRatio;
  int exp = (invScale > 0.0 && invScale.isFinite)
      ? (math.log(invScale) / math.ln2).floor()
      : 0;
  double mantissa = invScale * math.pow(2.0, -exp);
  if (mantissa >= 1.0) {
    mantissa *= 0.5;
    exp++;
  } else if (mantissa > 0.0 && mantissa < 0.5) {
    mantissa *= 2.0;
    exp--;
  }

  final double dxWorld = (orbitCenterXBig - centerXBig).toDouble();
  final double dyWorld = (orbitCenterYBig - centerYBig).toDouble();
  final double pxPerWorld =
      zoom * (viewportWidth > 0.0 ? uSize.width / viewportWidth : 1.0);
  final double refDeltaPxX = dxWorld * pxPerWorld;
  final double refDeltaPxY = dyWorld * pxPerWorld;

  shader.setFloat(0, uSize.width);
  shader.setFloat(1, uSize.height);
  shader.setFloat(2, math.cos(rotation));
  shader.setFloat(3, math.sin(rotation));
  shader.setFloat(4, mantissa);
  shader.setFloat(5, exp.toDouble());
  shader.setFloat(6, refDeltaPxX);
  shader.setFloat(7, refDeltaPxY);
  shader.setFloat(8, maxIter.toDouble());
  shader.setFloat(9, orbit.refLen.toDouble());
  shader.setFloat(10, fractalTypeIndex.toDouble());
  shader.setFloat(11, paletteIndex.toDouble());
  shader.setFloat(12, primary.r);
  shader.setFloat(13, primary.g);
  shader.setFloat(14, primary.b);
  shader.setFloat(15, tertiary.r);
  shader.setFloat(16, tertiary.g);
  shader.setFloat(17, tertiary.b);
  shader.setFloat(18, colorOffset);
  shader.setFloat(19, smoothColor ? 1.0 : 0.0);
  shader.setFloat(20, orbit.refCenterXDouble);
  shader.setFloat(21, orbit.refCenterYDouble);
  shader.setFloat(22, juliaCx);
  shader.setFloat(23, juliaCy);
  final double orbitZoom = orbit.orbitZoom > 0.0 ? orbit.orbitZoom : zoom;
  final double saScale = (orbitZoom / zoom) * scaleRatio;
  final double refShiftLogicalPx =
      math.sqrt(dxWorld * dxWorld + dyWorld * dyWorld) * orbitZoom;
  final bool useSa = orbit.saSkip > 0 &&
      saScale > 0.0 &&
      saScale.isFinite &&
      (orbitZoom / zoom) <= 1.25 &&
      refShiftLogicalPx <= (viewportWidth > 0.0 ? viewportWidth * 0.25 : 120.0);

  final double saScale2 = saScale * saScale;
  final double saScale3 = saScale2 * saScale;
  double effectiveSaSkip = useSa ? orbit.saSkip.toDouble() : 0.0;
  double saARe = useSa ? orbit.saARe * saScale : 0.0;
  double saAIm = useSa ? orbit.saAIm * saScale : 0.0;
  double saBRe = useSa ? orbit.saBRe * saScale2 : 0.0;
  double saBIm = useSa ? orbit.saBIm * saScale2 : 0.0;
  double saCRe = useSa ? orbit.saCRe * saScale3 : 0.0;
  double saCIm = useSa ? orbit.saCIm * saScale3 : 0.0;
  if (!saARe.isFinite ||
      !saAIm.isFinite ||
      !saBRe.isFinite ||
      !saBIm.isFinite ||
      !saCRe.isFinite ||
      !saCIm.isFinite) {
    effectiveSaSkip = 0.0;
    saARe = 0.0;
    saAIm = 0.0;
    saBRe = 0.0;
    saBIm = 0.0;
    saCRe = 0.0;
    saCIm = 0.0;
  }

  shader.setFloat(24, effectiveSaSkip);
  shader.setFloat(25, saARe);
  shader.setFloat(26, saAIm);
  shader.setFloat(27, saBRe);
  shader.setFloat(28, saBIm);
  shader.setFloat(29, saCRe);
  shader.setFloat(30, saCIm);
  shader.setImageSampler(0, orbitTexture);
}

class _FractalViewportPainter extends CustomPainter {
  static const Color _darkBackdrop = Color(0xFF0A0E14);

  final ui.FragmentShader? shader;
  final ui.FragmentShader? ptShader;
  final bool programLoaded;
  final bool shaderLoadFailed;
  final FractalEngine engine;
  final double devicePixelRatio;
  final Color primary;
  final Color tertiary;
  final PerturbationOrbitResult? ptOrbit;
  final ui.Image? ptOrbitTexture;
  final BigFixed? ptOrbitCenterXBig;
  final BigFixed? ptOrbitCenterYBig;
  final ui.Image? cpuImage;
  final _CpuRenderSnapshot? cpuSnapshot;
  final double cpuScale;
  final ui.Image? cpuOverscanImage;
  final _CpuRenderSnapshot? cpuOverscanSnapshot;
  final double overscanMultiplier;
  final ui.Image? gpuBakedImage;
  final _GpuBakeKey? gpuBakedKey;
  final double gpuBakedScale;
  final ui.Image? prevFadeImage;
  final double prevFadeScale;
  final double fadeProgress;
  final Color background;

  final int _fractalTypeIndex;
  final double _centerX;
  final double _centerY;
  final BigFixed _centerXBig;
  final BigFixed _centerYBig;
  final double _zoom;
  final double _rotation;
  final int _maxIter;
  final double _juliaCx;
  final double _juliaCy;
  final int _paletteIndex;
  final double _colorOffset;
  final bool _smoothColor;
  final ActiveRenderMode _renderMode;
  final double _resolutionScale;
  final double _effectiveDragScale;
  final bool _useSsaa;
  final bool _isInteracting;

  _FractalViewportPainter({
    required this.shader,
    required this.ptShader,
    required this.programLoaded,
    required this.shaderLoadFailed,
    required this.engine,
    required this.devicePixelRatio,
    required this.primary,
    required this.tertiary,
    required this.ptOrbit,
    required this.ptOrbitTexture,
    required this.ptOrbitCenterXBig,
    required this.ptOrbitCenterYBig,
    required this.cpuImage,
    required this.cpuSnapshot,
    required this.cpuScale,
    required this.cpuOverscanImage,
    required this.cpuOverscanSnapshot,
    required this.overscanMultiplier,
    required this.gpuBakedImage,
    required this.gpuBakedKey,
    required this.gpuBakedScale,
    required this.prevFadeImage,
    required this.prevFadeScale,
    required this.fadeProgress,
    required this.background,
  })  : _fractalTypeIndex = engine.fractalType.shaderIndex,
        _centerX = engine.centerX,
        _centerY = engine.centerY,
        _centerXBig = engine.centerXBig,
        _centerYBig = engine.centerYBig,
        _zoom = engine.zoom,
        _rotation = engine.rotation,
        _maxIter = engine.effectiveMaxIterations,
        _juliaCx = engine.juliaCx,
        _juliaCy = engine.juliaCy,
        _paletteIndex = engine.palette.shaderIndex,
        _colorOffset = engine.colorOffset,
        _smoothColor = engine.smoothColor,
        _renderMode = engine.activeRenderMode,
        _resolutionScale = engine.quality.resolutionScale,
        _effectiveDragScale = engine.effectiveDragScale,
        _useSsaa = engine.quality.useSsaa,
        _isInteracting = engine.isInteracting;

  void _drawBackdrop(Canvas canvas, Size size, {bool useDark = false}) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = useDark
            ? _darkBackdrop
            : (shaderLoadFailed ? background : _darkBackdrop),
    );
  }

  void _drawLiveShader(
    Canvas canvas,
    Size size,
    ui.FragmentShader? activeShader,
  ) {
    if (_renderMode == ActiveRenderMode.gpuPerturbation) {
      if (ptShader != null &&
          ptOrbit != null &&
          ptOrbitTexture != null &&
          ptOrbitCenterXBig != null &&
          ptOrbitCenterYBig != null) {
        _applyPerturbationUniforms(
          shader: ptShader!,
          uSize: size,
          viewportWidth: size.width,
          centerXBig: _centerXBig,
          centerYBig: _centerYBig,
          orbitCenterXBig: ptOrbitCenterXBig!,
          orbitCenterYBig: ptOrbitCenterYBig!,
          zoom: _zoom,
          rotation: _rotation,
          maxIter: _maxIter,
          fractalTypeIndex: _fractalTypeIndex,
          juliaCx: _juliaCx,
          juliaCy: _juliaCy,
          paletteIndex: _paletteIndex,
          primary: primary,
          tertiary: tertiary,
          colorOffset: _colorOffset,
          smoothColor: _smoothColor,
          orbit: ptOrbit!,
          orbitTexture: ptOrbitTexture!,
        );
        canvas.drawRect(
          Offset.zero & size,
          Paint()..shader = ptShader!,
        );
      } else {
        _drawBackdrop(canvas, size, useDark: true);
      }
      return;
    }

    if (activeShader == null) {
      _drawBackdrop(canvas, size);
      return;
    }

    final bool useDf64 = !_isInteracting &&
        (_renderMode == ActiveRenderMode.gpuDf64 ||
            (_renderMode.isCpu && _zoom >= FractalEngine.df64ThresholdZoom));
    _applyShaderUniforms(
      shader: activeShader,
      uSize: size,
      centerX: _centerX,
      centerY: _centerY,
      uScale: 1.0 / _zoom,
      rotation: _rotation,
      maxIter: _maxIter,
      fractalTypeIndex: _fractalTypeIndex,
      juliaCx: _juliaCx,
      juliaCy: _juliaCy,
      paletteIndex: _paletteIndex,
      primary: primary,
      tertiary: tertiary,
      colorOffset: _colorOffset,
      smoothColor: _smoothColor,
      useDf64: useDf64,
      useSsaa: !_isInteracting && _useSsaa,
    );
    canvas.drawRect(
      Offset.zero & size,
      Paint()..shader = activeShader,
    );
  }

  bool _matchesCpuAppearance(_CpuRenderSnapshot s) {
    return s.fractalTypeIndex == _fractalTypeIndex &&
        s.paletteIndex == _paletteIndex &&
        s.juliaCx == _juliaCx &&
        s.juliaCy == _juliaCy &&
        s.smoothColor == _smoothColor &&
        s.colorOffset == _colorOffset;
  }

  void _drawReprojectedImage({
    required Canvas canvas,
    required Size size,
    required ui.Image image,
    required Size oldViewport,
    required double oldCenterX,
    required double oldCenterY,
    BigFixed? oldCenterXBig,
    BigFixed? oldCenterYBig,
    required double oldZoom,
    required double oldRotation,
    required double sourceScale,
    double viewportSpanMultiplier = 1.0,
  }) {
    final FilterQuality filterQuality = sourceScale <= 0.15
        ? FilterQuality.low
        : (sourceScale <= 0.50 ? FilterQuality.medium : FilterQuality.high);
    final double drawW = oldViewport.width * viewportSpanMultiplier;
    final double drawH = oldViewport.height * viewportSpanMultiplier;
    final Rect dst = Rect.fromCenter(
      center: Offset.zero,
      width: drawW,
      height: drawH,
    );
    final Rect src = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );

    final double dxWorld = oldCenterXBig != null
        ? (oldCenterXBig - _centerXBig).toDouble()
        : (oldCenterX - _centerX);
    final double dyWorld = oldCenterYBig != null
        ? (oldCenterYBig - _centerYBig).toDouble()
        : (oldCenterY - _centerY);

    canvas.save();
    canvas.translate(size.width * 0.5, size.height * 0.5);
    canvas.rotate(-_rotation);
    canvas.translate(
      dxWorld * _zoom,
      dyWorld * _zoom,
    );
    canvas.rotate(oldRotation);
    canvas.scale(_zoom / oldZoom);
    canvas.drawImageRect(
      image,
      src,
      dst,
      Paint()..filterQuality = filterQuality,
    );
    canvas.restore();
  }

  void _drawStretchedImage(
    Canvas canvas,
    Size size,
    ui.Image image,
    FilterQuality filterQuality, {
    double opacity = 1.0,
  }) {
    final Rect src = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    final Paint paint = Paint()..filterQuality = filterQuality;
    if (opacity < 1.0) {
      paint.color = Color.fromRGBO(255, 255, 255, opacity.clamp(0.0, 1.0));
    }
    canvas.drawImageRect(
      image,
      src,
      Offset.zero & size,
      paint,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final ui.FragmentShader? activeShader = shader;
    final ui.Image? img = cpuImage;
    final _CpuRenderSnapshot? snap = cpuSnapshot;
    final ui.Image? overscanImg = cpuOverscanImage;
    final _CpuRenderSnapshot? overscanSnap = cpuOverscanSnapshot;

    // 1. CPU float64 mode: skip hidden GPU shader whenever a CPU image exists.
    if (_renderMode.isCpu) {
      final bool hasMatchingOverscan = overscanImg != null &&
          overscanSnap != null &&
          _matchesCpuAppearance(overscanSnap);
      final bool hasMainCpu = img != null && snap != null;
      if (hasMainCpu || hasMatchingOverscan) {
        _drawBackdrop(canvas, size, useDark: true);
        if (hasMatchingOverscan) {
          _drawReprojectedImage(
            canvas: canvas,
            size: size,
            image: overscanImg,
            oldViewport: overscanSnap.viewport,
            oldCenterX: overscanSnap.centerX,
            oldCenterY: overscanSnap.centerY,
            oldZoom: overscanSnap.zoom,
            oldRotation: overscanSnap.rotation,
            sourceScale: 0.20,
            viewportSpanMultiplier: overscanMultiplier,
          );
        }
        if (hasMainCpu) {
          final bool isStationaryCpu = !_isInteracting &&
              snap.centerX == _centerX &&
              snap.centerY == _centerY &&
              snap.zoom == _zoom &&
              snap.rotation == _rotation;
          if (isStationaryCpu &&
              prevFadeImage != null &&
              fadeProgress < 1.0) {
            final FilterQuality cpuFilterQuality = cpuScale <= 0.15
                ? FilterQuality.low
                : (cpuScale <= 0.50
                    ? FilterQuality.medium
                    : FilterQuality.high);
            _drawStretchedImage(
              canvas,
              size,
              prevFadeImage!,
              FilterQuality.medium,
            );
            _drawStretchedImage(
              canvas,
              size,
              img,
              cpuFilterQuality,
              opacity: fadeProgress,
            );
          } else {
            _drawReprojectedImage(
              canvas: canvas,
              size: size,
              image: img,
              oldViewport: snap.viewport,
              oldCenterX: snap.centerX,
              oldCenterY: snap.centerY,
              oldZoom: snap.zoom,
              oldRotation: snap.rotation,
              sourceScale: cpuScale,
            );
          }
        }
        return;
      }
      if (activeShader != null && programLoaded) {
        _drawLiveShader(canvas, size, activeShader);
      } else {
        _drawBackdrop(canvas, size);
      }
      return;
    }

    // 2. GPU mode: prefer exact-match baked image (~0.2ms, 0% shader execution
    // during UI animations, card squashing, and inspector scrolling) ONLY when
    // the baked viewport matches the current canvas size. Whenever `size` is
    // actively animating/changing, draw the live GPU shader directly so the
    // fractal fills the card edge-to-edge with zero black letterbox voids.
    final ui.Image? baked = gpuBakedImage;
    final _GpuBakeKey? bakedKey = gpuBakedKey;
    final bool isHeavyGpu = _renderMode == ActiveRenderMode.gpuDf64 ||
        _renderMode == ActiveRenderMode.gpuPerturbation;
    if (baked != null &&
        bakedKey != null &&
        (bakedKey.viewport == size || isHeavyGpu)) {
      final _GpuBakeKey targetFullKey = _GpuBakeKey(
        viewport: size,
        devicePixelRatio: devicePixelRatio,
        scale: _resolutionScale,
        centerX: _centerX,
        centerY: _centerY,
        centerXBig: _centerXBig,
        centerYBig: _centerYBig,
        zoom: _zoom,
        rotation: _rotation,
        maxIterations: _maxIter,
        fractalTypeIndex: _fractalTypeIndex,
        juliaCx: _juliaCx,
        juliaCy: _juliaCy,
        paletteIndex: _paletteIndex,
        primaryArgb: primary.toARGB32(),
        tertiaryArgb: tertiary.toARGB32(),
        colorOffset: _colorOffset,
        smoothColor: _smoothColor,
        useDf64: _renderMode == ActiveRenderMode.gpuDf64,
        usePerturbation: _renderMode == ActiveRenderMode.gpuPerturbation,
        orbitId: _renderMode == ActiveRenderMode.gpuPerturbation
            ? (ptOrbit?.hashCode ?? 0)
            : 0,
        useSsaa: _useSsaa,
      );

      final bool isStationaryGpu =
          !_isInteracting && bakedKey.matchesFrameExceptScale(targetFullKey);
      if (isStationaryGpu) {
        final FilterQuality bakedFilter =
            gpuBakedScale < 1.0 ? FilterQuality.medium : FilterQuality.high;
        if (!_isInteracting && prevFadeImage != null && fadeProgress < 1.0) {
          _drawStretchedImage(
            canvas,
            size,
            prevFadeImage!,
            FilterQuality.medium,
          );
          _drawStretchedImage(
            canvas,
            size,
            baked,
            bakedFilter,
            opacity: fadeProgress,
          );
        } else {
          _drawStretchedImage(
            canvas,
            size,
            baked,
            bakedFilter,
          );
        }
        return;
      }

      final bool usePotatoLodDuringDrag = _isInteracting &&
          (_renderMode == ActiveRenderMode.gpuDf64 ||
              _renderMode == ActiveRenderMode.gpuPerturbation ||
              _effectiveDragScale < 0.95);
      final double liveScale = usePotatoLodDuringDrag
          ? math.min(_effectiveDragScale, _resolutionScale)
          : _resolutionScale;
      final _GpuBakeKey targetLiveKey = targetFullKey.withScale(liveScale);
      if (bakedKey == targetLiveKey) {
        _drawStretchedImage(canvas, size, baked, FilterQuality.medium);
        return;
      }

      final bool hasMatchingBakedAppearance =
          bakedKey.matchesAppearance(targetFullKey);
      final bool preferAffineBaked = hasMatchingBakedAppearance &&
          (_renderMode == ActiveRenderMode.gpuDf64 ||
              _renderMode == ActiveRenderMode.gpuPerturbation ||
              usePotatoLodDuringDrag ||
              ((activeShader == null || !programLoaded) &&
                  (!_isInteracting || _resolutionScale < 1.0)));

      if (preferAffineBaked) {
        _drawBackdrop(canvas, size, useDark: true);
        _drawReprojectedImage(
          canvas: canvas,
          size: size,
          image: baked,
          oldViewport: bakedKey.viewport,
          oldCenterX: bakedKey.centerX,
          oldCenterY: bakedKey.centerY,
          oldCenterXBig: bakedKey.centerXBig,
          oldCenterYBig: bakedKey.centerYBig,
          oldZoom: bakedKey.zoom,
          oldRotation: bakedKey.rotation,
          sourceScale: gpuBakedScale,
        );
        return;
      }
    }

    if (_renderMode == ActiveRenderMode.gpuPerturbation) {
      _drawLiveShader(canvas, size, null);
      return;
    }

    if (activeShader != null && programLoaded) {
      _drawLiveShader(canvas, size, activeShader);
      return;
    }

    if (img != null && snap != null) {
      _drawBackdrop(canvas, size, useDark: true);
      _drawReprojectedImage(
        canvas: canvas,
        size: size,
        image: img,
        oldViewport: snap.viewport,
        oldCenterX: snap.centerX,
        oldCenterY: snap.centerY,
        oldZoom: snap.zoom,
        oldRotation: snap.rotation,
        sourceScale: cpuScale,
      );
      return;
    }

    _drawBackdrop(canvas, size);
  }

  @override
  bool shouldRepaint(covariant _FractalViewportPainter old) {
    return old.shader != shader ||
        old.ptShader != ptShader ||
        old.programLoaded != programLoaded ||
        old.shaderLoadFailed != shaderLoadFailed ||
        old.devicePixelRatio != devicePixelRatio ||
        old._fractalTypeIndex != _fractalTypeIndex ||
        old._centerX != _centerX ||
        old._centerY != _centerY ||
        old._centerXBig != _centerXBig ||
        old._centerYBig != _centerYBig ||
        old._zoom != _zoom ||
        old._rotation != _rotation ||
        old._maxIter != _maxIter ||
        old._juliaCx != _juliaCx ||
        old._juliaCy != _juliaCy ||
        old._paletteIndex != _paletteIndex ||
        old._colorOffset != _colorOffset ||
        old._smoothColor != _smoothColor ||
        old._renderMode != _renderMode ||
        old._resolutionScale != _resolutionScale ||
        old._effectiveDragScale != _effectiveDragScale ||
        old._useSsaa != _useSsaa ||
        old._isInteracting != _isInteracting ||
        old.primary != primary ||
        old.tertiary != tertiary ||
        old.ptOrbit != ptOrbit ||
        old.ptOrbitTexture != ptOrbitTexture ||
        old.ptOrbitCenterXBig != ptOrbitCenterXBig ||
        old.ptOrbitCenterYBig != ptOrbitCenterYBig ||
        old.cpuImage != cpuImage ||
        old.cpuSnapshot != cpuSnapshot ||
        old.cpuScale != cpuScale ||
        old.cpuOverscanImage != cpuOverscanImage ||
        old.cpuOverscanSnapshot != cpuOverscanSnapshot ||
        old.overscanMultiplier != overscanMultiplier ||
        old.gpuBakedImage != gpuBakedImage ||
        old.gpuBakedKey != gpuBakedKey ||
        old.gpuBakedScale != gpuBakedScale ||
        old.prevFadeImage != prevFadeImage ||
        old.fadeProgress != fadeProgress ||
        old.background != background;
  }
}

class _VisualKey {
  final int fractalTypeIndex;
  final double centerX;
  final double centerY;
  final double zoom;
  final double rotation;
  final int maxIter;
  final double juliaCx;
  final double juliaCy;
  final int paletteIndex;
  final double colorOffset;
  final bool smoothColor;
  final ActiveRenderMode renderMode;
  final RenderQuality quality;
  final Size viewport;
  final int primaryArgb;
  final int tertiaryArgb;
  final int cpuImageId;
  final int gpuBakedImageId;

  const _VisualKey({
    required this.fractalTypeIndex,
    required this.centerX,
    required this.centerY,
    required this.zoom,
    required this.rotation,
    required this.maxIter,
    required this.juliaCx,
    required this.juliaCy,
    required this.paletteIndex,
    required this.colorOffset,
    required this.smoothColor,
    required this.renderMode,
    required this.quality,
    required this.viewport,
    required this.primaryArgb,
    required this.tertiaryArgb,
    required this.cpuImageId,
    required this.gpuBakedImageId,
  });

  factory _VisualKey.from({
    required FractalEngine engine,
    required Size viewport,
    required Color primary,
    required Color tertiary,
    required int cpuImageId,
    required int gpuBakedImageId,
  }) {
    return _VisualKey(
      fractalTypeIndex: engine.fractalType.shaderIndex,
      centerX: engine.centerX,
      centerY: engine.centerY,
      zoom: engine.zoom,
      rotation: engine.rotation,
      maxIter: engine.effectiveMaxIterations,
      juliaCx: engine.juliaCx,
      juliaCy: engine.juliaCy,
      paletteIndex: engine.palette.shaderIndex,
      colorOffset: engine.colorOffset,
      smoothColor: engine.smoothColor,
      renderMode: engine.activeRenderMode,
      quality: engine.quality,
      viewport: viewport,
      primaryArgb: primary.toARGB32(),
      tertiaryArgb: tertiary.toARGB32(),
      cpuImageId: cpuImageId,
      gpuBakedImageId: gpuBakedImageId,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _VisualKey &&
        other.fractalTypeIndex == fractalTypeIndex &&
        other.centerX == centerX &&
        other.centerY == centerY &&
        other.zoom == zoom &&
        other.rotation == rotation &&
        other.maxIter == maxIter &&
        other.juliaCx == juliaCx &&
        other.juliaCy == juliaCy &&
        other.paletteIndex == paletteIndex &&
        other.colorOffset == colorOffset &&
        other.smoothColor == smoothColor &&
        other.renderMode == renderMode &&
        other.quality == quality &&
        other.viewport == viewport &&
        other.primaryArgb == primaryArgb &&
        other.tertiaryArgb == tertiaryArgb &&
        other.cpuImageId == cpuImageId &&
        other.gpuBakedImageId == gpuBakedImageId;
  }

  @override
  int get hashCode => Object.hash(
        fractalTypeIndex,
        centerX,
        centerY,
        zoom,
        rotation,
        maxIter,
        juliaCx,
        juliaCy,
        paletteIndex,
        colorOffset,
        smoothColor,
        renderMode,
        quality,
        viewport,
        primaryArgb,
        tertiaryArgb,
        cpuImageId,
        gpuBakedImageId,
      );
}

class _GpuBakeKey {
  final Size viewport;
  final double devicePixelRatio;
  final double scale;
  final double centerX;
  final double centerY;
  final BigFixed? centerXBig;
  final BigFixed? centerYBig;
  final double zoom;
  final double rotation;
  final int maxIterations;
  final int fractalTypeIndex;
  final double juliaCx;
  final double juliaCy;
  final int paletteIndex;
  final int primaryArgb;
  final int tertiaryArgb;
  final double colorOffset;
  final bool smoothColor;
  final bool useDf64;
  final bool usePerturbation;
  final int orbitId;
  final bool useSsaa;

  const _GpuBakeKey({
    required this.viewport,
    required this.devicePixelRatio,
    required this.scale,
    required this.centerX,
    required this.centerY,
    this.centerXBig,
    this.centerYBig,
    required this.zoom,
    required this.rotation,
    required this.maxIterations,
    required this.fractalTypeIndex,
    required this.juliaCx,
    required this.juliaCy,
    required this.paletteIndex,
    required this.primaryArgb,
    required this.tertiaryArgb,
    required this.colorOffset,
    required this.smoothColor,
    required this.useDf64,
    this.usePerturbation = false,
    this.orbitId = 0,
    required this.useSsaa,
  });

  factory _GpuBakeKey.from({
    required FractalEngine engine,
    required Size viewport,
    required double devicePixelRatio,
    required double scale,
    required Color primary,
    required Color tertiary,
    int orbitId = 0,
  }) {
    final bool isPt = engine.activeRenderMode.isPerturbation;
    return _GpuBakeKey(
      viewport: viewport,
      devicePixelRatio: devicePixelRatio,
      scale: scale,
      centerX: engine.centerX,
      centerY: engine.centerY,
      centerXBig: isPt ? engine.centerXBig : null,
      centerYBig: isPt ? engine.centerYBig : null,
      zoom: engine.zoom,
      rotation: engine.rotation,
      maxIterations: engine.effectiveMaxIterations,
      fractalTypeIndex: engine.fractalType.shaderIndex,
      juliaCx: engine.juliaCx,
      juliaCy: engine.juliaCy,
      paletteIndex: engine.palette.shaderIndex,
      primaryArgb: primary.toARGB32(),
      tertiaryArgb: tertiary.toARGB32(),
      colorOffset: engine.colorOffset,
      smoothColor: engine.smoothColor,
      useDf64: engine.activeRenderMode == ActiveRenderMode.gpuDf64,
      usePerturbation: isPt,
      orbitId: isPt ? orbitId : 0,
      useSsaa: engine.quality.useSsaa,
    );
  }

  _GpuBakeKey withScale(double nextScale) {
    if (nextScale == scale) return this;
    return _GpuBakeKey(
      viewport: viewport,
      devicePixelRatio: devicePixelRatio,
      scale: nextScale,
      centerX: centerX,
      centerY: centerY,
      centerXBig: centerXBig,
      centerYBig: centerYBig,
      zoom: zoom,
      rotation: rotation,
      maxIterations: maxIterations,
      fractalTypeIndex: fractalTypeIndex,
      juliaCx: juliaCx,
      juliaCy: juliaCy,
      paletteIndex: paletteIndex,
      primaryArgb: primaryArgb,
      tertiaryArgb: tertiaryArgb,
      colorOffset: colorOffset,
      smoothColor: smoothColor,
      useDf64: useDf64,
      usePerturbation: usePerturbation,
      orbitId: orbitId,
      useSsaa: useSsaa,
    );
  }

  bool matchesFrameExceptScale(_GpuBakeKey other) {
    return other.viewport == viewport &&
        other.devicePixelRatio == devicePixelRatio &&
        other.centerX == centerX &&
        other.centerY == centerY &&
        other.centerXBig == centerXBig &&
        other.centerYBig == centerYBig &&
        other.zoom == zoom &&
        other.rotation == rotation &&
        other.maxIterations == maxIterations &&
        other.fractalTypeIndex == fractalTypeIndex &&
        other.juliaCx == juliaCx &&
        other.juliaCy == juliaCy &&
        other.paletteIndex == paletteIndex &&
        other.primaryArgb == primaryArgb &&
        other.tertiaryArgb == tertiaryArgb &&
        other.colorOffset == colorOffset &&
        other.smoothColor == smoothColor &&
        other.useDf64 == useDf64 &&
        other.usePerturbation == usePerturbation &&
        other.orbitId == orbitId &&
        other.useSsaa == useSsaa;
  }

  bool matchesAppearance(_GpuBakeKey other) {
    return other.fractalTypeIndex == fractalTypeIndex &&
        other.juliaCx == juliaCx &&
        other.juliaCy == juliaCy &&
        other.paletteIndex == paletteIndex &&
        other.primaryArgb == primaryArgb &&
        other.tertiaryArgb == tertiaryArgb &&
        other.colorOffset == colorOffset &&
        other.smoothColor == smoothColor;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _GpuBakeKey &&
        other.viewport == viewport &&
        other.devicePixelRatio == devicePixelRatio &&
        other.scale == scale &&
        other.centerX == centerX &&
        other.centerY == centerY &&
        other.centerXBig == centerXBig &&
        other.centerYBig == centerYBig &&
        other.zoom == zoom &&
        other.rotation == rotation &&
        other.maxIterations == maxIterations &&
        other.fractalTypeIndex == fractalTypeIndex &&
        other.juliaCx == juliaCx &&
        other.juliaCy == juliaCy &&
        other.paletteIndex == paletteIndex &&
        other.primaryArgb == primaryArgb &&
        other.tertiaryArgb == tertiaryArgb &&
        other.colorOffset == colorOffset &&
        other.smoothColor == smoothColor &&
        other.useDf64 == useDf64 &&
        other.usePerturbation == usePerturbation &&
        other.orbitId == orbitId &&
        other.useSsaa == useSsaa;
  }

  @override
  int get hashCode => Object.hash(
        Object.hash(
          viewport,
          devicePixelRatio,
          scale,
          centerX,
          centerY,
          centerXBig,
          centerYBig,
          zoom,
          rotation,
          maxIterations,
          fractalTypeIndex,
        ),
        Object.hash(
          juliaCx,
          juliaCy,
          paletteIndex,
          primaryArgb,
          tertiaryArgb,
          colorOffset,
          smoothColor,
          useDf64,
          usePerturbation,
          orbitId,
          useSsaa,
        ),
      );
}

class _CpuRenderSnapshot {
  final Size viewport;
  final double devicePixelRatio;
  final double fullScale;
  final double centerX;
  final double centerY;
  final double zoom;
  final double rotation;
  final int maxIterations;
  final int fractalTypeIndex;
  final double juliaCx;
  final double juliaCy;
  final int paletteIndex;
  final double primaryR;
  final double primaryG;
  final double primaryB;
  final double secondaryR;
  final double secondaryG;
  final double secondaryB;
  final double colorOffset;
  final bool smoothColor;

  const _CpuRenderSnapshot({
    required this.viewport,
    required this.devicePixelRatio,
    required this.fullScale,
    required this.centerX,
    required this.centerY,
    required this.zoom,
    required this.rotation,
    required this.maxIterations,
    required this.fractalTypeIndex,
    required this.juliaCx,
    required this.juliaCy,
    required this.paletteIndex,
    required this.primaryR,
    required this.primaryG,
    required this.primaryB,
    required this.secondaryR,
    required this.secondaryG,
    required this.secondaryB,
    required this.colorOffset,
    required this.smoothColor,
  });

  factory _CpuRenderSnapshot.from({
    required FractalEngine engine,
    required Size viewport,
    required double devicePixelRatio,
    required Color primary,
    required Color tertiary,
  }) {
    return _CpuRenderSnapshot(
      viewport: viewport,
      devicePixelRatio: devicePixelRatio,
      fullScale: engine.quality.resolutionScale,
      centerX: engine.centerX,
      centerY: engine.centerY,
      zoom: engine.zoom,
      rotation: engine.rotation,
      maxIterations: engine.effectiveMaxIterations,
      fractalTypeIndex: engine.fractalType.shaderIndex,
      juliaCx: engine.juliaCx,
      juliaCy: engine.juliaCy,
      paletteIndex: engine.palette.shaderIndex,
      primaryR: primary.r,
      primaryG: primary.g,
      primaryB: primary.b,
      secondaryR: tertiary.r,
      secondaryG: tertiary.g,
      secondaryB: tertiary.b,
      colorOffset: engine.colorOffset,
      smoothColor: engine.smoothColor,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _CpuRenderSnapshot &&
        other.viewport == viewport &&
        other.devicePixelRatio == devicePixelRatio &&
        other.fullScale == fullScale &&
        other.centerX == centerX &&
        other.centerY == centerY &&
        other.zoom == zoom &&
        other.rotation == rotation &&
        other.maxIterations == maxIterations &&
        other.fractalTypeIndex == fractalTypeIndex &&
        other.juliaCx == juliaCx &&
        other.juliaCy == juliaCy &&
        other.paletteIndex == paletteIndex &&
        other.primaryR == primaryR &&
        other.primaryG == primaryG &&
        other.primaryB == primaryB &&
        other.secondaryR == secondaryR &&
        other.secondaryG == secondaryG &&
        other.secondaryB == secondaryB &&
        other.colorOffset == colorOffset &&
        other.smoothColor == smoothColor;
  }

  @override
  int get hashCode => Object.hash(
        viewport,
        devicePixelRatio,
        fullScale,
        centerX,
        centerY,
        zoom,
        rotation,
        maxIterations,
        fractalTypeIndex,
        juliaCx,
        juliaCy,
        paletteIndex,
        primaryR,
        primaryG,
        primaryB,
        secondaryR,
        secondaryG,
        secondaryB,
        colorOffset,
        smoothColor,
      );
}
