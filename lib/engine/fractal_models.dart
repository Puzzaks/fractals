import 'dart:typed_data';

/// Supported fractal mathematical formulas.
enum FractalType {
  mandelbrot(
    index: 0,
    translationKey: 'fractal_mandelbrot',
    defaultCenterX: -0.5,
    defaultCenterY: 0.0,
    defaultZoom: 240.0,
  ),
  julia(
    index: 1,
    translationKey: 'fractal_julia',
    defaultCenterX: 0.0,
    defaultCenterY: 0.0,
    defaultZoom: 240.0,
  ),
  burningShip(
    index: 2,
    translationKey: 'fractal_burning_ship',
    defaultCenterX: -0.4,
    defaultCenterY: -0.5,
    defaultZoom: 220.0,
  ),
  tricorn(
    index: 3,
    translationKey: 'fractal_tricorn',
    defaultCenterX: -0.3,
    defaultCenterY: 0.0,
    defaultZoom: 220.0,
  );

  final int shaderIndex;
  final String translationKey;
  final double defaultCenterX;
  final double defaultCenterY;
  final double defaultZoom;

  const FractalType({
    required int index,
    required this.translationKey,
    required this.defaultCenterX,
    required this.defaultCenterY,
    required this.defaultZoom,
  }) : shaderIndex = index;

  static FractalType fromName(String? name) {
    return FractalType.values.firstWhere(
      (e) => e.name == name,
      orElse: () => FractalType.mandelbrot,
    );
  }
}

/// Curated continuous color palettes matching `shaders/fractal.frag` and
/// `cpu_renderer.dart`.
enum FractalPalette {
  system(index: 0, translationKey: 'palette_system'),
  inferno(index: 1, translationKey: 'palette_inferno'),
  viridis(index: 2, translationKey: 'palette_viridis'),
  ocean(index: 3, translationKey: 'palette_ocean'),
  neon(index: 4, translationKey: 'palette_neon'),
  monochrome(index: 5, translationKey: 'palette_monochrome'),
  twilight(index: 6, translationKey: 'palette_twilight'),
  ukraine(index: 7, translationKey: 'palette_ukraine');

  final int shaderIndex;
  final String translationKey;

  const FractalPalette({
    required int index,
    required this.translationKey,
  }) : shaderIndex = index;

  static FractalPalette fromName(String? name) {
    return FractalPalette.values.firstWhere(
      (e) => e.name == name,
      orElse: () => FractalPalette.system,
    );
  }
}

/// Render quality presets controlling CPU pixel density, iteration scaling,
/// and GPU 2x2 rotated-grid supersampling (SSAA).
enum RenderQuality {
  performance(
    resolutionScale: 0.5,
    iterationMultiplier: 0.65,
    useSsaa: false,
    translationKey: 'quality_performance',
  ),
  balanced(
    resolutionScale: 0.75,
    iterationMultiplier: 0.85,
    useSsaa: false,
    translationKey: 'quality_balanced',
  ),
  native(
    resolutionScale: 1.0,
    iterationMultiplier: 1.0,
    useSsaa: false,
    translationKey: 'quality_native',
  ),
  ultra(
    resolutionScale: 1.5,
    iterationMultiplier: 1.25,
    useSsaa: true,
    translationKey: 'quality_ultra',
  );

  final double resolutionScale;
  final double iterationMultiplier;
  final bool useSsaa;
  final String translationKey;

  const RenderQuality({
    required this.resolutionScale,
    required this.iterationMultiplier,
    required this.useSsaa,
    required this.translationKey,
  });

  static RenderQuality fromName(String? name) {
    return RenderQuality.values.firstWhere(
      (e) => e.name == name,
      orElse: () => RenderQuality.native,
    );
  }
}

/// User-selectable rendering backend preference.
enum RenderBackend {
  auto(translationKey: 'backend_auto'),
  gpuShader(translationKey: 'backend_gpu'),
  cpuFloat64(translationKey: 'backend_cpu');

  final String translationKey;

  const RenderBackend({required this.translationKey});

  static RenderBackend fromName(String? name) {
    return RenderBackend.values.firstWhere(
      (e) => e.name == name,
      orElse: () => RenderBackend.auto,
    );
  }
}

/// Effective active execution mode resolved from [RenderBackend] and zoom.
enum ActiveRenderMode {
  gpuFloat32(badge: 'GPU f32'),
  gpuDf64(badge: 'GPU df64'),
  gpuPerturbation(badge: 'GPU PT'),
  cpuFloat64(badge: 'CPU f64');

  final String badge;

  const ActiveRenderMode({required this.badge});

  bool get isCpu => this == ActiveRenderMode.cpuFloat64;
  bool get isGpu => !isCpu;
  bool get isPerturbation => this == ActiveRenderMode.gpuPerturbation;
}

/// Splits an IEEE-754 64-bit [double] into a `(hi, lo)` pair of 32-bit
/// representable values such that `hi + lo == value` for `df64` GLSL uniforms.
(double hi, double lo) splitDoubleToDf64(double value) {
  if (!value.isFinite) {
    return (0.0, 0.0);
  }
  final Float32List f32 = Float32List(1);
  f32[0] = value;
  final double hi = f32[0];
  final double lo = value - hi;
  return (hi, lo);
}

/// Saved coordinate + aesthetic bookmark for quick navigation.
class FractalBookmark {
  final String id;
  final String name;
  final FractalType fractalType;
  final double centerX;
  final double centerY;
  final String? centerXDecimal;
  final String? centerYDecimal;
  final double zoom;
  final double juliaCx;
  final double juliaCy;
  final FractalPalette palette;
  final String? author;
  final bool isBuiltIn;

  const FractalBookmark({
    required this.id,
    required this.name,
    required this.fractalType,
    required this.centerX,
    required this.centerY,
    this.centerXDecimal,
    this.centerYDecimal,
    required this.zoom,
    this.juliaCx = -0.7269,
    this.juliaCy = 0.1889,
    this.palette = FractalPalette.system,
    this.author,
    this.isBuiltIn = false,
  });

  FractalBookmark copyWith({
    String? id,
    String? name,
    FractalType? fractalType,
    double? centerX,
    double? centerY,
    String? centerXDecimal,
    String? centerYDecimal,
    double? zoom,
    double? juliaCx,
    double? juliaCy,
    FractalPalette? palette,
    String? author,
    bool? isBuiltIn,
  }) {
    return FractalBookmark(
      id: id ?? this.id,
      name: name ?? this.name,
      fractalType: fractalType ?? this.fractalType,
      centerX: centerX ?? this.centerX,
      centerY: centerY ?? this.centerY,
      centerXDecimal: centerXDecimal ?? this.centerXDecimal,
      centerYDecimal: centerYDecimal ?? this.centerYDecimal,
      zoom: zoom ?? this.zoom,
      juliaCx: juliaCx ?? this.juliaCx,
      juliaCy: juliaCy ?? this.juliaCy,
      palette: palette ?? this.palette,
      author: author ?? this.author,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'fractalType': fractalType.name,
        'centerX': centerX,
        'centerY': centerY,
        if (centerXDecimal != null) 'centerXDecimal': centerXDecimal,
        if (centerYDecimal != null) 'centerYDecimal': centerYDecimal,
        'zoom': zoom,
        'juliaCx': juliaCx,
        'juliaCy': juliaCy,
        'palette': palette.name,
        if (author != null) 'author': author,
      };

  factory FractalBookmark.fromJson(Map<String, dynamic> json) {
    return FractalBookmark(
      id: json['id']?.toString() ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      name: json['name']?.toString() ?? 'Bookmark',
      fractalType: FractalType.fromName(json['fractalType']?.toString()),
      centerX: (json['centerX'] as num?)?.toDouble() ?? -0.5,
      centerY: (json['centerY'] as num?)?.toDouble() ?? 0.0,
      centerXDecimal: json['centerXDecimal']?.toString(),
      centerYDecimal: json['centerYDecimal']?.toString(),
      zoom: (json['zoom'] as num?)?.toDouble() ?? 240.0,
      juliaCx: (json['juliaCx'] as num?)?.toDouble() ?? -0.7269,
      juliaCy: (json['juliaCy'] as num?)?.toDouble() ?? 0.1889,
      palette: FractalPalette.fromName(json['palette']?.toString()),
      author: json['author']?.toString(),
      isBuiltIn: false,
    );
  }
}

/// Curated mathematical landmarks across all supported fractals.
const List<FractalBookmark> builtInBookmarks = <FractalBookmark>[
  FractalBookmark(
    id: 'builtin_mandelbrot_home',
    name: 'Mandelbrot Overview',
    fractalType: FractalType.mandelbrot,
    centerX: -0.5,
    centerY: 0.0,
    zoom: 240.0,
    palette: FractalPalette.system,
    author: 'Puzzak',
    isBuiltIn: true,
  ),
  FractalBookmark(
    id: 'builtin_seahorse_valley',
    name: 'Seahorse Valley',
    fractalType: FractalType.mandelbrot,
    centerX: -0.743643887037151,
    centerY: 0.131825904205330,
    zoom: 400000.0,
    palette: FractalPalette.ocean,
    author: 'Puzzak',
    isBuiltIn: true,
  ),
  FractalBookmark(
    id: 'builtin_elephant_valley',
    name: 'Elephant Valley',
    fractalType: FractalType.mandelbrot,
    centerX: 0.281717921930775,
    centerY: 0.011005259958547,
    zoom: 50000.0,
    palette: FractalPalette.inferno,
    author: 'Puzzak',
    isBuiltIn: true,
  ),
  FractalBookmark(
    id: 'builtin_minibrot',
    name: 'Mini-Brot Island',
    fractalType: FractalType.mandelbrot,
    centerX: -1.768778833,
    centerY: -0.001738996,
    zoom: 2500000.0,
    palette: FractalPalette.twilight,
    author: 'Puzzak',
    isBuiltIn: true,
  ),
  FractalBookmark(
    id: 'builtin_triple_spiral',
    name: 'Triple Spiral',
    fractalType: FractalType.mandelbrot,
    centerX: -0.088,
    centerY: 0.654,
    zoom: 12000.0,
    palette: FractalPalette.viridis,
    author: 'Puzzak',
    isBuiltIn: true,
  ),
  FractalBookmark(
    id: 'builtin_burning_ship',
    name: 'Burning Ship Armada',
    fractalType: FractalType.burningShip,
    centerX: -1.755,
    centerY: -0.025,
    zoom: 4500.0,
    palette: FractalPalette.inferno,
    author: 'Puzzak',
    isBuiltIn: true,
  ),
  FractalBookmark(
    id: 'builtin_julia_dendrite',
    name: 'Julia Dendrite',
    fractalType: FractalType.julia,
    centerX: 0.0,
    centerY: 0.0,
    zoom: 240.0,
    juliaCx: -0.7269,
    juliaCy: 0.1889,
    palette: FractalPalette.neon,
    author: 'Puzzak',
    isBuiltIn: true,
  ),
  FractalBookmark(
    id: 'builtin_julia_spiral',
    name: 'Julia Spiral Galaxy',
    fractalType: FractalType.julia,
    centerX: 0.0,
    centerY: 0.0,
    zoom: 260.0,
    juliaCx: -0.8,
    juliaCy: 0.156,
    palette: FractalPalette.twilight,
    author: 'Puzzak',
    isBuiltIn: true,
  ),
  FractalBookmark(
    id: 'builtin_tricorn_spire',
    name: 'Tricorn Spire',
    fractalType: FractalType.tricorn,
    centerX: -0.3,
    centerY: 0.0,
    zoom: 220.0,
    palette: FractalPalette.ocean,
    author: 'Puzzak',
    isBuiltIn: true,
  ),
  FractalBookmark(
    id: 'builtin_deep_spiral_e25',
    name: 'Deep Spiral 10²⁵×',
    fractalType: FractalType.mandelbrot,
    centerX: -0.7436438870371587,
    centerY: 0.13182590420531197,
    centerXDecimal: '-0.743643887037158704752191506114774',
    centerYDecimal: '0.131825904205311970493132056385139',
    zoom: 1e25,
    palette: FractalPalette.inferno,
    author: 'Puzzak',
    isBuiltIn: true,
  ),
];
