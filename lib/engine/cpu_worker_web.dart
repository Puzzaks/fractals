import 'dart:typed_data';

import 'cpu_renderer.dart';

/// Web targets execute CPU rendering single-threaded without isolate pools.
int get workerCount => 1;

/// No-op on web since no persistent worker isolate pool is allocated.
Future<void> disposeWorkerPool() async {}

/// Single-threaded fallback for [CpuFractalRenderer] on web targets.
Future<Uint8List> renderMultiIsolate(
  CpuRenderRequest request,
  int workers,
  int maxWorkers, {
  void Function(double progress)? onProgress,
  CpuRenderCancellationToken? cancellationToken,
}) async {
  if (cancellationToken?.isCancelled == true) {
    throw const CpuRenderCancelledException();
  }
  final Uint8List result =
      CpuFractalRenderer.renderInterleavedStatic(request, 0, 1);
  if (cancellationToken?.isCancelled == true) {
    throw const CpuRenderCancelledException();
  }
  onProgress?.call(1.0);
  return result;
}
