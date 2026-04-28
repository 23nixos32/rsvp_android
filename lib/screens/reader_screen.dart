import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../engine/rsvp_engine.dart';
import '../engine/epub_parser.dart';
import '../models/app_state.dart';

class ReaderScreen extends StatefulWidget {
  final Map<String, String> book;
  final List<String> tokens;
  final int startIndex;
  const ReaderScreen({super.key, required this.book, required this.tokens, required this.startIndex});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  static const _volumeChannel = MethodChannel('com.rsvpreader.app/volume_keys');

  late AppConfig _cfg;
  late int _idx;
  late int _total;
  bool _paused = true;
  bool _done = false;
  bool _fontScaleMode = false;
  Timer? _playTimer;
  Timer? _holdTimer;
  String _currentWord = '';
  double _sessionFontSize = 48.0;

  @override
  void initState() {
    super.initState();
    _idx   = widget.startIndex;
    _total = countWords(widget.tokens);
    _init();
    // Listen for volume key events from MainActivity
    _volumeChannel.setMethodCallHandler((call) async {
      if (call.method == 'volumeUp') {
        _fontScaleMode ? _adjustFontSize(2) : _adjustWpm(10);
      } else if (call.method == 'volumeDown') {
        _fontScaleMode ? _adjustFontSize(-2) : _adjustWpm(-10);
      }
    });
  }

  Future<void> _init() async {
    _cfg = await loadConfig();
    if (mounted) setState(() { _sessionFontSize = _cfg.fontSize; });
    _peekWord();
  }

  @override
  void dispose() {
    _playTimer?.cancel();
    _holdTimer?.cancel();
    _volumeChannel.setMethodCallHandler(null);
    _doSave();
    super.dispose();
  }

  void _peekWord() {
    var idx = _idx;
    while (idx < widget.tokens.length && widget.tokens[idx] == paraMarker) idx++;
    if (idx < widget.tokens.length && mounted) setState(() => _currentWord = widget.tokens[idx]);
  }

  int _wordsRead() => widget.tokens.sublist(0, _idx.clamp(0, widget.tokens.length))
      .where((t) => t != paraMarker).length;

  double get _pct => _wordsRead() / _total.clamp(1, 999999) * 100;

  void _scheduleNext() {
    _playTimer?.cancel();
    _playTimer = Timer(Duration(milliseconds: msPerWord(_cfg.wpm).round()), _next);
  }

  void _next() {
    if (_paused || _done) return;
    if (_idx >= widget.tokens.length) {
      setState(() { _done = true; _paused = true; });
      _doSave();
      return;
    }
    if (widget.tokens[_idx] == paraMarker) { _idx++; _next(); return; }
    if (mounted) setState(() => _currentWord = widget.tokens[_idx++]);
    if (_idx % 100 == 0) _doSave();
    _scheduleNext();
  }

  void _togglePause() {
    setState(() => _paused = !_paused);
    if (!_paused) _scheduleNext();
  }

  void _stepBack() {
    _playTimer?.cancel();
    var idx = _idx - 1;
    while (idx > 0 && widget.tokens[idx] == paraMarker) idx--;
    _idx = idx.clamp(0, widget.tokens.length);
    _peekWord();
    if (!_paused) _scheduleNext();
  }

  void _stepForward() {
    _playTimer?.cancel();
    var idx = _idx + 1;
    while (idx < widget.tokens.length && widget.tokens[idx] == paraMarker) idx++;
    _idx = idx.clamp(0, widget.tokens.length);
    _peekWord();
    if (!_paused) _scheduleNext();
  }

  void _startHold(bool forward) {
    _holdTimer?.cancel();
    _holdTimer = Timer.periodic(
      Duration(milliseconds: msPerWord(_cfg.wpm).round()),
      (_) => forward ? _stepForward() : _stepBack(),
    );
  }

  void _stopHold() => _holdTimer?.cancel();

  void _adjustWpm(int delta) {
    setState(() => _cfg.wpm = (_cfg.wpm + delta).clamp(60, 1500));
    saveConfig(_cfg);
  }

  void _adjustFontSize(double delta) {
    setState(() => _sessionFontSize = (_sessionFontSize + delta).clamp(20, 120));
  }

  void _toggleFontScaleMode() {
    setState(() => _fontScaleMode = !_fontScaleMode);
    if (!_fontScaleMode) {
      _cfg.fontSize = _sessionFontSize;
      saveConfig(_cfg);
    }
  }

  Future<void> _doSave() async {
    final wr = _wordsRead();
    final pct = wr / _total.clamp(1, 999999) * 100;
    await saveBookmark(Bookmark(
      bookId: widget.book['book_id']!,
      title: widget.book['title']!,
      filepath: widget.book['filepath']!,
      wordIndex: _idx,
      totalWords: _total,
      progressPct: pct,
    ));
  }

  void _handleTap(TapUpDetails d, double w) {
    final x = d.localPosition.dx;
    if (x < w / 3)      _stepBack();
    else if (x > w * 2/3) _stepForward();
    else                  _togglePause();
  }

  void _handleLongPress(LongPressStartDetails d, double w) {
    final x = d.localPosition.dx;
    if (x < w / 3)        _startHold(false);
    else if (x > w * 2/3) _startHold(true);
    else                   _toggleFontScaleMode();
  }

  Widget _buildWord() {
    final (pre, orp, post) = splitOrp(_currentWord);
    final style = TextStyle(fontSize: _sessionFontSize, fontFamily: 'monospace');
    return Row(
      children: [
        Expanded(child: Text(pre, textAlign: TextAlign.right,
            style: style.copyWith(color: const Color(0xFFBEBEBE)))),
        Text(orp, style: style.copyWith(color: const Color(0xFFEBEBEB), fontWeight: FontWeight.bold)),
        Expanded(child: Text(post, textAlign: TextAlign.left,
            style: style.copyWith(color: const Color(0xFFBEBEBE)))),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return Scaffold(
      backgroundColor: const Color(0xFF0d0d1a),
      body: SafeArea(
        child: Column(children: [
          // Top bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: const Color(0xFF1a1a2e),
            child: Row(children: [
              Expanded(child: Text(widget.book['title'] ?? '',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
                overflow: TextOverflow.ellipsis)),
              Text('${_cfg.wpm} WPM  ${_paused ? "⏸" : "▶"}  ${_pct.toStringAsFixed(1)}%  (${_wordsRead()}/$_total)',
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ]),
          ),
          // Font scale banner
          if (_fontScaleMode)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: const Color(0xFF00b4d8).withValues(alpha: 0.15),
              child: Text(
                'Font: ${_sessionFontSize.toInt()}pt  —  volume keys to adjust  —  long press centre to close',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF00b4d8), fontSize: 12),
              ),
            ),
          // Word display — touch zones
          Expanded(
            child: GestureDetector(
              onTapUp: (d) => _handleTap(d, w),
              onLongPressStart: (d) => _handleLongPress(d, w),
              onLongPressEnd: (_) => _stopHold(),
              child: Container(color: Colors.transparent, child: _buildWord()),
            ),
          ),
          // Progress
          LinearProgressIndicator(value: _pct / 100,
            backgroundColor: Colors.white12,
            valueColor: const AlwaysStoppedAnimation(Color(0xFF00b4d8)),
            minHeight: 2),
          // Hint bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: const Color(0xFF1a1a2e),
            child: const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('← tap/hold', style: TextStyle(color: Colors.grey, fontSize: 11)),
              Text('tap = play/pause  long = font', style: TextStyle(color: Colors.grey, fontSize: 11)),
              Text('tap/hold →', style: TextStyle(color: Colors.grey, fontSize: 11)),
            ]),
          ),
        ]),
      ),
    );
  }
}
