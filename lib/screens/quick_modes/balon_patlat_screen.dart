import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/question.dart';
import '../../models/subject.dart';
import '../../services/data_service.dart';
import '../../services/remote_question_service.dart';
import '../../services/sound_service.dart';
import '../../services/storage_service.dart';
import '../../theme/theme_provider.dart';
import '../../theme/app_theme.dart';
import '../tools_hub_screen.dart';

/// Mini oyun — Balon Patlat: bir soru sorulur, her şık uçuşan/yüzen bir
/// balonda gösterilir; kullanıcı DOĞRU cevabın balonuna dokunur. Doğru
/// balona dokunursa puan kazanır ve balon patlar (scale+fade animasyonu),
/// yanlış balona dokunursa can kaybeder. Sorular RemoteQuestionService +
/// DataService.cachedSubjects üzerinden TÜM derslerden karışık çekilir
/// (Türkçe/Vatandaşlık için özellikle uygun, ama kısıtlama yok).
const String kBalonPatlatGameId = 'balon-patlat';
const int kBalonRoundCount = 8;
const int kBalonLives = 3;
const int kBalonScorePerCorrect = 10;

class BalonPatlatScreen extends StatefulWidget {
  final List<Subject> subjects;
  const BalonPatlatScreen({super.key, required this.subjects});

  @override
  State<BalonPatlatScreen> createState() => _BalonPatlatScreenState();
}

class _BalonRound {
  final Question question;
  final List<int> order; // permütasyon: balon i -> question.secenekler[order[i]]
  _BalonRound(this.question, this.order);

  int get correctBalloonIndex => order.indexOf(question.dogruIndex);
}

class _BalonPatlatScreenState extends State<BalonPatlatScreen> {
  final Random _rnd = Random();

  bool _locked = false;
  bool _loading = true;
  bool _noQuestions = false;
  bool _finished = false;

  List<Question> _pool = [];
  final List<Question> _used = [];
  _BalonRound? _round;
  int _roundIndex = 0;
  int _score = 0;
  int _lives = kBalonLives;
  int? _tappedBalloon;
  bool _showResult = false;
  bool _correctTap = false;
  bool _roundLocked = false;

  // Toplam oynama süresi takibi: oturum, soru havuzu başarıyla yüklenip ilk
  // tur başladığında başlar; ekran kapandığında (erken çıkış dahil, dispose
  // her zaman çağrılır) kısmi süre de kaydedilir.
  DateTime? _sessionStart;
  late final StorageService _storage;

  @override
  void initState() {
    super.initState();
    _storage = context.read<StorageService>();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  @override
  void dispose() {
    _flushPlayTime();
    super.dispose();
  }

  void _flushPlayTime() {
    final start = _sessionStart;
    if (start == null) return;
    _sessionStart = null;
    _storage.addGameTimeSpent(kBalonPatlatGameId, DateTime.now().difference(start));
  }

  Future<void> _boot() async {
    final storage = context.read<StorageService>();
    final premium = storage.isPremiumUser();
    if (!premium) {
      final gp = storage.getGamePlayState(kBalonPatlatGameId);
      if ((gp['plays'] as int) >= kFreeGameDailyLimit) {
        if (!mounted) return;
        setState(() => _locked = true);
        return;
      }
      await storage.useGamePlay(kBalonPatlatGameId);
    }
    if (!mounted) return;

    setState(() => _loading = true);
    final pool = await _loadMixedPool();
    if (!mounted) return;

    if (pool.length < 4) {
      setState(() {
        _noQuestions = true;
        _loading = false;
      });
      return;
    }

    pool.shuffle(_rnd);
    setState(() {
      _pool = pool;
      _used.clear();
      _roundIndex = 0;
      _score = 0;
      _lives = kBalonLives;
      _finished = false;
      _loading = false;
      _round = _buildRound();
      // ÖNEMLİ (düzeltilen hata): "Tekrar Oyna" sonrası bir önceki oyunun
      // son turundan kalma bu 4 alan sıfırlanmadığı için yeni oyun İLK
      // TURDA ZATEN KİLİTLİ/CEVAPLANMIŞ görünüyordu (balon seçilemiyor,
      // sonraki soruya geçilemiyordu) — uygulamayı kapatıp açmak initState'in
      // varsayılan değerleriyle "düzeltiyordu", asıl neden buydu.
      _tappedBalloon = null;
      _showResult = false;
      _correctTap = false;
      _roundLocked = false;
    });
    _sessionStart ??= DateTime.now();
  }

  /// Tüm derslerin tüm konularından (RemoteQuestionService.getPool ile,
  /// önbellek varsa TAM havuz yoksa gömülü yedek) paralel olarak soru
  /// toplar (Future.wait) ve karışık, tek bir havuz döner. En az 5 şıklı
  /// sorular tercih edilir; 4 şıklı sorular da desteklenir.
  Future<List<Question>> _loadMixedPool() async {
    final dataService = context.read<DataService>();
    final remote = context.read<RemoteQuestionService>();
    var subjects = widget.subjects.isNotEmpty ? widget.subjects : dataService.cachedSubjects;
    if (subjects.isEmpty) {
      subjects = await dataService.loadAll();
    }

    final futures = <Future<List<Question>>>[];
    for (final s in subjects) {
      for (final t in s.konular) {
        futures.add(
          remote.getPool(t.id, t.sorular).then(
                (qs) => qs
                    .where((q) => q.secenekler.length >= 4)
                    .map((q) => q.copyWith(subjectId: s.id, subjectAd: s.ad))
                    .toList(),
              ),
        );
      }
    }
    final results = await Future.wait(futures);
    final all = <Question>[];
    for (final r in results) {
      all.addAll(r);
    }
    return all;
  }

  _BalonRound? _buildRound() {
    final available = _pool.where((q) => !_used.contains(q)).toList();
    final source = available.isNotEmpty ? available : _pool;
    if (source.isEmpty) return null;
    final q = source[_rnd.nextInt(source.length)];
    _used.add(q);
    // En fazla 5 şık gösterilir (balon kalabalığı olmasın diye).
    final n = min(q.secenekler.length, 5);
    final order = List<int>.generate(q.secenekler.length, (i) => i)..shuffle(_rnd);
    final trimmed = order.take(n).toList();
    if (!trimmed.contains(q.dogruIndex)) {
      // Doğru şık kırpılan kısımda kalmışsa yerine koy.
      trimmed[_rnd.nextInt(trimmed.length)] = q.dogruIndex;
    }
    trimmed.shuffle(_rnd);
    return _BalonRound(q, trimmed);
  }

  void _onBalloonTap(int balloonIndex) {
    if (_roundLocked || _round == null) return;
    context.read<SoundService>().click();
    final round = _round!;
    final correct = balloonIndex == round.correctBalloonIndex;
    setState(() {
      _roundLocked = true;
      _tappedBalloon = balloonIndex;
      _showResult = true;
      _correctTap = correct;
      if (correct) {
        _score += kBalonScorePerCorrect;
      } else {
        _lives -= 1;
      }
    });

    Future.delayed(const Duration(milliseconds: 950), () {
      if (!mounted) return;
      if (_lives <= 0 || _roundIndex + 1 >= kBalonRoundCount) {
        setState(() => _finished = true);
        return;
      }
      setState(() {
        _roundIndex += 1;
        _round = _buildRound();
        _tappedBalloon = null;
        _showResult = false;
        _roundLocked = false;
      });
    });
  }

  void _retry() {
    setState(() {
      _locked = false;
      _noQuestions = false;
      _loading = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  @override
  Widget build(BuildContext context) {
    if (_locked) {
      return const LockedFeatureCard(
        title: 'Balon Patlat',
        desc: "Bugünkü $kFreeGameDailyLimit ücretsiz Balon Patlat hakkını kullandın. Yarın tekrar oyna ya da Premium'a geçip sınırsız oyna.",
      );
    }
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('🎈 Balon Patlat')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_noQuestions) {
      return Scaffold(
        appBar: AppBar(title: const Text('🎈 Balon Patlat')),
        body: const Center(child: Text('Yeterli soru bulunamadı.')),
      );
    }
    if (_finished) {
      return _buildResult(context);
    }
    return _buildBoard(context);
  }

  Widget _buildResult(BuildContext context) {
    final colors = context.watch<ThemeProvider>().colors;
    final won = _lives > 0;
    return Scaffold(
      appBar: AppBar(title: const Text('🎈 Balon Patlat')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(won ? '🎉' : '💥', style: const TextStyle(fontSize: 44)),
                const SizedBox(height: 12),
                Text(
                  won ? 'Tüm balonları tamamladın!' : 'Canların bitti!',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  'Skor: $_score  •  ${_roundIndex + 1}/$kBalonRoundCount soru',
                  style: TextStyle(color: colors.textFaint),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: () {
                        context.read<SoundService>().click();
                        _retry();
                      },
                      child: const Text('🔄 Tekrar Oyna'),
                    ),
                    OutlinedButton(
                      onPressed: () {
                        context.read<SoundService>().click();
                        Navigator.of(context).pop();
                      },
                      child: const Text('Menüye Dön'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBoard(BuildContext context) {
    final colors = context.watch<ThemeProvider>().colors;
    final round = _round;
    if (round == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final totalSeconds = context.watch<StorageService>().getGameTimeSpent(kBalonPatlatGameId);
    return Scaffold(
      appBar: AppBar(
        title: const Text('🎈 Balon Patlat'),
        actions: const [
          HowToPlayButton(
            title: '🎈 Nasıl Oynanır?',
            body: 'Ekranda bir soru ve uçuşan balonlarda şıklar görürsün. Doğru '
                'cevap olduğunu düşündüğün balona dokun: doğruysa balon patlar ve '
                'puan kazanırsın, yanlışsa can kaybedersin. Canların bitmeden ya da '
                'tüm sorular tamamlanmadan oyun devam eder — dikkatli ve hızlı ol!',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Soru ${_roundIndex + 1}/$kBalonRoundCount',
                    style: TextStyle(fontSize: 12.5, color: colors.textFaint, fontWeight: FontWeight.w700),
                  ),
                  Row(
                    children: [
                      Text('⭐ $_score', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                      const SizedBox(width: 12),
                      Row(
                        children: List.generate(
                          kBalonLives,
                          (i) => Icon(
                            i < _lives ? Icons.favorite : Icons.favorite_border,
                            size: 16,
                            color: colors.danger,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Toplam: ${formatPlayDuration(totalSeconds)} oynadın',
                  style: TextStyle(fontSize: 11, color: colors.textFaint),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colors.glass2,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colors.border),
                ),
                child: Text(
                  round.question.soru,
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, height: 1.3),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      for (var i = 0; i < round.order.length; i++)
                        _buildBalloon(context, round, i, constraints, colors),
                    ],
                  );
                },
              ),
            ),
            if (_showResult)
              Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  _correctTap
                      ? '✅ Doğru! +$kBalonScorePerCorrect puan'
                      : '❌ Yanlış! Doğrusu: ${round.question.secenekler[round.question.dogruIndex]}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: _correctTap ? colors.success : colors.danger,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Balonların ekrandaki gevşek "dağınık" konumları — balon sayısına göre
  // (4 ya da 5) hazır bir sabit anchor kümesinden alınır, ardından küçük bir
  // rastgele jitter eklenir (böylece her turda biraz farklı görünür ama
  // üst üste binmezler).
  static const List<Offset> _anchors5 = [
    Offset(0.12, 0.06),
    Offset(0.62, 0.02),
    Offset(0.05, 0.52),
    Offset(0.58, 0.46),
    Offset(0.30, 0.74),
  ];
  static const List<Offset> _anchors4 = [
    Offset(0.08, 0.08),
    Offset(0.56, 0.04),
    Offset(0.10, 0.56),
    Offset(0.54, 0.52),
  ];

  Widget _buildBalloon(
    BuildContext context,
    _BalonRound round,
    int balloonIndex,
    BoxConstraints constraints,
    KpssColors colors,
  ) {
    final anchors = round.order.length >= 5 ? _anchors5 : _anchors4;
    final anchor = anchors[balloonIndex % anchors.length];
    final w = constraints.maxWidth;
    final h = constraints.maxHeight;
    final balloonW = (w * 0.42).clamp(120.0, 210.0).toDouble();
    final left = (anchor.dx * w).clamp(0.0, max(0.0, w - balloonW)).toDouble();
    final top = (anchor.dy * h).clamp(0.0, max(0.0, h - 110)).toDouble();

    final optionText = round.question.secenekler[round.order[balloonIndex]];
    final isCorrectBalloon = balloonIndex == round.correctBalloonIndex;
    final isTapped = _tappedBalloon == balloonIndex;

    Color balloonColor;
    if (_showResult && isTapped) {
      balloonColor = isCorrectBalloon ? colors.success : colors.danger;
    } else if (_showResult && isCorrectBalloon) {
      balloonColor = colors.success;
    } else {
      final palette = [colors.violet, colors.rose, colors.gold, colors.mint, colors.violetL];
      balloonColor = palette[balloonIndex % palette.length];
    }

    return Positioned(
      left: left,
      top: top,
      width: balloonW,
      child: _FloatingBalloon(
        seed: balloonIndex,
        popped: _showResult && isTapped && isCorrectBalloon,
        faded: _showResult && !isTapped && !isCorrectBalloon,
        color: balloonColor,
        text: optionText,
        onTap: () => _onBalloonTap(balloonIndex),
      ),
    );
  }
}

/// Bağımsız hafif animasyonlu tek bir balon: yavaşça yukarı-aşağı süzülür
/// ve hafifçe sağa-sola sallanır (karmaşık bir fizik motoru yok — sadece
/// AnimationController ile sürekli tekrar eden sin/cos ofseti). Doğru
/// cevap seçildiğinde scale+fade ile "patlar".
class _FloatingBalloon extends StatefulWidget {
  final int seed;
  final bool popped;
  final bool faded;
  final Color color;
  final String text;
  final VoidCallback onTap;
  const _FloatingBalloon({
    required this.seed,
    required this.popped,
    required this.faded,
    required this.color,
    required this.text,
    required this.onTap,
  });

  @override
  State<_FloatingBalloon> createState() => _FloatingBalloonState();
}

class _FloatingBalloonState extends State<_FloatingBalloon> with SingleTickerProviderStateMixin {
  late final AnimationController _floatCtrl;
  late final double _phase;
  late final double _ampX;
  late final double _ampY;

  @override
  void initState() {
    super.initState();
    final rnd = Random(widget.seed * 7919 + 13);
    _phase = rnd.nextDouble() * 2 * pi;
    _ampX = 6 + rnd.nextDouble() * 8;
    _ampY = 8 + rnd.nextDouble() * 10;
    _floatCtrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 2600 + rnd.nextInt(1400)),
    )..repeat();
  }

  @override
  void dispose() {
    _floatCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _floatCtrl,
      builder: (context, child) {
        final t = _floatCtrl.value * 2 * pi;
        final dx = sin(t + _phase) * _ampX;
        final dy = sin(t * 0.8 + _phase) * _ampY;
        return Transform.translate(offset: Offset(dx, dy), child: child);
      },
      child: AnimatedScale(
        scale: widget.popped ? 1.35 : 1.0,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: widget.popped || widget.faded ? 0.0 : 1.0,
          duration: const Duration(milliseconds: 320),
          child: GestureDetector(
            onTap: widget.onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              decoration: BoxDecoration(
                color: widget.color.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.22), blurRadius: 10, offset: const Offset(0, 5)),
                ],
                border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 1.4),
              ),
              child: Text(
                widget.text,
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5, height: 1.2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
