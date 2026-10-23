import 'dart:math' as math;
import 'dart:ffi';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:win32/win32.dart';

/// Region excludes transparent pixels at the OS level, including rounded corners.
/// Unlike WS_EX_TRANSPARENT toggling, this still works between processes and does
/// not depend on Dart receiving hover events in the transparent area.
class WindowRegion {
  WindowRegion(this.hwnd);
  final int hwnd;
  List<int>? _last;
  // win32 5.x exposes SetWindowRgn but omits CreateRoundRectRgn.
  static final _createRoundRectRgn = DynamicLibrary.open('gdi32.dll')
      .lookupFunction<
        IntPtr Function(Int32, Int32, Int32, Int32, Int32, Int32),
        int Function(int, int, int, int, int, int)
      >('CreateRoundRectRgn');

  void update(Rect bounds, double radius, double dpr) {
    final values = [
      (bounds.left * dpr).round(),
      (bounds.top * dpr).round(),
      (bounds.right * dpr).round(),
      (bounds.bottom * dpr).round(),
      (radius * 2 * dpr).round(),
    ];
    if (_last != null &&
        List.generate(5, (i) => values[i] == _last![i]).every((v) => v)) {
      return;
    }
    final region = _createRoundRectRgn(
      values[0],
      values[1],
      values[2] + 1,
      values[3] + 1,
      values[4],
      values[4],
    );
    if (region == 0) throw StateError('CreateRoundRectRgn: ${GetLastError()}');
    if (SetWindowRgn(hwnd, region, TRUE) == 0) {
      DeleteObject(region); // On success ownership belongs to Windows.
      throw StateError('SetWindowRgn: ${GetLastError()}');
    }
    _last = values;
  }
}

/// Measured *after* AnimatedContainer layout, so the native region follows the
/// actual interpolated geometry, rather than the animation's destination size.
class RegionTracking extends SingleChildRenderObjectWidget {
  const RegionTracking({super.key, required this.region, required super.child});
  final WindowRegion region;
  @override
  RenderObject createRenderObject(BuildContext context) => RegionRender(region);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant RegionRender renderObject,
  ) {
    renderObject.region = region;
  }
}

class RegionRender extends RenderProxyBox {
  RegionRender(this.region);
  WindowRegion region;
  bool _scheduled = false;

  double _paintedRadius(RenderObject node) {
    if (node is RenderDecoratedBox && node.decoration is BoxDecoration) {
      final decoration = node.decoration as BoxDecoration;
      return decoration.borderRadius?.resolve(TextDirection.ltr).topLeft.x ?? 0;
    }
    double? found;
    node.visitChildren((child) {
      found ??= _paintedRadius(child);
    });
    return found ?? 0;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    if (_scheduled) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!attached || !hasSize) return;
      final dpr = RendererBinding
          .instance
          .platformDispatcher
          .views
          .first
          .devicePixelRatio;
      region.update(
        localToGlobal(Offset.zero) & size,
        math.min(_paintedRadius(this), size.height / 2),
        dpr,
      );
    });
  }
}
