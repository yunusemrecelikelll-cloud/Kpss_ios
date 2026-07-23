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

const int kIliBulRounds = 8;

const String _kHowToPlay =
    'Zorluk seç (Kolay/Orta/Zor). Ekranda bir il adı yazar; o ili haritada '
    'bulup dokun. Yanlış dokunursan 3 hakkın vardır; üçünü de kullanırsan '
    'doğru cevap gösterilir ve sıradaki soruya geçilir. 8 soru sonunda skorun görünür.';

/// Mod 1 — "İli Bul": kullanıcının en güçlü fikir dediği mod. Haritada
/// gösterilen bir il adını, il düğmelerinden doğru olanına dokunarak bulur.
/// Zorluk: Kolay = büyük şehirler, Orta = İç/Doğu Anadolu, Zor = Karadeniz +
/// küçük iller (bkz. TurkeyProvince.zorluk).
class IliBulScreen extends StatelessWidget {
  const IliBulScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.watch<ThemeProvider>().colors;
    final storage = context.watch<StorageService>();
    final premium = storage.isPremiumUser();
    final left = mapGameDailyLeft(storage);

    return Scaffold(
      appBar: AppBar(
        title: const Text('🔎 İli Bul'),
        actions: [
          IconButton(
            tooltip: 'Nasıl oynanır?',
            icon: const Icon(Icons.help_outline),
            onPressed: () => showHowToPlaySheet(context, title: 'İli Bul', body: _kHowToPlay),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Zorluk seç ve haritada söylenen ili bul. '
              '${premium ? "Sınırsız oynarsın." : "Bugün $left hakkın kaldı."}',
              style: TextStyle(fontSize: 13.5, color: colors.textFaint),
            ),
            const SizedBox(height: 18),
            _DifficultyCard(
              zorluk: 'kolay',
              title: '🟢 Kolay',
              desc: 'Büyük şehirler (İstanbul, Ankara, İzmir, Antalya, Adana...)',
            ),
            _DifficultyCard(
              zorluk: 'orta',
              title: '🟡 Orta',
              desc: 'İç Anadolu ve Doğu Anadolu illeri',
            ),
            _DifficultyCard(
              zorluk: 'zor',
              title: '🔴 Zor',
              desc: 'Karadeniz ve daha az bilinen iller',
            ),
          ],
        ),
      ),
    );
  }
}

class _DifficultyCard extends StatelessWidget {
  final String zorluk;
  final String title;
  final String desc;
  const _DifficultyCard({required this.zorluk, required this.title, required this.desc});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(desc),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          context.read<SoundService>().click();
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => _IliBulPlayScreen(zorluk: zorluk)),
          );
        },
      ),
    );
  }
}

class _IliBulPlayScreen extends StatefulWidget {
  final String zorluk;
  const _IliBulPlayScreen({required this.zorluk});

  @override
  State<_IliBulPlayScreen> createState() => _IliBulPlayScreenState();
}

class _IliBulPlayScreenState extends State<_IliBulPlayScreen> {
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
      context.read<StorageService>().addGameTimeSpent(kIliBulGameId, DateTime.now().difference(start));
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
    final pool = kTurkeyProvinces.where((p) => p.zorluk == widget.zorluk).toList()..shuffle(Random());
    setState(() {
      _queue = pool.take(kIliBulRounds).toList();
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
    if (p.id == _target.id) {
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

        title: 'İli Bul',
        desc: "Bugünkü $kFreeGameDailyLimit ücretsiz harita oyunu hakkını kullandın. Yarın tekrar oyna ya da Premium'a geçip sınırsız oyna.",
      );
    }
    if (!_booted) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_finished) {
      return MapQuizResult(
        title: '🔎 İli Bul',
        modeId: kIliBulGameId,
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
      title: '🔎 İli Bul',
      promptText: '"${_target.ad}" ilini haritada bul!',
      statusText: 'Soru ${_round + 1}/${_queue.length} • Skor: $_score'
          '${_showResult ? "" : " • Hak: ${kMapMaxAttempts - _attempts}/$kMapMaxAttempts"}',
      palette: mapModePaletteFor(kIliBulGameId),
      howToPlay: _kHowToPlay,
      map: TurkeyMapCanvas(
        provinces: kTurkeyProvinces,
        colorFor: (p) {
          if (!_showResult) {
            if (p.id == _flashWrongId) return colors.danger;
            return colors.violet.withValues(alpha: 0.32);
          }
          if (p.id == _target.id) return colors.success;
          if (p.id == _tapped?.id) return colors.danger;
          return colors.violet.withValues(alpha: 0.15);
        },
        onTap: _onTapProvince,
      ),
      feedback: _showResult ? _buildFeedback(colors) : null,
    );
  }

  Widget _buildFeedback(KpssColors colors) {
    final correct = _tapped?.id == _target.id;
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
                ? '✅ Doğru! Bu il ${_target.ad}.'
                : '❌ $kMapMaxAttempts hakkını da kullandın. Doğru cevap: ${_target.ad}.',
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
