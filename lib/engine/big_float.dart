import 'dart:math' as math;
import 'dart:typed_data';

/// Returns the fixed-point fractional bit width required for a given [zoom]
/// level.
///
/// Returns `128` for `zoom <= 1.0`, otherwise `ceil(log2(zoom)) + 64` rounded
/// up to the next multiple of `64`, clamped to `[128, 640]`.
int requiredPrecisionBits(double zoom) {
  if (zoom.isNaN || zoom <= 1.0) {
    return 128;
  }
  if (!zoom.isFinite) {
    return 640;
  }
  final int bits = (math.log(zoom) / math.ln2).ceil() + 64;
  final int rounded = ((bits + 63) ~/ 64) * 64;
  return rounded.clamp(128, 640);
}

/// Arbitrary-precision signed fixed-point number backed by a [BigInt].
///
/// Represents the real value `raw * 2^(-fracBits)`.
class BigFixed implements Comparable<BigFixed> {
  /// Raw scaled integer value (`value * 2^fracBits`).
  final BigInt raw;

  /// Number of fractional binary bits.
  final int fracBits;

  /// Creates a [BigFixed] directly from its [raw] scaled integer and
  /// [fracBits].
  const BigFixed(this.raw, this.fracBits)
      : assert(fracBits >= 0, 'fracBits must be non-negative');

  /// Creates a zero value with [fracBits] fractional bits.
  BigFixed.zero(this.fracBits)
      : assert(fracBits >= 0, 'fracBits must be non-negative'),
        raw = BigInt.zero;

  /// Creates a [BigFixed] from an integer [v] with [fracBits] fractional bits.
  BigFixed.fromInt(int v, this.fracBits)
      : assert(fracBits >= 0, 'fracBits must be non-negative'),
        raw = BigInt.from(v) << fracBits;

  /// Creates a [BigFixed] from an IEEE-754 [double] [v] using exact binary
  /// decomposition via [ByteData].
  ///
  /// Handles `0.0`, `-0.0`, and subnormals without floating-point scaling
  /// overflow or underflow. Throws an [ArgumentError] if [v] is non-finite.
  factory BigFixed.fromDouble(double v, int fracBits) {
    if (fracBits < 0) {
      throw ArgumentError.value(fracBits, 'fracBits', 'Must be non-negative');
    }
    if (!v.isFinite) {
      throw ArgumentError.value(v, 'v', 'Must be finite');
    }

    final ByteData data = ByteData(8)..setFloat64(0, v, Endian.big);
    final int bits = data.getUint64(0, Endian.big);
    final bool negative = (bits >> 63) != 0;
    final int expBits = (bits >> 52) & 0x7FF;
    final int mantissaBits = bits & 0xFFFFFFFFFFFFF;

    if (expBits == 0 && mantissaBits == 0) {
      return BigFixed.zero(fracBits);
    }

    final BigInt significand;
    final int exponent;
    if (expBits == 0) {
      // Subnormal: value = (-1)^s * mantissa * 2^(-1074)
      significand = BigInt.from(mantissaBits);
      exponent = -1074;
    } else {
      // Normal: value = (-1)^s * (2^52 + mantissa) * 2^(expBits - 1075)
      significand = BigInt.from(mantissaBits) | (BigInt.one << 52);
      exponent = expBits - 1075;
    }

    final int shift = exponent + fracBits;
    final BigInt mag;
    if (shift >= 0) {
      mag = significand << shift;
    } else {
      final int r = -shift;
      if (r > 53) {
        mag = BigInt.zero;
      } else {
        mag = (significand + (BigInt.one << (r - 1))) >> r;
      }
    }

    return BigFixed(negative ? -mag : mag, fracBits);
  }

  /// Parses an arbitrary-length decimal string [s] (including optional sign and
  /// optional `e`/`E` exponent) into a [BigFixed] with [fracBits] fractional
  /// bits using exact [BigInt] base-10 scaling and half-up rounding.
  factory BigFixed.parseDecimal(String s, int fracBits) {
    if (fracBits < 0) {
      throw ArgumentError.value(fracBits, 'fracBits', 'Must be non-negative');
    }
    String text = s.trim();
    if (text.isEmpty) {
      throw FormatException('Empty decimal string', s);
    }

    bool negative = false;
    if (text.startsWith('-')) {
      negative = true;
      text = text.substring(1);
    } else if (text.startsWith('+')) {
      text = text.substring(1);
    }

    if (text.isEmpty) {
      throw FormatException('Invalid decimal string', s);
    }

    int exp10 = 0;
    final int eIndex = text.indexOf(RegExp(r'[eE]'));
    if (eIndex != -1) {
      final String expPart = text.substring(eIndex + 1);
      if (expPart.isEmpty) {
        throw FormatException('Invalid exponent in decimal string', s);
      }
      exp10 = int.parse(expPart);
      text = text.substring(0, eIndex);
    }

    final int dotIndex = text.indexOf('.');
    final String intPart;
    final String fracPart;
    if (dotIndex == -1) {
      intPart = text;
      fracPart = '';
    } else {
      if (text.indexOf('.', dotIndex + 1) != -1) {
        throw FormatException('Multiple decimal points in string', s);
      }
      intPart = text.substring(0, dotIndex);
      fracPart = text.substring(dotIndex + 1);
    }

    final String digitsStr = '$intPart$fracPart';
    if (digitsStr.isEmpty || !RegExp(r'^\d+$').hasMatch(digitsStr)) {
      throw FormatException('Invalid digits in decimal string', s);
    }

    final BigInt digits = BigInt.parse(digitsStr);
    if (digits == BigInt.zero) {
      return BigFixed.zero(fracBits);
    }

    final int scale = fracPart.length - exp10;
    final BigInt mag;
    if (scale <= 0) {
      final BigInt mul = BigInt.from(10).pow(-scale);
      mag = (digits * mul) << fracBits;
    } else {
      final BigInt num = digits << fracBits;
      final BigInt den = BigInt.from(10).pow(scale);
      mag = (num + (den >> 1)) ~/ den;
    }

    return BigFixed(negative ? -mag : mag, fracBits);
  }

  /// Returns a copy of this value with [newFracBits] fractional bits, shifting
  /// left or rounding half-up and shifting right as needed.
  BigFixed withPrecision(int newFracBits) {
    if (newFracBits < 0) {
      throw ArgumentError.value(
        newFracBits,
        'newFracBits',
        'Must be non-negative',
      );
    }
    if (newFracBits == fracBits) {
      return this;
    }
    if (newFracBits > fracBits) {
      return BigFixed(raw << (newFracBits - fracBits), newFracBits);
    }
    final int shift = fracBits - newFracBits;
    final bool neg = raw.isNegative;
    final BigInt absRaw = raw.abs();
    final BigInt rounded = (absRaw + (BigInt.one << (shift - 1))) >> shift;
    return BigFixed(neg ? -rounded : rounded, newFracBits);
  }

  /// Converts this fixed-point value to an IEEE-754 [double].
  ///
  /// Uses bit-length normalization and power-of-two scaling so both very large
  /// and very small values (e.g. `1e-100`) convert cleanly without [BigInt]
  /// conversion overflow.
  double toDouble() {
    if (raw == BigInt.zero) {
      return 0.0;
    }
    final bool neg = raw.isNegative;
    final BigInt absRaw = raw.abs();
    final int bitLen = absRaw.bitLength;

    double mant;
    int exp;
    if (bitLen <= 53) {
      mant = absRaw.toDouble();
      exp = -fracBits;
    } else {
      final int drop = bitLen - 53;
      final BigInt top = (absRaw + (BigInt.one << (drop - 1))) >> drop;
      mant = top.toDouble();
      exp = drop - fracBits;
    }

    // Scale by 2^exp in bounded steps so intermediate math.pow(2.0, ...)
    // never overflows or underflows prematurely.
    while (exp > 512) {
      mant *= _pow2Pos512;
      exp -= 512;
      if (!mant.isFinite) {
        return neg ? double.negativeInfinity : double.infinity;
      }
    }
    while (exp < -512) {
      mant *= _pow2Neg512;
      exp += 512;
      if (mant == 0.0) {
        return 0.0;
      }
    }
    final double result = mant * math.pow(2.0, exp).toDouble();
    return neg ? -result : result;
  }

  static final double _pow2Pos512 = math.pow(2.0, 512).toDouble();
  static final double _pow2Neg512 = math.pow(2.0, -512).toDouble();

  /// Formats this value as a base-10 decimal string with [fracDigits]
  /// fractional digits (rounded half-up).
  ///
  /// When [trimTrailingZeros] is `true`, trailing zeros in the fractional part
  /// (and the decimal point if all fractional digits are zero) are omitted.
  String toDecimalString(int fracDigits, {bool trimTrailingZeros = false}) {
    if (fracDigits < 0) {
      throw ArgumentError.value(
        fracDigits,
        'fracDigits',
        'Must be non-negative',
      );
    }
    final bool neg = raw.isNegative;
    final BigInt absRaw = raw.abs();
    final BigInt scale = BigInt.from(10).pow(fracDigits);
    final BigInt half =
        fracBits > 0 ? (BigInt.one << (fracBits - 1)) : BigInt.zero;
    final BigInt scaled = fracBits > 0
        ? ((absRaw * scale + half) >> fracBits)
        : (absRaw * scale);

    final String sign = (neg && scaled > BigInt.zero) ? '-' : '';
    if (fracDigits == 0) {
      return '$sign$scaled';
    }

    final BigInt intPart = scaled ~/ scale;
    final BigInt fracPart = scaled % scale;
    String fracStr = fracPart.toString().padLeft(fracDigits, '0');
    if (trimTrailingZeros) {
      fracStr = fracStr.replaceFirst(RegExp(r'0+$'), '');
      if (fracStr.isEmpty) {
        return '$sign$intPart';
      }
    }
    return '$sign$intPart.$fracStr';
  }

  BigFixed operator +(BigFixed other) {
    if (fracBits == other.fracBits) {
      return BigFixed(raw + other.raw, fracBits);
    }
    final int target = math.max(fracBits, other.fracBits);
    final BigInt a =
        fracBits == target ? raw : raw << (target - fracBits);
    final BigInt b =
        other.fracBits == target ? other.raw : other.raw << (target - other.fracBits);
    return BigFixed(a + b, target);
  }

  BigFixed operator -(BigFixed other) {
    if (fracBits == other.fracBits) {
      return BigFixed(raw - other.raw, fracBits);
    }
    final int target = math.max(fracBits, other.fracBits);
    final BigInt a =
        fracBits == target ? raw : raw << (target - fracBits);
    final BigInt b =
        other.fracBits == target ? other.raw : other.raw << (target - other.fracBits);
    return BigFixed(a - b, target);
  }

  BigFixed operator -() => BigFixed(-raw, fracBits);

  BigFixed operator *(BigFixed other) {
    if (fracBits == other.fracBits) {
      return BigFixed((raw * other.raw) >> fracBits, fracBits);
    }
    final int target = math.max(fracBits, other.fracBits);
    final BigInt a =
        fracBits == target ? raw : raw << (target - fracBits);
    final BigInt b =
        other.fracBits == target ? other.raw : other.raw << (target - other.fracBits);
    return BigFixed((a * b) >> target, target);
  }

  /// Returns `this * this` at the same [fracBits] precision.
  BigFixed square() => BigFixed((raw * raw) >> fracBits, fracBits);

  /// Returns the absolute value of `this`.
  BigFixed abs() => raw.isNegative ? BigFixed(-raw, fracBits) : this;

  @override
  int compareTo(BigFixed other) {
    if (fracBits == other.fracBits) {
      return raw.compareTo(other.raw);
    }
    final int target = math.max(fracBits, other.fracBits);
    final BigInt a =
        fracBits == target ? raw : raw << (target - fracBits);
    final BigInt b =
        other.fracBits == target ? other.raw : other.raw << (target - other.fracBits);
    return a.compareTo(b);
  }

  bool operator <(BigFixed other) => compareTo(other) < 0;
  bool operator >(BigFixed other) => compareTo(other) > 0;
  bool operator <=(BigFixed other) => compareTo(other) <= 0;
  bool operator >=(BigFixed other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BigFixed && compareTo(other) == 0);

  @override
  int get hashCode {
    if (raw == BigInt.zero) {
      return 0;
    }
    BigInt v = raw;
    int f = fracBits;
    // Strip trailing binary zeros so equal mathematical values share a hash.
    while (f > 0 && v.isEven) {
      v = v >> 1;
      f--;
    }
    return Object.hash(v, f);
  }

  @override
  String toString() => toDecimalString(16, trimTrailingZeros: true);
}
