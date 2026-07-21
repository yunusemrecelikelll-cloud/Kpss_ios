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

const int kUrunRounds = 8;

const String _kHowToPlay =
    'Ekranda bir ürün adı yazar (fındık, çay, pamuk gibi). O ürünle en çok '
    'özdeşleşen ili haritada işaretle — bazı ürünlerin birden fazla doğru '
    'ili olabilir. Yanlış dokunursan 3 hakkın vardır.';

/// Mod 5 — "Ürün Haritası": KPSS'de sık çıkan ekonomik coğrafya
/// ürünlerinden biri sorulur, kullanıcı o ürünle özdeşleşen ili haritada
/// işaretler. Küratörlü ve DOĞRULANMIŞ bir eşleşme listesi kullanılır (bazı
/// ürünler birden fazla ilde öne çıktığı için birden fazla doğru cevap kabul
/// edilir).
class UrunEsleme {
  final String urun;
  final List<String> ilIds;
  const UrunEsleme(this.urun, this.ilIds);
}

const List<UrunEsleme> kUrunEslemeleri = [
  UrunEsleme('Çay', ['rize', 'trabzon']),
  UrunEsleme('Fındık', ['giresun', 'ordu']),
  UrunEsleme('Antep Fıstığı', ['gaziantep']),
  UrunEsleme('Kayısı', ['malatya']),
  UrunEsleme('Pamuk', ['sanliurfa', 'adana', 'aydin']),
  UrunEsleme('Zeytin/Zeytinyağı', ['aydin', 'mugla', 'balikesir']),
  UrunEsleme('Kuru İncir', ['aydin']),
  UrunEsleme('Çekirdeksiz Kuru Üzüm', ['manisa']),
  UrunEsleme('Gül (Gül Yağı)', ['isparta']),
  UrunEsleme('Muz', ['mersin']),
  UrunEsleme('Şeftali', ['bursa', 'amasya', 'bilecik']),
  UrunEsleme('Pastırma ve Sucuk', ['kayseri']),
  UrunEsleme('Maraş Dondurması', ['kahramanmaras']),
  UrunEsleme('Kırmızı Toz Biber', ['kahramanmaras']),
  UrunEsleme('Leblebi', ['corum']),
  UrunEsleme('Kaya Tuzu', ['cankiri']),
  UrunEsleme('Taşkömürü Madenciliği', ['zonguldak']),
  UrunEsleme('Demir-Çelik Sanayii', ['karabuk', 'sivas']),
  UrunEsleme('Lületaşı', ['eskisehir']),
  UrunEsleme('Halı Dokumacılığı', ['usak', 'kirsehir']),
  UrunEsleme('Çini/Seramik', ['kutahya']),
  UrunEsleme('Otlu Peynir', ['van']),
  UrunEsleme('Kaşar Peyniri', ['kars', 'ardahan']),
  UrunEsleme('Tiftik (Ankara Keçisi)', ['ankara']),
  UrunEsleme('Petrol Rafinerisi', ['batman']),
  UrunEsleme('Kivi', ['yalova']),
  // Aşağıdaki maddeler lib/data/learn_map_data.dart'taki "Haritadan Öğren"
  // kütüphanesiyle AYNI, TÜİK/resmi kuruma dayanan doğrulanmış verilerden
  // türetilmiştir (bkz. o dosyadaki [LearnMapItem.kaynak] alanları) — "daha
  // fazla seçenek" isteği üzerine soru havuzu genişletildi.
  UrunEsleme('Elma', ['isparta', 'karaman']),
  UrunEsleme('Ayçiçeği', ['tekirdag', 'edirne', 'kirklareli']),
  UrunEsleme('Tütün', ['adiyaman', 'samsun', 'batman']),
  UrunEsleme('Haşhaş', ['afyonkarahisar', 'burdur', 'denizli', 'kutahya', 'usak']),
  UrunEsleme('Bor', ['eskisehir', 'kutahya', 'balikesir']),
  UrunEsleme('Krom', ['elazig']),
  UrunEsleme('Sığır (Büyükbaş Hayvancılık)', ['konya', 'izmir', 'erzurum']),
  UrunEsleme('Koyun (Küçükbaş Hayvancılık)', ['van', 'konya', 'sanliurfa']),
  UrunEsleme('Bal (Arıcılık)', ['ordu', 'adana', 'mugla']),
  UrunEsleme('Doğalgaz', ['zonguldak', 'tekirdag', 'kirklareli']),
  UrunEsleme('Güneş Enerjisi (GES)', ['konya', 'ankara', 'gaziantep']),
  UrunEsleme('Rüzgar Enerjisi (RES)', ['izmir', 'canakkale', 'balikesir']),
  UrunEsleme('Jeotermal Enerji', ['aydin', 'denizli', 'manisa']),
  UrunEsleme('Demir', ['sivas', 'malatya']),
  UrunEsleme('Bakır', ['artvin', 'rize']),
];

class UrunHaritasiScreen extends StatefulWidget {
  const UrunHaritasiScreen({super.key});

  @override
  State<UrunHaritasiScreen> createState() => _UrunHaritasiScreenState();
}

class _UrunHaritasiScreenState extends State<UrunHaritasiScreen> {
  bool _locked = false;
  bool _booted = false;
  bool _finished = false;
  int _round = 0;
  int _score = 0;
  int _attempts = 0;
  late List<UrunEsleme> _queue;
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
      context.read<StorageService>().addGameTimeSpent(kUrunHaritasiGameId, DateTime.now().difference(start));
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
    final pool = List<UrunEsleme>.from(kUrunEslemeleri)..shuffle(Random());
    setState(() {
      _queue = pool.take(kUrunRounds).toList();
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

  UrunEsleme get _target => _queue[_round];

  void _onTapProvince(TurkeyProvince p) {
    if (_showResult) return;
    context.read<SoundService>().click();
    if (_target.ilIds.contains(p.id)) {
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
        title: 'Ürün Haritası',
        desc: "Bugünkü $kFreeGameDailyLimit ücretsiz harita oyunu hakkını kullandın. Yarın tekrar oyna ya da Premium'a geçip sınırsız oyna.",
      );
    }
    if (!_booted) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_finished) {
      return MapQuizResult(
        title: '🌾 Ürün Haritası',
        modeId: kUrunHaritasiGameId,
        score: _score,
        total: _queue.length,
        onRetry: _retry,
      );
    }
    return _buildRound(context);
  }

  Widget _buildRound(BuildContext context) {
    final colors = context.watch<ThemeProvider>().colors;
    return MapQuizScaffold(
      title: '🌾 Ürün Haritası',
      promptText: '"${_target.urun}" ile en çok özdeşleşen ili seç!',
      statusText: 'Soru ${_round + 1}/${_queue.length} • Skor: $_score'
          '${_showResult ? "" : " • Hak: ${kMapMaxAttempts - _attempts}/$kMapMaxAttempts"}',
      palette: mapModePaletteFor(kUrunHaritasiGameId),
      howToPlay: _kHowToPlay,
      map: TurkeyMapCanvas(
        provinces: kTurkeyProvinces,
        colorFor: (p) {
          if (!_showResult) {
            if (p.id == _flashWrongId) return colors.danger;
            return colors.violet.withValues(alpha: 0.32);
          }
          if (_target.ilIds.contains(p.id)) return colors.success;
          if (p.id == _tapped?.id) return colors.danger;
          return colors.violet.withValues(alpha: 0.12);
        },
        onTap: _onTapProvince,
      ),
      feedback: _showResult ? _buildFeedback(colors) : null,
    );
  }

  Widget _buildFeedback(KpssColors colors) {
    final correct = _target.ilIds.contains(_tapped?.id);
    final correctNames = _target.ilIds.map((id) => kTurkeyProvinces.firstWhere((p) => p.id == id).ad).join(', ');
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
            correct ? '✅ Doğru!' : '❌ $kMapMaxAttempts hakkını da kullandın.',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Text('"${_target.urun}" ile öne çıkan il(ler): $correctNames', style: const TextStyle(fontSize: 12.5)),
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
