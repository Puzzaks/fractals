import 'dart:convert';
import 'dart:io' show Directory, File, Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show Uint8List, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:m3x_gh/m3x_gh.dart';
import 'package:m3x_ui/m3x_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../engine/cpu_renderer.dart';
import '../engine/fractal_engine.dart';
import '../engine/fractal_models.dart';
import 'hud_overlay.dart';

/// Renders the current fractal view at [targetLongEdge] pixels using the
/// multi-isolate CPU `float64` renderer and opens the system share sheet.
Future<void> exportFractalPng(
  BuildContext context,
  FractalEngine engine,
  Size viewport,
  int targetLongEdge,
) async {
  if (engine.isExporting) return;

  final ColorScheme scheme = Theme.of(context).colorScheme;
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final RenderBox? box = context.findRenderObject() as RenderBox?;
  final Rect? shareOrigin =
      (box != null && box.hasSize) ? box.localToGlobal(Offset.zero) & box.size : null;

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

  final String exportingMsg = engine.tr('exporting');
  final String failedMsg = engine.tr('export_failed');
  final String shareText =
      '${engine.tr(engine.fractalType.translationKey)} · ${FractalEngine.formatZoom(engine.zoom)}';

  engine.setExporting(true);
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
      logicalWidth: effectiveViewport.width,
      logicalHeight: effectiveViewport.height,
      centerX: engine.centerX,
      centerY: engine.centerY,
      zoom: engine.zoom,
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

    final Uint8List? pngBytes = await CpuFractalRenderer.renderPngBytes(request);
    if (pngBytes == null) {
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

    final String fileName =
        'fractal_${engine.fractalType.name}_${DateTime.now().millisecondsSinceEpoch}.png';

    if (kIsWeb) {
      await Share.shareXFiles(
        <XFile>[XFile.fromData(pngBytes, mimeType: 'image/png', name: fileName)],
        text: shareText,
        sharePositionOrigin: shareOrigin,
      );
    } else {
      final Directory tempDir = await getTemporaryDirectory();
      final File file =
          File('${tempDir.path}${Platform.pathSeparator}$fileName');
      await file.writeAsBytes(pngBytes, flush: true);
      await Share.shareXFiles(
        <XFile>[XFile(file.path, mimeType: 'image/png')],
        text: shareText,
        sharePositionOrigin: shareOrigin,
      );
    }
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
    engine.setExporting(false);
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
            child: FractalInspectorPanel(
              viewport: viewport,
              scrollController: scrollController,
              isSheet: true,
              onClose: () => Navigator.of(sheetContext).pop(),
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

Future<void> _showAddBookmarkDialog(
  BuildContext context,
  FractalEngine engine,
) async {
  final TextEditingController controller = TextEditingController(
    text:
        '${engine.tr(engine.fractalType.translationKey)} (${FractalEngine.formatZoom(engine.zoom)})',
  );
  try {
    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(engine.tr('save_bookmark')),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: engine.tr('save_bookmark_hint'),
              border: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(16)),
              ),
            ),
            onSubmitted: (String value) {
              Navigator.of(dialogContext).pop(value.trim());
            },
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(engine.tr('cancel')),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: Text(engine.tr('save')),
            ),
          ],
        );
      },
    );
    if (result != null && result.isNotEmpty) {
      engine.addCustomBookmark(result);
    }
  } finally {
    controller.dispose();
  }
}

/// Full Material 3 Expressive inspector panel built with `m3x_ui` components.
class FractalInspectorPanel extends StatefulWidget {
  final Size viewport;
  final ScrollController? scrollController;
  final bool isSheet;
  final VoidCallback? onClose;

  const FractalInspectorPanel({
    super.key,
    required this.viewport,
    this.scrollController,
    this.isSheet = false,
    this.onClose,
  });

  @override
  State<FractalInspectorPanel> createState() => _FractalInspectorPanelState();
}

class _FractalInspectorPanelState extends State<FractalInspectorPanel> {
  late final Future<String> _authorsFuture;

  @override
  void initState() {
    super.initState();
    _authorsFuture = rootBundle.loadString('assets/data/authors.json');
  }

  Future<void> _openLanguageDialog(
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

  List<Color> _palettePreviewColors(
    FractalPalette palette,
    ColorScheme scheme,
  ) {
    switch (palette) {
      case FractalPalette.system:
        return <Color>[scheme.primary, scheme.tertiary];
      case FractalPalette.inferno:
        return const <Color>[
          Color(0xFF851C6B),
          Color(0xFFED6921),
          Color(0xFFFCF5A3),
        ];
      case FractalPalette.viridis:
        return const <Color>[
          Color(0xFF290A54),
          Color(0xFF26AD82),
          Color(0xFFEBE62E),
        ];
      case FractalPalette.ocean:
        return const <Color>[
          Color(0xFF0A5CAD),
          Color(0xFF2ED1E0),
          Color(0xFFE0F7FF),
        ];
      case FractalPalette.neon:
        return const <Color>[
          Color(0xFFFF0080),
          Color(0xFF00FF80),
          Color(0xFF0080FF),
        ];
      case FractalPalette.monochrome:
        return const <Color>[
          Color(0xFF1F2329),
          Color(0xFF9EA4B0),
          Color(0xFFF5F7FA),
        ];
      case FractalPalette.twilight:
        return const <Color>[
          Color(0xFF7D3899),
          Color(0xFFEB7A80),
          Color(0xFFF5D6A6),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final FractalEngine engine = context.read<FractalEngine>();
    context.select<FractalEngine, String>(
      (FractalEngine e) =>
          '${e.dictionary.isSystemLanguage}:${e.dictionary.locale}',
    );
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final double dpr = MediaQuery.devicePixelRatioOf(context);
    final int screenLongEdge = widget.viewport.isEmpty
        ? 1920
        : (math.max(widget.viewport.width, widget.viewport.height) * dpr)
            .round()
            .clamp(512, 4096);

    final String languageSubtitle = engine.dictionary.isSystemLanguage
        ? engine.tr('language_system')
        : engine.dictionary.currentLanguageName;

    return Column(
      children: <Widget>[
        if (widget.isSheet) const _SheetHandle(),
        _PanelHeader(
          title: engine.tr('inspector_title'),
          onClose: widget.onClose,
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            controller: widget.scrollController,
            padding: const EdgeInsets.only(bottom: 32),
            children: <Widget>[
              // 1. Live Telemetry (isolated Consumer so pan/zoom doesn't
              // rebuild the entire settings ListView).
              const _LiveTelemetrySection(),

              // 2. Fractal & Parameters
              Category.settings(
                title: engine.tr('section_fractal'),
                context: context,
              ),
              Builder(
                builder: (BuildContext ctx) {
                  final (
                    FractalType fractalType,
                    double juliaCx,
                    double juliaCy,
                  ) = ctx.select<FractalEngine, (FractalType, double, double)>(
                    (FractalEngine e) => (e.fractalType, e.juliaCx, e.juliaCy),
                  );
                  return CardGroup(
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: LayoutBuilder(
                          builder: (
                            BuildContext boxCtx,
                            BoxConstraints boxConstraints,
                          ) {
                            return SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minWidth: boxConstraints.maxWidth,
                                ),
                                child: SegmentedButton<FractalType>(
                                  showSelectedIcon: false,
                                  style: const ButtonStyle(
                                    visualDensity: VisualDensity.compact,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  segments: FractalType.values
                                      .map(
                                        (FractalType type) =>
                                            ButtonSegment<FractalType>(
                                          value: type,
                                          label: Text(
                                            engine.tr(type.translationKey),
                                            maxLines: 1,
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  selected: <FractalType>{fractalType},
                                  onSelectionChanged:
                                      (Set<FractalType> selection) {
                                    if (selection.isNotEmpty) {
                                      HapticFeedback.lightImpact();
                                      engine.setFractalType(selection.first);
                                    }
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      if (fractalType == FractalType.julia) ...<Widget>[
                        CardContents.slider(
                          title: engine.tr('julia_real'),
                          value: juliaCx,
                          min: -2.0,
                          max: 2.0,
                          trailing: Text(
                            juliaCx.toStringAsFixed(4),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontFeatures: <FontFeature>[
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          onChanged: (double v) => engine.setJuliaC(v, juliaCy),
                        ),
                        CardContents.slider(
                          title: engine.tr('julia_imag'),
                          value: juliaCy,
                          min: -2.0,
                          max: 2.0,
                          trailing: Text(
                            juliaCy.toStringAsFixed(4),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontFeatures: <FontFeature>[
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          onChanged: (double v) => engine.setJuliaC(juliaCx, v),
                        ),
                      ],
                      CardContents.tap(
                        title: engine.tr('reset_view'),
                        subtitle: engine.tr('reset_view_sub'),
                        trailing: const Icon(
                          Icons.center_focus_strong_rounded,
                          size: 20,
                        ),
                        action: engine.resetView,
                      ),
                    ],
                  );
                },
              ),

              // 3. Appearance & Color
              Category.settings(
                title: engine.tr('section_appearance'),
                context: context,
              ),
              Builder(
                builder: (BuildContext ctx) {
                  final (
                    FractalPalette palette,
                    bool smoothColor,
                    double colorOffset,
                  ) = ctx.select<FractalEngine, (FractalPalette, bool, double)>(
                    (FractalEngine e) =>
                        (e.palette, e.smoothColor, e.colorOffset),
                  );
                  return CardGroup(
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              engine.tr('palette_label'),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children:
                                  FractalPalette.values.map((FractalPalette p) {
                                final bool selected = palette == p;
                                final List<Color> swatch =
                                    _palettePreviewColors(p, scheme);
                                return ChoiceChip(
                                  selected: selected,
                                  avatar: Container(
                                    width: 16,
                                    height: 16,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: LinearGradient(colors: swatch),
                                      border: Border.all(
                                        color: scheme.outline
                                            .withValues(alpha: 0.4),
                                        width: 0.8,
                                      ),
                                    ),
                                  ),
                                  label: Text(engine.tr(p.translationKey)),
                                  onSelected: (bool isSelected) {
                                    if (isSelected) {
                                      HapticFeedback.lightImpact();
                                      engine.setPalette(p);
                                    }
                                  },
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                      CardContents.turn(
                        title: engine.tr('smooth_coloring'),
                        subtitle: engine.tr('smooth_coloring_sub'),
                        value: smoothColor,
                        action: () => engine.setSmoothColor(!smoothColor),
                        switcher: engine.setSmoothColor,
                      ),
                      CardContents.slider(
                        title: engine.tr('color_phase'),
                        value: colorOffset,
                        min: 0.0,
                        max: 1.0,
                        trailing: Text(
                          '${(colorOffset * 100).round()}%',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontFeatures: <FontFeature>[
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                        onChanged: engine.setColorOffset,
                      ),
                    ],
                  );
                },
              ),

              // 4. Rendering & Precision
              Category.settings(
                title: engine.tr('section_rendering'),
                context: context,
              ),
              Builder(
                builder: (BuildContext ctx) {
                  final (
                    RenderQuality quality,
                    RenderBackend backend,
                    double dragPreviewScale,
                    bool autoIterations,
                    int manualMaxIterations,
                    int effectiveMaxIterations,
                    bool showTelemetry,
                  ) = ctx.select<
                      FractalEngine,
                      (
                        RenderQuality,
                        RenderBackend,
                        double,
                        bool,
                        int,
                        int,
                        bool,
                      )>(
                    (FractalEngine e) => (
                      e.quality,
                      e.backend,
                      e.dragPreviewScale,
                      e.autoIterations,
                      e.manualMaxIterations,
                      e.effectiveMaxIterations,
                      e.showTelemetry,
                    ),
                  );
                  return CardGroup(
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              engine.tr('quality_label'),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children:
                                  RenderQuality.values.map((RenderQuality q) {
                                return ChoiceChip(
                                  selected: quality == q,
                                  label: Text(engine.tr(q.translationKey)),
                                  onSelected: (bool isSelected) {
                                    if (isSelected) {
                                      HapticFeedback.lightImpact();
                                      engine.setQuality(q);
                                    }
                                  },
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
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
                              builder: (
                                BuildContext boxCtx,
                                BoxConstraints boxConstraints,
                              ) {
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
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
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
                                      selected: <RenderBackend>{backend},
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
                      CardContents.slider(
                        title: engine.tr('drag_preview_scale'),
                        subtitle: engine.tr('drag_preview_scale_sub'),
                        value: dragPreviewScale,
                        min: 0.10,
                        max: 1.00,
                        divisions: 18,
                        trailing: Text(
                          '${(dragPreviewScale * 100).round()}%',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontFeatures: <FontFeature>[
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                        onChanged: engine.setDragPreviewScale,
                      ),
                      CardContents.turn(
                        title: engine.tr('auto_iterations'),
                        subtitle: engine.tr('auto_iterations_sub'),
                        value: autoIterations,
                        action: () =>
                            engine.setAutoIterations(!autoIterations),
                        switcher: engine.setAutoIterations,
                      ),
                      CardContents.slider(
                        title: engine.tr('max_iterations'),
                        subtitle: autoIterations
                            ? '${engine.tr('backend_auto')}: $effectiveMaxIterations'
                            : null,
                        value: (autoIterations
                                ? effectiveMaxIterations
                                : manualMaxIterations)
                            .toDouble()
                            .clamp(50.0, 2000.0),
                        min: 50,
                        max: 2000,
                        divisions: 39,
                        trailing: Text(
                          '$effectiveMaxIterations',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontFeatures: <FontFeature>[
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                        onChanged: (double value) {
                          if (autoIterations) {
                            engine.setAutoIterations(false);
                          }
                          engine.setManualMaxIterations(value.round());
                        },
                      ),
                      CardContents.turn(
                        title: engine.tr('show_telemetry'),
                        subtitle: engine.tr('show_telemetry_sub'),
                        value: showTelemetry,
                        action: () => engine.setShowTelemetry(!showTelemetry),
                        switcher: engine.setShowTelemetry,
                      ),
                    ],
                  );
                },
              ),

              // 5. Bookmarks
              Category.settings(
                title: engine.tr('section_bookmarks'),
                context: context,
              ),
              Builder(
                builder: (BuildContext ctx) {
                  ctx.select<FractalEngine, (int, FractalType, String)>(
                    (FractalEngine e) => (
                      e.customBookmarks.length,
                      e.fractalType,
                      FractalEngine.formatZoom(e.zoom),
                    ),
                  );
                  return _BookmarkCardGroup(engine: engine);
                },
              ),

              // 6. Export
              Category.settings(
                title: engine.tr('section_export'),
                context: context,
              ),
              Builder(
                builder: (BuildContext ctx) {
                  final bool isExporting = ctx.select<FractalEngine, bool>(
                    (FractalEngine e) => e.isExporting,
                  );
                  return CardGroup(
                    children: <Widget>[
                      if (isExporting)
                        CardContents.progress(
                          title: engine.tr('exporting'),
                          subtitle: '',
                          subsubtitle: '',
                          progress: -1,
                        ),
                      CardContents.tap(
                        title: engine.tr('export_screen'),
                        subtitle:
                            '${widget.viewport.isEmpty ? 1080 : widget.viewport.width.round()} × '
                            '${widget.viewport.isEmpty ? 1920 : widget.viewport.height.round()} @ ${dpr.toStringAsFixed(1)}×',
                        trailing:
                            const Icon(Icons.photo_size_select_actual_rounded),
                        action: () => exportFractalPng(
                          context,
                          engine,
                          widget.viewport,
                          screenLongEdge,
                        ),
                      ),
                      CardContents.tap(
                        title: engine.tr('export_2k'),
                        subtitle: 'CPU float64 · PNG',
                        trailing: const Icon(Icons.hd_rounded),
                        action: () => exportFractalPng(
                          context,
                          engine,
                          widget.viewport,
                          2560,
                        ),
                      ),
                      CardContents.tap(
                        title: engine.tr('export_4k'),
                        subtitle: 'CPU float64 · PNG',
                        trailing: const Icon(Icons.four_k_rounded),
                        action: () => exportFractalPng(
                          context,
                          engine,
                          widget.viewport,
                          3840,
                        ),
                      ),
                    ],
                  );
                },
              ),

              // 7. About & Ecosystem
              Category.settings(
                title: engine.tr('section_about'),
                context: context,
              ),
              CardGroup(
                children: <Widget>[
                  CardContents.tap(
                    title: engine.tr('language_label'),
                    subtitle: languageSubtitle,
                    trailing: const Icon(Icons.translate_rounded, size: 20),
                    action: () => _openLanguageDialog(context, engine),
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
                  FutureBuilder<String>(
                    future: _authorsFuture,
                    builder: (
                      BuildContext ctx,
                      AsyncSnapshot<String> snapshot,
                    ) {
                      if (!snapshot.hasData) {
                        return const SizedBox.shrink();
                      }
                      final List<_AuthorLink> links =
                          _parseAuthorLinks(snapshot.data!);
                      if (links.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              engine.tr('authors_label'),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: links.map((_AuthorLink link) {
                                return ActionChip(
                                  avatar: const Icon(
                                    Icons.link_rounded,
                                    size: 16,
                                  ),
                                  label: Text(link.title),
                                  onPressed: () {
                                    final Uri? uri = Uri.tryParse(link.url);
                                    if (uri != null) {
                                      launchUrl(
                                        uri,
                                        mode: LaunchMode.externalApplication,
                                      );
                                    }
                                  },
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
              TextPart.infoShort(
                title: engine.tr('hint_controls'),
                subtitle: '',
                action: () {},
                context: context,
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<_AuthorLink> _parseAuthorLinks(String rawJson) {
    try {
      final dynamic decoded = jsonDecode(rawJson);
      if (decoded is! Map) return const <_AuthorLink>[];
      final dynamic authors = decoded['Authors'];
      if (authors is! List || authors.isEmpty) return const <_AuthorLink>[];
      final List<_AuthorLink> results = <_AuthorLink>[];
      for (final dynamic author in authors) {
        if (author is Map && author['Links'] is List) {
          for (final dynamic link in author['Links'] as List) {
            if (link is Map &&
                link['Title'] != null &&
                link['Link'] != null) {
              results.add(
                _AuthorLink(
                  title: link['Title'].toString(),
                  url: link['Link'].toString(),
                ),
              );
            }
          }
        }
      }
      return results;
    } catch (_) {
      return const <_AuthorLink>[];
    }
  }
}

class _LiveTelemetrySection extends StatelessWidget {
  const _LiveTelemetrySection();

  @override
  Widget build(BuildContext context) {
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
              history: engine.fpsHistory
                  .map((double v) => (v * 0.48).clamp(0.0, 0.48))
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
          CardContents.doubleTap(
            title: bookmark.name,
            subtitle:
                '${engine.tr(bookmark.fractalType.translationKey)} · '
                '${FractalEngine.formatZoom(bookmark.zoom)}',
            icon: Icons.delete_outline_rounded,
            secondTooltip: engine.tr('delete'),
            action: () {
              engine.applyBookmark(bookmark);
              onApplied?.call();
            },
            secondAction: () => engine.removeCustomBookmark(bookmark.id),
          ),
        for (final FractalBookmark bookmark in builtInBookmarks)
          CardContents.tap(
            title: bookmark.name,
            subtitle:
                '${engine.tr(bookmark.fractalType.translationKey)} · '
                '${FractalEngine.formatZoom(bookmark.zoom)}',
            trailing: const Icon(Icons.explore_rounded, size: 20),
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
  final VoidCallback? onClose;

  const _PanelHeader({
    required this.title,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 10, 10),
      child: Row(
        children: <Widget>[
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

class _AuthorLink {
  final String title;
  final String url;

  const _AuthorLink({required this.title, required this.url});
}
