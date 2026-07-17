import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Konu anlatımlarının Türkçe sesli okunmasını sağlayan flutter_tts
/// sarmalayıcısı.
///
/// TTS motoru bazı cihazlarda/emülatörlerde kurulu ya da erişilebilir
/// olmayabilir; bu yüzden başlatma ve konuşma çağrıları etrafındaki tüm
/// hatalar sessizce yutulur — sesli anlatım tamamen opsiyonel bir özelliktir
/// ve asla uygulamayı çökertmemelidir.
class TtsService extends ChangeNotifier {
  TtsService() {
    _initFuture = _init();
  }

  final FlutterTts _tts = FlutterTts();
  late final Future<void> _initFuture;
  bool _initOk = false;

  bool _isSpeaking = false;
  bool get isSpeaking => _isSpeaking;

  void _setSpeaking(bool value) {
    if (_isSpeaking == value) return;
    _isSpeaking = value;
    notifyListeners();
  }

  Future<void> _init() async {
    try {
      _tts.setStartHandler(() => _setSpeaking(true));
      _tts.setCompletionHandler(() => _setSpeaking(false));
      _tts.setCancelHandler(() => _setSpeaking(false));
      _tts.setErrorHandler((_) => _setSpeaking(false));
      _tts.setPauseHandler(() => _setSpeaking(false));
      _tts.setContinueHandler(() => _setSpeaking(true));

      await _tts.setLanguage('tr-TR');
      await _tts.setSpeechRate(0.48);
      await _tts.setPitch(1.0);
      await _tts.awaitSpeakCompletion(true);
      _initOk = true;
    } catch (_) {
      // TTS motoru bu cihazda kurulu/erişilebilir değil — sessizce yut.
      _initOk = false;
    }
  }

  /// Verilen metni Türkçe olarak seslendirir. Motor başlatılamadıysa ya da
  /// konuşma sırasında bir hata oluşursa sessizce hiçbir şey yapmaz.
  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    try {
      await _initFuture;
      if (!_initOk) return;
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {
      _setSpeaking(false);
    }
  }

  /// Konuşmayı durdurur. Motor mevcut değilse ya da hata oluşursa sessizce
  /// yoksayılır.
  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {
      // yoksay
    } finally {
      _setSpeaking(false);
    }
  }

  /// Bazı platform/motor kombinasyonlarında desteklenmeyebilir; desteklenmiyorsa
  /// sessizce yoksayılır.
  Future<void> pause() async {
    try {
      await _tts.pause();
    } catch (_) {
      // desteklenmiyor olabilir — yoksay
    }
  }

  @override
  void dispose() {
    unawaited(_tts.stop());
    super.dispose();
  }
}
