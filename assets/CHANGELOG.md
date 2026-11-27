## [1.0.9] - 2026-11-25
#### Changes & Fixes
- **Stale-Orbit Potato Jump Fix**: Held GPU Perturbation re-bakes while a new reference orbit is in flight (`_isPtOrbitStaleFor`) so the canvas smoothly reprojects the last valid frame until the fresh orbit lands.
- **4K/8K Export Sharpness & `Pictures/Fractals` Save**: Computed image export iterations from `effectiveZoom` (with `>= 1.0×` quality multiplier) for sharper high-res boundaries, bumped GPU Perturbation live preview to `720px`, and added Android `saveImageToGallery` (`MediaStore` / `Pictures/Fractals`) matching `Movies/Fractals` for videos.

## [1.0.8] - 2026-11-25
#### Changes & Fixes
- **Deep-Zoom GPU Perturbation Image Export**: Upgraded image export (`exportFractalImage`) at `zoom >= 2e12` to render seamlessly in `1024×1024` GPU Perturbation tiles up to 8K (`7680×4320`) with live downscaled overlay previews, avoiding GPU timeouts and precision loss.
- **Infinite Perturbation Orbit Loop Fix**: Tracked the requested viewport center (`_ptOrbitQueryCenterXBig/YBig`) separately from the winning `5×5` probe's reference center so off-center probes no longer re-trigger `_startPtOrbit` on every frame.
- **Android Release Permissions, Notification Icon & FGS Safety**: Added `INTERNET` and legacy `WRITE_EXTERNAL_STORAGE (maxSdkVersion=28)` to `AndroidManifest.xml`, added a monochrome `ic_stat_fractals` notification vector icon, guarded `ExportForegroundService` against Android 12+ `ForegroundServiceDidNotStartInTimeException` and Android 15 `onTimeout`, and hardened `Mp4VideoEncoder` against native resource leaks and 0-byte EOS outputs.
- **Translations & Release Docs**: Added all 11 missing keys to `en.json` and `uk.json`, localized remaining hardcoded UI strings, gated `"Saved to Movies/Fractals"` toast on successful URI return, and updated `README.md` + `docs/PLAY_STORE_LISTING.md` for `1.0.x`.

## [1.0.7] - 2026-11-25
#### Changes & Fixes
- **48-Bit Orbit Texture & Perturbation Glitch Fixes**: Upgraded the GPU perturbation reference orbit texture from 24-bit (`256×128`) to 48-bit `hi + lo` (`256×256`), added `5×5` grid neighbor probing in `PerturbationSolver`, allowed reference orbits to refresh during continuous pan/zoom gestures, widened `scaleC` / `shouldRebase` exponent bounds, and improved Celtic `aRe` precision—eliminating Burning Ship circular glitch blobs and mid-zoom Celtic stippling.
- **Deeper Auto-Iterations for Spirals**: Steeper `effectiveMaxIterations` scaling (`120 + 115*log10(z) + 2.5*log10(z)^2`) so tight Multibrot-3 and Mandelbrot spirals resolve cleanly instead of clipping to black.

## [1.0.6] - 2026-11-25
#### Changes & Fixes
- **Video & Image Export Locks, Persistence & Polish**: Locked fractal/palette/bookmark/reset controls and `/export` back navigation during active renders, swapped the HUD reset button for a long-press **Stop Rendering** button while exporting, separated image vs. video `ExportKind` progress states, persisted all export settings across app launches, allowed video zoom-outs down to `minZoom`, clipped the filmstrip range selector highlight strictly inside rounded corners, and fixed scrub preview position drift via `setZoomOnly` + `df64` precision retention.
- **Fullscreen Toggle & Magnetic Snap**: Restored progressive potato-LOD re-bakes and stretched `gpuFloat32` baking during fullscreen transitions to eliminate animation stutter; added gentle haptic magnetic snapping at `0°`/`90°`/`180°`/`270°` rotation and `x = 0`/`y = 0` axes.
- **Rotation in HUD, Bookmarks & Share Sheet**: Added rotation persistence in `FractalBookmark`, `?d=` bookmark links, HUD status/telemetry readouts, and Share sheet metadata.
- **Deep-Zoom Perturbation & Achievement Fixes**: Expanded neighbor probing in `PerturbationSolver` to run whenever `best.len < maxIter`, fixed 24-bit orbit texture zero-bias (`16777214.0`), capped Mandelbrot SA at `1e30` to prevent `float32` uniform underflow, guarded Celtic `s = -127` renormalization, switched deep-zoom HUD/copied coordinates to `BigFixed`, and aligned `Planck Scale Tourist` (`10³⁵×`) and `Googol Explorer` (`10¹⁰⁰×`) thresholds with `formatZoom`.

## [1.0.5] - 2026-11-24
#### Changes & Fixes
- **Filmstrip Trimmer Polish & Zoom Speed Card**: Replaced separate handle `GestureDetector`s in `_ZoomRangeFilmstripTrimmer` with a unified hit-testing `GestureDetector` for reliable right-handle grabbing, added 120 FPS local drag state with `100ms`-throttled live canvas preview (`engine.setInteracting`), eliminated rounded-corner border bleed (`ClipRRect(14)`), and moved the per-frame zoom speed indicator to a dedicated status card below Zoom Range.

## [1.0.4] - 2026-11-24
#### Changes & Fixes
- **Filmstrip Zoom Range Trimmer**: Added a Google Photos-style Material 3 `_ZoomRangeFilmstripTrimmer` to the Zoom Video export panel with 8 asynchronous fractal thumbnails (CPU + GPU Perturbation), draggable start/end handles and range window, live canvas preview scrubbing, and per-frame zoom speed indicator (`Smooth` / `Fast (strobe risk)`).

## [1.0.3] - 2026-11-24
#### Changes & Fixes
- **Fullscreen Toggle Sharpness**: Fixed fullscreen toggle flashing low-resolution potato frames by debouncing viewport-only resize re-bakes and baking directly at full resolution.
- **Celtic Deep-Zoom Pan Fix**: Fixed Celtic (`fType == 5`) deep-zoom perturbation pan teleporting.

## [1.0.2] - 2026-11-24
#### Changes & Fixes
- **Speed-Gated Scroll Motion Blur**: Added a `450.0 px/s` velocity deadzone so slow and normal scrolling stays 100% sharp, with proportional blur scaling above the threshold up to `2.6` sigma.
- **Fullscreen Progress Pill Safe Inset**: Added bottom safe-area padding (`MediaQuery.paddingOf(context).bottom + 18.0`) to the fullscreen rendering/benchmark progress pill so it sits cleanly above the Android gesture navigation bar.
- **Community Bookmarks Docs**: Added a **Community Bookmarks** section to `README.md` detailing Pull Request submissions to `assets/bookmarks.json` (`"author"`) and automatic GitHub OTA bookmark syncing in release builds.

## [1.0.1] - 2026-11-24
#### Changes & Fixes
- **Deep-Zoom Perturbation Video Export**: Upgraded Zoom Video export to render deep-zoom frames via GPU Perturbation (`10³⁰⁰×` sharp) instead of `float64` CPU fallback, added `3–30s` Duration & `12–120fps` FPS sliders, `4K` resolution, and video-specific `infoShort` explainer.
- **Android MediaStore & Export Notifications**: Added Android `POST_NOTIFICATIONS` permission request on export start, saving rendered videos to `/Movies/Fractals` via `MediaStore`, and tappable export-complete share notifications.
- **Celtic Stability, Motion Blur & New Achievements**: Fixed Celtic (`fType == 5`) deep-zoom stability, doubled vertical motion blur strength across all settings subpages, and added **We Need to Go Deeper** (`10¹⁵⁰×`) and **It's Getting Hot in Here** (`10³⁰⁰×`) Play Games achievements.

## [1.0.0] - 2026-11-24
#### Changes & Fixes
- **Dependency & Build Toolchain Upgrade**: Upgraded Kotlin Gradle Plugin (KGP), Android Gradle Plugin (AGP) / Gradle, and all Dart/Flutter dependencies.
- **Android Auto Backup Rules**: Added Android Auto Backup rules (`backup_rules.xml`, `data_extraction_rules.xml`) preserving `FlutterSharedPreferences.xml` across reinstalls and device transfers.
- **JSON-Backed Default Bookmarks**: Migrated default landmarks/bookmarks to `assets/bookmarks.json` with GitHub OTA refresh support.
- **Scroll Velocity Motion Blur**: Added velocity-driven vertical motion blur on scroll in settings while keeping the frosted top header blur.
- **Background Export & MP4 Zoom Animation**: Added Background Foreground-Service Export with live notification progress (`ExportForegroundService`) and MP4 Zoom Animation Export (`Mp4VideoEncoder` via `MediaCodec` + `MediaMuxer`).
- **New Fractal Types**: Added **Multibrot-3** (`z³ + c`) and **Celtic** fractals across GPU shaders, perturbation solver, and CPU renderer.

## [0.9.0] - 2026-11-24
#### Changes & Fixes
- **Googol Deep-Zoom Upgrade**: Raised perturbation reference orbit texture to `256×128` (`16,384` iterations) and engine iteration clamps to `16,384` with `608+`-bit `BigFixed` precision for `10¹⁰⁰×` Googol exploration.
- **Native Recents Link Sharing**: Restored native Android Recents link sharing (`onProvideAssistContent` / `setAssistShareUrl`) synced to the active fractal view.
- **OTA Translation Updates**: Wired GitHub OTA translation updates (`!kDebugMode`) for `Dictionary`.
- **Play Games & Bookmarks**: Fixed `Lost in the Spiral` to track 60-minute incremental steps, retained cached leaderboard ranks on transient errors, and added duplicate bookmark detection in the Share sheet.
- **Settings & Blur-on-Scroll**: Fixed visible header blur-on-scroll (`_InspectorHeaderScrollScaffold`), relocated **Blur on Scroll** to **App & Links**, and added `TextPart.infoShort` explainers to **Rendering & Performance** and **Export**.

## [0.8.10] - 2026-11-24
#### Changes & Fixes
- **Bookmark Added State**: Added `"Added"` (`Icons.bookmark_added_rounded`) state on the Share Sheet and Incoming Preview Pill bookmark buttons.
- **Header Blur-on-Scroll Fix**: Fixed visible header blur-on-scroll (`_InspectorHeaderScrollScaffold`) with translucent `BackdropFilter` over scrolled cards.
- **Potatoemeter Overhaul**: Folded global rank and tap-to-open leaderboard into the Hardware Rating card, removed Copy Results and `mIter/s` breakdown, added `infoShort` explainer, and added cloud score fallback in `_PlayGamesSubPage`.
- **Bookmark Deletion in Edit Dialog**: Moved custom bookmark deletion into the edit dialog (`_BookmarkNameDialog`).
- **Play Games Achievements Fix**: Fixed `Cartographer` (5-bookmark sync) and `Lost in the Spiral` (1h cumulative time sync) Play Games achievements.

## [0.8.9] - 2026-11-24
#### Changes & Fixes
- **Native Toast Notifications**: Replaced Flutter `SnackBar`s with native Android `Toast` notifications (`showToast` / `showAppToast`).
- **HUD Pill Shrink-Wrap Fix**: Fixed `HudStatusRow` pill shrink-wrap (`spaceBetween` instead of `Spacer`) so coordinates don't truncate prematurely.
- **Compact Share Sheet Pill**: Collapsed Share Sheet actions into a rounded 4-icon pill (`Copy Coordinates`, `Share`, `Add to Bookmarks`, `Render Image`).
- **Blur-on-Scroll Restoration**: Restored blur-on-scroll across all settings subpage headers (`_SubPageScaffold`) with a new **Blur on Scroll** toggle in Appearance settings.
- **Ukrainian Localization Polish**: Polished Ukrainian translations (`uk.json`) for natural phrasing.

## [0.8.8] - 2026-11-24
#### Changes & Fixes
- **Ukraine Color Palette (`FractalPalette.ukraine`)**: Added the blue-and-yellow **Ukraine** color palette across GPU shaders, CPU renderer, and UI swatch.
- **Smooth Palette Switching**: Reset progressive GPU bake stage to potato-first on palette/color changes for lag-free switching.
- **Compact HUD & Share Sheet**: Shrink-wrapped the `HudStatusRow` Zoom/Position pill to match the bottom pills and moved **Add to Bookmarks** into the Share sheet.
- **Split Bookmarks & Author Subtitles**: Split bookmarks into **My Bookmarks** and **Default Bookmarks** with `"by <author>"` subtitles (defaulting built-ins to `"by Puzzak"`).
- **Settings & Play Games Polish**: Added hold-to-reset protection on **Reset All Settings**, removed redundant single-block and matching subpage headers, and removed local Play Games disconnect.

## [0.8.7] - 2026-11-24
#### Changes & Fixes
- **Dedicated Play Games Subpage (`_PlayGamesSubPage`)**: Refactored Play Games into a dedicated `_PlayGamesSubPage` with a single hub entry that signs in and opens the subpage when signed out, or opens directly when signed in.
- **Play Games Records & Account Groups**: Grouped **Records** (Deepest Zoom, Exploration Time, Potatoemeter, and **Achievements** with live `X / Y` unlocked progress) and **Account** (**Disconnect Play Games** returning to the main Settings hub).

## [0.8.6] - 2026-11-24
#### Changes & Fixes
- **Redesigned `HudStatusRow`**: Replaced the separate share button with a tappable Zoom + Position share pill, added hold-to-reset protection (`Icons.restart_alt_rounded`), and added an Add to Bookmarks action (`Icons.bookmark_add_rounded`).
- **Expanded `HudBottomBar`**: Expanded the Palette pill label when space permits and moved Bookmarks (`Icons.bookmarks_rounded`) to the bottom bar.
- **Startup `"Loading..."` Fix**: Fixed the `"Loading..."` startup `SnackBar` by waiting until `FractalEngine.initialized` is true before showing it.
- **Inspector, Settings & Potatoemeter Polish**: Added Copy Coordinates to the share sheet, matched PAIOS `primaryFixedDim`/`onPrimaryFixed` settings category icons, removed the redundant hub coordinates card and dead Telemetry HUD toggle, hid manual Max Iterations when Auto Iterations is enabled (raising max to `4000`), and merged Global Rank + Global Leaderboard in Potatoemeter.

## [0.8.5] - 2026-11-24
#### Changes & Fixes
- **Two-Line `HudStatusRow`**: Upgraded `HudStatusRow` to a two-line Zoom + Position readout with full-size (`24px`) Reset, Bookmarks, and Share buttons matching `HudBottomBar`.
- **Simplified `HudBottomBar` & Fullscreen Hint**: Removed the Hide UI button from `HudBottomBar` and added a one-time startup floating `SnackBar` hint for the long-press fullscreen toggle.

## [0.8.4] - 2026-11-24
#### Changes & Fixes
- **1:1 Inspector Sheet Dragging**: Fixed inspector sheet drag multiplier by tracking `globalPosition.dy` relative to drag start for true 1:1 finger movement.
- **Subpage Header Dragging**: Enabled vertical sheet dragging on all inspector subpage headers (`_SubPageScaffold`, including Potatoemeter, Appearance, Bookmarks, Controls, and Export).

## [0.8.3] - 2026-11-24
#### Changes & Fixes
- **Unobstructed Fractal Canvas**: Removed the floating top telemetry bubble and canvas Reset FAB.
- **Compact `HudStatusRow`**: Added a compact `HudStatusRow` directly above the bottom control bar below the fractal viewer with Zoom, Position, and an integrated Reset button.
- **Debug-Only Telemetry**: Restricted renderer mode, iterations counter, and FPS telemetry to debug builds (`kDebugMode`).
- **Magnification & Achievement Calibration**: Fixed `FractalEngine.formatZoom` base magnification (`/ 240.0`) so `240.0` displays as `1.00×` and `minZoom` (`50.0`) displays as `0.21×`, and updated `First Dive` threshold to `100×` magnification.
- **Bookmark Save Fix & Renaming**: Fixed named bookmark save crash (`_BookmarkNameDialog` lifecycle) and added custom bookmark renaming.
- **Play Games Authorship & `?d=<base64url>` Links**: Added Play Games player display name (`getPlayerName`), `"Signed in as <name>"`, Potatoemeter rank in the hub subtitle, QR/share authorship + editable name, and `?d=<base64url>` share link encoding.
- **Settings & Translation Audit**: Added 4-stop Render Quality slider with tooltip, debug-only Render Backend switcher, auto-hiding Drag Preview Resolution when Auto Adaptive LOD is enabled, and shortened/localized subtitles.

## [0.8.2] - 2026-11-24
#### Changes & Fixes
- **Cross-Device Play Games Sync**: Added `refreshAllPlayGamesRanks` to merge cloud exploration time with unsynced local time without overwriting, and merge deepest zoom across devices.
- **Live Potatoemeter Rank Refresh**: Refreshed Potatoemeter global rank live after benchmark submission and when opening the Potatoemeter subpage.
- **First Dive Achievement Threshold**: Fixed the `First Dive` achievement threshold to `100×`.
- **Superscript Scientific Zoom Notation**: Added `FractalEngine.formatZoom` for superscript scientific zoom formatting (e.g. `10¹²×`, `5.2×10⁷⁵×`).
- **Richer Play Games UI & Perturbation Progress**: Enhanced Play Games leaderboard cards (Deepest Zoom, Exploration Time, Potatoemeter Rank) in the Inspector Hub and added an indeterminate progress bar during deep perturbation orbit computation.

## [0.8.1] - 2026-11-24
#### Changes & Fixes
- **Signed Profile Builds**: Signed `profile` APK builds with the release keystore (`key.properties`) so Play Games Services v2 OAuth credentials match.
- **PlayGames Logcat Diagnostics**: Added `PlayGames` logcat diagnostics in `MainActivity.kt`.
- **Gated Play Games UI & Sign-In Feedback**: Gated Leaderboards, Achievements, and Global Rank cards behind signed-in state, with a fallback `SnackBar` when sign-in is cancelled or unavailable.

## [0.8.0] - 2026-11-24
#### Features
- **Google Play Games Services v2 Integration**: Added native Google Play Games Services v2 SDK integration (`play-services-games-v2:20.1.2`) via `MethodChannel`.
- **3 Leaderboards**: Added **Potatoemeter Global Ranking**, **Deepest Zoom Reached**, and **Total Exploration Time** leaderboards.
- **12 Achievements**: Added 12 achievements covering depth milestones, Potatoemeter performance tiers, **Multiverse Hopper** (4-step fractal tour), **Cartographer**, **Share the Infinity**, and **Lost in the Spiral**.
- **Play Games Inspector Hub & Potatoemeter Rank**: Added a Play Games section in the inspector hub and Global Rank display in Potatoemeter.

## Update 0.7.4 ([0.7.4] - 2026-11-24)
#### Changes & Fixes
- **720px Crisp Live Export Preview (`BoxFit.contain`)**: Doubled Cinebench tile preview buffer resolution (`360px -> 720px`) and switched export preview fitting to `BoxFit.contain` so `1:1` and portrait exports never clip.
- **Cancel Rendering Button & Cleaner Copy**: Added instant **Cancel Rendering** (`Icons.stop_circle_rounded`) using `CpuRenderCancellationToken` while exporting, and shortened the status text to `"Rendering image…"`.

## Update 0.7.3 ([0.7.3] - 2026-11-24)
#### Features
- **Cinebench-Style Live Tile Export**: Exports render in center-outward tiles and stream live tile completions into the top fractal viewport card, while the Export button swaps cleanly into the progress bar during export.
- **Device Screen Preset & Export Rotation**: Added `Device Screen` resolution preset and `Current / 0° / 90° / 180° / 270°` rotation selector.
#### Fixes
- **True Square-Pixel Export Math**: Fixed `1:1` and non-screen aspect ratio exports (`logicalW / exportW == logicalH / exportH`) so fractals are never squashed.

## Update 0.7.2 ([0.7.2] - 2026-11-24)
#### Changes
- **Subdomain App Links (`fractals.puzzak.page`)**: Switched Android App Links & share URLs to dedicated `fractals.puzzak.page/v` subdomain backed by GitHub Pages `web` branch.
- **Potatoemeter v2**: 10-pass trimmed-mean GPU stages (`3` warm-up + `10` timed passes dropping 2 fastest/slowest) for tight repeatability, rescaled universal score weights (`0.005 / 0.10 / 0.15`), passive background calibration (`liveAdaptiveRating`), and live benchmark preview inside the top fractal viewport card.

## Update 0.7.1 ([0.7.1] - 2026-11-23)
#### Fixes
- **Deterministic GPU Fence-Synced Potatoemeter**: Added `Image.toByteData(rawRgba)` GPU fence synchronization inside `PotatoBenchmarkRunner`, increased per-stage workloads (`1024×1024 @ 1000 it` for `GPU f32`, `768×768 @ 800 it` for `GPU df64`, `384×384 @ 600 it` for `CPU f64`) with warm-ups + median aggregation, and recalibrated `computeScore` weights (`0.08`, `1.5`, `1.0`).
#### Changes
- **Live Benchmark Preview Card**: Displays each stage's rendered fractal preview (`Ocean` → `Inferno` → `Neon`) and live pass timing inside the Potatoemeter hero card with zero impact on measured scores.

## Update 0.7.0 ([0.7.0] - 2026-11-23)
#### Features
- **Deep-Link & QR Code Bookmark Sharing**: Added `https://puzzak.page/fractals/v?...` + `fractals://v?...` + Play Install Referrer deferred deep-link codec (`FractalShareLink`), scannable QR code Share Sheet (`showShareFractalSheet`), and incoming shared-bookmark preview & save pill.
- **Rich Picture Export Builder**: Added unified PNG/JPEG export with `1080p` / `2K` / `4K` / `8K` resolution presets, `Match Screen` / `16:9` / `2:1` / `21:9` / `32:9` / `4:3` / `1:1` / `Custom` aspect ratios, and `Landscape`/`Portrait` orientation selector.
#### Changes & Fixes
- **UX Overhaul & Palette-Flicker Fix**: Added full-header sheet drag handle, larger bottom bar icons (`24 px`), moved Reset View to a Material 3 canvas FAB, promoted Potatoemeter to top-level with a larger hero card, moved Bento to the bottom without header, clarified hub subtitles, and fixed stale GPU bake invalidation when switching palettes.

## Update 0.6.0 ([0.6.0] - 2026-11-23)
#### Features
- **Potatoemeter Hardware Benchmark & Potato Rating**: Added `PotatoBenchmarkRunner` measuring `GPU f32`, `GPU df64`, and `CPU f64` throughput in `MIter/s`, 6 Potato Rating tiers (`Raw Spud` to `Quantum Yam`), persisted per-device $k_{\text{mode}}$ calibration in `FractalEngine`, and a dedicated Potatoemeter inspector subpage.

## Update 0.5.3 ([0.5.3] - 2026-11-23)
#### Fixes
- **120 FPS Resize & Sheet Transitions in `GPU df64` / `GPU PT` (`FractalCanvas`)**: Allowed `_gpuBakedImage` affine reprojection when the viewport `size` animates or resizes (Explorer Controls drag handle / split sheet) in heavy GPU modes (`gpuDf64`, `gpuPerturbation`), eliminating ~300 ms synchronous shader stalls while keeping `GPU f32` live-rendered edge-to-edge.

## Update 0.5.2 ([0.5.2] - 2026-11-23)
#### Fixes
- Eliminated infinite `_startPtOrbit` loop when reference orbits escape early (`_ptOrbitRequestedMaxIter`), fixing both stuck-in-potato releases and idle 4 FPS / 300 ms re-bakes in `GPU PT`.
- Excluded `ActiveRenderMode.gpuPerturbation` from UI-frame `updateLod` during active gestures (`_onFrameTimings`), matching `gpuDf64`.
- Fixed `FractalEngine.formatZoom` 64-bit integer overflow above `10^18` (`math.pow(10.0, exp)`).

## Update 0.5.1 ([0.5.1] - 2026-11-23)
#### Fixes
- **GPU Perturbation Series Approximation Scaling & Convergence Guard (`PerturbationSolver`, `FractalCanvas`)**: Added `PerturbationOrbitResult.orbitZoom`, scaled SA coefficients `A`/`B`/`C` by `saScale = (orbitZoom / zoom) * (viewportWidth / uSize.width)` (`saScale`, `saScale²`, `saScale³`) to fix DPR/LOD/zoom mismatches, and disabled SA when panning or zooming out beyond its convergence radius.

## Update 0.5.0 ([0.5.0] - 2026-11-23)
#### Features
- **GPU Perturbation Theory & Series Approximation (`10¹⁰⁰+` Deep Zoom)**: Added arbitrary-precision `BigFixed` arithmetic (`lib/engine/big_float.dart`), background-isolate reference orbit + 3-term Series Approximation solver (`lib/engine/perturbation_solver.dart`), and scaled float-exp GPU perturbation shader with Zhuoran's rebasing (`shaders/perturbation.frag`).
#### Changes
- **`ActiveRenderMode.gpuPerturbation` (`GPU PT`)**: Routes `Auto` and `GPU` backends at `zoom >= 2e12` (up to `1e150`) to GPU Perturbation instead of `CPU f64`, with `BigFixed` focal-point camera math and `Deep Spiral 10²⁵×` curated landmark bookmark.

## Update 0.4.3 ([0.4.3] - 2026-11-23)
#### Fixes
- **All-Stage Progressive Crossfade (`FractalCanvas`)**: Fixed GPU progressive stages (`0.10`, `0.25`, `0.50`, `1.0`) to crossfade uniformly via `matchesFrameExceptScale`, started `_fadeController` before committing the new image to eliminate the 1-frame `opacity = 1.0` snap, and smoothed the transition to `320 ms` (`Curves.easeInOutCubic`).
- **Uniform Fullscreen Corner Inset (`lib/main.dart`)**: Added `1.5 dp` hardware squircle inset on rounded fullscreen displays so the 3 px edge progress bar keeps uniform thickness through the 45° corner apex.

## Update 0.4.2 ([0.4.2] - 2026-11-23)
#### Changes
- **Unified Progressive-LOD Progress Bar (`FractalCanvas`)**: Unified the idle refinement progress bar (`0% → 100%`) weighted by `scale²` across all progressive LOD stages instead of resetting per LOD.
- **Extended Idle Sharpening Crossfade (`FractalCanvas`)**: Extended the idle progressive sharpening crossfade duration to `280 ms` (`Curves.easeOutCubic`) for smoother, more noticeable transitions.
#### Fixes
- **Fullscreen Corner-Radius DPR Scaling (`lib/main.dart`)**: Fixed fullscreen corner-radius progress bar DPR scaling (`_screenTopCornerRadiusPx / MediaQuery.devicePixelRatioOf(context)` in `build()`), resolving the cold-start `1.0x` DPR semicircle on Pixel 9 Pro.

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
