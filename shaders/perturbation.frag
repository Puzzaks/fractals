#version 460 core

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;            // 0..1
uniform vec2 uRot;             // 2..3
uniform float uScaleMantissa;  // 4 (in [0.5, 1.0))
uniform float uScaleExp;       // 5 (power of 2 exponent: 1/zoom = uScaleMantissa * exp2(uScaleExp))
uniform vec2 uRefDeltaPx;      // 6..7 (pixel offset from viewport center to ref center)
uniform float uMaxIter;        // 8
uniform float uRefLen;         // 9
uniform float uFractalType;    // 10
uniform float uPalette;        // 11
uniform vec3 uPrimaryColor;    // 12..14
uniform vec3 uSecondaryColor;  // 15..17
uniform float uColorOffset;    // 18
uniform float uSmoothColor;    // 19
uniform vec2 uRefCenterApprox; // 20..21
uniform vec2 uJuliaC;          // 22..23
uniform float uSaSkip;         // 24
uniform vec2 uSaA;             // 25..26
uniform vec2 uSaB;             // 27..28
uniform vec2 uSaC;             // 29..30
uniform sampler2D uRefOrbit;   // sampler slot 0 (256 x 32)

out vec4 fragColor;

// ---------------------------------------------------------------------------
// Complex & 24-bit texture orbit helpers
// ---------------------------------------------------------------------------

vec2 cmul(vec2 a, vec2 b) {
  return vec2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

float decode24(vec3 rgb) {
  return (dot(floor(rgb * 255.0 + 0.5), vec3(65536.0, 256.0, 1.0)) / 16777215.0) * 8.0 - 4.0;
}

vec2 sampleOrbit(int idx) {
  int texRe = idx * 2;
  int texIm = texRe + 1;
  int rowRe = texRe / 256;
  int colRe = texRe - rowRe * 256;
  int rowIm = texIm / 256;
  int colIm = texIm - rowIm * 256;
  vec2 uvRe = vec2((float(colRe) + 0.5) / 256.0, (float(rowRe) + 0.5) / 32.0);
  vec2 uvIm = vec2((float(colIm) + 0.5) / 256.0, (float(rowIm) + 0.5) / 32.0);
  float re = decode24(texture(uRefOrbit, uvRe).rgb);
  float im = decode24(texture(uRefOrbit, uvIm).rgb);
  return vec2(re, im);
}

// ---------------------------------------------------------------------------
// Cyclic 4-stop smooth palette sampler (matches shaders/fractal.frag)
// ---------------------------------------------------------------------------

vec3 cyclicGradient(float t, vec3 c0, vec3 c1, vec3 c2, vec3 c3) {
  float x = fract(t) * 4.0;
  float idx = floor(x);
  float f = smoothstep(0.0, 1.0, fract(x));
  if (idx < 0.5) return mix(c0, c1, f);
  if (idx < 1.5) return mix(c1, c2, f);
  if (idx < 2.5) return mix(c2, c3, f);
  return mix(c3, c0, f);
}

vec3 samplePalette(float t) {
  int pal = int(uPalette + 0.5);
  if (pal == 0) {
    // System Dynamic (Material You primary + secondary/tertiary)
    vec3 darkBase = uPrimaryColor * 0.16;
    vec3 midPrimary = uPrimaryColor;
    vec3 highlight = mix(uSecondaryColor, vec3(1.0), 0.35);
    vec3 accent = uSecondaryColor * 0.85;
    return cyclicGradient(t, darkBase, midPrimary, highlight, accent);
  }
  if (pal == 1) {
    // Inferno
    return cyclicGradient(
      t,
      vec3(0.04, 0.02, 0.10),
      vec3(0.52, 0.11, 0.42),
      vec3(0.93, 0.41, 0.13),
      vec3(0.99, 0.96, 0.64)
    );
  }
  if (pal == 2) {
    // Viridis
    return cyclicGradient(
      t,
      vec3(0.16, 0.04, 0.33),
      vec3(0.17, 0.42, 0.56),
      vec3(0.15, 0.68, 0.51),
      vec3(0.92, 0.90, 0.18)
    );
  }
  if (pal == 3) {
    // Ocean
    return cyclicGradient(
      t,
      vec3(0.01, 0.06, 0.18),
      vec3(0.04, 0.36, 0.68),
      vec3(0.18, 0.82, 0.88),
      vec3(0.88, 0.97, 1.00)
    );
  }
  if (pal == 4) {
    // Neon cosine spectrum
    return 0.5 + 0.5 * cos(6.2831853 * (t + vec3(0.0, 0.33, 0.67)));
  }
  if (pal == 5) {
    // Monochrome
    float lum = 0.5 - 0.5 * cos(6.2831853 * t);
    return vec3(lum * 0.94, lum * 0.96, lum);
  }
  if (pal == 6) {
    // Twilight
    return cyclicGradient(
      t,
      vec3(0.08, 0.05, 0.22),
      vec3(0.49, 0.22, 0.60),
      vec3(0.92, 0.48, 0.50),
      vec3(0.96, 0.84, 0.65)
    );
  }
  // Ukraine (pal == 7)
  return cyclicGradient(
    t,
    vec3(0.00, 0.34, 0.72),
    vec3(0.12, 0.53, 0.90),
    vec3(1.00, 0.84, 0.00),
    vec3(1.00, 0.96, 0.62)
  );
}

// ---------------------------------------------------------------------------
// Scaled Float-Exp Perturbation evaluator with Zhuoran's rebasing + SA
// ---------------------------------------------------------------------------

vec3 evalPerturbation(vec2 fragPos) {
  int fType = int(uFractalType + 0.5);
  int maxIter = int(clamp(uMaxIter, 1.0, 16384.0));
  int refLen = int(max(uRefLen, 1.0));

  vec2 offsetPx = fragPos - (uSize * 0.5);
  offsetPx = vec2(
    offsetPx.x * uRot.x - offsetPx.y * uRot.y,
    offsetPx.x * uRot.y + offsetPx.y * uRot.x
  );
  vec2 deltaPx = offsetPx - uRefDeltaPx;

  int s0 = int(floor(uScaleExp + 0.5));
  vec2 dc0 = deltaPx * uScaleMantissa;
  vec2 cDelta = (fType == 1) ? vec2(0.0) : dc0;

  vec2 d = (fType == 1) ? dc0 : vec2(0.0);
  int s = s0;
  int refIdx = 0;
  int startIter = 0;

  // Series Approximation initialization for Mandelbrot
  if (uSaSkip > 0.5 && fType == 0) {
    vec2 dp2 = cmul(deltaPx, deltaPx);
    vec2 dp3 = cmul(dp2, deltaPx);
    d = cmul(uSaA, deltaPx) + cmul(uSaB, dp2) + cmul(uSaC, dp3);
    s = 0;
    for (int k = 0; k < 32; k++) {
      float d2 = dot(d, d);
      if (d2 == 0.0 || d2 >= 0.0625 || s <= -120) break;
      d *= 16.0;
      s -= 4;
    }
    for (int k = 0; k < 8; k++) {
      float d2 = dot(d, d);
      if (d2 <= 16.0 || s >= 12) break;
      d *= 0.0625;
      s += 4;
    }
    refIdx = int(uSaSkip + 0.5);
    if (refIdx >= refLen) {
      refIdx = refLen - 1;
    }
    startIter = refIdx;
  }

  float escapedIter = -1.0;
  float mag2 = 0.0;
  vec2 Z = vec2(0.0);

  for (int n = 0; n < 16384; n++) {
    if (n < startIter) continue;
    if (n >= maxIter) break;

    vec2 X = sampleOrbit(refIdx);
    vec2 dActual = (s >= -120) ? (d * exp2(float(s))) : vec2(0.0);
    Z = X + dActual;
    float z2 = dot(Z, Z);

    if (z2 > 4.0) {
      escapedIter = float(n);
      mag2 = z2;
      break;
    }

    // Zhuoran's rebasing: rebase when |Z| < |dActual| or end of reference orbit
    bool shouldRebase = (refIdx + 1 >= refLen);
    if (fType != 1 && s >= -120 && z2 < dot(dActual, dActual)) {
      shouldRebase = true;
    }

    if (shouldRebase) {
      refIdx = 0;
      X = (fType == 1) ? sampleOrbit(0) : vec2(0.0);
      d = Z - X;
      s = 0;
      for (int k = 0; k < 32; k++) {
        float d2 = dot(d, d);
        if (d2 == 0.0 || d2 >= 0.0625 || s <= -120) break;
        d *= 16.0;
        s -= 4;
      }
    }

    // Perturbation recurrence step
    float scaleS = (s >= -126) ? exp2(float(s)) : 0.0;
    float expDiff = float(s0 - s);
    float scaleC = (expDiff >= -126.0 && expDiff <= 20.0) ? exp2(expDiff) : 0.0;

    if (fType == 2) {
      // Burning Ship: |X + d * 2^s| - |X|
      vec2 da;
      if (s > -120) {
        da = (abs(X + d * exp2(float(s))) - abs(X)) * exp2(float(-s));
      } else {
        da = vec2(
          X.x == 0.0 ? abs(d.x) : (X.x > 0.0 ? d.x : -d.x),
          X.y == 0.0 ? abs(d.y) : (X.y > 0.0 ? d.y : -d.y)
        );
      }
      d = 2.0 * cmul(abs(X), da) + cmul(da, da) * scaleS + cDelta * scaleC;
    } else if (fType == 3) {
      // Tricorn: conjugate Z
      vec2 Xc = vec2(X.x, -X.y);
      vec2 dc = vec2(d.x, -d.y);
      d = 2.0 * cmul(Xc, dc) + cmul(dc, dc) * scaleS + cDelta * scaleC;
    } else {
      // Mandelbrot (0) & Julia (1)
      d = 2.0 * cmul(X, d) + cmul(d, d) * scaleS + cDelta * scaleC;
    }

    // Renormalize (d, s) to keep mantissa in well-conditioned float32 range
    float d2 = dot(d, d);
    for (int k = 0; k < 8; k++) {
      if (d2 <= 16.0 || s >= 12) break;
      d *= 0.0625;
      s += 4;
      d2 = dot(d, d);
    }
    for (int k = 0; k < 8; k++) {
      if (d2 >= 1e-6 || d2 == 0.0 || s <= s0 - 16) break;
      d *= 16.0;
      s -= 4;
      d2 = dot(d, d);
    }

    refIdx++;
  }

  if (escapedIter < 0.0) {
    return vec3(0.0);
  }

  if (uSmoothColor >= 0.5) {
    vec2 cApprox = (fType == 1) ? uJuliaC : uRefCenterApprox;
    for (int k = 0; k < 4; k++) {
      if (mag2 >= 256.0) break;
      vec2 Zs = (fType == 2) ? abs(Z) : Z;
      float zx2 = Zs.x * Zs.x;
      float zy2 = Zs.y * Zs.y;
      float nextZy = (fType == 3 ? -2.0 : 2.0) * Zs.x * Zs.y + cApprox.y;
      float nextZx = zx2 - zy2 + cApprox.x;
      Z = vec2(nextZx, nextZy);
      mag2 = dot(Z, Z);
      escapedIter += 1.0;
    }
  }

  float nu = escapedIter;
  if (uSmoothColor >= 0.5) {
    float logZn = log(max(mag2, 1.0001)) * 0.5;
    nu = escapedIter + 1.0 - log(max(logZn / log(2.0), 1e-6)) / log(2.0);
  }
  float phase = nu * 0.032 + uColorOffset;
  return samplePalette(phase);
}

void main() {
  fragColor = vec4(evalPerturbation(FlutterFragCoord().xy), 1.0);
}
