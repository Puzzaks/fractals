import 'dart:async';
import 'dart:io' show Platform;
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'cpu_renderer.dart';

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
      cancellationToken?.removeListener(cancelListener);
      replyPort.close();
    }

    cancelListener = () {
      workers[workerId].sendPort.send(<Object>['cancel', jobId]);
      if (!completer.isCompleted) {
        cleanup();
        completer.completeError(const CpuRenderCancelledException());
      }
    };

    cancellationToken?.addListener(cancelListener);

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
        CpuFractalRenderer.renderRowRangeStatic(
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

_WorkerPool? _pool;
Future<_WorkerPool>? _poolFuture;
Timer? _idleTimer;
int _activeRenders = 0;
int _nextJobId = 0;

/// Maximum number of worker isolates to use for CPU rendering on native targets.
int get workerCount {
  try {
    return math.max(1, math.min(Platform.numberOfProcessors - 1, 7));
  } catch (_) {
    return 2;
  }
}

Future<_WorkerPool> _acquirePool(int count) async {
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
Future<void> disposeWorkerPool() async {
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

/// Dispatches [request] across [workers] persistent isolates and reassembles
/// the interleaved row strips into a contiguous RGBA8888 buffer.
Future<Uint8List> renderMultiIsolate(
  CpuRenderRequest request,
  int workers,
  int maxWorkers, {
  void Function(double progress)? onProgress,
  CpuRenderCancellationToken? cancellationToken,
}) async {
  final int w = math.max(1, request.width);
  final int h = math.max(1, request.height);

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
        disposeWorkerPool();
      });
    }
  }
}
