import 'dart:async';
import 'package:flutter/foundation.dart';

/// Controller for RSVP (Rapid Serial Visual Presentation) reading
class RSVPController extends ChangeNotifier {
  List<String> _words = [];
  int _currentIndex = 0;
  bool _isPlaying = false;
  double _wpm = 300;
  Timer? _timer;
  bool _longWordDelay = true;

  // Callbacks
  Function(int)? onWordChanged;
  Function()? onFinished;
  Function()? onProgressSave;

  List<String> get words => _words;
  int get currentIndex => _currentIndex;
  bool get isPlaying => _isPlaying;
  double get wpm => _wpm;
  bool get longWordDelay => _longWordDelay;

  /// Set words and reset index
  void setWords(List<String> words) {
    _words = words;
    _currentIndex = 0;
    notifyListeners();
  }

  /// Set WPM (words per minute)
  void setWpm(double wpm) {
    _wpm = wpm.clamp(60, 1200);
    notifyListeners();
  }

  /// Set long word delay setting
  void setLongWordDelay(bool enabled) {
    _longWordDelay = enabled;
    notifyListeners();
  }

  /// Toggle play/pause
  void togglePlay() {
    if (_words.isEmpty) return;
    if (_isPlaying) {
      pause();
    } else {
      play();
    }
  }

  /// Start reading
  void play() {
    if (_words.isEmpty) return;
    _isPlaying = true;
    notifyListeners();
    _scheduleNextWord();
  }

  /// Pause reading
  void pause() {
    _timer?.cancel();
    _isPlaying = false;
    notifyListeners();
    onProgressSave?.call();
  }

  /// Reset to beginning
  void reset() {
    pause();
    _currentIndex = 0;
    notifyListeners();
    onProgressSave?.call();
  }

  /// Jump to specific word index
  void jumpToIndex(int index) {
    pause();
    _currentIndex = index.clamp(0, _words.length - 1);
    notifyListeners();
  }

  /// Calculate delay for current word based on WPM and word characteristics
  int _calculateDelay(String word) {
    // Base delay: milliseconds per word at given WPM
    final baseDelay = (60000 / _wpm).round();
    double multiplier = 1.0;

    // Punctuation delays
    if (word.endsWith('.') ||
        word.endsWith('!') ||
        word.endsWith('?') ||
        word.endsWith(':')) {
      multiplier = 2.5;
    } else if (word.endsWith(',') || word.endsWith(';')) {
      multiplier = 1.5;
    }

    // Long word delay
    if (_longWordDelay && word.length > 9) {
      // If we already have a pause (punctuation), extend it slightly
      // Otherwise add time
      multiplier = multiplier == 1.0 ? 1.5 : multiplier * 1.2;
    } else if (word.length < 3) {
      // Short words are faster
      multiplier *= 0.8;
    }

    return (baseDelay * multiplier).round();
  }

  /// Schedule next word display
  void _scheduleNextWord() {
    if (!_isPlaying) return;

    if (_currentIndex >= _words.length) {
      pause();
      _currentIndex = 0;
      onFinished?.call();
      return;
    }

    final currentWord = _words[_currentIndex];
    final delay = _calculateDelay(currentWord);

    _timer = Timer(Duration(milliseconds: delay), () {
      if (_isPlaying) {
        _currentIndex++;
        notifyListeners();
        onWordChanged?.call(_currentIndex);

        // Save progress every 10 words
        if (_currentIndex % 10 == 0) {
          onProgressSave?.call();
        }

        _scheduleNextWord();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
