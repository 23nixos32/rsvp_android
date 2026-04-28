const String paraMarker = '\x00PARA\x00';

int getOrpIndex(String word) {
  final alpha = word.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
  final length = alpha.isNotEmpty ? alpha.length : word.length;
  int pos;
  if (length % 2 == 0) {
    pos = length ~/ 2;
  } else {
    final y = length - 1;
    final z = y ~/ 2;
    pos = z + 1;
  }
  return (pos - 1).clamp(0, word.length - 1);
}

(String, String, String) splitOrp(String word) {
  if (word.isEmpty) return ('', ' ', '');
  final idx = getOrpIndex(word);
  return (word.substring(0, idx), word[idx], word.substring(idx + 1));
}

double msPerWord(int wpm) => (60.0 / wpm.clamp(1, 9999)) * 1000.0;
