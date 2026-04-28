import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../engine/rsvp_engine.dart';
import '../engine/epub_parser.dart';
import '../models/app_state.dart';
import 'reader_screen.dart';
import 'search_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<Map<String, String>> _library = [];
  Map<String, Bookmark> _bookmarks = {};
  int _selectedIndex = 0;
  bool _loading = false;
  String _status = '';

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final lib    = await loadLibrary();
    final bmarks = await loadAllBookmarks();
    if (mounted) setState(() {
      _library       = lib;
      _bookmarks     = bmarks;
      _selectedIndex = _selectedIndex.clamp(0, (lib.length - 1).clamp(0, 9999));
    });
  }

  Future<void> _scanDir() async {
    // Use pickFiles with epub extension — works reliably on all Android versions
    // without any storage permissions via Android's Storage Access Framework
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select EPUB file(s)',
      type: FileType.custom,
      allowedExtensions: ['epub'],
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return;
    setState(() { _loading = true; _status = 'Adding books…'; });

    final existing = _library.map((b) => b['book_id']).toSet();
    int added = 0;

    for (final file in result.files) {
      final path = file.path;
      if (path == null) continue;
      try {
        final bookId = await getBookId(path);
        if (existing.contains(bookId)) continue;
        final parsed = await parseEpub(path);
        _library.add({
          'book_id':  bookId,
          'filepath': path,
          'title':    parsed.title,
        });
        existing.add(bookId);
        added++;
      } catch (_) { continue; }
    }

    await saveLibrary(_library);
    final bmarks = await loadAllBookmarks();
    if (mounted) setState(() {
      _bookmarks = bmarks;
      _loading   = false;
      _status    = added > 0 ? 'Added $added book(s)' : 'No new books found';
    });
  }

  Future<void> _openBook(Map<String, String> book) async {
    setState(() { _loading = true; _status = 'Loading…'; });
    try {
      final parsed = await parseEpub(book['filepath']!);
      final bm     = await getBookmark(book['book_id']!);
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(
        builder: (_) => ReaderScreen(
          book: book, tokens: parsed.tokens, startIndex: bm?.wordIndex ?? 0)));
      await _load();
    } catch (e) {
      if (mounted) setState(() => _status = 'Error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _jumpTo(Map<String, String> book) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        title: const Text('Jump to %', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: '14.0',
            hintStyle: TextStyle(color: Colors.grey),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.grey)))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('Jump')),
        ]));
    if (result == null || result.isEmpty) return;
    final pct = double.tryParse(result.replaceAll('%', ''));
    if (pct == null) return;
    setState(() { _loading = true; _status = 'Seeking…'; });
    try {
      final parsed = await parseEpub(book['filepath']!);
      final total  = countWords(parsed.tokens);
      final target = (total * pct / 100).toInt();
      var wc = 0; var wi = 0;
      for (var i = 0; i < parsed.tokens.length; i++) {
        if (parsed.tokens[i] != paraMarker) {
          if (wc >= target) { wi = i; break; }
          wc++;
        }
      }
      await saveBookmark(Bookmark(
        bookId: book['book_id']!, title: book['title']!,
        filepath: book['filepath']!, wordIndex: wi,
        totalWords: total, progressPct: pct.clamp(0.0, 100.0)));
      await _load();
      if (mounted) setState(() => _status = 'Position set to ${pct.toStringAsFixed(1)}%');
    } catch (e) {
      if (mounted) setState(() => _status = 'Error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _searchBook(Map<String, String> book) async {
    final ctrl = TextEditingController();
    final query = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        title: const Text('Search', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl, autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'phrase to find…',
            hintStyle: TextStyle(color: Colors.grey),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.grey)))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('Search')),
        ]));
    if (query == null || query.isEmpty) return;
    setState(() { _loading = true; _status = 'Searching…'; });
    try {
      final parsed = await parseEpub(book['filepath']!);
      if (!mounted) return;
      final tokenIndex = await Navigator.push<int>(context, MaterialPageRoute(
        builder: (_) => SearchScreen(
          book: book, tokens: parsed.tokens, query: query)));
      if (tokenIndex != null) {
        final total = countWords(parsed.tokens);
        final wb    = parsed.tokens
            .sublist(0, tokenIndex)
            .where((t) => t != paraMarker)
            .length;
        final pct = wb / total.clamp(1, 999999) * 100;
        await saveBookmark(Bookmark(
          bookId: book['book_id']!, title: book['title']!,
          filepath: book['filepath']!, wordIndex: tokenIndex,
          totalWords: total, progressPct: pct));
        await _load();
        if (mounted) setState(() => _status = 'Position set to ${pct.toStringAsFixed(1)}%');
      }
    } catch (e) {
      if (mounted) setState(() => _status = 'Error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _removeBook(int index) async {
    final book = _library[index];
    await deleteBookmark(book['book_id']!);
    _library.removeAt(index);
    await saveLibrary(_library);
    await _load();
    if (mounted) setState(() => _status = 'Removed ${book['title']}');
  }

  void _showOptions(Map<String, String> book, int index) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1a1a2e),
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.percent, color: Colors.white),
          title: const Text('Jump to %', style: TextStyle(color: Colors.white)),
          onTap: () { Navigator.pop(context); _jumpTo(book); }),
        ListTile(
          leading: const Icon(Icons.search, color: Colors.white),
          title: const Text('Search', style: TextStyle(color: Colors.white)),
          onTap: () { Navigator.pop(context); _searchBook(book); }),
        ListTile(
          leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
          title: const Text('Remove', style: TextStyle(color: Colors.redAccent)),
          onTap: () { Navigator.pop(context); _removeBook(index); }),
      ])));
  }

  Widget _buildTile(int i) {
    final book = _library[i];
    final bm   = _bookmarks[book['book_id']];
    final pct  = bm?.progressPct ?? 0.0;
    final last = (bm?.lastOpened.length ?? 0) >= 10
        ? bm!.lastOpened.substring(0, 10) : '—';
    final sel  = i == _selectedIndex;
    return GestureDetector(
      onTap:       () => setState(() => _selectedIndex = i),
      onDoubleTap: () => _openBook(book),
      onLongPress: () => _showOptions(book, i),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: sel ? Colors.white.withValues(alpha: 0.08) : Colors.transparent,
        child: Row(children: [
          Expanded(child: Text(book['title'] ?? '?',
            style: TextStyle(
              color: sel ? const Color(0xFFEBEBEB) : const Color(0xFFBEBEBE),
              fontWeight: sel ? FontWeight.bold : FontWeight.normal,
              fontSize: 15),
            overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          SizedBox(width: 80, child: LinearProgressIndicator(
            value: pct / 100,
            backgroundColor: Colors.white12,
            valueColor: const AlwaysStoppedAnimation(Color(0xFF00b4d8)))),
          const SizedBox(width: 8),
          Text('${pct.toStringAsFixed(1)}%',
              style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(width: 8),
          Text(last, style: const TextStyle(color: Colors.grey, fontSize: 11)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0d0d1a),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1a1a2e),
        title: const Text('RSVP Reader',
            style: TextStyle(color: Color(0xFF00b4d8))),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open, color: Colors.white),
            tooltip: 'Scan directory',
            onPressed: _loading ? null : _scanDir),
        ],
      ),
      body: Column(children: [
        Expanded(child: _library.isEmpty
          ? const Center(child: Text('Tap the folder icon to scan for EPUBs',
              style: TextStyle(color: Colors.grey)))
          : ListView.builder(
              itemCount: _library.length,
              itemBuilder: (_, i) => _buildTile(i))),
        if (_loading)
          const LinearProgressIndicator(
            backgroundColor: Colors.transparent,
            valueColor: AlwaysStoppedAnimation(Color(0xFF00b4d8))),
        if (_status.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: const Color(0xFF1a1a2e),
            child: Text(_status,
                style: const TextStyle(color: Colors.grey, fontSize: 12))),
        if (_library.isNotEmpty)
          SafeArea(child: Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00b4d8),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: _loading
                    ? null : () => _openBook(_library[_selectedIndex]),
                child: Text(
                  'Open: ${_library[_selectedIndex]['title'] ?? ''}',
                  overflow: TextOverflow.ellipsis))))),
      ]),
    );
  }
}
