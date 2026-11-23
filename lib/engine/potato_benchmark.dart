import 'dart:convert';
import 'dart:math' as math;
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
    return (gpuF32MIter * 0.15 + gpuDf64MIter * 6.0 + cpuF64MIter * 4.0)
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
  static const int maxIter = 400;

  static const int _gpuF32Size = 512;
  static const int _gpuDf64Size = 384;
  static const int _cpuF64Size = 384;

  static Future<PotatoBenchmarkResult> run({
    void Function(double progress, String stage)? onProgress,
  }) async {
    onProgress?.call(0.0, 'GPU float32');

    ui.FragmentProgram? program;
    try {
      program = await ui.FragmentProgram.fromAsset('shaders/fractal.frag');
    } catch (_) {
      program = null;
    }

    // Stage 1: GPU float32 (0.0 -> 0.35)
    double kGpuF32;
    double gpuF32MIter;
    if (program != null) {
      try {
        final double medianMs = await _benchmarkGpuStage(
          program: program,
          size: _gpuF32Size,
          useDf64: false,
          timedRuns: 4,
          onStepProgress: (int step, int total) {
            onProgress?.call(
              (0.35 * (step / total)).clamp(0.0, 0.35),
              'GPU float32',
            );
          },
        );
        final double work = (_gpuF32Size * _gpuF32Size * maxIter).toDouble();
        kGpuF32 = medianMs / work;
        gpuF32MIter = work / (medianMs * 1000.0);
      } catch (_) {
        final double work = (_gpuF32Size * _gpuF32Size * maxIter).toDouble();
        const double fallbackMs = 50.0;
        kGpuF32 = fallbackMs / work;
        gpuF32MIter = work / (fallbackMs * 1000.0);
      }
    } else {
      final double work = (_gpuF32Size * _gpuF32Size * maxIter).toDouble();
      const double fallbackMs = 50.0;
      kGpuF32 = fallbackMs / work;
      gpuF32MIter = work / (fallbackMs * 1000.0);
    }

    // Stage 2: GPU df64 (0.35 -> 0.70)
    onProgress?.call(0.35, 'GPU df64');
    double kGpuDf64;
    double gpuDf64MIter;
    if (program != null) {
      try {
        final double medianMs = await _benchmarkGpuStage(
          program: program,
          size: _gpuDf64Size,
          useDf64: true,
          timedRuns: 3,
          onStepProgress: (int step, int total) {
            onProgress?.call(
              (0.35 + 0.35 * (step / total)).clamp(0.35, 0.70),
              'GPU df64',
            );
          },
        );
        final double work = (_gpuDf64Size * _gpuDf64Size * maxIter).toDouble();
        kGpuDf64 = medianMs / work;
        gpuDf64MIter = work / (medianMs * 1000.0);
      } catch (_) {
        final double work = (_gpuDf64Size * _gpuDf64Size * maxIter).toDouble();
        const double fallbackMs = 150.0;
        kGpuDf64 = fallbackMs / work;
        gpuDf64MIter = work / (fallbackMs * 1000.0);
      }
    } else {
      final double work = (_gpuDf64Size * _gpuDf64Size * maxIter).toDouble();
      const double fallbackMs = 150.0;
      kGpuDf64 = fallbackMs / work;
      gpuDf64MIter = work / (fallbackMs * 1000.0);
    }

    // Stage 3: CPU float64 (0.70 -> 1.0)
    onProgress?.call(0.70, 'CPU float64');
    final Stopwatch cpuWatch = Stopwatch()..start();
    await CpuFractalRenderer.renderRgba(
      CpuRenderRequest(
        width: _cpuF64Size,
        height: _cpuF64Size,
        logicalWidth: _cpuF64Size.toDouble(),
        logicalHeight: _cpuF64Size.toDouble(),
        centerX: centerX,
        centerY: centerY,
        zoom: zoom,
        maxIterations: maxIter,
        fractalTypeIndex: 0,
        juliaCx: 0.0,
        juliaCy: 0.0,
        paletteIndex: 1,
        primaryR: 0.25,
        primaryG: 0.55,
        primaryB: 0.95,
        secondaryR: 0.95,
        secondaryG: 0.45,
        secondaryB: 0.25,
        colorOffset: 0.0,
        smoothColor: true,
      ),
      onProgress: (double p) {
        onProgress?.call(
          (0.70 + 0.30 * p).clamp(0.70, 1.0),
          'CPU float64',
        );
      },
    );
    cpuWatch.stop();

    final double cpuMs = math.max(0.05, cpuWatch.elapsedMicroseconds / 1000.0);
    final double cpuWork = (_cpuF64Size * _cpuF64Size * maxIter).toDouble();
    final double kCpuF64 = cpuMs / cpuWork;
    final double cpuF64MIter = cpuWork / (cpuMs * 1000.0);

    onProgress?.call(1.0, 'CPU float64');

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
    required bool useDf64,
    required int timedRuns,
    required void Function(int step, int total) onStepProgress,
  }) async {
    final int totalSteps = timedRuns + 1;
    // 1 warm-up pass (not timed)
    await _bakeOnce(program: program, size: size, useDf64: useDf64);
    onStepProgress(1, totalSteps);

    final List<double> samplesMs = <double>[];
    for (int i = 0; i < timedRuns; i++) {
      final Stopwatch sw = Stopwatch()..start();
      await _bakeOnce(program: program, size: size, useDf64: useDf64);
      sw.stop();
      samplesMs.add(math.max(0.05, sw.elapsedMicroseconds / 1000.0));
      onStepProgress(i + 2, totalSteps);
    }

    samplesMs.sort();
    final int mid = samplesMs.length ~/ 2;
    if (samplesMs.length.isOdd) {
      return samplesMs[mid];
    }
    return (samplesMs[mid - 1] + samplesMs[mid]) * 0.5;
  }

  static Future<void> _bakeOnce({
    required ui.FragmentProgram program,
    required int size,
    required bool useDf64,
  }) async {
    final ui.FragmentShader shader = program.fragmentShader();
    ui.Picture? picture;
    ui.Image? image;
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
      shader.setFloat(12, 1.0);
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
    } finally {
      image?.dispose();
      picture?.dispose();
      shader.dispose();
    }
  }
}
