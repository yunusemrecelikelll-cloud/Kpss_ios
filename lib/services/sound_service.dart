import 'dart:async';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';

import 'storage_service.dart';

/// sounds.js'nin (Web Audio API ile gerçek-zamanlı sentezlenen click/tick/
/// odaklanma sesleri) Flutter karşılığı.
///
/// JS tarafında bu sesler oscillator/noise-buffer ile anlık üretiliyordu;
/// Dart'ta gerçek-zamanlı DSP pratik olmadığından aynı algoritmalar
/// (brown noise, bandpass/highpass filtreleme, exponential zarf vb.) offline
/// bir Node.js script'i ile bir kez WAV dosyalarına render edildi
/// (`assets/sounds/*.wav`) ve burada audioplayers ile çalınıyor.
///
/// Ağırlıklı rastgele "sınav ortamı" olay seçimi JS'teki `_AMBIENCE_EVENTS`
/// dizisiyle birebir aynıdır.
class SoundService {
  SoundService(this._storage);

  final StorageService _storage;
  final Random _rand = Random();

  bool get _enabled => _storage.getSettings()['soundEnabled'] != false;

  // ── Geçici bastırma (test ekranı) ──
  // Test sırasında buton tıklama sesleri dikkat dağıtmasın diye QuizScreen
  // açılırken setSuppressed(true), kapanırken setSuppressed(false) çağırır.
  // Kullanıcının Ayarlar'daki KALICI ses tercihini (soundEnabled) DEĞİŞTİRMEZ;
  // sadece bu oturum boyunca click() sesini susturur.
  bool _suppressed = false;

  /// Tıklama seslerini geçici olarak susturur/açar (bkz. [_suppressed]).
  void setSuppressed(bool value) {
    _suppressed = value;
  }

  final _QuickPlayerPool _clickPool =
      _QuickPlayerPool('sounds/click.wav', poolSize: 4);
  final _QuickPlayerPool _tickPool =
      _QuickPlayerPool('sounds/tick.wav', poolSize: 2);

  // JS _tickPhase: iki farklı perde arasında (480 / 820 Hz) geçiş yapar.
  // tick.wav 480Hz tabanında render edildi; "yüksek" perde için playbackRate
  // ile 820/480 oranında hızlandırılır.
  bool _tickPhase = false;
  static const double _tickHighRate = 820 / 480;

  // ── Sınav ortamı odaklanma sesleri ──
  final AudioPlayer _ambiencePlayer = AudioPlayer();
  bool _ambiencePlaying = false;
  Timer? _ambienceEventTimer;

  final Map<String, _QuickPlayerPool> _eventPools = {
    'paper_rustle': _QuickPlayerPool('sounds/paper_rustle.wav'),
    'page_turn': _QuickPlayerPool('sounds/page_turn.wav'),
    'pencil_scratch': _QuickPlayerPool('sounds/pencil_scratch.wav'),
    'chair_creak': _QuickPlayerPool('sounds/chair_creak.wav'),
    'soft_cough': _QuickPlayerPool('sounds/soft_cough.wav', poolSize: 2),
  };

  // JS _AMBIENCE_EVENTS ile birebir aynı ağırlıklar.
  static const List<_WeightedEvent> _ambienceEvents = [
    _WeightedEvent('paper_rustle', 5),
    _WeightedEvent('page_turn', 3),
    _WeightedEvent('pencil_scratch', 5),
    _WeightedEvent('chair_creak', 2),
    _WeightedEvent('soft_cough', 1),
  ];

  /// Dolgun tık — buton/etkileşim sesi. Ayarlardaki soundEnabled'a ve geçici
  /// bastırma bayrağına ([setSuppressed]) bağlıdır.
  Future<void> click() async {
    if (!_enabled || _suppressed) return;
    await _clickPool.play();
  }

  /// Geri sayım tik-tak sesi (son 5 saniye). Ayarlardaki soundEnabled'a bağlıdır.
  Future<void> tick() async {
    if (!_enabled) return;
    final rate = _tickPhase ? _tickHighRate : 1.0;
    _tickPhase = !_tickPhase;
    await _tickPool.play(rate: rate);
  }

  /// Yeni bir soru/sınav başlarken tik-tak fazını sıfırlar (JS: resetTickPhase).
  void resetTickPhase() {
    _tickPhase = false;
  }

  /// Sınav ortamı odaklanma seslerini başlatır: çok alçak sesle sürekli
  /// döngülü bir fon uğultusu + 15-40sn arası rastgele aralıklarla tetiklenen
  /// TEK bir olay sesi (kağıt hışırtısı, sayfa çevirme, kalem sesi, sandalye
  /// gıcırtısı, nadiren öksürük) — bkz. QuizScreen (Ayarlar'daki "Adaptasyon
  /// Sesleri" açıkken aktif test ekranında çağrılır) ve web karşılığı
  /// src/js/sounds.js#startFocusAmbience (orada "Sınav Ortamı Odaklanma
  /// Sesleri" adıyla manuel bir aç/kapa düğmesiyle tetiklenir).
  ///
  /// Diğer tik/tık seslerini bastırmasın diye HEM döngü hem olay sesleri
  /// düşük ses seviyesinde çalınır. JS'teki gibi kullanıcı elle açıp
  /// kapattığı için soundEnabled ayarına bağlı DEĞİLDİR — gating çağıran
  /// tarafta (QuizScreen'de "adaptationSoundsEnabled" ayarına göre) yapılır.
  Future<void> startFocusAmbience() async {
    if (_ambiencePlaying) return;
    _ambiencePlaying = true;
    try {
      await _ambiencePlayer.setReleaseMode(ReleaseMode.loop);
      await _ambiencePlayer.play(
        // Gerçek kütüphane ortam sesi (Freesound CC kaynaklı iki kaydın
        // birleştirilip normalize edilmiş hali) — düşük sesle sürekli döngü.
        // Üstüne aşağıdaki rastgele olaylar (kağıt/kalem/sayfa/öksürük) da
        // çalınarak gerçekçi bir çalışma salonu atmosferi oluşur.
        AssetSource('sounds/library_ambience.mp3'),
        volume: 0.5,
      );
    } catch (_) {
      _ambiencePlaying = false;
      return;
    }
    _scheduleNextAmbienceEvent();
  }

  Future<void> stopFocusAmbience() async {
    _ambiencePlaying = false;
    _ambienceEventTimer?.cancel();
    _ambienceEventTimer = null;
    try {
      await _ambiencePlayer.stop();
    } catch (_) {
      // yoksay
    }
  }

  // Sınav salonu "Adaptasyon Sesleri" için olay sesleri arası bekleme:
  // 15-40sn arası rastgele — göze/kulağa batmayacak kadar seyrek, ama testin
  // tamamı boyunca birkaç kez gerçekçi bir atmosfer hissi verecek kadar sık.
  static const int _minEventDelayMs = 15000;
  static const int _maxEventDelaySpanMs = 25000; // 15000 + [0, 25000) => 15-40sn

  void _scheduleNextAmbienceEvent() {
    final delayMs = _minEventDelayMs + _rand.nextInt(_maxEventDelaySpanMs);
    _ambienceEventTimer = Timer(Duration(milliseconds: delayMs), () async {
      if (!_ambiencePlaying) return;
      await _playRandomAmbienceEvent();
      if (_ambiencePlaying) _scheduleNextAmbienceEvent();
    });
  }

  // Olay sesleri de (tık/tik-tak ve varsa diğer geri bildirim sesleriyle
  // çakışıp dikkat dağıtmasın diye) düşük sesle çalınır.
  static const double _eventVolume = 0.45;

  Future<void> _playRandomAmbienceEvent() async {
    final total = _ambienceEvents.fold<int>(0, (sum, e) => sum + e.weight);
    var r = _rand.nextDouble() * total;
    for (final e in _ambienceEvents) {
      r -= e.weight;
      if (r <= 0) {
        await _eventPools[e.name]?.play(volume: _eventVolume);
        return;
      }
    }
  }

  /// Servis kapatılırken (ör. app dispose) tüm oynatıcıları serbest bırakır.
  Future<void> dispose() async {
    _ambienceEventTimer?.cancel();
    _ambienceEventTimer = null;
    await _ambiencePlayer.dispose();
    await _clickPool.dispose();
    await _tickPool.dispose();
    for (final pool in _eventPools.values) {
      await pool.dispose();
    }
  }
}

class _WeightedEvent {
  const _WeightedEvent(this.name, this.weight);
  final String name;
  final int weight;
}

/// Aynı kısa ses dosyasının hızlı/üst üste çalınabilmesi için basit bir
/// round-robin AudioPlayer havuzu (audioplayers'ın AudioPool'una benzer,
/// ama setPlaybackRate desteği (tick perde değişimi) için özelleştirilmiş).
class _QuickPlayerPool {
  _QuickPlayerPool(this._assetPath, {this.poolSize = 3});

  final String _assetPath;
  final int poolSize;
  final List<AudioPlayer> _players = [];
  int _next = 0;
  Future<void>? _preparing;

  Future<void> _ensureReady() {
    if (_players.length >= poolSize) return Future.value();
    return _preparing ??= _prepare().whenComplete(() => _preparing = null);
  }

  Future<void> _prepare() async {
    for (var i = _players.length; i < poolSize; i++) {
      final player = AudioPlayer();
      try {
        await player.setPlayerMode(PlayerMode.lowLatency);
        await player.setReleaseMode(ReleaseMode.stop);
        await player.setSource(AssetSource(_assetPath));
        _players.add(player);
      } catch (_) {
        await player.dispose();
      }
    }
  }

  Future<void> play({double volume = 1.0, double rate = 1.0}) async {
    await _ensureReady();
    if (_players.isEmpty) return;
    final player = _players[_next % _players.length];
    _next++;
    try {
      await player.stop();
      await player.setVolume(volume);
      await player.setPlaybackRate(rate);
      await player.resume();
    } catch (_) {
      // Ses çalınamazsa sessizce yut — click/tick kritik bir davranış değil.
    }
  }

  Future<void> dispose() async {
    for (final p in _players) {
      await p.dispose();
    }
    _players.clear();
  }
}
