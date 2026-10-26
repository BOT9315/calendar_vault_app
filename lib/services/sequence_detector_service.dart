import 'dart:async';
import 'package:flutter/services.dart';

typedef OnSecretMatchedCallback = void Function();
typedef OnCandidateCheckCallback = Future<bool> Function(List<int> candidate);

class SequenceDetectorService {
  final List<int> _currentBuffer = [];
  Timer? _resetTimer;
  static const int TIMEOUT_SECONDS = 5;

  List<int> targetSequence;
  final OnSecretMatchedCallback onMatched;
  final OnCandidateCheckCallback? onCandidateCheck;

  SequenceDetectorService({
    required this.targetSequence,
    required this.onMatched,
    this.onCandidateCheck,
  });

  /// Called whenever user taps a date (day number 1..31) on the calendar
  void onDateTapped(int day) async {
    _resetTimer?.cancel();

    _currentBuffer.add(day);

    // Buffer holds up to 4 dates (standard sequence length)
    final maxLen = targetSequence.isNotEmpty ? targetSequence.length : 4;
    if (_currentBuffer.length > maxLen) {
      _currentBuffer.removeAt(0);
    }

    // 1. Direct match with configured sequence
    if (_matchesSequence()) {
      HapticFeedback.heavyImpact();
      _currentBuffer.clear();
      onMatched();
      return;
    }

    // 2. If 4 dates have been tapped and candidate check callback is provided (e.g. for reinstallation recovery)
    if (_currentBuffer.length == 4 && onCandidateCheck != null) {
      final candidate = List<int>.from(_currentBuffer);
      final isMatch = await onCandidateCheck!(candidate);
      if (isMatch) {
        HapticFeedback.heavyImpact();
        targetSequence = List.from(candidate);
        _currentBuffer.clear();
        onMatched();
        return;
      }
    }

    // Auto-clear buffer if user stops tapping for TIMEOUT_SECONDS
    _resetTimer = Timer(const Duration(seconds: TIMEOUT_SECONDS), () {
      _currentBuffer.clear();
    });
  }

  bool _matchesSequence() {
    if (targetSequence.isEmpty) return false;
    if (_currentBuffer.length != targetSequence.length) return false;
    for (int i = 0; i < targetSequence.length; i++) {
      if (_currentBuffer[i] != targetSequence[i]) return false;
    }
    return true;
  }

  void updateTargetSequence(List<int> newSequence) {
    targetSequence = List.from(newSequence);
    _currentBuffer.clear();
  }

  void reset() {
    _currentBuffer.clear();
    _resetTimer?.cancel();
  }
}
