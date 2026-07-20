import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/subject.dart';
import '../models/topic.dart';
import '../games/card_game_engine.dart' show ciftRengi, kYanlisRengi;
import '../games/card_game_v2_engine.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../theme/theme_provider.dart';
import 'tools_hub_screen.dart';
import 'topic_screen.dart';

/// JS: FREE_GAME_DAILY / GAME2_MAX_MISTAKES
const int kFreeGameDaily = 10;
const int kGame2MaxMistakes = 3;
const String kGame2Id = 'cardgame2';

/// Kart Oyunu V2 — JS: renderGameSubjectPicker('cardgame2') girişi.
/// Ders seç → konu seç → açık kartlarla eşleştir.
class CardGameV2Screen extends StatelessWidget {
  final List<Subject> subjects;
  const CardGameV2Screen({super.key, required this.subjects});

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final colors = context.watch<ThemeProvider>().colors;
    final premium = storage.isPremiumUser();
    final gp = storage.getGamePlayState(kGame2Id);
    final left = (kFreeGameDaily - (gp['plays'] as int)).clamp(0, kFreeGameDaily);
    final progress = storage.getGamePassedTopics(kGame2Id);
    final totalSeconds = storage.getGameTimeSpent(kKartOyunuGameId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('🃏 Kart Oyunu V2'),
        actions: const [
          HowToPlayButton(
            title: '🃏 Nasıl Oynanır?',
            body: 'Önce bir ders, sonra bir konu seç. Soldaki terimi sağdaki doğru '
                'tanımıyla eşleştirmek için ikisine sırayla dokun; doğru eşleşmeler bir '
                'çizgiyle birleşir. Belirli bir yanlış sayısını geçersen konuyu '
                'kaybedersin, tüm eşleşmeleri tamamlarsan konuyu geçersin.',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Bir ders seç. ${premium ? "Sınırsız oynarsın." : "Bugün $left hakkın kaldı."}',
            style: TextStyle(fontSize: 13.5, color: colors.textFaint),
          ),
          const SizedBox(height: 4),
          Text(
            'Toplam: ${formatPlayDuration(totalSeconds)} oynadın',
            style: TextStyle(fontSize: 11.5, color: colors.textFaint),
          ),
          const SizedBox(height: 16),
          for (final s in subjects)
            _SubjectRow(
              subject: s,
              passedCount: s.konular.where((t) => progress[t.id] == true).length,
              onTap: () {
                context.read<SoundService>().click();
                Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => _V2TopicPicker(subject: s)));
              },
            ),
        ],
      ),
    );
  }
}

class _SubjectRow extends StatelessWidget {
  final Subject subject;
  final int passedCount;
  final VoidCallback onTap;
  const _SubjectRow({required this.subject, required this.passedCount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final total = subject.konular.length;
    final pct = total == 0 ? 0.0 : passedCount / total;
    return Card(
      child: ListTile(
        leading: Text(subject.icon, style: const TextStyle(fontSize: 22)),
        title: Text(subject.ad, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 6),
            LinearProgressIndicator(value: pct),
            const SizedBox(height: 4),
            Text('$passedCount/$total konu geçildi', style: const TextStyle(fontSize: 11)),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _V2TopicPicker extends StatelessWidget {
  final Subject subject;
  const _V2TopicPicker({required this.subject});

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final colors = context.watch<ThemeProvider>().colors;
    final progress = storage.getGamePassedTopics(kGame2Id);

    return Scaffold(
      appBar: AppBar(title: Text('🃏 Kart Oyunu V2 — ${subject.ad}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (var i = 0; i < subject.konular.length; i++)
            Builder(builder: (context) {
              final t = subject.konular[i];
              final passed = progress[t.id] == true;
              final eligible = CardGameV2Engine.buildPairsForTopic(t).length >= 3;
              return Opacity(
                opacity: eligible ? 1 : 0.5,
                child: Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: passed ? colors.success.withValues(alpha: 0.2) : null,
                      child: Text(passed ? '✓' : '${i + 1}'),
                    ),
                    title: Text(t.baslik, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(passed
                        ? 'Geçildi ✓'
                        : eligible
                            ? 'Henüz geçilmedi'
                            : 'Bu oyun için yeterli içerik yok'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      context.read<SoundService>().click();
                      if (!eligible) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(const SnackBar(content: Text('Bu konu için yeterli içerik yok.')));
                        return;
                      }
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => _V2PlayScreen(subject: subject, topic: t)),
                      );
                    },
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

/// Eşleşen bir çifti birleştiren ok — [renk] çiftin palet rengidir.
class _EslesmeOku {
  final Offset a, b;
  final Color renk;
  const _EslesmeOku(this.a, this.b, this.renk);
}

/// Okları çizer. Son eklenen ok [ilerleme] (0→1) değerine göre soldan sağa
/// ANİMASYONLU uzar; önceki oklar tam çizilir.
class _MatchLinePainter extends CustomPainter {
  final List<_EslesmeOku> lines;
  final double ilerleme;
  _MatchLinePainter(this.lines, this.ilerleme);

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      final t = (i == lines.length - 1) ? ilerleme.clamp(0.0, 1.0) : 1.0;
      if (t <= 0) continue;
      final uc = Offset.lerp(l.a, l.b, t)!;

      final linePaint = Paint()
        ..color = l.renk
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      canvas.drawLine(l.a, uc, linePaint);
      canvas.drawCircle(l.a, 3, Paint()..color = l.renk);

      final dir = l.b - l.a;
      final len = dir.distance;
      if (len == 0) continue;
      final unit = dir / len;
      final normal = Offset(-unit.dy, unit.dx);
      final back = uc - unit * 9;
      final p1 = back + normal * 4.5;
      final p2 = back - normal * 4.5;
      final path = Path()
        ..moveTo(uc.dx, uc.dy)
        ..lineTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..close();
      canvas.drawPath(path, Paint()..color = l.renk);
    }
  }

  @override
  bool shouldRepaint(covariant _MatchLinePainter oldDelegate) =>
      oldDelegate.lines.length != lines.length || oldDelegate.ilerleme != ilerleme;
}

/// Kart Oyunu V2 tahtası + sonuç ekranı — JS: _renderGame2Board / _renderGameResult.
class _V2PlayScreen extends StatefulWidget {
  final Subject subject;
  final Topic topic;
  const _V2PlayScreen({required this.subject, required this.topic});

  @override
  State<_V2PlayScreen> createState() => _V2PlayScreenState();
}

class _V2PlayScreenState extends State<_V2PlayScreen> with TickerProviderStateMixin {
  final _engine = CardGameV2Engine();
  final _boardKey = GlobalKey();
  late List<GlobalKey> _leftKeys;
  late List<GlobalKey> _rightKeys;
  late AnimationController _shakeCtrl;

  /// Yeni bir eşleşme okunun soldan sağa çizilme animasyonu.
  late AnimationController _okCtrl;

  bool _locked = false;
  bool _started = false;
  bool _flashWrong = false;
  bool? _passed; // null: oynanıyor, true/false: bitti
  List<_EslesmeOku> _lines = [];

  // Toplam oynama süresi takibi (Kart Oyunu ortak kimliği, bkz. tools_hub_screen.dart) —
  // ekran açık kaldığı sürece (tekrar denemeler dahil) TEK oturum sayılır; erken
  // çıkışta da dispose her zaman çağrıldığından kısmi süre kaydedilir.
  DateTime? _sessionStart;
  late final StorageService _storage;

  @override
  void initState() {
    super.initState();
    _storage = context.read<StorageService>();
    _shakeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
    _okCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  @override
  void dispose() {
    _flushPlayTime();
    _shakeCtrl.dispose();
    _okCtrl.dispose();
    super.dispose();
  }

  void _flushPlayTime() {
    final start = _sessionStart;
    if (start == null) return;
    _sessionStart = null;
    _storage.addGameTimeSpent(kKartOyunuGameId, DateTime.now().difference(start));
  }

  Future<void> _boot() async {
    final storage = context.read<StorageService>();
    final premium = storage.isPremiumUser();
    if (!premium) {
      final gp = storage.getGamePlayState(kGame2Id);
      if ((gp['plays'] as int) >= kFreeGameDaily) {
        if (!mounted) return;
        setState(() => _locked = true);
        return;
      }
      await storage.useGamePlay(kGame2Id);
    }
    _engine.start(widget.topic, maxMistakes: kGame2MaxMistakes);
    _leftKeys = List.generate(_engine.left.length, (_) => GlobalKey());
    _rightKeys = List.generate(_engine.right.length, (_) => GlobalKey());
    if (!mounted) return;
    setState(() {
      _started = true;
      _passed = null;
      _flashWrong = false;
      _lines = [];
    });
    _sessionStart ??= DateTime.now();
  }

  void _retry() {
    setState(() {
      _started = false;
      _locked = false;
      _passed = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  void _recomputeLines() {
    final boardBox = _boardKey.currentContext?.findRenderObject() as RenderBox?;
    if (boardBox == null || !boardBox.hasSize) return;
    final newLines = <_EslesmeOku>[];
    for (var i = 0; i < _engine.left.length; i++) {
      final c = _engine.left[i];
      if (!c.matched) continue;
      final ri = _engine.right.indexWhere((r) => r.matched && r.pairId == c.pairId);
      if (ri < 0) continue;
      final lBox = _leftKeys[i].currentContext?.findRenderObject() as RenderBox?;
      final rBox = _rightKeys[ri].currentContext?.findRenderObject() as RenderBox?;
      if (lBox == null || rBox == null || !lBox.hasSize || !rBox.hasSize) continue;
      final lTopLeft = lBox.localToGlobal(Offset.zero, ancestor: boardBox);
      final rTopLeft = rBox.localToGlobal(Offset.zero, ancestor: boardBox);
      final p1 = lTopLeft + Offset(lBox.size.width, lBox.size.height / 2);
      final p2 = rTopLeft + Offset(0, rBox.size.height / 2);
      newLines.add(_EslesmeOku(p1, p2, ciftRengi(c.renkIndex)));
    }
    if (newLines.length != _lines.length && mounted) {
      final yeniOkVar = newLines.length > _lines.length;
      setState(() => _lines = newLines);
      // Yeni eşleşmenin oku soldan sağa çizilsin.
      if (yeniOkVar) _okCtrl.forward(from: 0);
    }
  }

  void _triggerShake() {
    setState(() => _flashWrong = true);
    _shakeCtrl.forward(from: 0);
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      setState(() {
        _flashWrong = false;
        _engine.clearLastWrong();
      });
    });
  }

  void _checkEnd() {
    if (_engine.isComplete) {
      final storage = context.read<StorageService>();
      storage.markGameTopicPassed(kGame2Id, widget.topic.id);
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!mounted) return;
        setState(() => _passed = true);
      });
    } else if (_engine.isFailed) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!mounted) return;
        setState(() => _passed = false);
      });
    }
  }

  void _handleTap(String side, int i) {
    final res = side == 'left' ? _engine.selectLeft(i) : _engine.selectRight(i);
    if (res.status == 'ignored') return;
    context.read<SoundService>().click();
    setState(() {});
    if (res.status == 'match') {
      WidgetsBinding.instance.addPostFrameCallback((_) => _recomputeLines());
    }
    if (res.status == 'nomatch') {
      _triggerShake();
    }
    _checkEnd();
  }

  @override
  Widget build(BuildContext context) {
    if (_locked) {
      return const LockedFeatureCard(
        title: 'Kart Oyunu V2',
        desc: "Bugünkü $kFreeGameDaily ücretsiz hakkını kullandın. Yarın tekrar oyna ya da Premium'a geçip sınırsız oyna.",
      );
    }
    if (!_started) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_engine.pairsTotal < 2) {
      return Scaffold(
        appBar: AppBar(title: const Text('🃏 Kart Oyunu V2')),
        body: const Center(child: Text('Bu konu için yeterli içerik yok.')),
      );
    }
    if (_passed != null) {
      return _V2Result(
        subject: widget.subject,
        topic: widget.topic,
        passed: _passed!,
        onRetry: _retry,
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => _recomputeLines());
    final colors = context.watch<ThemeProvider>().colors;

    return Scaffold(
      appBar: AppBar(
        title: Text('🃏 Kart Oyunu V2 — ${widget.topic.baslik}'),
        actions: const [
          HowToPlayButton(
            title: '🃏 Nasıl Oynanır?',
            body: 'Soldaki terimi sağdaki doğru tanımıyla eşleştirmek için ikisine '
                'sırayla dokun; doğru eşleşmeler bir çizgiyle birleşir. Belirli bir '
                'yanlış sayısını geçersen konuyu kaybedersin, tüm eşleşmeleri '
                'tamamlarsan konuyu geçersin.',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sol taraftaki terimi sağdaki tanımıyla eşleştir. '
              'Eşleşen: ${_engine.matchedCount}/${_engine.pairsTotal} • '
              'Yanlış: ${_engine.mistakes}/${_engine.maxMistakes}',
              style: TextStyle(fontSize: 13, color: colors.textFaint),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                decoration: BoxDecoration(
                  color: _flashWrong ? colors.danger.withValues(alpha: 0.14) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                // Kartlar KARŞILIKLI iki sütunda, hepsi EŞİT boyutta duracak
                // şekilde dizilir: her satır Expanded olduğundan yükseklikler
                // eşitlenir, sıralama karışıktır ama ızgara hizalı kalır.
                child: Stack(
                  key: _boardKey,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              for (var i = 0; i < _engine.left.length; i++)
                                Expanded(
                                  child: _buildCard(
                                      side: 'left', i: i, key: _leftKeys[i], card: _engine.left[i]),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 34),
                        Expanded(
                          child: Column(
                            children: [
                              for (var i = 0; i < _engine.right.length; i++)
                                Expanded(
                                  child: _buildCard(
                                      side: 'right', i: i, key: _rightKeys[i], card: _engine.right[i]),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedBuilder(
                          animation: _okCtrl,
                          builder: (context, _) => CustomPaint(
                            painter: _MatchLinePainter(_lines, _okCtrl.value),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard({required String side, required int i, required Key key, required Match2Card card}) {
    final colors = context.watch<ThemeProvider>().colors;
    final selected = side == 'left' ? _engine.selectedLeft == i : _engine.selectedRight == i;
    final isWrong = side == 'left' ? _engine.lastWrong?.leftIdx == i : _engine.lastWrong?.rightIdx == i;

    // Eşleşen çift AYNI paleti paylaşır; farklı çiftler farklı renk alır.
    final Color? vurgu = isWrong
        ? kYanlisRengi
        : card.matched
            ? ciftRengi(card.renkIndex)
            : null;

    Widget content = AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      key: key,
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: vurgu != null
            ? vurgu.withValues(alpha: 0.20)
            : selected
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.18)
                : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: vurgu ??
              (selected ? Theme.of(context).colorScheme.primary : colors.border),
          width: vurgu != null || selected ? 1.8 : 1,
        ),
      ),
      alignment: Alignment.center,
      // Tüm kartlar eşit boyutta olduğundan metin, kartın içine sığacak
      // şekilde gerektiğinde küçültülür.
      child: LayoutBuilder(
        builder: (context, kisit) => FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(
            width: kisit.maxWidth.isFinite ? kisit.maxWidth : 140,
            child: Text(
              card.text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: colors.text),
            ),
          ),
        ),
      ),
    );

    if (isWrong) {
      content = AnimatedBuilder(
        animation: _shakeCtrl,
        builder: (context, child) {
          final dx = _shakeCtrl.isAnimating ? sin(_shakeCtrl.value * pi * 6) * 6 : 0.0;
          return Transform.translate(offset: Offset(dx, 0), child: child);
        },
        child: content,
      );
    }

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: card.matched ? null : () => _handleTap(side, i),
      child: content,
    );
  }
}

class _V2Result extends StatelessWidget {
  final Subject subject;
  final Topic topic;
  final bool passed;
  final VoidCallback onRetry;
  const _V2Result({required this.subject, required this.topic, required this.passed, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colors = context.watch<ThemeProvider>().colors;
    return Scaffold(
      appBar: AppBar(title: const Text('🃏 Kart Oyunu V2')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Card(
          color: passed ? null : colors.danger.withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(passed ? '🎉' : '📚', style: const TextStyle(fontSize: 44)),
                const SizedBox(height: 10),
                Text(passed ? 'Konuyu geçtin!' : 'Bu konuyu geçemedin',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(
                  passed
                      ? '${topic.baslik} konusundaki tüm eşleşmeleri buldun.'
                      : '${topic.baslik} konusunu tekrar çalışman işini kolaylaştırır.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.textFaint),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    if (!passed)
                      ElevatedButton(
                        onPressed: () {
                          context.read<SoundService>().click();
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => TopicScreen(subject: subject, topic: topic)),
                          );
                        },
                        child: const Text('📖 Konuyu Tekrar Çalış'),
                      ),
                    OutlinedButton(
                      onPressed: () {
                        context.read<SoundService>().click();
                        Navigator.of(context).pop();
                      },
                      child: const Text('Konu Listesine Dön'),
                    ),
                    TextButton(
                      onPressed: () {
                        context.read<SoundService>().click();
                        onRetry();
                      },
                      child: const Text('🔄 Tekrar Dene'),
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
}
