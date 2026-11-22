import 'dart:async';
import 'dart:math' as math;

import 'package:dynamic_color/dynamic_color.dart';
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
  bool _inspectorOpen = false;
  bool _shownLongPressHint = false;
  Size _latestViewport = Size.zero;

  void _toggleInspector() {
    setState(() {
      _inspectorOpen = !_inspectorOpen;
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

    return Scaffold(
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
                            });
                          }
                        : null,
                    onToggleInspector: _toggleInspector,
                    onLongPress: () => _handleCanvasLongPress(context, engine),
                    onViewportChanged: (Size size) {
                      _latestViewport = size;
                    },
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

          final Widget inspectorCard = Material(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(24),
            clipBehavior: Clip.antiAlias,
            child: FractalInspectorPanel(
              viewport: _latestViewport,
              onClose: () {
                setState(() {
                  _inspectorOpen = false;
                });
              },
            ),
          );

          final Widget layoutBody;
          if (sizeClass.isCompact) {
            final double openInspectorHeight = innerHeight <= 0
                ? 0.0
                : (innerHeight * 0.65)
                    .clamp(math.min(160.0, innerHeight), innerHeight);
            layoutBody = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(child: fractalCard),
                bottomBarSlot,
                AnimatedContainer(
                  duration: _layoutAnimDuration,
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
                        padding: const EdgeInsets.only(top: 10),
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
    );
  }
}
