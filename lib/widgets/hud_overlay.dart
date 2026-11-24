import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../engine/fractal_engine.dart';
import '../engine/fractal_models.dart';
import 'app_toast.dart';

/// Returns a representative icon for [type].
IconData fractalTypeIcon(FractalType type) {
  switch (type) {
    case FractalType.mandelbrot:
      return Icons.all_inclusive_rounded;
    case FractalType.julia:
      return Icons.auto_awesome_rounded;
    case FractalType.burningShip:
      return Icons.local_fire_department_rounded;
    case FractalType.tricorn:
      return Icons.change_history_rounded;
  }
}

/// Returns preview swatch colors for [palette] using the active [scheme].
List<Color> fractalPalettePreviewColors(
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
    case FractalPalette.ukraine:
      return const <Color>[
        Color(0xFF0057B7),
        Color(0xFF2196F3),
        Color(0xFFFFD700),
      ];
  }
}

/// Presents a direct modal bottom sheet selector for all 4 [FractalType]s.
Future<void> showFractalSelectorSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext sheetContext) {
      final ColorScheme scheme = Theme.of(sheetContext).colorScheme;
      final FractalEngine engine = sheetContext.watch<FractalEngine>();
      return _SelectorSheetFrame(
        title: engine.tr('select_fractal'),
        onClose: () => Navigator.of(sheetContext).pop(),
        children: FractalType.values.map((FractalType type) {
          final bool selected = engine.fractalType == type;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: ListTile(
              selected: selected,
              selectedTileColor:
                  scheme.primaryContainer.withValues(alpha: 0.45),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              leading: Icon(
                fractalTypeIcon(type),
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
              title: Text(
                engine.tr(type.translationKey),
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              trailing: selected
                  ? Icon(Icons.check_rounded, color: scheme.primary)
                  : null,
              onTap: () {
                HapticFeedback.lightImpact();
                engine.setFractalType(type, resetCamera: false);
                Navigator.of(sheetContext).pop();
              },
            ),
          );
        }).toList(),
      );
    },
  );
}

/// Presents a direct modal bottom sheet selector for all 7 [FractalPalette]s.
Future<void> showPaletteSelectorSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext sheetContext) {
      final ColorScheme scheme = Theme.of(sheetContext).colorScheme;
      final FractalEngine engine = sheetContext.watch<FractalEngine>();
      return _SelectorSheetFrame(
        title: engine.tr('palette_label'),
        onClose: () => Navigator.of(sheetContext).pop(),
        children: FractalPalette.values.map((FractalPalette palette) {
          final bool selected = engine.palette == palette;
          final List<Color> swatch =
              fractalPalettePreviewColors(palette, scheme);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: ListTile(
              selected: selected,
              selectedTileColor:
                  scheme.primaryContainer.withValues(alpha: 0.45),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              leading: Row(
                mainAxisSize: MainAxisSize.min,
                children: swatch.map((Color color) {
                  return Container(
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
                  );
                }).toList(),
              ),
              title: Text(
                engine.tr(palette.translationKey),
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              trailing: selected
                  ? Icon(Icons.check_rounded, color: scheme.primary)
                  : null,
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.of(sheetContext).pop();
                Future<void>.delayed(
                  const Duration(milliseconds: 120),
                  () => engine.setPalette(palette),
                );
              },
            ),
          );
        }).toList(),
      );
    },
  );
}

class _SelectorSheetFrame extends StatelessWidget {
  final String title;
  final VoidCallback onClose;
  final List<Widget> children;

  const _SelectorSheetFrame({
    required this.title,
    required this.onClose,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface.withValues(alpha: 0.94),
      elevation: 8,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 10, 8),
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
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: onClose,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: children,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Copies the current complex-plane center coordinates to the system clipboard
/// and shows a localized confirmation toast.
Future<void> copyFractalCoordinates(
  BuildContext context,
  FractalEngine engine,
) async {
  final String x = FractalEngine.formatCoord(engine.centerX, engine.zoom);
  final String y = FractalEngine.formatCoord(engine.centerY, engine.zoom);
  final String copiedMsg = engine.tr('telemetry_copied');
  await Clipboard.setData(ClipboardData(text: '$x, $y'));
  if (!context.mounted) return;
  showAppToast(context, copiedMsg);
}

/// Compact translucent Material 3 Expressive telemetry pill displayed at the
/// top-left corner inside the framed fractal card.
class HudTelemetryOverlay extends StatelessWidget {
  const HudTelemetryOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final FractalEngine engine = context.watch<FractalEngine>();
    if (!engine.showTelemetry) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double maxPillWidth =
            (constraints.maxWidth - 24).clamp(120.0, 320.0);

        return Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxPillWidth),
              child: _TelemetryPill(engine: engine),
            ),
          ),
        );
      },
    );
  }
}

/// Two-line Material 3 status bar rendered below the fractal viewer.
class HudStatusRow extends StatelessWidget {
  final VoidCallback onShare;

  const HudStatusRow({
    super.key,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final FractalEngine engine = context.watch<FractalEngine>();
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final String zoomLabel = FractalEngine.formatZoom(engine.zoom);
    final String centerXStr =
        FractalEngine.formatCoord(engine.centerX, engine.zoom);
    final String centerYStr =
        FractalEngine.formatCoord(engine.centerY, engine.zoom);

    return Material(
      color: scheme.surfaceContainerHigh,
      elevation: 0,
      shape: StadiumBorder(
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Flexible(
              child: Tooltip(
                message: engine.tr('share_title'),
                child: Material(
                  color: scheme.secondaryContainer.withValues(alpha: 0.72),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      onShare();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                zoomLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: scheme.onSecondaryContainer,
                                  fontFeatures: const <FontFeature>[
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                              if (kDebugMode) ...<Widget>[
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    '${engine.activeRenderMode.badge} · '
                                    '${engine.effectiveMaxIterations} it · '
                                    '${FractalEngine.formatFps(engine.currentFps)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: textTheme.labelSmall?.copyWith(
                                      color: scheme.onSecondaryContainer
                                          .withValues(alpha: 0.78),
                                      fontFeatures: const <FontFeature>[
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          Text(
                            '$centerXStr, $centerYStr',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.labelSmall?.copyWith(
                              color: scheme.onSecondaryContainer
                                  .withValues(alpha: 0.78),
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
            ),
            const SizedBox(width: 8),
            _BarIconButton(
              icon: Icons.restart_alt_rounded,
              tooltip: engine.tr('reset_view'),
              padding: 8,
              onTap: () {
                final String raw = engine.tr('hold_to_reset_hint');
                final String message = (raw.isEmpty ||
                        raw == 'hold_to_reset_hint' ||
                        raw.startsWith('!'))
                    ? 'Hold to reset view'
                    : raw;
                showAppToast(context, message);
              },
              onLongPress: engine.resetView,
            ),
          ],
        ),
      ),
    );
  }
}

/// Clean Material 3 bottom action bar rendered in the frame area below the
/// rounded fractal card.
class HudBottomBar extends StatelessWidget {
  final bool isInspectorOpen;
  final VoidCallback onToggleInspector;
  final VoidCallback onOpenBookmarks;

  const HudBottomBar({
    super.key,
    required this.isInspectorOpen,
    required this.onToggleInspector,
    required this.onOpenBookmarks,
  });

  @override
  Widget build(BuildContext context) {
    final FractalEngine engine = context.watch<FractalEngine>();
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surfaceContainerHigh,
      elevation: 0,
      shape: StadiumBorder(
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Row(
                children: <Widget>[
                  Flexible(
                    child: _BarPillButton(
                      icon: fractalTypeIcon(engine.fractalType),
                      label: engine.tr(engine.fractalType.translationKey),
                      tooltip: engine.tr('section_fractal'),
                      onTap: () => showFractalSelectorSheet(context),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: _BarPillButton(
                      icon: Icons.palette_rounded,
                      label: engine.tr(engine.palette.translationKey),
                      tooltip: engine.tr('palette_label'),
                      onTap: () => showPaletteSelectorSheet(context),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _BarIconButton(
                  icon: Icons.bookmarks_rounded,
                  tooltip: engine.tr('section_bookmarks'),
                  padding: 8,
                  onTap: onOpenBookmarks,
                ),
                _BarIconButton(
                  icon: Icons.tune_rounded,
                  tooltip: engine.tr('inspector_title'),
                  selected: isInspectorOpen,
                  padding: 8,
                  onTap: onToggleInspector,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TelemetryPill extends StatelessWidget {
  final FractalEngine engine;

  const _TelemetryPill({required this.engine});

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final String centerXStr =
        FractalEngine.formatCoord(engine.centerX, engine.zoom);
    final String centerYStr =
        FractalEngine.formatCoord(engine.centerY, engine.zoom);
    final String fpsLabel =
        '${FractalEngine.formatFps(engine.currentFps)} · '
        '${FractalEngine.formatFrameTime(engine.lastFrameTimeMs)}';
    final String zoomLabel = FractalEngine.formatZoom(engine.zoom);
    final ActiveRenderMode mode = engine.activeRenderMode;

    return Material(
      color: scheme.surfaceContainerHigh.withValues(alpha: 0.84),
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          copyFractalCoordinates(context, engine);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Flexible(
                    child: Text(
                      fpsLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _BackendBadgeChip(
                    label: mode.badge,
                    isCpuRendering: engine.isCpuRendering,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.zoom_in_rounded,
                    size: 14,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      '$zoomLabel · ${engine.effectiveMaxIterations} it',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Flexible(
                    child: Text(
                      '$centerXStr, $centerYStr',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.copy_rounded,
                    size: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackendBadgeChip extends StatelessWidget {
  final String label;
  final bool isCpuRendering;

  const _BackendBadgeChip({
    required this.label,
    required this.isCpuRendering,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (isCpuRendering) ...<Widget>[
            SizedBox(
              width: 9,
              height: 9,
              child: CircularProgressIndicator(
                strokeWidth: 1.8,
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.onPrimaryContainer,
                ),
          ),
        ],
      ),
    );
  }
}

class _BarPillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onTap;

  const _BarPillButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: scheme.secondaryContainer.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, size: 19, color: scheme.onSecondaryContainer),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: scheme.onSecondaryContainer,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BarIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final double padding;

  const _BarIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.onLongPress,
    this.selected = false,
    this.padding = 11,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: selected ? scheme.primaryContainer : Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap == null
              ? null
              : () {
                  HapticFeedback.lightImpact();
                  onTap!();
                },
          onLongPress: onLongPress == null
              ? null
              : () {
                  HapticFeedback.mediumImpact();
                  onLongPress!();
                },
          child: Padding(
            padding: EdgeInsets.all(padding),
            child: Icon(
              icon,
              size: 24,
              color: selected
                  ? scheme.onPrimaryContainer
                  : scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
