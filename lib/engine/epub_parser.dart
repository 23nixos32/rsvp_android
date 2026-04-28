import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:epubx/epubx.dart';
import 'package:html/parser.dart' as html_parser;
import 'rsvp_engine.dart';

const _blockTags = {'p','h1','h2','h3','h4','h5','h6','li','div','br','tr','blockquote'};

Future<String> getBookId(String filepath) async {
  final bytes = await File(filepath).openRead(0, 65536).fold<List<int>>(
    [], (acc, chunk) => acc..addAll(chunk));
  return md5.convert(bytes).toString().substring(0, 16);
}

class ParsedBook {
  final String title;
  final List<String> tokens;
  ParsedBook(this.title, this.tokens);
}

Future<ParsedBook> parseEpub(String filepath) async {
  final bytes = await File(filepath).readAsBytes();
  final book = EpubReader.readBook(bytes);
  final title = book.Title?.trim().isNotEmpty == true
      ? book.Title! : filepath.split('/').last.replaceAll('.epub', '');

  final rawTokens = <String>[];
  for (final chapter in book.Chapters ?? []) {
    _processChapter(chapter, rawTokens);
  }

  final tokens = <String>[];
  var prevMarker = false;
  for (final t in rawTokens) {
    if (t == paraMarker) {
      if (!prevMarker && tokens.isNotEmpty) tokens.add(t);
      prevMarker = true;
    } else {
      tokens.add(t);
      prevMarker = false;
    }
  }
  return ParsedBook(title, tokens);
}

void _processChapter(EpubChapter chapter, List<String> tokens) {
  final content = chapter.HtmlContent ?? '';
  if (content.isNotEmpty) {
    final doc = html_parser.parse(content);
    for (final tag in ['script','style','head','nav']) {
      for (final el in doc.querySelectorAll(tag)) el.remove();
    }
    final buffer = StringBuffer();
    void walk(node) {
      if (node.nodeType == 3) {
        buffer.write(node.text);
      } else {
        if (_blockTags.contains(node.localName ?? '')) buffer.write('\x01');
        for (final child in node.nodes) walk(child);
      }
    }
    walk(doc.body ?? doc.documentElement);
    for (final chunk in buffer.toString().split('\x01')) {
      final words = chunk.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      if (words.isNotEmpty) { tokens.addAll(words); tokens.add(paraMarker); }
    }
  }
  for (final sub in chapter.SubChapters ?? []) _processChapter(sub, tokens);
}

int countWords(List<String> tokens) => tokens.where((t) => t != paraMarker).length;

Future<List<Map<String, String>>> scanDir(String directory) async {
  final results = <Map<String, String>>[];
  final dir = Directory(directory);
  if (!await dir.exists()) return results;
  await for (final entity in dir.list(recursive: true)) {
    if (entity is File && entity.path.toLowerCase().endsWith('.epub')) {
      try {
        final bookId = await getBookId(entity.path);
        final bytes = await entity.readAsBytes();
        final book = EpubReader.readBook(bytes);
        final t = book.Title?.trim() ?? '';
        results.add({'book_id': bookId, 'filepath': entity.path,
          'title': t.isNotEmpty ? t : entity.path.split('/').last});
      } catch (_) { continue; }
    }
  }
  results.sort((a, b) => (a['title'] ?? '').compareTo(b['title'] ?? ''));
  return results;
}
