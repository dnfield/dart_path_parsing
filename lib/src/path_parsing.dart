// This code has been 'translated' largely from the Chromium/blink source
// for SVG path parsing.
// The following files can be cross referenced to the classes and methods here:
//   * https://github.com/chromium/chromium/blob/master/third_party/blink/renderer/core/svg/svg_parser_utilities.cc
//   * https://github.com/chromium/chromium/blob/master/third_party/blink/renderer/core/svg/svg_parser_utilities.h
//   * https://github.com/chromium/chromium/blob/master/third_party/blink/renderer/core/svg/svg_path_string_source.cc
//   * https://github.com/chromium/chromium/blob/master/third_party/blink/renderer/core/svg/svg_path_string_source.h
//   * https://github.com/chromium/chromium/blob/master/third_party/blink/renderer/core/svg/svg_path_parser.cc
//   * https://github.com/chromium/chromium/blob/master/third_party/blink/renderer/core/svg/svg_path_parser.h
//   * https://github.com/chromium/chromium/blob/master/third_party/blink/renderer/core/html/parser/html_parser_idioms.h (IsHTMLSpace)
//   * https://github.com/chromium/chromium/blob/master/third_party/blink/renderer/core/svg/svg_path_parser_test.cc

import 'dart:math' as math show sqrt, max, pi, tan, sin, cos, pow, atan2;
import 'dart:typed_data';

import 'path_segment_type.dart';

/// Parse `svg`, emitting the segment data to `path`.
void writeSvgPathDataToPath(String? svg, PathProxy path) {
  if (svg == null || svg == '') {
    return;
  }

  final SvgPathStringSource parser = SvgPathStringSource(svg);
  final SvgPathNormalizer normalizer = SvgPathNormalizer();
  for (PathSegmentData seg in parser.parseSegments()) {
    normalizer.emitSegment(seg, path);
  }
}

/// A receiver for normalized [PathSegmentData].
abstract class PathProxy {
  void moveTo(double x, double y);
  void lineTo(double x, double y);
  void cubicTo(
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
  );
  void arcToPoint(
    double x1,
    double y1,
    double r1,
    double r2,
    double angle,
    bool largeArc,
    bool clockwise,
  );
  void close();
}

const double _twoPiFloat = math.pi * 2.0;
const double _piOverTwoFloat = math.pi / 2.0;
final Float64x2 _one = Float64x2.splat(1);
final Float64x2 _oneOverThree = Float64x2.splat(1.0 / 3.0);
final Float64x2 _two = Float64x2.splat(2);
final Float64x2 _pointFive = Float64x2.splat(.5);

extension Float64x2Extension on Float64x2 {
  double get direction {
    return math.atan2(y, x);
  }

  Float64x2 reciprocal() {
    return _one / this;
  }
}

class SvgPathStringSource {
  SvgPathStringSource(this._string)
      : assert(_string != null), // ignore: unnecessary_null_comparison
        _previousCommand = SvgPathSegType.unknown,
        _idx = 0,
        _length = _string.length {
    _skipOptionalSvgSpaces();
  }

  final String _string;

  SvgPathSegType _previousCommand;
  int _idx;
  final int _length;

  bool _isHtmlSpace(int character) {
    // Histogram from Apple's page load test combined with some ad hoc browsing
    // some other test suites.
    //
    //     82%: 216330 non-space characters, all > U+0020
    //     11%:  30017 plain space characters, U+0020
    //      5%:  12099 newline characters, U+000A
    //      2%:   5346 tab characters, U+0009
    //
    // No other characters seen. No U+000C or U+000D, and no other control
    // characters. Accordingly, we check for non-spaces first, then space, then
    // newline, then tab, then the other characters.

    return character <= AsciiConstants.space &&
        (character == AsciiConstants.space ||
            character == AsciiConstants.slashN ||
            character == AsciiConstants.slashT ||
            character == AsciiConstants.slashR ||
            character == AsciiConstants.slashF);
  }

  /// Increments _idx to the first non-space character.
  ///
  /// Returns the code unit of the first non-space, or -1 if at end of string.
  int _skipOptionalSvgSpaces() {
    while (true) {
      if (_idx >= _length) {
        return -1;
      }

      final int c = _string.codeUnitAt(_idx);
      if (!_isHtmlSpace(c)) {
        return c;
      }

      _idx++;
    }
  }

  void _skipOptionalSvgSpacesOrDelimiter(
      [int delimiter = AsciiConstants.comma]) {
    final int c = _skipOptionalSvgSpaces();
    if (c == delimiter) {
      _idx++;
      _skipOptionalSvgSpaces();
    }
  }

  static bool _isNumberStart(int lookahead) {
    return (lookahead >= AsciiConstants.number0 &&
            lookahead <= AsciiConstants.number9) ||
        lookahead == AsciiConstants.plus ||
        lookahead == AsciiConstants.minus ||
        lookahead == AsciiConstants.period;
  }

  SvgPathSegType _maybeImplicitCommand(
    int lookahead,
    SvgPathSegType nextCommand,
  ) {
    // Check if the current lookahead may start a number - in which case it
    // could be the start of an implicit command. The 'close' command does not
    // have any parameters though and hence can't have an implicit
    // 'continuation'.
    if (!_isNumberStart(lookahead) || _previousCommand == SvgPathSegType.close)
      return nextCommand;
    // Implicit continuations of moveto command translate to linetos.
    if (_previousCommand == SvgPathSegType.moveToAbs) {
      return SvgPathSegType.lineToAbs;
    }
    if (_previousCommand == SvgPathSegType.moveToRel) {
      return SvgPathSegType.lineToRel;
    }
    return _previousCommand;
  }

  bool _isValidRange(double x) =>
      -double.maxFinite <= x && x <= double.maxFinite;

  bool _isValidExponent(double x) => -37 <= x && x <= 38;

  /// Reads a code unit and advances the index.
  ///
  /// Must not be called at end of string.
  int _readCodeUnit() {
    // assert(_idx >= _length);
    if (_idx >= _length) {
      return -1;
    }
    return _string.codeUnitAt(_idx++);
  }

  // We use this generic parseNumber function to allow the Path parsing code to
  // work at a higher precision internally, without any unnecessary runtime cost
  // or code complexity.
  double _parseNumber() {
    _skipOptionalSvgSpaces();

    // Read the sign.
    int sign = 1;
    int c = _readCodeUnit();
    if (c == AsciiConstants.plus) {
      c = _readCodeUnit();
    } else if (c == AsciiConstants.minus) {
      sign = -1;
      c = _readCodeUnit();
    }

    if ((c < AsciiConstants.number0 || c > AsciiConstants.number9) &&
        c != AsciiConstants.period) {
      throw StateError('First character of a number must be one of [0-9+-.].');
    }

    // Read the integer part, build left-to-right.
    double integer = 0.0;
    while (AsciiConstants.number0 <= c && c <= AsciiConstants.number9) {
      integer = integer * 10 + (c - AsciiConstants.number0);
      c = _readCodeUnit();
    }

    // Bail out early if this overflows.
    if (!_isValidRange(integer)) {
      throw StateError('Numeric overflow');
    }

    double decimal = 0.0;
    if (c == AsciiConstants.period) {
      // read the decimals
      c = _readCodeUnit();

      // There must be a least one digit following the .
      if (c < AsciiConstants.number0 || c > AsciiConstants.number9)
        throw StateError('There must be at least one digit following the .');

      double frac = 1.0;
      while (AsciiConstants.number0 <= c && c <= AsciiConstants.number9) {
        frac *= 0.1;
        decimal += (c - AsciiConstants.number0) * frac;
        c = _readCodeUnit();
      }
    }

    double number = integer + decimal;
    number *= sign;

    // read the exponent part
    if (_idx < _length &&
        (c == AsciiConstants.lowerE || c == AsciiConstants.upperE) &&
        (_string.codeUnitAt(_idx) != AsciiConstants.lowerX &&
            _string.codeUnitAt(_idx) != AsciiConstants.lowerM)) {
      c = _readCodeUnit();

      // read the sign of the exponent
      bool exponentIsNegative = false;
      if (c == AsciiConstants.plus) {
        c = _readCodeUnit();
      } else if (c == AsciiConstants.minus) {
        c = _readCodeUnit();
        exponentIsNegative = true;
      }

      // There must be an exponent
      if (c < AsciiConstants.number0 || c > AsciiConstants.number9)
        throw StateError('Missing exponent');

      double exponent = 0.0;
      while (c >= AsciiConstants.number0 && c <= AsciiConstants.number9) {
        exponent *= 10.0;
        exponent += c - AsciiConstants.number0;
        c = _readCodeUnit();
      }
      if (exponentIsNegative) {
        exponent = -exponent;
      }
      // Make sure exponent is valid.
      if (!_isValidExponent(exponent)) {
        throw StateError('Invalid exponent $exponent');
      }
      if (exponent != 0) {
        number *= math.pow(10.0, exponent);
      }
    }

    // Don't return Infinity() or NaN().
    if (!_isValidRange(number)) {
      throw StateError('Numeric overflow');
    }

    // At this stage, c contains an unprocessed character, and _idx has
    // already been incremented.

    // If c == -1, the input was already at the end of the string, so no
    // further processing needs to occur.
    if (c != -1) {
      --_idx; // Put the unprocessed character back.

      // if (mode & kAllowTrailingWhitespace)
      _skipOptionalSvgSpacesOrDelimiter();
    }
    return number;
  }

  bool _parseArcFlag() {
    if (!hasMoreData) {
      throw StateError('Expected more data');
    }
    final int flagChar = _string.codeUnitAt(_idx++);
    _skipOptionalSvgSpacesOrDelimiter();

    if (flagChar == AsciiConstants.number0)
      return false;
    else if (flagChar == AsciiConstants.number1)
      return true;
    else
      throw StateError('Invalid flag value');
  }

  bool get hasMoreData => _idx < _length;

  // Iterable<PathSegmentData> parseSegments() sync* {
  List<PathSegmentData> parseSegments() {
    final List<PathSegmentData> data = <PathSegmentData>[];
    while (hasMoreData) {
      data.add(parseSegment());
    }
    return data;
  }

  PathSegmentData parseSegment() {
    assert(hasMoreData);
    final PathSegmentData segment = PathSegmentData();
    final int lookahead = _string.codeUnitAt(_idx);
    SvgPathSegType command = AsciiConstants.mapLetterToSegmentType(lookahead);
    if (_previousCommand == SvgPathSegType.unknown) {
      // First command has to be a moveto.
      if (command != SvgPathSegType.moveToRel &&
          command != SvgPathSegType.moveToAbs) {
        throw StateError('Expected to find moveTo command');
      }
      // Consume command letter.
      _idx++;
    } else if (command == SvgPathSegType.unknown) {
      // Possibly an implicit command.
      assert(_previousCommand != SvgPathSegType.unknown);
      command = _maybeImplicitCommand(lookahead, command);
      if (command == SvgPathSegType.unknown) {
        throw StateError('Expected a path command');
      }
    } else {
      // Valid explicit command.
      _idx++;
    }

    segment.command = _previousCommand = command;

    switch (segment.command) {
      case SvgPathSegType.cubicToRel:
      case SvgPathSegType.cubicToAbs:
        segment.point1 = Float64x2(_parseNumber(), _parseNumber());
        continue cubic_smooth;
      case SvgPathSegType.smoothCubicToRel:
      cubic_smooth:
      case SvgPathSegType.smoothCubicToAbs:
        segment.point2 = Float64x2(_parseNumber(), _parseNumber());
        continue quad_smooth;
      case SvgPathSegType.moveToRel:
      case SvgPathSegType.moveToAbs:
      case SvgPathSegType.lineToRel:
      case SvgPathSegType.lineToAbs:
      case SvgPathSegType.smoothQuadToRel:
      quad_smooth:
      case SvgPathSegType.smoothQuadToAbs:
        segment.targetPoint = Float64x2(_parseNumber(), _parseNumber());
        break;
      case SvgPathSegType.lineToHorizontalRel:
      case SvgPathSegType.lineToHorizontalAbs:
        segment.targetPoint = Float64x2(_parseNumber(), segment.targetPoint.y);
        break;
      case SvgPathSegType.lineToVerticalRel:
      case SvgPathSegType.lineToVerticalAbs:
        segment.targetPoint = Float64x2(segment.targetPoint.x, _parseNumber());
        break;
      case SvgPathSegType.close:
        _skipOptionalSvgSpaces();
        break;
      case SvgPathSegType.quadToRel:
      case SvgPathSegType.quadToAbs:
        segment.point1 = Float64x2(_parseNumber(), _parseNumber());
        segment.targetPoint = Float64x2(_parseNumber(), _parseNumber());
        break;
      case SvgPathSegType.arcToRel:
      case SvgPathSegType.arcToAbs:
        segment.point1 = Float64x2(_parseNumber(), _parseNumber());
        segment.arcAngle = _parseNumber();
        segment.arcLarge = _parseArcFlag();
        segment.arcSweep = _parseArcFlag();
        segment.targetPoint = Float64x2(_parseNumber(), _parseNumber());
        break;
      case SvgPathSegType.unknown:
        throw StateError('Unknown segment command');
    }

    return segment;
  }
}

Float64x2 reflectedPoint(Float64x2 reflectedIn, Float64x2 pointToReflect) {
  return _two * reflectedIn - pointToReflect;
}

/// Blend the points with a ratio (1/3):(2/3).
Float64x2 blendPoints(Float64x2 p1, Float64x2 p2) {
  return (p1 + _two * p2) * _oneOverThree;
}

bool isCubicCommand(SvgPathSegType command) {
  return command == SvgPathSegType.cubicToAbs ||
      command == SvgPathSegType.cubicToRel ||
      command == SvgPathSegType.smoothCubicToAbs ||
      command == SvgPathSegType.smoothCubicToRel;
}

bool isQuadraticCommand(SvgPathSegType command) {
  return command == SvgPathSegType.quadToAbs ||
      command == SvgPathSegType.quadToRel ||
      command == SvgPathSegType.smoothQuadToAbs ||
      command == SvgPathSegType.smoothQuadToRel;
}

// TODO(dnfield): This can probably be cleaned up a bit.  Some of this was designed in such a way to pack data/optimize for C++
// There are probably better/clearer ways to do it for Dart.
class PathSegmentData {
  PathSegmentData()
      : command = SvgPathSegType.unknown,
        arcSweep = false,
        arcLarge = false;

  Float64x2 get arcRadii => point1;

  double get arcAngle => point2.x;
  set arcAngle(double angle) {
    point2 = Float64x2(angle, point2.y);
  }

  SvgPathSegType command;
  Float64x2 targetPoint = Float64x2.zero();
  Float64x2 point1 = Float64x2.zero();
  Float64x2 point2 = Float64x2.zero();
  bool arcSweep;
  bool arcLarge;

  @override
  String toString() {
    return 'PathSegmentData{$command $targetPoint $point1 $point2 $arcSweep $arcLarge}';
  }
}

class SvgPathNormalizer {
  Float64x2 _currentPoint = Float64x2.zero();
  Float64x2 _subPathPoint = Float64x2.zero();
  Float64x2 _controlPoint = Float64x2.zero();
  SvgPathSegType _lastCommand = SvgPathSegType.unknown;

  void emitSegment(PathSegmentData segment, PathProxy path) {
    final PathSegmentData normSeg = segment;
    assert(_currentPoint != null); // ignore: unnecessary_null_comparison
    // Convert relative points to absolute points.
    switch (segment.command) {
      case SvgPathSegType.quadToRel:
        normSeg.point1 += _currentPoint;
        normSeg.targetPoint += _currentPoint;
        break;
      case SvgPathSegType.cubicToRel:
        normSeg.point1 += _currentPoint;
        continue smooth_rel;
      smooth_rel:
      case SvgPathSegType.smoothCubicToRel:
        normSeg.point2 += _currentPoint;
        continue arc_rel;
      case SvgPathSegType.moveToRel:
      case SvgPathSegType.lineToRel:
      case SvgPathSegType.lineToHorizontalRel:
      case SvgPathSegType.lineToVerticalRel:
      case SvgPathSegType.smoothQuadToRel:
      arc_rel:
      case SvgPathSegType.arcToRel:
        normSeg.targetPoint += _currentPoint;
        break;
      case SvgPathSegType.lineToHorizontalAbs:
        normSeg.targetPoint = Float64x2(normSeg.targetPoint.x, _currentPoint.y);
        break;
      case SvgPathSegType.lineToVerticalAbs:
        normSeg.targetPoint = Float64x2(_currentPoint.x, normSeg.targetPoint.y);
        break;
      case SvgPathSegType.close:
        // Reset m_currentPoint for the next path.
        normSeg.targetPoint = _subPathPoint;
        break;
      default:
        break;
    }

    // Update command verb, handle smooth segments and convert quadratic curve
    // segments to cubics.
    switch (segment.command) {
      case SvgPathSegType.moveToRel:
      case SvgPathSegType.moveToAbs:
        _subPathPoint = normSeg.targetPoint;
        path.moveTo(normSeg.targetPoint.x, normSeg.targetPoint.y);
        break;
      case SvgPathSegType.lineToRel:
      case SvgPathSegType.lineToAbs:
      case SvgPathSegType.lineToHorizontalRel:
      case SvgPathSegType.lineToHorizontalAbs:
      case SvgPathSegType.lineToVerticalRel:
      case SvgPathSegType.lineToVerticalAbs:
        path.lineTo(normSeg.targetPoint.x, normSeg.targetPoint.y);
        break;
      case SvgPathSegType.close:
        path.close();
        break;
      case SvgPathSegType.smoothCubicToRel:
      case SvgPathSegType.smoothCubicToAbs:
        if (!isCubicCommand(_lastCommand)) {
          normSeg.point1 = _currentPoint;
        } else {
          normSeg.point1 = reflectedPoint(
            _currentPoint,
            _controlPoint,
          );
        }
        continue cubic_abs2;
      case SvgPathSegType.cubicToRel:
      cubic_abs2:
      case SvgPathSegType.cubicToAbs:
        _controlPoint = normSeg.point2;
        path.cubicTo(
          normSeg.point1.x,
          normSeg.point1.y,
          normSeg.point2.x,
          normSeg.point2.y,
          normSeg.targetPoint.x,
          normSeg.targetPoint.y,
        );
        break;
      case SvgPathSegType.smoothQuadToRel:
      case SvgPathSegType.smoothQuadToAbs:
        if (!isQuadraticCommand(_lastCommand)) {
          normSeg.point1 = _currentPoint;
        } else {
          normSeg.point1 = reflectedPoint(
            _currentPoint,
            _controlPoint,
          );
        }
        continue quad_abs2;
      case SvgPathSegType.quadToRel:
      quad_abs2:
      case SvgPathSegType.quadToAbs:
        // Save the unmodified control point.
        _controlPoint = normSeg.point1;
        normSeg.point1 = blendPoints(_currentPoint, _controlPoint);
        normSeg.point2 = blendPoints(
          normSeg.targetPoint,
          _controlPoint,
        );
        path.cubicTo(
          normSeg.point1.x,
          normSeg.point1.y,
          normSeg.point2.x,
          normSeg.point2.y,
          normSeg.targetPoint.x,
          normSeg.targetPoint.y,
        );
        break;
      case SvgPathSegType.arcToRel:
      case SvgPathSegType.arcToAbs:
        path.arcToPoint(
          normSeg.targetPoint.x,
          normSeg.targetPoint.y,
          normSeg.arcRadii.x,
          normSeg.arcRadii.y,
          normSeg.arcAngle,
          normSeg.arcLarge,
          normSeg.arcSweep,
        );
        break;
      default:
        throw StateError('Invalid command type in path');
    }

    _currentPoint = normSeg.targetPoint;

    if (!isCubicCommand(segment.command) &&
        !isQuadraticCommand(segment.command)) {
      _controlPoint = _currentPoint;
    }

    _lastCommand = segment.command;
  }

// This works by converting the SVG arc to 'simple' beziers.
// Partly adapted from Niko's code in kdelibs/kdecore/svgicons.
// See also SVG implementation notes:
// http://www.w3.org/TR/SVG/implnote.html#ArcConversionEndpointToCenter
  bool _decomposeArcToCubic(
    Float64x2 currentPoint,
    PathSegmentData arcSegment,
    PathProxy path,
  ) {
    // If rx = 0 or ry = 0 then this arc is treated as a straight line segment (a
    // 'lineto') joining the endpoints.
    // http://www.w3.org/TR/SVG/implnote.html#ArcOutOfRangeParameters
    Float64x2 absArc = arcSegment.arcRadii.abs();
    if (absArc.x == 0 || absArc.y == 0) {
      return false;
    }

    // If the current point and target point for the arc are identical, it should
    // be treated as a zero length path. This ensures continuity in animations.
    if (arcSegment.targetPoint == currentPoint) {
      return false;
    }

    final double angle = arcSegment.arcAngle;

    final Float64x2 midPointDistance =
        (currentPoint - arcSegment.targetPoint) * _pointFive;

    final _AffineMatrix pointTransform = _AffineMatrix();
    pointTransform.rotate(-angle);

    final Float64x2 transformedMidPoint =
        pointTransform.mapPoint(midPointDistance);

    final Float64x2 squaredArc = absArc * absArc;
    final Float64x2 squaredMidPoint = transformedMidPoint * transformedMidPoint;

    // Check if the radii are big enough to draw the arc, scale radii if not.
    // http://www.w3.org/TR/SVG/implnote.html#ArcCorrectionOutOfRangeRadii
    final Float64x2 scaledPoints = squaredMidPoint / squaredArc;
    final double radiiScale = scaledPoints.x + scaledPoints.y;
    if (radiiScale > 1.0) {
      absArc = absArc * Float64x2.splat(math.sqrt(radiiScale));
    }
    pointTransform.reset();
    pointTransform.scale(absArc.reciprocal());
    pointTransform.rotate(-angle);

    Float64x2 point1 = pointTransform.mapPoint(currentPoint);
    Float64x2 point2 = pointTransform.mapPoint(arcSegment.targetPoint);

    Float64x2 delta = point2 - point1;

    final double d = delta.x * delta.x + delta.y * delta.y;
    final double scaleFactorSquared = math.max(1.0 / d - 0.25, 0.0);
    Float64x2 scaleFactor = Float64x2.splat(math.sqrt(scaleFactorSquared));
    if (!scaleFactor.x.isFinite) {
      scaleFactor = Float64x2.zero();
    }

    if (arcSegment.arcSweep == arcSegment.arcLarge) {
      scaleFactor = -scaleFactor;
    }

    delta = delta * scaleFactor;
    final Float64x2 centerPoint =
        ((point1 + point2) * _pointFive) + Float64x2(-delta.y, delta.x);
    final double theta1 = (point1 - centerPoint).direction;
    final double theta2 = (point2 - centerPoint).direction;
    double thetaArc = theta2 - theta1;

    if (thetaArc < 0.0 && arcSegment.arcSweep) {
      thetaArc += _twoPiFloat;
    } else if (thetaArc > 0.0 && !arcSegment.arcSweep) {
      thetaArc -= _twoPiFloat;
    }
    pointTransform.reset();
    pointTransform.rotate(angle);
    pointTransform.scale(absArc);

    // Some results of atan2 on some platform implementations are not exact
    // enough. So that we get more cubic curves than expected here. Adding 0.001f
    // reduces the count of segments to the correct count.
    final int segments = (thetaArc / (_piOverTwoFloat + 0.001)).abs().ceil();
    for (int i = 0; i < segments; i += 1) {
      final double startTheta = theta1 + i * thetaArc / segments;
      final double endTheta = theta1 + (i + 1) * thetaArc / segments;

      final double t = (8.0 / 6.0) * math.tan(0.25 * (endTheta - startTheta));
      if (!t.isFinite) {
        return false;
      }
      final double sinStartTheta = math.sin(startTheta);
      final double cosStartTheta = math.cos(startTheta);
      final double sinEndTheta = math.sin(endTheta);
      final double cosEndTheta = math.cos(endTheta);

      point1 = Float64x2(cosStartTheta - t * sinStartTheta,
              sinStartTheta + t * cosStartTheta) +
          centerPoint;
      Float64x2 targetPoint = Float64x2(cosEndTheta, sinEndTheta) + centerPoint;
      point2 = targetPoint + Float64x2(t * sinEndTheta, -t * cosEndTheta);

      point1 = pointTransform.mapPoint(point1);
      point2 = pointTransform.mapPoint(point2);
      targetPoint = pointTransform.mapPoint(targetPoint);

      path.cubicTo(
        point1.x,
        point1.y,
        point2.x,
        point2.y,
        targetPoint.x,
        targetPoint.y,
      );
    }
    return true;
  }
}

class _AffineMatrix {
  _AffineMatrix() : _abde = Float32x4(1, 0, 0, 1);

  late Float32x4 _abde;

  bool _isIdentity = true;

  double get a => _abde.x;
  double get b => _abde.y;
  // double get c => 0;
  double get d => _abde.z;
  double get e => _abde.w;
  // double get f => 0;

  void reset() {
    _abde = Float32x4(1, 0, 0, 1);
    _isIdentity = true;
  }

  void rotate(double angle) {
    if (angle == 0) {
      return;
    }
    final double cosAngle = math.cos(angle);
    final double sinAngle = math.sin(angle);
    _abde = _abde * Float32x4(cosAngle, -sinAngle, sinAngle, cosAngle);
    _isIdentity = false;
  }

  void scale(Float64x2 xy) {
    if (xy == Float64x2.splat(1)) {
      return;
    }
    _abde = _abde * Float32x4(xy.x, 1, 1, xy.y);
    _isIdentity = false;
  }

  Float64x2 mapPoint(Float64x2 point) {
    if (_isIdentity) {
      return point;
    }
    return Float64x2(
      a * point.x + b * point.y,
      d * point.x + e * point.y,
    );
  }

  @override
  String toString() {
    return '''
[ $a, $b, 0.0 ]
[ $d, $e, 0.0 ]
[ 0.0, 0.0, 1.0 ]
''';
  }
}
