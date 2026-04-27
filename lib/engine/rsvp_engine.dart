// Core RSVP engine — mirrors the Python logic exactly.

const String paraMarker = '\x00PARA\x00';

/// Returns the 0-based index of the ORP character in [word].
///
/// Even length : position = length / 2  (1-based) → index = length/2 - 1
/// Odd length  : y = length-1, z = y/2, pos = z+1 (1-based) → index = (length-1)/2
int getOrpIndex(String word) {
  // Strip non-alphanumeric to measure the readable core
  final alpha = word.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
  final length = alpha.isNotEmpty ? alpha.length : word.length;

  int pos;
  if (length % 2 == 0) {
    pos = length ~/ 2; // 1-based
  } else {
    final y = length - 1;
    final z = y ~/ 2;
    pos = z + 1; // 1-based
  }
  // Convert to 0-based, clamp to word length
  return (pos - 1).clamp(0, word.length - 1);
}

/// Split [word] into (pre, orp, post).
(String, String, String) splitOrp(String word) {
  if (word.isEmpty) return ('', ' ', '');
  final idx = getOrpIndex(word);
  return (
    word.substring(0, idx),
    word[idx],
    word.substring(idx + 1),
  );
}

/// Base display duration in milliseconds at [wpm].
double msPerWord(int wpm) {
  return (60.0 / wpm.clamp(1, 9999)) * 1000.0;
}
