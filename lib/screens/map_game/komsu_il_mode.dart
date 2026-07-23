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

const int kKomsuIlRounds = 8;

const String _kHowToPlay =
    'Ekranda bir il adı yazar. O ilin GERÇEK komşu illerinden birine dokun '
    '(gösterilen ilin kendisine dokunamazsın). Yanlış dokunursan 3 hakkın vardır; '
    'üçünü de kullanırsan komşu iller yazıyla gösterilir.';

/// Mod 4 — "Komşu İl Oyunu": bir il gösterilir, kullanıcı onun GERÇEK
/// komşularından birini haritada işaretler.
class KomsuIlScreen extends StatefulWidget {
  const KomsuIlScreen({super.key});

  @override
  State<KomsuIlScreen> createState() => _KomsuIlScreenState();
}

class _KomsuIlScreenState extends State<KomsuIlScreen> {
  bool _locked = false;
  bool _booted = false;
  bool _finished = false;
  int _round = 0;
  int _score = 0;
  int _attempts = 0;
  late List<TurkeyProvince> _queue;
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
      context.read<StorageService>().addGameTimeSpent(kKomsuIlGameId, DateTime.now().difference(start));
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
    final pool = kTurkeyProvinces.where((p) => p.komsular.length >= 2).toList()..shuffle(Random());
    setState(() {
      _queue = pool.take(kKomsuIlRounds).toList();
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

  TurkeyProvince get _target => _queue[_round];

  void _onTapProvince(TurkeyProvince p) {
    if (_showResult) return;
    context.read<SoundService>().click();
    if (_target.komsular.contains(p.id)) {
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
      return LockedFeatureCard(
        gameId: kMapGameId,
        oyunAdi: 'Harita Oyunu',
        onUnlocked: _retry,

        title: 'Komşu İl Oyunu',
        desc: "Bugünkü $kFreeGameDailyLimit ücretsiz harita oyunu hakkını kullandın. Yarın tekrar oyna ya da Premium'a geçip sınırsız oyna.",
      );
    }
    if (!_booted) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_finished) {
      return MapQuizResult(
        title: '🤝 Komşu İl Oyunu',
        modeId: kKomsuIlGameId,
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
      title: '🤝 Komşu İl Oyunu',
      promptText: '"${_target.ad}"nin komşularından birini seç!',
      statusText: 'Soru ${_round + 1}/${_queue.length} • Skor: $_score'
          '${_showResult ? "" : " • Hak: ${kMapMaxAttempts - _attempts}/$kMapMaxAttempts"}',
      palette: mapModePaletteFor(kKomsuIlGameId),
      howToPlay: _kHowToPlay,
      map: TurkeyMapCanvas(
        provinces: kTurkeyProvinces,
        // Hedef il haritada HİÇBİR ZAMAN gösterilmez (ne renkle ne ikonla,
        // cevap gösterildikten sonra bile) — sadece yukarıdaki promptText'te
        // ve aşağıdaki geri bildirim metninde yazıyla belirtilir. Kullanıcı
        // komşuluğu kendi coğrafya bilgisiyle bulmalı; haritadan konumunu
        // görüp etraftaki illere bakarak tahmin etmesin.
        colorFor: (p) {
          if (!_showResult) {
            if (p.id == _flashWrongId) return colors.danger;
            return colors.violet.withValues(alpha: 0.32);
          }
          if (_target.komsular.contains(p.id)) return colors.success;
          if (p.id == _tapped?.id) return colors.danger;
          return colors.violet.withValues(alpha: 0.12);
        },
        onTap: (p) {
          if (p.id == _target.id) return; // gösterilen il seçilemez
          _onTapProvince(p);
        },
      ),
      feedback: _showResult ? _buildFeedback(colors) : null,
    );
  }

  Widget _buildFeedback(KpssColors colors) {
    final correct = _target.komsular.contains(_tapped?.id);
    final neighborNames = _target.komsular.map((id) => kTurkeyProvinces.firstWhere((p) => p.id == id).ad).join(', ');
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
            correct
                ? '✅ Doğru! ${_tapped?.ad}, ${_target.ad}\'nin komşusudur.'
                : '❌ $kMapMaxAttempts hakkını da kullandın. ${_tapped?.ad} bir komşu değil.',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Text('${_target.ad}\'nin komşuları: $neighborNames', style: const TextStyle(fontSize: 12.5)),
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
