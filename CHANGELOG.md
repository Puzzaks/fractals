## Update 0.4.1 ([0.4.1] - 2026-11-23)
#### Changes
- **Idle Progressive Sharpening Crossfade (`FractalCanvas`)**: Added a subtle 150 ms ease-out GPU alpha crossfade when idle progressive sharpening (`0.04 → 0.10 → 0.25 → 0.50 → 1.0`) refines a stationary view (cancelled immediately on touch).
- **Contour-Hugging Top-Edge Progress Bar (`_ViewportEdgeProgressBar`)**: Replaced the flat progress bar with a contour-hugging top-edge progress bar that hides in Settings, curves inside the 24 px card border in Framed mode, and hugs the hardware rounded display corners (`RoundedCorner.POSITION_TOP_LEFT`) at the absolute top edge in Fullscreen mode.

## Update 0.4.0 ([0.4.0] - 2026-11-23)
#### Changes
- **Live Render & Export Progress (`CpuFractalRenderer`, `FractalEngine`)**: Added row-level multi-isolate progress reporting (`onProgress`) and cooperative `CpuRenderCancellationToken` / `CpuRenderCancelledException` abort support in `CpuFractalRenderer`, plus `renderProgress`, `exportProgress`, `activeProgress`, and `hasActiveProgress` state in `FractalEngine`.
- **Instant Touch-to-Abort (`FractalCanvas`)**: Touching, panning, or zooming on `FractalCanvas` during a multi-second `CPU f64` render immediately cancels the background pass and drops back to smooth interactive preview.
- **Viewport & Export Progress UI (`lib/main.dart`, `lib/widgets/inspector_panel.dart`)**: Added a thin top-edge Material 3 `LinearProgressIndicator` on the fractal viewport and determinate percentage progress in the PNG Export card.

## Update 0.3.4 ([0.3.4] - 2026-11-23)
#### Fixes
- **Rapid-Zoom & Re-Grip `GPU df64` Downscale (`FractalCanvas`, `shaders/fractal.frag`)**: Removed `maxIterations` from `_GpuBakeKey.matchesAppearance` so logarithmic iteration-count growth during zoom no longer invalidates the baked preview, kept the affine-reprojected baked preview active during `GPU df64` transitions and finger lifts, and disabled `df64` and SSAA on live fallback shader frames while interacting.

## Update 0.3.3 ([0.3.3] - 2026-11-23)
#### Changes
- **Predictive Cost-Model LOD Solver (`FractalEngine`)**: Added per-mode cost-per-pixel-iteration calibration (`_costPerPixelIter`), `updateViewportPixelArea`, `predictOptimalScale` ($s^*$) with 10% safety headroom, and asymmetric EMA `recordRenderCostSample` calibration.
- **Instant Pre-Potato & Monotonic-Down Gesture Lock (`FractalEngine`)**: Added `_gestureLockedDragScale` initialized via `predictOptimalScale()` on touch (`setInteracting(true)`) and locked monotonically downward during active gestures (`recordRenderCostSample` and `recordBakeDurationForLod`), committing back to `_adaptiveDragScale` on release.

## Update 0.3.2 ([0.3.2] - 2026-11-23)
#### Changes
- **Ultra-Potato `0.02x` LOD & 5-Stage Idle Sharpening (`FractalEngine`, `FractalCanvas`)**: Lowered the adaptive and manual `dragPreviewScale` floor to `0.02x` (`2%`), changed default/reset `_adaptiveDragScale` to `0.10`, and added a 5-stage idle sharpening ladder (`[0.04, 0.10, 0.25, 0.50, full]`).
#### Fixes
- **Adaptive LOD Feedback Loop (`FractalEngine`, `FractalCanvas`)**: Added `recordBakeDurationForLod(double ms)` driven by actual `bakeMs` (`> 16.0 ms` tightens by `0.55×`, `< 8.0 ms` relaxes by `+0.02`) and added `updateLod = true` to `recordFrameDurationMs` so fast `2 ms` reprojected UI frames no longer inflate `_adaptiveDragScale`.

## Update 0.3.1 ([0.3.1] - 2026-11-23)
#### Changes
- **120 FPS Reprojected `GPU df64` Potato-LOD Drag (`FractalEngine`)**: Tuned `Auto-Adaptive Progressive LOD` (`_adaptiveDragScale` default/reset `0.14`, clamped `0.05x–0.35x`, tightening by `0.62×` above `18.0 ms` and relaxing `+0.03` below `10.0 ms`), and lowered the manual `dragPreviewScale` floor to `0.05x` (`5%`).
- **Roadmap (`ROADMAP.md`)**: Updated Phase 2 (`10/10`) with `0.2.0–0.3.1` milestones and added Phase 3 backlog items for Deep-Link & QR Code Bookmark Sharing, Live Render & Export Progress Indicator, and Inline Quick-Parameter Scrubber.
#### Fixes
- **Inverted Twist-Rotation**: Fixed inverted two-finger twist-rotation direction during canvas gestures.

## Update 0.3.0 ([0.3.0] - 2026-11-23)
#### Changes
- **Canvas Rotation (`FractalEngine`, `fractal.frag`, `CpuFractalRenderer`)**: Added full 2D viewport rotation (`uRot` uniform in `shaders/fractal.frag`, `rotCos`/`rotSin` in `CpuRenderRequest`, `rotation` / `rotationDegrees` / `enableGestureRotation` / `setRotation` / `resetRotation` in `FractalEngine`, per-fractal camera memory, and `rotateLeft`/`rotateRight` keybinds `Q`/`E`).
- **Auto-Adaptive Progressive LOD (`FractalEngine`)**: Added `autoAdaptiveLod` (`fv_auto_adaptive_lod`, default `true`) and `effectiveDragScale` that dynamically scales drag preview resolution between `0.06` and `0.50` based on recent frame times.
- **Localization (`en.json`, `uk.json`)**: Added English and Ukrainian strings for rotation controls, auto-adaptive LOD, and rotation keybinds.

## Update 0.2.3 ([0.2.3] - 2026-11-23)
#### Changes
- **M3x UI `^0.1.4` Upgrade**: Upgraded `m3x_ui` to `^0.1.4` (`M3x Ecosystem (pub.dev)` dependency labels and `SettingsBentoHeader.onHeaderTap` wired to `https://puzzak.page`).
- **Draggable Mobile Explorer Controls**: Added a Material 3 drag handle on compact mobile Explorer Controls to expand smoothly to 100% fullscreen, snap to 65% split, or drag down to dismiss.
- **Responsive Fractal Selector**: Replaced the cramped 4-way `SegmentedButton` in *Fractal & Parameters* with `CardContents.tapIcon` rows so *Burning Ship* and *Tricorn* never clip on phones.
#### Fixes
- **Nested Navigator Predictive-Back Bleed-Through**: Fixed transparent route bleed-through during nested `Navigator` predictive-back gestures by wrapping every inspector route in an opaque `Material(color: scheme.surface)`.

## Update 0.2.2 ([0.2.2] - 2026-11-23)
#### Changes
- **M3x Bento Integration (`FractalEngine`, `pubspec.yaml`)**: Initialized `M3x.init(enableMesh: false)` and bundled `pubspec.yaml` as a Flutter asset so `SettingsBentoHeader` auto-populates with the real native app icon, live package metadata, dependencies, and `CHANGELOG.md`.
- **PAIOS-Style Settings Layout**: Added `tapIcon` actions on settings category buttons, dedicated `Category.settings` headers for every card group, and localized section headers (`section_color_options`, `section_camera`, `section_precision`, `section_ecosystem`, `section_julia`).
- **Julia Parameter Reset (`FractalEngine`)**: Added `resetJuliaC()` to restore the default `c = -0.7269 + 0.1889i` seed with persistence.
- **Softer Render Speed Sparkline**: Smoothed the telemetry Render Speed sparkline visualization.
#### Fixes
- **Fractal Selector Sheet Title**: Fixed the `"Select Fractal"` bottom sheet title.

## Update 0.2.1 ([0.2.1] - 2026-11-23)
#### Changes
- **Settings Hub Header & Ecosystem Links**: Added inline `SettingsBentoHeader` (with bundled `CHANGELOG.md` dialog and package dependency inspector) and `puzzak.page` link directly on the main Settings Hub, dropping the legacy `authors.json` socials list.
- **Settings Navigation Refinement**: Renamed the `Rendering, Precision & Performance` sub-page while keeping Live Telemetry and About directly on the main Settings Hub.

## Update 0.2.0 ([0.2.0] - 2026-11-23)
#### Changes
- **Per-Fractal Camera Memory (`FractalEngine`)**: Remember and restore each fractal's last `(centerX, centerY, zoom)` position across fractal switches (persisted via `fv_fractal_cameras`), with `setFractalType(..., resetCamera: false)` by default and clean reset in `resetView()` / `resetAllSettings()`.
- **Configurable Overscan Cushion (`FractalEngine`)**: Added an `overscanMultiplier` (`0.0`–`5.0`, default `2.0`, persisted via `fv_overscan_multiplier`) so users can balance zero-overscan speed against edge-free panning.
- **Customizable Keyboard Shortcuts (`FractalKeyAction`, `FractalEngine`)**: Added `FractalKeyAction` (`panUp`, `panDown`, `panLeft`, `panRight`, `zoomIn`, `zoomOut`, `resetView`, `toggleHud`, `toggleInspector`) with `fv_keybinds` JSON persistence and `formatKeyLabel` formatting.
- **CPU Isolate Core Reservation (`CpuFractalRenderer`)**: Reserved 1 CPU core (`max(1, min(Platform.numberOfProcessors - 1, 7))`) so Flutter UI and raster threads stay responsive during `CPU f64` rendering on 4-thread devices.
- **Localization (`en.json`, `uk.json`)**: Added English and Ukrainian strings for overscan controls, keybind actions, and fractal/palette selectors.

## Update 0.1.3 ([0.1.3] - 2026-11-23)
#### Changes
- **2× Low-Res Background Overscan Cushion (`CPU f64`)**: Added a 2× low-resolution background overscan cushion in `CPU f64` mode, eliminating black margins during panning and zooming out.
- **Configurable Drag Preview Resolution (`FractalEngine`, Settings)**: Added a Drag Preview Resolution slider (`10%–100%`, persisted via `fv_drag_preview_scale`, default `20%`) for `CPU f64` and `GPU df64` modes.
- **Viewport Tap & Long-Press Navigation**: Single-tapping the cropped fractal now returns 1 step to the Card HUD, while long-pressing jumps directly to Fullscreen.
#### Fixes
- **UI vs. Fractal Render Telemetry Separation (`FractalEngine`)**: Separated UI frame timing from fractal render FPS/ms telemetry, added `resetFrameTimingWindow()` across GPU/CPU mode switches, clamped `currentFps` to `0.1–120.0`, and added `formatFrameTime` / `formatFps` formatters.

## Update 0.1.2 ([0.1.2] - 2026-11-23)
#### Changes
- **Brent's Periodicity Bailout (`shaders/fractal.frag`, `lib/engine/cpu_renderer.dart`)**: Added power-of-2 Brent periodicity checking for Mandelbrot across `GPU f32`, `GPU df64`, and `CPU f64` renderers so trapped interior mini-brot pixels bail out early instead of grinding `maxIter`.
- **Persistent Interleaved CPU Isolate Pool (`lib/engine/cpu_renderer.dart`)**: Replaced per-frame `Isolate.run` spawning with a lazy persistent worker pool (`_WorkerPool` with `TransferableTypedData`, 10s idle auto-shutdown, and `disposePool()`), plus interleaved scanline distribution (`y = workerId; y < h; y += workerCount`) for even multi-core load balancing.
- **Structured `[FV_PERF]` Console Telemetry (`lib/engine/fractal_engine.dart`)**: Added `logPerf` emitting `[FV_PERF]` events on interaction, fractal type, quality, and backend mode transitions in non-release builds.
#### Fixes
- **FPS Rolling Window & Cap (`lib/engine/fractal_engine.dart`)**: Switched `recordFrameDurationMs` to a 4-sample rolling window and capped `_currentFps` at `120.0` (accepting optional `buildMs` and `rasterMs`), fixing frame-time/FPS desyncs and impossible >120 FPS readings.
- **UI & Transition Polish**: Addressed video-reported UI and mode transition issues.

## Update 0.1.1 ([0.1.1] - 2026-11-22)
#### Changes
- **3-State Framed Card Layout & Adaptive Split Settings**: Added a 3-state viewport layout: `Fullscreen` (toggled via long-press anywhere with no corner button), `Framed Card HUD` with a non-clipping bottom bar, and `Adaptive Squash/Split Settings` (`35%/65%` top/bottom on phones, `50%/50%` on foldables, `67%/33%` on tablets/desktops).
- **`df64` GLSL Shader Optimization (`shaders/fractal.frag`)**: Added `dfTwoProdSplit`, `dfSqrSplit`, and `dfAddFast` helpers so `zx` and `zy` are `dfSplit` only once per loop iteration instead of twice, eliminating redundant splits across `zx*zx`, `zy*zy`, and `zx*zy` and streamlining the `z + c` step.
#### Fixes
- **Deep-Zoom 120 FPS UI Fix**: Skipped running the hidden `df64` GPU shader under cached `CPU f64` frames, added async offscreen GPU frame baking when idle, enabled true `0.5x`/`0.75x` GPU resolution scaling plus dynamic `0.5x` downscaling during `df64` drag, and deduplicated `dfSplit` calls in `df64` GLSL arithmetic.

## Update 0.1.0 ([0.1.0] - 2026-11-22)
#### Changes
- **Real-Time GLSL GPU Shader & Dekker-Knuth `df64` Deep Zoom (`shaders/fractal.frag`, `lib/engine/fractal_models.dart`)**: Replaced the legacy single-threaded CPU BMP stream (`lib/generator.dart`) with a hardware-accelerated `#version 460 core` GLSL fragment shader supporting `float32` (`GPU f32`) and automatic Dekker-Knuth double-float (`GPU df64` via `splitDoubleToDf64`, `dfQuickTwoSum`, `dfTwoSum`, `dfSplit`, `dfTwoProd`) above `zoom >= 5e4` up to ~`10^12×` (`2e12` scale), complete with Mandelbrot cardioid & period-2 bulb early bailout and optional `2x2` rotated-grid SSAA.
- **Multi-Isolate CPU `float64` Ultra-Deep-Zoom & Export Engine (`lib/engine/cpu_renderer.dart`)**: Added parallel worker-isolate `float64` rendering (`CpuFractalRenderer`, partitioning up to 8 horizontal strips via `Isolate.run`) with 1:1 formula/palette parity for seamless ultra-deep zoom (`zoom >= 2e12` up to `10^15×` / `maxZoom = 1e15`), explicit `Auto` / `GPU Shader` / `CPU Float64` backend selection, and off-screen PNG encoding.
- **Expanded Fractal Suite (`FractalType`)**: Added **Julia** (with interactive `Re(c)` and `Im(c)` parameters), **Burning Ship**, and **Tricorn** alongside **Mandelbrot**, replacing the unfinished experimental Sierpinski stub.
- **7 Smooth Continuous Color Palettes (`FractalPalette`)**: Added cyclic 4-stop smoothstep and cosine color palettes (**System Dynamic** Material You, **Inferno**, **Viridis**, **Ocean**, **Neon**, **Monochrome**, and **Twilight**), continuous normalized escape-time smoothing (`Smooth Coloring` toggle), and a `Color Phase Shift` slider.
- **Adaptive `m3x` Material 3 Expressive UI & Localization (`m3x_ui`, `m3x_core`, `m3x_dict`, `m3x_gh`)**: Replaced the legacy modal `MaterialApp`-per-sheet UI with an adaptive `m3x_ui` layout (phone bottom-sheet inspector and tablet/foldable/desktop docked side panel), `AnalyticsService` diagnostics, bundled **English (`en`)** and **Ukrainian (`uk`)** localization (`m3x_dict`), and an in-app GitHub Repository Explorer (`m3x_gh`).
- **Curated Landmarks, Bookmarks, HD/2K/4K PNG Export & Desktop Controls (`lib/engine/fractal_engine.dart`)**: Added 9 curated mathematical landmarks (`builtInBookmarks`), persistent custom bookmarks and full camera/settings persistence (`SharedPreferences`), Screen (HD) / 2K (`2560px`) / 4K (`3840px`) PNG rendering and system sharing (`path_provider` + `share_plus`), and desktop keyboard/mouse shortcuts (`+`/`-`, Arrows/WASD, `R` reset, `H` toggle HUD, `I` toggle inspector, scroll-wheel focal zoom).
- **CI/CD, Release Tooling & Store Metadata (`.github/workflows/ci.yml`, `build_releases.ps1`, `docs/PLAY_STORE_LISTING.md`)**: Added GitHub Actions `flutter analyze` & `flutter test` workflow, parameterized `build_releases.ps1` (`-ApkOnly`, `-AabOnly`, `-OutputDir`) producing `Fractals_v0.1.0_GitHub.apk` / `Fractals_v0.1.0_PlayStore.aab`, and updated Play Store listing copy.
#### Fixes
- **Play Store Lag, Thermal Throttling & Missing Quality Controls**: Eliminated the continuous `Future.delayed(1ms)` main-thread CPU rendering loop, BMP re-encoding overhead, and excessive heat/battery drain by moving live rendering to vsync-paced GPU shaders and adding `RenderQuality` presets (`Performance 0.5x`, `Balanced 0.75x`, `Native 1x`, `Ultra SSAA`) plus logarithmic `Auto Iterations` (`80..2000`, manual `50..2000`).
- **Legacy Pan/Pinch Drift & Broken Focal Zoom (`FractalEngine.transformAtFocalPoint`)**: Replaced the unanchored legacy gesture math (`delta / zoom * 3.5` drift and broken `scale` step increments) with exact 1:1 pointer panning and focal-point anchoring so coordinates under the pointer or fingers stay pinned while zooming.
- **Telemetry FPS & Formatting Bugs (`FractalEngine.recordFrameDurationMs`)**: Fixed the legacy `100 / lastTime` FPS calculation bug (which under-reported FPS by 10×) with a rolling 10-frame millisecond average (`1000.0 / avgMs`), 30-sample sparkline history, zoom-adaptive coordinate precision (`4..16` decimal digits), and one-tap coordinate copying.
- **Repository Links & Release Signing (`README.md`, `android/app/build.gradle`)**: Updated legacy `Puzzaks/Fractal-Viewer` references to `Puzzaks/fractals` and guarded `signingConfigs.release` on `key.properties` presence so contributor/CI builds fall back cleanly to debug signing.

## Update 0.0.3 ([0.0.3] - 2026-11-01)
#### Changes
- Modernized Android Gradle configuration (`android/app/build.gradle`, `android/settings.gradle`, Gradle wrapper, `minSdk 24`, `targetSdk 36`) and enabled `analysis_options.yaml` (`flutter_lints`).

## Update 0.0.2 ([0.0.2] - 2024-08-16)
#### Changes
- Added Windows, macOS, and Linux Flutter desktop target scaffolding.
- Added `assets/data/authors.json` developer ecosystem links chip bar inside Settings.
- Added Android showcase banner and screenshot assets to `README.md`.

## Update 0.0.1 ([0.0.1] - 2024-01-19)
#### Changes
- Initial Google Play Store release (`page.puzzak.fractals`): CPU-rendered `image` BMP Mandelbrot stream with `0.075` drag preview scale, `1.0` idle full-res frame, Material You dynamic color tinting, basic telemetry card, and experimental Sierpinski prototype.

---
> Template for later updates
```Markdown
## Update 0.1.0 ([0.1.0] - YYYY-MM-DD)
#### Changes
#### Fixes
#### Known Issues
#### Miscellaneous
```
