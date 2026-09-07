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

const int kTarihRounds = 8;

const String _kHowToPlay =
    'Millî Mücadele döneminde yaşanan bir olayın adı yazar (ör. "Sivas '
    'Kongresi"). Olayın gerçekleştiği ili haritada işaretle. Yanlış dokunursan '
    '3 hakkın vardır; üçünü de kullanırsan doğru il gösterilir.';

/// Mod 6 — "Tarih Haritası": Millî Mücadele/Kurtuluş Savaşı döneminin
/// TÜRKİYE SINIRLARI İÇİNDE yaşanan olaylarından biri sorulur (yurt dışında
/// geçen olaylar — ör. Lozan — bilinçli olarak KULLANILMAMIŞTIR).
class TarihOlayi {
  final String olay;
  final String ilId;
  const TarihOlayi(this.olay, this.ilId);
}

const List<TarihOlayi> kTarihOlaylari = [
  TarihOlayi('Amasya Genelgesi (22 Haziran 1919)', 'amasya'),
  TarihOlayi('Amasya Görüşmeleri', 'amasya'),
  TarihOlayi('Havza Genelgesi', 'samsun'),
  TarihOlayi("Mustafa Kemal'in Samsun'a Çıkışı (19 Mayıs 1919)", 'samsun'),
  TarihOlayi('Erzurum Kongresi', 'erzurum'),
  TarihOlayi('Sivas Kongresi', 'sivas'),
  TarihOlayi('I. İnönü Muharebesi', 'eskisehir'),
  TarihOlayi('II. İnönü Muharebesi', 'eskisehir'),
  TarihOlayi('Sakarya Meydan Muharebesi', 'ankara'),
  TarihOlayi("Büyük Taarruz'un Başladığı Kocatepe", 'afyonkarahisar'),
  TarihOlayi('Başkomutanlık Meydan Muharebesi (Dumlupınar)', 'kutahya'),
  TarihOlayi('Çanakkale Savaşları (1915)', 'canakkale'),
  TarihOlayi('Malazgirt Meydan Muharebesi (1071)', 'mus'),
  TarihOlayi("TBMM'nin Açılışı (23 Nisan 1920)", 'ankara'),
  TarihOlayi("Antep Savunması (\"Gazi\" unvanı)", 'gaziantep'),
  TarihOlayi("Urfa'nın Kurtuluşu (\"Şanlı\" unvanı)", 'sanliurfa'),
  TarihOlayi("Maraş'ın Kurtuluşu (\"Kahraman\" unvanı)", 'kahramanmaras'),
  TarihOlayi('Mudanya Mütarekesi', 'bursa'),
];

class TarihHaritasiScreen extends StatefulWidget {
  const TarihHaritasiScreen({super.key});

  @override
  State<TarihHaritasiScreen> createState() => _TarihHaritasiScreenState();
}

class _TarihHaritasiScreenState extends State<TarihHaritasiScreen> {
  bool _locked = false;
  bool _booted = false;
  bool _finished = false;
  int _round = 0;
  int _score = 0;
  int _attempts = 0;
  late List<TarihOlayi> _queue;
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
      context.read<StorageService>().addGameTimeSpent(kTarihHaritasiGameId, DateTime.now().difference(start));
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
    final pool = List<TarihOlayi>.from(kTarihOlaylari)..shuffle(Random());
    setState(() {
      _queue = pool.take(kTarihRounds).toList();
      _booted = true;
      _round = 0;
      _score = 0;
      _attempts = 0;
      _finished = false;
      // bkz. bolge_bul_mode.dart — retry sonrası bir önceki oyunun son
      // sonuç durumunun sızmaması için tur-bazlı alanlar burada da sıfırlanır.
      _showResult = false;
      _tapped = null;
    });
  }

  TarihOlayi get _target => _queue[_round];

  void _onTapProvince(TurkeyProvince p) {
    if (_showResult) return;
    context.read<SoundService>().click();
    if (_target.ilId == p.id) {
      setState(() {
        _tapped = p;
        _showResult = true;
        _score++;
        context.read<StorageService>().addGameAnswer(kTarihHaritasiGameId, 'tarih', true);
      });
      return;
    }
    _attempts++;
    if (!_yanlisSecilen.any((x) => x.id == p.id)) _yanlisSecilen.add(p);
    context.read<StorageService>().addGameAnswer(kTarihHaritasiGameId, 'tarih', false);
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
    final dogruIl = kTurkeyProvinces.firstWhere((p) => p.id == _target.ilId);
    haritaYanlisKaydet(
      context,
      soru: _target.olay,
      dogruId: _target.ilId,
      dogruAd: dogruIl.ad,
      secilenIds: _yanlisSecilen.map((e) => e.id).toList(),
      secilenAdlar: _yanlisSecilen.map((e) => e.ad).toList(),
      modId: kTarihHaritasiGameId,
      modAd: 'Tarih Haritası',
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
      _yanlisSecilen.clear();
      _tapped = null;
      _showResult = false;
      _attempts = 0;
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

        title: 'Tarih Haritası',
        desc: "Bugünkü $kFreeGameDailyLimit ücretsiz harita oyunu hakkını kullandın. Yarın tekrar oyna ya da Premium'a geçip sınırsız oyna.",
      );
    }
    if (!_booted) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_finished) {
      return MapQuizResult(
        title: '🕰️ Tarih Haritası',
        modeId: kTarihHaritasiGameId,
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
    final targetName = kTurkeyProvinces.firstWhere((p) => p.id == _target.ilId).ad;
    return MapQuizScaffold(
      title: '🕰️ Tarih Haritası',
      promptText: '"${_target.olay}" hangi ilde yaşanmıştır?',
      statusText: 'Soru ${_round + 1}/${_queue.length} • Skor: $_score'
          '${_showResult ? "" : " • Hak: ${kMapMaxAttempts - _attempts}/$kMapMaxAttempts"}',
      palette: mapModePaletteFor(kTarihHaritasiGameId),
      howToPlay: _kHowToPlay,
      map: TurkeyMapCanvas(
        provinces: kTurkeyProvinces,
        colorFor: (p) {
          if (!_showResult) {
            if (_yanlisSecilen.any((x) => x.id == p.id)) return colors.danger;
            return mapRenk.withValues(alpha: 0.32);
          }
          if (p.id == _target.ilId) return colors.success;
          if (p.id == _tapped?.id) return colors.danger;
          return colors.violet.withValues(alpha: 0.12);
        },
        onTap: _onTapProvince,
      ),
      feedback: _showResult
          ? _buildFeedback(colors, targetName)
          : null,
      pendingNotice: (!_showResult && _yanlisSecilen.isNotEmpty)
          ? haritaBekleyenAfis(context,
              secilenAd: _yanlisSecilen.last.ad,
              kalanHak: kMapMaxAttempts - _attempts)
          : null,
    );
  }

  Widget _buildFeedback(KpssColors colors, String targetName) {
    final correct = _target.ilId == _tapped?.id;
    return haritaSonucAfisi(
      context,
      dogru: correct,
      baslik: correct ? 'Doğru! $targetName.' : 'Doğru cevap: $targetName.',
      aciklama: (!correct && _yanlisSecilen.isNotEmpty)
          ? haritaYanlisSebebi(kTarihHaritasiGameId, targetName,
              _yanlisSecilen.map((e) => e.ad).toList())
          : null,
      sonSoru: _round + 1 >= _queue.length,
      onNext: _next,
    );
  }
}
