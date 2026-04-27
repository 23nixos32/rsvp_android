import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:volume_controller/volume_controller.dart';
import '../engine/rsvp_engine.dart';
import '../engine/epub_parser.dart';
import '../models/app_state.dart';

class ReaderScreen extends StatefulWidget {
  final Map<String, String> book;
  final List<String> tokens;
  final int startIndex;

  const ReaderScreen({
    super.key,
    required this.book,
    required this.tokens,
    required this.startIndex,
  });

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late AppConfig _cfg;
  late int _idx;
  late int _total;
  bool _paused = true;
  bool _done = false;
  bool _fontScaleMode = false;
  Timer? _timer;
  Timer? _holdTimer;
  String _currentWord = '';
  double _sessionFontSize = 48.0;

  // Volume listener subscription
  StreamSubscription? _volumeSub;

  @override
  void initState() {
    super.initState();
    _idx   = widget.startIndex;
    _total = countWords(widget.tokens);
    _init();
  }

  Future<void> _init() async {
    _cfg = await loadConfig();
    setState(() {
      _sessionFontSize = _cfg.fontSize;
    });
    _peekWord();

    // Volume key listener
    VolumeController().listener((vol) {
      // We intercept volume changes but use them for WPM or font scale
    });
    // Use key events for volume instead
    HardwareKeyboard.instance.addHandler(_handleKey);
  }

  bool _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (_fontScaleMode) {
      if (event.logicalKey == LogicalKeyboardKey.audioVolumeUp) {
        setState(() => _sessionFontSize = (_sessionFontSize + 2).clamp(20, 120));
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.audioVolumeDown) {
        setState(() => _sessionFontSize = (_sessionFontSize - 2).clamp(20, 120));
        return true;
      }
    } else {
      if (event.logicalKey == LogicalKeyboardKey.audioVolumeUp) {
        _adjustWpm(10);
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.audioVolumeDown) {
        _adjustWpm(-10);
        return true;
      }
    }
    return false;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _holdTimer?.cancel();
    _volumeSub?.cancel();
    HardwareKeyboard.instance.removeHandler(_handleKey);
    _doSave();
    super.dispose();
  }

  // ── word display ────────────────────────────────────────────────────────────

  void _peekWord() {
    var idx = _idx;
    while (idx < widget.tokens.length && widget.tokens[idx] == paraMarker) {
      idx++;
    }
    if (idx < widget.tokens.length) {
      setState(() => _currentWord = widget.tokens[idx]);
    }
  }

  int _wordsRead() => widget.tokens
      .sublist(0, _idx.clamp(0, widget.tokens.length))
      .where((t) => t != paraMarker)
      .length;

  double get _progressPct => _wordsRead() / _total.clamp(1, 999999) * 100;

  // ── playback ────────────────────────────────────────────────────────────────

  void _scheduleNext() {
    _timer?.cancel();
    _timer = Timer(
      Duration(milliseconds: msPerWord(_cfg.wpm).round()),
      _next,
    );
  }

  void _next() {
    if (_paused || _done) return;
    final tokens = widget.tokens;
    if (_idx >= tokens.length) {
      setState(() { _done = true; _paused = true; });
      _doSave();
      return;
    }
    if (tokens[_idx] == paraMarker) {
      _idx++;
      _next();
      return;
    }
    setState(() => _currentWord = tokens[_idx++]);
    if (_idx % 100 == 0) _doSave();
    _scheduleNext();
  }

  void _togglePause() {
    setState(() => _paused = !_paused);
    if (!_paused) _scheduleNext();
  }

  void _stepBack() {
    _timer?.cancel();
    var idx = _idx - 1;
    while (idx > 0 && widget.tokens[idx] == paraMarker) idx--;
    _idx = idx.clamp(0, widget.tokens.length);
    _peekWord();
    setState(() {});
    if (!_paused) _scheduleNext();
  }

  void _stepForward() {
    _timer?.cancel();
    var idx = _idx + 1;
    while (idx < widget.tokens.length && widget.tokens[idx] == paraMarker) {
      idx++;
    }
    _idx = idx.clamp(0, widget.tokens.length);
    _peekWord();
    setState(() {});
    if (!_paused) _scheduleNext();
  }

  void _startHold(bool forward) {
    _holdTimer?.cancel();
    _holdTimer = Timer.periodic(
      Duration(milliseconds: msPerWord(_cfg.wpm).round()),
      (_) => forward ? _stepForward() : _stepBack(),
    );
  }

  void _stopHold() {
    _holdTimer?.cancel();
  }

  void _adjustWpm(int delta) {
    setState(() {
      _cfg.wpm = (_cfg.wpm + delta).clamp(60, 1500);
    });
    saveConfig(_cfg);
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

  // ── font scale mode ─────────────────────────────────────────────────────────

  void _toggleFontScaleMode() {
    setState(() => _fontScaleMode = !_fontScaleMode);
    if (!_fontScaleMode) {
      // Save font size on close
      _cfg.fontSize = _sessionFontSize;
      saveConfig(_cfg);
    }
  }

  // ── touch zones ─────────────────────────────────────────────────────────────

  void _handleTap(TapUpDetails details, double width) {
    final x = details.localPosition.dx;
    if (x < width / 3) {
      _stepBack();
    } else if (x > width * 2 / 3) {
      _stepForward();
    } else {
      _togglePause();
    }
  }

  void _handleLongPressStart(LongPressStartDetails details, double width) {
    final x = details.localPosition.dx;
    if (x < width / 3) {
      _startHold(false);
    } else if (x > width * 2 / 3) {
      _startHold(true);
    } else {
      _toggleFontScaleMode();
    }
  }

  // ── word rendering ──────────────────────────────────────────────────────────

  Widget _buildWord() {
    final word = _currentWord;
    if (word.isEmpty) return const SizedBox.shrink();
    final (pre, orp, post) = splitOrp(word);

    return Row(
      mainAxisSize: MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            pre,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: _sessionFontSize,
              color: const Color(0xFFBEBEBE),
              fontFamily: 'monospace',
            ),
          ),
        ),
        Text(
          orp,
          style: TextStyle(
            fontSize: _sessionFontSize,
            color: const Color(0xFFEBEBEB),
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
        Expanded(
          child: Text(
            post,
            textAlign: TextAlign.left,
            style: TextStyle(
              fontSize: _sessionFontSize,
              color: const Color(0xFFBEBEBE),
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final wr = _wordsRead();
    final pct = _progressPct;

    return Scaffold(
      backgroundColor: const Color(0xFF0d0d1a),
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: const Color(0xFF1a1a2e),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.book['title'] ?? '',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${_cfg.wpm} WPM  ${_paused ? "⏸" : "▶"}  ${pct.toStringAsFixed(1)}%  ($wr/$_total)',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),

            // Font scale overlay
            if (_fontScaleMode)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: const Color(0xFF00b4d8).withOpacity(0.15),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.text_fields, color: Color(0xFF00b4d8), size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'Font scale: ${_sessionFontSize.toStringAsFixed(0)}  — volume keys to adjust, long press to close',
                      style: const TextStyle(color: Color(0xFF00b4d8), fontSize: 12),
                    ),
                  ],
                ),
              ),

            // Main word display — tap/hold zones
            Expanded(
              child: GestureDetector(
                onTapUp: (d) => _handleTap(d, screenWidth),
                onLongPressStart: (d) => _handleLongPressStart(d, screenWidth),
                onLongPressEnd: (_) => _stopHold(),
                child: Container(
                  color: Colors.transparent,
                  child: _buildWord(),
                ),
              ),
            ),

            // Progress bar
            LinearProgressIndicator(
              value: pct / 100,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation(Color(0xFF00b4d8)),
              minHeight: 2,
            ),

            // Bottom hint bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: const Color(0xFF1a1a2e),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('← back',
                      style: TextStyle(color: Colors.grey, fontSize: 11)),
                  const Text('tap = play/pause  long = font',
                      style: TextStyle(color: Colors.grey, fontSize: 11)),
                  const Text('forward →',
                      style: TextStyle(color: Colors.grey, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
