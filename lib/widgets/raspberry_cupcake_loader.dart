import 'dart:math' as math;

import 'package:flutter/material.dart';

class RaspberryCupcakeLoader extends StatefulWidget {
  const RaspberryCupcakeLoader({
    super.key,
    this.fullScreen = false,
    this.message = 'Preparing something sweet...',
  });

  final bool fullScreen;
  final String message;

  @override
  State<RaspberryCupcakeLoader> createState() => _RaspberryCupcakeLoaderState();
}

class _RaspberryCupcakeLoaderState extends State<RaspberryCupcakeLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Transform.translate(
            offset: Offset(0, -5 * math.sin(_controller.value * math.pi)),
            child: CustomPaint(
              size: const Size(142, 142),
              painter: _CupcakePainter(_controller.value),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Angelz Bites Cupcakes',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF94163A),
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            widget.message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF786570),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (index) {
              final phase = (_controller.value + index / 3) % 1;
              return Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: Color.lerp(
                    const Color(0xFFF2DCE4),
                    const Color(0xFFB91C49),
                    phase,
                  ),
                  shape: BoxShape.circle,
                ),
              );
            }),
          ),
        ],
      ),
    );

    if (!widget.fullScreen) return content;
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFF7FA), Color(0xFFF2DCE4)],
        ),
      ),
      alignment: Alignment.center,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: FittedBox(fit: BoxFit.scaleDown, child: content),
        ),
      ),
    );
  }
}

class _CupcakePainter extends CustomPainter {
  const _CupcakePainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 142;
    canvas.save();
    canvas.scale(scale);

    canvas.drawCircle(
      const Offset(71, 70),
      65,
      Paint()..color = const Color(0xFFF2DCE4),
    );

    final wrapper = Path()
      ..moveTo(38, 77)
      ..lineTo(45, 122)
      ..quadraticBezierTo(71, 134, 97, 122)
      ..lineTo(104, 77)
      ..close();
    canvas.drawPath(wrapper, Paint()..color = const Color(0xFFB91C49));

    final wrapperRim = Paint()
      ..color = const Color(0xFF94163A)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(45, 91), const Offset(97, 91), wrapperRim);
    canvas.drawLine(const Offset(47, 104), const Offset(95, 104), wrapperRim);
    canvas.drawLine(const Offset(50, 117), const Offset(92, 117), wrapperRim);

    final frosting = Path()
      ..moveTo(34, 80)
      ..cubicTo(28, 74, 34, 64, 44, 64)
      ..cubicTo(37, 54, 45, 44, 56, 47)
      ..cubicTo(53, 34, 66, 29, 74, 39)
      ..cubicTo(83, 31, 96, 38, 93, 50)
      ..cubicTo(107, 50, 112, 64, 102, 71)
      ..cubicTo(109, 78, 102, 85, 94, 84)
      ..lineTo(44, 84)
      ..quadraticBezierTo(37, 85, 34, 80)
      ..close();
    canvas.drawPath(frosting, Paint()..color = const Color(0xFFFFF9FB));
    canvas.drawPath(
      frosting,
      Paint()
        ..color = const Color(0xFFE7B8C7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    canvas.drawCircle(
      const Offset(71, 34),
      8,
      Paint()..color = const Color(0xFFB91C49),
    );
    canvas.drawCircle(
      const Offset(65, 38),
      5,
      Paint()..color = const Color(0xFFC93D64),
    );
    canvas.drawCircle(
      const Offset(77, 38),
      5,
      Paint()..color = const Color(0xFF94163A),
    );

    final sprinkles = Paint()
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    const sprinklePoints = [
      Offset(48, 63),
      Offset(61, 54),
      Offset(83, 58),
      Offset(94, 68),
      Offset(70, 73),
    ];
    const sprinkleColors = [
      Color(0xFFE6A23C),
      Color(0xFFB91C49),
      Color(0xFFC93D64),
      Color(0xFFE6A23C),
      Color(0xFF94163A),
    ];
    for (var index = 0; index < sprinklePoints.length; index++) {
      final point = sprinklePoints[index];
      final wobble = math.sin(progress * math.pi * 2 + index) * 1.5;
      sprinkles.color = sprinkleColors[index];
      canvas.drawLine(
        Offset(point.dx, point.dy + wobble),
        Offset(point.dx + 4, point.dy + 2 + wobble),
        sprinkles,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CupcakePainter oldDelegate) =>
      oldDelegate.progress != progress;
}
