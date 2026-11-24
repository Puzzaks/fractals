import 'dart:async' show Timer;
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

import '../engine/big_float.dart';
import '../engine/cpu_renderer.dart';
import '../engine/fractal_engine.dart';
import '../engine/fractal_models.dart';
import '../engine/perturbation_solver.dart';
import '../engine/play_games_service.dart';
import '../engine/potato_benchmark.dart';
import 'app_toast.dart';
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
  showAppToast(context, exportingMsg, long: true);

  const MethodChannel displayChannel =
      MethodChannel('page.puzzak.fractals/display');
  try {
    await displayChannel.invokeMethod<void>('requestNotificationPermission');
  } catch (_) {}
  try {
    await displayChannel.invokeMethod<void>(
      'startExportNotification',
      <String, dynamic>{
        'title': exportingMsg,
        'detail': '$exportW × $exportH',
      },
    );
  } catch (_) {}

  int lastNotifiedPct = -1;

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
        final int pct = (p * 100).round();
        if (pct - lastNotifiedPct >= 5 || pct >= 100) {
          lastNotifiedPct = pct;
          displayChannel.invokeMethod<void>(
            'updateExportNotification',
            <String, dynamic>{
              'progress': p,
              'title': exportingMsg,
              'detail': '$exportW × $exportH · $pct%',
            },
          ).catchError((Object _) {});
        }
        if (engine.isBenchmarking) {
          engine.updateBenchmarkOverlay(
            active: true,
            stage: exportingMsg,
            detail: '$exportW × $exportH · $pct%',
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
      if (context.mounted) {
        showAppToast(context, failedMsg);
      }
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
    if (context.mounted) {
      showAppToast(
        context,
        _trOr(engine, 'export_cancelled', 'Export cancelled'),
      );
    }
  } catch (e) {
    engine.analytics.log('Export', 'Error', '$e');
    if (context.mounted) {
      showAppToast(context, failedMsg);
    }
  } finally {
    try {
      await displayChannel.invokeMethod<void>('stopExportNotification');
    } catch (_) {}
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
Future<bool> _handlePlayGamesSignIn(
  BuildContext context,
  FractalEngine engine,
) async {
  final bool ok = await engine.signInPlayGames();
  if (!ok && context.mounted) {
    showAppToast(context, 'Play Games sign-in was cancelled or unavailable');
  }
  return ok;
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
  final String? deleteLabel;
  final VoidCallback? onDelete;

  const _BookmarkNameDialog({
    required this.title,
    required this.hintText,
    required this.cancelLabel,
    required this.saveLabel,
    required this.initialName,
    this.deleteLabel,
    this.onDelete,
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
        if (widget.onDelete != null)
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              widget.onDelete!();
            },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(widget.deleteLabel ?? 'Delete'),
          ),
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

/// Opens a dialog to save the current fractal view as a custom bookmark.
Future<void> showAddBookmarkDialog(
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
      deleteLabel: engine.tr('delete'),
      onDelete: () => engine.removeCustomBookmark(bookmark.id),
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
        engine.defaultBookmarks.length + engine.customBookmarks.length;
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

    final Widget body = _InspectorHeaderScrollScaffold(
      isSheet: isSheet,
      enableScrollBlur: engine.enableScrollBlur,
      headerContent: headerContent,
      hasHeaderDrag: hasHeaderDrag,
      onHeaderDragStart: effectiveDragStart,
      onHeaderDragUpdate: effectiveDragUpdate,
      onHeaderDragEnd: effectiveDragEnd,
      onHeaderDragCancel: effectiveDragCancel,
      scrollController: scrollController,
      listTopPadding: 16,
      listBottomPadding: 16,
      children: <Widget>[
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
                        color: scheme.onPrimaryFixed,
                        colorBG: scheme.primaryFixedDim,
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
                        color: scheme.onPrimaryFixed,
                        colorBG: scheme.primaryFixedDim,
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
                        color: scheme.onPrimaryFixed,
                        colorBG: scheme.primaryFixedDim,
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
                        colorBG: scheme.primaryFixedDim,
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
                        color: scheme.onPrimaryFixed,
                        colorBG: scheme.primaryFixedDim,
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
                        color: scheme.onPrimaryFixed,
                        colorBG: scheme.primaryFixedDim,
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
                        color: scheme.onPrimaryFixed,
                        colorBG: scheme.primaryFixedDim,
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
                      CardContents.tapIcon(
                        title: engine.tr('section_play_games'),
                        subtitle: engine.playGamesSignedIn
                            ? (engine.playGamesPlayerName != null &&
                            engine.playGamesPlayerName!.isNotEmpty
                            ? engine
                            .tr('play_games_signed_in_as')
                            .replaceAll(
                          '{name}',
                          engine.playGamesPlayerName!,
                        )
                            : engine.tr('play_games_connected'))
                            : engine.tr('play_games_sign_in_sub'),
                        icon: Icons.sports_esports_rounded,
                        color: scheme.onPrimaryFixed,
                        colorBG: scheme.primaryFixedDim,
                        trailing: const Icon(Icons.chevron_right_rounded),
                        action: () async {
                          if (engine.playGamesSignedIn) {
                            _pushSubPage(
                              context,
                              _PlayGamesSubPage(
                                isSheet: isSheet,
                                onClose: onClose,
                              ),
                            );
                            return;
                          }
                          final bool ok =
                          await _handlePlayGamesSignIn(context, engine);
                          if (ok && context.mounted) {
                            _pushSubPage(
                              context,
                              _PlayGamesSubPage(
                                isSheet: isSheet,
                                onClose: onClose,
                              ),
                            );
                          }
                        },
                      )
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
                      CardContents.turn(
                        title: _trOr(
                          engine,
                          'enable_scroll_blur',
                          'Blur on Scroll',
                        ),
                        subtitle: _trOr(
                          engine,
                          'enable_scroll_blur_sub',
                          'Blur headers behind scrolled content',
                        ),
                        value: engine.enableScrollBlur,
                        action: () =>
                            engine.setEnableScrollBlur(!engine.enableScrollBlur),
                        switcher: engine.setEnableScrollBlur,
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
                      GestureDetector(
                        onLongPress: engine.resetAllSettings,
                        child: CardContents.tap(
                          title: engine.tr('reset_all'),
                          subtitle: engine.tr('reset_all_sub'),
                          trailing: const Icon(Icons.restore_rounded, size: 20),
                          action: () => showAppToast(
                            context,
                            _trOr(
                              engine,
                              'hold_to_reset_settings_hint',
                              'Hold to reset all settings',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
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

class _InspectorHeaderScrollScaffold extends StatefulWidget {
  final bool isSheet;
  final bool enableScrollBlur;
  final Widget headerContent;
  final bool hasHeaderDrag;
  final GestureDragStartCallback? onHeaderDragStart;
  final GestureDragUpdateCallback? onHeaderDragUpdate;
  final GestureDragEndCallback? onHeaderDragEnd;
  final GestureDragCancelCallback? onHeaderDragCancel;
  final ScrollController? scrollController;
  final double listTopPadding;
  final double listBottomPadding;
  final List<Widget> children;

  const _InspectorHeaderScrollScaffold({
    required this.isSheet,
    required this.enableScrollBlur,
    required this.headerContent,
    required this.hasHeaderDrag,
    this.onHeaderDragStart,
    this.onHeaderDragUpdate,
    this.onHeaderDragEnd,
    this.onHeaderDragCancel,
    this.scrollController,
    required this.listTopPadding,
    required this.listBottomPadding,
    required this.children,
  });

  @override
  State<_InspectorHeaderScrollScaffold> createState() =>
      _InspectorHeaderScrollScaffoldState();
}

class _InspectorHeaderScrollScaffoldState
    extends State<_InspectorHeaderScrollScaffold>
    with SingleTickerProviderStateMixin {
  static const double _maxMotionBlurSigma = 2.6;
  static const double _minActiveBlurSigma = 0.05;

  late final AnimationController _decayController;
  Timer? _idleTimer;
  int _lastUpdateMicros = 0;
  double _decayStartSigma = 0.0;
  double _motionBlurSigma = 0.0;

  @override
  void initState() {
    super.initState();
    _decayController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(_onDecayTick);
  }

  @override
  void didUpdateWidget(covariant _InspectorHeaderScrollScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enableScrollBlur && _motionBlurSigma != 0.0) {
      _idleTimer?.cancel();
      _decayController.stop();
      _motionBlurSigma = 0.0;
    }
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _decayController.dispose();
    super.dispose();
  }

  void _onDecayTick() {
    final double t = Curves.easeOutCubic.transform(_decayController.value);
    final double next = _decayStartSigma * (1.0 - t);
    final double clamped = next < _minActiveBlurSigma ? 0.0 : next;
    if (clamped != _motionBlurSigma && mounted) {
      setState(() => _motionBlurSigma = clamped);
    }
  }

  void _startDecay() {
    _idleTimer?.cancel();
    if (!mounted) return;
    if (_motionBlurSigma <= _minActiveBlurSigma) {
      if (_motionBlurSigma != 0.0) {
        setState(() => _motionBlurSigma = 0.0);
      }
      return;
    }
    _decayStartSigma = _motionBlurSigma;
    _decayController.forward(from: 0.0);
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (!widget.enableScrollBlur ||
        notification.metrics.axis != Axis.vertical) {
      return false;
    }

    if (notification is ScrollUpdateNotification) {
      final int nowMicros = DateTime.now().microsecondsSinceEpoch;
      final double dt = _lastUpdateMicros == 0
          ? 0.016
          : ((nowMicros - _lastUpdateMicros) / 1e6).clamp(0.008, 0.1);
      _lastUpdateMicros = nowMicros;

      final double delta = (notification.scrollDelta ?? 0.0).abs();
      final double velocityPxPerSec = delta / dt;
      final double target = velocityPxPerSec <= 450.0
          ? 0.0
          : ((velocityPxPerSec - 450.0) / 1800.0).clamp(0.0, 1.0) *
              _maxMotionBlurSigma;

      _idleTimer?.cancel();
      _idleTimer = Timer(const Duration(milliseconds: 64), _startDecay);

      if (target > _motionBlurSigma) {
        _decayController.stop();
        final double next = target < _minActiveBlurSigma ? 0.0 : target;
        if ((next - _motionBlurSigma).abs() > 0.02) {
          setState(() => _motionBlurSigma = next);
        }
      }
    } else if (notification is ScrollEndNotification) {
      _lastUpdateMicros = 0;
      _startDecay();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Widget draggableHeader = widget.hasHeaderDrag
        ? GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: widget.onHeaderDragStart,
            onVerticalDragUpdate: widget.onHeaderDragUpdate,
            onVerticalDragEnd: widget.onHeaderDragEnd,
            onVerticalDragCancel: widget.onHeaderDragCancel,
            child: widget.headerContent,
          )
        : widget.headerContent;

    if (!widget.enableScrollBlur) {
      return Material(
        color: scheme.surface,
        child: Column(
          children: <Widget>[
            draggableHeader,
            const Divider(height: 1),
            Expanded(
              child: ListView(
                controller: widget.scrollController,
                padding: EdgeInsets.only(
                  top: widget.listTopPadding,
                  bottom: widget.listBottomPadding,
                ),
                children: widget.children,
              ),
            ),
          ],
        ),
      );
    }

    // Matches _SheetHandle (18) + _PanelHeader (68) + Divider (1).
    final double headerHeight = (widget.isSheet ? 18.0 : 0.0) + 68.0 + 1.0;

    Widget listView = ImageFiltered(
      enabled: _motionBlurSigma > _minActiveBlurSigma,
      imageFilter: ui.ImageFilter.blur(
        sigmaX: 0.0,
        sigmaY: _motionBlurSigma,
      ),
      child: ListView(
        controller: widget.scrollController,
        padding: EdgeInsets.only(
          top: headerHeight + widget.listTopPadding,
          bottom: widget.listBottomPadding,
        ),
        children: widget.children,
      ),
    );

    return Material(
      color: scheme.surface,
      child: Stack(
        children: <Widget>[
          NotificationListener<ScrollNotification>(
            onNotification: _handleScrollNotification,
            child: listView,
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipRect(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  color: scheme.surface.withValues(alpha: 0.55),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      draggableHeader,
                      const Divider(height: 1),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
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
    final bool enableScrollBlur =
        context.select<FractalEngine, bool>((FractalEngine e) => e.enableScrollBlur);
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

    return _InspectorHeaderScrollScaffold(
      isSheet: isSheet,
      enableScrollBlur: enableScrollBlur,
      headerContent: headerContent,
      hasHeaderDrag: hasHeaderDrag,
      onHeaderDragStart: dragScope?.onHeaderDragStart,
      onHeaderDragUpdate: dragScope?.onHeaderDragUpdate,
      onHeaderDragEnd: dragScope?.onHeaderDragEnd,
      onHeaderDragCancel: dragScope?.onHeaderDragCancel,
      listTopPadding: 10,
      listBottomPadding: 32,
      children: children,
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
    final double overscan = engine.overscanMultiplier;

    return _SubPageScaffold(
      title: engine.tr('section_rendering'),
      isSheet: isSheet,
      onClose: onClose,
      children: <Widget>[
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
            if (!engine.autoIterations)
              CardContents.slider(
                title: engine.tr('max_iterations'),
                value: engine.manualMaxIterations
                    .toDouble()
                    .clamp(50.0, 4000.0),
                min: 50,
                max: 4000,
                divisions: 79,
                trailing: Text(
                  '${engine.manualMaxIterations}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                  ),
                ),
                onChanged: (double value) {
                  engine.setManualMaxIterations(value.round());
                },
              ),
          ],
        ),
        TextPart.infoShort(
          title: _trOr(
            engine,
            'rendering_explainer',
            'Higher render quality sharpens detail, while lower drag resolution and overscan cushion keep panning smooth. Auto backend switches from GPU to high-precision CPU on deep zooms.',
          ),
          subtitle: '',
          action: () {},
          context: context,
        ),
      ],
    );
  }
}

class _PlayGamesSubPage extends StatefulWidget {
  final bool isSheet;
  final VoidCallback? onClose;

  const _PlayGamesSubPage({
    required this.isSheet,
    this.onClose,
  });

  @override
  State<_PlayGamesSubPage> createState() => _PlayGamesSubPageState();
}

class _PlayGamesSubPageState extends State<_PlayGamesSubPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<FractalEngine>().refreshAllPlayGamesRanks();
    });
  }

  @override
  Widget build(BuildContext context) {
    final FractalEngine engine = context.watch<FractalEngine>();
    final summary = engine.achievementsSummary;

    return _SubPageScaffold(
      title: engine.tr('section_play_games'),
      isSheet: widget.isSheet,
      onClose: widget.onClose,
      children: <Widget>[
        CardGroup(
          children: <Widget>[
            CardContents.tap(
              title: _trOr(
                engine,
                'play_games_deepest_zoom',
                'Deepest Zoom',
              ),
              subtitle:
                  '${FractalEngine.formatZoom(engine.deepestZoom)} · ${engine.deepestZoomRank?.displayRank ?? _trOr(engine, 'play_games_unranked', 'Unranked')}',
              trailing: const Icon(Icons.zoom_in_rounded, size: 20),
              action: () => PlayGamesService.instance.showLeaderboard(
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
              trailing: const Icon(Icons.timer_rounded, size: 20),
              action: () => PlayGamesService.instance.showLeaderboard(
                PlayGamesService.leaderboardTotalTime,
              ),
            ),
            CardContents.tap(
              title: engine.tr('benchmark_title'),
              subtitle:
                  '${engine.lastBenchmark?.score ?? engine.potatoGlobalRank?.rawScore ?? "--"} · ${engine.potatoGlobalRank?.displayRank ?? _trOr(engine, 'play_games_unranked', 'Unranked')}',
              trailing: const Icon(Icons.speed_rounded, size: 20),
              action: () => PlayGamesService.instance.showLeaderboard(
                PlayGamesService.leaderboardPotatoemeter,
              ),
            ),
            CardContents.tap(
              title: _trOr(
                engine,
                'play_games_achievements',
                'Achievements',
              ),
              subtitle: summary != null
                  ? _trOr(
                      engine,
                      'play_games_achievements_progress',
                      '{unlocked} / {total} unlocked',
                    )
                      .replaceAll('{unlocked}', '${summary.unlocked}')
                      .replaceAll('{total}', '${summary.total}')
                  : engine.tr('play_games_achievements_sub'),
              trailing: const Icon(Icons.emoji_events_rounded, size: 20),
              action: () => PlayGamesService.instance.showAchievements(),
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

    return _SubPageScaffold(
      title: engine.tr('benchmark_title'),
      isSheet: widget.isSheet,
      onClose: widget.onClose,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 4),
          child: Material(
            color: scheme.primaryContainer.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(24),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: engine.playGamesSignedIn
                  ? () => PlayGamesService.instance.showLeaderboard(
                        PlayGamesService.leaderboardPotatoemeter,
                      )
                  : null,
              child: Padding(
                padding: const EdgeInsets.all(20),
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
                          style:
                              Theme.of(context).textTheme.labelMedium?.copyWith(
                                    color: scheme.onPrimaryContainer,
                                  ),
                        ),
                        if (engine.playGamesSignedIn) ...<Widget>[
                          const Spacer(),
                          if (engine.potatoGlobalRank != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.onPrimaryContainer
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Icon(
                                    Icons.leaderboard_rounded,
                                    size: 14,
                                    color: scheme.onPrimaryContainer,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    engine.potatoGlobalRank!.displayRank,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(
                                          color: scheme.onPrimaryContainer,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ],
                              ),
                            )
                          else
                            Icon(
                              Icons.leaderboard_rounded,
                              size: 18,
                              color: scheme.onPrimaryContainer
                                  .withValues(alpha: 0.7),
                            ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      b?.tier ?? engine.tr('benchmark_ready'),
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
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
          ],
        ),
        TextPart.infoShort(
          title: _trOr(
            engine,
            'potato_explainer',
            'Potatoemeter measures your device’s GPU and CPU fractal rendering speed to assign a hardware tier and calibrate smooth drag resolution.',
          ),
          subtitle: '',
          action: () {},
          context: context,
        ),
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

enum _ExportMode { image, video }

enum _VideoResolutionPreset {
  hd720('720p', 1280, 720),
  fhd1080('1080p', 1920, 1080),
  uhd4k('4K', 3840, 2160);

  final String label;
  final int longEdge;
  final int shortEdge;
  const _VideoResolutionPreset(this.label, this.longEdge, this.shortEdge);
}

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
  _ExportMode _mode = _ExportMode.image;
  ExportImageFormat _format = ExportImageFormat.png;
  _ExportResolutionPreset _res = _ExportResolutionPreset.qhd1440;
  _ExportAspectPreset _aspect = _ExportAspectPreset.matchScreen;
  late _ExportOrientation _orientation;
  _ExportRotationPreset _rotation = _ExportRotationPreset.current;
  int _customWidth = 3840;
  int _customHeight = 2160;
  int _videoDurationSec = 5;
  int _videoFps = 24;
  _VideoResolutionPreset _videoRes = _VideoResolutionPreset.hd720;

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

  (int, int) _resolvedVideoDimensions() {
    final int w = _orientation == _ExportOrientation.landscape
        ? _videoRes.longEdge
        : _videoRes.shortEdge;
    final int h = _orientation == _ExportOrientation.landscape
        ? _videoRes.shortEdge
        : _videoRes.longEdge;
    return ((w ~/ 2) * 2, (h ~/ 2) * 2);
  }

  static int _maxIterationsForZoom(FractalEngine engine, double zoom) {
    if (!engine.autoIterations) {
      return (engine.manualMaxIterations * engine.quality.iterationMultiplier)
          .round()
          .clamp(50, 16384);
    }
    final double ratio = math.max(1.0, zoom / 200.0);
    final double logZoom = math.log(ratio) / math.ln10;
    final int base = (120.0 + 75.0 * logZoom).round();
    return (base * engine.quality.iterationMultiplier).round().clamp(80, 16384);
  }

  static void _applyExportPerturbationUniforms({
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
    final double scaleRatio =
        viewportWidth > 0.0 ? viewportWidth / uSize.width : 1.0;
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

  Future<void> _exportZoomVideo(
    BuildContext context,
    FractalEngine engine,
    Size viewport,
    int videoW,
    int videoH,
  ) async {
    if (engine.isExporting) return;

    final ColorScheme scheme = Theme.of(context).colorScheme;
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    final Rect? shareOrigin =
        (box != null && box.hasSize) ? box.localToGlobal(Offset.zero) & box.size : null;

    final Size effectiveViewport =
        viewport.isEmpty ? const Size(1080, 1920) : viewport;
    final double baseSpan =
        math.min(effectiveViewport.width, effectiveViewport.height);
    final double exportAspect = videoW / videoH;
    final double logicalW =
        exportAspect >= 1.0 ? baseSpan * exportAspect : baseSpan;
    final double logicalH =
        exportAspect >= 1.0 ? baseSpan : baseSpan / exportAspect;

    final int totalFrames = _videoDurationSec * _videoFps;
    final double startZoom = engine.fractalType.defaultZoom;
    final double endZoom = engine.zoom;
    final double zoomRatio = endZoom / startZoom;
    final double rot = _rotation.radians(engine.rotation) ?? engine.rotation;
    final double rotCos = math.cos(rot);
    final double rotSin = math.sin(rot);

    final String renderingMsg =
        _trOr(engine, 'export_rendering_video', 'Rendering video');
    final String failedMsg = engine.tr('export_failed');

    engine.setExporting(true);
    final CpuRenderCancellationToken cancelToken =
        engine.startExportCancellationToken();
    showAppToast(context, renderingMsg, long: true);

    const MethodChannel displayChannel =
        MethodChannel('page.puzzak.fractals/display');
    try {
      await displayChannel.invokeMethod<void>('requestNotificationPermission');
    } catch (_) {}
    try {
      await displayChannel.invokeMethod<void>(
        'startExportNotification',
        <String, dynamic>{
          'title': renderingMsg,
          'detail': '$videoW × $videoH · $totalFrames frames',
        },
      );
    } catch (_) {}

    int lastNotifiedPct = -1;
    bool encodeStarted = false;
    ui.FragmentShader? ptShader;
    PerturbationOrbitResult? ptOrbit;
    ui.Image? ptOrbitTexture;
    BigFixed? ptOrbitCenterXBig;
    BigFixed? ptOrbitCenterYBig;
    double ptOrbitZoom = 0.0;
    int ptOrbitRequestedMaxIter = 0;

    try {
      final int ts = DateTime.now().millisecondsSinceEpoch;
      final String displayName =
          'fractal_zoom_${engine.fractalType.name}_$ts.mp4';
      final Directory tempDir = await getTemporaryDirectory();
      final String mp4Path =
          '${tempDir.path}${Platform.pathSeparator}$displayName';

      await displayChannel.invokeMethod<void>(
        'startVideoEncode',
        <String, dynamic>{
          'path': mp4Path,
          'width': videoW,
          'height': videoH,
          'fps': _videoFps,
        },
      );
      encodeStarted = true;

      for (int i = 0; i < totalFrames; i++) {
        if (cancelToken.isCancelled) {
          throw const CpuRenderCancelledException();
        }
        final double t = totalFrames <= 1 ? 1.0 : i / (totalFrames - 1);
        final double frameZoom = startZoom * math.pow(zoomRatio, t);
        final int frameMaxIter = _maxIterationsForZoom(engine, frameZoom);

        final ui.Image frameImg;
        if (frameZoom >= FractalEngine.cpuDeepThresholdZoom) {
          if (ptShader == null) {
            final ui.FragmentProgram ptProgram =
                await ui.FragmentProgram.fromAsset('shaders/perturbation.frag');
            ptShader = ptProgram.fragmentShader();
          }
          final bool needsOrbit = ptOrbit == null ||
              ptOrbitTexture == null ||
              ptOrbitCenterXBig == null ||
              ptOrbitCenterYBig == null ||
              frameZoom > ptOrbitZoom * 1.8 ||
              (frameMaxIter > ptOrbitRequestedMaxIter &&
                  ptOrbitRequestedMaxIter < PerturbationSolver.maxOrbitSteps);
          if (needsOrbit) {
            final int fracBits = requiredPrecisionBits(frameZoom);
            final int decimalDigits = (fracBits * 0.30103).ceil() + 4;
            final double halfDiag =
                0.5 * math.sqrt(logicalW * logicalW + logicalH * logicalH);
            final PerturbationOrbitRequest req = PerturbationOrbitRequest(
              centerXDecimal:
                  engine.centerXBig.toDecimalString(decimalDigits),
              centerYDecimal:
                  engine.centerYBig.toDecimalString(decimalDigits),
              zoom: frameZoom,
              maxIterations: frameMaxIter,
              fractalTypeIndex: engine.fractalType.shaderIndex,
              juliaCx: engine.juliaCx,
              juliaCy: engine.juliaCy,
              viewportHalfDiagPx: halfDiag,
              fracBits: fracBits,
            );
            final PerturbationOrbitResult orbitResult =
                await PerturbationSolver.computeOrbit(req);
            if (cancelToken.isCancelled) {
              throw const CpuRenderCancelledException();
            }
            final ui.Image decodedTex =
                await PerturbationSolver.decodeOrbitTexture(orbitResult);
            if (cancelToken.isCancelled) {
              decodedTex.dispose();
              throw const CpuRenderCancelledException();
            }
            ptOrbitTexture?.dispose();
            ptOrbit = orbitResult;
            ptOrbitTexture = decodedTex;
            ptOrbitCenterXBig =
                BigFixed.parseDecimal(orbitResult.refCenterXDecimal, fracBits);
            ptOrbitCenterYBig =
                BigFixed.parseDecimal(orbitResult.refCenterYDecimal, fracBits);
            ptOrbitZoom = frameZoom;
            ptOrbitRequestedMaxIter = frameMaxIter;
          }

          final Size targetSize = Size(videoW.toDouble(), videoH.toDouble());
          final ui.PictureRecorder recorder = ui.PictureRecorder();
          final Canvas canvas = Canvas(recorder);
          _applyExportPerturbationUniforms(
            shader: ptShader,
            uSize: targetSize,
            viewportWidth: logicalW,
            centerXBig: engine.centerXBig,
            centerYBig: engine.centerYBig,
            orbitCenterXBig: ptOrbitCenterXBig,
            orbitCenterYBig: ptOrbitCenterYBig,
            zoom: frameZoom,
            rotation: rot,
            maxIter: frameMaxIter,
            fractalTypeIndex: engine.fractalType.shaderIndex,
            juliaCx: engine.juliaCx,
            juliaCy: engine.juliaCy,
            paletteIndex: engine.palette.shaderIndex,
            primary: scheme.primary,
            tertiary: scheme.tertiary,
            colorOffset: engine.colorOffset,
            smoothColor: engine.smoothColor,
            orbit: ptOrbit,
            orbitTexture: ptOrbitTexture,
          );
          canvas.drawRect(
            Offset.zero & targetSize,
            Paint()..shader = ptShader,
          );
          final ui.Picture picture = recorder.endRecording();
          try {
            frameImg = await picture.toImage(videoW, videoH);
          } finally {
            picture.dispose();
          }
        } else {
          final CpuRenderRequest request = CpuRenderRequest(
            width: videoW,
            height: videoH,
            logicalWidth: logicalW,
            logicalHeight: logicalH,
            centerX: engine.centerX,
            centerY: engine.centerY,
            zoom: frameZoom,
            rotCos: rotCos,
            rotSin: rotSin,
            maxIterations: frameMaxIter,
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

          frameImg = await CpuFractalRenderer.renderImage(
            request,
            cancellationToken: cancelToken,
          );
        }

        Uint8List? pngBytes;
        try {
          if (cancelToken.isCancelled) {
            frameImg.dispose();
            throw const CpuRenderCancelledException();
          }
          final ByteData? data =
              await frameImg.toByteData(format: ui.ImageByteFormat.png);
          pngBytes = data?.buffer.asUint8List();
        } catch (e) {
          frameImg.dispose();
          rethrow;
        }

        final double progress = (i + 1) / totalFrames;
        final int pct = (progress * 100).round();
        engine.setExportProgress(progress);
        engine.updateBenchmarkOverlay(
          active: true,
          stage: renderingMsg,
          detail: '${i + 1}/$totalFrames · $pct%',
          previewImage: frameImg,
        );

        if (pngBytes == null) {
          throw StateError('Failed to encode frame $i');
        }
        await displayChannel.invokeMethod<void>(
          'appendVideoFrame',
          <String, dynamic>{'pngBytes': pngBytes},
        );

        if (pct - lastNotifiedPct >= 5 || i == totalFrames - 1) {
          lastNotifiedPct = pct;
          displayChannel.invokeMethod<void>(
            'updateExportNotification',
            <String, dynamic>{
              'progress': progress,
              'title': renderingMsg,
              'detail': '${i + 1}/$totalFrames · $pct%',
            },
          ).catchError((Object _) {});
        }
      }

      await displayChannel.invokeMethod<void>('finishVideoEncode');
      encodeStarted = false;

      String? contentUri;
      try {
        contentUri = await displayChannel.invokeMethod<String>(
          'saveVideoToGallery',
          <String, dynamic>{
            'sourcePath': mp4Path,
            'displayName': displayName,
          },
        );
      } catch (_) {}

      final String savedMsg = _trOr(
        engine,
        'video_saved_movies',
        'Saved to Movies/Fractals',
      );
      if (context.mounted) {
        showAppToast(context, savedMsg);
      }

      if (contentUri != null && contentUri.isNotEmpty) {
        try {
          await displayChannel.invokeMethod<void>(
            'showExportCompleteNotification',
            <String, dynamic>{
              'title': savedMsg,
              'detail':
                  '$videoW × $videoH · ${_videoDurationSec}s · ${_videoFps}fps',
              'contentUri': contentUri,
              'mimeType': 'video/mp4',
            },
          );
        } catch (_) {}
      }

      await Share.shareXFiles(
        <XFile>[XFile(mp4Path, mimeType: 'video/mp4')],
        text:
            '${engine.tr(engine.fractalType.translationKey)} · ${FractalEngine.formatZoom(engine.zoom)}',
        sharePositionOrigin: shareOrigin,
      );
      engine.recordShareEvent();
    } on CpuRenderCancelledException {
      if (encodeStarted) {
        try {
          await displayChannel.invokeMethod<void>('finishVideoEncode');
        } catch (_) {}
      }
      if (context.mounted) {
        showAppToast(
          context,
          _trOr(engine, 'export_cancelled', 'Export cancelled'),
        );
      }
    } catch (e) {
      if (encodeStarted) {
        try {
          await displayChannel.invokeMethod<void>('finishVideoEncode');
        } catch (_) {}
      }
      engine.analytics.log('ExportVideo', 'Error', '$e');
      if (context.mounted) {
        showAppToast(context, failedMsg);
      }
    } finally {
      ptOrbitTexture?.dispose();
      ptShader?.dispose();
      try {
        await displayChannel.invokeMethod<void>('stopExportNotification');
      } catch (_) {}
      engine.updateBenchmarkOverlay(active: false);
      engine.setExporting(false);
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
      final (int videoW, int videoH) = _resolvedVideoDimensions();
      final int totalFrames = _videoDurationSec * _videoFps;

      return _SubPageScaffold(
        title: engine.tr('section_export'),
        isSheet: widget.isSheet,
        onClose: widget.onClose,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: SegmentedButton<_ExportMode>(
              segments: <ButtonSegment<_ExportMode>>[
                ButtonSegment<_ExportMode>(
                  value: _ExportMode.image,
                  icon: const Icon(Icons.image_rounded, size: 18),
                  label: Text(_trOr(engine, 'export_mode_image', 'Image')),
                ),
                ButtonSegment<_ExportMode>(
                  value: _ExportMode.video,
                  icon: const Icon(Icons.movie_rounded, size: 18),
                  label: Text(_trOr(engine, 'export_mode_video', 'Zoom Video')),
                ),
              ],
              selected: <_ExportMode>{_mode},
              onSelectionChanged: engine.isExporting
                  ? null
                  : (Set<_ExportMode> next) {
                      if (next.isNotEmpty) {
                        setState(() => _mode = next.first);
                      }
                    },
            ),
          ),
          if (_mode == _ExportMode.video) ...<Widget>[
            CardGroup(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              _trOr(engine, 'export_duration', 'Duration'),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          Text(
                            '${_videoDurationSec}s · $totalFrames frames',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: scheme.primary,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: _videoDurationSec.toDouble(),
                        min: 3,
                        max: 30,
                        divisions: 27,
                        label: '${_videoDurationSec}s',
                        onChanged: engine.isExporting
                            ? null
                            : (double value) {
                                final int next = value.round().clamp(3, 30);
                                if (next != _videoDurationSec) {
                                  HapticFeedback.selectionClick();
                                  setState(() => _videoDurationSec = next);
                                }
                              },
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              _trOr(engine, 'export_fps', 'Frame Rate'),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          Text(
                            '$_videoFps fps',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: scheme.primary,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: _videoFps.toDouble(),
                        min: 12,
                        max: 120,
                        divisions: 108,
                        label: '$_videoFps fps',
                        onChanged: engine.isExporting
                            ? null
                            : (double value) {
                                final int next = value.round().clamp(12, 120);
                                if (next != _videoFps) {
                                  HapticFeedback.selectionClick();
                                  setState(() => _videoFps = next);
                                }
                              },
                      ),
                    ],
                  ),
                ),
                CardContents.tap(
                  title: _trOr(engine, 'export_resolution', 'Resolution'),
                  subtitle: '${_videoRes.label} ($videoW × $videoH)',
                  trailing: const Icon(Icons.chevron_right_rounded),
                  action: () => OptionPickerDialog.show<_VideoResolutionPreset>(
                    context: context,
                    title: _trOr(engine, 'export_resolution', 'Resolution'),
                    options: <OptionPickerItem<_VideoResolutionPreset>>[
                      for (final _VideoResolutionPreset r
                          in _VideoResolutionPreset.values)
                        OptionPickerItem<_VideoResolutionPreset>(
                          value: r,
                          title: r.label,
                        ),
                    ],
                    currentValue: _videoRes,
                    onSelected: (_VideoResolutionPreset value) {
                      setState(() => _videoRes = value);
                    },
                  ),
                ),
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
                    title: _trOr(
                      engine,
                      'export_rendering_video',
                      'Rendering video',
                    ),
                    subtitle: engine.exportProgress != null
                        ? '${(engine.exportProgress! * 100).round()}%'
                        : '',
                    subsubtitle: '',
                    progress: engine.exportProgress ?? -1,
                  ),
                  CardContents.tapIcon(
                    title: _trOr(engine, 'export_cancel', 'Cancel Rendering'),
                    subtitle: '$videoW × $videoH · $totalFrames frames',
                    icon: Icons.stop_circle_rounded,
                    color: scheme.onErrorContainer,
                    colorBG: scheme.errorContainer,
                    action: engine.cancelActiveExport,
                  ),
                ] else
                  CardContents.tapIcon(
                    title: _trOr(engine, 'export_render_video', 'Render Video'),
                    subtitle:
                        '$videoW × $videoH · ${_videoDurationSec}s · ${_videoFps}fps · $totalFrames frames',
                    icon: Icons.movie_creation_rounded,
                    color: scheme.onPrimaryContainer,
                    colorBG: scheme.primaryContainer,
                    action: () => _exportZoomVideo(
                      context,
                      engine,
                      activeViewport,
                      videoW,
                      videoH,
                    ),
                  ),
              ],
            ),
          ] else ...<Widget>[
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
          TextPart.infoShort(
            title: _mode == _ExportMode.video
                ? _trOr(
                    engine,
                    'export_video_explainer',
                    'Zoom videos animate smoothly from the default overview into your current coordinates and zoom level, saved as MP4 to Movies/Fractals.',
                  )
                : _trOr(
                    engine,
                    'export_explainer',
                    'High-resolution exports render off-screen at your chosen aspect ratio and orientation. Choose PNG for lossless quality or JPEG for a smaller file size.',
                  ),
            subtitle: '',
            action: () {},
            context: context,
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

String _bookmarkSubtitle(FractalEngine engine, FractalBookmark bookmark) {
  final String? rawAuthor = bookmark.author?.trim();
  if (rawAuthor != null && rawAuthor.isNotEmpty) {
    return _trOr(engine, 'bookmark_by_author', 'by {author}')
        .replaceAll('{author}', rawAuthor);
  }
  if (bookmark.isBuiltIn) {
    return _trOr(engine, 'bookmark_by_author', 'by {author}')
        .replaceAll('{author}', 'Puzzak');
  }
  return FractalEngine.formatZoom(bookmark.zoom);
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        CardGroup(
          children: <Widget>[
            CardContents.tapIcon(
              title: engine.tr('save_bookmark'),
              subtitle:
                  '${engine.tr(engine.fractalType.translationKey)} · '
                  '${FractalEngine.formatZoom(engine.zoom)}',
              icon: Icons.bookmark_add_rounded,
              color: scheme.onPrimaryContainer,
              colorBG: scheme.primaryContainer,
              action: () => showAddBookmarkDialog(context, engine),
            ),
          ],
        ),
        if (engine.customBookmarks.isNotEmpty) ...<Widget>[
          Category.settings(
            title: _trOr(engine, 'bookmarks_user', 'My Bookmarks'),
            context: context,
          ),
          CardGroup(
            children: <Widget>[
              for (final FractalBookmark bookmark in engine.customBookmarks)
                CardContents.tap(
                  title: bookmark.name,
                  subtitle: _bookmarkSubtitle(engine, bookmark),
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
                        onPressed: () => showShareFractalSheet(
                          context,
                          engine,
                          bookmark: bookmark,
                        ),
                      ),
                    ],
                  ),
                  action: () {
                    engine.applyBookmark(bookmark);
                    onApplied?.call();
                  },
                ),
            ],
          ),
        ],
        Category.settings(
          title: _trOr(engine, 'bookmarks_default', 'Default Bookmarks'),
          context: context,
        ),
        CardGroup(
          children: <Widget>[
            for (final FractalBookmark bookmark in engine.defaultBookmarks)
              CardContents.tap(
                title: bookmark.name,
                subtitle: _bookmarkSubtitle(engine, bookmark),
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
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
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
      ),
    );
  }
}
