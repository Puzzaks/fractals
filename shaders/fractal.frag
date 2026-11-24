#version 460 core

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uCenterXHi;
uniform float uCenterXLo;
uniform float uCenterYHi;
uniform float uCenterYLo;
uniform float uScaleHi;
uniform float uScaleLo;
uniform float uMaxIter;
uniform float uFractalType;
uniform vec2 uJuliaC;
uniform float uPalette;
uniform vec3 uPrimaryColor;
uniform vec3 uSecondaryColor;
uniform float uColorOffset;
uniform float uSmoothColor;
uniform float uUseDf64;
uniform float uSsaa;
uniform vec2 uRot;

out vec4 fragColor;

// ---------------------------------------------------------------------------
// Double-float (df64) arithmetic via Dekker-Knuth error-free transformations.
// Note: Mandelbrot/Julia coordinates remain bounded (|z| <= 16 before escape),
// so 4097.0 * a never overflows IEEE-754 float32.
// ---------------------------------------------------------------------------

vec2 dfQuickTwoSum(float a, float b) {
  precise float s = a + b;
  precise float e = b - (s - a);
  return vec2(s, e);
}

vec2 dfTwoSum(float a, float b) {
  precise float s = a + b;
  precise float v = s - a;
  precise float e = (a - (s - v)) + (b - v);
  return vec2(s, e);
}

vec2 dfSplit(float a) {
  precise float c = 4097.0 * a;
  precise float aBig = c - a;
  precise float aHi = c - aBig;
  precise float aLo = a - aHi;
  return vec2(aHi, aLo);
}

vec2 dfTwoProd(float a, float b) {
  precise float p = a * b;
  vec2 aS = dfSplit(a);
  vec2 bS = dfSplit(b);
  precise float err =
      ((aS.x * bS.x - p) + aS.x * bS.y + aS.y * bS.x) + aS.y * bS.y;
  return vec2(p, err);
}

vec2 dfTwoProdSplit(float a, vec2 aS, float b, vec2 bS) {
  precise float p = a * b;
  precise float err =
      ((aS.x * bS.x - p) + aS.x * bS.y + aS.y * bS.x) + aS.y * bS.y;
  return vec2(p, err);
}

vec2 dfSqrSplit(float a, vec2 aS) {
  precise float p = a * a;
  precise float err = ((aS.x * aS.x - p) + 2.0 * aS.x * aS.y) + aS.y * aS.y;
  return vec2(p, err);
}

vec2 dfAdd(vec2 a, vec2 b) {
  vec2 s = dfTwoSum(a.x, b.x);
  vec2 t = dfTwoSum(a.y, b.y);
  s.y += t.x;
  s = dfQuickTwoSum(s.x, s.y);
  s.y += t.y;
  s = dfQuickTwoSum(s.x, s.y);
  return s;
}

vec2 dfAddFast(vec2 a, vec2 b) {
  vec2 s = dfTwoSum(a.x, b.x);
  s.y += a.y + b.y;
  return dfQuickTwoSum(s.x, s.y);
}

vec2 dfSub(vec2 a, vec2 b) {
  return dfAdd(a, vec2(-b.x, -b.y));
}

vec2 dfMul(vec2 a, vec2 b) {
  vec2 p = dfTwoProd(a.x, b.x);
  p.y += a.x * b.y + a.y * b.x;
  return dfQuickTwoSum(p.x, p.y);
}

vec2 dfAbs(vec2 a) {
  return (a.x < 0.0 || (a.x == 0.0 && a.y < 0.0)) ? vec2(-a.x, -a.y) : a;
}

// ---------------------------------------------------------------------------
// Cyclic 4-stop smooth palette sampler (zero wrap discontinuity)
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
// Single-sample fractal evaluator (float32 or df64 path)
// ---------------------------------------------------------------------------

vec3 evalSample(vec2 fragPos) {
  int fType = int(uFractalType + 0.5);
  int maxIter = int(clamp(uMaxIter, 1.0, 2000.0));
  vec2 offsetPx = fragPos - (uSize * 0.5);
  offsetPx = vec2(
    offsetPx.x * uRot.x - offsetPx.y * uRot.y,
    offsetPx.x * uRot.y + offsetPx.y * uRot.x
  );
  float escapeR2 = uSmoothColor >= 0.5 ? 256.0 : 4.0;

  float escapedIter = -1.0;
  float mag2 = 0.0;

  if (uUseDf64 >= 0.5) {
    vec2 scale = vec2(uScaleHi, uScaleLo);
    vec2 cx = dfAdd(vec2(uCenterXHi, uCenterXLo), dfMul(vec2(offsetPx.x, 0.0), scale));
    vec2 cy = dfAdd(vec2(uCenterYHi, uCenterYLo), dfMul(vec2(offsetPx.y, 0.0), scale));

    // Early cardioid & period-2 bulb bailout for Mandelbrot
    if (fType == 0) {
      float fx = cx.x + cx.y;
      float fy = cy.x + cy.y;
      float fy2 = fy * fy;
      float xMinus = fx - 0.25;
      float q = xMinus * xMinus + fy2;
      if (q * (q + xMinus) <= 0.25 * fy2) {
        return vec3(0.0);
      }
      float xPlus1 = fx + 1.0;
      if (xPlus1 * xPlus1 + fy2 <= 0.0625) {
        return vec3(0.0);
      }
    }

    vec2 zx = vec2(0.0);
    vec2 zy = vec2(0.0);
    vec2 px = cx;
    vec2 py = cy;

    if (fType == 1) {
      zx = cx;
      zy = cy;
      px = vec2(uJuliaC.x, 0.0);
      py = vec2(uJuliaC.y, 0.0);
    }

    vec2 ox = vec2(0.0);
    vec2 oy = vec2(0.0);
    int period = 8;
    int steps = 0;

    for (int i = 0; i < 2000; i++) {
      if (i >= maxIter) break;
      if (fType == 2) {
        zx = dfAbs(zx);
        zy = dfAbs(zy);
      }
      vec2 zxS = dfSplit(zx.x);
      vec2 zyS = dfSplit(zy.x);
      vec2 zx2 = dfSqrSplit(zx.x, zxS);
      zx2.y += 2.0 * zx.x * zx.y;
      zx2 = dfQuickTwoSum(zx2.x, zx2.y);

      vec2 zy2 = dfSqrSplit(zy.x, zyS);
      zy2.y += 2.0 * zy.x * zy.y;
      zy2 = dfQuickTwoSum(zy2.x, zy2.y);

      mag2 = (zx2.x + zx2.y) + (zy2.x + zy2.y);
      if (mag2 > escapeR2) {
        escapedIter = float(i);
        break;
      }

      if (fType == 4) {
        vec2 threeZy2 = dfMul(vec2(3.0, 0.0), zy2);
        vec2 threeZx2 = dfMul(vec2(3.0, 0.0), zx2);
        vec2 nextZx = dfAddFast(dfMul(zx, dfSub(zx2, threeZy2)), px);
        vec2 nextZy = dfAddFast(dfMul(zy, dfSub(threeZx2, zy2)), py);
        zx = nextZx;
        zy = nextZy;
      } else {
        vec2 twoZxy = dfTwoProdSplit(zx.x, zxS, zy.x, zyS);
        twoZxy.y += zx.x * zy.y + zx.y * zy.x;
        twoZxy = dfQuickTwoSum(twoZxy.x, twoZxy.y);
        twoZxy *= 2.0;
        if (fType == 3) {
          twoZxy = -twoZxy;
        }
        vec2 reSq = dfSub(zx2, zy2);
        if (fType == 5) {
          reSq = dfAbs(reSq);
        }
        zx = dfAddFast(reSq, px);
        zy = dfAddFast(twoZxy, py);
      }

      if (fType == 0) {
        if (abs(zx.x - ox.x) + abs(zy.x - oy.x) < 1e-7 &&
            abs(zx.y - ox.y) + abs(zy.y - oy.y) < 1e-11) {
          escapedIter = -1.0;
          break;
        }
        steps++;
        if (steps >= period) {
          ox = zx;
          oy = zy;
          period *= 2;
          steps = 0;
        }
      }
    }
  } else {
    float cx = uCenterXHi + offsetPx.x * uScaleHi;
    float cy = uCenterYHi + offsetPx.y * uScaleHi;

    if (fType == 0) {
      float cy2 = cy * cy;
      float xMinus = cx - 0.25;
      float q = xMinus * xMinus + cy2;
      if (q * (q + xMinus) <= 0.25 * cy2) {
        return vec3(0.0);
      }
      float xPlus1 = cx + 1.0;
      if (xPlus1 * xPlus1 + cy2 <= 0.0625) {
        return vec3(0.0);
      }
    }

    float zx = 0.0;
    float zy = 0.0;
    float px = cx;
    float py = cy;

    if (fType == 1) {
      zx = cx;
      zy = cy;
      px = uJuliaC.x;
      py = uJuliaC.y;
    }

    float ox = 0.0;
    float oy = 0.0;
    int period = 8;
    int steps = 0;

    for (int i = 0; i < 2000; i++) {
      if (i >= maxIter) break;
      if (fType == 2) {
        zx = abs(zx);
        zy = abs(zy);
      }
      float zx2 = zx * zx;
      float zy2 = zy * zy;
      mag2 = zx2 + zy2;
      if (mag2 > escapeR2) {
        escapedIter = float(i);
        break;
      }
      if (fType == 4) {
        float nextZx = zx * (zx2 - 3.0 * zy2) + px;
        float nextZy = zy * (3.0 * zx2 - zy2) + py;
        zx = nextZx;
        zy = nextZy;
      } else if (fType == 5) {
        float nextZy = 2.0 * zx * zy + py;
        zx = abs(zx2 - zy2) + px;
        zy = nextZy;
      } else {
        float nextZy = (fType == 3 ? -2.0 : 2.0) * zx * zy + py;
        zx = zx2 - zy2 + px;
        zy = nextZy;
      }

      if (fType == 0) {
        if (abs(zx - ox) + abs(zy - oy) < 1e-6) {
          escapedIter = -1.0;
          break;
        }
        steps++;
        if (steps >= period) {
          ox = zx;
          oy = zy;
          period *= 2;
          steps = 0;
        }
      }
    }
  }

  if (escapedIter < 0.0) {
    return vec3(0.0);
  }

  float nu = escapedIter;
  if (uSmoothColor >= 0.5) {
    float logZn = log(max(mag2, 1.0001)) * 0.5;
    float degreeLog = (fType == 4) ? log(3.0) : log(2.0);
    nu = escapedIter + 1.0 - log(max(logZn / log(2.0), 1e-6)) / degreeLog;
  }
  float phase = nu * 0.032 + uColorOffset;
  return samplePalette(phase);
}

void main() {
  vec2 pos = FlutterFragCoord().xy;
  if (uSsaa >= 0.5) {
    // 2x2 rotated-grid supersampling for Ultra quality
    vec3 acc = evalSample(pos + vec2(-0.375, -0.125));
    acc += evalSample(pos + vec2(0.125, -0.375));
    acc += evalSample(pos + vec2(0.375, 0.125));
    acc += evalSample(pos + vec2(-0.125, 0.375));
    fragColor = vec4(acc * 0.25, 1.0);
  } else {
    fragColor = vec4(evalSample(pos), 1.0);
  }
}
