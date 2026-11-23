import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset, Size;

import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:fractals/engine/fractal_engine.dart';
import 'package:fractals/engine/fractal_models.dart';
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
          equals((400 * q.iterationMultiplier).round().clamp(50, 2000)),
        );
      }

      // Clamping checks at manual extremes.
      engine.setManualMaxIterations(50);
      engine.setQuality(RenderQuality.performance); // 50 * 0.65 = 32.5 -> 50
      expect(engine.effectiveMaxIterations, equals(50));

      engine.setManualMaxIterations(2000);
      engine.setQuality(RenderQuality.ultra); // 2000 * 1.25 = 2500 -> 2000
      expect(engine.effectiveMaxIterations, equals(2000));
    });

    test(
        'activeRenderMode transitions cleanly across float32 -> df64 -> cpuFloat64 and honors overrides',
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
      expect(engine.activeRenderMode, equals(ActiveRenderMode.cpuFloat64));
      expect(engine.activeRenderMode.isCpu, isTrue);

      // Explicit GPU shader override stays on GPU even above cpuDeepThresholdZoom.
      engine.setBackend(RenderBackend.gpuShader);
      expect(engine.activeRenderMode, equals(ActiveRenderMode.gpuDf64));
      setZoom(240.0);
      expect(engine.activeRenderMode, equals(ActiveRenderMode.gpuFloat32));

      // Explicit CPU float64 override forces CPU at any zoom level.
      engine.setBackend(RenderBackend.cpuFloat64);
      expect(engine.activeRenderMode, equals(ActiveRenderMode.cpuFloat64));
      setZoom(1e8);
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
}
