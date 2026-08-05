import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/turkey_map_data.dart';
import '../../services/sound_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_provider.dart';
import '../tools_hub_screen.dart';
import 'map_shared.dart';

const int kBolgeBulRounds = 8;

const String _kHowToPlay =
    'Ekranda bir bölge adı yazar (ör. "Ege"). O bölgeye ait HERHANGİ bir ile '
    'haritada dokun. Yanlış dokunursan 3 hakkın vardır; üçünü de kullanırsan '
    'doğru cevap gösterilir ve sıradaki soruya geçilir. 8 soru sonunda skorun görünür.';

/// Mod 3 — "Bölgeyi Bul": 7 coğrafi bölgeden biri sorulur, kullanıcı o
/// bölgeye ait HERHANGİ bir ile dokunarak cevaplar.
class BolgeyiBulScreen extends StatefulWidget {
  const BolgeyiBulScreen({super.key});

  @override
  State<BolgeyiBulScreen> createState() => _BolgeyiBulScreenState();
}

class _BolgeyiBulScreenState extends State<BolgeyiBulScreen> {
  bool _locked = false;
  bool _booted = false;
  bool _finished = false;
  int _round = 0;
  int _score = 0;
  int _attempts = 0;
  late List<String> _queue;
  TurkeyProvince? _tapped;
  bool _showResult = false;
  final List<TurkeyProvince> _yanlisSecilen = [];
  DateTime? _sessionStart;

  @override
  void initState() {
    super.initState();
    _sessionStart = DateTime.now();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  @override
  void dispose() {
    final start = _sessionStart;
    if (start != null) {
      context.read<StorageService>().addGameTimeSpent(kBolgeBulGameId, DateTime.now().difference(start));
    }
    super.dispose();
  }

  Future<void> _boot() async {
    final ok = await consumeMapGameDailyPlay(context);
    if (!mounted) return;
    if (!ok) {
      setState(() => _locked = true);
      return;
    }
    final rnd = Random();
    final regions = List<String>.from(kTurkeyRegions);
    final queue = <String>[];
    while (queue.length < kBolgeBulRounds) {
      regions.shuffle(rnd);
      queue.addAll(regions);
    }
    setState(() {
      _queue = queue.take(kBolgeBulRounds).toList();
      _booted = true;
      _round = 0;
      _score = 0;
      _attempts = 0;
      _finished = false;
      // ÖNEMLİ (düzeltilen hata): retry ("tekrar başla") sonrası bir önceki
      // oyunun SON sorusundan kalan _showResult/_tapped/_yanlisSecilen burada
      // sıfırlanmıyordu — bu yüzden yeni oyun ilk karede hiçbir dokunuş
      // olmadan doğrudan eski (ve genelde yanlış eşleşen) sonuç banner'ını
      // ("3 hakkını da kullandın") gösteriyordu. Artık her boot'ta (ilk açılış
      // ve retry) TÜM tur-bazlı durum alanları sıfırlanıyor.
      _showResult = false;
      _tapped = null;
    });
  }

  String get _target => _queue[_round];

  void _onTapProvince(TurkeyProvince p) {
    if (_showResult) return;
    context.read<SoundService>().click();
    if (p.bolge == _target) {
      setState(() {
        _tapped = p;
        _showResult = true;
        _score++;
        context.read<StorageService>().addGameAnswer(kBolgeBulGameId, 'cografya', true);
      });
      return;
    }
    _attempts++;
    context.read<StorageService>().addGameAnswer(kBolgeBulGameId, 'cografya', false);
    if (!_yanlisSecilen.any((x) => x.id == p.id)) _yanlisSecilen.add(p);
    if (_attempts >= kMapMaxAttempts) {
      _kaydetYanlis();
      setState(() {
        _tapped = p;
        _showResult = true;
      });
    } else {
      // Kullanıcı isteği: ilk yanlış işaret 2. seçime kadar KALSIN;
      // alt uyarı (haritaBekleyenAfis) pendingNotice ile gösterilir.
      setState(() {});
    }
  }

  void _kaydetYanlis() {
    if (_yanlisSecilen.isEmpty) return;
    haritaYanlisKaydet(
      context,
      soru: '"$_target" Bölgesi\'nden bir il seç',
      dogruId: '',
      dogruAd: '$_target Bölgesi',
      secilenIds: _yanlisSecilen.map((e) => e.id).toList(),
      secilenAdlar: _yanlisSecilen.map((e) => e.ad).toList(),
      modId: kBolgeBulGameId,
      modAd: 'Bölgeyi Bul',
    );
  }

  void _next() {
    context.read<SoundService>().click();
    if (_round + 1 >= _queue.length) {
      setState(() => _finished = true);
      return;
    }
    setState(() {
      _round++;
      _tapped = null;
      _showResult = false;
      _attempts = 0;
      _yanlisSecilen.clear();
    });
  }

  void _retry() {
    setState(() {
      _booted = false;
      _locked = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  @override
  Widget build(BuildContext context) {
    if (_locked) {
      return LockedFeatureCard(
        gameId: kMapGameId,
        oyunAdi: 'Harita Oyunu',
        onUnlocked: _retry,

        title: 'Bölgeyi Bul',
        desc: "Bugünkü $kFreeGameDailyLimit ücretsiz harita oyunu hakkını kullandın. Yarın tekrar oyna ya da Premium'a geçip sınırsız oyna.",
      );
    }
    if (!_booted) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_finished) {
      return MapQuizResult(
        title: '🧭 Bölgeyi Bul',
        modeId: kBolgeBulGameId,
        score: _score,
        total: _queue.length,
        onRetry: _retry,
      );
    }
    return _buildRound(context);
  }

  Widget _buildRound(BuildContext context) {
    final colors = context.watch<ThemeProvider>().colors;
    final mapRenk = mapHighlightColor(context);
    return MapQuizScaffold(
      title: '🧭 Bölgeyi Bul',
      promptText: '"$_target" Bölgesi\'nden bir il seç!',
      statusText: 'Soru ${_round + 1}/${_queue.length} • Skor: $_score'
          '${_showResult ? "" : " • Hak: ${kMapMaxAttempts - _attempts}/$kMapMaxAttempts"}',
      palette: mapModePaletteFor(kBolgeBulGameId),
      howToPlay: _kHowToPlay,
      map: TurkeyMapCanvas(
        provinces: kTurkeyProvinces,
        colorFor: (p) {
          if (!_showResult) {
            if (_yanlisSecilen.any((x) => x.id == p.id)) return colors.danger;
            return mapRenk.withValues(alpha: 0.32);
          }
          if (p.bolge == _target) return regionColor(_target).withValues(alpha: 0.75);
          return colors.violet.withValues(alpha: 0.12);
        },
        overlayFor: (p) {
          if (!_showResult || p.id != _tapped?.id) return null;
          final correct = _tapped?.bolge == _target;
          return Text(correct ? '✅' : '❌', style: const TextStyle(fontSize: 13));
        },
        onTap: _onTapProvince,
      ),
      feedback: _showResult ? _buildFeedback(colors) : null,
      pendingNotice: (!_showResult && _yanlisSecilen.isNotEmpty)
          ? haritaBekleyenAfis(context,
              secilenAd: _yanlisSecilen.last.ad,
              kalanHak: kMapMaxAttempts - _attempts)
          : null,
    );
  }

  Widget _buildFeedback(KpssColors colors) {
    final correct = _tapped?.bolge == _target;
    return haritaSonucAfisi(
      context,
      dogru: correct,
      baslik: correct
          ? '${_tapped?.ad}, $_target Bölgesi\'ndedir.'
          : '${_tapped?.ad}, ${_tapped?.bolge} Bölgesi\'nde (aranan: $_target).',
      aciklama: (!correct && _yanlisSecilen.isNotEmpty)
          ? haritaYanlisSebebi(kBolgeBulGameId, '$_target Bölgesi',
              _yanlisSecilen.map((e) => e.ad).toList())
          : null,
      sonSoru: _round + 1 >= _queue.length,
      onNext: _next,
    );
  }
}
