import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../engine/fractal_engine.dart';
import '../engine/fractal_models.dart';
import '../engine/fractal_share_link.dart';
import 'app_toast.dart';
import 'hud_overlay.dart';
import 'inspector_panel.dart' show showAddBookmarkDialog;

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
  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext sheetContext) {
      return _ShareFractalSheetContent(
        engine: engine,
        bookmark: bookmark,
        onOpenExport: onOpenExport,
      );
    },
  );
}

class _ShareFractalSheetContent extends StatefulWidget {
  final FractalEngine engine;
  final FractalBookmark? bookmark;
  final VoidCallback? onOpenExport;

  const _ShareFractalSheetContent({
    required this.engine,
    this.bookmark,
    this.onOpenExport,
  });

  @override
  State<_ShareFractalSheetContent> createState() =>
      _ShareFractalSheetContentState();
}

class _ShareFractalSheetContentState extends State<_ShareFractalSheetContent> {
  late final TextEditingController _nameController;
  bool _bookmarkAdded = false;

  @override
  void initState() {
    super.initState();
    final FractalEngine engine = widget.engine;
    final String initialName = widget.bookmark?.name ??
        '${engine.tr(engine.fractalType.translationKey)} (${FractalEngine.formatZoom(engine.zoom)})';
    _nameController = TextEditingController(text: initialName);
    _bookmarkAdded = engine.isCurrentViewBookmarked();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final FractalEngine engine = widget.engine;
    final FractalBookmark? bookmark = widget.bookmark;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;

    final String currentName = _nameController.text.trim();
    final String? rawPlayerName = engine.playGamesPlayerName;
    final String? author = engine.playGamesSignedIn &&
            rawPlayerName != null &&
            rawPlayerName.trim().isNotEmpty
        ? rawPlayerName.trim()
        : null;

    final Uri shareUri = bookmark != null
        ? FractalShareLink.encodeBookmark(
            bookmark,
            name: currentName.isNotEmpty ? currentName : null,
            author: author,
          )
        : FractalShareLink.encode(
            engine,
            name: currentName.isNotEmpty ? currentName : null,
            author: author,
          );
    final String shareUrl = shareUri.toString();

    final FractalType fractalType = bookmark?.fractalType ?? engine.fractalType;
    final double zoom = bookmark?.zoom ?? engine.zoom;
    final FractalPalette palette = bookmark?.palette ?? engine.palette;
    final String metadata =
        '${engine.tr(fractalType.translationKey)} · ${FractalEngine.formatZoom(zoom)} · ${engine.tr(palette.translationKey)}';

    final String title = _trOr(engine, 'share_title', 'Share Fractal');
    final String copyCoordsLabel =
        _trOr(engine, 'copy_coordinates', 'Copy Coordinates');
    final String shareLabel = _trOr(engine, 'share_link', 'Share Link');
    final String exportLabel =
        _trOr(engine, 'share_export_picture', 'Export Picture');
    final String bookmarkLabel =
        _trOr(engine, 'add_to_bookmarks', 'Add to Bookmarks');
    final String addedLabel = _trOr(engine, 'bookmark_added', 'Added');
    final String savedMsg =
        _trOr(engine, 'shared_preview_saved', 'Saved to bookmarks');
    final String nameFieldLabel =
        _trOr(engine, 'share_name_label', 'Fractal Name');

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Material(
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
                      tooltip: MaterialLocalizations.of(context)
                          .closeButtonTooltip,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _nameController,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: nameFieldLabel,
                    prefixIcon: const Icon(Icons.edit_rounded, size: 18),
                    border: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                    ),
                  ),
                  onChanged: (_) => setState(() {
                    _bookmarkAdded = false;
                  }),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      QrImageView(
                        data: shareUrl,
                        version: QrVersions.auto,
                        size: 184,
                        backgroundColor: Colors.white,
                      ),
                      if (currentName.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 8),
                        Text(
                          currentName,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleSmall?.copyWith(
                            color: Colors.black87,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      if (author != null) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          _trOr(
                            engine,
                            'share_shared_by',
                            'Shared by {author}',
                          ).replaceAll('{author}', author),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ],
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
                Material(
                  color: scheme.surfaceContainerHigh,
                  shape: const StadiumBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        IconButton(
                          tooltip: copyCoordsLabel,
                          iconSize: 28,
                          constraints: const BoxConstraints.tightFor(
                            width: 48,
                            height: 48,
                          ),
                          onPressed: () =>
                              copyFractalCoordinates(context, engine),
                          icon: const Icon(Icons.content_copy_rounded),
                        ),
                        IconButton(
                          tooltip: shareLabel,
                          iconSize: 28,
                          constraints: const BoxConstraints.tightFor(
                            width: 48,
                            height: 48,
                          ),
                          onPressed: () async {
                            final RenderBox? box =
                                context.findRenderObject() as RenderBox?;
                            final Rect? origin = (box != null && box.hasSize)
                                ? box.localToGlobal(Offset.zero) & box.size
                                : null;
                            final String shareText = currentName.isNotEmpty
                                ? '$currentName · $shareUrl'
                                : shareUrl;
                            await Share.share(
                              shareText,
                              sharePositionOrigin: origin,
                            );
                            engine.recordShareEvent();
                          },
                          icon: const Icon(Icons.share_rounded),
                        ),
                        IconButton(
                          tooltip: _bookmarkAdded ? addedLabel : bookmarkLabel,
                          iconSize: 28,
                          constraints: const BoxConstraints.tightFor(
                            width: 48,
                            height: 48,
                          ),
                          onPressed: () async {
                            if (_bookmarkAdded) {
                              showAppToast(
                                context,
                                _trOr(
                                  engine,
                                  'bookmark_already_saved',
                                  'Already saved to bookmarks',
                                ),
                              );
                              return;
                            }
                            if (currentName.isNotEmpty) {
                              engine.addCustomBookmark(currentName);
                              setState(() {
                                _bookmarkAdded = true;
                              });
                              if (!context.mounted) return;
                              showAppToast(context, savedMsg);
                            } else {
                              await showAddBookmarkDialog(context, engine);
                            }
                          },
                          icon: Icon(
                            _bookmarkAdded
                                ? Icons.bookmark_added_rounded
                                : Icons.bookmark_add_rounded,
                            color: _bookmarkAdded ? scheme.primary : null,
                          ),
                        ),
                        IconButton(
                          tooltip: exportLabel,
                          iconSize: 28,
                          constraints: const BoxConstraints.tightFor(
                            width: 48,
                            height: 48,
                          ),
                          onPressed: widget.onOpenExport == null
                              ? null
                              : () {
                                  Navigator.of(context).pop();
                                  widget.onOpenExport!();
                                },
                          icon: const Icon(Icons.image_rounded),
                        ),
                      ],
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
