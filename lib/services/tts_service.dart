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
      // Daha doğal ve akıcı bir tempo — çok hızlı olunca motor takılıp
      // duraksayabiliyor, bu değer daha pürüzsüz bir okuma sağlıyor.
      await _tts.setSpeechRate(0.46);
      await _tts.setPitch(1.05);
      await _tts.setVolume(1.0);
      await _tts.awaitSpeakCompletion(true);
      await _selectBestTurkishVoice();
      _initOk = true;
    } catch (_) {
      // TTS motoru bu cihazda kurulu/erişilebilir değil — sessizce yut.
      _initOk = false;
    }
  }

  /// Cihazdaki Türkçe sesler arasından en doğal/akıcı olanı seçer (konuşan
  /// "karakteri" değiştirir). Uygun ses bulunamazsa varsayılan ses kalır.
  Future<void> _selectBestTurkishVoice() async {
    try {
      final voices = await _tts.getVoices;
      if (voices is! List) return;
      final turkish = <Map>[];
      for (final v in voices) {
        if (v is Map) {
          final locale =
              (v['locale'] ?? v['language'] ?? '').toString().toLowerCase();
          if (locale.startsWith('tr')) turkish.add(v);
        }
      }
      if (turkish.isEmpty) return;
      // Daha kaliteli sesleri öne al: Google "network"/"neural"/"enhanced"
      // sesleri robotik olmayan, akıcı bir okuma sağlar.
      int score(Map v) {
        final name = (v['name'] ?? '').toString().toLowerCase();
        var s = 0;
        if (name.contains('network')) s += 4;
        if (name.contains('neural') || name.contains('enhanced')) s += 3;
        if (name.contains('female') || name.contains('kadın')) s += 1;
        if (name.contains('tr-tr-x')) s += 1;
        return s;
      }

      turkish.sort((a, b) => score(b).compareTo(score(a)));
      final best = turkish.first;
      await _tts.setVoice({
        'name': (best['name'] ?? '').toString(),
        'locale':
            (best['locale'] ?? best['language'] ?? 'tr-TR').toString(),
      });
    } catch (_) {
      // ses seçimi başarısızsa varsayılan sesle devam et
    }
  }

  /// Metni seslendirmeden önce akıcılığı bozan öğeleri temizler: emojiler,
  /// madde işaretleri ve fazladan boş satır/boşluk — bunlar TTS motorunda
  /// takılmaya/duraksamaya yol açar, temizleyince okuma pürüzsüzleşir.
  static String _cleanForSpeech(String text) {
    var t = text;
    t = t.replaceAll(
        RegExp(
            r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2190}-\u{21FF}\u{2B00}-\u{2BFF}\u{FE0F}\u{200D}]',
            unicode: true),
        ' ');
    t = t.replaceAll(RegExp(r'[•·►▶*_]'), ' ');
    t = t.replaceAll(RegExp(r'[ \t]*\n[ \t]*'), '\n');
    t = t.replaceAll(RegExp(r'\n{2,}'), '\n');
    t = t.replaceAll('\n', '. ');
    t = t.replaceAll(RegExp(r'([.?!:])\s*\.'), r'$1');
    t = t.replaceAll(RegExp(r'\s{2,}'), ' ');
    return t.trim();
  }

  /// Verilen metni Türkçe olarak seslendirir. Motor başlatılamadıysa ya da
  /// konuşma sırasında bir hata oluşursa sessizce hiçbir şey yapmaz.
  Future<void> speak(String text) async {
    final cleaned = _cleanForSpeech(text);
    if (cleaned.isEmpty) return;
    try {
      await _initFuture;
      if (!_initOk) return;
      await _tts.stop();
      await _tts.speak(cleaned);
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

  /// [stop]'un "bekleme gerektirmeyen" hali — `dispose()` ve
  /// `didChangeAppLifecycleState` gibi async olamayan yerlerden güvenle
  /// çağrılabilir (asla hata fırlatmaz, sonucu beklenmez).
  ///
  /// Ekran değişiminde / teste girerken sesli anlatımın arka planda çalmaya
  /// devam etmemesi için kullanılır (bkz. topic_screen.dart, quiz_screen.dart,
  /// subject_screen.dart).
  void stopNow() {
    unawaited(stop());
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
