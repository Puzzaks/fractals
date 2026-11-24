import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fractals/engine/fractal_engine.dart';
import 'package:fractals/engine/fractal_models.dart';
import 'package:fractals/main.dart';
import 'package:fractals/widgets/fractal_canvas.dart';
import 'package:fractals/widgets/hud_overlay.dart';
import 'package:fractals/widgets/inspector_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    rootBundle.clear();
  });

  tearDown(() {
    rootBundle.clear();
  });

  Future<FractalEngine> createInitializedEngine(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final FractalEngine engine = FractalEngine();
    addTearDown(engine.dispose);
    await tester.runAsync(() async {
      await engine.init();
      await rootBundle.loadString('CHANGELOG.md');
    });
    return engine;
  }

  Future<void> pumpAppAtSize(
    WidgetTester tester,
    Size size, {
    FractalEngine? engine,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FractalViewerApp(engine: engine));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  }

  Future<void> disposeAppCleanly(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets(
      'Phone layout (400x800): framed HUD, long-press fullscreen toggle, and 35/65 split inspector',
      (WidgetTester tester) async {
    final FractalEngine engine = await createInitializedEngine(tester);
    await pumpAppAtSize(tester, const Size(400, 800), engine: engine);
    expect(tester.takeException(), isNull);

    final Finder canvas = find.byType(FractalCanvas);
    final Finder statusRow = find.byType(HudStatusRow);
    final Finder bottomBar = find.byType(HudBottomBar);

    expect(canvas, findsOneWidget);
    expect(statusRow, findsOneWidget);
    expect(bottomBar, findsOneWidget);
    expect(engine.showHud, isTrue);

    // Status row renders zoom magnification and formatted coordinates.
    expect(
      find.descendant(of: statusRow, matching: find.text('1.00×')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: statusRow,
        matching: find.textContaining('-0.5000, 0.0000'),
      ),
      findsOneWidget,
    );

    // Bottom bar action buttons appear cleanly without overflow.
    expect(
      find.descendant(of: bottomBar, matching: find.text('Mandelbrot')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: bottomBar,
        matching: find.byIcon(Icons.palette_rounded),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: bottomBar,
        matching: find.byIcon(Icons.bookmarks_rounded),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: statusRow,
        matching: find.byIcon(Icons.restart_alt_rounded),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: bottomBar,
        matching: find.byIcon(Icons.visibility_off_rounded),
      ),
      findsNothing,
    );
    final Finder tuneButton = find.descendant(
      of: bottomBar,
      matching: find.byIcon(Icons.tune_rounded),
    );
    expect(tuneButton, findsOneWidget);

    // Tapping the bottom-bar Fractal pill opens showFractalSelectorSheet.
    final Finder fractalPill = find.descendant(
      of: bottomBar,
      matching: find.text('Mandelbrot'),
    );
    await tester.tap(fractalPill);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Select Fractal'), findsOneWidget);
    expect(find.text('Julia'), findsOneWidget);

    await tester.tap(find.text('Julia'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(engine.fractalType, equals(FractalType.julia));
    expect(
      find.descendant(of: bottomBar, matching: find.text('Julia')),
      findsOneWidget,
    );

    // Switch back to Mandelbrot via the selector sheet.
    await tester.tap(
      find.descendant(of: bottomBar, matching: find.text('Julia')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mandelbrot').last);
    await tester.pumpAndSettle();
    expect(engine.fractalType, equals(FractalType.mandelbrot));

    // Long-press on FractalCanvas enters fullscreen (no corner restore button).
    await tester.longPress(canvas);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(engine.showHud, isFalse);
    expect(find.byIcon(Icons.visibility_rounded), findsNothing);
    expect(statusRow.hitTestable(), findsNothing);
    expect(tester.getSize(canvas).height, equals(800.0));

    // Long-press again restores the framed card HUD.
    await tester.longPress(canvas);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(engine.showHud, isTrue);
    expect(statusRow.hitTestable(), findsOneWidget);
    expect(tester.getSize(canvas).height, lessThan(800.0));

    // Tap Settings/Inspector button to enter State 2 (35% / 65% vertical split).
    await tester.ensureVisible(tuneButton);
    await tester.pumpAndSettle();
    await tester.tap(tuneButton);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final Finder inspector = find.byType(FractalInspectorPanel);
    final Finder inspectorNav = find.byType(Navigator).last;
    expect(inspector, findsOneWidget);
    expect(
      find.descendant(of: inspector, matching: find.text('Settings')),
      findsAtLeastNWidgets(1),
    );

    final double canvasHeight = tester.getSize(canvas).height;
    final double inspectorHeight = tester.getSize(inspector).height;
    expect(canvasHeight, lessThan(350.0));
    expect(inspectorHeight, greaterThan(450.0));

    // Verify Settings Hub rows appear inside FractalInspectorPanel.
    final Finder inspectorList = find.descendant(
      of: inspector,
      matching: find.byType(ListView),
    );
    final Finder fractalHubRow = find.descendant(
      of: inspector,
      matching: find.text('Fractals'),
    );
    final Finder controlsHubRow = find.descendant(
      of: inspector,
      matching: find.text('Controls & Keybinds'),
    );
    expect(fractalHubRow, findsOneWidget);
    await tester.scrollUntilVisible(
      controlsHubRow,
      100.0,
      scrollable: find.descendant(
        of: inspectorList,
        matching: find.byType(Scrollable),
      ).first,
    );
    await Scrollable.ensureVisible(
      tester.element(controlsHubRow),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    expect(controlsHubRow.hitTestable(), findsOneWidget);

    // Tap 'Controls & Keybinds' -> sub-page pushes inside the nested Navigator
    // while FractalCanvas remains live.
    await tester.tap(controlsHubRow);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(canvas, findsOneWidget);
    expect(
      find.descendant(
        of: inspectorNav,
        matching: find.byIcon(Icons.arrow_back_rounded),
      ),
      findsOneWidget,
    );

    // Tap Back button -> pops back to the Hub without closing Explorer Controls.
    await tester.tap(
      find.descendant(
        of: inspectorNav,
        matching: find.byIcon(Icons.arrow_back_rounded),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      find.descendant(of: inspector, matching: find.text('Settings')),
      findsAtLeastNWidgets(1),
    );
    expect(tester.getSize(inspector).height, greaterThan(450.0));

    // Push 'Fractal & Parameters' sub-page, switch Mandelbrot -> Julia, and
    // verify Julia Re(c) / Julia Im(c) sliders appear.
    await tester.scrollUntilVisible(
      fractalHubRow,
      -100.0,
      scrollable: find.descendant(
        of: inspectorList,
        matching: find.byType(Scrollable),
      ).first,
    );
    await Scrollable.ensureVisible(
      tester.element(fractalHubRow),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(fractalHubRow);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final Finder juliaSegment = find.descendant(
      of: inspectorNav,
      matching: find.text('Julia'),
    );
    await Scrollable.ensureVisible(
      tester.element(juliaSegment),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(juliaSegment);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final Finder juliaReal = find.descendant(
      of: inspectorNav,
      matching: find.text('Julia Re(c)'),
    );
    await tester.scrollUntilVisible(
      juliaReal,
      100.0,
      scrollable: find.descendant(
        of: inspectorNav,
        matching: find.byType(Scrollable),
      ).first,
    );
    await Scrollable.ensureVisible(
      tester.element(juliaReal),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    expect(juliaReal.hitTestable(), findsOneWidget);

    final Finder juliaImag = find.descendant(
      of: inspectorNav,
      matching: find.text('Julia Im(c)'),
    );
    await Scrollable.ensureVisible(
      tester.element(juliaImag),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    expect(juliaImag.hitTestable(), findsOneWidget);
    expect(
      find.descendant(
        of: inspectorNav,
        matching: find.text('Reset Julia Parameters'),
      ),
      findsOneWidget,
    );

    // Pop back to Hub via Back button without closing Explorer Controls.
    await tester.tap(
      find.descendant(
        of: inspectorNav,
        matching: find.byIcon(Icons.arrow_back_rounded),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      find.descendant(of: inspector, matching: find.text('Settings')),
      findsAtLeastNWidgets(1),
    );

    // Close the inline inspector cleanly.
    await tester.tap(
      find.descendant(
        of: inspector,
        matching: find.byIcon(Icons.close_rounded),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getSize(canvas).height, greaterThan(600.0));

    final Finder animatedInspectorPanel = find.ancestor(
      of: inspector,
      matching: find.byType(AnimatedContainer),
    );
    expect(tester.getSize(animatedInspectorPanel.first).height, equals(0.0));

    // Re-open Explorer Controls and verify single tap on FractalCanvas closes
    // it back to Card HUD.
    await tester.ensureVisible(tuneButton);
    await tester.pumpAndSettle();
    await tester.tap(tuneButton);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getSize(animatedInspectorPanel.first).height, greaterThan(450.0));

    await tester.tap(canvas);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(engine.showHud, isTrue);
    expect(tester.getSize(animatedInspectorPanel.first).height, equals(0.0));
    expect(bottomBar.hitTestable(), findsOneWidget);
    expect(tester.getSize(canvas).height, greaterThan(600.0));

    // Re-open Explorer Controls and verify long-press on FractalCanvas jumps
    // straight to Fullscreen.
    await tester.ensureVisible(tuneButton);
    await tester.pumpAndSettle();
    await tester.tap(tuneButton);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getSize(animatedInspectorPanel.first).height, greaterThan(450.0));

    await tester.longPress(canvas);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(engine.showHud, isFalse);
    expect(tester.getSize(animatedInspectorPanel.first).height, equals(0.0));
    expect(tester.getSize(canvas).height, equals(800.0));

    await disposeAppCleanly(tester);
  });

  testWidgets(
      'Foldable layout (800x900): opening Settings splits 50% / 50% horizontally',
      (WidgetTester tester) async {
    final FractalEngine engine = await createInitializedEngine(tester);
    await pumpAppAtSize(tester, const Size(800, 900), engine: engine);
    expect(tester.takeException(), isNull);

    final Finder canvas = find.byType(FractalCanvas);
    final Finder bottomBar = find.byType(HudBottomBar);
    final Finder inspector = find.byType(FractalInspectorPanel);

    await tester.tap(
      find.descendant(of: bottomBar, matching: find.byIcon(Icons.tune_rounded)),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final double canvasWidth = tester.getSize(canvas).width;
    final double inspectorWidth = tester.getSize(inspector).width;
    expect((canvasWidth - inspectorWidth).abs(), lessThanOrEqualTo(24.0));
    expect(
      find.descendant(of: inspector, matching: find.text('Settings'))
          .hitTestable(),
      findsAtLeastNWidgets(1),
    );

    await disposeAppCleanly(tester);
  });

  testWidgets(
      'Tablet/Laptop layout (1200x800): opening Settings splits 67% / 33% horizontally',
      (WidgetTester tester) async {
    final FractalEngine engine = await createInitializedEngine(tester);
    await pumpAppAtSize(tester, const Size(1200, 800), engine: engine);
    expect(tester.takeException(), isNull);

    final Finder canvas = find.byType(FractalCanvas);
    final Finder bottomBar = find.byType(HudBottomBar);
    final Finder inspector = find.byType(FractalInspectorPanel);

    // Inspector starts collapsed (width == 0).
    final Finder animatedSidePanel = find.ancestor(
      of: inspector,
      matching: find.byType(AnimatedContainer),
    );
    expect(tester.getSize(animatedSidePanel.first).width, equals(0.0));

    // Open the split inspector side panel.
    await tester.tap(
      find.descendant(of: bottomBar, matching: find.byIcon(Icons.tune_rounded)),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final double canvasWidth = tester.getSize(canvas).width;
    final double inspectorWidth = tester.getSize(inspector).width;
    expect((canvasWidth - 2.0 * inspectorWidth).abs(), lessThanOrEqualTo(32.0));
    expect(find.text('Settings').hitTestable(), findsAtLeastNWidgets(1));
    expect(find.text('Fractals').hitTestable(), findsOneWidget);

    // Close the split inspector cleanly.
    await tester.tap(
      find.descendant(
        of: inspector,
        matching: find.byIcon(Icons.close_rounded),
      ).hitTestable(),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(animatedSidePanel.first).width, equals(0.0));
    expect(tester.takeException(), isNull);

    await disposeAppCleanly(tester);
  });

  testWidgets(
      'Default FractalViewerApp smoke test renders and disposes without pending timers',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const FractalViewerApp());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    expect(find.byType(FractalCanvas), findsOneWidget);
    expect(find.byType(HudBottomBar), findsOneWidget);

    await disposeAppCleanly(tester);
  });

  testWidgets(
      'Rapid GPU df64 zoom + finger lift/re-grip keeps effectiveDragScale downscaled',
      (WidgetTester tester) async {
    final FractalEngine engine = await createInitializedEngine(tester);
    const Size viewport = Size(400, 800);
    engine.updateViewportPixelArea(
      (viewport.width * viewport.height).round(),
    );

    engine.setInteracting(true);
    final double initialScale = engine.effectiveDragScale;
    expect(initialScale, inInclusiveRange(0.02, 1.0));

    // Rapidly zoom into GPU df64 range during the active gesture.
    engine.zoomAtFocalPoint(
      const Offset(200, 400),
      viewport,
      1e5,
      persist: false,
    );
    expect(engine.activeRenderMode, equals(ActiveRenderMode.gpuDf64));

    // Finger lift, then immediate re-grip in GPU df64 mode.
    engine.setInteracting(false);
    engine.setInteracting(true);

    expect(engine.activeRenderMode, equals(ActiveRenderMode.gpuDf64));
    expect(engine.effectiveDragScale, inInclusiveRange(0.02, 0.35));
    expect(engine.effectiveDragScale, lessThan(initialScale));
    expect(tester.takeException(), isNull);
  });
}
