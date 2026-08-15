import 'package:flutter/material.dart';

/// Paints a softly feathered illustration behind full-screen foreground
/// content without introducing a card or clipped image boundary.
class FullBleedIllustrationBackground extends StatelessWidget {
  const FullBleedIllustrationBackground({
    required this.backgroundGradient,
    required this.child,
    this.illustrationAsset,
    this.illustration,
    this.alignment = Alignment.center,
    this.fit = BoxFit.contain,
    this.topFade = 0,
    this.bottomFade = 0,
    this.leftFade = 0,
    this.rightFade = 0,
    this.decorativeOverlay,
    this.illustrationOverlay,
    this.scrim,
    this.semanticLabel,
    this.excludeFromSemantics = true,
    super.key,
  }) : assert(
         (illustrationAsset == null) != (illustration == null),
         'Provide exactly one illustrationAsset or illustration widget.',
       ),
       assert(topFade >= 0 && topFade <= 0.5),
       assert(bottomFade >= 0 && bottomFade <= 0.5),
       assert(leftFade >= 0 && leftFade <= 0.5),
       assert(rightFade >= 0 && rightFade <= 0.5);

  final String? illustrationAsset;
  final Widget? illustration;
  final AlignmentGeometry alignment;
  final BoxFit fit;
  final Gradient backgroundGradient;

  /// Fractions of the illustration bounds used to fade each edge.
  final double topFade;
  final double bottomFade;
  final double leftFade;
  final double rightFade;

  /// A non-interactive layer painted between the background and illustration.
  final Widget? decorativeOverlay;

  /// A non-interactive layer painted over the illustration but below [scrim].
  final Widget? illustrationOverlay;

  /// A readability gradient painted above the decorative layers.
  final Gradient? scrim;

  final String? semanticLabel;
  final bool excludeFromSemantics;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final artwork = _buildArtwork();

    return DecoratedBox(
      decoration: BoxDecoration(gradient: backgroundGradient),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (decorativeOverlay != null)
            IgnorePointer(child: ExcludeSemantics(child: decorativeOverlay!)),
          IgnorePointer(
            child: RepaintBoundary(
              child: _EdgeFeatherMask(
                topFade: topFade,
                bottomFade: bottomFade,
                leftFade: leftFade,
                rightFade: rightFade,
                child: artwork,
              ),
            ),
          ),
          if (illustrationOverlay != null)
            IgnorePointer(child: ExcludeSemantics(child: illustrationOverlay!)),
          if (scrim != null)
            IgnorePointer(
              child: ExcludeSemantics(
                child: DecoratedBox(decoration: BoxDecoration(gradient: scrim)),
              ),
            ),
          child,
        ],
      ),
    );
  }

  Widget _buildArtwork() {
    Widget artwork;
    if (illustrationAsset case final asset?) {
      artwork = Image.asset(
        asset,
        fit: fit,
        alignment: alignment,
        filterQuality: FilterQuality.high,
        gaplessPlayback: true,
        semanticLabel: semanticLabel,
        excludeFromSemantics: excludeFromSemantics || semanticLabel == null,
      );
    } else {
      artwork = FittedBox(fit: fit, alignment: alignment, child: illustration!);
      if (excludeFromSemantics || semanticLabel == null) {
        artwork = ExcludeSemantics(child: artwork);
      } else {
        artwork = Semantics(image: true, label: semanticLabel, child: artwork);
      }
    }
    return artwork;
  }
}

class _EdgeFeatherMask extends StatelessWidget {
  const _EdgeFeatherMask({
    required this.topFade,
    required this.bottomFade,
    required this.leftFade,
    required this.rightFade,
    required this.child,
  });

  final double topFade;
  final double bottomFade;
  final double leftFade;
  final double rightFade;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    Widget masked = child;
    if (leftFade > 0 || rightFade > 0) {
      masked = ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => LinearGradient(
          colors: [
            leftFade > 0 ? Colors.transparent : Colors.white,
            Colors.white,
            Colors.white,
            rightFade > 0 ? Colors.transparent : Colors.white,
          ],
          stops: [0, leftFade, 1 - rightFade, 1],
        ).createShader(bounds),
        child: masked,
      );
    }
    if (topFade > 0 || bottomFade > 0) {
      masked = ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            topFade > 0 ? Colors.transparent : Colors.white,
            Colors.white,
            Colors.white,
            bottomFade > 0 ? Colors.transparent : Colors.white,
          ],
          stops: [0, topFade, 1 - bottomFade, 1],
        ).createShader(bounds),
        child: masked,
      );
    }
    return masked;
  }
}
