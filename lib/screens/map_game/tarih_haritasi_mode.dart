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
  String? _flashWrongId;
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
      _flashWrongId = null;
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
      });
      return;
    }
    _attempts++;
    if (_attempts >= kMapMaxAttempts) {
      setState(() {
        _tapped = p;
        _showResult = true;
      });
    } else {
      _flashWrong(p.id);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('❌ Yanlış, tekrar dene! (${kMapMaxAttempts - _attempts} hakkın kaldı)'),
        duration: const Duration(milliseconds: 1400),
      ));
    }
  }

  /// Yanlış dokunulan ili kısa süreliğine kırmızı yakıp söndürür.
  void _flashWrong(String id) {
    setState(() => _flashWrongId = id);
    Future.delayed(const Duration(milliseconds: 550), () {
      if (mounted && _flashWrongId == id) setState(() => _flashWrongId = null);
    });
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
      _flashWrongId = null;
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
      return const LockedFeatureCard(
        title: 'Tarih Haritası',
        desc: "Bugünkü $kFreeGameDailyLimit ücretsiz harita oyunu hakkını kullandın. Yarın tekrar oyna ya da Premium'a geçip sınırsız oyna.",
      );
    }
    if (!_booted) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_finished) {
      return MapSessionResult(
        title: '🕰️ Tarih Haritası',
        emoji: _score >= (_queue.length * 0.7) ? '🎉' : '📚',
        message: '${_queue.length} sorudan $_score tanesini doğru bildin.',
        onRetry: _retry,
        palette: mapModePaletteFor(kTarihHaritasiGameId),
      );
    }
    return _buildRound(context);
  }

  Widget _buildRound(BuildContext context) {
    final colors = context.watch<ThemeProvider>().colors;
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
            if (p.id == _flashWrongId) return colors.danger;
            return colors.violet.withValues(alpha: 0.32);
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
    );
  }

  Widget _buildFeedback(KpssColors colors, String targetName) {
    final correct = _target.ilId == _tapped?.id;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: (correct ? colors.success : colors.danger).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: correct ? colors.success : colors.danger),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            correct ? '✅ Doğru! $targetName.' : '❌ $kMapMaxAttempts hakkını da kullandın. Doğru cevap: $targetName.',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton(
              onPressed: _next,
              child: Text(_round + 1 < _queue.length ? 'Sonraki Soru →' : 'Bitir'),
            ),
          ),
        ],
      ),
    );
  }
}
