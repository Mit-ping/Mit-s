import 'package:flutter/material.dart';
import 'package:hiddify/features/one_tap/mit_connection_controls.dart';

/// Decorative only. Successful core status, never a tap or timer, reveals the art.
class MitConnectionBackdrop extends StatefulWidget {
  const MitConnectionBackdrop({super.key, required this.connected});

  final bool connected;

  @override
  State<MitConnectionBackdrop> createState() => _MitConnectionBackdropState();
}

class _MitConnectionBackdropState extends State<MitConnectionBackdrop> with SingleTickerProviderStateMixin {
  late final _rain = AnimationController(vsync: this, duration: const Duration(seconds: 18));
  late final _painter = _MatrixPainter(_rain);

  void _updateRain() {
    final animate = !widget.connected && !MediaQuery.disableAnimationsOf(context) && TickerMode.of(context);
    if (animate && !_rain.isAnimating) {
      _rain.repeat();
    } else if (!animate) {
      _rain.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateRain();
  }

  @override
  void didUpdateWidget(MitConnectionBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateRain();
  }

  @override
  void dispose() {
    _rain.dispose();
    _painter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ExcludeSemantics(
        child: Stack(fit: StackFit.expand, children: [
          const ColoredBox(color: mitBackground),
          RepaintBoundary(child: CustomPaint(painter: _painter)),
          AnimatedOpacity(
            key: const ValueKey('mit-connected-artwork'),
            opacity: widget.connected ? 1 : 0,
            duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : mitConnectionTransition,
            curve: Curves.easeInOutCubic,
            child: Image.asset('assets/images/mit_vpn_background.png', fit: BoxFit.cover, alignment: Alignment.topCenter),
          ),
          const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0x33000000), Color(0x22000000), Color(0xDD030805), mitBackground],
            stops: [0, .38, .74, 1],
          ))),
        ]),
      ),
    );
  }
}

/// Cached columns keep the rain local to a repaint boundary, without rebuilding UI.
class _MatrixPainter extends CustomPainter {
  _MatrixPainter(this.phase) : super(repaint: phase) {
    const glyphs = '01010123456789ABCDEF';
    for (var column = 0; column < 24; column++) {
      final length = 14 + column % 9;
      final text = TextPainter(
        text: TextSpan(children: [
          for (var row = 0; row < length; row++)
            TextSpan(
              text: '${glyphs[(column * 7 + row * 11) % glyphs.length]}\n',
              style: TextStyle(color: const Color(0xFF35FF62).withValues(alpha: .04 + .23 * row / length)),
            ),
        ], style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.25)),
        textDirection: TextDirection.ltr,
      )..layout();
      _columns.add(text);
    }
  }

  final Animation<double> phase;
  final _columns = <TextPainter>[];

  void dispose() {
    for (final column in _columns) {
      column.dispose();
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final dots = Paint()..color = const Color(0xFF35FF62).withValues(alpha: .10);
    for (var x = 10.0; x < size.width; x += 18) {
      for (var y = 8.0; y < size.height; y += 18) {
        canvas.drawCircle(Offset(x, y), .65, dots);
      }
    }
    for (var i = 0; i < _columns.length; i++) {
      final text = _columns[i];
      final travel = size.height + text.height;
      final y = ((phase.value + i * .137) % 1) * travel - text.height;
      final x = i * size.width / _columns.length;
      text.paint(canvas, Offset(x, y));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MatrixPainter oldDelegate) => oldDelegate.phase != phase;
}
