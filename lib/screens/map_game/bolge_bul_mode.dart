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
      // oyunun SON sorusundan kalan _showResult/_tapped/_flashWrongId burada
      // sıfırlanmıyordu — bu yüzden yeni oyun ilk karede hiçbir dokunuş
      // olmadan doğrudan eski (ve genelde yanlış eşleşen) sonuç banner'ını
      // ("3 hakkını da kullandın") gösteriyordu. Artık her boot'ta (ilk açılış
      // ve retry) TÜM tur-bazlı durum alanları sıfırlanıyor.
      _showResult = false;
      _tapped = null;
      _flashWrongId = null;
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
        title: 'Bölgeyi Bul',
        desc: "Bugünkü $kFreeGameDailyLimit ücretsiz harita oyunu hakkını kullandın. Yarın tekrar oyna ya da Premium'a geçip sınırsız oyna.",
      );
    }
    if (!_booted) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_finished) {
      return MapSessionResult(
        title: '🧭 Bölgeyi Bul',
        emoji: _score >= (_queue.length * 0.7) ? '🎉' : '📚',
        message: '${_queue.length} sorudan $_score tanesini doğru bildin.',
        onRetry: _retry,
        palette: mapModePaletteFor(kBolgeBulGameId),
      );
    }
    return _buildRound(context);
  }

  Widget _buildRound(BuildContext context) {
    final colors = context.watch<ThemeProvider>().colors;
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
            if (p.id == _flashWrongId) return colors.danger;
            return colors.violet.withValues(alpha: 0.32);
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
    );
  }

  Widget _buildFeedback(KpssColors colors) {
    final correct = _tapped?.bolge == _target;
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
                ? '✅ Doğru! ${_tapped?.ad}, $_target Bölgesi\'ndedir.'
                : '❌ $kMapMaxAttempts hakkını da kullandın. ${_tapped?.ad}, ${_tapped?.bolge} Bölgesi\'nde yer alır (aranan: $_target).',
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
