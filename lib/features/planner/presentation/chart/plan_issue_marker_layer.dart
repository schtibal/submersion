import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:submersion/core/utils/unit_formatter.dart';
import 'package:submersion/features/planner/domain/services/plan_issue_grouping.dart';
import 'package:submersion/features/planner/domain/services/plan_issue_markers.dart';
import 'package:submersion/features/planner/presentation/chart/plan_chart_geometry.dart';
import 'package:submersion/features/planner/presentation/chart/plan_chart_palette.dart';
import 'package:submersion/features/planner/presentation/widgets/plan_issue_text.dart';
import 'package:submersion/features/planner/presentation/widgets/plan_status_chips.dart';
import 'package:submersion/l10n/l10n_extension.dart';

/// A warning marker where the chart draws it (#3738): [anchor] is the point
/// on the profile line where the warnings start, [glyph] the small warning
/// sign drawn just above it (below it when the anchor is too close to the
/// top of the plot).
class PlacedIssueMarker {
  const PlacedIssueMarker({
    required this.marker,
    required this.depthMeters,
    required this.anchor,
    required this.glyph,
  });

  final PlanIssueMarker marker;
  final double depthMeters;
  final Offset anchor;
  final Rect glyph;
}

/// Width and height of a marker's warning sign, in logical pixels.
const issueMarkerGlyphSize = Size(14, 12);

/// Gap between the profile line and the warning sign, so the sign never
/// covers the line it points at.
const _glyphGap = 5.0;

/// Places [markers] on the profile [depthAt] describes. Markers whose
/// anchors land closer than [mergeDistance] pixels share one, so warnings
/// that start at nearly the same point never pile up at the current zoom.
List<PlacedIssueMarker> placeIssueMarkers({
  required List<PlanIssueMarker> markers,
  required PlanChartGeometry geometry,
  required double Function(double timeSeconds) depthAt,
  double mergeDistance = 16,
}) {
  final plot = geometry.plotRect;
  final merged = <(PlanIssueMarker, double, Offset)>[];
  for (final marker in markers) {
    final depth = depthAt(marker.runtimeSeconds.toDouble());
    final anchor = geometry.toPixel(marker.runtimeSeconds.toDouble(), depth);
    if (merged.isNotEmpty &&
        (merged.last.$3 - anchor).distance < mergeDistance) {
      final (previous, previousDepth, previousAnchor) = merged.removeLast();
      merged.add((
        PlanIssueMarker(
          runtimeSeconds: previous.runtimeSeconds,
          groups: [...previous.groups, ...marker.groups]
            ..sort(
              (a, b) =>
                  b.issue.severity.index.compareTo(a.issue.severity.index),
            ),
        ),
        previousDepth,
        previousAnchor,
      ));
      continue;
    }
    merged.add((marker, depth, anchor));
  }

  const size = issueMarkerGlyphSize;
  return [
    for (final (marker, depth, anchor) in merged)
      () {
        final above = anchor.dy - _glyphGap - size.height;
        final top = above >= plot.top ? above : anchor.dy + _glyphGap;
        final left = (anchor.dx - size.width / 2)
            .clamp(plot.left, math.max(plot.left, plot.right - size.width))
            .toDouble();
        return PlacedIssueMarker(
          marker: marker,
          depthMeters: depth,
          anchor: anchor,
          glyph: Rect.fromLTWH(left, top, size.width, size.height),
        );
      }(),
  ];
}

/// The marker under [position], or null. [radius] widens the target past
/// the small sign, to the 48 px minimum a fingertip needs on touch.
int? hitTestIssueMarker(
  List<PlacedIssueMarker> placed,
  Offset position, {
  double radius = 16,
}) {
  int? best;
  var bestDistance = radius;
  for (var i = 0; i < placed.length; i++) {
    final distance = (placed[i].glyph.center - position).distance;
    if (distance <= bestDistance) {
      best = i;
      bestDistance = distance;
    }
  }
  return best;
}

/// Draws the warning markers over the chart, gives each one to screen
/// readers, and shows the warnings of the [activeIndex] marker in a small
/// card beside it. It takes no pointer input itself: the chart's own
/// pointer handling hit-tests the markers, so a tap on one never also
/// selects a segment or adds a waypoint.
class PlanIssueMarkerLayer extends StatelessWidget {
  const PlanIssueMarkerLayer({
    super.key,
    required this.placed,
    required this.highlighted,
    required this.activeIndex,
    required this.palette,
    required this.units,
    required this.onActivate,
  });

  final List<PlacedIssueMarker> placed;
  final Set<PlanIssueKey> highlighted;
  final int? activeIndex;
  final PlanChartPalette palette;
  final UnitFormatter units;

  /// Called when a screen reader activates the marker at this index.
  final ValueChanged<int> onActivate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = activeIndex;
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            key: const Key('planChartIssueMarkers'),
            painter: PlanIssueMarkerPainter(
              placed: placed,
              colors: [
                for (final p in placed)
                  planIssueSeverityColor(scheme, p.marker.severity),
              ],
              highlighted: [
                for (final p in placed) p.marker.keys.any(highlighted.contains),
              ],
              outline: palette.backdrop,
            ),
          ),
        ),
        for (var i = 0; i < placed.length; i++)
          Positioned.fromRect(
            rect: placed[i].glyph.inflate(8),
            child: Semantics(
              button: true,
              label: _semanticsLabel(context, placed[i]),
              onTap: () => onActivate(i),
              child: const SizedBox.expand(),
            ),
          ),
        if (active != null && active < placed.length)
          Positioned.fill(
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: CustomSingleChildLayout(
                  delegate: _PopupLayout(placed[active].glyph),
                  child: _IssuePopup(
                    key: const Key('planChartIssuePopup'),
                    placed: placed[active],
                    palette: palette,
                    units: units,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _semanticsLabel(BuildContext context, PlacedIssueMarker placed) => [
    _positionText(context, placed, units),
    for (final group in placed.marker.groups) _groupText(context, group, units),
  ].join('\n');
}

String _positionText(
  BuildContext context,
  PlacedIssueMarker placed,
  UnitFormatter units,
) => context.l10n.plannerCanvas_scrub_readout(
  (placed.marker.runtimeSeconds / 60).round().toString(),
  units.formatDepth(placed.depthMeters, decimals: 0),
);

/// A row's text exactly as the warnings list prints it.
String _groupText(
  BuildContext context,
  GroupedPlanIssue group,
  UnitFormatter units,
) {
  final message = planIssueMessage(context, group.issue, units);
  return group.count > 1
      ? context.l10n.plannerCanvas_issue_repeated(message, group.count)
      : message;
}

/// Each marker as a small warning sign in its severity's colour, outlined
/// in the chart backdrop so it reads over the profile, the fill and the
/// ceiling band, with a dot on the line where the warnings start. A
/// highlighted marker gets a ring.
class PlanIssueMarkerPainter extends CustomPainter {
  const PlanIssueMarkerPainter({
    required this.placed,
    required this.colors,
    required this.highlighted,
    required this.outline,
  });

  final List<PlacedIssueMarker> placed;
  final List<Color> colors;
  final List<bool> highlighted;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final outlinePaint = Paint()
      ..color = outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeJoin = StrokeJoin.round;
    for (var i = 0; i < placed.length; i++) {
      final marker = placed[i];
      final color = colors[i];
      final fill = Paint()..color = color;

      canvas.drawCircle(marker.anchor, 2.5, fill);
      canvas.drawCircle(marker.anchor, 2.5, outlinePaint);

      final glyph = marker.glyph;
      final sign = Path()
        ..moveTo(glyph.center.dx, glyph.top)
        ..lineTo(glyph.right, glyph.bottom)
        ..lineTo(glyph.left, glyph.bottom)
        ..close();
      canvas.drawPath(sign, fill);
      canvas.drawPath(sign, outlinePaint);

      // The exclamation mark, in the outline colour so it contrasts with
      // the sign in both themes.
      final mark = Paint()
        ..color = outline
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(glyph.center.dx, glyph.top + 4),
        Offset(glyph.center.dx, glyph.bottom - 4.5),
        mark,
      );
      canvas.drawCircle(Offset(glyph.center.dx, glyph.bottom - 2.2), 0.9, mark);

      if (highlighted[i]) {
        canvas.drawCircle(
          glyph.center,
          glyph.longestSide / 2 + 5,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }
  }

  @override
  bool shouldRepaint(PlanIssueMarkerPainter oldDelegate) =>
      outline != oldDelegate.outline ||
      !listEquals(colors, oldDelegate.colors) ||
      !listEquals(highlighted, oldDelegate.highlighted) ||
      !listEquals(
        [for (final p in placed) p.glyph],
        [for (final p in oldDelegate.placed) p.glyph],
      );
}

/// Puts the warnings card beside its marker: to the right when it fits,
/// else to the left, vertically centred on the sign and kept inside the
/// chart.
class _PopupLayout extends SingleChildLayoutDelegate {
  const _PopupLayout(this.glyph);

  final Rect glyph;

  static const _margin = 4.0;
  static const _gap = 8.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        maxWidth: math.min(260, constraints.maxWidth - 2 * _margin),
        maxHeight: constraints.maxHeight - 2 * _margin,
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    var x = glyph.right + _gap;
    if (x + childSize.width > size.width - _margin) {
      x = glyph.left - _gap - childSize.width;
    }
    final y = glyph.center.dy - childSize.height / 2;
    return Offset(
      x.clamp(_margin, math.max(_margin, size.width - childSize.width)),
      y.clamp(_margin, math.max(_margin, size.height - childSize.height)),
    );
  }

  @override
  bool shouldRelayout(_PopupLayout oldDelegate) => glyph != oldDelegate.glyph;
}

class _IssuePopup extends StatelessWidget {
  const _IssuePopup({
    super.key,
    required this.placed,
    required this.palette,
    required this.units,
  });

  final PlacedIssueMarker placed;
  final PlanChartPalette palette;
  final UnitFormatter units;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: palette.readoutBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.readoutBorder),
      ),
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _positionText(context, placed, units),
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: palette.readoutText,
              ),
            ),
            for (final group in placed.marker.groups)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      planIssueIcon(group.issue.severity),
                      size: 16,
                      color: planIssueSeverityColor(
                        theme.colorScheme,
                        group.issue.severity,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        _groupText(context, group, units),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: palette.readoutText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
