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

/// Remove soft hyphens and split mid-word hard hyphens into separate tokens.
/// 'disc-concerted'      -> ['disc', 'concerted']
/// 'chains-of-words'     -> ['chains', 'of', 'words']
/// 'normal'              -> ['normal']
/// Leading/trailing hyphens (punctuation) are left intact.
List<String> _splitWord(String word) {
  // Remove soft hyphens (U+00AD)
  word = word.replaceAll('\u00AD', '');
  // Only split on mid-word hyphens
  if (word.length > 2 && word.substring(1, word.length - 1).contains('-')) {
    final parts = word.split('-').where((p) => p.isNotEmpty).toList();
    if (parts.length > 1) return parts;
  }
  return [word];
}

Future<ParsedBook> parseEpub(String filepath) async {
  final bytes = await File(filepath).readAsBytes();
  final book = await EpubReader.readBook(bytes);
  final title = (book.Title?.trim().isNotEmpty == true)
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
      if (words.isNotEmpty) {
        for (final w in words) {
          tokens.addAll(_splitWord(w));
        }
        tokens.add(paraMarker);
      }
    }
  }
  for (final sub in chapter.SubChapters ?? []) _processChapter(sub, tokens);
}

int countWords(List<String> tokens) => tokens.where((t) => t != paraMarker).length;
