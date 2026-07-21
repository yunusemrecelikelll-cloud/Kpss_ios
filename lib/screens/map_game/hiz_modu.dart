import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/turkey_map_data.dart';
import '../../services/sound_service.dart';
import '../../services/storage_service.dart';
import '../../theme/theme_provider.dart';
import '../quick_modes/quick_modes_shared.dart' show GameResultStat;
import '../tools_hub_screen.dart';
import 'iklim_avi_mode.dart' show IklimSorusu, kIklimSorulari;
import 'map_shared.dart';
import 'urun_haritasi_mode.dart' show UrunEsleme, kUrunEslemeleri;

const String _kHowToPlay =
    '60 saniye boyunca İli Bul, Bölgeyi Bul, Komşu İl, Ürün Haritası ve İklim '
    'Avı modlarının soru havuzundan karışık, art arda sorular gelir. Dokunduğun '
    'il 1 saniye boyunca renklenir (doğruysa yeşil, yanlışsa kırmızı — yanlışta '
    'doğru cevap da yeşil yanar), sonra sıradaki soru gelir. Bu 1 saniye boyunca '
    'geri sayım DURUR, yani tam 60 saniye oynarsın; süre bitince toplam skorun görünür.';

/// Mod 8 — "60 Saniyede Türkiye": diğer mini oyun modlarının (İli Bul,
/// Bölgeyi Bul, Komşu İl, Ürün Haritası, İklim Avı) soru havuzundan karışık,
/// art arda sorular gelir; 60 saniye boyunca ne kadar çok doğru cevap
/// verirsen skorun o kadar yüksek olur.
abstract class _HizPrompt {
  String get metin;

  /// Sorunun hangi konu başlığından geldiği — oyun sonunda "en çok nerede
  /// yanlış yaptın, neye çalışmalısın" yorumunu üretmek için yanlışlar bu
  /// başlığa göre gruplanır.
  String get kategori;

  bool dogruMu(TurkeyProvince p);
}

class _IlHiz extends _HizPrompt {
  final TurkeyProvince hedef;
  _IlHiz(this.hedef);
  @override
  String get metin => '"${hedef.ad}" ilini bul!';
  @override
  String get kategori => 'İl konumları';
  @override
  bool dogruMu(TurkeyProvince p) => p.id == hedef.id;
}

class _BolgeHiz extends _HizPrompt {
  final String bolge;
  _BolgeHiz(this.bolge);
  @override
  String get metin => '"$bolge" Bölgesi\'nden bir il seç!';
  @override
  String get kategori => 'Bölgeler';
  @override
  bool dogruMu(TurkeyProvince p) => p.bolge == bolge;
}

class _KomsuHiz extends _HizPrompt {
  final TurkeyProvince hedef;
  _KomsuHiz(this.hedef);
  @override
  String get metin => '"${hedef.ad}"nin bir komşusunu seç!';
  @override
  String get kategori => 'Komşu iller';
  @override
  bool dogruMu(TurkeyProvince p) => hedef.komsular.contains(p.id);
}

class _UrunHiz extends _HizPrompt {
  final String urun;
  final List<String> ilIds;
  _UrunHiz(this.urun, this.ilIds);
  @override
  String get metin => '"$urun" ürünüyle özdeşleşen ili seç!';
  @override
  String get kategori => 'Tarım ürünleri';
  @override
  bool dogruMu(TurkeyProvince p) => ilIds.contains(p.id);
}

/// İklim sorusu — artık iklimin ADINI söyleyen basit eşleştirme yerine, İklim
/// Avı modunun yeni soru havuzundaki (bkz. iklim_avi_mode.dart
/// [kIklimSorulari]) ÇIKARIM GEREKTİREN tarifleri kullanır.
class _IklimHiz extends _HizPrompt {
  final IklimSorusu soru;
  _IklimHiz(this.soru);
  @override
  String get metin => soru.soru;
  @override
  String get kategori => 'İklim bilgisi';
  @override
  bool dogruMu(TurkeyProvince p) => soru.dogruIller.contains(p.id);
}

List<_HizPrompt> _generatePromptBatch(Random rnd) {
  final list = <_HizPrompt>[];
  final komsuPool = kTurkeyProvinces.where((p) => p.komsular.length >= 2).toList();
  for (final p in (List<TurkeyProvince>.from(kTurkeyProvinces)..shuffle(rnd)).take(10)) {
    list.add(_IlHiz(p));
  }
  for (final b in (List<String>.from(kTurkeyRegions)..shuffle(rnd)).take(7)) {
    list.add(_BolgeHiz(b));
  }
  for (final p in (List<TurkeyProvince>.from(komsuPool)..shuffle(rnd)).take(7)) {
    list.add(_KomsuHiz(p));
  }
  for (final u in (List<UrunEsleme>.from(kUrunEslemeleri)..shuffle(rnd)).take(7)) {
    list.add(_UrunHiz(u.urun, u.ilIds));
  }
  for (final s in (List<IklimSorusu>.from(kIklimSorulari)..shuffle(rnd)).take(5)) {
    list.add(_IklimHiz(s));
  }
  list.shuffle(rnd);
  return list;
}

const int kHizSuresi = 60;

class HizliTurkiyeScreen extends StatefulWidget {
  const HizliTurkiyeScreen({super.key});

  @override
  State<HizliTurkiyeScreen> createState() => _HizliTurkiyeScreenState();
}

class _HizliTurkiyeScreenState extends State<HizliTurkiyeScreen> {
  bool _locked = false;
  bool _booted = false;
  bool _finished = false;
  int _secondsLeft = kHizSuresi;
  int _score = 0;
  int _wrong = 0;
  int _attempts = 0;
  final _rnd = Random();
  final List<_HizPrompt> _queue = [];
  _HizPrompt? _current;

  /// Son cevabın doğru mu yanlış mı olduğu — ✓/✗ geri bildirim satırı ve
  /// haritanın renklenmesi için. null ise henüz cevap verilmemiştir.
  bool? _sonCevapDogruMu;

  // ── Cevap geri bildirimi (1 saniye) ───────────────────────────────────────
  // Kullanıcı bir ile dokunduğunda seçtiği il 1 saniye boyunca renklenir
  // (doğruysa yeşil, yanlışsa kırmızı; yanlışta DOĞRU cevap da yeşil gösterilir
  // ki öğretici olsun). Bu 1 saniye boyunca GERİ SAYIM DURUR — kullanıcı gerçek
  // 60 saniyeyi oynar, geri bildirim süreden yemez.
  static const Duration _kGeriBildirimSuresi = Duration(seconds: 1);

  /// Geri bildirim gösterilirken true — bu sırada yeni dokunuşlar yok sayılır.
  bool _geriBildirimAktif = false;

  /// Kullanıcının DOKUNDUĞU ilin kimliği.
  String? _secilenIlId;

  /// Yanlış cevapta yeşil gösterilecek doğru il(ler).
  Set<String> _dogruIlIdleri = {};

  Timer? _geriBildirimTimer;

  /// Yanlış yapılan soruların konu başlığına göre sayımı — oyun sonundaki
  /// "neye çalışmalısın" yorumunu üretir.
  final Map<String, int> _yanlisKategoriler = {};

  /// Bu turda kırılan yeni bir rekor var mı (sonuç ekranında vurgulanır).
  bool _yeniRekor = false;
  int _oncekiRekor = 0;

  Timer? _ticker;
  DateTime? _sessionStart;

  @override
  void initState() {
    super.initState();
    _sessionStart = DateTime.now();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _geriBildirimTimer?.cancel();
    final start = _sessionStart;
    if (start != null) {
      context.read<StorageService>().addGameTimeSpent(kHizliTurkiyeGameId, DateTime.now().difference(start));
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
    _queue
      ..clear()
      ..addAll(_generatePromptBatch(_rnd));
    setState(() {
      _booted = true;
      _finished = false;
      _secondsLeft = kHizSuresi;
      _score = 0;
      _wrong = 0;
      _attempts = 0;
      _sonCevapDogruMu = null;
      _geriBildirimAktif = false;
      _secilenIlId = null;
      _dogruIlIdleri = {};
      _yanlisKategoriler.clear();
      _yeniRekor = false;
      _oncekiRekor = context.read<StorageService>().getHighScore(kHizliTurkiyeGameId);
      _current = _popNext();
    });
    context.read<SoundService>().resetTickPhase();
    _geriBildirimTimer?.cancel();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  _HizPrompt _popNext() {
    if (_queue.isEmpty) _queue.addAll(_generatePromptBatch(_rnd));
    return _queue.removeLast();
  }

  void _tick() {
    if (!mounted) return;
    setState(() => _secondsLeft--);
    if (_secondsLeft <= 5 && _secondsLeft > 0) {
      context.read<SoundService>().tick();
    }
    if (_secondsLeft <= 0) {
      _ticker?.cancel();
      _turuBitir();
    }
  }

  /// Süre bittiğinde skoru kalıcı olarak kaydeder (rekor + son tur dağılımı)
  /// ve sonuç ekranına geçer.
  Future<void> _turuBitir() async {
    _ticker?.cancel();
    _geriBildirimTimer?.cancel();
    final storage = context.read<StorageService>();
    final rekorKirildi = await storage.submitHighScore(kHizliTurkiyeGameId, _score);
    await storage.setLastRoundStats(kHizliTurkiyeGameId, correct: _score, wrong: _wrong);
    if (!mounted) return;
    setState(() {
      _yeniRekor = rekorKirildi;
      _finished = true;
    });
  }

  /// Dokunulduğu ANDA cevabı işler; ardından 1 saniyelik geri bildirim gösterip
  /// sıradaki soruya geçer.
  ///
  /// GECİKME YOK: skor/doğruluk hesabı ve seçilen ilin renklenmesi dokunuşla
  /// AYNI karede olur (eskiden burada 260 ms'lik bir `Future.delayed` vardı ve
  /// "tıklayınca hemen seçmiyor" hissi veriyordu — geri getirilmedi). Gecikme
  /// yalnızca seçimden SONRA, geri bildirimi görebilmek için vardır ve bu süre
  /// boyunca GERİ SAYIM DURUR: kullanıcı gerçekten 60 saniye oynar.
  void _onTapProvince(TurkeyProvince p) {
    if (_finished || _current == null || _geriBildirimAktif) return;
    context.read<SoundService>().click();
    final soru = _current!;
    final correct = soru.dogruMu(p);
    if (!correct) {
      _yanlisKategoriler[soru.kategori] = (_yanlisKategoriler[soru.kategori] ?? 0) + 1;
    }

    // Geri sayımı duraklat — geri bildirim süresi oyundan çalmasın.
    _ticker?.cancel();
    _ticker = null;

    setState(() {
      _attempts++;
      if (correct) {
        _score++;
      } else {
        _wrong++;
      }
      _sonCevapDogruMu = correct;
      _geriBildirimAktif = true;
      _secilenIlId = p.id;
      // Yanlışta doğru cevap(lar) da yeşil gösterilir — öğretici olsun diye.
      // (Bölge/ürün/iklim sorularında birden fazla il doğru olabilir.)
      _dogruIlIdleri = correct
          ? {p.id}
          : kTurkeyProvinces.where(soru.dogruMu).map((e) => e.id).toSet();
    });

    _geriBildirimTimer?.cancel();
    _geriBildirimTimer = Timer(_kGeriBildirimSuresi, () {
      if (!mounted || _finished) return;
      setState(() {
        _geriBildirimAktif = false;
        _secilenIlId = null;
        _dogruIlIdleri = {};
        _current = _popNext();
      });
      _basaSarmadanTickerBaslat();
    });
  }

  /// Geri bildirim bittikten sonra geri sayımı KALDIĞI yerden sürdürür
  /// (`_secondsLeft` sıfırlanmaz, sadece saniye darbeleri yeniden başlar).
  void _basaSarmadanTickerBaslat() {
    _ticker?.cancel();
    if (!mounted || _finished || _secondsLeft <= 0) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  /// Oyun sonunda doğru/yanlış dağılımına ve yanlışların hangi konuda
  /// yoğunlaştığına göre kişiye özel bir değerlendirme metni üretir.
  String _sonucYorumu() {
    final b = StringBuffer();
    // NOT: Doğru/yanlış/isabet sayıları artık sonuç ekranının [DsStatStrip]
    // şeridinde gösteriliyor; burada TEKRAR yazılmaz, sadece yorum üretilir.
    if (_attempts == 0) {
      b.writeln('Hiç cevap vermedin — haritaya dokunarak başlayabilirsin.');
      return b.toString().trim();
    }

    final oran = (_score * 100 / _attempts).round();

    if (oran >= 85) {
      b.writeln('Harika! Türkiye haritasına gerçekten hâkimsin.');
    } else if (oran >= 60) {
      b.writeln('İyi gidiyorsun. Biraz daha tekrarla üst seviyeye çıkarsın.');
    } else if (oran >= 40) {
      b.writeln('Fena değil ama haritayı daha sık çalışman gerekiyor.');
    } else {
      b.writeln('Temelden tekrar etmelisin. "Haritadan Öğren" bölümü iyi bir başlangıç olur.');
    }

    if (_yanlisKategoriler.isNotEmpty) {
      final sirali = _yanlisKategoriler.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final enZayif = sirali.first;
      b.writeln();
      b.writeln('📌 En çok "${enZayif.key}" konusunda zorlandın '
          '(${enZayif.value} yanlış). Önce buraya çalış.');
      if (sirali.length > 1 && sirali[1].value > 0) {
        b.writeln('Ardından "${sirali[1].key}" konusunu tekrar et.');
      }
    }
    return b.toString().trim();
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
        title: '60 Saniyede Türkiye',
        desc: "Bugünkü $kFreeGameDailyLimit ücretsiz harita oyunu hakkını kullandın. Yarın tekrar oyna ya da Premium'a geçip sınırsız oyna.",
      );
    }
    if (!_booted) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_finished) {
      final sonucColors = context.watch<ThemeProvider>().colors;
      final rekor = context.watch<StorageService>().getHighScore(kHizliTurkiyeGameId);
      final isabet = _attempts == 0 ? 0 : (_score * 100 / _attempts).round();
      return MapSessionResult(
        title: '⏱️ 60 Saniyede Türkiye',
        emoji: _yeniRekor ? '🏆' : (_score >= 15 ? '🎉' : (_score >= 8 ? '💪' : '📚')),
        headline: _yeniRekor
            ? 'Yeni rekor kırdın!'
            : (_score >= 15 ? 'Süre doldu — harika skor!' : 'Süre doldu!'),
        message: '60 saniyede $_attempts soru cevapladın.',
        stats: [
          GameResultStat(emoji: '✅', value: '$_score', label: 'Doğru', color: sonucColors.success),
          GameResultStat(emoji: '❌', value: '$_wrong', label: 'Yanlış', color: sonucColors.danger),
          GameResultStat(emoji: '🎯', value: '%$isabet', label: 'İsabet'),
        ],
        highScore: rekor,
        newRecord: _yeniRekor,
        note: _sonucYorumu(),
        onRetry: _retry,
        palette: mapModePaletteFor(kHizliTurkiyeGameId),
      );
    }
    final colors = context.watch<ThemeProvider>().colors;
    final palette = mapModePaletteFor(kHizliTurkiyeGameId);
    return Scaffold(
      appBar: AppBar(
        title: const Text('⏱️ 60 Saniyede Türkiye'),
        actions: [
          IconButton(
            tooltip: 'Nasıl oynanır?',
            icon: const Icon(Icons.help_outline),
            onPressed: () => showHowToPlaySheet(context, title: '60 Saniyede Türkiye', body: _kHowToPlay),
          ),
        ],
      ),
      body: Container(
        decoration: mapModeBackgroundDecoration(palette, colors.isLight),
        child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('⏳ $_secondsLeft sn', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _secondsLeft <= 10 ? colors.danger : colors.text)),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        children: [
                          Text('✅ $_score',
                              style: TextStyle(fontWeight: FontWeight.w800, color: colors.success)),
                          const SizedBox(width: 10),
                          Text('❌ $_wrong',
                              style: TextStyle(fontWeight: FontWeight.w800, color: colors.danger)),
                        ],
                      ),
                      Text('🏆 Rekor: $_oncekiRekor',
                          style: TextStyle(fontSize: 11.5, color: colors.textFaint)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(_current?.metin ?? '', style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Expanded(
                child: TurkeyMapCanvas(
                  provinces: kTurkeyProvinces,
                  // 1 saniyelik geri bildirim: seçilen il doğruysa yeşil,
                  // yanlışsa kırmızı; yanlışta doğru cevap(lar) da yeşil yanar.
                  colorFor: (p) {
                    if (_geriBildirimAktif) {
                      if (p.id == _secilenIlId) {
                        return (_sonCevapDogruMu == true ? colors.success : colors.danger)
                            .withValues(alpha: 0.85);
                      }
                      if (_dogruIlIdleri.contains(p.id)) {
                        return colors.success.withValues(alpha: 0.55);
                      }
                    }
                    return colors.violet.withValues(alpha: 0.32);
                  },
                  onTap: _onTapProvince,
                ),
              ),
              // Akışı DURDURMAYAN geri bildirim: sonraki soru zaten ekranda,
              // bu satır sadece bir önceki cevabın sonucunu gösterir.
              SizedBox(
                height: 24,
                child: _sonCevapDogruMu == null
                    ? null
                    : Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          _sonCevapDogruMu! ? '✅ Doğru!' : '❌ Yanlış!',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: _sonCevapDogruMu! ? colors.success : colors.danger,
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}
