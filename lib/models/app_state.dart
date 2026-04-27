import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Config ────────────────────────────────────────────────────────────────────

class AppConfig {
  int wpm;
  double fontSize;

  AppConfig({this.wpm = 250, this.fontSize = 48.0});

  factory AppConfig.fromJson(Map<String, dynamic> j) => AppConfig(
        wpm: j['wpm'] ?? 250,
        fontSize: (j['font_size'] ?? 48.0).toDouble(),
      );

  Map<String, dynamic> toJson() => {'wpm': wpm, 'font_size': fontSize};
}

Future<AppConfig> loadConfig() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString('config');
  if (raw != null) {
    try {
      return AppConfig.fromJson(jsonDecode(raw));
    } catch (_) {}
  }
  return AppConfig();
}

Future<void> saveConfig(AppConfig config) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('config', jsonEncode(config.toJson()));
}

// ── Bookmarks (one file per book) ─────────────────────────────────────────────

class Bookmark {
  final String bookId;
  final String title;
  final String filepath;
  int wordIndex;
  int totalWords;
  double progressPct;
  String lastOpened;

  Bookmark({
    required this.bookId,
    required this.title,
    required this.filepath,
    this.wordIndex = 0,
    this.totalWords = 0,
    this.progressPct = 0.0,
    String? lastOpened,
  }) : lastOpened = lastOpened ?? DateTime.now().toIso8601String();

  factory Bookmark.fromJson(Map<String, dynamic> j) => Bookmark(
        bookId: j['book_id'] ?? '',
        title: j['title'] ?? '',
        filepath: j['filepath'] ?? '',
        wordIndex: j['word_index'] ?? 0,
        totalWords: j['total_words'] ?? 0,
        progressPct: (j['progress_pct'] ?? 0.0).toDouble(),
        lastOpened: j['last_opened'],
      );

  Map<String, dynamic> toJson() => {
        'book_id': bookId,
        'title': title,
        'filepath': filepath,
        'word_index': wordIndex,
        'total_words': totalWords,
        'progress_pct': progressPct,
        'last_opened': lastOpened,
      };
}

Future<Directory> _bookmarksDir() async {
  final base = await getApplicationDocumentsDirectory();
  final dir = Directory('${base.path}/rsvp_reader/bookmarks');
  await dir.create(recursive: true);
  return dir;
}

Future<void> saveBookmark(Bookmark bm) async {
  bm.lastOpened = DateTime.now().toIso8601String();
  final dir = await _bookmarksDir();
  final f = File('${dir.path}/${bm.bookId}.json');
  await f.writeAsString(jsonEncode(bm.toJson()));
}

Future<Bookmark?> getBookmark(String bookId) async {
  final dir = await _bookmarksDir();
  final f = File('${dir.path}/$bookId.json');
  if (!await f.exists()) return null;
  try {
    return Bookmark.fromJson(jsonDecode(await f.readAsString()));
  } catch (_) {
    return null;
  }
}

Future<void> deleteBookmark(String bookId) async {
  final dir = await _bookmarksDir();
  final f = File('${dir.path}/$bookId.json');
  if (await f.exists()) await f.delete();
}

Future<Map<String, Bookmark>> loadAllBookmarks() async {
  final dir = await _bookmarksDir();
  final result = <String, Bookmark>{};
  await for (final entity in dir.list()) {
    if (entity is File && entity.path.endsWith('.json')) {
      try {
        final bm = Bookmark.fromJson(jsonDecode(await entity.readAsString()));
        result[bm.bookId] = bm;
      } catch (_) {}
    }
  }
  return result;
}

// ── Library ───────────────────────────────────────────────────────────────────

Future<File> _libraryFile() async {
  final base = await getApplicationDocumentsDirectory();
  final dir = Directory('${base.path}/rsvp_reader');
  await dir.create(recursive: true);
  return File('${dir.path}/library.json');
}

Future<List<Map<String, String>>> loadLibrary() async {
  final f = await _libraryFile();
  if (!await f.exists()) return [];
  try {
    final list = jsonDecode(await f.readAsString()) as List;
    return list.map((e) => Map<String, String>.from(e)).toList();
  } catch (_) {
    return [];
  }
}

Future<void> saveLibrary(List<Map<String, String>> library) async {
  final f = await _libraryFile();
  await f.writeAsString(jsonEncode(library));
}
