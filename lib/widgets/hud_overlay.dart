import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../engine/fractal_engine.dart';
import '../engine/fractal_models.dart';

/// Copies the current complex-plane center coordinates to the system clipboard
/// and shows a localized confirmation [SnackBar].
Future<void> copyFractalCoordinates(
  BuildContext context,
  FractalEngine engine,
) async {
  final String x = FractalEngine.formatCoord(engine.centerX, engine.zoom);
  final String y = FractalEngine.formatCoord(engine.centerY, engine.zoom);
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final String copiedMsg = engine.tr('telemetry_copied');
  await Clipboard.setData(ClipboardData(text: '$x, $y'));
  if (!context.mounted) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(copiedMsg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
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

/// Clean Material 3 bottom action bar rendered in the frame area below the
/// rounded fractal card.
class HudBottomBar extends StatelessWidget {
  final bool isInspectorOpen;
  final VoidCallback onToggleInspector;
  final VoidCallback onOpenBookmarks;
  final VoidCallback onExportPng;
  final VoidCallback onHideHud;

  const HudBottomBar({
    super.key,
    required this.isInspectorOpen,
    required this.onToggleInspector,
    required this.onOpenBookmarks,
    required this.onExportPng,
    required this.onHideHud,
  });

  @override
  Widget build(BuildContext context) {
    final FractalEngine engine = context.watch<FractalEngine>();
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool showPaletteLabel = constraints.maxWidth >= 560;
        final double minRowWidth =
            (constraints.maxWidth - 16).clamp(0.0, double.infinity);

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
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: minRowWidth),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        _BarPillButton(
                          icon: Icons.auto_awesome_rounded,
                          label: engine.tr(engine.fractalType.translationKey),
                          tooltip: engine.tr('section_fractal'),
                          onTap: () {
                            final int nextIdx =
                                (engine.fractalType.index + 1) %
                                    FractalType.values.length;
                            engine.setFractalType(FractalType.values[nextIdx]);
                          },
                        ),
                        const SizedBox(width: 4),
                        if (showPaletteLabel)
                          _BarPillButton(
                            icon: Icons.palette_rounded,
                            label: engine.tr(engine.palette.translationKey),
                            tooltip: engine.tr('palette_label'),
                            onTap: engine.cyclePalette,
                          )
                        else
                          _BarIconButton(
                            icon: Icons.palette_rounded,
                            tooltip:
                                '${engine.tr('palette_label')}: ${engine.tr(engine.palette.translationKey)}',
                            onTap: engine.cyclePalette,
                          ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        _BarIconButton(
                          icon: Icons.bookmarks_rounded,
                          tooltip: engine.tr('section_bookmarks'),
                          onTap: onOpenBookmarks,
                        ),
                        _BarIconButton(
                          icon: Icons.center_focus_strong_rounded,
                          tooltip: engine.tr('reset_view'),
                          onTap: engine.resetView,
                        ),
                        _BarIconButton(
                          icon: Icons.ios_share_rounded,
                          tooltip: engine.tr('export_screen'),
                          isBusy: engine.isExporting,
                          onTap: engine.isExporting ? null : onExportPng,
                        ),
                        _BarIconButton(
                          icon: Icons.visibility_off_rounded,
                          tooltip: engine.tr('hud_hide'),
                          onTap: onHideHud,
                        ),
                        _BarIconButton(
                          icon: Icons.tune_rounded,
                          tooltip: engine.tr('inspector_title'),
                          selected: isInspectorOpen,
                          onTap: onToggleInspector,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, size: 17, color: scheme.onSecondaryContainer),
                const SizedBox(width: 6),
                Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: scheme.onSecondaryContainer,
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
  final bool selected;
  final bool isBusy;

  const _BarIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.selected = false,
    this.isBusy = false,
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
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: isBusy
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: scheme.primary,
                    ),
                  )
                : Icon(
                    icon,
                    size: 20,
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
