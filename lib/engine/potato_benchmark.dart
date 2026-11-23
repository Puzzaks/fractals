import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'cpu_renderer.dart';
import 'fractal_models.dart';

/// Persistent hardware benchmark result produced by [PotatoBenchmarkRunner].
class PotatoBenchmarkResult {
  final int score;
  final String tier;
  final double gpuF32MIterPerSec;
  final double gpuDf64MIterPerSec;
  final double cpuF64MIterPerSec;
  final double kGpuF32;
  final double kGpuDf64;
  final double kCpuF64;
  final int completedAtMs;

  const PotatoBenchmarkResult({
    required this.score,
    required this.tier,
    required this.gpuF32MIterPerSec,
    required this.gpuDf64MIterPerSec,
    required this.cpuF64MIterPerSec,
    required this.kGpuF32,
    required this.kGpuDf64,
    required this.kCpuF64,
    required this.completedAtMs,
  });

  /// Maps a composite [score] to a Potatoemeter hardware tier name.
  static String tierForScore(int score) {
    if (score < 100) return 'Raw Spud';
    if (score < 250) return 'Baked Potato';
    if (score < 500) return 'Loaded Fries';
    if (score < 900) return 'Golden Hashbrown';
    if (score < 1500) return 'Turbo Tater';
    return 'Quantum Yam';
  }

  /// Computes the composite Potatoemeter score from per-backend throughput.
  static int computeScore({
    required double gpuF32MIter,
    required double gpuDf64MIter,
    required double cpuF64MIter,
  }) {
    return (gpuF32MIter * 0.08 + gpuDf64MIter * 1.5 + cpuF64MIter * 1.0)
        .round()
        .clamp(1, 99999);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'score': score,
        'tier': tier,
        'gpuF32MIterPerSec': gpuF32MIterPerSec,
        'gpuDf64MIterPerSec': gpuDf64MIterPerSec,
        'cpuF64MIterPerSec': cpuF64MIterPerSec,
        'kGpuF32': kGpuF32,
        'kGpuDf64': kGpuDf64,
        'kCpuF64': kCpuF64,
        'completedAtMs': completedAtMs,
      };

  factory PotatoBenchmarkResult.fromJson(Map<String, dynamic> json) {
    final double gpuF32 =
        (json['gpuF32MIterPerSec'] as num?)?.toDouble() ?? 0.0;
    final double gpuDf64 =
        (json['gpuDf64MIterPerSec'] as num?)?.toDouble() ?? 0.0;
    final double cpuF64 =
        (json['cpuF64MIterPerSec'] as num?)?.toDouble() ?? 0.0;
    final int score = (json['score'] as num?)?.toInt() ??
        computeScore(
          gpuF32MIter: gpuF32,
          gpuDf64MIter: gpuDf64,
          cpuF64MIter: cpuF64,
        );
    final String tier =
        json['tier']?.toString().trim().isNotEmpty == true
            ? json['tier'].toString()
            : tierForScore(score);
    return PotatoBenchmarkResult(
      score: score,
      tier: tier,
      gpuF32MIterPerSec: gpuF32,
      gpuDf64MIterPerSec: gpuDf64,
      cpuF64MIterPerSec: cpuF64,
      kGpuF32: (json['kGpuF32'] as num?)?.toDouble() ?? 1.5e-8,
      kGpuDf64: (json['kGpuDf64'] as num?)?.toDouble() ?? 1.2e-6,
      kCpuF64: (json['kCpuF64'] as num?)?.toDouble() ?? 5.0e-6,
      completedAtMs: (json['completedAtMs'] as num?)?.toInt() ?? 0,
    );
  }

  /// Formats a concise plain-text summary suitable for clipboard sharing.
  String toShareSummary() {
    return 'Potatoemeter: $score ($tier) | '
        'GPU f32: ${gpuF32MIterPerSec.toStringAsFixed(1)} MIter/s | '
        'GPU df64: ${gpuDf64MIterPerSec.toStringAsFixed(1)} MIter/s | '
        'CPU f64: ${cpuF64MIterPerSec.toStringAsFixed(1)} MIter/s';
  }

  @override
  String toString() => jsonEncode(toJson());
}

/// Runs the standardized 3-stage Potatoemeter hardware benchmark against a
/// fixed Seahorse-boundary Mandelbrot scene.
class PotatoBenchmarkRunner {
  const PotatoBenchmarkRunner._();

  static const double centerX = -0.743643887;
  static const double centerY = 0.131825904;
  static const double zoom = 12000.0;
  static const int _gpuF32Size = 1024;
  static const int _gpuF32MaxIter = 1000;
  static const int _gpuF32Palette = 3;
  static const int _gpuF32WarmupRuns = 2;
  static const int _gpuF32TimedRuns = 5;

  static const int _gpuDf64Size = 768;
  static const int _gpuDf64MaxIter = 800;
  static const int _gpuDf64Palette = 1;
  static const int _gpuDf64WarmupRuns = 2;
  static const int _gpuDf64TimedRuns = 4;

  static const int _cpuF64Size = 384;
  static const int _cpuF64MaxIter = 600;
  static const int _cpuF64Palette = 4;
  static const int _cpuF64WarmupRuns = 1;
  static const int _cpuF64TimedRuns = 3;

  static Future<PotatoBenchmarkResult> run({
    void Function(
      double progress,
      String stage, {
      String? detail,
      ui.Image? previewImage,
    })? onProgress,
  }) async {
    onProgress?.call(0.0, 'GPU float32');

    ui.FragmentProgram? program;
    try {
      program = await ui.FragmentProgram.fromAsset('shaders/fractal.frag');
    } catch (_) {
      program = null;
    }

    // Stage 1: GPU float32 (0.0 -> 0.35)
    final double gpuF32Work =
        (_gpuF32Size * _gpuF32Size * _gpuF32MaxIter).toDouble();
    double kGpuF32;
    double gpuF32MIter;
    if (program != null) {
      try {
        final double medianMs = await _benchmarkGpuStage(
          program: program,
          size: _gpuF32Size,
          maxIter: _gpuF32MaxIter,
          paletteIndex: _gpuF32Palette,
          useDf64: false,
          warmupRuns: _gpuF32WarmupRuns,
          timedRuns: _gpuF32TimedRuns,
          keepLastImage: onProgress != null,
          onStepProgress: (
            int step,
            int total, {
            String? detail,
            ui.Image? previewImage,
          }) {
            onProgress?.call(
              (0.35 * (step / total)).clamp(0.0, 0.35),
              'GPU float32',
              detail: detail,
              previewImage: previewImage,
            );
          },
        );
        kGpuF32 = medianMs / gpuF32Work;
        gpuF32MIter = gpuF32Work / (medianMs * 1000.0);
      } catch (_) {
        const double fallbackMs = 50.0;
        kGpuF32 = fallbackMs / gpuF32Work;
        gpuF32MIter = gpuF32Work / (fallbackMs * 1000.0);
      }
    } else {
      const double fallbackMs = 50.0;
      kGpuF32 = fallbackMs / gpuF32Work;
      gpuF32MIter = gpuF32Work / (fallbackMs * 1000.0);
    }

    // Stage 2: GPU df64 (0.35 -> 0.70)
    onProgress?.call(0.35, 'GPU df64');
    final double gpuDf64Work =
        (_gpuDf64Size * _gpuDf64Size * _gpuDf64MaxIter).toDouble();
    double kGpuDf64;
    double gpuDf64MIter;
    if (program != null) {
      try {
        final double medianMs = await _benchmarkGpuStage(
          program: program,
          size: _gpuDf64Size,
          maxIter: _gpuDf64MaxIter,
          paletteIndex: _gpuDf64Palette,
          useDf64: true,
          warmupRuns: _gpuDf64WarmupRuns,
          timedRuns: _gpuDf64TimedRuns,
          keepLastImage: onProgress != null,
          onStepProgress: (
            int step,
            int total, {
            String? detail,
            ui.Image? previewImage,
          }) {
            onProgress?.call(
              (0.35 + 0.35 * (step / total)).clamp(0.35, 0.70),
              'GPU df64',
              detail: detail,
              previewImage: previewImage,
            );
          },
        );
        kGpuDf64 = medianMs / gpuDf64Work;
        gpuDf64MIter = gpuDf64Work / (medianMs * 1000.0);
      } catch (_) {
        const double fallbackMs = 150.0;
        kGpuDf64 = fallbackMs / gpuDf64Work;
        gpuDf64MIter = gpuDf64Work / (fallbackMs * 1000.0);
      }
    } else {
      const double fallbackMs = 150.0;
      kGpuDf64 = fallbackMs / gpuDf64Work;
      gpuDf64MIter = gpuDf64Work / (fallbackMs * 1000.0);
    }

    // Stage 3: CPU float64 (0.70 -> 1.0)
    onProgress?.call(0.70, 'CPU float64');
    final double cpuWork =
        (_cpuF64Size * _cpuF64Size * _cpuF64MaxIter).toDouble();
    final CpuRenderRequest cpuRequest = CpuRenderRequest(
      width: _cpuF64Size,
      height: _cpuF64Size,
      logicalWidth: _cpuF64Size.toDouble(),
      logicalHeight: _cpuF64Size.toDouble(),
      centerX: centerX,
      centerY: centerY,
      zoom: zoom,
      maxIterations: _cpuF64MaxIter,
      fractalTypeIndex: 0,
      juliaCx: 0.0,
      juliaCy: 0.0,
      paletteIndex: _cpuF64Palette,
      primaryR: 0.25,
      primaryG: 0.55,
      primaryB: 0.95,
      secondaryR: 0.95,
      secondaryG: 0.45,
      secondaryB: 0.25,
      colorOffset: 0.0,
      smoothColor: true,
    );

    const int totalCpuSteps = _cpuF64WarmupRuns + _cpuF64TimedRuns;
    for (int w = 0; w < _cpuF64WarmupRuns; w++) {
      final double stepStart = 0.70 + 0.30 * (w / totalCpuSteps);
      final double stepEnd = 0.70 + 0.30 * ((w + 1) / totalCpuSteps);
      await CpuFractalRenderer.renderRgba(
        cpuRequest,
        onProgress: (double p) {
          onProgress?.call(
            (stepStart + (stepEnd - stepStart) * p).clamp(0.70, 1.0),
            'CPU float64',
          );
        },
      );
      onProgress?.call(stepEnd.clamp(0.70, 1.0), 'CPU float64');
    }

    final List<double> cpuSamplesMs = <double>[];
    for (int i = 0; i < _cpuF64TimedRuns; i++) {
      final int stepIndex = _cpuF64WarmupRuns + i;
      final double stepStart = 0.70 + 0.30 * (stepIndex / totalCpuSteps);
      final double stepEnd = 0.70 + 0.30 * ((stepIndex + 1) / totalCpuSteps);
      final bool isLast = i == _cpuF64TimedRuns - 1;

      final Stopwatch cpuWatch = Stopwatch()..start();
      final Uint8List rgba = await CpuFractalRenderer.renderRgba(
        cpuRequest,
        onProgress: (double p) {
          onProgress?.call(
            (stepStart + (stepEnd - stepStart) * p).clamp(0.70, 1.0),
            'CPU float64',
          );
        },
      );
      cpuWatch.stop();

      final double stepMs =
          math.max(0.05, cpuWatch.elapsedMicroseconds / 1000.0);
      cpuSamplesMs.add(stepMs);
      final double stepMIter = cpuWork / (stepMs * 1000.0);

      ui.Image? previewImage;
      if (isLast && onProgress != null) {
        previewImage = await _decodeRgbaPreview(rgba, _cpuF64Size, _cpuF64Size);
      }

      onProgress?.call(
        stepEnd.clamp(0.70, 1.0),
        'CPU float64',
        detail:
            '${stepMs.toStringAsFixed(1)} ms · ${stepMIter.toStringAsFixed(0)} MIter/s',
        previewImage: previewImage,
      );
    }

    final double cpuMs = _medianMs(cpuSamplesMs);
    final double kCpuF64 = cpuMs / cpuWork;
    final double cpuF64MIter = cpuWork / (cpuMs * 1000.0);

    final int score = PotatoBenchmarkResult.computeScore(
      gpuF32MIter: gpuF32MIter,
      gpuDf64MIter: gpuDf64MIter,
      cpuF64MIter: cpuF64MIter,
    );
    return PotatoBenchmarkResult(
      score: score,
      tier: PotatoBenchmarkResult.tierForScore(score),
      gpuF32MIterPerSec: gpuF32MIter,
      gpuDf64MIterPerSec: gpuDf64MIter,
      cpuF64MIterPerSec: cpuF64MIter,
      kGpuF32: kGpuF32,
      kGpuDf64: kGpuDf64,
      kCpuF64: kCpuF64,
      completedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  static Future<double> _benchmarkGpuStage({
    required ui.FragmentProgram program,
    required int size,
    required int maxIter,
    required int paletteIndex,
    required bool useDf64,
    required int warmupRuns,
    required int timedRuns,
    required bool keepLastImage,
    required void Function(
      int step,
      int total, {
      String? detail,
      ui.Image? previewImage,
    }) onStepProgress,
  }) async {
    final int totalSteps = warmupRuns + timedRuns;
    final double work = (size * size * maxIter).toDouble();

    for (int w = 0; w < warmupRuns; w++) {
      await _bakeOnce(
        program: program,
        size: size,
        maxIter: maxIter,
        paletteIndex: paletteIndex,
        useDf64: useDf64,
        keepImage: false,
      );
      onStepProgress(w + 1, totalSteps);
    }

    final List<double> samplesMs = <double>[];
    for (int i = 0; i < timedRuns; i++) {
      final bool isLast = i == timedRuns - 1;
      final Stopwatch sw = Stopwatch()..start();
      final ui.Image? preview = await _bakeOnce(
        program: program,
        size: size,
        maxIter: maxIter,
        paletteIndex: paletteIndex,
        useDf64: useDf64,
        keepImage: keepLastImage && isLast,
      );
      sw.stop();

      final double stepMs = math.max(0.05, sw.elapsedMicroseconds / 1000.0);
      samplesMs.add(stepMs);
      final double stepMIter = work / (stepMs * 1000.0);
      onStepProgress(
        warmupRuns + i + 1,
        totalSteps,
        detail:
            '${stepMs.toStringAsFixed(1)} ms · ${stepMIter.toStringAsFixed(0)} MIter/s',
        previewImage: preview,
      );
    }

    return _medianMs(samplesMs);
  }

  static double _medianMs(List<double> samplesMs) {
    samplesMs.sort();
    final int mid = samplesMs.length ~/ 2;
    if (samplesMs.length.isOdd) {
      return samplesMs[mid];
    }
    return (samplesMs[mid - 1] + samplesMs[mid]) * 0.5;
  }

  static Future<ui.Image> _decodeRgbaPreview(
    Uint8List rgba,
    int width,
    int height,
  ) {
    final Completer<ui.Image> completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  static Future<ui.Image?> _bakeOnce({
    required ui.FragmentProgram program,
    required int size,
    required int maxIter,
    required int paletteIndex,
    required bool useDf64,
    required bool keepImage,
  }) async {
    final ui.FragmentShader shader = program.fragmentShader();
    ui.Picture? picture;
    ui.Image? image;
    bool transferOwnership = false;
    try {
      final (double cxHi, double cxLo) = splitDoubleToDf64(centerX);
      final (double cyHi, double cyLo) = splitDoubleToDf64(centerY);
      final (double scHi, double scLo) = splitDoubleToDf64(1.0 / zoom);
      final double dim = size.toDouble();

      shader.setFloat(0, dim);
      shader.setFloat(1, dim);
      shader.setFloat(2, cxHi);
      shader.setFloat(3, cxLo);
      shader.setFloat(4, cyHi);
      shader.setFloat(5, cyLo);
      shader.setFloat(6, scHi);
      shader.setFloat(7, scLo);
      shader.setFloat(8, maxIter.toDouble());
      shader.setFloat(9, 0.0);
      shader.setFloat(10, 0.0);
      shader.setFloat(11, 0.0);
      shader.setFloat(12, paletteIndex.toDouble());
      shader.setFloat(13, 0.25);
      shader.setFloat(14, 0.55);
      shader.setFloat(15, 0.95);
      shader.setFloat(16, 0.95);
      shader.setFloat(17, 0.45);
      shader.setFloat(18, 0.25);
      shader.setFloat(19, 0.0);
      shader.setFloat(20, 1.0);
      shader.setFloat(21, useDf64 ? 1.0 : 0.0);
      shader.setFloat(22, 0.0);
      shader.setFloat(23, 1.0);
      shader.setFloat(24, 0.0);

      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final ui.Canvas canvas = ui.Canvas(recorder);
      final ui.Paint paint = ui.Paint()..shader = shader;
      canvas.drawRect(ui.Rect.fromLTWH(0.0, 0.0, dim, dim), paint);
      picture = recorder.endRecording();
      image = await picture.toImage(size, size);
      // Force GPU fence completion before the caller stops its Stopwatch.
      await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (keepImage) {
        transferOwnership = true;
        return image;
      }
      return null;
    } finally {
      if (!transferOwnership) {
        image?.dispose();
      }
      picture?.dispose();
      shader.dispose();
    }
  }
}
