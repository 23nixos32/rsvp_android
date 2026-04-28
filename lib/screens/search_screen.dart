import 'package:flutter/material.dart';
import '../engine/rsvp_engine.dart';

class SearchMatch {
  final int tokenIndex;
  final String pre, match, post;
  SearchMatch(this.tokenIndex, this.pre, this.match, this.post);
}

List<SearchMatch> findMatches(List<String> tokens, String query) {
  final words = tokens.where((t) => t != paraMarker).toList();
  final qWords = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (qWords.isEmpty) return [];
  final wordPositions = <int>[];
  for (var i = 0; i < tokens.length; i++) {
    if (tokens[i] != paraMarker) wordPositions.add(i);
  }
  final matches = <SearchMatch>[];
  for (var wi = 0; wi <= words.length - qWords.length; wi++) {
    final slice = words.sublist(wi, wi + qWords.length)
        .map((w) => w.toLowerCase().replaceAll(RegExp(r'[.,;:!?"\']+'), '')).toList();
    if (slice.join(' ') == qWords.join(' ')) {
      final pre = [if (wi > 6) '…', ...words.sublist((wi-6).clamp(0,wi))].join(' ');
      final mid = words.sublist(wi, wi + qWords.length).join(' ');
      final end = wi + qWords.length;
      final post = [...words.sublist(end, (end+6).clamp(0,words.length)),
        if (end+6 < words.length) '…'].join(' ');
      matches.add(SearchMatch(wordPositions[wi], pre, mid, post));
    }
  }
  return matches;
}

class SearchScreen extends StatefulWidget {
  final Map<String, String> book;
  final List<String> tokens;
  final String query;
  const SearchScreen({super.key, required this.book, required this.tokens, required this.query});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late List<SearchMatch> _matches;
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    _matches = findMatches(widget.tokens, widget.query);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0d0d1a),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1a1a2e),
        title: Text('"${widget.query}"', style: const TextStyle(color: Color(0xFF00b4d8), fontSize: 14),
            overflow: TextOverflow.ellipsis),
      ),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(12),
          child: Text(_matches.isEmpty ? 'No matches found.'
              : '${_matches.length} match(es) — tap to select, double-tap to jump',
            style: const TextStyle(color: Colors.grey, fontSize: 13))),
        Expanded(child: ListView.builder(
          itemCount: _matches.length,
          itemBuilder: (_, i) {
            final m = _matches[i];
            final sel = i == _selected;
            return GestureDetector(
              onTap: () => setState(() => _selected = i),
              onDoubleTap: () => Navigator.pop(context, m.tokenIndex),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                color: sel ? Colors.white.withValues(alpha: 0.08) : Colors.transparent,
                child: RichText(text: TextSpan(
                  style: const TextStyle(color: Color(0xFFBEBEBE), fontSize: 14),
                  children: [
                    if (m.pre.isNotEmpty) TextSpan(text: '${m.pre} '),
                    TextSpan(text: m.match, style: const TextStyle(
                        color: Color(0xFFEBEBEB), fontWeight: FontWeight.bold)),
                    if (m.post.isNotEmpty) TextSpan(text: ' ${m.post}'),
                  ],
                )),
              ),
            );
          },
        )),
        if (_matches.isNotEmpty)
          SafeArea(child: Padding(padding: const EdgeInsets.all(12),
            child: SizedBox(width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00b4d8),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: () => Navigator.pop(context, _matches[_selected].tokenIndex),
                child: const Text('Jump to selected match'),
              )))),
      ]),
    );
  }
}
