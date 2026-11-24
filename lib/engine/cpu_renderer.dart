import 'dart:async';
import 'dart:io' show Platform;
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show MethodChannel;

/// Output container format for exported CPU fractal renders.
enum ExportImageFormat { png, jpeg }

/// Exception thrown when a CPU fractal render is cancelled via
/// [CpuRenderCancellationToken].
class CpuRenderCancelledException implements Exception {
  final String message;

  const CpuRenderCancelledException([this.message = 'CPU render cancelled']);

  @override
  String toString() => 'CpuRenderCancelledException: $message';
}

/// Cooperative cancellation token for [CpuFractalRenderer] operations.
class CpuRenderCancellationToken {
  bool _isCancelled = false;
  final List<void Function()> _listeners = <void Function()>[];

  bool get isCancelled => _isCancelled;

  void _addListener(void Function() cb) {
    if (_isCancelled) {
      cb();
      return;
    }
    _listeners.add(cb);
  }

  void _removeListener(void Function() cb) {
    _listeners.remove(cb);
  }

  /// Cancels the associated render (idempotent).
  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    final List<void Function()> snapshot = List<void Function()>.of(_listeners);
    _listeners.clear();
    for (final void Function() cb in snapshot) {
      cb();
    }
  }
}

/// Pure value object describing a single CPU float64 fractal render task.
class CpuRenderRequest {
  final int width;
  final int height;
  final double logicalWidth;
  final double logicalHeight;
  final double centerX;
  final double centerY;
  final double zoom;
  final int maxIterations;
  final int fractalTypeIndex;
  final double juliaCx;
  final double juliaCy;
  final int paletteIndex;
  final double primaryR;
  final double primaryG;
  final double primaryB;
  final double secondaryR;
  final double secondaryG;
  final double secondaryB;
  final double colorOffset;
  final bool smoothColor;
  final double rotCos;
  final double rotSin;

  const CpuRenderRequest({
    required this.width,
    required this.height,
    required this.logicalWidth,
    required this.logicalHeight,
    required this.centerX,
    required this.centerY,
    required this.zoom,
    required this.maxIterations,
    required this.fractalTypeIndex,
    required this.juliaCx,
    required this.juliaCy,
    required this.paletteIndex,
    required this.primaryR,
    required this.primaryG,
    required this.primaryB,
    required this.secondaryR,
    required this.secondaryG,
    required this.secondaryB,
    required this.colorOffset,
    required this.smoothColor,
    this.rotCos = 1.0,
    this.rotSin = 0.0,
  });
}

class _WorkerHandle {
  final Isolate isolate;
  final SendPort sendPort;

  const _WorkerHandle(this.isolate, this.sendPort);
}

class _WorkerPool {
  final List<_WorkerHandle> workers;

  _WorkerPool(this.workers);

  static Future<_WorkerPool> spawn(int count) async {
    final List<_WorkerHandle> handles = await Future.wait(
      List<Future<_WorkerHandle>>.generate(count, (_) => _spawnOne()),
    );
    return _WorkerPool(handles);
  }

  static Future<_WorkerHandle> _spawnOne() async {
    final ReceivePort initPort = ReceivePort();
    final Isolate isolate = await Isolate.spawn(_workerMain, initPort.sendPort);
    final SendPort sendPort = await initPort.first as SendPort;
    initPort.close();
    return _WorkerHandle(isolate, sendPort);
  }

  void cancelJob(int jobId) {
    for (final _WorkerHandle handle in workers) {
      handle.sendPort.send(<Object>['cancel', jobId]);
    }
  }

  Future<Uint8List> dispatch(
    int jobId,
    int workerId,
    CpuRenderRequest req,
    int workerCount, {
    void Function(int batchRows)? onBatchProgress,
    CpuRenderCancellationToken? cancellationToken,
  }) {
    if (cancellationToken?.isCancelled == true) {
      return Future<Uint8List>.error(const CpuRenderCancelledException());
    }
    final ReceivePort replyPort = ReceivePort();
    final Completer<Uint8List> completer = Completer<Uint8List>();
    late final void Function() cancelListener;

    void cleanup() {
      cancellationToken?._removeListener(cancelListener);
      replyPort.close();
    }

    cancelListener = () {
      workers[workerId].sendPort.send(<Object>['cancel', jobId]);
      if (!completer.isCompleted) {
        cleanup();
        completer.completeError(const CpuRenderCancelledException());
      }
    };

    cancellationToken?._addListener(cancelListener);

    replyPort.listen((dynamic message) {
      if (message is List && message.length == 2 && message[0] == 'progress') {
        if (!completer.isCompleted && message[1] is int) {
          onBatchProgress?.call(message[1]! as int);
        }
        return;
      }

      cleanup();
      if (completer.isCompleted) return;
      if (message is TransferableTypedData) {
        completer.complete(message.materialize().asUint8List());
      } else if (message is Uint8List) {
        completer.complete(message);
      } else if (message is List &&
          message.isNotEmpty &&
          message[0] == 'cancelled') {
        completer.completeError(const CpuRenderCancelledException());
      } else if (message is List && message.length == 2 && message[0] == 'error') {
        completer.completeError(StateError(message[1].toString()));
      } else {
        completer.completeError(StateError('Unexpected worker reply: $message'));
      }
    });
    workers[workerId].sendPort.send(
      <Object>['render', jobId, req, workerId, workerCount, replyPort.sendPort],
    );
    return completer.future;
  }

  void dispose() {
    for (final _WorkerHandle handle in workers) {
      handle.sendPort.send(null);
      handle.isolate.kill(priority: Isolate.beforeNextEvent);
    }
  }
}

void _workerMain(SendPort mainSendPort) {
  final ReceivePort inbox = ReceivePort();
  mainSendPort.send(inbox.sendPort);
  final Set<int> cancelledJobs = <int>{};
  const int batchRows = 16;

  inbox.listen((dynamic message) {
    if (message == null) {
      inbox.close();
      return;
    }
    if (message is! List<Object?> || message.isEmpty) return;
    final Object? kind = message[0];
    if (kind == 'cancel') {
      if (message.length >= 2 && message[1] is int) {
        cancelledJobs.add(message[1]! as int);
        if (cancelledJobs.length > 64) {
          cancelledJobs.remove(cancelledJobs.first);
        }
      }
      return;
    }
    if (kind != 'render' || message.length < 6) return;

    final int jobId = message[1]! as int;
    final CpuRenderRequest req = message[2]! as CpuRenderRequest;
    final int workerId = message[3]! as int;
    final int workerCount = message[4]! as int;
    final SendPort replyPort = message[5]! as SendPort;

    if (cancelledJobs.remove(jobId)) {
      replyPort.send(<Object>['cancelled']);
      return;
    }

    final int w = math.max(1, req.width);
    final int h = math.max(1, req.height);
    final int rows =
        workerId < h ? ((h - 1 - workerId) ~/ workerCount) + 1 : 0;
    final Uint8List rgba = Uint8List(w * rows * 4);

    if (rows == 0) {
      replyPort.send(TransferableTypedData.fromList(<Uint8List>[rgba]));
      return;
    }

    int nextRowIndex = 0;

    void runBatch() {
      if (cancelledJobs.remove(jobId)) {
        replyPort.send(<Object>['cancelled']);
        return;
      }
      try {
        final int endRowIndex = math.min(nextRowIndex + batchRows, rows);
        final int batchCount = endRowIndex - nextRowIndex;
        CpuFractalRenderer._renderRowRange(
          req,
          workerId,
          workerCount,
          nextRowIndex,
          endRowIndex,
          rgba,
        );
        nextRowIndex = endRowIndex;
        replyPort.send(<Object>['progress', batchCount]);
        if (nextRowIndex < rows) {
          Timer.run(runBatch);
        } else {
          replyPort.send(TransferableTypedData.fromList(<Uint8List>[rgba]));
        }
      } catch (e) {
        replyPort.send(<Object>['error', e.toString()]);
      }
    }

    Timer.run(runBatch);
  });
}

/// Multi-isolate CPU `float64` fractal renderer with exact parity to
/// `shaders/fractal.frag` (supports ultra-deep zoom beyond GPU float32/df64
/// limits and high-resolution offline PNG export).
class CpuFractalRenderer {
  const CpuFractalRenderer._();

  static _WorkerPool? _pool;
  static Future<_WorkerPool>? _poolFuture;
  static Timer? _idleTimer;
  static int _activeRenders = 0;
  static int _nextJobId = 0;

  static int get _workerCount {
    if (kIsWeb) return 1;
    try {
      return math.max(1, math.min(Platform.numberOfProcessors - 1, 7));
    } catch (_) {
      return 2;
    }
  }

  static Future<_WorkerPool> _acquirePool(int count) async {
    final _WorkerPool? existing = _pool;
    if (existing != null && existing.workers.length >= count) {
      return existing;
    }
    if (_poolFuture != null) {
      final _WorkerPool pending = await _poolFuture!;
      if (pending.workers.length >= count) {
        return pending;
      }
    }
    final Future<_WorkerPool> spawning = _WorkerPool.spawn(count);
    _poolFuture = spawning;
    try {
      final _WorkerPool spawned = await spawning;
      _pool = spawned;
      return spawned;
    } finally {
      if (identical(_poolFuture, spawning)) {
        _poolFuture = null;
      }
    }
  }

  /// Disposes the persistent worker isolate pool, if active.
  static Future<void> disposePool() async {
    _idleTimer?.cancel();
    _idleTimer = null;
    final Future<_WorkerPool>? pending = _poolFuture;
    _poolFuture = null;
    if (pending != null) {
      try {
        final _WorkerPool spawned = await pending;
        spawned.dispose();
      } catch (_) {}
    }
    final _WorkerPool? current = _pool;
    _pool = null;
    current?.dispose();
  }

  /// Renders [request] across parallel isolates into raw RGBA8888 pixels and
  /// decodes into a GPU-uploadable [ui.Image].
  static Future<ui.Image> renderImage(
    CpuRenderRequest request, {
    void Function(double progress)? onProgress,
    CpuRenderCancellationToken? cancellationToken,
  }) async {
    if (cancellationToken?.isCancelled == true) {
      throw const CpuRenderCancelledException();
    }
    final Uint8List rgba = await renderRgba(
      request,
      onProgress: onProgress,
      cancellationToken: cancellationToken,
    );
    if (cancellationToken?.isCancelled == true) {
      throw const CpuRenderCancelledException();
    }
    final Completer<ui.Image> completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      request.width,
      request.height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  /// Renders [request] into raw RGBA8888 bytes and encodes a PNG byte buffer.
  static Future<Uint8List?> renderPngBytes(
    CpuRenderRequest request, {
    void Function(double progress)? onProgress,
    CpuRenderCancellationToken? cancellationToken,
  }) async {
    if (cancellationToken?.isCancelled == true) {
      throw const CpuRenderCancelledException();
    }
    final ui.Image image = await renderImage(
      request,
      onProgress: onProgress == null
          ? null
          : (double p) => onProgress((p * 0.92).clamp(0.0, 0.92)),
      cancellationToken: cancellationToken,
    );
    try {
      if (cancellationToken?.isCancelled == true) {
        throw const CpuRenderCancelledException();
      }
      onProgress?.call(0.95);
      final ByteData? data =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (cancellationToken?.isCancelled == true) {
        throw const CpuRenderCancelledException();
      }
      onProgress?.call(1.0);
      return data?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  /// Renders [request] and encodes it in the requested [format] (PNG or JPEG).
  ///
  /// On Android, JPEG encoding uses the native `page.puzzak.fractals/display`
  /// platform channel; other platforms fall back to PNG bytes.
  static Future<Uint8List?> renderEncodedImageBytes(
    CpuRenderRequest request, {
    ExportImageFormat format = ExportImageFormat.png,
    int jpegQuality = 92,
    void Function(double progress)? onProgress,
    CpuRenderCancellationToken? cancellationToken,
  }) async {
    final Uint8List? pngBytes = await renderPngBytes(
      request,
      onProgress: format == ExportImageFormat.jpeg
          ? (double p) => onProgress?.call(p * 0.92)
          : onProgress,
      cancellationToken: cancellationToken,
    );
    if (pngBytes == null || format == ExportImageFormat.png) {
      return pngBytes;
    }
    if (format == ExportImageFormat.jpeg && !kIsWeb && Platform.isAndroid) {
      try {
        final Uint8List? jpegBytes =
            await const MethodChannel('page.puzzak.fractals/display')
                .invokeMethod<Uint8List>(
          'encodeJpeg',
          <String, Object>{
            'pngBytes': pngBytes,
            'quality': jpegQuality.clamp(50, 100),
          },
        );
        onProgress?.call(1.0);
        return jpegBytes ?? pngBytes;
      } catch (_) {
        onProgress?.call(1.0);
        return pngBytes;
      }
    }
    return pngBytes;
  }

  /// Renders [request] in a center-outward grid of tiles, emitting incremental
  /// downsampled preview images via [onPreviewTile] after each tile completes,
  /// then encodes the assembled full-resolution buffer as PNG or JPEG.
  static Future<Uint8List?> renderTiledEncodedImageBytes(
    CpuRenderRequest request, {
    ExportImageFormat format = ExportImageFormat.png,
    int jpegQuality = 92,
    void Function(double progress)? onProgress,
    void Function(ui.Image previewImage)? onPreviewTile,
    CpuRenderCancellationToken? cancellationToken,
  }) async {
    if (cancellationToken?.isCancelled == true) {
      throw const CpuRenderCancelledException();
    }
    if (request.width < 128 ||
        request.height < 128 ||
        onPreviewTile == null) {
      return renderEncodedImageBytes(
        request,
        format: format,
        jpegQuality: jpegQuality,
        onProgress: onProgress,
        cancellationToken: cancellationToken,
      );
    }

    final int cols = request.width >= 3000 ? 5 : 4;
    final int rows = request.height >= 3000 ? 5 : 4;
    final Uint8List fullRgba = Uint8List(request.width * request.height * 4);

    final int maxDim = math.max(request.width, request.height);
    final double previewScale = maxDim > 720 ? 720.0 / maxDim : 1.0;
    final int previewW = math.max(1, (request.width * previewScale).round());
    final int previewH = math.max(1, (request.height * previewScale).round());
    final Uint8List previewRgba = Uint8List(previewW * previewH * 4);
    for (int i = 0; i < previewRgba.length; i += 4) {
      previewRgba[i] = 10;
      previewRgba[i + 1] = 14;
      previewRgba[i + 2] = 20;
      previewRgba[i + 3] = 255;
    }

    final double gridCenterC = (cols - 1) * 0.5;
    final double gridCenterR = (rows - 1) * 0.5;
    final List<({int c, int r, int x0, int y0, int w, int h, double distSq, double angle})>
        tiles =
        <({int c, int r, int x0, int y0, int w, int h, double distSq, double angle})>[];

    for (int r = 0; r < rows; r++) {
      final int y0 = (r * request.height) ~/ rows;
      final int y1 = ((r + 1) * request.height) ~/ rows;
      final int tileH = y1 - y0;
      for (int c = 0; c < cols; c++) {
        final int x0 = (c * request.width) ~/ cols;
        final int x1 = ((c + 1) * request.width) ~/ cols;
        final int tileW = x1 - x0;
        final double dc = c - gridCenterC;
        final double dr = r - gridCenterR;
        tiles.add((
          c: c,
          r: r,
          x0: x0,
          y0: y0,
          w: tileW,
          h: tileH,
          distSq: dc * dc + dr * dr,
          angle: math.atan2(dr, dc),
        ));
      }
    }

    tiles.sort((a, b) {
      final int distCmp = a.distSq.compareTo(b.distSq);
      if (distCmp != 0) return distCmp;
      return a.angle.compareTo(b.angle);
    });

    final int totalTiles = tiles.length;
    final int fullStride = request.width * 4;
    final int previewStride = previewW * 4;
    int completedTiles = 0;

    for (final tile in tiles) {
      if (cancellationToken?.isCancelled == true) {
        throw const CpuRenderCancelledException();
      }

      final double tileCenterPxX =
          tile.x0 + tile.w * 0.5 - request.width * 0.5;
      final double tileCenterPxY =
          tile.y0 + tile.h * 0.5 - request.height * 0.5;
      final double dxLogical =
          tileCenterPxX * (request.logicalWidth / request.width);
      final double dyLogical =
          tileCenterPxY * (request.logicalHeight / request.height);
      final double rx =
          dxLogical * request.rotCos - dyLogical * request.rotSin;
      final double ry =
          dxLogical * request.rotSin + dyLogical * request.rotCos;
      final double tileCenterX = request.centerX + rx / request.zoom;
      final double tileCenterY = request.centerY + ry / request.zoom;
      final double tileLogicalW =
          request.logicalWidth * (tile.w / request.width);
      final double tileLogicalH =
          request.logicalHeight * (tile.h / request.height);

      final CpuRenderRequest tileReq = CpuRenderRequest(
        width: tile.w,
        height: tile.h,
        logicalWidth: tileLogicalW,
        logicalHeight: tileLogicalH,
        centerX: tileCenterX,
        centerY: tileCenterY,
        zoom: request.zoom,
        maxIterations: request.maxIterations,
        fractalTypeIndex: request.fractalTypeIndex,
        juliaCx: request.juliaCx,
        juliaCy: request.juliaCy,
        paletteIndex: request.paletteIndex,
        primaryR: request.primaryR,
        primaryG: request.primaryG,
        primaryB: request.primaryB,
        secondaryR: request.secondaryR,
        secondaryG: request.secondaryG,
        secondaryB: request.secondaryB,
        colorOffset: request.colorOffset,
        smoothColor: request.smoothColor,
        rotCos: request.rotCos,
        rotSin: request.rotSin,
      );

      final Uint8List tileRgba = await renderRgba(
        tileReq,
        cancellationToken: cancellationToken,
      );
      if (cancellationToken?.isCancelled == true) {
        throw const CpuRenderCancelledException();
      }

      final int tileRowBytes = tile.w * 4;
      for (int row = 0; row < tile.h; row++) {
        final int srcStart = row * tileRowBytes;
        final int dstStart = (tile.y0 + row) * fullStride + tile.x0 * 4;
        fullRgba.setRange(dstStart, dstStart + tileRowBytes, tileRgba, srcStart);
      }

      final int px0 = (tile.x0 * previewW) ~/ request.width;
      final int px1 = math
          .max(px0 + 1, ((tile.x0 + tile.w) * previewW) ~/ request.width)
          .clamp(0, previewW);
      final int py0 = (tile.y0 * previewH) ~/ request.height;
      final int py1 = math
          .max(py0 + 1, ((tile.y0 + tile.h) * previewH) ~/ request.height)
          .clamp(0, previewH);

      for (int py = py0; py < py1; py++) {
        final int srcY =
            (((py + 0.5) * request.height / previewH).floor() - tile.y0)
                .clamp(0, tile.h - 1);
        final int srcRowOffset = srcY * tileRowBytes;
        final int dstRowOffset = py * previewStride;
        for (int px = px0; px < px1; px++) {
          final int srcX =
              (((px + 0.5) * request.width / previewW).floor() - tile.x0)
                  .clamp(0, tile.w - 1);
          final int srcIdx = srcRowOffset + srcX * 4;
          final int dstIdx = dstRowOffset + px * 4;
          previewRgba[dstIdx] = tileRgba[srcIdx];
          previewRgba[dstIdx + 1] = tileRgba[srcIdx + 1];
          previewRgba[dstIdx + 2] = tileRgba[srcIdx + 2];
          previewRgba[dstIdx + 3] = tileRgba[srcIdx + 3];
        }
      }

      completedTiles++;
      onProgress?.call((completedTiles / totalTiles) * 0.90);

      final Completer<ui.Image> previewCompleter = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        Uint8List.fromList(previewRgba),
        previewW,
        previewH,
        ui.PixelFormat.rgba8888,
        previewCompleter.complete,
      );
      final ui.Image previewImage = await previewCompleter.future;
      if (cancellationToken?.isCancelled == true) {
        previewImage.dispose();
        throw const CpuRenderCancelledException();
      }
      onPreviewTile(previewImage);
    }

    if (cancellationToken?.isCancelled == true) {
      throw const CpuRenderCancelledException();
    }
    onProgress?.call(0.94);

    final Completer<ui.Image> fullCompleter = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      fullRgba,
      request.width,
      request.height,
      ui.PixelFormat.rgba8888,
      fullCompleter.complete,
    );
    final ui.Image fullImage = await fullCompleter.future;
    final Uint8List? pngBytes;
    try {
      if (cancellationToken?.isCancelled == true) {
        throw const CpuRenderCancelledException();
      }
      final ByteData? data =
          await fullImage.toByteData(format: ui.ImageByteFormat.png);
      pngBytes = data?.buffer.asUint8List();
    } finally {
      fullImage.dispose();
    }

    if (cancellationToken?.isCancelled == true) {
      throw const CpuRenderCancelledException();
    }
    if (pngBytes == null || format == ExportImageFormat.png) {
      onProgress?.call(1.0);
      return pngBytes;
    }

    if (format == ExportImageFormat.jpeg && !kIsWeb && Platform.isAndroid) {
      try {
        final Uint8List? jpegBytes =
            await const MethodChannel('page.puzzak.fractals/display')
                .invokeMethod<Uint8List>(
          'encodeJpeg',
          <String, Object>{
            'pngBytes': pngBytes,
            'quality': jpegQuality.clamp(50, 100),
          },
        );
        onProgress?.call(1.0);
        return jpegBytes ?? pngBytes;
      } catch (_) {
        onProgress?.call(1.0);
        return pngBytes;
      }
    }

    onProgress?.call(1.0);
    return pngBytes;
  }

  /// Computes raw RGBA8888 pixel bytes across parallel worker isolates.
  static Future<Uint8List> renderRgba(
    CpuRenderRequest request, {
    void Function(double progress)? onProgress,
    CpuRenderCancellationToken? cancellationToken,
  }) async {
    if (cancellationToken?.isCancelled == true) {
      throw const CpuRenderCancelledException();
    }
    final int w = math.max(1, request.width);
    final int h = math.max(1, request.height);
    final int maxWorkers = _workerCount;
    final int workers = math.min(maxWorkers, h);

    if (kIsWeb || workers <= 1 || w * h < 20000) {
      final Uint8List result = _renderInterleaved(request, 0, 1);
      if (cancellationToken?.isCancelled == true) {
        throw const CpuRenderCancelledException();
      }
      onProgress?.call(1.0);
      return result;
    }

    _activeRenders++;
    _idleTimer?.cancel();
    try {
      final _WorkerPool pool = await _acquirePool(maxWorkers);
      if (cancellationToken?.isCancelled == true) {
        throw const CpuRenderCancelledException();
      }
      final int jobId = ++_nextJobId;
      int completedRows = 0;
      double lastReportedProgress = -1.0;

      void handleBatchProgress(int batchRows) {
        if (onProgress == null) return;
        completedRows += batchRows;
        final double progress = (completedRows / h).clamp(0.0, 1.0);
        if (progress >= 1.0 ||
            lastReportedProgress < 0.0 ||
            progress - lastReportedProgress >= 0.02) {
          lastReportedProgress = progress;
          onProgress(progress);
        }
      }

      final List<Future<Uint8List>> futures = List<Future<Uint8List>>.generate(
        workers,
        (int workerId) => pool.dispatch(
          jobId,
          workerId,
          request,
          workers,
          onBatchProgress: handleBatchProgress,
          cancellationToken: cancellationToken,
        ),
      );

      final List<Uint8List> strips = await Future.wait(futures);
      if (cancellationToken?.isCancelled == true) {
        pool.cancelJob(jobId);
        throw const CpuRenderCancelledException();
      }
      final Uint8List output = Uint8List(w * h * 4);
      final int rowBytes = w * 4;
      for (int workerId = 0; workerId < workers; workerId++) {
        final Uint8List strip = strips[workerId];
        final int rowCount = strip.length ~/ rowBytes;
        for (int r = 0; r < rowCount; r++) {
          final int dstY = workerId + r * workers;
          final int dstOffset = dstY * rowBytes;
          final int srcOffset = r * rowBytes;
          output.setRange(dstOffset, dstOffset + rowBytes, strip, srcOffset);
        }
      }
      if (lastReportedProgress < 1.0) {
        onProgress?.call(1.0);
      }
      return output;
    } finally {
      _activeRenders--;
      if (_activeRenders == 0) {
        _idleTimer?.cancel();
        _idleTimer = Timer(const Duration(seconds: 10), () {
          disposePool();
        });
      }
    }
  }

  static Uint8List _renderInterleaved(
    CpuRenderRequest req,
    int workerId,
    int workerCount,
  ) {
    final int w = math.max(1, req.width);
    final int h = math.max(1, req.height);
    final int rows =
        workerId < h ? ((h - 1 - workerId) ~/ workerCount) + 1 : 0;
    final Uint8List rgba = Uint8List(w * rows * 4);
    _renderRowRange(req, workerId, workerCount, 0, rows, rgba);
    return rgba;
  }

  static void _renderRowRange(
    CpuRenderRequest req,
    int workerId,
    int workerCount,
    int startRowIndex,
    int endRowIndex,
    Uint8List rgba,
  ) {
    final int w = math.max(1, req.width);
    final int h = math.max(1, req.height);
    final double halfLogicalW = req.logicalWidth * 0.5;
    final double halfLogicalH = req.logicalHeight * 0.5;
    final double scaleX = req.logicalWidth / w;
    final double scaleY = req.logicalHeight / h;
    final double invZoom = 1.0 / req.zoom;
    final double escapeR2 = req.smoothColor ? 256.0 : 4.0;
    final double ln2 = math.ln2;
    final int maxIter = req.maxIterations.clamp(1, 5000);
    final int fType = req.fractalTypeIndex;
    final int pal = req.paletteIndex;

    int outIdx = startRowIndex * w * 4;
    for (int r = startRowIndex; r < endRowIndex; r++) {
      final int y = workerId + r * workerCount;
      final double fragY = (y + 0.5) * scaleY;
      final double dy = fragY - halfLogicalH;

      for (int x = 0; x < w; x++) {
        final double fragX = (x + 0.5) * scaleX;
        final double dx = fragX - halfLogicalW;
        final double rx = dx * req.rotCos - dy * req.rotSin;
        final double ry = dx * req.rotSin + dy * req.rotCos;
        final double cx = req.centerX + rx * invZoom;
        final double cy = req.centerY + ry * invZoom;

        // Cardioid & period-2 bulb early bailout for Mandelbrot
        if (fType == 0) {
          final double cy2 = cy * cy;
          final double xMinus = cx - 0.25;
          final double q = xMinus * xMinus + cy2;
          if (q * (q + xMinus) <= 0.25 * cy2) {
            rgba[outIdx++] = 0;
            rgba[outIdx++] = 0;
            rgba[outIdx++] = 0;
            rgba[outIdx++] = 255;
            continue;
          }
          final double xPlus1 = cx + 1.0;
          if (xPlus1 * xPlus1 + cy2 <= 0.0625) {
            rgba[outIdx++] = 0;
            rgba[outIdx++] = 0;
            rgba[outIdx++] = 0;
            rgba[outIdx++] = 255;
            continue;
          }
        }

        double zx = 0.0;
        double zy = 0.0;
        double px = cx;
        double py = cy;
        if (fType == 1) {
          zx = cx;
          zy = cy;
          px = req.juliaCx;
          py = req.juliaCy;
        }

        int escapedIter = -1;
        double mag2 = 0.0;
        final double zxFactor = fType == 3 ? -2.0 : 2.0;

        double ox = 0.0;
        double oy = 0.0;
        int period = 8;
        int steps = 0;

        for (int i = 0; i < maxIter; i++) {
          if (fType == 2) {
            if (zx < 0) zx = -zx;
            if (zy < 0) zy = -zy;
          }
          final double zx2 = zx * zx;
          final double zy2 = zy * zy;
          mag2 = zx2 + zy2;
          if (mag2 > escapeR2) {
            escapedIter = i;
            break;
          }
          if (fType == 4) {
            final double nextZx = zx * (zx2 - 3.0 * zy2) + px;
            final double nextZy = zy * (3.0 * zx2 - zy2) + py;
            zx = nextZx;
            zy = nextZy;
          } else if (fType == 5) {
            final double nextZy = 2.0 * zx * zy + py;
            zx = (zx2 - zy2).abs() + px;
            zy = nextZy;
          } else {
            final double nextZy = zxFactor * zx * zy + py;
            zx = zx2 - zy2 + px;
            zy = nextZy;
          }

          if (fType == 0) {
            if ((zx - ox).abs() + (zy - oy).abs() < 1e-13) {
              escapedIter = -1;
              break;
            }
            steps++;
            if (steps >= period) {
              ox = zx;
              oy = zy;
              period *= 2;
              steps = 0;
            }
          }
        }

        if (escapedIter < 0) {
          rgba[outIdx++] = 0;
          rgba[outIdx++] = 0;
          rgba[outIdx++] = 0;
          rgba[outIdx++] = 255;
          continue;
        }

        double nu = escapedIter.toDouble();
        if (req.smoothColor) {
          final double logZn = math.log(math.max(mag2, 1.0001)) * 0.5;
          final double degreeLog = fType == 4 ? math.log(3.0) : ln2;
          nu = escapedIter +
              1.0 -
              math.log(math.max(logZn / ln2, 1e-6)) / degreeLog;
        }
        final double phase = nu * 0.032 + req.colorOffset;
        final (int r, int g, int b) = _samplePalette(
          phase,
          pal,
          req.primaryR,
          req.primaryG,
          req.primaryB,
          req.secondaryR,
          req.secondaryG,
          req.secondaryB,
        );
        rgba[outIdx++] = r;
        rgba[outIdx++] = g;
        rgba[outIdx++] = b;
        rgba[outIdx++] = 255;
      }
    }
  }

  static double _fract(double x) => x - x.floorToDouble();

  static double _smoothstep(double x) {
    final double t = x.clamp(0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
  }

  static (int, int, int) _cyclicGradient(
    double t,
    double r0,
    double g0,
    double b0,
    double r1,
    double g1,
    double b1,
    double r2,
    double g2,
    double b2,
    double r3,
    double g3,
    double b3,
  ) {
    final double x = _fract(t) * 4.0;
    final int idx = x.floor();
    final double f = _smoothstep(_fract(x));

    double sr, sg, sb;
    switch (idx) {
      case 0:
        sr = r0 + (r1 - r0) * f;
        sg = g0 + (g1 - g0) * f;
        sb = b0 + (b1 - b0) * f;
      case 1:
        sr = r1 + (r2 - r1) * f;
        sg = g1 + (g2 - g1) * f;
        sb = b1 + (b2 - b1) * f;
      case 2:
        sr = r2 + (r3 - r2) * f;
        sg = g2 + (g3 - g2) * f;
        sb = b2 + (b3 - b2) * f;
      default:
        sr = r3 + (r0 - r3) * f;
        sg = g3 + (g0 - g3) * f;
        sb = b3 + (b0 - b3) * f;
    }
    return (
      (sr * 255.0).round().clamp(0, 255),
      (sg * 255.0).round().clamp(0, 255),
      (sb * 255.0).round().clamp(0, 255),
    );
  }

  static (int, int, int) _samplePalette(
    double t,
    int pal,
    double pR,
    double pG,
    double pB,
    double sR,
    double sG,
    double sB,
  ) {
    switch (pal) {
      case 0:
        return _cyclicGradient(
          t,
          pR * 0.16,
          pG * 0.16,
          pB * 0.16,
          pR,
          pG,
          pB,
          sR + (1.0 - sR) * 0.35,
          sG + (1.0 - sG) * 0.35,
          sB + (1.0 - sB) * 0.35,
          sR * 0.85,
          sG * 0.85,
          sB * 0.85,
        );
      case 1:
        return _cyclicGradient(
          t,
          0.04,
          0.02,
          0.10,
          0.52,
          0.11,
          0.42,
          0.93,
          0.41,
          0.13,
          0.99,
          0.96,
          0.64,
        );
      case 2:
        return _cyclicGradient(
          t,
          0.16,
          0.04,
          0.33,
          0.17,
          0.42,
          0.56,
          0.15,
          0.68,
          0.51,
          0.92,
          0.90,
          0.18,
        );
      case 3:
        return _cyclicGradient(
          t,
          0.01,
          0.06,
          0.18,
          0.04,
          0.36,
          0.68,
          0.18,
          0.82,
          0.88,
          0.88,
          0.97,
          1.00,
        );
      case 4:
        const double tau = 6.283185307179586;
        final double r = 0.5 + 0.5 * math.cos(tau * (t + 0.0));
        final double g = 0.5 + 0.5 * math.cos(tau * (t + 0.33));
        final double b = 0.5 + 0.5 * math.cos(tau * (t + 0.67));
        return (
          (r * 255.0).round().clamp(0, 255),
          (g * 255.0).round().clamp(0, 255),
          (b * 255.0).round().clamp(0, 255),
        );
      case 5:
        const double tau = 6.283185307179586;
        final double lum = 0.5 - 0.5 * math.cos(tau * t);
        return (
          (lum * 0.94 * 255.0).round().clamp(0, 255),
          (lum * 0.96 * 255.0).round().clamp(0, 255),
          (lum * 255.0).round().clamp(0, 255),
        );
      case 6:
        return _cyclicGradient(
          t,
          0.08,
          0.05,
          0.22,
          0.49,
          0.22,
          0.60,
          0.92,
          0.48,
          0.50,
          0.96,
          0.84,
          0.65,
        );
      default:
        return _cyclicGradient(
          t,
          0.00,
          0.34,
          0.72,
          0.12,
          0.53,
          0.90,
          1.00,
          0.84,
          0.00,
          1.00,
          0.96,
          0.62,
        );
    }
  }
}
