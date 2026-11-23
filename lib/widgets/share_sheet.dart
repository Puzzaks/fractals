import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../engine/fractal_engine.dart';
import '../engine/fractal_models.dart';
import '../engine/fractal_share_link.dart';

String _trOr(FractalEngine engine, String key, String fallback) {
  final String value = engine.tr(key);
  if (value.isEmpty || value == key || value.startsWith('!')) {
    return fallback;
  }
  return value;
}

/// Shows a Material 3 modal bottom sheet for sharing the current fractal view
/// or a specific [bookmark] as a QR code, deep link, or exported image.
Future<void> showShareFractalSheet(
  BuildContext context,
  FractalEngine engine, {
  FractalBookmark? bookmark,
  VoidCallback? onOpenExport,
}) async {
  final Uri shareUri = bookmark != null
      ? FractalShareLink.encodeBookmark(bookmark)
      : FractalShareLink.encode(engine);
  final String shareUrl = shareUri.toString();
  final String title =
      bookmark?.name ?? _trOr(engine, 'share_title', 'Share Fractal');

  final FractalType fractalType = bookmark?.fractalType ?? engine.fractalType;
  final double zoom = bookmark?.zoom ?? engine.zoom;
  final FractalPalette palette = bookmark?.palette ?? engine.palette;
  final String metadata =
      '${engine.tr(fractalType.translationKey)} · ${FractalEngine.formatZoom(zoom)} · ${engine.tr(palette.translationKey)}';

  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final String copyLabel = _trOr(engine, 'share_copy_link', 'Copy Link');
  final String copiedMsg =
      _trOr(engine, 'share_link_copied', 'Share link copied');
  final String shareLabel = _trOr(engine, 'share_link', 'Share Link');
  final String exportLabel =
      _trOr(engine, 'share_export_picture', 'Export Picture');

  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext sheetContext) {
      final ColorScheme scheme = Theme.of(sheetContext).colorScheme;
      final TextTheme textTheme = Theme.of(sheetContext).textTheme;

      return Material(
        color: scheme.surface.withValues(alpha: 0.96),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: MaterialLocalizations.of(sheetContext)
                          .closeButtonTooltip,
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: QrImageView(
                    data: shareUrl,
                    version: QrVersions.auto,
                    size: 184,
                    backgroundColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  metadata,
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: <Widget>[
                    FilledButton.tonalIcon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: shareUrl));
                        if (!sheetContext.mounted) return;
                        messenger
                          ..hideCurrentSnackBar()
                          ..showSnackBar(
                            SnackBar(
                              content: Text(copiedMsg),
                              behavior: SnackBarBehavior.floating,
                              duration: const Duration(seconds: 2),
                            ),
                          );
                      },
                      icon: const Icon(Icons.copy_rounded),
                      label: Text(copyLabel),
                    ),
                    FilledButton.icon(
                      onPressed: () async {
                        final RenderBox? box =
                            sheetContext.findRenderObject() as RenderBox?;
                        final Rect? origin = (box != null && box.hasSize)
                            ? box.localToGlobal(Offset.zero) & box.size
                            : null;
                        await Share.share(
                          '$title · $shareUrl',
                          sharePositionOrigin: origin,
                        );
                      },
                      icon: const Icon(Icons.share_rounded),
                      label: Text(shareLabel),
                    ),
                    if (onOpenExport != null)
                      FilledButton.tonalIcon(
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                          onOpenExport();
                        },
                        icon: const Icon(Icons.image_rounded),
                        label: Text(exportLabel),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
