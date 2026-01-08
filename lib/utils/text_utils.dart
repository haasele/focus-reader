/// Utility functions for text processing
class TextUtils {
  static final RegExp _whitespaceRegex = RegExp(r'\s+');

  /// Split text into words, removing empty strings
  static List<String> splitIntoWords(String text) {
    return text
        .split(_whitespaceRegex)
        .where((w) => w.isNotEmpty)
        .toList();
  }

  /// Calculate Optimal Recognition Point (ORP) index for a word
  /// ORP is the position where the eye naturally focuses when reading
  static int getOrpIndex(String word) {
    if (word.isEmpty) return 0;
    final len = word.length;
    if (len <= 1) return 0;
    if (len <= 5) return 1;
    if (len <= 9) return 2;
    if (len <= 13) return 3;
    return 4;
  }

  /// Safely get ORP parts of a word (before, focus char, after)
  /// Returns null if word is empty or invalid
  static ({String part1, String focusChar, String part2})? getOrpParts(
    String word,
  ) {
    if (word.isEmpty) return null;

    final orpIndex = getOrpIndex(word);
    if (orpIndex >= word.length) {
      // Fallback: use first character as focus
      return (
        part1: '',
        focusChar: word[0],
        part2: word.substring(1),
      );
    }

    return (
      part1: word.substring(0, orpIndex),
      focusChar: word[orpIndex],
      part2: word.substring(orpIndex + 1),
    );
  }
}
