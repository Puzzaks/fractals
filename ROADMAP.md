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

## Phase 3 `Arbitrary Precision, Formulas & Showcase` 8/10
 - [x] **Perturbation Theory & Series Approximation (`10^100+` Zoom)** `0.5.0`
    - Compute high-precision arbitrary-precision reference orbits on background isolates and evaluate per-pixel deltas with perturbation theory + glitch detection to break past the `10^15×` IEEE-754 `double` precision ceiling.
 - [ ] **Custom Formula & Parameter Editor**
    - Interactive complex expression builder (custom exponents $z^p + c$, Phoenix, Newton basins, custom bailout thresholds) with real-time parameter sliders.
 - [ ] **Orbit Traps, Distance Estimation & Procedural Shading**
    - Geometric orbit traps, analytical interior/exterior distance estimation, and specular normal-map surface lighting.
 - [x] **Video / Zoom Animation Export** `1.0.0`
    - Automated MP4 zoom animation export (`Mp4VideoEncoder` via Android `MediaCodec` + `MediaMuxer`) for deep-zoom dives with configurable duration, resolution, and frame rate.
 - [x] **Deep-Link & QR Code Bookmark Sharing** `0.7.0`
    - Encode fractal type, center coordinates, zoom, rotation, Julia `c`, and palette into shareable URLs & scannable QR codes so users can share discoveries directly.
 - [x] **Live Render & Export Progress Indicator** `0.4.0`
    - Thin top-edge Material 3 progress bar during multi-second deep-zoom passes and 2K/4K PNG exports, with instant touch-to-abort back to smooth potato LOD.
 - [x] **Built-in Hardware Benchmark ("Potatoemeter" & Potato Rating)** `0.6.0`
    - Deterministic 2–3 second GPU `f32`, GPU `df64`, and multi-core CPU `f64` benchmark measuring real Mega-Iterations/sec (`MIter/s`), awarding a shareable Potato Rating, and persisting per-device $k_{\text{mode}}$ calibration for instant frame-1 LOD accuracy.
 - [x] **Google Play Games Services (Potatoemeter & Exploration Leaderboards + Achievements)** `0.8.0`
    - Submit verified Potatoemeter hardware scores and deep-zoom exploration milestones to Google Play Games Services leaderboards and achievements.
 - [x] **Background Foreground-Service Export & Notification Progress** `1.0.0`
    - Off-screen PNG and MP4 exports continue reliably in the background via `ExportForegroundService` with live Android notification progress updates.
 - [x] **Additional Fractal Types (Multibrot-3 & Celtic)** `1.0.0`
    - Added **Multibrot-3** (`z³ + c`) and **Celtic** fractals across GPU shaders, perturbation solver, and CPU renderer.

## Phase 4 `v1.1.0 — Exploration & Navigation QoL` 0/14
 - [ ] **CPU Perturbation Deep-Zoom (`10³⁰⁰+×` Multi-Isolate Renderer)**
    - Upgrade `CpuFractalRenderer` to consume `PerturbationSolver` reference orbits directly in native Dart `float64` across all CPU cores (no `float32` exponent limits), bringing CPU rendering to full `10³⁰⁰+×` parity for Windows/Linux desktops and fallback devices, and re-expose the backend toggle in release builds.
 - [ ] **Video Export ETA (Weighted Remaining Time)**
    - Show an approximate time-to-completion estimate during MP4 zoom exports, weighted by iteration/zoom depth since deeper frames take progressively longer to render.
 - [ ] **Bookmark "Inherit / Keep Current Palette"**
    - Make `FractalBookmark.palette` optional/nullable (supporting `"inherit"` / omitted in `bookmarks.json` and a "Keep current palette" toggle when saving custom bookmarks) so bookmarks only override the active palette when intended.
 - [ ] **Color Cycling / Live Palette Animation**
    - Optional gentle live palette phase-shift animation on the canvas and an optional color-cycle toggle during MP4 video export.
 - [ ] **Bookmark Landmark Overlay**
    - On-canvas landmark pins with zoom-range visibility, auto-hidden in fullscreen and during exports, and filtered to the active fractal; quick toggle in the HUD Bookmarks popup plus a dedicated Settings tile (with inline master toggle) leading to a sub-page for edge-sticking radius, pin styling, and visibility rules.
 - [ ] **Smooth Fly-To Camera Animation**
    - Optional (toggleable in Settings) fast-start ease-in / smooth-landing camera transition when jumping to bookmarks or resetting view, skipping heavy deep-zoom frames early.
 - [ ] **One-Finger Tap-and-Slide Zoom**
    - Google Maps-style double-tap-and-drag zoom with a configurable reversed-direction toggle.
 - [ ] **Split / Ghost Julia Preview (PiP)**
    - Hold-and-drag crosshair on Mandelbrot to preview the corresponding Julia set live in a corner PiP, with one-tap jump-in.
 - [ ] **Camera History Stack (Undo / Redo)**
    - Back/forward navigation stack for camera jumps, bookmarks, and resets so accidental taps never lose a deep-zoom spot.
 - [ ] **Settings Top-Preview Polish (Julia Full-View Live Preview)**
    - When adjusting Julia `c` parameters in settings while deeply zoomed in, temporarily show the full Julia overview in the top preview so changes are immediately visible, then return to the user's deep-zoom position when finished.
 - [ ] **Smooth Progressive LOD Crossfade Polish** *(evaluate)*
    - Audit and tune the existing `_fadeController` crossfade between lower-LOD and higher-LOD frames in `fractal_canvas.dart` (with a toggle for users who prefer crisp instant swaps).
 - [ ] **Megapixel (MP) Export Presets & Chunked Ultra-Res Encoding**
    - Add photography-style MP presets (`12 MP`, `24 MP`, `33 MP`, `50 MP+`) with streaming/chunked encoding so ultra-high-res exports never OOM.
 - [ ] **EXIF / PNG Metadata Injection**
    - Embed app version, signed-in Google Play Games author, timestamp, fractal parameters, and `?d=` share link into exported images.
 - [ ] **Optional 2×2 SSAA Supersampled Export**
    - Toggleable anti-aliased export mode for silky-smooth 1px filaments.

## Phase 5 `Further Plans — Unified Web App (fractals.puzzak.page)` 0/4
 - [ ] **Unified Flutter Web GPU Target**
    - Ship the same Flutter codebase to Web (`fractals.puzzak.page`) with GPU shader & precision tweaks so it runs smoothly across desktop and mobile browsers.
 - [ ] **In-Browser Deep-Link `?d=` Decoding**
    - Parse `?d=` share payloads directly in the browser to restore exact fractal type, coordinates, zoom, rotation, Julia `c`, and palette.
 - [ ] **Interactive Pan, Zoom & Touch Controls**
    - Smooth mouse-wheel, drag, pinch-to-zoom, and rotation navigation matching the mobile/desktop app experience.
 - [ ] **Static Fallback Preview & Share Cards**
    - Lightweight Open Graph / fallback canvas preview for instant link unfurling and unsupported browsers, with direct "Open in App" handoff.

## Phase 6 `Deep Deep Zoom (No ETA / Blue-Sky Ideas)` 0/1
 - [ ] **3D Fractals & Dimensional Projections**
    - Explore 3D fractal rendering (Mandelbulb, Quaternion Julia sets, raymarching, and 2D-slice-to-3D projection experiments).
