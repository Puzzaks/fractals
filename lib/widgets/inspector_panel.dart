import 'dart:io' show Directory, File, Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show Uint8List, ValueListenable, kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:m3x/m3x.dart' show M3x;
import 'package:m3x_gh/m3x_gh.dart';
import 'package:m3x_ui/m3x_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../engine/cpu_renderer.dart';
import '../engine/fractal_engine.dart';
import '../engine/fractal_models.dart';
import '../engine/play_games_service.dart';
import '../engine/potato_benchmark.dart';
import 'hud_overlay.dart';
import 'share_sheet.dart';

/// Renders the current fractal view at [width] × [height] pixels using the
/// multi-isolate CPU `float64` renderer in [format] (PNG or JPEG) and opens
/// the system share sheet.
Future<void> exportFractalImage(
  BuildContext context,
  FractalEngine engine,
  Size viewport, {
  required int width,
  required int height,
  ExportImageFormat format = ExportImageFormat.png,
  double? rotationOverrideRadians,
}) async {
  if (engine.isExporting) return;

  final ColorScheme scheme = Theme.of(context).colorScheme;
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final RenderBox? box = context.findRenderObject() as RenderBox?;
  final Rect? shareOrigin =
      (box != null && box.hasSize) ? box.localToGlobal(Offset.zero) & box.size : null;

  final Size effectiveViewport =
      viewport.isEmpty ? const Size(1080, 1920) : viewport;
  final int exportW = width.clamp(128, 7680);
  final int exportH = height.clamp(128, 7680);
  final double rot = rotationOverrideRadians ?? engine.rotation;
  final double baseSpan =
      math.min(effectiveViewport.width, effectiveViewport.height);
  final double exportAspect = exportW / exportH;
  final double logicalW =
      exportAspect >= 1.0 ? baseSpan * exportAspect : baseSpan;
  final double logicalH =
      exportAspect >= 1.0 ? baseSpan : baseSpan / exportAspect;

  final String exportingMsg = engine.tr('exporting');
  final String failedMsg = engine.tr('export_failed');
  final String shareText =
      '${engine.tr(engine.fractalType.translationKey)} · ${FractalEngine.formatZoom(engine.zoom)}';

  engine.setExporting(true);
  final CpuRenderCancellationToken cancelToken =
      engine.startExportCancellationToken();
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(exportingMsg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );

  try {
    final CpuRenderRequest request = CpuRenderRequest(
      width: exportW,
      height: exportH,
      logicalWidth: logicalW,
      logicalHeight: logicalH,
      centerX: engine.centerX,
      centerY: engine.centerY,
      zoom: engine.zoom,
      rotCos: math.cos(rot),
      rotSin: math.sin(rot),
      maxIterations: engine.effectiveMaxIterations,
      fractalTypeIndex: engine.fractalType.shaderIndex,
      juliaCx: engine.juliaCx,
      juliaCy: engine.juliaCy,
      paletteIndex: engine.palette.shaderIndex,
      primaryR: scheme.primary.r,
      primaryG: scheme.primary.g,
      primaryB: scheme.primary.b,
      secondaryR: scheme.tertiary.r,
      secondaryG: scheme.tertiary.g,
      secondaryB: scheme.tertiary.b,
      colorOffset: engine.colorOffset,
      smoothColor: engine.smoothColor,
    );

    final Uint8List? imageBytes =
        await CpuFractalRenderer.renderTiledEncodedImageBytes(
      request,
      format: format,
      cancellationToken: cancelToken,
      onProgress: (double p) {
        engine.setExportProgress(p);
        if (engine.isBenchmarking) {
          engine.updateBenchmarkOverlay(
            active: true,
            stage: exportingMsg,
            detail: '$exportW × $exportH · ${(p * 100).round()}%',
          );
        }
      },
      onPreviewTile: (ui.Image previewImg) {
        final int pct = ((engine.exportProgress ?? 0.0) * 100).round();
        engine.updateBenchmarkOverlay(
          active: true,
          stage: exportingMsg,
          detail: '$exportW × $exportH · $pct%',
          previewImage: previewImg,
        );
      },
    );
    if (imageBytes == null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(failedMsg),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }

    final bool isJpeg = format == ExportImageFormat.jpeg;
    final String ext = isJpeg ? 'jpg' : 'png';
    final String mimeType = isJpeg ? 'image/jpeg' : 'image/png';
    final String fileName =
        'fractal_${engine.fractalType.name}_${DateTime.now().millisecondsSinceEpoch}.$ext';

    if (kIsWeb) {
      await Share.shareXFiles(
        <XFile>[XFile.fromData(imageBytes, mimeType: mimeType, name: fileName)],
        text: shareText,
        sharePositionOrigin: shareOrigin,
      );
    } else {
      final Directory tempDir = await getTemporaryDirectory();
      final File file =
          File('${tempDir.path}${Platform.pathSeparator}$fileName');
      await file.writeAsBytes(imageBytes, flush: true);
      await Share.shareXFiles(
        <XFile>[XFile(file.path, mimeType: mimeType)],
        text: shareText,
        sharePositionOrigin: shareOrigin,
      );
    }
    engine.recordShareEvent();
  } on CpuRenderCancelledException {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(_trOr(engine, 'export_cancelled', 'Export cancelled')),
          behavior: SnackBarBehavior.floating,
        ),
      );
  } catch (e) {
    engine.analytics.log('Export', 'Error', '$e');
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(failedMsg),
          behavior: SnackBarBehavior.floating,
        ),
      );
  } finally {
    engine.updateBenchmarkOverlay(active: false);
    engine.setExporting(false);
  }
}

/// Renders the current fractal view at [targetLongEdge] pixels as PNG and
/// opens the system share sheet.
Future<void> exportFractalPng(
  BuildContext context,
  FractalEngine engine,
  Size viewport,
  int targetLongEdge,
) {
  final Size effectiveViewport =
      viewport.isEmpty ? const Size(1080, 1920) : viewport;
  final double aspect = effectiveViewport.width / effectiveViewport.height;
  final int exportW;
  final int exportH;
  if (effectiveViewport.width >= effectiveViewport.height) {
    exportW = targetLongEdge.clamp(128, 7680);
    exportH = math.max(1, (exportW / aspect).round());
  } else {
    exportH = targetLongEdge.clamp(128, 7680);
    exportW = math.max(1, (exportH * aspect).round());
  }
  return exportFractalImage(
    context,
    engine,
    effectiveViewport,
    width: exportW,
    height: exportH,
    format: ExportImageFormat.png,
  );
}

String _trOr(FractalEngine engine, String key, String fallback) {
  final String raw = engine.tr(key);
  if (raw.isEmpty || raw == key || raw.startsWith('!')) {
    return fallback;
  }
  return raw;
}

String _qualityTooltipLabel(FractalEngine engine, RenderQuality quality) {
  switch (quality) {
    case RenderQuality.performance:
      return _trOr(engine, 'quality_short_low', 'Low');
    case RenderQuality.balanced:
      return _trOr(engine, 'quality_short_balanced', 'Balanced');
    case RenderQuality.native:
      return _trOr(engine, 'quality_short_high', 'High');
    case RenderQuality.ultra:
      return _trOr(engine, 'quality_short_ultra', 'Ultra');
  }
}

String _formatDuration(int ms) {
  final int totalSeconds = (ms / 1000).floor();
  final int hours = totalSeconds ~/ 3600;
  final int minutes = (totalSeconds % 3600) ~/ 60;
  final int seconds = totalSeconds % 60;
  if (hours > 0) {
    return '${hours}h ${minutes}m';
  }
  if (minutes > 0) {
    return '${minutes}m ${seconds}s';
  }
  return '${seconds}s';
}

/// Triggers Play Games sign-in and shows a fallback snackbar if cancelled or unavailable.
Future<void> _handlePlayGamesSignIn(
  BuildContext context,
  FractalEngine engine,
) async {
  final bool ok = await engine.signInPlayGames();
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Play Games sign-in was cancelled or unavailable'),
      ),
    );
  }
}

/// Presents [FractalInspectorPanel] inside a translucent draggable modal bottom
/// sheet for compact (`< 680dp`) viewports.
Future<void> showFractalInspectorSheet(
  BuildContext context, {
  required Size viewport,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext sheetContext) {
      final ColorScheme scheme = Theme.of(sheetContext).colorScheme;
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.35,
        maxChildSize: 0.95,
        builder: (BuildContext ctx, ScrollController scrollController) {
          return Material(
            color: scheme.surface.withValues(alpha: 0.92),
            elevation: 8,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Navigator(
              onGenerateRoute: (RouteSettings settings) {
                return MaterialPageRoute<void>(
                  settings: settings,
                  builder: (BuildContext navCtx) => FractalInspectorPanel(
                    viewport: viewport,
                    scrollController: scrollController,
                    isSheet: true,
                    onClose: () => Navigator.of(sheetContext).pop(),
                  ),
                );
              },
            ),
          );
        },
      );
    },
  );
}

/// Presents a focused bookmarks browser & quick-save modal bottom sheet.
Future<void> showFractalBookmarksSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext sheetContext) {
      final ColorScheme scheme = Theme.of(sheetContext).colorScheme;
      final FractalEngine engine = sheetContext.watch<FractalEngine>();
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        minChildSize: 0.35,
        maxChildSize: 0.92,
        builder: (BuildContext ctx, ScrollController scrollController) {
          return Material(
            color: scheme.surface.withValues(alpha: 0.94),
            elevation: 8,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: <Widget>[
                const _SheetHandle(),
                _PanelHeader(
                  title: engine.tr('section_bookmarks'),
                  onClose: () => Navigator.of(sheetContext).pop(),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.only(top: 10, bottom: 28),
                    children: <Widget>[
                      _BookmarkCardGroup(
                        engine: engine,
                        onApplied: () => Navigator.of(sheetContext).pop(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

class _BookmarkNameDialog extends StatefulWidget {
  final String title;
  final String hintText;
  final String cancelLabel;
  final String saveLabel;
  final String initialName;

  const _BookmarkNameDialog({
    required this.title,
    required this.hintText,
    required this.cancelLabel,
    required this.saveLabel,
    required this.initialName,
  });

  @override
  State<_BookmarkNameDialog> createState() => _BookmarkNameDialogState();
}

class _BookmarkNameDialogState extends State<_BookmarkNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: widget.hintText,
          border: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.cancelLabel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.saveLabel),
        ),
      ],
    );
  }
}

Future<void> _showAddBookmarkDialog(
  BuildContext context,
  FractalEngine engine,
) async {
  final String defaultName =
      '${engine.tr(engine.fractalType.translationKey)} (${FractalEngine.formatZoom(engine.zoom)})';
  final String? result = await showDialog<String>(
    context: context,
    builder: (BuildContext dialogContext) => _BookmarkNameDialog(
      title: engine.tr('save_bookmark'),
      hintText: engine.tr('save_bookmark_hint'),
      cancelLabel: engine.tr('cancel'),
      saveLabel: engine.tr('save'),
      initialName: defaultName,
    ),
  );
  if (result != null && result.isNotEmpty) {
    engine.addCustomBookmark(result);
  }
}

Future<void> _showRenameBookmarkDialog(
  BuildContext context,
  FractalEngine engine,
  FractalBookmark bookmark,
) async {
  final String? result = await showDialog<String>(
    context: context,
    builder: (BuildContext dialogContext) => _BookmarkNameDialog(
      title: _trOr(engine, 'rename_bookmark', 'Rename Bookmark'),
      hintText: engine.tr('save_bookmark_hint'),
      cancelLabel: engine.tr('cancel'),
      saveLabel: engine.tr('save'),
      initialName: bookmark.name,
    ),
  );
  if (result != null && result.isNotEmpty && result != bookmark.name) {
    engine.renameCustomBookmark(bookmark.id, result);
  }
}

class InspectorSheetDragScope extends InheritedWidget {
  final GestureDragStartCallback? onHeaderDragStart;
  final GestureDragUpdateCallback? onHeaderDragUpdate;
  final GestureDragEndCallback? onHeaderDragEnd;
  final GestureDragCancelCallback? onHeaderDragCancel;

  const InspectorSheetDragScope({
    super.key,
    required super.child,
    this.onHeaderDragStart,
    this.onHeaderDragUpdate,
    this.onHeaderDragEnd,
    this.onHeaderDragCancel,
  });

  bool get hasCallbacks =>
      onHeaderDragStart != null ||
      onHeaderDragUpdate != null ||
      onHeaderDragEnd != null ||
      onHeaderDragCancel != null;

  Widget wrap(Widget child) {
    return InspectorSheetDragScope(
      onHeaderDragStart: onHeaderDragStart,
      onHeaderDragUpdate: onHeaderDragUpdate,
      onHeaderDragEnd: onHeaderDragEnd,
      onHeaderDragCancel: onHeaderDragCancel,
      child: child,
    );
  }

  static InspectorSheetDragScope? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<InspectorSheetDragScope>();
  }

  @override
  bool updateShouldNotify(InspectorSheetDragScope oldWidget) {
    return onHeaderDragStart != oldWidget.onHeaderDragStart ||
        onHeaderDragUpdate != oldWidget.onHeaderDragUpdate ||
        onHeaderDragEnd != oldWidget.onHeaderDragEnd ||
        onHeaderDragCancel != oldWidget.onHeaderDragCancel;
  }
}

/// Material 3 Expressive Settings Hub built with `m3x_ui` components that
/// pushes dedicated sub-pages inside its enclosing nested [Navigator].
class FractalInspectorPanel extends StatelessWidget {
  final Size viewport;
  final ValueListenable<Size>? viewportListenable;
  final ScrollController? scrollController;
  final bool isSheet;
  final VoidCallback? onClose;
  final GestureDragStartCallback? onHeaderDragStart;
  final GestureDragUpdateCallback? onHeaderDragUpdate;
  final GestureDragEndCallback? onHeaderDragEnd;
  final GestureDragCancelCallback? onHeaderDragCancel;

  const FractalInspectorPanel({
    super.key,
    required this.viewport,
    this.viewportListenable,
    this.scrollController,
    this.isSheet = false,
    this.onClose,
    this.onHeaderDragStart,
    this.onHeaderDragUpdate,
    this.onHeaderDragEnd,
    this.onHeaderDragCancel,
  });

  static void openExport(
    NavigatorState? nav, {
    required Size viewport,
    ValueListenable<Size>? viewportListenable,
    bool isSheet = false,
    VoidCallback? onClose,
  }) {
    if (nav == null) return;
    final InspectorSheetDragScope? dragScope =
        InspectorSheetDragScope.maybeOf(nav.context);
    final Widget page = _ExportSubPage(
      viewport: viewport,
      viewportListenable: viewportListenable,
      isSheet: isSheet,
      onClose: onClose,
    );
    nav.push(
      MaterialPageRoute<void>(
        builder: (BuildContext _) =>
            dragScope != null ? dragScope.wrap(page) : page,
      ),
    );
  }

  void _pushSubPage(BuildContext context, Widget page) {
    final InspectorSheetDragScope? dragScope =
        InspectorSheetDragScope.maybeOf(context);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext _) =>
            dragScope != null ? dragScope.wrap(page) : page,
      ),
    );
  }

  Future<void> _showLanguagePicker(
    BuildContext context,
    FractalEngine engine,
  ) async {
    final List<dynamic> rawLanguages = engine.dictionary.languages.isNotEmpty
        ? engine.dictionary.languages
        : const <Map<String, String>>[
            <String, String>{
              'id': 'en',
              'origin': 'English',
              'name': 'English',
            },
            <String, String>{
              'id': 'uk',
              'origin': 'Українська',
              'name': 'Ukrainian',
            },
          ];

    final List<OptionPickerItem<String>> items = <OptionPickerItem<String>>[
      OptionPickerItem<String>(
        value: '__system__',
        title: engine.tr('language_system'),
      ),
      for (final dynamic entry in rawLanguages)
        if (entry is Map && entry['id'] != null)
          OptionPickerItem<String>(
            value: entry['id'].toString(),
            title: (entry['origin'] ?? entry['name'] ?? entry['id']).toString(),
            subtitle: (entry['name'] != null &&
                    entry['name'].toString() !=
                        (entry['origin'] ?? '').toString())
                ? entry['name'].toString()
                : '',
          ),
    ];

    final String current = engine.dictionary.isSystemLanguage
        ? '__system__'
        : engine.dictionary.locale;

    await OptionPickerDialog.show<String>(
      context: context,
      title: engine.tr('language_label'),
      options: items,
      currentValue: current,
      onSelected: (String value) {
        engine.setLanguage(value == '__system__' ? null : value);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final FractalEngine engine = context.watch<FractalEngine>();
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String languageSubtitle = engine.dictionary.isSystemLanguage
        ? engine.tr('language_system')
        : engine.dictionary.currentLanguageName;
    final int bookmarkCount =
        builtInBookmarks.length + engine.customBookmarks.length;
    final PotatoBenchmarkResult? b = engine.lastBenchmark;

    final Widget headerContent = Column(
      children: <Widget>[
        if (isSheet) const _SheetHandle(),
        _PanelHeader(
          title: engine.tr('inspector_title'),
          onClose: onClose,
        ),
      ],
    );
    final InspectorSheetDragScope? inheritedScope =
        InspectorSheetDragScope.maybeOf(context);
    final GestureDragStartCallback? effectiveDragStart =
        onHeaderDragStart ?? inheritedScope?.onHeaderDragStart;
    final GestureDragUpdateCallback? effectiveDragUpdate =
        onHeaderDragUpdate ?? inheritedScope?.onHeaderDragUpdate;
    final GestureDragEndCallback? effectiveDragEnd =
        onHeaderDragEnd ?? inheritedScope?.onHeaderDragEnd;
    final GestureDragCancelCallback? effectiveDragCancel =
        onHeaderDragCancel ?? inheritedScope?.onHeaderDragCancel;
    final bool hasOwnHeaderDrag = onHeaderDragStart != null ||
        onHeaderDragUpdate != null ||
        onHeaderDragEnd != null ||
        onHeaderDragCancel != null;
    final bool hasHeaderDrag = effectiveDragStart != null ||
        effectiveDragUpdate != null ||
        effectiveDragEnd != null ||
        effectiveDragCancel != null;

    final Widget body = Material(
      color: scheme.surface,
      child: Column(
        children: <Widget>[
          if (hasHeaderDrag)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragStart: effectiveDragStart,
              onVerticalDragUpdate: effectiveDragUpdate,
              onVerticalDragEnd: effectiveDragEnd,
              onVerticalDragCancel: effectiveDragCancel,
              child: headerContent,
            )
          else
            headerContent,
          const Divider(height: 1),
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.only(bottom: 32),
                children: <Widget>[
                  const _LiveTelemetrySection(),
                  Category.settings(
                    title: _trOr(engine, 'section_settings', 'Settings'),
                    context: context,
                  ),
                  CardGroup(
                    children: <Widget>[
                      CardContents.tapIcon(
                        title: engine.tr('section_fractal'),
                        subtitle: engine.tr(engine.fractalType.translationKey),
                        icon: fractalTypeIcon(engine.fractalType),
                        color: scheme.onPrimaryContainer,
                        colorBG: scheme.primaryContainer,
                        trailing: const Icon(Icons.chevron_right_rounded),
                        action: () => _pushSubPage(
                          context,
                          _FractalCameraPage(
                            isSheet: isSheet,
                            onClose: onClose,
                          ),
                        ),
                      ),
                      CardContents.tapIcon(
                        title: engine.tr('section_appearance'),
                        subtitle: engine.tr(engine.palette.translationKey),
                        icon: Icons.palette_rounded,
                        color: scheme.onSecondaryContainer,
                        colorBG: scheme.secondaryContainer,
                        trailing: const Icon(Icons.chevron_right_rounded),
                        action: () => _pushSubPage(
                          context,
                          _AppearancePalettesPage(
                            isSheet: isSheet,
                            onClose: onClose,
                          ),
                        ),
                      ),
                      CardContents.tapIcon(
                        title: engine.tr('section_bookmarks'),
                        subtitle:
                            '$bookmarkCount ${_trOr(engine, 'bookmarks_saved_suffix', 'saved')}',
                        icon: Icons.bookmarks_rounded,
                        color: scheme.onTertiaryContainer,
                        colorBG: scheme.tertiaryContainer,
                        trailing: const Icon(Icons.chevron_right_rounded),
                        action: () => _pushSubPage(
                          context,
                          _BookmarksSubPage(
                            isSheet: isSheet,
                            onClose: onClose,
                          ),
                        ),
                      ),
                      CardContents.tapIcon(
                        title: engine.tr('section_rendering'),
                        subtitle:
                            '${engine.tr(engine.quality.translationKey)} · ${engine.activeRenderMode.badge}',
                        icon: Icons.tune_rounded,
                        color: scheme.onPrimaryFixed,
                        colorBG: scheme.primaryFixed,
                        trailing: const Icon(Icons.chevron_right_rounded),
                        action: () => _pushSubPage(
                          context,
                          _RenderingPerformancePage(
                            isSheet: isSheet,
                            onClose: onClose,
                          ),
                        ),
                      ),
                      CardContents.tapIcon(
                        title: engine.tr('benchmark_title'),
                        subtitle: b != null
                            ? '${b.tier} · ${b.score} ${_trOr(engine, 'benchmark_pts', 'pts')}'
                                '${engine.playGamesSignedIn && engine.potatoGlobalRank != null ? ' · ${engine.potatoGlobalRank!.displayRank}' : ''}'
                            : (engine.playGamesSignedIn &&
                                    engine.potatoGlobalRank != null
                                ? '${engine.potatoGlobalRank!.displayRank} · ${engine.tr('benchmark_subtitle')}'
                                : engine.tr('benchmark_subtitle')),
                        icon: Icons.speed_rounded,
                        color: scheme.onTertiaryFixed,
                        colorBG: scheme.tertiaryFixed,
                        trailing: const Icon(Icons.chevron_right_rounded),
                        action: () => _pushSubPage(
                          context,
                          _BenchmarkSubPage(
                            isSheet: isSheet,
                            onClose: onClose,
                          ),
                        ),
                      ),
                      CardContents.tapIcon(
                        title: _trOr(
                          engine,
                          'section_controls',
                          'Controls & Keybinds',
                        ),
                        subtitle: _trOr(
                          engine,
                          'section_controls_sub',
                          'Keyboard shortcuts & controls',
                        ),
                        icon: Icons.keyboard_rounded,
                        color: scheme.onSecondaryFixed,
                        colorBG: scheme.secondaryFixed,
                        trailing: const Icon(Icons.chevron_right_rounded),
                        action: () => _pushSubPage(
                          context,
                          _KeybindsSubPage(
                            isSheet: isSheet,
                            onClose: onClose,
                          ),
                        ),
                      ),
                      CardContents.tapIcon(
                        title: engine.tr('section_export'),
                        subtitle: _trOr(
                          engine,
                          'section_export_sub',
                          'PNG / JPEG · 1080p–8K',
                        ),
                        icon: Icons.ios_share_rounded,
                        color: scheme.onSurfaceVariant,
                        colorBG: scheme.surfaceContainerHighest,
                        trailing: const Icon(Icons.chevron_right_rounded),
                        action: () => _pushSubPage(
                          context,
                          _ExportSubPage(
                            viewport: viewport,
                            viewportListenable: viewportListenable,
                            isSheet: isSheet,
                            onClose: onClose,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Category.settings(
                    title: _trOr(engine, 'section_play_games', 'Play Games'),
                    context: context,
                  ),
                  CardGroup(
                    children: <Widget>[
                      if (engine.playGamesSignedIn) ...<Widget>[
                        CardContents.tap(
                          title: _trOr(
                            engine,
                            'play_games_deepest_zoom',
                            'Deepest Zoom',
                          ),
                          subtitle:
                              '${FractalEngine.formatZoom(engine.deepestZoom)} · ${engine.deepestZoomRank?.displayRank ?? _trOr(engine, 'play_games_unranked', 'Unranked')}',
                          trailing: const Icon(
                            Icons.zoom_in_rounded,
                            size: 20,
                          ),
                          action: () =>
                              PlayGamesService.instance.showLeaderboard(
                            PlayGamesService.leaderboardDeepestZoom,
                          ),
                        ),
                        CardContents.tap(
                          title: _trOr(
                            engine,
                            'play_games_exploration_time',
                            'Exploration Time',
                          ),
                          subtitle:
                              '${_formatDuration(engine.totalExplorationMs)} · ${engine.totalTimeRank?.displayRank ?? _trOr(engine, 'play_games_unranked', 'Unranked')}',
                          trailing: const Icon(
                            Icons.timer_rounded,
                            size: 20,
                          ),
                          action: () =>
                              PlayGamesService.instance.showLeaderboard(
                            PlayGamesService.leaderboardTotalTime,
                          ),
                        ),
                        CardContents.tap(
                          title: _trOr(
                            engine,
                            'play_games_potatoemeter_rank',
                            'Potatoemeter Rank',
                          ),
                          subtitle:
                              '${engine.lastBenchmark?.score ?? "--"} · ${engine.potatoGlobalRank?.displayRank ?? _trOr(engine, 'play_games_unranked', 'Unranked')}',
                          trailing: const Icon(
                            Icons.speed_rounded,
                            size: 20,
                          ),
                          action: () =>
                              PlayGamesService.instance.showLeaderboard(
                            PlayGamesService.leaderboardPotatoemeter,
                          ),
                        ),
                        CardContents.tap(
                          title: _trOr(
                            engine,
                            'play_games_all_leaderboards',
                            'All Leaderboards',
                          ),
                          subtitle: _trOr(
                            engine,
                            'play_games_leaderboards_sub',
                            'Deepest zoom, time & Potatoemeter',
                          ),
                          trailing: const Icon(
                            Icons.leaderboard_rounded,
                            size: 20,
                          ),
                          action: () =>
                              PlayGamesService.instance.showAllLeaderboards(),
                        ),
                        CardContents.tap(
                          title: _trOr(
                            engine,
                            'play_games_achievements',
                            'Achievements',
                          ),
                          subtitle: _trOr(
                            engine,
                            'play_games_achievements_sub',
                            'View unlocked fractal milestones',
                          ),
                          trailing: const Icon(
                            Icons.emoji_events_rounded,
                            size: 20,
                          ),
                          action: () =>
                              PlayGamesService.instance.showAchievements(),
                        ),
                        CardContents.tap(
                          title: _trOr(
                            engine,
                            'play_games_connected',
                            'Play Games Connected',
                          ),
                          subtitle: engine.playGamesPlayerName != null &&
                                  engine.playGamesPlayerName!.isNotEmpty
                              ? _trOr(
                                  engine,
                                  'play_games_signed_in_as',
                                  'Signed in as {name}',
                                ).replaceAll(
                                  '{name}',
                                  engine.playGamesPlayerName!,
                                )
                              : _trOr(
                                  engine,
                                  'play_games_connected_sub',
                                  'Progress & scores sync automatically',
                                ),
                          trailing: const Icon(
                            Icons.verified_user_rounded,
                            size: 20,
                          ),
                          action: () => engine.signInPlayGames(),
                        ),
                      ] else
                        CardContents.tap(
                          title: _trOr(
                            engine,
                            'play_games_sign_in',
                            'Sign in to Play Games',
                          ),
                          subtitle: _trOr(
                            engine,
                            'play_games_sign_in_sub',
                            'Sync leaderboards & achievements',
                          ),
                          trailing: const Icon(Icons.login_rounded, size: 20),
                          action: () =>
                              _handlePlayGamesSignIn(context, engine),
                        ),
                    ],
                  ),
                  Category.settings(
                    title: _trOr(engine, 'section_ecosystem', 'App & Links'),
                    context: context,
                  ),
                  CardGroup(
                    children: <Widget>[
                      CardContents.tap(
                        title: engine.tr('language_label'),
                        subtitle: languageSubtitle,
                        trailing: const Icon(Icons.translate_rounded, size: 20),
                        action: () => _showLanguagePicker(context, engine),
                      ),
                      CardContents.tap(
                        title: engine.tr('github_explorer'),
                        subtitle: engine.tr('github_explorer_sub'),
                        trailing: const Icon(Icons.open_in_new_rounded, size: 20),
                        action: () => M3xGitHub.openExplorer(
                          context,
                          owner: 'Puzzaks',
                          repo: 'fractals',
                        ),
                      ),
                      CardContents.tap(
                        title: engine.tr('reset_all'),
                        subtitle: engine.tr('reset_all_sub'),
                        trailing: const Icon(Icons.restore_rounded, size: 20),
                        action: engine.resetAllSettings,
                      ),
                    ],
                  ),
                  SettingsBentoHeader(
                    appName: M3x.appName.isNotEmpty
                        ? M3x.appName
                        : engine.tr('app_title'),
                    subtitle: M3x.appDescription.isNotEmpty
                        ? M3x.appDescription
                        : 'GPU Fractal Explorer',
                    icon: Icons.auto_awesome_rounded,
                    versionDisplay: M3x.versionDisplay.isNotEmpty
                        ? M3x.versionDisplay
                        : '0.2.2',
                    onHeaderTap: () => launchUrl(
                      Uri.parse('https://puzzak.page'),
                      mode: LaunchMode.externalApplication,
                    ),
                    onVersionTap: () =>
                        SettingsBentoHeader.showChangelogDialog(context),
                    onModulesTap: () =>
                        SettingsBentoHeader.showDependenciesDialog(context),
                  ),
                ],
              ),
            ),
        ],
      ),
    );

    if (!hasOwnHeaderDrag) {
      return body;
    }

    return InspectorSheetDragScope(
      onHeaderDragStart: effectiveDragStart,
      onHeaderDragUpdate: effectiveDragUpdate,
      onHeaderDragEnd: effectiveDragEnd,
      onHeaderDragCancel: effectiveDragCancel,
      child: body,
    );
  }
}

class _SubPageScaffold extends StatelessWidget {
  final String title;
  final bool isSheet;
  final VoidCallback? onClose;
  final List<Widget> children;

  const _SubPageScaffold({
    required this.title,
    required this.isSheet,
    required this.children,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final InspectorSheetDragScope? dragScope =
        InspectorSheetDragScope.maybeOf(context);
    final Widget headerContent = Column(
      children: <Widget>[
        if (isSheet) const _SheetHandle(),
        _PanelHeader(
          title: title,
          onBack: () => Navigator.of(context).pop(),
          onClose: onClose,
        ),
      ],
    );
    final bool hasHeaderDrag = dragScope != null && dragScope.hasCallbacks;

    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: <Widget>[
          if (hasHeaderDrag)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragStart: dragScope.onHeaderDragStart,
              onVerticalDragUpdate: dragScope.onHeaderDragUpdate,
              onVerticalDragEnd: dragScope.onHeaderDragEnd,
              onVerticalDragCancel: dragScope.onHeaderDragCancel,
              child: headerContent,
            )
          else
            headerContent,
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 10, bottom: 32),
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

class _FractalCameraPage extends StatelessWidget {
  final bool isSheet;
  final VoidCallback? onClose;

  const _FractalCameraPage({
    required this.isSheet,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final FractalEngine engine = context.watch<FractalEngine>();
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return _SubPageScaffold(
      title: engine.tr('section_fractal'),
      isSheet: isSheet,
      onClose: onClose,
      children: <Widget>[
        Category.settings(
          title: _trOr(engine, 'select_fractal', 'Select Fractal'),
          context: context,
        ),
        CardGroup(
          children: FractalType.values.map((FractalType type) {
            final bool isSelected = engine.fractalType == type;
            return CardContents.tapIcon(
              title: engine.tr(type.translationKey),
              subtitle: isSelected
                  ? _trOr(engine, 'selected_label', 'Active')
                  : '',
              icon: fractalTypeIcon(type),
              color: isSelected
                  ? scheme.onPrimaryContainer
                  : scheme.onSurfaceVariant,
              colorBG: isSelected
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerHighest,
              selected: isSelected,
              trailing: isSelected
                  ? Icon(Icons.check_circle_rounded, color: scheme.primary)
                  : null,
              action: () {
                HapticFeedback.lightImpact();
                engine.setFractalType(type, resetCamera: false);
              },
            );
          }).toList(),
        ),
        if (engine.fractalType == FractalType.julia) ...<Widget>[
          Category.settings(
            title: _trOr(engine, 'section_julia', 'Julia Seed (c)'),
            context: context,
          ),
          CardGroup(
            children: <Widget>[
              CardContents.slider(
                title: engine.tr('julia_real'),
                value: engine.juliaCx,
                min: -2.0,
                max: 2.0,
                trailing: Text(
                  engine.juliaCx.toStringAsFixed(4),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                  ),
                ),
                onChanged: (double v) => engine.setJuliaC(v, engine.juliaCy),
              ),
              CardContents.slider(
                title: engine.tr('julia_imag'),
                value: engine.juliaCy,
                min: -2.0,
                max: 2.0,
                trailing: Text(
                  engine.juliaCy.toStringAsFixed(4),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                  ),
                ),
                onChanged: (double v) => engine.setJuliaC(engine.juliaCx, v),
              ),
              CardContents.tapIcon(
                title: _trOr(engine, 'julia_reset', 'Reset Julia Parameters'),
                subtitle: _trOr(
                  engine,
                  'julia_reset_sub',
                  'Restore default Julia seed (-0.7269 + 0.1889i)',
                ),
                icon: Icons.restart_alt_rounded,
                color: scheme.onSecondaryContainer,
                colorBG: scheme.secondaryContainer,
                action: engine.resetJuliaC,
              ),
            ],
          ),
        ],
        Category.settings(
          title: _trOr(engine, 'section_camera', 'Camera & Position'),
          context: context,
        ),
        CardGroup(
          children: <Widget>[
            CardContents.slider(
              title: _trOr(engine, 'rotation_label', 'Rotation'),
              value: engine.rotationDegrees.clamp(-180.0, 180.0),
              min: -180.0,
              max: 180.0,
              divisions: 72,
              trailing: Text(
                '${engine.rotationDegrees.round()}°',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                ),
              ),
              onChanged: engine.setRotationDegrees,
            ),
            CardContents.turn(
              title: engine.tr('rotation_gesture'),
              subtitle: _trOr(
                engine,
                'rotation_gesture_sub',
                'Rotate viewport with two-finger twist gesture',
              ),
              value: engine.enableGestureRotation,
              action: () => engine
                  .setEnableGestureRotation(!engine.enableGestureRotation),
              switcher: engine.setEnableGestureRotation,
            ),
            CardContents.tapIcon(
              title: engine.tr('rotation_reset'),
              subtitle: _trOr(
                engine,
                'rotation_reset_sub',
                'Restore viewport rotation to 0°',
              ),
              icon: Icons.rotate_left_rounded,
              color: scheme.onSecondaryContainer,
              colorBG: scheme.secondaryContainer,
              action: engine.resetRotation,
            ),
            CardContents.tap(
              title: engine.tr('reset_view'),
              subtitle: engine.tr('reset_view_sub'),
              trailing: const Icon(Icons.center_focus_strong_rounded, size: 20),
              action: engine.resetView,
            ),
          ],
        ),
      ],
    );
  }
}

class _AppearancePalettesPage extends StatelessWidget {
  final bool isSheet;
  final VoidCallback? onClose;

  const _AppearancePalettesPage({
    required this.isSheet,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final FractalEngine engine = context.watch<FractalEngine>();
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return _SubPageScaffold(
      title: engine.tr('section_appearance'),
      isSheet: isSheet,
      onClose: onClose,
      children: <Widget>[
        Category.settings(
          title: engine.tr('palette_label'),
          context: context,
        ),
        CardGroup(
          children: FractalPalette.values.map((FractalPalette palette) {
            final bool selected = engine.palette == palette;
            final List<Color> swatch =
                fractalPalettePreviewColors(palette, scheme);
            return CardContents.tap(
              title: engine.tr(palette.translationKey),
              subtitle: selected ? _trOr(engine, 'selected_label', 'Active') : '',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (final Color color in swatch)
                    Container(
                      width: 12,
                      height: 12,
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color,
                        border: Border.all(
                          color: scheme.outline.withValues(alpha: 0.4),
                          width: 0.7,
                        ),
                      ),
                    ),
                  if (selected) ...<Widget>[
                    const SizedBox(width: 6),
                    Icon(Icons.check_rounded, size: 20, color: scheme.primary),
                  ],
                ],
              ),
              action: () {
                HapticFeedback.lightImpact();
                engine.setPalette(palette);
              },
            );
          }).toList(),
        ),
        Category.settings(
          title: _trOr(engine, 'section_color_options', 'Coloring & Blending'),
          context: context,
        ),
        CardGroup(
          children: <Widget>[
            CardContents.turn(
              title: engine.tr('smooth_coloring'),
              subtitle: engine.tr('smooth_coloring_sub'),
              value: engine.smoothColor,
              action: () => engine.setSmoothColor(!engine.smoothColor),
              switcher: engine.setSmoothColor,
            ),
            CardContents.slider(
              title: engine.tr('color_phase'),
              value: engine.colorOffset,
              min: 0.0,
              max: 1.0,
              trailing: Text(
                '${(engine.colorOffset * 100).round()}%',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                ),
              ),
              onChanged: engine.setColorOffset,
            ),
          ],
        ),
      ],
    );
  }
}

class _RenderingPerformancePage extends StatelessWidget {
  final bool isSheet;
  final VoidCallback? onClose;

  const _RenderingPerformancePage({
    required this.isSheet,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final FractalEngine engine = context.watch<FractalEngine>();
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final int effectiveMaxIterations = engine.effectiveMaxIterations;
    final double overscan = engine.overscanMultiplier;

    return _SubPageScaffold(
      title: engine.tr('section_rendering'),
      isSheet: isSheet,
      onClose: onClose,
      children: <Widget>[
        Category.settings(
          title: engine.tr('section_rendering'),
          context: context,
        ),
        CardGroup(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 14,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          engine.tr('quality_label'),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      Text(
                        engine.tr(engine.quality.translationKey),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: scheme.primary,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: engine.quality.index.toDouble(),
                    min: 0,
                    max: (RenderQuality.values.length - 1).toDouble(),
                    divisions: RenderQuality.values.length - 1,
                    label: _qualityTooltipLabel(engine, engine.quality),
                    onChanged: (double value) {
                      final RenderQuality next = RenderQuality.values[value
                          .round()
                          .clamp(0, RenderQuality.values.length - 1)];
                      if (next != engine.quality) {
                        HapticFeedback.lightImpact();
                        engine.setQuality(next);
                      }
                    },
                  ),
                ],
              ),
            ),
            if (kDebugMode)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      engine.tr('backend_label'),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      engine.tr('backend_sub'),
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 10),
                    LayoutBuilder(
                      builder:
                          (BuildContext boxCtx, BoxConstraints boxConstraints) {
                        return SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minWidth: boxConstraints.maxWidth,
                            ),
                            child: SegmentedButton<RenderBackend>(
                              showSelectedIcon: false,
                              style: const ButtonStyle(
                                visualDensity: VisualDensity.compact,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              segments: RenderBackend.values
                                  .map(
                                    (RenderBackend b) =>
                                        ButtonSegment<RenderBackend>(
                                      value: b,
                                      label: Text(
                                        engine.tr(b.translationKey),
                                        maxLines: 1,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              selected: <RenderBackend>{engine.backend},
                              onSelectionChanged:
                                  (Set<RenderBackend> selection) {
                                if (selection.isNotEmpty) {
                                  HapticFeedback.lightImpact();
                                  engine.setBackend(selection.first);
                                }
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            CardContents.turn(
              title: engine.tr('auto_lod'),
              subtitle: engine.tr('auto_lod_sub'),
              value: engine.autoAdaptiveLod,
              action: () => engine.setAutoAdaptiveLod(!engine.autoAdaptiveLod),
              switcher: engine.setAutoAdaptiveLod,
            ),
            if (!engine.autoAdaptiveLod)
              CardContents.slider(
                title: engine.tr('drag_preview_scale'),
                subtitle: engine.tr('drag_preview_scale_sub'),
                value: engine.dragPreviewScale.clamp(0.02, 1.00),
                min: 0.02,
                max: 1.00,
                divisions: 49,
                trailing: Text(
                  '${(engine.dragPreviewScale * 100).round()}%',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                  ),
                ),
                onChanged: engine.setDragPreviewScale,
              ),
            CardContents.slider(
              title: _trOr(
                engine,
                'overscan_multiplier',
                'Overscan Cushion',
              ),
              subtitle: _trOr(
                engine,
                'overscan_multiplier_sub',
                'Pre-renders edges while panning',
              ),
              value: overscan,
              min: 0.0,
              max: 5.0,
              divisions: 20,
              trailing: Text(
                overscan < 1.05
                    ? _trOr(engine, 'off_label', 'Off')
                    : '${overscan.toStringAsFixed(2)}×',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                ),
              ),
              onChanged: engine.setOverscanMultiplier,
            ),
          ],
        ),
        Category.settings(
          title: _trOr(engine, 'section_precision', 'Iterations & Precision'),
          context: context,
        ),
        CardGroup(
          children: <Widget>[
            CardContents.turn(
              title: engine.tr('auto_iterations'),
              subtitle: engine.tr('auto_iterations_sub'),
              value: engine.autoIterations,
              action: () => engine.setAutoIterations(!engine.autoIterations),
              switcher: engine.setAutoIterations,
            ),
            CardContents.slider(
              title: engine.tr('max_iterations'),
              subtitle: engine.autoIterations
                  ? '${engine.tr('backend_auto')}: $effectiveMaxIterations'
                  : null,
              value: (engine.autoIterations
                      ? effectiveMaxIterations
                      : engine.manualMaxIterations)
                  .toDouble()
                  .clamp(50.0, 2000.0),
              min: 50,
              max: 2000,
              divisions: 39,
              trailing: Text(
                '$effectiveMaxIterations',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                ),
              ),
              onChanged: (double value) {
                if (engine.autoIterations) {
                  engine.setAutoIterations(false);
                }
                engine.setManualMaxIterations(value.round());
              },
            ),
            CardContents.turn(
              title: engine.tr('show_telemetry'),
              subtitle: engine.tr('show_telemetry_sub'),
              value: engine.showTelemetry,
              action: () => engine.setShowTelemetry(!engine.showTelemetry),
              switcher: engine.setShowTelemetry,
            ),
          ],
        ),
      ],
    );
  }
}

class _BenchmarkSubPage extends StatefulWidget {
  final bool isSheet;
  final VoidCallback? onClose;

  const _BenchmarkSubPage({
    required this.isSheet,
    this.onClose,
  });

  @override
  State<_BenchmarkSubPage> createState() => _BenchmarkSubPageState();
}

class _BenchmarkSubPageState extends State<_BenchmarkSubPage> {
  bool _running = false;
  double _progress = 0.0;
  String _stage = '';
  String _detail = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<FractalEngine>().refreshPotatoGlobalRank();
    });
  }

  Future<void> _runBenchmark(FractalEngine engine) async {
    if (_running) return;
    setState(() {
      _running = true;
      _progress = 0.0;
      _stage = '';
      _detail = '';
    });
    try {
      final PotatoBenchmarkResult result = await PotatoBenchmarkRunner.run(
        onProgress: (
          double p,
          String stage, {
          String? detail,
          ui.Image? previewImage,
        }) {
          if (!mounted) {
            previewImage?.dispose();
            return;
          }
          engine.updateBenchmarkOverlay(
            active: true,
            stage: stage,
            detail: detail ?? '',
            previewImage: previewImage,
          );
          setState(() {
            _progress = p;
            _stage = stage;
            _detail = detail ?? '';
          });
        },
      );
      if (!mounted) return;
      engine.applyBenchmarkResult(result);
    } finally {
      engine.updateBenchmarkOverlay(active: false);
      if (mounted) {
        setState(() {
          _running = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final FractalEngine engine = context.watch<FractalEngine>();
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final PotatoBenchmarkResult? b = engine.lastBenchmark;
    final PotatoBenchmarkResult live = engine.liveAdaptiveRating;
    const TextStyle valueStyle = TextStyle(
      fontWeight: FontWeight.w600,
      fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
    );

    return _SubPageScaffold(
      title: engine.tr('benchmark_title'),
      isSheet: widget.isSheet,
      onClose: widget.onClose,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 4),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.speed_rounded,
                      size: 20,
                      color: scheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      engine.tr('benchmark_rating'),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: scheme.onPrimaryContainer,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  b?.tier ?? engine.tr('benchmark_ready'),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: scheme.onPrimaryContainer,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  b != null
                      ? '${b.score} pts'
                      : engine.tr('benchmark_subtitle'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: scheme.onPrimaryContainer.withValues(alpha: 0.85),
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Live adaptive: ${live.tier} · ${live.score} pts',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                ),
              ],
            ),
          ),
        ),
        Category.settings(
          title: _trOr(engine, 'section_actions', 'Actions'),
          context: context,
        ),
        CardGroup(
          children: <Widget>[
            if (_running)
              CardContents.progress(
                title: _stage.isEmpty ? engine.tr('benchmark_running') : _stage,
                subtitle:
                    '${(_progress * 100).round()}%${_detail.isNotEmpty ? ' · $_detail' : ''}',
                subsubtitle: '',
                progress: _progress.clamp(0.0, 1.0),
              ),
            CardContents.tapIcon(
              title: b == null
                  ? engine.tr('benchmark_run')
                  : engine.tr('benchmark_rerun'),
              subtitle: _running
                  ? engine.tr('benchmark_running')
                  : engine.tr('benchmark_subtitle'),
              icon: _running
                  ? Icons.hourglass_top_rounded
                  : Icons.play_arrow_rounded,
              color: scheme.onSecondaryContainer,
              colorBG: scheme.secondaryContainer,
              action: () => _runBenchmark(engine),
            ),
            if (b != null && !_running)
              CardContents.tap(
                title: engine.tr('benchmark_copy'),
                subtitle: b.toShareSummary(),
                trailing: const Icon(Icons.copy_rounded, size: 20),
                action: () {
                  Clipboard.setData(ClipboardData(text: b.toShareSummary()));
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      SnackBar(
                        content: Text(engine.tr('benchmark_copied')),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                },
              ),
          ],
        ),
        Category.settings(
          title: _trOr(engine, 'section_play_games', 'Play Games'),
          context: context,
        ),
        CardGroup(
          children: <Widget>[
            if (engine.playGamesSignedIn) ...<Widget>[
              CardContents.tap(
                title: _trOr(engine, 'play_games_global_rank', 'Global Rank'),
                subtitle: _trOr(
                  engine,
                  'play_games_potato_rank_sub',
                  'Potatoemeter leaderboard',
                ),
                trailing: Text(
                  engine.potatoGlobalRank?.displayRank ?? '--',
                  style: valueStyle,
                ),
                action: () => PlayGamesService.instance.showLeaderboard(
                  PlayGamesService.leaderboardPotatoemeter,
                ),
              ),
              CardContents.tapIcon(
                title: _trOr(
                  engine,
                  'play_games_global_leaderboard',
                  'Global Leaderboard',
                ),
                subtitle: _trOr(
                  engine,
                  'play_games_global_leaderboard_sub',
                  'View Potatoemeter rankings',
                ),
                icon: Icons.leaderboard_rounded,
                color: scheme.onPrimaryContainer,
                colorBG: scheme.primaryContainer,
                trailing: const Icon(Icons.open_in_new_rounded, size: 20),
                action: () => PlayGamesService.instance.showLeaderboard(
                  PlayGamesService.leaderboardPotatoemeter,
                ),
              ),
            ] else
              CardContents.tap(
                title: _trOr(
                  engine,
                  'play_games_sign_in',
                  'Sign in to Play Games',
                ),
                subtitle: _trOr(
                  engine,
                  'play_games_sign_in_prompt',
                  'Sign in to view rank',
                ),
                trailing: const Icon(Icons.login_rounded, size: 20),
                action: () => _handlePlayGamesSignIn(context, engine),
              ),
          ],
        ),
        if (b != null) ...<Widget>[
          Category.settings(
            title: engine.tr('benchmark_throughput'),
            context: context,
          ),
          CardGroup(
            children: <Widget>[
              CardContents.tap(
                title: 'GPU float32',
                subtitle: '',
                trailing: Text(
                  '${b.gpuF32MIterPerSec.toStringAsFixed(1)} MIter/s',
                  style: valueStyle,
                ),
                action: () {},
              ),
              CardContents.tap(
                title: 'GPU df64',
                subtitle: '',
                trailing: Text(
                  '${b.gpuDf64MIterPerSec.toStringAsFixed(1)} MIter/s',
                  style: valueStyle,
                ),
                action: () {},
              ),
              CardContents.tap(
                title: 'CPU float64',
                subtitle: '',
                trailing: Text(
                  '${b.cpuF64MIterPerSec.toStringAsFixed(1)} MIter/s',
                  style: valueStyle,
                ),
                action: () {},
              ),
              CardContents.tap(
                title: 'Calibrated drag preview scale (GPU df64)',
                subtitle: '',
                trailing: Text(
                  '${(engine.predictOptimalScale(mode: ActiveRenderMode.gpuDf64) * 100).round()}%',
                  style: valueStyle,
                ),
                action: () {},
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _BookmarksSubPage extends StatelessWidget {
  final bool isSheet;
  final VoidCallback? onClose;

  const _BookmarksSubPage({
    required this.isSheet,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final FractalEngine engine = context.watch<FractalEngine>();
    return _SubPageScaffold(
      title: engine.tr('section_bookmarks'),
      isSheet: isSheet,
      onClose: onClose,
      children: <Widget>[
        Category.settings(
          title: engine.tr('section_bookmarks'),
          context: context,
        ),
        _BookmarkCardGroup(engine: engine),
      ],
    );
  }
}

class _KeybindsSubPage extends StatelessWidget {
  final bool isSheet;
  final VoidCallback? onClose;

  const _KeybindsSubPage({
    required this.isSheet,
    this.onClose,
  });

  String _actionLabel(FractalEngine engine, FractalKeyAction action) {
    switch (action) {
      case FractalKeyAction.panUp:
        return _trOr(engine, 'key_pan_up', 'Pan Up');
      case FractalKeyAction.panDown:
        return _trOr(engine, 'key_pan_down', 'Pan Down');
      case FractalKeyAction.panLeft:
        return _trOr(engine, 'key_pan_left', 'Pan Left');
      case FractalKeyAction.panRight:
        return _trOr(engine, 'key_pan_right', 'Pan Right');
      case FractalKeyAction.zoomIn:
        return _trOr(engine, 'key_zoom_in', 'Zoom In');
      case FractalKeyAction.zoomOut:
        return _trOr(engine, 'key_zoom_out', 'Zoom Out');
      case FractalKeyAction.rotateLeft:
        return _trOr(engine, 'key_rotate_left', 'Rotate Left');
      case FractalKeyAction.rotateRight:
        return _trOr(engine, 'key_rotate_right', 'Rotate Right');
      case FractalKeyAction.resetView:
        return engine.tr('reset_view');
      case FractalKeyAction.toggleHud:
        return _trOr(engine, 'key_toggle_hud', 'Toggle HUD');
      case FractalKeyAction.toggleInspector:
        return _trOr(engine, 'key_toggle_inspector', 'Toggle Controls');
    }
  }

  static bool _isModifierKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight ||
        key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight ||
        key == LogicalKeyboardKey.altLeft ||
        key == LogicalKeyboardKey.altRight ||
        key == LogicalKeyboardKey.metaLeft ||
        key == LogicalKeyboardKey.metaRight;
  }

  Future<void> _showRebindDialog(
    BuildContext context,
    FractalEngine engine,
    FractalKeyAction action,
    String actionTitle,
  ) async {
    final FocusNode listenerFocus = FocusNode();
    try {
      final LogicalKeyboardKey? picked = await showDialog<LogicalKeyboardKey>(
        context: context,
        builder: (BuildContext dialogContext) {
          final ColorScheme scheme = Theme.of(dialogContext).colorScheme;
          return KeyboardListener(
            focusNode: listenerFocus,
            autofocus: true,
            onKeyEvent: (KeyEvent event) {
              if (event is! KeyDownEvent) return;
              if (event.logicalKey == LogicalKeyboardKey.escape) {
                Navigator.of(dialogContext).pop();
                return;
              }
              if (_isModifierKey(event.logicalKey)) return;
              Navigator.of(dialogContext).pop(event.logicalKey);
            },
            child: AlertDialog(
              title: Text(actionTitle),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.keyboard_rounded,
                    size: 40,
                    color: scheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _trOr(engine, 'press_any_key', 'Press any key...'),
                    textAlign: TextAlign.center,
                    style: Theme.of(dialogContext).textTheme.bodyLarge,
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(engine.tr('cancel')),
                ),
              ],
            ),
          );
        },
      );
      if (picked != null) {
        engine.setKeybind(action, picked);
      }
    } finally {
      listenerFocus.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final FractalEngine engine = context.watch<FractalEngine>();
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return _SubPageScaffold(
      title: _trOr(engine, 'section_controls', 'Controls & Keybinds'),
      isSheet: isSheet,
      onClose: onClose,
      children: <Widget>[
        Category.settings(
          title: _trOr(engine, 'section_controls', 'Controls & Keybinds'),
          context: context,
        ),
        CardGroup(
          children: FractalKeyAction.values.map((FractalKeyAction action) {
            final String title = _actionLabel(engine, action);
            final String keyLabel = FractalEngine.formatKeyLabel(
              engine.keybindFor(action),
            );
            return CardContents.tap(
              title: title,
              subtitle: _trOr(engine, 'tap_to_rebind', 'Tap to rebind'),
              trailing: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.6),
                  ),
                ),
                child: Text(
                  keyLabel,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.onSecondaryContainer,
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                ),
              ),
              action: () => _showRebindDialog(context, engine, action, title),
            );
          }).toList(),
        ),
        Category.settings(
          title: _trOr(engine, 'reset_keybinds', 'Reset Default Keybinds'),
          context: context,
        ),
        CardGroup(
          children: <Widget>[
            CardContents.tap(
              title: _trOr(engine, 'reset_keybinds', 'Reset Default Keybinds'),
              subtitle: _trOr(
                engine,
                'reset_keybinds_sub',
                'Restore WASD, R, H, I, and +/- defaults',
              ),
              trailing: const Icon(Icons.restore_rounded, size: 20),
              action: engine.resetKeybinds,
            ),
          ],
        ),
      ],
    );
  }
}

enum _ExportResolutionPreset {
  deviceScreen(0, 'Device Screen'),
  fhd1080(1920, 'Full HD (1080p)'),
  qhd1440(2560, '2K (1440p)'),
  uhd4k(3840, '4K (2160p)'),
  uhd8k(7680, '8K (4320p)');

  final int longEdge;
  final String label;
  const _ExportResolutionPreset(this.longEdge, this.label);
}

enum _ExportRotationPreset {
  current,
  deg0,
  deg90,
  deg180,
  deg270;

  String label(FractalEngine engine) {
    switch (this) {
      case _ExportRotationPreset.current:
        final int deg =
            ((engine.rotation * 180 / math.pi).round() % 360 + 360) % 360;
        return '${_trOr(engine, 'export_rotation_current', 'Current')} ($deg°)';
      case _ExportRotationPreset.deg0:
        return '0°';
      case _ExportRotationPreset.deg90:
        return '90°';
      case _ExportRotationPreset.deg180:
        return '180°';
      case _ExportRotationPreset.deg270:
        return '270°';
    }
  }

  double? radians(double current) {
    switch (this) {
      case _ExportRotationPreset.current:
        return null;
      case _ExportRotationPreset.deg0:
        return 0.0;
      case _ExportRotationPreset.deg90:
        return math.pi / 2;
      case _ExportRotationPreset.deg180:
        return math.pi;
      case _ExportRotationPreset.deg270:
        return 3 * math.pi / 2;
    }
  }
}

enum _ExportAspectPreset {
  matchScreen(null),
  r16x9(16 / 9),
  r2x1(2 / 1),
  r21x9(21 / 9),
  r32x9(32 / 9),
  r4x3(4 / 3),
  r1x1(1.0),
  custom(null);

  final double? ratio;
  const _ExportAspectPreset(this.ratio);

  String label(FractalEngine engine) {
    switch (this) {
      case _ExportAspectPreset.matchScreen:
        return _trOr(engine, 'export_match_screen', 'Match Screen');
      case _ExportAspectPreset.r16x9:
        return '16:9';
      case _ExportAspectPreset.r2x1:
        return '2:1';
      case _ExportAspectPreset.r21x9:
        return '21:9';
      case _ExportAspectPreset.r32x9:
        return '32:9';
      case _ExportAspectPreset.r4x3:
        return '4:3';
      case _ExportAspectPreset.r1x1:
        return '1:1';
      case _ExportAspectPreset.custom:
        return _trOr(engine, 'export_custom_size', 'Custom Size');
    }
  }
}

enum _ExportOrientation { landscape, portrait }

class _ExportSubPage extends StatefulWidget {
  final Size viewport;
  final ValueListenable<Size>? viewportListenable;
  final bool isSheet;
  final VoidCallback? onClose;

  const _ExportSubPage({
    required this.viewport,
    this.viewportListenable,
    required this.isSheet,
    this.onClose,
  });

  @override
  State<_ExportSubPage> createState() => _ExportSubPageState();
}

class _ExportSubPageState extends State<_ExportSubPage> {
  ExportImageFormat _format = ExportImageFormat.png;
  _ExportResolutionPreset _res = _ExportResolutionPreset.qhd1440;
  _ExportAspectPreset _aspect = _ExportAspectPreset.matchScreen;
  late _ExportOrientation _orientation;
  _ExportRotationPreset _rotation = _ExportRotationPreset.current;
  int _customWidth = 3840;
  int _customHeight = 2160;

  @override
  void initState() {
    super.initState();
    final Size initialVp = widget.viewportListenable?.value ?? widget.viewport;
    final Size effectiveVp =
        initialVp.isEmpty ? const Size(1080, 1920) : initialVp;
    _orientation = effectiveVp.height > effectiveVp.width
        ? _ExportOrientation.portrait
        : _ExportOrientation.landscape;
  }

  (int, int) _resolvedDimensions(
    Size activeViewport,
    int deviceScreenW,
    int deviceScreenH,
  ) {
    if (_aspect == _ExportAspectPreset.custom) {
      return (_customWidth.clamp(128, 7680), _customHeight.clamp(128, 7680));
    }
    final Size effectiveViewport =
        activeViewport.isEmpty ? const Size(1080, 1920) : activeViewport;
    final int longEdge = (_res == _ExportResolutionPreset.deviceScreen
            ? math.max(deviceScreenW, deviceScreenH)
            : _res.longEdge)
        .clamp(128, 7680);
    if (_aspect == _ExportAspectPreset.r1x1) {
      return (longEdge, longEdge);
    }
    final double rawRatio = _aspect == _ExportAspectPreset.matchScreen
        ? math.max(effectiveViewport.width, effectiveViewport.height) /
            math.min(effectiveViewport.width, effectiveViewport.height)
        : (_aspect.ratio ?? (16 / 9));
    final double normalizedRatio = rawRatio >= 1.0 ? rawRatio : 1.0 / rawRatio;
    final double ratio = _orientation == _ExportOrientation.portrait
        ? 1.0 / normalizedRatio
        : normalizedRatio;
    if (ratio >= 1.0) {
      final int h = (longEdge / ratio).round().clamp(128, 7680);
      return (longEdge, h);
    } else {
      final int w = (longEdge * ratio).round().clamp(128, 7680);
      return (w, longEdge);
    }
  }

  Future<void> _showCustomSizeDialog(
    BuildContext context,
    FractalEngine engine,
  ) async {
    final TextEditingController widthCtrl =
        TextEditingController(text: '$_customWidth');
    final TextEditingController heightCtrl =
        TextEditingController(text: '$_customHeight');
    try {
      final (int, int)? result = await showDialog<(int, int)>(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: Text(_trOr(engine, 'export_custom_size', 'Custom Size')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: widthCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Width (px, 128–7680)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(16)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: heightCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Height (px, 128–7680)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(16)),
                    ),
                  ),
                ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(engine.tr('cancel')),
              ),
              FilledButton(
                onPressed: () {
                  final int w =
                      (int.tryParse(widthCtrl.text) ?? _customWidth)
                          .clamp(128, 7680);
                  final int h =
                      (int.tryParse(heightCtrl.text) ?? _customHeight)
                          .clamp(128, 7680);
                  Navigator.of(dialogContext).pop((w, h));
                },
                child: Text(engine.tr('save')),
              ),
            ],
          );
        },
      );
      if (result != null && mounted) {
        setState(() {
          _customWidth = result.$1;
          _customHeight = result.$2;
        });
      }
    } finally {
      widthCtrl.dispose();
      heightCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final FractalEngine engine = context.watch<FractalEngine>();
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String formatLabel =
        _format == ExportImageFormat.png ? 'PNG' : 'JPEG';

    Widget buildBody(Size activeViewport) {
      final Size effectiveViewport =
          activeViewport.isEmpty ? const Size(1080, 1920) : activeViewport;
      final double dpr = MediaQuery.devicePixelRatioOf(context);
      final int deviceScreenW =
          (effectiveViewport.width * dpr).round().clamp(128, 7680);
      final int deviceScreenH =
          (effectiveViewport.height * dpr).round().clamp(128, 7680);
      final (int exportW, int exportH) = _resolvedDimensions(
        effectiveViewport,
        deviceScreenW,
        deviceScreenH,
      );
      final String mpLabel =
          ((exportW * exportH) / 1e6).toStringAsFixed(1);
      final bool showResolution = _aspect != _ExportAspectPreset.custom;
      final bool showOrientation =
          _aspect != _ExportAspectPreset.r1x1 &&
          _aspect != _ExportAspectPreset.custom;

      return _SubPageScaffold(
        title: engine.tr('section_export'),
        isSheet: widget.isSheet,
        onClose: widget.onClose,
        children: <Widget>[
          Category.settings(
            title: engine.tr('section_export'),
            context: context,
          ),
          CardGroup(
            children: <Widget>[
              CardContents.tap(
                title: _trOr(engine, 'export_format', 'Format'),
                subtitle: formatLabel,
                trailing: const Icon(Icons.chevron_right_rounded),
                action: () => OptionPickerDialog.show<ExportImageFormat>(
                  context: context,
                  title: _trOr(engine, 'export_format', 'Format'),
                  options: <OptionPickerItem<ExportImageFormat>>[
                    OptionPickerItem<ExportImageFormat>(
                      value: ExportImageFormat.png,
                      title: 'PNG',
                      subtitle: _trOr(engine, 'export_format_png_sub', 'Lossless'),
                    ),
                    OptionPickerItem<ExportImageFormat>(
                      value: ExportImageFormat.jpeg,
                      title: 'JPEG',
                      subtitle: _trOr(engine, 'export_format_jpg_sub', 'Smaller file'),
                    ),
                  ],
                  currentValue: _format,
                  onSelected: (ExportImageFormat value) {
                    setState(() => _format = value);
                  },
                ),
              ),
              if (showResolution)
                CardContents.tap(
                  title: _trOr(engine, 'export_resolution', 'Resolution'),
                  subtitle: _res.label,
                  trailing: const Icon(Icons.chevron_right_rounded),
                  action: () =>
                      OptionPickerDialog.show<_ExportResolutionPreset>(
                    context: context,
                    title: _trOr(engine, 'export_resolution', 'Resolution'),
                    options: <OptionPickerItem<_ExportResolutionPreset>>[
                      for (final _ExportResolutionPreset p
                          in _ExportResolutionPreset.values)
                        OptionPickerItem<_ExportResolutionPreset>(
                          value: p,
                          title: p.label,
                        ),
                    ],
                    currentValue: _res,
                    onSelected: (_ExportResolutionPreset value) {
                      setState(() => _res = value);
                    },
                  ),
                ),
              CardContents.tap(
                title: _trOr(engine, 'export_aspect', 'Aspect Ratio'),
                subtitle: _aspect.label(engine),
                trailing: const Icon(Icons.chevron_right_rounded),
                action: () => OptionPickerDialog.show<_ExportAspectPreset>(
                  context: context,
                  title: _trOr(engine, 'export_aspect', 'Aspect Ratio'),
                  options: <OptionPickerItem<_ExportAspectPreset>>[
                    for (final _ExportAspectPreset a
                        in _ExportAspectPreset.values)
                      OptionPickerItem<_ExportAspectPreset>(
                        value: a,
                        title: a.label(engine),
                      ),
                  ],
                  currentValue: _aspect,
                  onSelected: (_ExportAspectPreset value) {
                    setState(() => _aspect = value);
                  },
                ),
              ),
              if (showOrientation)
                CardContents.tap(
                  title: _trOr(engine, 'export_orientation', 'Orientation'),
                  subtitle: _orientation == _ExportOrientation.landscape
                      ? _trOr(engine, 'export_landscape', 'Landscape')
                      : _trOr(engine, 'export_portrait', 'Portrait'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  action: () => OptionPickerDialog.show<_ExportOrientation>(
                    context: context,
                    title: _trOr(engine, 'export_orientation', 'Orientation'),
                    options: <OptionPickerItem<_ExportOrientation>>[
                      OptionPickerItem<_ExportOrientation>(
                        value: _ExportOrientation.landscape,
                        title: _trOr(engine, 'export_landscape', 'Landscape'),
                      ),
                      OptionPickerItem<_ExportOrientation>(
                        value: _ExportOrientation.portrait,
                        title: _trOr(engine, 'export_portrait', 'Portrait'),
                      ),
                    ],
                    currentValue: _orientation,
                    onSelected: (_ExportOrientation value) {
                      setState(() => _orientation = value);
                    },
                  ),
                ),
              CardContents.tap(
                title: _trOr(engine, 'export_rotation', 'Export Rotation'),
                subtitle: _rotation.label(engine),
                trailing: const Icon(Icons.chevron_right_rounded),
                action: () => OptionPickerDialog.show<_ExportRotationPreset>(
                  context: context,
                  title: _trOr(engine, 'export_rotation', 'Export Rotation'),
                  options: <OptionPickerItem<_ExportRotationPreset>>[
                    for (final _ExportRotationPreset r
                        in _ExportRotationPreset.values)
                      OptionPickerItem<_ExportRotationPreset>(
                        value: r,
                        title: r.label(engine),
                      ),
                  ],
                  currentValue: _rotation,
                  onSelected: (_ExportRotationPreset value) {
                    setState(() => _rotation = value);
                  },
                ),
              ),
              if (_aspect == _ExportAspectPreset.custom)
                CardContents.tap(
                  title: _trOr(engine, 'export_custom_size', 'Custom Size'),
                  subtitle: '$exportW × $exportH',
                  trailing: const Icon(Icons.edit_rounded, size: 20),
                  action: () => _showCustomSizeDialog(context, engine),
                ),
            ],
          ),
          Category.settings(
            title: _trOr(engine, 'section_actions', 'Actions'),
            context: context,
          ),
          CardGroup(
            children: <Widget>[
              if (engine.isExporting) ...<Widget>[
                CardContents.progress(
                  title: engine.tr('exporting'),
                  subtitle: engine.exportProgress != null
                      ? '${(engine.exportProgress! * 100).round()}%'
                      : '',
                  subsubtitle: '',
                  progress: engine.exportProgress ?? -1,
                ),
                CardContents.tapIcon(
                  title: _trOr(engine, 'export_cancel', 'Cancel Rendering'),
                  subtitle: '$exportW × $exportH',
                  icon: Icons.stop_circle_rounded,
                  color: scheme.onErrorContainer,
                  colorBG: scheme.errorContainer,
                  action: engine.cancelActiveExport,
                ),
              ] else
                CardContents.tapIcon(
                  title: _trOr(engine, 'export_start', 'Export & Share Image'),
                  subtitle: '$exportW × $exportH · $mpLabel MP · $formatLabel',
                  icon: Icons.ios_share_rounded,
                  color: scheme.onPrimaryContainer,
                  colorBG: scheme.primaryContainer,
                  action: () => exportFractalImage(
                    context,
                    engine,
                    activeViewport,
                    width: exportW,
                    height: exportH,
                    format: _format,
                    rotationOverrideRadians:
                        _rotation.radians(engine.rotation),
                  ),
                ),
            ],
          ),
        ],
      );
    }

    if (widget.viewportListenable != null) {
      return ValueListenableBuilder<Size>(
        valueListenable: widget.viewportListenable!,
        builder: (BuildContext _, Size liveSize, Widget? __) {
          return buildBody(liveSize.isEmpty ? widget.viewport : liveSize);
        },
      );
    }
    return buildBody(widget.viewport);
  }
}

class _LiveTelemetrySection extends StatelessWidget {
  const _LiveTelemetrySection();

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Consumer<FractalEngine>(
      builder: (BuildContext context, FractalEngine engine, Widget? child) {
        final String coordSubtitle =
            '${FractalEngine.formatCoord(engine.centerX, engine.zoom)}, '
            '${FractalEngine.formatCoord(engine.centerY, engine.zoom)}';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Category.settings(
              title: engine.tr('section_telemetry'),
              context: context,
            ),
            TelemetrySparklineCard(
              title: engine.tr('telemetry_fps'),
              valueText: FractalEngine.formatFps(engine.currentFps),
              subValue:
                  '${FractalEngine.formatFrameTime(engine.lastFrameTimeMs)} · '
                  '${engine.activeRenderMode.badge} · '
                  '${engine.effectiveMaxIterations} it',
              secondaryLabelText: engine.tr('telemetry_zoom'),
              secondaryValueText: FractalEngine.formatZoom(engine.zoom),
              height: 164,
              graphColor: scheme.primary.withValues(alpha: 0.35),
              history: engine.fpsHistory
                  .map((double v) => (v * 0.36).clamp(0.0, 0.36))
                  .toList(),
              isOnline: !engine.isCpuRendering,
              margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 2),
              borderRadius: BorderRadius.circular(20),
            ),
            CardGroup(
              children: <Widget>[
                CardContents.tap(
                  title: engine.tr('telemetry_center'),
                  subtitle: coordSubtitle,
                  trailing: const Icon(Icons.copy_rounded, size: 20),
                  action: () => copyFractalCoordinates(context, engine),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _BookmarkCardGroup extends StatelessWidget {
  final FractalEngine engine;
  final VoidCallback? onApplied;

  const _BookmarkCardGroup({
    required this.engine,
    this.onApplied,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return CardGroup(
      children: <Widget>[
        CardContents.tapIcon(
          title: engine.tr('save_bookmark'),
          subtitle:
              '${engine.tr(engine.fractalType.translationKey)} · '
              '${FractalEngine.formatZoom(engine.zoom)}',
          icon: Icons.bookmark_add_rounded,
          color: scheme.onPrimaryContainer,
          colorBG: scheme.primaryContainer,
          action: () => _showAddBookmarkDialog(context, engine),
        ),
        for (final FractalBookmark bookmark in engine.customBookmarks)
          CardContents.tap(
            title: bookmark.name,
            subtitle:
                '${engine.tr(bookmark.fractalType.translationKey)} · '
                '${FractalEngine.formatZoom(bookmark.zoom)}',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                IconButton(
                  icon: const Icon(Icons.edit_rounded, size: 20),
                  tooltip: _trOr(engine, 'rename_bookmark', 'Rename'),
                  onPressed: () =>
                      _showRenameBookmarkDialog(context, engine, bookmark),
                ),
                IconButton(
                  icon: const Icon(Icons.share_rounded, size: 20),
                  tooltip: _trOr(engine, 'share_title', 'Share'),
                  onPressed: () =>
                      showShareFractalSheet(context, engine, bookmark: bookmark),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  tooltip: engine.tr('delete'),
                  onPressed: () => engine.removeCustomBookmark(bookmark.id),
                ),
              ],
            ),
            action: () {
              engine.applyBookmark(bookmark);
              onApplied?.call();
            },
          ),
        for (final FractalBookmark bookmark in builtInBookmarks)
          CardContents.tap(
            title: bookmark.name,
            subtitle:
                '${engine.tr(bookmark.fractalType.translationKey)} · '
                '${FractalEngine.formatZoom(bookmark.zoom)}',
            trailing: IconButton(
              icon: const Icon(Icons.share_rounded, size: 20),
              tooltip: _trOr(engine, 'share_title', 'Share'),
              onPressed: () =>
                  showShareFractalSheet(context, engine, bookmark: bookmark),
            ),
            action: () {
              engine.applyBookmark(bookmark);
              onApplied?.call();
            },
          ),
      ],
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Center(
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: scheme.outlineVariant.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onBack;
  final VoidCallback? onClose;

  const _PanelHeader({
    required this.title,
    this.onBack,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(onBack != null ? 8 : 20, 10, 10, 10),
      child: Row(
        children: <Widget>[
          if (onBack != null) ...<Widget>[
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: onBack,
            ),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onClose != null)
            IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: onClose,
            ),
        ],
      ),
    );
  }
}
