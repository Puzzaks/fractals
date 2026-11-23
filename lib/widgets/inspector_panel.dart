import 'dart:io' show Directory, File, Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show Uint8List, ValueListenable, kIsWeb;
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
      rotCos: math.cos(engine.rotation),
      rotSin: math.sin(engine.rotation),
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

String _trOr(FractalEngine engine, String key, String fallback) {
  final String raw = engine.tr(key);
  if (raw.isEmpty || raw == key || raw.startsWith('!')) {
    return fallback;
  }
  return raw;
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

/// Material 3 Expressive Settings Hub built with `m3x_ui` components that
/// pushes dedicated sub-pages inside its enclosing nested [Navigator].
class FractalInspectorPanel extends StatelessWidget {
  final Size viewport;
  final ValueListenable<Size>? viewportListenable;
  final ScrollController? scrollController;
  final bool isSheet;
  final VoidCallback? onClose;

  const FractalInspectorPanel({
    super.key,
    required this.viewport,
    this.viewportListenable,
    this.scrollController,
    this.isSheet = false,
    this.onClose,
  });

  void _pushSubPage(BuildContext context, Widget page) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => page,
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

    return Material(
      color: scheme.surface,
      child: Column(
        children: <Widget>[
        if (isSheet) const _SheetHandle(),
        _PanelHeader(
          title: engine.tr('inspector_title'),
          onClose: onClose,
        ),
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
                    subtitle: '$bookmarkCount',
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
                    color: scheme.onPrimaryContainer,
                    colorBG: scheme.primaryContainer,
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
                    title: _trOr(
                      engine,
                      'section_controls',
                      'Controls & Keybinds',
                    ),
                    subtitle: _trOr(
                      engine,
                      'section_controls_sub',
                      'Customize keyboard pan, zoom & shortcuts',
                    ),
                    icon: Icons.keyboard_rounded,
                    color: scheme.onSecondaryContainer,
                    colorBG: scheme.secondaryContainer,
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
                    subtitle: 'PNG · Screen / 2K / 4K',
                    icon: Icons.ios_share_rounded,
                    color: scheme.onTertiaryContainer,
                    colorBG: scheme.tertiaryContainer,
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
                title: engine.tr('section_about'),
                context: context,
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
            ],
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
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: <Widget>[
          if (isSheet) const _SheetHandle(),
          _PanelHeader(
            title: title,
            onBack: () => Navigator.of(context).pop(),
            onClose: onClose,
          ),
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
                    children: RenderQuality.values.map((RenderQuality q) {
                      return ChoiceChip(
                        selected: engine.quality == q,
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
                            onSelectionChanged: (Set<RenderBackend> selection) {
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
                'Pre-renders surrounding CPU area to reduce edge pop-in during pan',
              ),
              value: overscan,
              min: 0.0,
              max: 5.0,
              divisions: 20,
              trailing: Text(
                overscan < 1.05 ? 'Off' : '${overscan.toStringAsFixed(2)}×',
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

class _ExportSubPage extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final FractalEngine engine = context.watch<FractalEngine>();
    final double dpr = MediaQuery.devicePixelRatioOf(context);

    Widget buildBody(Size activeViewport) {
      final int screenLongEdge = activeViewport.isEmpty
          ? 1920
          : (math.max(activeViewport.width, activeViewport.height) * dpr)
              .round()
              .clamp(512, 4096);

      return _SubPageScaffold(
        title: engine.tr('section_export'),
        isSheet: isSheet,
        onClose: onClose,
        children: <Widget>[
          Category.settings(
            title: engine.tr('section_export'),
            context: context,
          ),
          CardGroup(
            children: <Widget>[
              if (engine.isExporting)
                CardContents.progress(
                  title: engine.tr('exporting'),
                  subtitle: '',
                  subsubtitle: '',
                  progress: -1,
                ),
              CardContents.tap(
                title: engine.tr('export_screen'),
                subtitle:
                    '${activeViewport.isEmpty ? 1080 : activeViewport.width.round()} × '
                    '${activeViewport.isEmpty ? 1920 : activeViewport.height.round()} @ ${dpr.toStringAsFixed(1)}×',
                trailing: const Icon(Icons.photo_size_select_actual_rounded),
                action: () => exportFractalPng(
                  context,
                  engine,
                  activeViewport,
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
                  activeViewport,
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
                  activeViewport,
                  3840,
                ),
              ),
            ],
          ),
        ],
      );
    }

    if (viewportListenable != null) {
      return ValueListenableBuilder<Size>(
        valueListenable: viewportListenable!,
        builder: (BuildContext _, Size liveSize, Widget? __) {
          return buildBody(liveSize.isEmpty ? viewport : liveSize);
        },
      );
    }
    return buildBody(viewport);
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
