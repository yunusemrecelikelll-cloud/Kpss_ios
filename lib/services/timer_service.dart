import 'dart:async';
import 'package:flutter/foundation.dart';

/// timer.js karşılığı: basit geri sayım sayacı.
/// Soru başına süre modunda kalan-süre-koruma ve süresi-dolan-soruyu-kilitleme
/// mantığı QuizScreen'de (JS'teki renderQuizView düzeltmesiyle birebir) uygulanır.
class TimerService extends ChangeNotifier {
  Timer? _ticker;
  int _remaining = 0;
  void Function()? _onExpire;

  int get remaining => _remaining;

  void start(int totalSeconds, {void Function()? onExpire}) {
    stop();
    _remaining = totalSeconds;
    _onExpire = onExpire;
    notifyListeners();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      _remaining -= 1;
      notifyListeners();
      if (_remaining <= 0) {
        stop();
        _onExpire?.call();
      }
    });
  }

  void stop() {
    _ticker?.cancel();
    _ticker = null;
  }

  static String format(int s) {
    final abs = s.abs();
    final m = (abs ~/ 60).toString().padLeft(2, '0');
    final sec = (abs % 60).toString().padLeft(2, '0');
    return '$m:$sec';
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
