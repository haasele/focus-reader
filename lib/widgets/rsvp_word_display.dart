import 'package:flutter/material.dart';
import '../utils/text_utils.dart';

/// Widget that displays a word with ORP (Optimal Recognition Point) highlighting
class RSVPWordDisplay extends StatelessWidget {
  final List<String> words;
  final int currentIndex;

  const RSVPWordDisplay({
    super.key,
    required this.words,
    required this.currentIndex,
  });

  @override
  Widget build(BuildContext context) {
    if (words.isEmpty) {
      return const Text(
        "PDF / EPUB / TXT öffnen",
        style: TextStyle(fontSize: 20, color: Colors.grey),
      );
    }

    if (currentIndex >= words.length) {
      return const Text(
        "Fertig!",
        style: TextStyle(fontSize: 40),
      );
    }

    // Bounds checking
    if (currentIndex < 0 || currentIndex >= words.length) {
      return const Text(
        "Fehler: Ungültiger Index",
        style: TextStyle(fontSize: 20, color: Colors.red),
      );
    }

    final word = words[currentIndex];
    final orpParts = TextUtils.getOrpParts(word);

    if (orpParts == null) {
      return const Text(
        "Fehler: Leeres Wort",
        style: TextStyle(fontSize: 20, color: Colors.red),
      );
    }

    const textStyle = TextStyle(
      fontFamily: 'Courier New',
      fontSize: 52,
      color: Colors.white,
      fontWeight: FontWeight.bold,
    );

    final redStyle = TextStyle(
      fontFamily: 'Courier New',
      fontSize: 52,
      color: Theme.of(context).colorScheme.secondary,
      fontWeight: FontWeight.bold,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Measure exact widths with TextPainter
        final part1Painter = TextPainter(
          text: TextSpan(text: orpParts.part1, style: textStyle),
          textDirection: TextDirection.ltr,
        );
        part1Painter.layout();

        final focusCharPainter = TextPainter(
          text: TextSpan(text: orpParts.focusChar, style: redStyle),
          textDirection: TextDirection.ltr,
        );
        focusCharPainter.layout();

        final part2Painter = TextPainter(
          text: TextSpan(text: orpParts.part2, style: textStyle),
          textDirection: TextDirection.ltr,
        );
        part2Painter.layout();

        final part1Width = part1Painter.width;
        final focusCharWidth = focusCharPainter.width;

        // Viewport center
        final centerX = constraints.maxWidth / 2;

        // Positions: Red character in the center
        final focusCharLeft = centerX - focusCharWidth / 2;
        final part1Left = focusCharLeft - part1Width;
        final part2Left = focusCharLeft + focusCharWidth;

        // Vertical centering
        final centerY = constraints.maxHeight / 2 - 26; // fontSize/2

        return Stack(
          children: [
            // part1 - left of red character
            if (orpParts.part1.isNotEmpty)
              Positioned(
                left: part1Left,
                top: centerY,
                child: Text(orpParts.part1, style: textStyle),
              ),
            // Red character - exactly in the center
            Positioned(
              left: focusCharLeft,
              top: centerY,
              child: Text(orpParts.focusChar, style: redStyle),
            ),
            // part2 - right of red character
            if (orpParts.part2.isNotEmpty)
              Positioned(
                left: part2Left,
                top: centerY,
                child: Text(orpParts.part2, style: textStyle),
              ),
          ],
        );
      },
    );
  }
}
