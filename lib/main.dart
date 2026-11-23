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
import 'package:shared_preferences/shared_preferences.dart';

import 'engine/fractal_engine.dart';
import 'engine/fractal_share_link.dart';
import 'widgets/fractal_canvas.dart';
import 'widgets/hud_overlay.dart';
import 'widgets/inspector_panel.dart';
import 'widgets/share_sheet.dart';

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
  static const MethodChannel _displayChannel =
      MethodChannel('page.puzzak.fractals/display');

  final GlobalKey _canvasKey = GlobalKey();
  final GlobalKey<NavigatorState> _inspectorNavKey = GlobalKey<NavigatorState>();
  final ValueNotifier<Size> _viewportNotifier = ValueNotifier<Size>(Size.zero);
  bool _inspectorOpen = false;
  double _compactInspectorFraction = 0.65;
  bool _isDraggingInspector = false;
  bool _shownLongPressHint = false;
  Size _latestViewport = Size.zero;
  double _screenTopCornerRadiusPx = 0.0;
  SharedFractalPayload? _pendingSharedPayload;

  @override
  void initState() {
    super.initState();
    _displayChannel.setMethodCallHandler(_handleDisplayChannelCall);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!kIsWeb && Platform.isAndroid) {
        unawaited(_queryTopCornerRadius());
      }
      unawaited(_checkInitialDeepLinkAndReferrer());
    });
  }

  Future<dynamic> _handleDisplayChannelCall(MethodCall call) async {
    if (call.method == 'onDeepLink') {
      _handleIncomingDeepLink(call.arguments as String?);
    }
    return null;
  }

  Future<void> _checkInitialDeepLinkAndReferrer() async {
    if (!mounted || kIsWeb) return;
    try {
      final String? initialLink =
          await _displayChannel.invokeMethod<String>('getInitialDeepLink');
      if (!mounted) return;
      if (initialLink != null && initialLink.trim().isNotEmpty) {
        _handleIncomingDeepLink(initialLink);
      }
    } catch (_) {
      // Ignore platform channel errors on unsupported hosts or tests.
    }

    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final bool alreadyChecked =
          prefs.getBool('fv_referrer_checked') ?? false;
      if (alreadyChecked || !mounted) return;
      await prefs.setBool('fv_referrer_checked', true);
      final String? referrer =
          await _displayChannel.invokeMethod<String>('getInstallReferrer');
      if (!mounted || _pendingSharedPayload != null) return;
      if (referrer != null && referrer.trim().isNotEmpty) {
        _handleIncomingDeepLink(referrer);
      }
    } catch (_) {
      // Ignore platform channel errors on unsupported hosts or tests.
    }
  }

  void _handleIncomingDeepLink(String? raw) {
    final SharedFractalPayload? payload = FractalShareLink.tryParse(raw);
    if (payload == null || !mounted) return;
    final FractalEngine engine = context.read<FractalEngine>();
    engine.applyBookmark(payload.bookmark);
    engine.setRotation(payload.rotation);
    engine.setColorOffset(payload.colorOffset);
    engine.setSmoothColor(payload.smoothColor);
    setState(() {
      _pendingSharedPayload = payload;
    });
  }

  Future<void> _queryTopCornerRadius() async {
    if (!mounted) return;
    try {
      final double rawPx =
          await _displayChannel.invokeMethod<double>('getTopCornerRadius') ??
              0.0;
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
    _displayChannel.setMethodCallHandler(null);
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

  void _openExportInspector(FractalEngine engine) {
    final bool isCompact =
        M3xWindowSizeClass.fromWidth(MediaQuery.sizeOf(context).width)
            .isCompact;
    setState(() {
      _inspectorOpen = true;
      _compactInspectorFraction = 0.65;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      FractalInspectorPanel.openExport(
        _inspectorNavKey.currentState,
        viewport: _latestViewport,
        viewportListenable: _viewportNotifier,
        isSheet: isCompact,
        onClose: () {
          setState(() {
            _inspectorOpen = false;
            _compactInspectorFraction = 0.65;
          });
        },
      );
    });
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
                  if (engine.isBenchmarking) ...<Widget>[
                    if (engine.benchmarkPreviewImage != null)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: RawImage(
                            image: engine.benchmarkPreviewImage,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    Positioned(
                      left: 14,
                      right: 14,
                      bottom: 14,
                      child: IgnorePointer(
                        child: Align(
                          alignment: Alignment.bottomLeft,
                          child: Material(
                            color: scheme.surfaceContainerHigh
                                .withValues(alpha: 0.90),
                            elevation: 3,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                              side: BorderSide(
                                color: scheme.outlineVariant
                                    .withValues(alpha: 0.45),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Icon(
                                    Icons.speed_rounded,
                                    size: 18,
                                    color: scheme.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      engine.benchmarkDetail.isEmpty
                                          ? engine.benchmarkStage
                                          : '${engine.benchmarkStage} · ${engine.benchmarkDetail}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            fontFeatures: const <FontFeature>[
                                              FontFeature.tabularFigures(),
                                            ],
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
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
                  if (_pendingSharedPayload != null)
                    Positioned(
                      top: 12,
                      left: 12,
                      right: 12,
                      child: Center(
                        child: _SharedBookmarkPreviewPill(
                          payload: _pendingSharedPayload!,
                          onSave: () {
                            final SharedFractalPayload payload =
                                _pendingSharedPayload!;
                            engine.addCustomBookmark(payload.bookmark.name);
                            setState(() {
                              _pendingSharedPayload = null;
                            });
                            final String rawSaved = engine.tr('bookmark_saved');
                            final String savedMsg = (rawSaved.isEmpty ||
                                    rawSaved == 'bookmark_saved' ||
                                    rawSaved.startsWith('!'))
                                ? 'Bookmark saved'
                                : rawSaved;
                            ScaffoldMessenger.of(context)
                              ..hideCurrentSnackBar()
                              ..showSnackBar(
                                SnackBar(
                                  content: Text(savedMsg),
                                  behavior: SnackBarBehavior.floating,
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                          },
                          onDismiss: () {
                            setState(() {
                              _pendingSharedPayload = null;
                            });
                          },
                        ),
                      ),
                    ),
                  Positioned(
                    right: 14,
                    bottom: 14,
                    child: AnimatedOpacity(
                      opacity: showHudChrome ? 1.0 : 0.0,
                      duration: _layoutAnimDuration,
                      curve: _layoutAnimCurve,
                      child: IgnorePointer(
                        ignoring: !showHudChrome,
                        child: FloatingActionButton.small(
                          heroTag: 'reset_view_fab',
                          tooltip: engine.tr('reset_view'),
                          backgroundColor: scheme.secondaryContainer,
                          foregroundColor: scheme.onSecondaryContainer,
                          onPressed: engine.resetView,
                          child: const Icon(Icons.center_focus_strong_rounded),
                        ),
                      ),
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
                          onShare: () => showShareFractalSheet(
                            context,
                            engine,
                            onOpenExport: () => _openExportInspector(engine),
                          ),
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
                  isSheet: sizeClass.isCompact,
                  onHeaderDragStart: sizeClass.isCompact
                      ? (_) {
                          setState(() => _isDraggingInspector = true);
                        }
                      : null,
                  onHeaderDragUpdate: sizeClass.isCompact
                      ? (DragUpdateDetails details) {
                          setState(() {
                            _compactInspectorFraction =
                                (_compactInspectorFraction -
                                        details.delta.dy /
                                            math.max(1.0, innerHeight))
                                    .clamp(0.20, 1.0);
                          });
                        }
                      : null,
                  onHeaderDragEnd: sizeClass.isCompact
                      ? (DragEndDetails details) {
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
                        }
                      : null,
                  onHeaderDragCancel: sizeClass.isCompact
                      ? () {
                          setState(() => _isDraggingInspector = false);
                        }
                      : null,
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
            child: inspectorNavigator,
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

class _SharedBookmarkPreviewPill extends StatelessWidget {
  final SharedFractalPayload payload;
  final VoidCallback onSave;
  final VoidCallback onDismiss;

  const _SharedBookmarkPreviewPill({
    required this.payload,
    required this.onSave,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Material(
      color: scheme.surfaceContainerHigh.withValues(alpha: 0.94),
      elevation: 2,
      shape: StadiumBorder(
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.link_rounded,
              size: 18,
              color: scheme.primary,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                payload.bookmark.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              onPressed: onSave,
              tooltip: 'Save',
              visualDensity: VisualDensity.compact,
              icon: Icon(
                Icons.bookmark_add_rounded,
                size: 20,
                color: scheme.primary,
              ),
            ),
            IconButton(
              onPressed: onDismiss,
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_rounded, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}
