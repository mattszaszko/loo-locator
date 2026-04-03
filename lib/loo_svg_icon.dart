import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Loo graphic from [assets/loo.svg], tinted with [color].
class LooSvgIcon extends StatelessWidget {
  const LooSvgIcon({
    super.key,
    this.size = 26,
    this.color = const Color(0xFFFFC107),
  });

  final double size;
  final Color color;

  static const String assetPath = 'assets/loo.svg';

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: SvgPicture.asset(
        assetPath,
        fit: BoxFit.contain,
        alignment: Alignment.center,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      ),
    );
  }
}
