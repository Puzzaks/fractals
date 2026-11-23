import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'big_float.dart';

/// Pure value-object request for computing a deep-zoom perturbation reference
/// orbit in a background isolate.
class PerturbationOrbitRequest {
  /// Decimal string for the viewport center real coordinate.
  final String centerXDecimal;

  /// Decimal string for the viewport center imaginary coordinate.
  final String centerYDecimal;

  /// Current zoom level.
  final double zoom;

  /// Maximum iterations requested by the renderer (clamped to `4096`).
  final int maxIterations;

  /// Fractal type index (`0` Mandelbrot, `1` Julia, `2` Burning Ship,
  /// `3` Tricorn).
  final int fractalTypeIndex;

  /// Julia seed real component (used when [fractalTypeIndex] == `1`).
  final double juliaCx;

  /// Julia seed imaginary component (used when [fractalTypeIndex] == `1`).
  final double juliaCy;

  /// Half-diagonal of the viewport in logical/physical pixels.
  final double viewportHalfDiagPx;

  /// Fixed-point fractional bit width for [BigFixed] orbit arithmetic.
  final int fracBits;

  const PerturbationOrbitRequest({
    required this.centerXDecimal,
    required this.centerYDecimal,
    required this.zoom,
    required this.maxIterations,
    required this.fractalTypeIndex,
    required this.juliaCx,
    required this.juliaCy,
    required this.viewportHalfDiagPx,
    required this.fracBits,
  });
}

/// Result of computing a perturbation reference orbit, optional Series
/// Approximation coefficients, and packed 24-bit RGB orbit texture bytes.
class PerturbationOrbitResult {
  final String refCenterXDecimal;
  final String refCenterYDecimal;
  final double refCenterXDouble;
  final double refCenterYDouble;
  final int refLen;
  final double orbitZoom;
  final int saSkip;
  final double saARe;
  final double saAIm;
  final double saBRe;
  final double saBIm;
  final double saCRe;
  final double saCIm;
  final int textureWidth;
  final int textureHeight;
  final Uint8List rgbaBytes;

  const PerturbationOrbitResult({
    required this.refCenterXDecimal,
    required this.refCenterYDecimal,
    required this.refCenterXDouble,
    required this.refCenterYDouble,
    required this.refLen,
    required this.orbitZoom,
    required this.saSkip,
    required this.saARe,
    required this.saAIm,
    required this.saBRe,
    required this.saBIm,
    required this.saCRe,
    required this.saCIm,
    this.textureWidth = 256,
    this.textureHeight = 32,
    required this.rgbaBytes,
  });
}

class _OrbitTrace {
  final BigFixed cx;
  final BigFixed cy;
  final List<double> re;
  final List<double> im;
  final bool isOriginalCenter;

  const _OrbitTrace({
    required this.cx,
    required this.cy,
    required this.re,
    required this.im,
    required this.isOriginalCenter,
  });

  int get len => re.length;
}

/// Computes arbitrary-precision reference orbits, Series Approximation skip
/// coefficients, and packed RGBA8888 orbit textures for GPU perturbation.
class PerturbationSolver {
  PerturbationSolver._();

  static const int maxOrbitSteps = 4096;
  static const int textureWidth = 256;
  static const int textureHeight = 32;

  /// Computes the reference orbit and Series Approximation off the UI thread.
  static Future<PerturbationOrbitResult> computeOrbit(
    PerturbationOrbitRequest req,
  ) {
    return Isolate.run(() => computeOrbitSync(req));
  }

  /// Synchronous orbit computation (suitable for isolates or unit tests).
  static PerturbationOrbitResult computeOrbitSync(
    PerturbationOrbitRequest req,
  ) {
    final int fracBits = req.fracBits;
    final int maxIter = req.maxIterations.clamp(1, maxOrbitSteps);

    final BigFixed centerX =
        BigFixed.parseDecimal(req.centerXDecimal, fracBits);
    final BigFixed centerY =
        BigFixed.parseDecimal(req.centerYDecimal, fracBits);
    final BigFixed juliaX = BigFixed.fromDouble(req.juliaCx, fracBits);
    final BigFixed juliaY = BigFixed.fromDouble(req.juliaCy, fracBits);
    final BigFixed bailoutSq = BigFixed.fromInt(16, fracBits);

    _OrbitTrace best = _runOrbit(
      cx: centerX,
      cy: centerY,
      maxIter: maxIter,
      fractalTypeIndex: req.fractalTypeIndex,
      juliaX: juliaX,
      juliaY: juliaY,
      bailoutSq: bailoutSq,
      fracBits: fracBits,
      isOriginalCenter: true,
    );

    final int probeThreshold = math.min(maxIter, 256);
    if (best.len < probeThreshold &&
        req.zoom > 0.0 &&
        req.zoom.isFinite &&
        req.viewportHalfDiagPx > 0.0) {
      final double offsetDouble = 0.2 * req.viewportHalfDiagPx / req.zoom;
      if (offsetDouble > 0.0 && offsetDouble.isFinite) {
        final BigFixed offset = BigFixed.fromDouble(offsetDouble, fracBits);
        final List<(BigFixed, BigFixed)> candidates = <(BigFixed, BigFixed)>[
          (centerX + offset, centerY),
          (centerX - offset, centerY),
          (centerX, centerY + offset),
          (centerX, centerY - offset),
        ];

        for (final (BigFixed px, BigFixed py) in candidates) {
          final _OrbitTrace candidate = _runOrbit(
            cx: px,
            cy: py,
            maxIter: maxIter,
            fractalTypeIndex: req.fractalTypeIndex,
            juliaX: juliaX,
            juliaY: juliaY,
            bailoutSq: bailoutSq,
            fracBits: fracBits,
            isOriginalCenter: false,
          );
          if (candidate.len > best.len) {
            best = candidate;
            if (best.len >= maxIter) {
              break;
            }
          }
        }
      }
    }

    final int refLen = best.len;

    // Series Approximation for Mandelbrot (type 0) when zoom <= 1e90.
    int saSkip = 0;
    double saARe = 0.0;
    double saAIm = 0.0;
    double saBRe = 0.0;
    double saBIm = 0.0;
    double saCRe = 0.0;
    double saCIm = 0.0;

    if (req.fractalTypeIndex == 0 &&
        req.zoom > 0.0 &&
        req.zoom <= 1e90 &&
        req.zoom.isFinite &&
        req.viewportHalfDiagPx > 0.0 &&
        req.viewportHalfDiagPx.isFinite &&
        refLen > 16) {
      final double invZoom = 1.0 / req.zoom;
      final double r = req.viewportHalfDiagPx;
      final double r2 = r * r;
      final double r3 = r2 * r;

      double aRe = 0.0;
      double aIm = 0.0;
      double bRe = 0.0;
      double bIm = 0.0;
      double cRe = 0.0;
      double cIm = 0.0;

      for (int n = 0; n < refLen - 16; n++) {
        final double txr = 2.0 * best.re[n];
        final double txi = 2.0 * best.im[n];

        // A_{n+1} = 2 * X_n * A_n + 1/zoom
        final double nARe = txr * aRe - txi * aIm + invZoom;
        final double nAIm = txr * aIm + txi * aRe;

        // B_{n+1} = 2 * X_n * B_n + A_n^2
        final double a2Re = aRe * aRe - aIm * aIm;
        final double a2Im = 2.0 * aRe * aIm;
        final double nBRe = txr * bRe - txi * bIm + a2Re;
        final double nBIm = txr * bIm + txi * bRe + a2Im;

        // C_{n+1} = 2 * X_n * C_n + 2 * A_n * B_n
        final double abRe = aRe * bRe - aIm * bIm;
        final double abIm = aRe * bIm + aIm * bRe;
        final double nCRe = txr * cRe - txi * cIm + 2.0 * abRe;
        final double nCIm = txr * cIm + txi * cRe + 2.0 * abIm;

        aRe = nARe;
        aIm = nAIm;
        bRe = nBRe;
        bIm = nBIm;
        cRe = nCRe;
        cIm = nCIm;

        if (!aRe.isFinite ||
            !aIm.isFinite ||
            !bRe.isFinite ||
            !bIm.isFinite ||
            !cRe.isFinite ||
            !cIm.isFinite) {
          break;
        }

        final double magA = math.sqrt(aRe * aRe + aIm * aIm) * r;
        final double magB = math.sqrt(bRe * bRe + bIm * bIm) * r2;
        final double magC = math.sqrt(cRe * cRe + cIm * cIm) * r3;

        if (magA < 0.05 && magB < 0.1 * magA && magC < 1e-3 * magA) {
          saSkip = n + 1;
          saARe = aRe;
          saAIm = aIm;
          saBRe = bRe;
          saBIm = bIm;
          saCRe = cRe;
          saCIm = cIm;
        } else {
          break;
        }
      }
    }

    // Pack orbit into 256 x 32 RGBA8888 texture (24-bit RGB fixed-point on
    // [-4.0, 4.0], A = 255 always to prevent Impeller premultiplied-alpha
    // corruption).
    final Uint8List rgbaBytes = Uint8List(textureWidth * textureHeight * 4);
    for (int i = 3; i < rgbaBytes.length; i += 4) {
      rgbaBytes[i] = 255;
    }
    for (int n = 0; n < refLen; n++) {
      _packFloat24(rgbaBytes, 2 * n, best.re[n]);
      _packFloat24(rgbaBytes, 2 * n + 1, best.im[n]);
    }

    final int decimalDigits = (fracBits * 0.30103).ceil() + 4;
    final String refCenterXDecimal = best.isOriginalCenter
        ? req.centerXDecimal
        : best.cx.toDecimalString(decimalDigits);
    final String refCenterYDecimal = best.isOriginalCenter
        ? req.centerYDecimal
        : best.cy.toDecimalString(decimalDigits);

    return PerturbationOrbitResult(
      refCenterXDecimal: refCenterXDecimal,
      refCenterYDecimal: refCenterYDecimal,
      refCenterXDouble: best.cx.toDouble(),
      refCenterYDouble: best.cy.toDouble(),
      refLen: refLen,
      orbitZoom: req.zoom,
      saSkip: saSkip,
      saARe: saARe,
      saAIm: saAIm,
      saBRe: saBRe,
      saBIm: saBIm,
      saCRe: saCRe,
      saCIm: saCIm,
      textureWidth: textureWidth,
      textureHeight: textureHeight,
      rgbaBytes: rgbaBytes,
    );
  }

  /// Decodes [result.rgbaBytes] into a GPU-uploadable [ui.Image].
  static Future<ui.Image> decodeOrbitTexture(PerturbationOrbitResult result) {
    final Completer<ui.Image> completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      result.rgbaBytes,
      result.textureWidth,
      result.textureHeight,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  static _OrbitTrace _runOrbit({
    required BigFixed cx,
    required BigFixed cy,
    required int maxIter,
    required int fractalTypeIndex,
    required BigFixed juliaX,
    required BigFixed juliaY,
    required BigFixed bailoutSq,
    required int fracBits,
    required bool isOriginalCenter,
  }) {
    final List<double> re = <double>[];
    final List<double> im = <double>[];

    BigFixed zx = fractalTypeIndex == 1 ? cx : BigFixed.zero(fracBits);
    BigFixed zy = fractalTypeIndex == 1 ? cy : BigFixed.zero(fracBits);

    for (int n = 0; n < maxIter; n++) {
      final BigFixed zx2 = zx.square();
      final BigFixed zy2 = zy.square();
      if (zx2 + zy2 > bailoutSq) {
        break;
      }

      re.add(zx.toDouble());
      im.add(zy.toDouble());

      switch (fractalTypeIndex) {
        case 1: // Julia: Z_{n+1} = Z_n^2 + J
          final BigFixed twoZxZy = BigFixed((zx * zy).raw << 1, fracBits);
          zx = zx2 - zy2 + juliaX;
          zy = twoZxZy + juliaY;
          break;
        case 2: // Burning Ship: Z_{n+1} = (|X_n| + i|Y_n|)^2 + C
          final BigFixed ax = zx.abs();
          final BigFixed ay = zy.abs();
          final BigFixed twoAxAy = BigFixed((ax * ay).raw << 1, fracBits);
          zx = zx2 - zy2 + cx;
          zy = twoAxAy + cy;
          break;
        case 3: // Tricorn: Z_{n+1} = conj(Z_n)^2 + C
          final BigFixed twoZxZy = BigFixed((zx * zy).raw << 1, fracBits);
          zx = zx2 - zy2 + cx;
          zy = cy - twoZxZy;
          break;
        case 0: // Mandelbrot: Z_{n+1} = Z_n^2 + C
        default:
          final BigFixed twoZxZy = BigFixed((zx * zy).raw << 1, fracBits);
          zx = zx2 - zy2 + cx;
          zy = twoZxZy + cy;
          break;
      }
    }

    return _OrbitTrace(
      cx: cx,
      cy: cy,
      re: re,
      im: im,
      isOriginalCenter: isOriginalCenter,
    );
  }

  static void _packFloat24(Uint8List bytes, int texelIndex, double v) {
    final double clamped = v.isFinite ? v.clamp(-4.0, 4.0) : 0.0;
    final int u =
        ((clamped + 4.0) / 8.0 * 16777215.0).round().clamp(0, 16777215);
    final int offset = texelIndex * 4;
    bytes[offset] = (u >> 16) & 0xFF;
    bytes[offset + 1] = (u >> 8) & 0xFF;
    bytes[offset + 2] = u & 0xFF;
    bytes[offset + 3] = 255;
  }
}
