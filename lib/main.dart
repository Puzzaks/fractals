import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:m3x_ui/m3x_ui.dart';
import 'package:provider/provider.dart';

import 'engine/fractal_engine.dart';
import 'widgets/fractal_canvas.dart';
import 'widgets/hud_overlay.dart';
import 'widgets/inspector_panel.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FractalViewerApp());
}

/// Root Material 3 Expressive application widget for Fractal Viewer.
///
/// Accepts an optional pre-configured [engine] for deterministic widget tests;
/// in production, creates, initializes, and disposes its own [FractalEngine].
class FractalViewerApp extends StatefulWidget {
  final FractalEngine? engine;

  const FractalViewerApp({
    super.key,
    this.engine,
  });

  @override
  State<FractalViewerApp> createState() => _FractalViewerAppState();
}

class _FractalViewerAppState extends State<FractalViewerApp> {
  static final ColorScheme _fallbackLightScheme =
      ColorScheme.fromSeed(seedColor: Colors.teal);
  static final ColorScheme _fallbackDarkScheme = ColorScheme.fromSeed(
    seedColor: Colors.teal,
    brightness: Brightness.dark,
  );

  FractalEngine? _ownedEngine;

  FractalEngine get _activeEngine => widget.engine ?? _ownedEngine!;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ),
    );
    if (widget.engine == null) {
      _ownedEngine = FractalEngine();
      unawaited(_ownedEngine!.init());
    }
  }

  @override
  void didUpdateWidget(covariant FractalViewerApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.engine != widget.engine) {
      if (widget.engine != null) {
        _ownedEngine?.dispose();
        _ownedEngine = null;
      } else if (_ownedEngine == null) {
        _ownedEngine = FractalEngine();
        unawaited(_ownedEngine!.init());
      }
    }
  }

  @override
  void dispose() {
    _ownedEngine?.dispose();
    _ownedEngine = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final FractalEngine engine = _activeEngine;

    return ChangeNotifierProvider<FractalEngine>.value(
      value: engine,
      child: DynamicColorBuilder(
        builder: (
          ColorScheme? lightDynamic,
          ColorScheme? darkDynamic,
        ) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            onGenerateTitle: (BuildContext ctx) {
              final FractalEngine eng = ctx.read<FractalEngine>();
              return eng.initialized
                  ? eng.tr('app_title')
                  : 'Fractal Viewer';
            },
            themeMode: ThemeMode.system,
            theme: ThemeData(
              useMaterial3: true,
              colorScheme: lightDynamic ?? _fallbackLightScheme,
            ),
            darkTheme: ThemeData(
              useMaterial3: true,
              colorScheme: darkDynamic ?? _fallbackDarkScheme,
            ),
            home: const FractalExplorerPage(),
          );
        },
      ),
    );
  }
}

/// Adaptive 3-state framed fractal exploration workspace:
/// - State 0 (Fullscreen): edge-to-edge canvas, long-press to restore controls.
/// - State 1 (Framed Card HUD): rounded fractal card with telemetry pill and
///   a bottom Material 3 action bar below the card.
/// - State 2 (Split Settings): in-place animated split layout (35%/65% vertical
///   on compact phones, 50%/50% horizontal on medium, 67%/33% on expanded).
class FractalExplorerPage extends StatefulWidget {
  const FractalExplorerPage({super.key});

  @override
  State<FractalExplorerPage> createState() => _FractalExplorerPageState();
}

class _FractalExplorerPageState extends State<FractalExplorerPage> {
  static const Duration _layoutAnimDuration = Duration(milliseconds: 280);
  static const Curve _layoutAnimCurve = Curves.easeOutCubic;

  final GlobalKey _canvasKey = GlobalKey();
  final GlobalKey<NavigatorState> _inspectorNavKey = GlobalKey<NavigatorState>();
  final ValueNotifier<Size> _viewportNotifier = ValueNotifier<Size>(Size.zero);
  bool _inspectorOpen = false;
  double _compactInspectorFraction = 0.65;
  bool _isDraggingInspector = false;
  bool _shownLongPressHint = false;
  Size _latestViewport = Size.zero;
  double _screenTopCornerRadiusPx = 0.0;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && Platform.isAndroid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_queryTopCornerRadius());
      });
    }
  }

  Future<void> _queryTopCornerRadius() async {
    if (!mounted) return;
    try {
      const MethodChannel channel =
          MethodChannel('page.puzzak.fractals/display');
      final double rawPx =
          await channel.invokeMethod<double>('getTopCornerRadius') ?? 0.0;
      if (!mounted || rawPx <= 0.0) return;
      setState(() {
        _screenTopCornerRadiusPx = rawPx;
      });
    } catch (_) {
      // Ignore platform channel errors on unsupported hosts or tests.
    }
  }

  @override
  void dispose() {
    _viewportNotifier.dispose();
    super.dispose();
  }

  void _toggleInspector() {
    setState(() {
      _inspectorOpen = !_inspectorOpen;
      _compactInspectorFraction = 0.65;
    });
  }

  void _hideHudWithHint(BuildContext context, FractalEngine engine) {
    engine.setShowHud(false);
    if (!_shownLongPressHint) {
      _shownLongPressHint = true;
      final String raw = engine.tr('hud_long_press_hint');
      final String message = (raw.isEmpty ||
              raw == 'hud_long_press_hint' ||
              raw.startsWith('!'))
          ? 'Long-press anywhere to show controls'
          : raw;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
    }
  }

  void _handleCanvasLongPress(BuildContext context, FractalEngine engine) {
    if (_inspectorOpen) {
      setState(() {
        _inspectorOpen = false;
        _compactInspectorFraction = 0.65;
      });
      engine.setShowHud(false);
      return;
    }
    if (engine.showHud) {
      _hideHudWithHint(context, engine);
    } else {
      engine.setShowHud(true);
    }
  }

  void _handleQuickExport(BuildContext context, FractalEngine engine) {
    final double dpr = MediaQuery.devicePixelRatioOf(context);
    final int targetLongEdge = _latestViewport.isEmpty
        ? 1920
        : (math.max(_latestViewport.width, _latestViewport.height) * dpr)
            .round()
            .clamp(512, 4096);
    unawaited(
      exportFractalPng(
        context,
        engine,
        _latestViewport,
        targetLongEdge,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final FractalEngine engine = context.watch<FractalEngine>();
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final EdgeInsets mediaPadding = MediaQuery.paddingOf(context);
    final bool isFullscreen = !engine.showHud && !_inspectorOpen;
    final bool showHudChrome = engine.showHud && !_inspectorOpen;
    final double dpr = MediaQuery.devicePixelRatioOf(context);
    final double screenCornerDp =
        dpr > 0.0 ? (_screenTopCornerRadiusPx / dpr) : 0.0;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        if (_inspectorOpen &&
            (_inspectorNavKey.currentState?.canPop() ?? false)) {
          _inspectorNavKey.currentState!.pop();
        } else if (_inspectorOpen) {
          setState(() {
            _inspectorOpen = false;
            _compactInspectorFraction = 0.65;
          });
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
      backgroundColor: scheme.surfaceContainerLow,
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final M3xWindowSizeClass sizeClass =
              M3xWindowSizeClass.fromWidth(constraints.maxWidth);
          final EdgeInsets outerPadding = isFullscreen
              ? EdgeInsets.zero
              : EdgeInsets.fromLTRB(
                  mediaPadding.left + 12,
                  mediaPadding.top + 8,
                  mediaPadding.right + 12,
                  mediaPadding.bottom + 10,
                );
          final double innerWidth =
              (constraints.maxWidth - outerPadding.horizontal)
                  .clamp(120.0, double.infinity);
          final double innerHeight =
              (constraints.maxHeight - outerPadding.vertical)
                  .clamp(120.0, double.infinity);

          final Widget fractalCard = TweenAnimationBuilder<double>(
            tween: Tween<double>(end: isFullscreen ? 0.0 : 24.0),
            duration: _layoutAnimDuration,
            curve: _layoutAnimCurve,
            builder: (BuildContext context, double radius, Widget? child) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                clipBehavior: Clip.antiAlias,
                child: child,
              );
            },
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: Color(0xFF0A0E14),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  FractalCanvas(
                    key: _canvasKey,
                    onTap: _inspectorOpen
                        ? () {
                            setState(() {
                              _inspectorOpen = false;
                              _compactInspectorFraction = 0.65;
                            });
                          }
                        : null,
                    onToggleInspector: _toggleInspector,
                    onLongPress: () => _handleCanvasLongPress(context, engine),
                    onViewportChanged: (Size size) {
                      _latestViewport = size;
                      _viewportNotifier.value = size;
                    },
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedOpacity(
                        opacity: (engine.hasActiveProgress && !_inspectorOpen)
                            ? 1.0
                            : 0.0,
                        duration: const Duration(milliseconds: 180),
                        child: _ViewportEdgeProgressBar(
                          progress: (engine.activeProgress ?? 0.0).clamp(0.0, 1.0),
                          cornerRadius:
                              isFullscreen ? screenCornerDp : 24.0,
                          color: engine.isExporting
                              ? scheme.tertiary
                              : scheme.primary,
                          trackColor: scheme.surfaceContainerHighest
                              .withValues(alpha: 0.28),
                          strokeWidth: 3.0,
                          extraInset:
                              (isFullscreen && screenCornerDp > 0.0) ? 1.5 : 0.0,
                        ),
                      ),
                    ),
                  ),
                  AnimatedOpacity(
                    opacity: showHudChrome ? 1.0 : 0.0,
                    duration: _layoutAnimDuration,
                    curve: _layoutAnimCurve,
                    child: IgnorePointer(
                      ignoring: !showHudChrome,
                      child: const HudTelemetryOverlay(),
                    ),
                  ),
                ],
              ),
            ),
          );

          final Widget bottomBarSlot = AnimatedContainer(
            duration: _layoutAnimDuration,
            curve: _layoutAnimCurve,
            height: showHudChrome ? 62.0 : 0.0,
            clipBehavior: Clip.hardEdge,
            decoration: const BoxDecoration(),
            child: OverflowBox(
              alignment: Alignment.bottomCenter,
              minHeight: 52.0,
              maxHeight: 62.0,
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: AnimatedOpacity(
                  opacity: showHudChrome ? 1.0 : 0.0,
                  duration: _layoutAnimDuration,
                  curve: _layoutAnimCurve,
                  child: IgnorePointer(
                    ignoring: !showHudChrome,
                    child: ExcludeSemantics(
                      excluding: !showHudChrome,
                      child: ExcludeFocus(
                        excluding: !showHudChrome,
                        child: HudBottomBar(
                          isInspectorOpen: _inspectorOpen,
                          onToggleInspector: _toggleInspector,
                          onOpenBookmarks: () =>
                              showFractalBookmarksSheet(context),
                          onExportPng: () =>
                              _handleQuickExport(context, engine),
                          onHideHud: () => _hideHudWithHint(context, engine),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );

          final Widget inspectorNavigator = Navigator(
            key: _inspectorNavKey,
            onGenerateRoute: (RouteSettings settings) {
              return MaterialPageRoute<void>(
                settings: settings,
                builder: (BuildContext navContext) => FractalInspectorPanel(
                  viewport: _latestViewport,
                  viewportListenable: _viewportNotifier,
                  onClose: () {
                    setState(() {
                      _inspectorOpen = false;
                      _compactInspectorFraction = 0.65;
                    });
                  },
                ),
              );
            },
          );

          final Widget inspectorCard = Material(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(24),
            clipBehavior: Clip.antiAlias,
            child: sizeClass.isCompact
                ? Column(
                    children: <Widget>[
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          setState(() {
                            _compactInspectorFraction =
                                _compactInspectorFraction >= 0.98 ? 0.65 : 1.0;
                          });
                        },
                        onVerticalDragStart: (_) {
                          setState(() => _isDraggingInspector = true);
                        },
                        onVerticalDragUpdate: (DragUpdateDetails details) {
                          setState(() {
                            _compactInspectorFraction =
                                (_compactInspectorFraction -
                                        details.delta.dy /
                                            math.max(1.0, innerHeight))
                                    .clamp(0.20, 1.0);
                          });
                        },
                        onVerticalDragEnd: (DragEndDetails details) {
                          final double velocity =
                              details.primaryVelocity ?? 0.0;
                          setState(() {
                            _isDraggingInspector = false;
                            if (velocity < -450 ||
                                _compactInspectorFraction >= 0.80) {
                              _compactInspectorFraction = 1.0;
                            } else if (velocity > 450) {
                              if (_compactInspectorFraction >= 0.72) {
                                _compactInspectorFraction = 0.65;
                              } else {
                                _inspectorOpen = false;
                                _compactInspectorFraction = 0.65;
                              }
                            } else if (_compactInspectorFraction < 0.38) {
                              _inspectorOpen = false;
                              _compactInspectorFraction = 0.65;
                            } else {
                              _compactInspectorFraction = 0.65;
                            }
                          });
                        },
                        onVerticalDragCancel: () {
                          setState(() => _isDraggingInspector = false);
                        },
                        child: SizedBox(
                          height: 28,
                          width: double.infinity,
                          child: Center(
                            child: Container(
                              width: 36,
                              height: 4,
                              decoration: BoxDecoration(
                                color: scheme.onSurfaceVariant
                                    .withValues(alpha: 0.4),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(child: inspectorNavigator),
                    ],
                  )
                : inspectorNavigator,
          );

          final Widget layoutBody;
          if (sizeClass.isCompact) {
            final double openInspectorHeight = innerHeight <= 0
                ? 0.0
                : (innerHeight * _compactInspectorFraction)
                    .clamp(0.0, innerHeight);
            final double topGap =
                (_inspectorOpen && _compactInspectorFraction >= 0.98)
                    ? 0.0
                    : 10.0;
            layoutBody = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(child: fractalCard),
                bottomBarSlot,
                AnimatedContainer(
                  duration: _isDraggingInspector
                      ? Duration.zero
                      : _layoutAnimDuration,
                  curve: _layoutAnimCurve,
                  height: _inspectorOpen ? openInspectorHeight : 0.0,
                  clipBehavior: Clip.hardEdge,
                  decoration: const BoxDecoration(),
                  child: OverflowBox(
                    alignment: Alignment.topCenter,
                    minHeight: openInspectorHeight,
                    maxHeight: openInspectorHeight,
                    child: SizedBox(
                      height: openInspectorHeight,
                      child: Padding(
                        padding: EdgeInsets.only(top: topGap),
                        child: AnimatedOpacity(
                          opacity: _inspectorOpen ? 1.0 : 0.0,
                          duration: _layoutAnimDuration,
                          curve: _layoutAnimCurve,
                          child: IgnorePointer(
                            ignoring: !_inspectorOpen,
                            child: ExcludeSemantics(
                              excluding: !_inspectorOpen,
                              child: ExcludeFocus(
                                excluding: !_inspectorOpen,
                                child: inspectorCard,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          } else {
            final double minWidth = math.min(280.0, innerWidth);
            final double openInspectorWidth = innerWidth <= 0
                ? 0.0
                : (sizeClass.isExpanded
                    ? (innerWidth / 3.0).clamp(minWidth, innerWidth)
                    : (innerWidth * 0.5).clamp(minWidth, innerWidth));
            layoutBody = Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Expanded(child: fractalCard),
                      bottomBarSlot,
                    ],
                  ),
                ),
                AnimatedContainer(
                  duration: _layoutAnimDuration,
                  curve: _layoutAnimCurve,
                  width: _inspectorOpen ? openInspectorWidth : 0.0,
                  clipBehavior: Clip.hardEdge,
                  decoration: const BoxDecoration(),
                  child: OverflowBox(
                    alignment: AlignmentDirectional.centerStart,
                    minWidth: openInspectorWidth,
                    maxWidth: openInspectorWidth,
                    child: SizedBox(
                      width: openInspectorWidth,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: AnimatedOpacity(
                          opacity: _inspectorOpen ? 1.0 : 0.0,
                          duration: _layoutAnimDuration,
                          curve: _layoutAnimCurve,
                          child: IgnorePointer(
                            ignoring: !_inspectorOpen,
                            child: ExcludeSemantics(
                              excluding: !_inspectorOpen,
                              child: ExcludeFocus(
                                excluding: !_inspectorOpen,
                                child: inspectorCard,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          }

          return AnimatedPadding(
            duration: _layoutAnimDuration,
            curve: _layoutAnimCurve,
            padding: outerPadding,
            child: layoutBody,
          );
        },
      ),
    ),
    );
  }
}

class _ViewportEdgeProgressBar extends StatelessWidget {
  final double progress;
  final double cornerRadius;
  final Color color;
  final Color trackColor;
  final double strokeWidth;
  final double extraInset;

  const _ViewportEdgeProgressBar({
    required this.progress,
    required this.cornerRadius,
    required this.color,
    required this.trackColor,
    this.strokeWidth = 3.0,
    this.extraInset = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ViewportEdgeProgressPainter(
        progress: progress,
        cornerRadius: cornerRadius,
        color: color,
        trackColor: trackColor,
        strokeWidth: strokeWidth,
        extraInset: extraInset,
      ),
    );
  }
}

class _ViewportEdgeProgressPainter extends CustomPainter {
  final double progress;
  final double cornerRadius;
  final Color color;
  final Color trackColor;
  final double strokeWidth;
  final double extraInset;

  const _ViewportEdgeProgressPainter({
    required this.progress,
    required this.cornerRadius,
    required this.color,
    required this.trackColor,
    required this.strokeWidth,
    this.extraInset = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final double r = cornerRadius.clamp(
      0.0,
      math.min(size.width * 0.45, size.height * 0.45),
    );
    final double inset = strokeWidth * 0.5 + extraInset;
    final double arcRadius = math.max(0.0, r - inset);

    final ui.Path path = ui.Path()..moveTo(inset, r);
    if (r > inset) {
      path.arcToPoint(
        Offset(r, inset),
        radius: Radius.circular(arcRadius),
        clockwise: true,
      );
    } else {
      path.moveTo(inset, inset);
    }
    path.lineTo(size.width - r, inset);
    if (r > inset) {
      path.arcToPoint(
        Offset(size.width - inset, r),
        radius: Radius.circular(arcRadius),
        clockwise: true,
      );
    } else {
      path.lineTo(size.width - inset, inset);
    }

    final Paint trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = trackColor;
    canvas.drawPath(path, trackPaint);

    if (progress > 0.0) {
      final Paint progressPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = color;
      for (final ui.PathMetric metric in path.computeMetrics()) {
        final ui.Path segment =
            metric.extractPath(0.0, metric.length * progress);
        canvas.drawPath(segment, progressPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ViewportEdgeProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.cornerRadius != cornerRadius ||
        oldDelegate.color != color ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.extraInset != extraInset;
  }
}
