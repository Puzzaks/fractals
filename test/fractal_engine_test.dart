import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset, Size;

import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:fractals/engine/big_float.dart';
import 'package:fractals/engine/cpu_renderer.dart';
import 'package:fractals/engine/fractal_engine.dart';
import 'package:fractals/engine/fractal_models.dart';
import 'package:fractals/engine/fractal_share_link.dart';
import 'package:fractals/engine/perturbation_solver.dart';
import 'package:fractals/engine/potato_benchmark.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Focal-point camera math', () {
    test('screenToWorld maps viewport center and scales inversely with zoom',
        () {
      final FractalEngine engine = FractalEngine();
      addTearDown(engine.dispose);

      const Size viewport = Size(800, 600);
      final Offset centerWorld = engine.screenToWorld(
        const Offset(400, 300),
        viewport,
      );
      expect(centerWorld.dx, equals(engine.centerX));
      expect(centerWorld.dy, equals(engine.centerY));

      // Empty viewport falls back to current center.
      final Offset emptyWorld = engine.screenToWorld(
        const Offset(123, 456),
        Size.zero,
      );
      expect(emptyWorld.dx, equals(engine.centerX));
      expect(emptyWorld.dy, equals(engine.centerY));

      // Offset from viewport center scales inversely with zoom.
      const Offset offCenter = Offset(640, 180); // (+240, -120) px from center
      final double zoom1 = engine.zoom; // 240.0
      final Offset world1 = engine.screenToWorld(offCenter, viewport);
      expect(world1.dx, closeTo(engine.centerX + 240.0 / zoom1, 1e-12));
      expect(world1.dy, closeTo(engine.centerY - 120.0 / zoom1, 1e-12));

      engine.zoomAtFocalPoint(viewport.center(Offset.zero), viewport, 2.0);
      final double zoom2 = engine.zoom;
      expect(zoom2, closeTo(zoom1 * 2.0, 1e-12));

      final Offset world2 = engine.screenToWorld(offCenter, viewport);
      expect(
        world2.dx - engine.centerX,
        closeTo((world1.dx - engine.centerX) * 0.5, 1e-12),
      );
      expect(
        world2.dy - engine.centerY,
        closeTo((world1.dy - engine.centerY) * 0.5, 1e-12),
      );
    });

    test(
        'zoomAtFocalPoint preserves world coordinate under arbitrary off-center localPos',
        () {
      final FractalEngine engine = FractalEngine();
      addTearDown(engine.dispose);

      const Size viewport = Size(1024, 768);
      const Offset focalPos = Offset(217.5, 589.25);

      for (final double factor in <double>[2.75, 12.5, 0.4, 150.0, 0.25]) {
        final Offset before = engine.screenToWorld(focalPos, viewport);
        engine.zoomAtFocalPoint(focalPos, viewport, factor, persist: false);
        final Offset after = engine.screenToWorld(focalPos, viewport);

        expect((after.dx - before.dx).abs(), lessThan(1e-9));
        expect((after.dy - before.dy).abs(), lessThan(1e-9));
      }
    });

    test('transformAtFocalPoint composes pan (focalDelta) and zoom accurately',
        () {
      final FractalEngine engine = FractalEngine();
      addTearDown(engine.dispose);

      const Size viewport = Size(800, 600);
      const Offset focalPos = Offset(310, 220);
      const Offset focalDelta = Offset(36, -18);
      const double scaleFactor = 2.5;

      final double initialZoom = engine.zoom;
      final Offset prevFocal = focalPos - focalDelta;
      final Offset worldUnderPrevFocal =
          engine.screenToWorld(prevFocal, viewport);

      engine.transformAtFocalPoint(
        focalPos: focalPos,
        focalDelta: focalDelta,
        scaleFactor: scaleFactor,
        viewport: viewport,
        persist: false,
      );

      expect(engine.zoom, closeTo(initialZoom * scaleFactor, 1e-12));
      final Offset worldUnderNewFocal =
          engine.screenToWorld(focalPos, viewport);
      expect(
        (worldUnderNewFocal.dx - worldUnderPrevFocal.dx).abs(),
        lessThan(1e-9),
      );
      expect(
        (worldUnderNewFocal.dy - worldUnderPrevFocal.dy).abs(),
        lessThan(1e-9),
      );

      // Pure pan via transformAtFocalPoint matches 1:1 delta / zoom.
      final double prePanX = engine.centerX;
      final double prePanY = engine.centerY;
      const Offset panDelta = Offset(-45, 30);
      engine.transformAtFocalPoint(
        focalPos: focalPos,
        focalDelta: panDelta,
        scaleFactor: 1.0,
        viewport: viewport,
        persist: false,
      );
      expect(engine.centerX, closeTo(prePanX - panDelta.dx / engine.zoom, 1e-12));
      expect(engine.centerY, closeTo(prePanY - panDelta.dy / engine.zoom, 1e-12));

      // Invalid scaleFactor or empty viewport must be ignored.
      final double savedZoom = engine.zoom;
      final double savedX = engine.centerX;
      engine.transformAtFocalPoint(
        focalPos: focalPos,
        focalDelta: const Offset(10, 10),
        scaleFactor: 0.0,
        viewport: viewport,
        persist: false,
      );
      engine.transformAtFocalPoint(
        focalPos: focalPos,
        focalDelta: const Offset(10, 10),
        scaleFactor: double.nan,
        viewport: viewport,
        persist: false,
      );
      engine.transformAtFocalPoint(
        focalPos: focalPos,
        focalDelta: const Offset(10, 10),
        scaleFactor: 2.0,
        viewport: Size.zero,
        persist: false,
      );
      expect(engine.zoom, equals(savedZoom));
      expect(engine.centerX, equals(savedX));
    });

    test('panBy shifts centerX and centerY by exact 1:1 pixel ratio (-delta / zoom)',
        () {
      final FractalEngine engine = FractalEngine();
      addTearDown(engine.dispose);

      const Size viewport = Size(800, 600);
      const Offset pointer = Offset(250, 175);
      const Offset delta = Offset(120, -60);

      final double startX = engine.centerX;
      final double startY = engine.centerY;
      final double zoom = engine.zoom;
      final Offset worldBefore = engine.screenToWorld(pointer, viewport);

      int notifications = 0;
      engine.addListener(() => notifications++);

      engine.panBy(Offset.zero, persist: false);
      expect(notifications, equals(0));

      engine.panBy(delta, persist: false);
      expect(notifications, equals(1));
      expect(engine.centerX, closeTo(startX - delta.dx / zoom, 1e-12));
      expect(engine.centerY, closeTo(startY - delta.dy / zoom, 1e-12));

      final Offset worldAfter = engine.screenToWorld(pointer + delta, viewport);
      expect((worldAfter.dx - worldBefore.dx).abs(), lessThan(1e-12));
      expect((worldAfter.dy - worldBefore.dy).abs(), lessThan(1e-12));
    });
  });

  group('Double-float (df64) splitting', () {
    test('splitDoubleToDf64 reconstructs value across positive, negative, zero, and non-finite inputs',
        () {
      final List<double> finiteInputs = <double>[
        0.0,
        -0.0,
        1.0,
        -1.0,
        0.281717921930775,
        -0.743643887037151,
        0.131825904205330,
        -1.768778833123456,
        math.pi,
        -math.e,
        1.2345678901234567e-8,
        -9.876543210987654e-13,
        12345.678901234567,
      ];

      final Float32List f32Checker = Float32List(1);
      for (final double value in finiteInputs) {
        final (double hi, double lo) = splitDoubleToDf64(value);
        expect(hi.isFinite, isTrue);
        expect(lo.isFinite, isTrue);

        // hi must be exactly representable as a 32-bit float.
        f32Checker[0] = hi;
        expect(f32Checker[0], equals(hi));

        // hi + lo reconstructs value to IEEE-754 float64 precision.
        final double reconstructed = hi + lo;
        final double tol = 1e-15 * value.abs();
        expect((reconstructed - value).abs(), lessThanOrEqualTo(tol));
      }

      expect(splitDoubleToDf64(double.nan), equals((0.0, 0.0)));
      expect(splitDoubleToDf64(double.infinity), equals((0.0, 0.0)));
      expect(splitDoubleToDf64(double.negativeInfinity), equals((0.0, 0.0)));
    });
  });

  group('Iteration scaling and render backend selection', () {
    test(
        'effectiveMaxIterations scales logarithmically when autoIterations is true and honors manual*quality when false',
        () {
      final FractalEngine engine = FractalEngine();
      addTearDown(engine.dispose);

      const Size viewport = Size(800, 600);
      final Offset center = viewport.center(Offset.zero);

      expect(engine.autoIterations, isTrue);
      expect(engine.quality, equals(RenderQuality.native));

      // Reset to exact zoom=200 (below default 240) to verify log10 baseline.
      engine.zoomAtFocalPoint(center, viewport, 200.0 / engine.zoom);
      final int iterAt200 = engine.effectiveMaxIterations;
      expect(iterAt200, equals(120));

      engine.zoomAtFocalPoint(center, viewport, 10.0); // zoom = 2000
      final int iterAt2k = engine.effectiveMaxIterations;
      expect(iterAt2k, equals(195)); // 120 + 75 * 1

      engine.zoomAtFocalPoint(center, viewport, 100.0); // zoom = 200000
      final int iterAt200k = engine.effectiveMaxIterations;
      expect(iterAt200k, equals(345)); // 120 + 75 * 3

      engine.zoomAtFocalPoint(center, viewport, 1000.0); // zoom = 2e8
      final int iterAt200m = engine.effectiveMaxIterations;
      expect(iterAt200m, equals(570)); // 120 + 75 * 6

      expect(iterAt2k - iterAt200, equals(75));
      expect(iterAt200k - iterAt2k, equals(150));
      expect(iterAt200m - iterAt200k, equals(225));

      // Quality scales auto iterations as well.
      engine.setQuality(RenderQuality.ultra);
      expect(
        engine.effectiveMaxIterations,
        equals((570 * RenderQuality.ultra.iterationMultiplier).round()),
      );

      // Manual mode ignores zoom and multiplies manualMaxIterations * quality.
      engine.setAutoIterations(false);
      engine.setManualMaxIterations(400);
      for (final RenderQuality q in RenderQuality.values) {
        engine.setQuality(q);
        expect(
          engine.effectiveMaxIterations,
          equals((400 * q.iterationMultiplier).round().clamp(50, 4000)),
        );
      }

      // Clamping checks at manual extremes.
      engine.setManualMaxIterations(50);
      engine.setQuality(RenderQuality.performance); // 50 * 0.65 = 32.5 -> 50
      expect(engine.effectiveMaxIterations, equals(50));

      engine.setManualMaxIterations(4000);
      engine.setQuality(RenderQuality.ultra); // 4000 * 1.25 = 5000 -> 4000
      expect(engine.effectiveMaxIterations, equals(4000));
    });

    test(
        'activeRenderMode transitions cleanly across float32 -> df64 -> gpuPerturbation and honors overrides',
        () {
      final FractalEngine engine = FractalEngine();
      addTearDown(engine.dispose);

      const Size viewport = Size(800, 600);
      final Offset center = viewport.center(Offset.zero);

      void setZoom(double targetZoom) {
        engine.zoomAtFocalPoint(
          center,
          viewport,
          targetZoom / engine.zoom,
          persist: false,
        );
      }

      expect(engine.backend, equals(RenderBackend.auto));
      setZoom(240.0);
      expect(engine.activeRenderMode, equals(ActiveRenderMode.gpuFloat32));
      expect(engine.activeRenderMode.isGpu, isTrue);
      expect(engine.activeRenderMode.isCpu, isFalse);

      setZoom(FractalEngine.df64ThresholdZoom - 1.0);
      expect(engine.activeRenderMode, equals(ActiveRenderMode.gpuFloat32));

      setZoom(FractalEngine.df64ThresholdZoom);
      expect(engine.activeRenderMode, equals(ActiveRenderMode.gpuDf64));
      expect(engine.activeRenderMode.isGpu, isTrue);

      setZoom(FractalEngine.cpuDeepThresholdZoom - 1e6);
      expect(engine.activeRenderMode, equals(ActiveRenderMode.gpuDf64));

      setZoom(FractalEngine.cpuDeepThresholdZoom);
      expect(engine.activeRenderMode, equals(ActiveRenderMode.gpuPerturbation));
      expect(engine.activeRenderMode.badge, equals('GPU PT'));
      expect(engine.activeRenderMode.isGpu, isTrue);
      expect(engine.activeRenderMode.isCpu, isFalse);

      // Explicit GPU shader override also routes to gpuPerturbation at >= 2e12.
      engine.setBackend(RenderBackend.gpuShader);
      expect(engine.activeRenderMode, equals(ActiveRenderMode.gpuPerturbation));
      expect(engine.activeRenderMode.badge, equals('GPU PT'));
      expect(engine.activeRenderMode.isGpu, isTrue);
      expect(engine.activeRenderMode.isCpu, isFalse);
      setZoom(240.0);
      expect(engine.activeRenderMode, equals(ActiveRenderMode.gpuFloat32));

      // Explicit CPU float64 override forces CPU at any zoom level.
      engine.setBackend(RenderBackend.cpuFloat64);
      expect(engine.activeRenderMode, equals(ActiveRenderMode.cpuFloat64));
      setZoom(1e8);
      expect(engine.activeRenderMode, equals(ActiveRenderMode.cpuFloat64));
      setZoom(FractalEngine.cpuDeepThresholdZoom);
      expect(engine.activeRenderMode, equals(ActiveRenderMode.cpuFloat64));
    });
  });

  group('Bookmarks and SharedPreferences persistence', () {
    test('FractalBookmark toJson / fromJson round-trip preserves fields', () {
      const FractalBookmark original = FractalBookmark(
        id: 'user_42',
        name: 'Custom Burning Ship',
        fractalType: FractalType.burningShip,
        centerX: -1.755123456,
        centerY: -0.025987654,
        zoom: 123456.78,
        juliaCx: -0.4,
        juliaCy: 0.6,
        palette: FractalPalette.inferno,
        isBuiltIn: true,
      );

      final Map<String, dynamic> decoded =
          jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>;
      final FractalBookmark restored = FractalBookmark.fromJson(decoded);

      expect(restored.id, equals(original.id));
      expect(restored.name, equals(original.name));
      expect(restored.fractalType, equals(original.fractalType));
      expect(restored.centerX, equals(original.centerX));
      expect(restored.centerY, equals(original.centerY));
      expect(restored.zoom, equals(original.zoom));
      expect(restored.juliaCx, equals(original.juliaCx));
      expect(restored.juliaCy, equals(original.juliaCy));
      expect(restored.palette, equals(original.palette));
      expect(restored.isBuiltIn, isFalse);
    });

    test('addCustomBookmark and removeCustomBookmark persist via SharedPreferences',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final FractalEngine engine1 = FractalEngine();
      addTearDown(engine1.dispose);
      await engine1.init();

      expect(engine1.initialized, isTrue);
      expect(engine1.customBookmarks, isEmpty);
      expect(engine1.allBookmarks.length, equals(builtInBookmarks.length));

      engine1.setFractalType(FractalType.julia);
      engine1.setJuliaC(-0.8, 0.156);
      engine1.setPalette(FractalPalette.neon);
      engine1.panBy(const Offset(48, -24));

      // Blank names are ignored.
      engine1.addCustomBookmark('   ');
      expect(engine1.customBookmarks, isEmpty);

      engine1.addCustomBookmark('  Julia Spiral Note  ');
      expect(engine1.customBookmarks.length, equals(1));
      final FractalBookmark saved = engine1.customBookmarks.first;
      expect(saved.name, equals('Julia Spiral Note'));
      expect(saved.fractalType, equals(FractalType.julia));
      expect(saved.palette, equals(FractalPalette.neon));
      expect(saved.juliaCx, closeTo(-0.8, 1e-12));
      expect(saved.juliaCy, closeTo(0.156, 1e-12));
      expect(saved.centerX, equals(engine1.centerX));
      expect(saved.centerY, equals(engine1.centerY));
      expect(saved.isBuiltIn, isFalse);
      expect(
        engine1.allBookmarks.length,
        equals(builtInBookmarks.length + 1),
      );

      // Reload into a fresh engine from the same mocked SharedPreferences store.
      final FractalEngine engine2 = FractalEngine();
      addTearDown(engine2.dispose);
      await engine2.init();

      expect(engine2.customBookmarks.length, equals(1));
      final FractalBookmark reloaded = engine2.customBookmarks.first;
      expect(reloaded.id, equals(saved.id));
      expect(reloaded.name, equals(saved.name));
      expect(reloaded.fractalType, equals(FractalType.julia));
      expect(reloaded.palette, equals(FractalPalette.neon));
      expect(reloaded.centerX, closeTo(saved.centerX, 1e-12));
      expect(reloaded.centerY, closeTo(saved.centerY, 1e-12));

      // Remove and verify persistence of deletion.
      engine2.removeCustomBookmark(saved.id);
      expect(engine2.customBookmarks, isEmpty);

      final FractalEngine engine3 = FractalEngine();
      addTearDown(engine3.dispose);
      await engine3.init();
      expect(engine3.customBookmarks, isEmpty);
    });
  });

  group('Telemetry', () {
    test('recordFrameDurationMs computes accurate FPS and caps fpsHistory at 30',
        () {
      final FractalEngine engine = FractalEngine();
      addTearDown(engine.dispose);

      // 1000 / (1000 / 60) == 60.0 FPS
      engine.recordFrameDurationMs(1000.0 / 60.0);
      expect(engine.lastFrameTimeMs, closeTo(16.6666667, 1e-5));
      expect(engine.currentFps, closeTo(60.0, 1e-4));
      expect(engine.fpsHistory.length, equals(1));
      expect(engine.fpsHistory.single, closeTo(60.0 / 120.0, 1e-5));

      // Push 35 samples total -> history must remain capped at 30 samples.
      for (int i = 0; i < 34; i++) {
        engine.recordFrameDurationMs(1000.0 / 60.0);
      }
      expect(engine.fpsHistory.length, equals(30));
      expect(engine.currentFps, closeTo(60.0, 1e-4));

      // 10 samples at ~33.333ms updates the 10-frame moving average to ~30 FPS.
      for (int i = 0; i < 10; i++) {
        engine.recordFrameDurationMs(1000.0 / 30.0);
      }
      expect(engine.fpsHistory.length, equals(30));
      expect(engine.currentFps, closeTo(30.0, 1e-4));
      expect(engine.fpsHistory.last, closeTo(30.0 / 120.0, 1e-5));

      // Clamping & non-finite safety: extreme small frame clamps to 120 FPS.
      for (int i = 0; i < 10; i++) {
        engine.recordFrameDurationMs(0.01);
      }
      expect(engine.lastFrameTimeMs, equals(0.1));
      expect(engine.currentFps, equals(120.0));
      expect(engine.fpsHistory.last, equals(1.0));

      // Non-finite input falls back cleanly to 16.6ms without NaN propagation.
      engine.recordFrameDurationMs(double.nan);
      expect(engine.lastFrameTimeMs, equals(16.6));
      expect(engine.currentFps.isFinite, isTrue);
      expect(engine.fpsHistory.length, equals(30));
    });
  });

  group('Per-fractal camera memory, overscan, and keybinds', () {
    test('per-fractal camera memory restores exact coordinates and persists across init()',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final FractalEngine engine1 = FractalEngine();
      addTearDown(engine1.dispose);
      await engine1.init();

      const Size viewport = Size(800, 600);
      expect(engine1.fractalType, equals(FractalType.mandelbrot));

      // Move Mandelbrot camera.
      engine1.panBy(const Offset(120, -80));
      engine1.zoomAtFocalPoint(const Offset(300, 250), viewport, 4.5);
      final double mandelX = engine1.centerX;
      final double mandelY = engine1.centerY;
      final double mandelZoom = engine1.zoom;

      // Switch to Julia and move Julia camera.
      engine1.setFractalType(FractalType.julia);
      expect(engine1.fractalType, equals(FractalType.julia));
      engine1.panBy(const Offset(-64, 42));
      engine1.zoomAtFocalPoint(const Offset(500, 320), viewport, 2.25);
      final double juliaX = engine1.centerX;
      final double juliaY = engine1.centerY;
      final double juliaZoom = engine1.zoom;

      // Switch back to Mandelbrot -> exact Mandelbrot camera restored.
      engine1.setFractalType(FractalType.mandelbrot);
      expect(engine1.centerX, equals(mandelX));
      expect(engine1.centerY, equals(mandelY));
      expect(engine1.zoom, equals(mandelZoom));

      // Switch to Julia -> exact Julia camera restored.
      engine1.setFractalType(FractalType.julia);
      expect(engine1.centerX, equals(juliaX));
      expect(engine1.centerY, equals(juliaY));
      expect(engine1.zoom, equals(juliaZoom));

      // Verify persistence across a fresh FractalEngine.init().
      final FractalEngine engine2 = FractalEngine();
      addTearDown(engine2.dispose);
      await engine2.init();

      expect(engine2.fractalType, equals(FractalType.julia));
      expect(engine2.centerX, closeTo(juliaX, 1e-12));
      expect(engine2.centerY, closeTo(juliaY, 1e-12));
      expect(engine2.zoom, closeTo(juliaZoom, 1e-9));

      engine2.setFractalType(FractalType.mandelbrot);
      expect(engine2.centerX, closeTo(mandelX, 1e-12));
      expect(engine2.centerY, closeTo(mandelY, 1e-12));
      expect(engine2.zoom, closeTo(mandelZoom, 1e-9));
    });

    test('overscanMultiplier defaults to 2.0, clamps 0.0..5.0, persists, and resets',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final FractalEngine engine1 = FractalEngine();
      addTearDown(engine1.dispose);
      await engine1.init();

      expect(engine1.overscanMultiplier, equals(2.0));

      engine1.setOverscanMultiplier(-1.5);
      expect(engine1.overscanMultiplier, equals(0.0));

      engine1.setOverscanMultiplier(9.0);
      expect(engine1.overscanMultiplier, equals(5.0));

      engine1.setOverscanMultiplier(3.25);
      expect(engine1.overscanMultiplier, equals(3.25));

      final FractalEngine engine2 = FractalEngine();
      addTearDown(engine2.dispose);
      await engine2.init();
      expect(engine2.overscanMultiplier, equals(3.25));

      engine2.resetAllSettings();
      expect(engine2.overscanMultiplier, equals(2.0));

      final FractalEngine engine3 = FractalEngine();
      addTearDown(engine3.dispose);
      await engine3.init();
      expect(engine3.overscanMultiplier, equals(2.0));
    });

    test('keybinds expose defaults, persist setKeybind(), and resetKeybinds()',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final FractalEngine engine1 = FractalEngine();
      addTearDown(engine1.dispose);
      await engine1.init();

      expect(
        engine1.keybindFor(FractalKeyAction.panUp),
        equals(LogicalKeyboardKey.keyW),
      );
      for (final FractalKeyAction action in FractalKeyAction.values) {
        expect(engine1.keybinds[action], equals(action.defaultKey));
      }

      engine1.setKeybind(FractalKeyAction.panUp, LogicalKeyboardKey.arrowUp);
      engine1.setKeybind(FractalKeyAction.zoomIn, LogicalKeyboardKey.numpadAdd);
      expect(
        engine1.keybindFor(FractalKeyAction.panUp),
        equals(LogicalKeyboardKey.arrowUp),
      );
      expect(
        engine1.keybindFor(FractalKeyAction.zoomIn),
        equals(LogicalKeyboardKey.numpadAdd),
      );

      final FractalEngine engine2 = FractalEngine();
      addTearDown(engine2.dispose);
      await engine2.init();
      expect(
        engine2.keybindFor(FractalKeyAction.panUp),
        equals(LogicalKeyboardKey.arrowUp),
      );
      expect(
        engine2.keybindFor(FractalKeyAction.zoomIn),
        equals(LogicalKeyboardKey.numpadAdd),
      );

      engine2.resetKeybinds();
      expect(
        engine2.keybindFor(FractalKeyAction.panUp),
        equals(LogicalKeyboardKey.keyW),
      );
      expect(
        engine2.keybindFor(FractalKeyAction.zoomIn),
        equals(LogicalKeyboardKey.equal),
      );

      final FractalEngine engine3 = FractalEngine();
      addTearDown(engine3.dispose);
      await engine3.init();
      expect(
        engine3.keybindFor(FractalKeyAction.panUp),
        equals(LogicalKeyboardKey.keyW),
      );
    });
  });

  group('Rotation math and Auto-Adaptive LOD', () {
    test(
        'rotated screenToWorld, panBy, and transformAtFocalPoint with rotationDelta preserve focal-point world coordinate',
        () {
      final FractalEngine engine = FractalEngine();
      addTearDown(engine.dispose);

      const Size viewport = Size(800, 600);
      const Offset focalPos = Offset(260, 190);
      const Offset focalDelta = Offset(28, -14);
      const double scaleFactor = 1.8;
      const double rotationDelta = 0.45;

      // Set an initial non-zero rotation and verify rotated screenToWorld & panBy.
      engine.setRotation(math.pi / 3.0);
      const Offset pointer = Offset(520, 410);
      const Offset panDelta = Offset(75, -45);
      final Offset worldBeforePan = engine.screenToWorld(pointer, viewport);
      engine.panBy(panDelta, persist: false);
      final Offset worldAfterPan =
          engine.screenToWorld(pointer + panDelta, viewport);
      expect((worldAfterPan.dx - worldBeforePan.dx).abs(), lessThan(1e-9));
      expect((worldAfterPan.dy - worldBeforePan.dy).abs(), lessThan(1e-9));

      // Simultaneous pan + zoom + rotationDelta around focalPos preserves world coordinate.
      final Offset anchoredWorld =
          engine.screenToWorld(focalPos - focalDelta, viewport);
      engine.transformAtFocalPoint(
        focalPos: focalPos,
        focalDelta: focalDelta,
        scaleFactor: scaleFactor,
        rotationDelta: rotationDelta,
        viewport: viewport,
        persist: false,
      );
      final Offset worldAtNewFocal = engine.screenToWorld(focalPos, viewport);
      expect((worldAtNewFocal.dx - anchoredWorld.dx).abs(), lessThan(1e-9));
      expect((worldAtNewFocal.dy - anchoredWorld.dy).abs(), lessThan(1e-9));
    });

    test(
        'autoAdaptiveLod steps effectiveDragScale down on slow frames, up on fast frames, and falls back to dragPreviewScale when disabled',
        () {
      final FractalEngine engine = FractalEngine();
      addTearDown(engine.dispose);

      expect(engine.autoAdaptiveLod, isTrue);
      final double initialScale = engine.effectiveDragScale;

      // Slow frames (60.0 ms > 28.0 ms) step effectiveDragScale down.
      for (int i = 0; i < 4; i++) {
        engine.recordFrameDurationMs(60.0);
      }
      final double steppedDown = engine.effectiveDragScale;
      expect(steppedDown, lessThan(initialScale));

      // Fast frames (5.0 ms < 12.0 ms) step effectiveDragScale back up.
      for (int i = 0; i < 6; i++) {
        engine.recordFrameDurationMs(5.0);
      }
      expect(engine.effectiveDragScale, greaterThan(steppedDown));

      // Disabling autoAdaptiveLod returns dragPreviewScale directly.
      engine.setDragPreviewScale(0.35);
      engine.setAutoAdaptiveLod(false);
      expect(engine.effectiveDragScale, closeTo(0.35, 1e-6));
    });

    test(
        'recordRenderCostSample + predictOptimalScale lowers s* on heavy samples and raises s* on light samples',
        () {
      final FractalEngine engine = FractalEngine();
      addTearDown(engine.dispose);

      engine.updateViewportPixelArea(1000000);
      final double baseline = engine.predictOptimalScale(
        mode: ActiveRenderMode.gpuDf64,
        viewportPixels: 1000000,
        iterations: 300,
      );

      // Feed heavy render cost samples (long duration for small pixel count).
      for (int i = 0; i < 4; i++) {
        engine.recordRenderCostSample(
          mode: ActiveRenderMode.gpuDf64,
          pixelCount: 50000,
          iterations: 300,
          durationMs: 45.0,
        );
      }
      final double afterHeavy = engine.predictOptimalScale(
        mode: ActiveRenderMode.gpuDf64,
        viewportPixels: 1000000,
        iterations: 300,
      );
      expect(afterHeavy, lessThan(baseline));

      // Feed very light render cost samples -> s* rises.
      for (int i = 0; i < 20; i++) {
        engine.recordRenderCostSample(
          mode: ActiveRenderMode.gpuDf64,
          pixelCount: 1000000,
          iterations: 300,
          durationMs: 1.0,
        );
      }
      final double afterLight = engine.predictOptimalScale(
        mode: ActiveRenderMode.gpuDf64,
        viewportPixels: 1000000,
        iterations: 300,
      );
      expect(afterLight, greaterThan(afterHeavy));
    });

    test(
        'monotonic-down gesture lock prevents effectiveDragScale from increasing during interaction and drops on heavy sample',
        () {
      final FractalEngine engine = FractalEngine();
      addTearDown(engine.dispose);

      engine.updateViewportPixelArea(1000000);
      engine.setInteracting(true);
      expect(engine.isInteracting, isTrue);

      final double lockedStart = engine.effectiveDragScale;

      // Fast / light samples must NOT raise effectiveDragScale during interaction.
      for (int i = 0; i < 10; i++) {
        engine.recordRenderCostSample(
          mode: ActiveRenderMode.gpuFloat32,
          pixelCount: 1000000,
          iterations: 120,
          durationMs: 0.5,
        );
        engine.recordFrameDurationMs(4.0);
        engine.recordBakeDurationForLod(2.0);
        expect(engine.effectiveDragScale, lessThanOrEqualTo(lockedStart));
      }

      // Heavy sample drops effectiveDragScale immediately even mid-gesture.
      engine.recordRenderCostSample(
        mode: ActiveRenderMode.gpuFloat32,
        pixelCount: 20000,
        iterations: 500,
        durationMs: 80.0,
      );
      expect(engine.effectiveDragScale, lessThan(lockedStart));
    });
  });

  group('CPU render progress, cancellation & engine progress state', () {
    CpuRenderRequest buildRequest({
      required int width,
      required int height,
      required int maxIterations,
    }) {
      return CpuRenderRequest(
        width: width,
        height: height,
        logicalWidth: width.toDouble(),
        logicalHeight: height.toDouble(),
        centerX: -0.5,
        centerY: 0.0,
        zoom: width * 0.4,
        maxIterations: maxIterations,
        fractalTypeIndex: 0,
        juliaCx: -0.7269,
        juliaCy: 0.1889,
        paletteIndex: 1,
        primaryR: 0.4,
        primaryG: 0.6,
        primaryB: 0.9,
        secondaryR: 0.9,
        secondaryG: 0.5,
        secondaryB: 0.2,
        colorOffset: 0.0,
        smoothColor: true,
      );
    }

    test(
        'CpuFractalRenderer.renderRgba streams monotonic onProgress ending at 1.0 (single & multi-isolate)',
        () async {
      // Single-isolate path (< 20,000 px).
      final List<double> smallProgress = <double>[];
      final Uint8List smallRgba = await CpuFractalRenderer.renderRgba(
        buildRequest(width: 64, height: 48, maxIterations: 20),
        onProgress: smallProgress.add,
      );
      expect(smallRgba.length, equals(64 * 48 * 4));
      expect(smallProgress, isNotEmpty);
      expect(smallProgress.last, equals(1.0));
      for (int i = 1; i < smallProgress.length; i++) {
        expect(smallProgress[i], greaterThanOrEqualTo(smallProgress[i - 1]));
      }

      // Multi-isolate path (>= 20,000 px).
      final List<double> largeProgress = <double>[];
      final Uint8List largeRgba = await CpuFractalRenderer.renderRgba(
        buildRequest(width: 200, height: 120, maxIterations: 20),
        onProgress: largeProgress.add,
      );
      expect(largeRgba.length, equals(200 * 120 * 4));
      expect(largeProgress.length, greaterThan(1));
      expect(largeProgress.last, equals(1.0));
      for (int i = 0; i < largeProgress.length; i++) {
        expect(largeProgress[i], inInclusiveRange(0.0, 1.0));
        if (i > 0) {
          expect(largeProgress[i], greaterThanOrEqualTo(largeProgress[i - 1]));
        }
      }
    });

    test(
        'CpuRenderCancellationToken.cancel() aborts multi-isolate renderRgba with CpuRenderCancelledException',
        () async {
      final CpuRenderCancellationToken token = CpuRenderCancellationToken();
      bool cancelled = false;

      await expectLater(
        CpuFractalRenderer.renderRgba(
          buildRequest(width: 320, height: 240, maxIterations: 2000),
          cancellationToken: token,
          onProgress: (double progress) {
            if (!cancelled && progress > 0.0) {
              cancelled = true;
              token.cancel();
            }
          },
        ),
        throwsA(isA<CpuRenderCancelledException>()),
      );
      expect(token.isCancelled, isTrue);
    });

    test(
        'FractalEngine progress state tracks activeProgress, hasActiveProgress, and resets on completion',
        () {
      final FractalEngine engine = FractalEngine();
      addTearDown(engine.dispose);

      expect(engine.renderProgress, isNull);
      expect(engine.exportProgress, isNull);
      expect(engine.activeProgress, isNull);
      expect(engine.hasActiveProgress, isFalse);

      // CPU render progress.
      engine.setCpuRendering(true);
      expect(engine.hasActiveProgress, isFalse);
      engine.setRenderProgress(0.42);
      expect(engine.renderProgress, closeTo(0.42, 1e-9));
      expect(engine.activeProgress, closeTo(0.42, 1e-9));
      expect(engine.hasActiveProgress, isTrue);

      // Export progress takes precedence over CPU render progress.
      engine.setExporting(true);
      expect(engine.hasActiveProgress, isTrue);
      expect(engine.activeProgress, equals(0.0));
      engine.setExportProgress(0.75);
      expect(engine.exportProgress, closeTo(0.75, 1e-9));
      expect(engine.activeProgress, closeTo(0.75, 1e-9));

      // Stopping export resets exportProgress to null and falls back to renderProgress.
      engine.setExporting(false);
      expect(engine.exportProgress, isNull);
      expect(engine.activeProgress, closeTo(0.42, 1e-9));
      expect(engine.hasActiveProgress, isTrue);

      // Stopping CPU rendering resets renderProgress to null.
      engine.setCpuRendering(false);
      expect(engine.renderProgress, isNull);
      expect(engine.activeProgress, isNull);
      expect(engine.hasActiveProgress, isFalse);
    });
  });

  group('Perturbation Theory, BigFixed & 10^50+ Deep Zoom', () {
    test(
        'BigFixed preserves 1e-100 deltas, 60-digit decimal roundtrip, and arithmetic accuracy',
        () {
      // 1e-100 delta added to 1.0 collapses in IEEE-754 double, but survives in BigFixed.
      final BigFixed one = BigFixed.fromDouble(1.0, 512);
      final BigFixed tinyDelta = BigFixed.fromDouble(1e-100, 512);
      expect(tinyDelta.toDouble(), closeTo(1e-100, 1e-112));
      final BigFixed sumWithTiny = one + tinyDelta;
      expect(sumWithTiny, isNot(equals(one)));
      expect((sumWithTiny - one).toDouble(), closeTo(1e-100, 1e-112));

      // 60-digit decimal parseDecimal / toDecimalString roundtrip.
      const String decimal60 =
          '-0.743643887037158704752191506114774123456789012345678901234567';
      final BigFixed parsed = BigFixed.parseDecimal(decimal60, 256);
      expect(parsed.toDecimalString(60), equals(decimal60));

      // +, -, *, and square() accuracy.
      final BigFixed a = BigFixed.parseDecimal('1.25', 128);
      final BigFixed b = BigFixed.parseDecimal('-0.5', 128);
      expect((a + b).toDecimalString(4, trimTrailingZeros: true), equals('0.75'));
      expect((a - b).toDecimalString(4, trimTrailingZeros: true), equals('1.75'));
      expect((a * b).toDecimalString(4, trimTrailingZeros: true), equals('-0.625'));
      expect(
        a.square().toDecimalString(6, trimTrailingZeros: true),
        equals('1.5625'),
      );
      expect(a.square(), equals(a * a));
    });

    test(
        'PerturbationSolver.computeOrbitSync computes Deep Spiral 1e30 orbit and RGBA texture',
        () {
      const double zoom = 1e30;
      final PerturbationOrbitRequest request = PerturbationOrbitRequest(
        centerXDecimal: '-0.743643887037158704752191506114774',
        centerYDecimal: '0.131825904205311970493132056385139',
        zoom: zoom,
        maxIterations: 1000,
        fractalTypeIndex: 0,
        juliaCx: 0.0,
        juliaCy: 0.0,
        viewportHalfDiagPx: 500.0,
        fracBits: requiredPrecisionBits(zoom),
      );

      final PerturbationOrbitResult result =
          PerturbationSolver.computeOrbitSync(request);

      expect(result.refLen, greaterThan(100));
      expect(result.saSkip, greaterThan(0));
      expect(result.rgbaBytes.length, equals(256 * 32 * 4));

      // Sampled orbit texels must have opaque alpha (A == 255).
      final List<int> sampleTexels = <int>[
        0,
        1,
        result.refLen ~/ 2,
        result.refLen - 1,
      ];
      for (final int idx in sampleTexels) {
        expect(result.rgbaBytes[idx * 4 + 3], equals(255));
      }
    });

    test(
        'FractalEngine preserves BigFixed centerXBig/centerYBig across panBy and transformAtFocalPoint at 1e50',
        () {
      final FractalEngine engine = FractalEngine();
      addTearDown(engine.dispose);

      const Size viewport = Size(800, 600);
      final Offset center = viewport.center(Offset.zero);

      engine.zoomAtFocalPoint(
        center,
        viewport,
        1e50 / engine.zoom,
        persist: false,
      );
      expect(engine.zoom, closeTo(1e50, 1e38));
      expect(engine.activeRenderMode, equals(ActiveRenderMode.gpuPerturbation));

      final BigFixed initialX = engine.centerXBig;
      final BigFixed initialY = engine.centerYBig;

      // A 10px pan at 1e50 zoom is ~1e-49 in world space — invisible to double,
      // but preserved exactly in BigFixed centerXBig/centerYBig.
      engine.panBy(const Offset(10, -5), persist: false);
      final BigFixed afterPanX = engine.centerXBig;
      final BigFixed afterPanY = engine.centerYBig;
      expect(afterPanX, isNot(equals(initialX)));
      expect(afterPanY, isNot(equals(initialY)));

      engine.transformAtFocalPoint(
        focalPos: const Offset(250, 180),
        focalDelta: const Offset(4, -3),
        scaleFactor: 1.5,
        viewport: viewport,
        persist: false,
      );
      expect(engine.zoom, greaterThan(1e50));
      expect(engine.centerXBig, isNot(equals(afterPanX)));
      expect(engine.centerYBig, isNot(equals(afterPanY)));
    });

    test(
        'PerturbationOrbitResult.orbitZoom matches request.zoom and saScale produces identical initial d across uSize/dpr/zoom ratios',
        () {
      const double orbitZoom = 1e30;
      const double viewportWidth = 400.0;
      final PerturbationOrbitRequest request = PerturbationOrbitRequest(
        centerXDecimal: '-0.743643887037158704752191506114774',
        centerYDecimal: '0.131825904205311970493132056385139',
        zoom: orbitZoom,
        maxIterations: 1000,
        fractalTypeIndex: 0,
        juliaCx: 0.0,
        juliaCy: 0.0,
        viewportHalfDiagPx: 500.0,
        fracBits: requiredPrecisionBits(orbitZoom),
      );

      final PerturbationOrbitResult result =
          PerturbationSolver.computeOrbitSync(request);

      expect(result.orbitZoom, equals(request.zoom));
      expect(result.saSkip, greaterThan(0));

      // Evaluate initial SA delta d = uSaA*dp + uSaB*dp^2 + uSaC*dp^3 for a
      // fixed world-space offset from the reference center across differing
      // (uSize, dpr, zoom) configurations.
      (double, double) evalSaDelta({
        required double zoom,
        required double uSizeWidth,
        required double deltaPxRefRe,
        required double deltaPxRefIm,
      }) {
        final double saScale =
            (result.orbitZoom / zoom) * (viewportWidth / uSizeWidth);
        final double saScale2 = saScale * saScale;
        final double saScale3 = saScale2 * saScale;

        final double uSaARe = result.saARe * saScale;
        final double uSaAIm = result.saAIm * saScale;
        final double uSaBRe = result.saBRe * saScale2;
        final double uSaBIm = result.saBIm * saScale2;
        final double uSaCRe = result.saCRe * saScale3;
        final double uSaCIm = result.saCIm * saScale3;

        // Same world-space offset in the target (uSizeWidth, zoom) pixel grid.
        final double dpRe = deltaPxRefRe / saScale;
        final double dpIm = deltaPxRefIm / saScale;

        final double dp2Re = dpRe * dpRe - dpIm * dpIm;
        final double dp2Im = 2.0 * dpRe * dpIm;
        final double dp3Re = dp2Re * dpRe - dp2Im * dpIm;
        final double dp3Im = dp2Re * dpIm + dp2Im * dpRe;

        final double dRe = (uSaARe * dpRe - uSaAIm * dpIm) +
            (uSaBRe * dp2Re - uSaBIm * dp2Im) +
            (uSaCRe * dp3Re - uSaCIm * dp3Im);
        final double dIm = (uSaARe * dpIm + uSaAIm * dpRe) +
            (uSaBRe * dp2Im + uSaBIm * dp2Re) +
            (uSaCRe * dp3Im + uSaCIm * dp3Re);
        return (dRe, dIm);
      }

      const double refPxRe = 120.0;
      const double refPxIm = -75.0;
      final (double baseRe, double baseIm) = evalSaDelta(
        zoom: orbitZoom,
        uSizeWidth: viewportWidth,
        deltaPxRefRe: refPxRe,
        deltaPxRefIm: refPxIm,
      );

      final List<({double zoom, double dpr, double lod})> configs =
          <({double zoom, double dpr, double lod})>[
        (zoom: orbitZoom, dpr: 3.0, lod: 1.0),
        (zoom: orbitZoom, dpr: 3.0, lod: 0.10),
        (zoom: orbitZoom * 2.5, dpr: 2.0, lod: 0.25),
        (zoom: orbitZoom * 0.8, dpr: 1.5, lod: 0.50),
      ];

      for (final cfg in configs) {
        final (double dRe, double dIm) = evalSaDelta(
          zoom: cfg.zoom,
          uSizeWidth: viewportWidth * cfg.dpr * cfg.lod,
          deltaPxRefRe: refPxRe,
          deltaPxRefIm: refPxIm,
        );
        expect(dRe, closeTo(baseRe, 1e-12));
        expect(dIm, closeTo(baseIm, 1e-12));
      }
    });

    test('FractalEngine.formatZoom formats 1e29 and 1e100 without 64-bit int overflow',
        () {
      expect(FractalEngine.formatZoom(240.0 * 7.21e29), equals('7.21e29×'));
      expect(FractalEngine.formatZoom(240.0 * 1e100), equals('1.00e100×'));
    });
  });

  group('Potatoemeter Hardware Benchmark & Calibration', () {
    test(
        'PotatoBenchmarkResult tierForScore, computeScore, JSON roundtrip, and toShareSummary',
        () {
      expect(PotatoBenchmarkResult.tierForScore(1), equals('Raw Spud'));
      expect(PotatoBenchmarkResult.tierForScore(99), equals('Raw Spud'));
      expect(PotatoBenchmarkResult.tierForScore(100), equals('Baked Potato'));
      expect(PotatoBenchmarkResult.tierForScore(249), equals('Baked Potato'));
      expect(PotatoBenchmarkResult.tierForScore(250), equals('Loaded Fries'));
      expect(PotatoBenchmarkResult.tierForScore(499), equals('Loaded Fries'));
      expect(
          PotatoBenchmarkResult.tierForScore(500), equals('Golden Hashbrown'));
      expect(
          PotatoBenchmarkResult.tierForScore(899), equals('Golden Hashbrown'));
      expect(PotatoBenchmarkResult.tierForScore(900), equals('Turbo Tater'));
      expect(PotatoBenchmarkResult.tierForScore(1499), equals('Turbo Tater'));
      expect(PotatoBenchmarkResult.tierForScore(1500), equals('Quantum Yam'));

      final int score = PotatoBenchmarkResult.computeScore(
        gpuF32MIter: 1000.0,
        gpuDf64MIter: 50.0,
        cpuF64MIter: 25.0,
      );
      expect(score, equals(14));
      expect(
        PotatoBenchmarkResult.computeScore(
          gpuF32MIter: 10000.0,
          gpuDf64MIter: 500.0,
          cpuF64MIter: 200.0,
        ),
        equals(130),
      );
      expect(
        PotatoBenchmarkResult.computeScore(
          gpuF32MIter: 0.0,
          gpuDf64MIter: 0.0,
          cpuF64MIter: 0.0,
        ),
        equals(1),
      );

      final PotatoBenchmarkResult original = PotatoBenchmarkResult(
        score: score,
        tier: PotatoBenchmarkResult.tierForScore(score),
        gpuF32MIterPerSec: 1000.0,
        gpuDf64MIterPerSec: 50.0,
        cpuF64MIterPerSec: 25.0,
        kGpuF32: 1.0e-9,
        kGpuDf64: 2.0e-8,
        kCpuF64: 4.0e-8,
        completedAtMs: 1763928000000,
      );

      final Map<String, dynamic> jsonMap =
          jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>;
      final PotatoBenchmarkResult restored =
          PotatoBenchmarkResult.fromJson(jsonMap);
      expect(restored.score, equals(original.score));
      expect(restored.tier, equals('Raw Spud'));
      expect(restored.gpuF32MIterPerSec, equals(original.gpuF32MIterPerSec));
      expect(restored.gpuDf64MIterPerSec, equals(original.gpuDf64MIterPerSec));
      expect(restored.cpuF64MIterPerSec, equals(original.cpuF64MIterPerSec));
      expect(restored.kGpuF32, equals(original.kGpuF32));
      expect(restored.kGpuDf64, equals(original.kGpuDf64));
      expect(restored.kCpuF64, equals(original.kCpuF64));
      expect(restored.completedAtMs, equals(original.completedAtMs));

      expect(
        original.toShareSummary(),
        equals(
          'Potatoemeter: 14 (Raw Spud) | '
          'GPU f32: 1000.0 MIter/s | '
          'GPU df64: 50.0 MIter/s | '
          'CPU f64: 25.0 MIter/s',
        ),
      );
    });

    test(
        'FractalEngine.applyBenchmarkResult updates calibration, predicts LOD, and persists across init()',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final FractalEngine engine = FractalEngine();
      await engine.init();

      const PotatoBenchmarkResult fastDevice = PotatoBenchmarkResult(
        score: 1600,
        tier: 'Quantum Yam',
        gpuF32MIterPerSec: 4000.0,
        gpuDf64MIterPerSec: 120.0,
        cpuF64MIterPerSec: 70.0,
        kGpuF32: 2.5e-10,
        kGpuDf64: 8.0e-9,
        kCpuF64: 1.4e-8,
        completedAtMs: 1763928100000,
      );

      engine.applyBenchmarkResult(fastDevice);
      expect(engine.lastBenchmark?.score, equals(1600));
      expect(engine.lastBenchmark?.tier, equals('Quantum Yam'));
      expect(
        engine.costPerPixelIterFor(ActiveRenderMode.gpuFloat32),
        closeTo(2.5e-10, 1e-15),
      );
      expect(
        engine.costPerPixelIterFor(ActiveRenderMode.gpuDf64),
        closeTo(8.0e-9, 1e-15),
      );
      expect(
        engine.costPerPixelIterFor(ActiveRenderMode.cpuFloat64),
        closeTo(1.4e-8, 1e-15),
      );
      expect(
        engine.costPerPixelIterFor(ActiveRenderMode.gpuPerturbation),
        closeTo(2.0e-9, 1e-15),
      );

      final double fastPredicted = engine.predictOptimalScale(
        mode: ActiveRenderMode.gpuDf64,
        viewportPixels: 1920 * 1080,
        iterations: 300,
      );
      expect(fastPredicted, greaterThan(0.02));
      expect(fastPredicted, lessThanOrEqualTo(0.50));

      // Verify a slower device produces a lower predicted scale than a fast one.
      final FractalEngine slowEngine = FractalEngine();
      await slowEngine.init();
      const PotatoBenchmarkResult slowDevice = PotatoBenchmarkResult(
        score: 40,
        tier: 'Raw Spud',
        gpuF32MIterPerSec: 40.0,
        gpuDf64MIterPerSec: 2.0,
        cpuF64MIterPerSec: 3.0,
        kGpuF32: 2.5e-8,
        kGpuDf64: 5.0e-7,
        kCpuF64: 3.3e-7,
        completedAtMs: 1763928200000,
      );
      slowEngine.applyBenchmarkResult(slowDevice);
      final double slowPredicted = slowEngine.predictOptimalScale(
        mode: ActiveRenderMode.gpuDf64,
        viewportPixels: 1920 * 1080,
        iterations: 300,
      );
      expect(slowPredicted, lessThan(fastPredicted));
      slowEngine.dispose();

      // Re-apply fastDevice to engine so SharedPreferences holds fastDevice,
      // then restore into a fresh FractalEngine instance via init().
      engine.applyBenchmarkResult(fastDevice);
      engine.dispose();

      final FractalEngine restored = FractalEngine();
      addTearDown(restored.dispose);
      await restored.init();

      expect(restored.lastBenchmark, isNotNull);
      expect(restored.lastBenchmark!.score, equals(1600));
      expect(restored.lastBenchmark!.tier, equals('Quantum Yam'));
      expect(
        restored.costPerPixelIterFor(ActiveRenderMode.gpuFloat32),
        closeTo(2.5e-10, 1e-15),
      );
      expect(
        restored.costPerPixelIterFor(ActiveRenderMode.gpuDf64),
        closeTo(8.0e-9, 1e-15),
      );
      expect(
        restored.costPerPixelIterFor(ActiveRenderMode.cpuFloat64),
        closeTo(1.4e-8, 1e-15),
      );
      expect(
        restored.costPerPixelIterFor(ActiveRenderMode.gpuPerturbation),
        closeTo(2.0e-9, 1e-15),
      );
    });

    test(
        'FractalEngine.liveAdaptiveRating reflects updated costPerPixelIter values',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final FractalEngine engine = FractalEngine();
      addTearDown(engine.dispose);
      await engine.init();

      final PotatoBenchmarkResult baseline = engine.liveAdaptiveRating;
      expect(baseline.score, greaterThanOrEqualTo(1));
      expect(
        baseline.tier,
        equals(PotatoBenchmarkResult.tierForScore(baseline.score)),
      );

      // Simulate fast GPU/CPU render samples to lower costPerPixelIter.
      for (int i = 0; i < 20; i++) {
        engine.recordRenderCostSample(
          mode: ActiveRenderMode.gpuFloat32,
          pixelCount: 1000000,
          iterations: 1000,
          durationMs: 5.0,
        );
        engine.recordRenderCostSample(
          mode: ActiveRenderMode.gpuDf64,
          pixelCount: 1000000,
          iterations: 500,
          durationMs: 500.0,
        );
        engine.recordRenderCostSample(
          mode: ActiveRenderMode.cpuFloat64,
          pixelCount: 250000,
          iterations: 400,
          durationMs: 200.0,
        );
      }

      final PotatoBenchmarkResult faster = engine.liveAdaptiveRating;
      expect(faster.score, greaterThan(baseline.score));
      expect(
        faster.gpuF32MIterPerSec,
        greaterThan(baseline.gpuF32MIterPerSec),
      );
      expect(
        faster.gpuDf64MIterPerSec,
        greaterThan(baseline.gpuDf64MIterPerSec),
      );
      expect(
        faster.cpuF64MIterPerSec,
        greaterThan(baseline.cpuF64MIterPerSec),
      );
      expect(
        faster.tier,
        equals(PotatoBenchmarkResult.tierForScore(faster.score)),
      );

      // Simulate slow render samples to raise costPerPixelIter.
      for (int i = 0; i < 20; i++) {
        engine.recordRenderCostSample(
          mode: ActiveRenderMode.gpuFloat32,
          pixelCount: 100000,
          iterations: 100,
          durationMs: 500.0,
        );
        engine.recordRenderCostSample(
          mode: ActiveRenderMode.gpuDf64,
          pixelCount: 100000,
          iterations: 100,
          durationMs: 1000.0,
        );
        engine.recordRenderCostSample(
          mode: ActiveRenderMode.cpuFloat64,
          pixelCount: 100000,
          iterations: 100,
          durationMs: 1000.0,
        );
      }

      final PotatoBenchmarkResult slower = engine.liveAdaptiveRating;
      expect(slower.score, lessThan(faster.score));
      expect(
        slower.gpuF32MIterPerSec,
        lessThan(faster.gpuF32MIterPerSec),
      );
      expect(
        slower.tier,
        equals(PotatoBenchmarkResult.tierForScore(slower.score)),
      );
    });
  });

  group('Deep-Link & QR Bookmark Codec', () {
    test(
        'FractalShareLink.encode and tryParse roundtrip preserves deep 10^25x coordinates, rotation, palette, and Julia c',
        () {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final FractalEngine engine = FractalEngine();
      addTearDown(engine.dispose);

      const String deepX = '-0.74364388703715870475219150611477412';
      const String deepY = '0.13182590420531197049313205638513945';
      const double deepZoom = 1e25 * 240.0;

      engine.applyBookmark(
        const FractalBookmark(
          id: 'deep_test',
          name: 'Deep Spiral',
          fractalType: FractalType.mandelbrot,
          centerX: -0.7436438870371587,
          centerY: 0.13182590420531197,
          centerXDecimal: deepX,
          centerYDecimal: deepY,
          zoom: deepZoom,
          palette: FractalPalette.inferno,
        ),
      );
      engine.setRotation(0.7854);
      engine.setSmoothColor(false);
      engine.setColorOffset(0.375);

      final Uri encodedMandel = FractalShareLink.encode(
        engine,
        name: 'Deep Spiral 10^25x',
      );
      expect(encodedMandel.scheme, equals('https'));
      expect(encodedMandel.host, equals('fractals.puzzak.page'));
      expect(encodedMandel.path, equals('/v'));

      final SharedFractalPayload? parsedMandel =
          FractalShareLink.tryParse(encodedMandel.toString());
      expect(parsedMandel, isNotNull);
      expect(
        parsedMandel!.bookmark.fractalType,
        equals(FractalType.mandelbrot),
      );
      expect(parsedMandel.bookmark.name, equals('Deep Spiral 10^25x'));
      expect(
        parsedMandel.bookmark.centerXDecimal,
        startsWith('-0.7436438870371587047521915061147741'),
      );
      expect(
        parsedMandel.bookmark.centerYDecimal,
        startsWith('0.1318259042053119704931320563851394'),
      );
      expect(
        (parsedMandel.bookmark.zoom - deepZoom).abs() / deepZoom,
        lessThan(1e-9),
      );
      expect(parsedMandel.rotation, closeTo(0.7854, 1e-4));
      expect(parsedMandel.bookmark.palette, equals(FractalPalette.inferno));
      expect(parsedMandel.smoothColor, isFalse);
      expect(parsedMandel.colorOffset, closeTo(0.375, 1e-4));

      // Verify Julia c parameters roundtrip as well.
      engine.setFractalType(FractalType.julia, resetCamera: true);
      engine.setJuliaC(-0.4, 0.6);
      engine.setPalette(FractalPalette.neon);
      engine.setSmoothColor(true);

      final Uri encodedJulia = FractalShareLink.encode(engine, name: 'Julia C');
      final SharedFractalPayload? parsedJulia =
          FractalShareLink.tryParse(encodedJulia.toString());
      expect(parsedJulia, isNotNull);
      expect(parsedJulia!.bookmark.fractalType, equals(FractalType.julia));
      expect(parsedJulia.bookmark.juliaCx, closeTo(-0.4, 1e-9));
      expect(parsedJulia.bookmark.juliaCy, closeTo(0.6, 1e-9));
      expect(parsedJulia.bookmark.palette, equals(FractalPalette.neon));
      expect(parsedJulia.smoothColor, isTrue);
    });

    test(
        'FractalShareLink.tryParse handles custom scheme, raw Play Install Referrer query strings, and rejects invalid URIs',
        () {
      const String customUri =
          'fractals://v?f=burningShip&x=-1.75&y=-0.03&z=4800&p=ocean&s=1&n=Ship';
      final SharedFractalPayload? parsedCustom =
          FractalShareLink.tryParse(customUri);
      expect(parsedCustom, isNotNull);
      expect(
        parsedCustom!.bookmark.fractalType,
        equals(FractalType.burningShip),
      );
      expect(parsedCustom.bookmark.centerX, closeTo(-1.75, 1e-9));
      expect(parsedCustom.bookmark.centerY, closeTo(-0.03, 1e-9));
      expect(parsedCustom.bookmark.zoom, closeTo(4800.0, 1e-9));
      expect(parsedCustom.bookmark.palette, equals(FractalPalette.ocean));
      expect(parsedCustom.bookmark.name, equals('Ship'));

      const String rawReferrer =
          'f=tricorn&x=0.125&y=-0.25&z=1200&r=0.5&p=twilight&s=0&co=0.25';
      final SharedFractalPayload? parsedReferrer =
          FractalShareLink.tryParse(rawReferrer);
      expect(parsedReferrer, isNotNull);
      expect(
        parsedReferrer!.bookmark.fractalType,
        equals(FractalType.tricorn),
      );
      expect(parsedReferrer.bookmark.centerX, closeTo(0.125, 1e-9));
      expect(parsedReferrer.bookmark.centerY, closeTo(-0.25, 1e-9));
      expect(parsedReferrer.bookmark.zoom, closeTo(1200.0, 1e-9));
      expect(parsedReferrer.rotation, closeTo(0.5, 1e-9));
      expect(parsedReferrer.bookmark.palette, equals(FractalPalette.twilight));
      expect(parsedReferrer.smoothColor, isFalse);
      expect(parsedReferrer.colorOffset, closeTo(0.25, 1e-9));

      // Backward-compatible legacy puzzak.page/fractals/v links remain parseable.
      final SharedFractalPayload? parsedLegacy = FractalShareLink.tryParse(
        'https://puzzak.page/fractals/v?f=mandelbrot&x=-0.5&y=0&z=240&p=viridis',
      );
      expect(parsedLegacy, isNotNull);
      expect(parsedLegacy!.bookmark.fractalType, equals(FractalType.mandelbrot));
      expect(parsedLegacy.bookmark.centerX, closeTo(-0.5, 1e-9));
      expect(parsedLegacy.bookmark.zoom, closeTo(240.0, 1e-9));
      expect(parsedLegacy.bookmark.palette, equals(FractalPalette.viridis));

      // Invalid / non-fractal inputs return null.
      expect(FractalShareLink.tryParse(null), isNull);
      expect(FractalShareLink.tryParse(''), isNull);
      expect(
        FractalShareLink.tryParse('https://example.com/fractals/v?f=mandelbrot&x=0&y=0&z=100'),
        isNull,
      );
      expect(
        FractalShareLink.tryParse('fractals://other?f=mandelbrot&x=0&y=0&z=100'),
        isNull,
      );
      expect(
        FractalShareLink.tryParse('https://fractals.puzzak.page/v?f=mandelbrot&x=0&y=0&z=0'),
        isNull,
      );
      expect(
        FractalShareLink.tryParse('https://puzzak.page/fractals/v?f=mandelbrot&x=0&y=0&z=0'),
        isNull,
      );
      expect(
        FractalShareLink.tryParse('f=mandelbrot&x=not_a_number&y=0&z=100'),
        isNull,
      );
    });

    test(
        'FractalShareLink.playStoreDeferredUrl embeds encoded query inside referrer',
        () {
      final Uri shareUri = Uri.https(
        'fractals.puzzak.page',
        '/v',
        <String, String>{
          'f': 'mandelbrot',
          'x': '-0.5',
          'y': '0.0',
          'z': '240',
          'p': 'viridis',
        },
      );
      final Uri deferred = FractalShareLink.playStoreDeferredUrl(shareUri);

      expect(deferred.scheme, equals('https'));
      expect(deferred.host, equals('play.google.com'));
      expect(deferred.path, equals('/store/apps/details'));
      expect(
        deferred.queryParameters['id'],
        equals(FractalShareLink.playStorePackage),
      );
      expect(deferred.queryParameters['referrer'], equals(shareUri.query));

      final SharedFractalPayload? fromReferrer =
          FractalShareLink.tryParse(deferred.queryParameters['referrer']);
      expect(fromReferrer, isNotNull);
      expect(
        fromReferrer!.bookmark.fractalType,
        equals(FractalType.mandelbrot),
      );
      expect(fromReferrer.bookmark.palette, equals(FractalPalette.viridis));
    });
  });
}
