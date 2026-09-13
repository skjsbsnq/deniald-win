part of 'desktop_widgets.dart';

/// The MD3E expressive-shape family used by desktop/home widgets
/// (02-VISUAL-SPEC.md §6).
///
/// The fork's material library does not ship `RoundedPolygon`/`MaterialShapes`
/// (verified: no `material_shapes.dart` under
/// `flutter/packages/flutter/lib/src/material/`), so every variant is drawn
/// from one parameterized rounded-polygon outline: N anchor vertices placed
/// on the rect's inscribed ellipse, each vertex rounded by a quadratic corner
/// whose cut length is a fraction of the adjacent half-edges. Lobe shapes
/// alternate the vertex radius to pull lobes out and valleys in.
enum DesktopBlobShape {
  /// Four-lobe clover: eight anchors alternating outer/inner radius.
  clover,

  /// Six-lobe scalloped cookie: twelve anchors with shallow valleys.
  cookie,

  /// Soft squircle/puffy diamond: four anchors with near-maximum corner cuts.
  puffy,

  /// Eight-lobe gentle starburst used for accent surfaces.
  softBurst,
}

class _BlobShapeSpec {
  const _BlobShapeSpec({
    required this.vertices,
    required this.phase,
    required this.innerRatio,
    required this.cornerCut,
  });

  /// Anchor count; when [innerRatio] < 1 the anchors alternate outer/inner
  /// radius so `vertices` must be even to close the lobe pattern.
  final int vertices;

  /// Rotation of the first anchor in radians (0 points +x).
  final double phase;

  /// Inner-anchor radius as a fraction of the outer radius. 1.0 keeps every
  /// anchor on the same ellipse (rounded polygon); lower values carve lobes.
  final double innerRatio;

  /// Fraction of each half-edge spent on the corner quadratic, before the
  /// user's corner-radius scale is applied. 0 is a sharp polygon, 1 rounds
  /// the full half-edge.
  final double cornerCut;
}

const Map<DesktopBlobShape, _BlobShapeSpec> _blobSpecs =
    <DesktopBlobShape, _BlobShapeSpec>{
      DesktopBlobShape.clover: _BlobShapeSpec(
        vertices: 8,
        phase: -math.pi / 2,
        innerRatio: 0.60,
        cornerCut: 0.60,
      ),
      DesktopBlobShape.cookie: _BlobShapeSpec(
        vertices: 12,
        phase: -math.pi / 2,
        innerRatio: 0.88,
        cornerCut: 0.55,
      ),
      DesktopBlobShape.puffy: _BlobShapeSpec(
        vertices: 4,
        phase: math.pi / 4,
        innerRatio: 1.0,
        cornerCut: 0.82,
      ),
      DesktopBlobShape.softBurst: _BlobShapeSpec(
        vertices: 16,
        phase: -math.pi / 2,
        innerRatio: 0.93,
        cornerCut: 0.48,
      ),
    };

/// Deterministic blob outline shared by the widget containers and tests.
///
/// The same arguments always produce bit-identical paths: anchors are placed
/// from fixed trig samples and the corner cut is a pure function of the edge
/// lengths, so golden tests and `computeMetrics` comparisons are stable.
abstract final class DesktopBlobPath {
  static Path build(
    DesktopBlobShape shape,
    Rect rect, {
    double roundnessScale = 1.0,
  }) {
    final spec = _blobSpecs[shape]!;
    if (rect.isEmpty) {
      return Path();
    }
    final center = rect.center;
    final rx = rect.width / 2;
    final ry = rect.height / 2;

    final anchors = <Offset>[
      for (var i = 0; i < spec.vertices; i += 1)
        _anchorAt(center, rx, ry, spec, i),
    ];

    final cut = (spec.cornerCut * roundnessScale).clamp(0.0, 1.0).toDouble();
    final path = Path();
    for (var i = 0; i < anchors.length; i += 1) {
      final current = anchors[i];
      final previous = anchors[(i - 1 + anchors.length) % anchors.length];
      final next = anchors[(i + 1) % anchors.length];

      final incoming = _cutPoint(
        from: current,
        toward: previous,
        cut: cut,
      );
      if (i == 0) {
        path.moveTo(incoming.dx, incoming.dy);
      } else {
        path.lineTo(incoming.dx, incoming.dy);
      }
      if (cut > 0) {
        final outgoing = _cutPoint(from: current, toward: next, cut: cut);
        path.quadraticBezierTo(
          current.dx,
          current.dy,
          outgoing.dx,
          outgoing.dy,
        );
      }
    }
    path.close();
    return path;
  }

  static Offset _anchorAt(
    Offset center,
    double rx,
    double ry,
    _BlobShapeSpec spec,
    int index,
  ) {
    final angle = spec.phase + (2 * math.pi * index) / spec.vertices;
    final radiusScale = index.isEven ? 1.0 : spec.innerRatio;
    return Offset(
      center.dx + math.cos(angle) * rx * radiusScale,
      center.dy + math.sin(angle) * ry * radiusScale,
    );
  }

  /// The point where vertex [from]'s corner cut meets the edge toward
  /// [toward]. The cut never exceeds half the edge so adjacent corners
  /// cannot overlap.
  static Offset _cutPoint({
    required Offset from,
    required Offset toward,
    required double cut,
  }) {
    final edge = toward - from;
    final length = edge.distance;
    if (length <= 0 || cut <= 0) {
      return from;
    }
    // The corner consumes `cut` of this vertex's half-edge; neighbouring
    // vertices apply the same rule from their side, so cuts never overlap.
    final travel = (length / 2) * cut;
    return from + (edge / length) * travel;
  }
}

/// A [ShapeBorder] that outlines any rect as one of the
/// [DesktopBlobShape] expressive blobs.
///
/// [roundnessScale] carries `ShellThemeData.cornerRadiusScale` into the
/// corner cuts so the user's roundness setting stays live on non-rectangular
/// shapes too (§D4); at zero the shape degrades to its polygon silhouette.
class BlobShapeBorder extends ShapeBorder {
  const BlobShapeBorder({required this.shape, this.roundnessScale = 1.0});

  final DesktopBlobShape shape;

  /// Multiplier on each variant's corner cut, normally
  /// `ShellThemeData.cornerRadiusScale`.
  final double roundnessScale;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return getOuterPath(rect, textDirection: textDirection);
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    return DesktopBlobPath.build(
      shape,
      rect,
      roundnessScale: roundnessScale,
    );
  }

  @override
  ShapeBorder scale(double t) {
    return BlobShapeBorder(shape: shape, roundnessScale: roundnessScale * t);
  }

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) {
    // Discrete morph targets (shape id is not continuously interpolable):
    // snap at the midpoint instead of blending unrelated outlines.
    return t < 0.5 ? a : this;
  }

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) {
    return t < 0.5 ? this : b;
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}

  @override
  bool operator ==(Object other) {
    return other is BlobShapeBorder &&
        other.shape == shape &&
        other.roundnessScale == roundnessScale;
  }

  @override
  int get hashCode => Object.hash(shape, roundnessScale);
}
