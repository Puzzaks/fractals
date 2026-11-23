# Project Roadmap
  - [ ] Planned/ indev change
  - [x] Implemented change
  - `~version` Upstream version of this change
  - `version` Downstream version of this change

---
## Phase 1 `Legacy CPU Prototype (0.0.1–0.0.4)` 4/4
 - [x] **Initial Play Store Release** `0.0.1`
    - Pure-Dart CPU Mandelbrot generator streaming BMP frames via `image`, `0.075x` drag preview with `1.0x` idle refinement, Material You dynamic color tinting, and initial Google Play launch (`page.puzzak.fractals`).
 - [x] **Author Metadata & Desktop Target Scaffolding** `0.0.2`
    - Multi-platform Windows/macOS/Linux runner setup, developer link chips (`assets/data/authors.json`), and README showcase imagery.
 - [x] **Android Build Modernization & Static Linting** `0.0.3`
    - Upgraded Gradle/AGP tooling, `minSdk 24` / `targetSdk 36` targeting, and `analysis_options.yaml` lint integration.
 - [x] **Pre-Rewrite Stabilization & Feedback Triage** `~0.0.4`
    - Triaged Play Store reviews regarding CPU frame lag, thermal throttling, broken pinch/pan controls, and missing resolution presets to architect the v0.1.0 GPU rewrite.

## Phase 2 `GPU Rewrite, m3x UI & Deep Zoom` 10/10
 - [x] **Real-Time GLSL Fragment Shader & `df64` Emulation** `0.1.0`
    - `#version 460 core` GPU shader (`shaders/fractal.frag`) with `float32` fast path, automatic Dekker-Knuth `df64` emulation (`zoom >= 5e4` up to ~`10^12×`), cardioid/period-2 bulb early bailout, and `2x2` rotated-grid SSAA (`Ultra`).
 - [x] **Multi-Isolate CPU `float64` Ultra-Deep-Zoom Fallback** `0.1.0`
    - Parallel worker-isolate `CpuFractalRenderer` (`Isolate.run`, up to 8 strip workers) extending precision smoothly up to `10^15×` (`maxZoom = 1e15`) with manual `Auto` / `GPU Shader` / `CPU Float64` backend selection.
 - [x] **Expanded Fractal & Smooth Palette Catalog** `0.1.0`
    - Added **Julia** (interactive `c` sliders), **Burning Ship**, and **Tricorn** alongside **Mandelbrot**, plus 7 continuous cyclic palettes (**System Dynamic**, **Inferno**, **Viridis**, **Ocean**, **Neon**, **Monochrome**, **Twilight**), smooth coloring toggle, and color phase shift.
 - [x] **Focal-Point Camera Math & Telemetry Fixes** `0.1.0`
    - Exact pointer-anchored zoom & 1:1 pan (`transformAtFocalPoint`), corrected rolling 10-frame FPS telemetry, zoom-matched coordinate precision (`4..16` digits), and desktop keyboard/mouse shortcuts (`+`/`-`, Arrows/WASD, `R`, `H`, `I`, scroll-wheel zoom).
 - [x] **Adaptive `m3x` Material 3 Expressive UI & Localization** `0.1.0`
    - Integrated `m3x_ui`, `m3x_core`, `m3x_dict`, and `m3x_gh` with an adaptive phone bottom-sheet vs. tablet/foldable/desktop docked inspector, bundled English & Ukrainian (`en` / `uk`) localization, and in-app GitHub Repository Explorer.
 - [x] **Curated Landmarks, Bookmarks & HD/2K/4K PNG Export** `0.1.0`
    - Added 9 built-in mathematical landmarks, persistent user bookmarks & settings (`SharedPreferences`), and off-screen Screen / 2K (`2560px`) / 4K (`3840px`) PNG rendering and sharing.
 - [x] **CI Workflow & Automated Release Packaging** `0.1.0`
    - GitHub Actions CI (`ci.yml`) for `flutter analyze` & `flutter test`, plus `build_releases.ps1` (`-ApkOnly`, `-AabOnly`) for reproducible GitHub APK and Play Store AAB artifacts.
 - [x] **Nested Split Settings, Keybinds & `m3x_ui 0.1.5` Bento** `0.2.0–0.2.3`
    - Nested split-navigation settings hub, customizable keyboard shortcuts (`WASD`/Arrows, `+`/`-`, `Q`/`E`, `R`, `H`, `I`), draggable mobile explorer sheet, and `m3x_ui ^0.1.5` Bento header with live package and changelog inspection.
 - [x] **Canvas Rotation & 2×–5× Overscan Cushion** `0.3.0`
    - Full 2D viewport rotation (`uRot` in GLSL & CPU renderer, two-finger twist gesture, `Q`/`E` keybinds, per-fractal camera memory) and configurable `0×–5×` off-screen overscan cushion for instant drag coverage.
 - [x] **Auto-Adaptive Progressive LOD & Reprojected Drag** `0.3.0–0.3.1`
    - Frame-time-driven `Auto-Adaptive Progressive LOD` (`0.05×–0.35×` potato-LOD drag scaling) paired with 120 FPS affine reprojection during pan/pinch/rotate gestures.

## Phase 3 `Arbitrary Precision, Formulas & Showcase` 1/9
 - [ ] **Perturbation Theory & Series Approximation (`10^100+` Zoom)**
    - Compute high-precision arbitrary-precision reference orbits on background isolates and evaluate per-pixel deltas with perturbation theory + glitch detection to break past the `10^15×` IEEE-754 `double` precision ceiling.
 - [ ] **Custom Formula & Parameter Editor**
    - Interactive complex expression builder (custom exponents $z^p + c$, Phoenix, Newton basins, custom bailout thresholds) with real-time parameter sliders.
 - [ ] **Orbit Traps, Distance Estimation & Procedural Shading**
    - Geometric orbit traps, analytical interior/exterior distance estimation, and specular normal-map surface lighting.
 - [ ] **Keyframed Zoom Animations & Video Export**
    - Camera spline timeline for automated deep-zoom dives and Julia `c`-parameter morph loops with offline frame/video export.
 - [ ] **WebGL / WASM Interactive Web Showcase**
    - Web deployment hosted via `puzzak.page` / GitHub Pages with shareable deep-link URLs encoding fractal type, coordinates, zoom, Julia seed, and palette.
 - [ ] **Deep-Link & QR Code Bookmark Sharing**
    - Encode fractal type, center coordinates, zoom, rotation, Julia `c`, and palette into shareable URLs & scannable QR codes so users can share discoveries directly.
 - [x] **Live Render & Export Progress Indicator** `0.4.0`
    - Thin top-edge Material 3 progress bar during multi-second deep-zoom passes and 2K/4K PNG exports, with instant touch-to-abort back to smooth potato LOD.
 - [ ] **Inline Quick-Parameter Scrubber**
    - Optional compact on-canvas scrubber bar for live tweaking of color phase, iterations, rotation, or Julia `c` without opening settings.
 - [ ] **Built-in Hardware Benchmark ("Potatoemeter" & Potato Rating)**
    - Deterministic 2–3 second GPU `f32`, GPU `df64`, and multi-core CPU `f64` benchmark measuring real Mega-Iterations/sec (`MIter/s`), awarding a shareable Potato Rating, and persisting per-device $k_{\text{mode}}$ calibration for instant frame-1 LOD accuracy.
