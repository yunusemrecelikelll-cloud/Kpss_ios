import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/turkey_map_data.dart';
import '../../services/sound_service.dart';
import '../../services/storage_service.dart';
import '../../theme/theme_provider.dart';
import '../tools_hub_screen.dart';
import 'iklim_avi_mode.dart' show kIklimKategorileri;
import 'map_shared.dart';
import 'urun_haritasi_mode.dart' show UrunEsleme, kUrunEslemeleri;

const String _kHowToPlay =
    '60 saniye boyunca İli Bul, Bölgeyi Bul, Komşu İl, Ürün Haritası ve İklim '
    'Avı modlarının soru havuzundan karışık, art arda sorular gelir. Doğru '
    'cevaplayınca hemen sıradaki soruya geçilir; süre bitince toplam skorun görünür.';

/// Mod 8 — "60 Saniyede Türkiye": diğer mini oyun modlarının (İli Bul,
/// Bölgeyi Bul, Komşu İl, Ürün Haritası, İklim Avı) soru havuzundan karışık,
/// art arda sorular gelir; 60 saniye boyunca ne kadar çok doğru cevap
/// verirsen skorun o kadar yüksek olur.
abstract class _HizPrompt {
  String get metin;
  bool dogruMu(TurkeyProvince p);
}

class _IlHiz extends _HizPrompt {
  final TurkeyProvince hedef;
  _IlHiz(this.hedef);
  @override
  String get metin => '"${hedef.ad}" ilini bul!';
  @override
  bool dogruMu(TurkeyProvince p) => p.id == hedef.id;
}

class _BolgeHiz extends _HizPrompt {
  final String bolge;
  _BolgeHiz(this.bolge);
  @override
  String get metin => '"$bolge" Bölgesi\'nden bir il seç!';
  @override
  bool dogruMu(TurkeyProvince p) => p.bolge == bolge;
}

class _KomsuHiz extends _HizPrompt {
  final TurkeyProvince hedef;
  _KomsuHiz(this.hedef);
  @override
  String get metin => '"${hedef.ad}"nin bir komşusunu seç!';
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
  bool dogruMu(TurkeyProvince p) => ilIds.contains(p.id);
}

class _IklimHiz extends _HizPrompt {
  final String kategori;
  _IklimHiz(this.kategori);
  @override
  String get metin => '"$kategori" iklimi görülen bir il seç!';
  @override
  bool dogruMu(TurkeyProvince p) => p.iklim.contains(kategori);
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
  for (final k in (List<String>.from(kIklimKategorileri)..shuffle(rnd)).take(5)) {
    list.add(_IklimHiz(k));
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
  int _attempts = 0;
  final _rnd = Random();
  final List<_HizPrompt> _queue = [];
  _HizPrompt? _current;
  bool _flash = false;
  bool _flashCorrect = false;
  TurkeyProvince? _lastTapped;
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
      _attempts = 0;
      _flash = false;
      _flashCorrect = false;
      _lastTapped = null;
      _current = _popNext();
    });
    context.read<SoundService>().resetTickPhase();
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
      setState(() => _finished = true);
    }
  }

  void _onTapProvince(TurkeyProvince p) {
    if (_flash || _finished || _current == null) return;
    context.read<SoundService>().click();
    final correct = _current!.dogruMu(p);
    setState(() {
      _attempts++;
      if (correct) _score++;
      _flash = true;
      _flashCorrect = correct;
      _lastTapped = p;
    });
    Future.delayed(const Duration(milliseconds: 260), () {
      if (!mounted || _finished) return;
      setState(() {
        _flash = false;
        _lastTapped = null;
        _current = _popNext();
      });
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
        title: '60 Saniyede Türkiye',
        desc: "Bugünkü $kFreeGameDailyLimit ücretsiz harita oyunu hakkını kullandın. Yarın tekrar oyna ya da Premium'a geçip sınırsız oyna.",
      );
    }
    if (!_booted) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_finished) {
      return MapSessionResult(
        title: '⏱️ 60 Saniyede Türkiye',
        emoji: _score >= 15 ? '🎉' : '📚',
        message: '$_attempts denemede $_score doğru cevap verdin!',
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
                  Text('Skor: $_score / $_attempts', style: const TextStyle(fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 8),
              Text(_current?.metin ?? '', style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Expanded(
                child: TurkeyMapCanvas(
                  provinces: kTurkeyProvinces,
                  colorFor: (p) {
                    if (!_flash) return colors.violet.withValues(alpha: 0.32);
                    final match = _current?.dogruMu(p) ?? false;
                    if (match) return colors.success;
                    if (p.id == _lastTapped?.id) return colors.danger;
                    return colors.violet.withValues(alpha: 0.12);
                  },
                  onTap: _onTapProvince,
                ),
              ),
              if (_flash)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _flashCorrect ? '✅ Doğru!' : '❌ Yanlış!',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: _flashCorrect ? colors.success : colors.danger,
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
