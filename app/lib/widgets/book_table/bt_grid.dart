import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// شبكة الجدول بالدمج الأفقيّ والعموديّ (ADR-057) — `Table` في Flutter لا يدعم الدمج العموديّ.
///
/// 📐 **التخطيط بثلاث مراحل** (كما يفعل Word والطباعة): ارتفاع كل صفٍّ من خلاياه المفردة ⟵ الخلية الممتدّة على صفوف
/// تُضيف ما ينقصها إلى آخر صفوفها ⟵ ثم تُرسم كل خليةٍ بمقاسها النهائيّ فتملأ خلفيتُها مساحتها كاملة.
/// والاتجاه RTL يضع العمود الأوّل يميناً.
class BtGrid extends MultiChildRenderObjectWidget {
  const BtGrid({
    super.key,
    required this.weights,
    required this.rowCount,
    this.rtl = true,
    this.borderWidth = 0.75,
    this.borderColor = const Color(0xFF000000),
    this.minRowHeight = 14,
    required super.children,
  });

  final List<double> weights;
  final int rowCount;
  final bool rtl;
  final double borderWidth;
  final Color borderColor;
  final double minRowHeight;

  @override
  RenderBtGrid createRenderObject(BuildContext context) => RenderBtGrid(
      weights: weights, rowCount: rowCount, rtl: rtl, borderWidth: borderWidth, borderColor: borderColor, minRowHeight: minRowHeight);

  @override
  void updateRenderObject(BuildContext context, RenderBtGrid renderObject) => renderObject
    ..weights = weights
    ..rowCount = rowCount
    ..rtl = rtl
    ..borderWidth = borderWidth
    ..borderColor = borderColor
    ..minRowHeight = minRowHeight;
}

/// موضع الخلية في الشبكة.
class BtGridCell extends ParentDataWidget<BtGridParentData> {
  const BtGridCell({super.key, required this.row, required this.col, this.rowSpan = 1, this.colSpan = 1, required super.child});
  final int row, col, rowSpan, colSpan;

  @override
  void applyParentData(RenderObject renderObject) {
    final pd = renderObject.parentData! as BtGridParentData;
    if (pd.row != row || pd.col != col || pd.rowSpan != rowSpan || pd.colSpan != colSpan) {
      pd
        ..row = row
        ..col = col
        ..rowSpan = rowSpan
        ..colSpan = colSpan;
      renderObject.parent?.markNeedsLayout();
    }
  }

  @override
  Type get debugTypicalAncestorWidgetClass => BtGrid;
}

class BtGridParentData extends ContainerBoxParentData<RenderBox> {
  int row = 0, col = 0, rowSpan = 1, colSpan = 1;
  Rect rect = Rect.zero;
}

class RenderBtGrid extends RenderBox
    with ContainerRenderObjectMixin<RenderBox, BtGridParentData>, RenderBoxContainerDefaultsMixin<RenderBox, BtGridParentData> {
  RenderBtGrid({
    required List<double> weights,
    required int rowCount,
    required bool rtl,
    required double borderWidth,
    required Color borderColor,
    required double minRowHeight,
  }) {
    _weights = weights;
    _rowCount = rowCount;
    _rtl = rtl;
    _borderWidth = borderWidth;
    _borderColor = borderColor;
    _minRowHeight = minRowHeight;
  }

  late List<double> _weights;
  set weights(List<double> v) {
    if (listEquals(v, _weights)) return;
    _weights = v;
    markNeedsLayout();
  }

  late int _rowCount;
  set rowCount(int v) {
    if (v == _rowCount) return;
    _rowCount = v;
    markNeedsLayout();
  }

  late bool _rtl;
  set rtl(bool v) {
    if (v == _rtl) return;
    _rtl = v;
    markNeedsLayout();
  }

  late double _borderWidth;
  set borderWidth(double v) {
    if (v == _borderWidth) return;
    _borderWidth = v;
    markNeedsPaint();
  }

  late Color _borderColor;
  set borderColor(Color v) {
    if (v == _borderColor) return;
    _borderColor = v;
    markNeedsPaint();
  }

  late double _minRowHeight;
  set minRowHeight(double v) {
    if (v == _minRowHeight) return;
    _minRowHeight = v;
    markNeedsLayout();
  }

  /// حدود الصفوف بعد آخر تخطيط — لمؤشّر التحديد في المحرّر (الدفعة ٧).
  List<double> rowEdges = const [];
  List<double> colEdges = const [];

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! BtGridParentData) child.parentData = BtGridParentData();
  }

  ({List<double> colW, List<double> rowH}) _measure(double width, Size Function(RenderBox, BoxConstraints) sizeOf) {
    final total = _weights.fold<double>(0, (a, b) => a + (b > 0 ? b : 0));
    final colW = [for (final w in _weights) total > 0 ? width * (w > 0 ? w : 0) / total : width / math.max(1, _weights.length)];
    final rowH = List<double>.filled(math.max(1, _rowCount), _minRowHeight);
    double spanW(BtGridParentData pd) => colW.skip(pd.col).take(pd.colSpan).fold<double>(0, (a, b) => a + b);

    final multi = <(BtGridParentData, double)>[];
    var child = firstChild;
    while (child != null) {
      final pd = child.parentData! as BtGridParentData;
      if (pd.row < rowH.length && pd.col < colW.length) {
        final h = sizeOf(child, BoxConstraints(minWidth: spanW(pd), maxWidth: spanW(pd))).height;
        if (pd.rowSpan <= 1) {
          rowH[pd.row] = math.max(rowH[pd.row], h);
        } else {
          multi.add((pd, h));
        }
      }
      child = pd.nextSibling;
    }
    // الممتدّة على صفوف: ما ينقصها يُضاف إلى آخر صفوفها
    for (final (pd, need) in multi) {
      final last = math.min(rowH.length - 1, pd.row + pd.rowSpan - 1);
      final have = rowH.sublist(pd.row, last + 1).fold<double>(0, (a, b) => a + b);
      if (need > have) rowH[last] += need - have;
    }
    return (colW: colW, rowH: rowH);
  }

  double _width(BoxConstraints c) => c.hasBoundedWidth ? c.maxWidth : 500;

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final m = _measure(_width(constraints), (child, c) => child.getDryLayout(c));
    return constraints.constrain(Size(_width(constraints), m.rowH.fold<double>(0, (a, b) => a + b)));
  }

  @override
  void performLayout() {
    final width = _width(constraints);
    final m = _measure(width, (child, c) {
      child.layout(c, parentUsesSize: true);
      return child.size;
    });
    final colX = <double>[0];
    for (final w in m.colW) {
      colX.add(colX.last + w);
    }
    final rowY = <double>[0];
    for (final h in m.rowH) {
      rowY.add(rowY.last + h);
    }
    var child = firstChild;
    while (child != null) {
      final pd = child.parentData! as BtGridParentData;
      if (pd.row < m.rowH.length && pd.col < m.colW.length) {
        final lastCol = math.min(m.colW.length, pd.col + pd.colSpan);
        final lastRow = math.min(m.rowH.length, pd.row + pd.rowSpan);
        final w = colX[lastCol] - colX[pd.col];
        final h = rowY[lastRow] - rowY[pd.row];
        child.layout(BoxConstraints.tightFor(width: w, height: h));
        final x = _rtl ? width - colX[lastCol] : colX[pd.col];
        pd
          ..offset = Offset(x, rowY[pd.row])
          ..rect = Rect.fromLTWH(x, rowY[pd.row], w, h);
      } else {
        child.layout(const BoxConstraints.tightFor(width: 0, height: 0));
      }
      child = pd.nextSibling;
    }
    rowEdges = rowY;
    colEdges = _rtl ? [for (final x in colX) width - x] : colX;
    size = constraints.constrain(Size(width, rowY.last));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
    if (_borderWidth <= 0) return;
    final paint = Paint()
      ..color = _borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = _borderWidth;
    var child = firstChild;
    while (child != null) {
      final pd = child.parentData! as BtGridParentData;
      context.canvas.drawRect(pd.rect.shift(offset), paint);
      child = pd.nextSibling;
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
