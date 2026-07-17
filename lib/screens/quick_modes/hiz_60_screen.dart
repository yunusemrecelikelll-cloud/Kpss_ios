import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/subject.dart';
import '../../models/question.dart';
import '../../services/remote_question_service.dart';
import '../../services/sound_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_provider.dart';
import '../tools_hub_screen.dart';
import 'quick_modes_shared.dart';

/// 60 Saniye Challenge — GENEL oyun kimliği. DİKKAT: bu, harita oyunundaki
/// "60 Saniyede Türkiye" (lib/screens/map_game/hiz_modu.dart) modundan
/// FARKLIDIR — o sadece harita/il sorularını kullanır, bu ekran ise TÜM
/// derslerden (harita hariç — zaten DataService.loadAll() haritayı içermez)
/// karışık soru çeker.
const String kHiz60GameId = 'hiz-60-genel';
const int kHiz60Suresi = 60;

/// 60 Saniye Challenge — 60 saniye boyunca art arda gelen karışık sorulara
/// hızlıca cevap verilir; doğru cevap sayısına göre puan alınır.
class Hiz60Screen extends StatefulWidget {
  final List<Subject> subjects;
  const Hiz60Screen({super.key, required this.subjects});

  @override
  State<Hiz60Screen> createState() => _Hiz60ScreenState();
}

class _Hiz60ScreenState extends State<Hiz60Screen> {
  final _rnd = Random();
  bool _locked = false;
  bool _loading = true;
  bool _noQuestions = false;
  bool _finished = false;

  List<Question> _pool = [];
  final List<Question> _queue = [];
  Question? _current;
  int _secondsLeft = kHiz60Suresi;
  int _score = 0;
  int _attempts = 0;
  int? _given;
  bool _flash = false;
  Timer? _ticker;

  // Toplam oynama süresi takibi: oturum, soru havuzu yüklenip ilk soru
  // gösterildiğinde başlar; ekran kapandığında (erken çıkış dahil, dispose
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
    _ticker?.cancel();
    super.dispose();
  }

  void _flushPlayTime() {
    final start = _sessionStart;
    if (start == null) return;
    _sessionStart = null;
    _storage.addGameTimeSpent(kHiz60GameId, DateTime.now().difference(start));
  }

  Future<void> _boot() async {
    final storage = context.read<StorageService>();
    final premium = storage.isPremiumUser();
    if (!premium) {
      final gp = storage.getGamePlayState(kHiz60GameId);
      if ((gp['plays'] as int) >= kFreeGameDailyLimit) {
        if (!mounted) return;
        setState(() => _locked = true);
        return;
      }
      await storage.useGamePlay(kHiz60GameId);
    }
    if (!mounted) return;

    final remote = context.read<RemoteQuestionService>();
    final pool = await QuickModesShared.collectAll(widget.subjects, remote, rnd: _rnd);
    if (!mounted) return;

    if (pool.isEmpty) {
      setState(() {
        _loading = false;
        _noQuestions = true;
      });
      return;
    }

    _pool = pool;
    _queue
      ..clear()
      ..addAll(pool);
    context.read<SoundService>().resetTickPhase();
    setState(() {
      _loading = false;
      _finished = false;
      _secondsLeft = kHiz60Suresi;
      _score = 0;
      _attempts = 0;
      _given = null;
      _flash = false;
      _current = _popNext();
    });
    _sessionStart ??= DateTime.now();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  Question _popNext() {
    if (_queue.isEmpty) {
      _queue.addAll(List<Question>.from(_pool)..shuffle(_rnd));
    }
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

  void _select(int idx) {
    if (_flash || _finished || _current == null) return;
    context.read<SoundService>().click();
    final correct = idx == _current!.dogruIndex;
    setState(() {
      _attempts++;
      _given = idx;
      _flash = true;
      if (correct) _score++;
    });
    Future.delayed(const Duration(milliseconds: 320), () {
      if (!mounted || _finished) return;
      setState(() {
        _flash = false;
        _given = null;
        _current = _popNext();
      });
    });
  }

  void _retry() {
    setState(() {
      _locked = false;
      _loading = true;
      _noQuestions = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  @override
  Widget build(BuildContext context) {
    if (_locked) {
      return const LockedFeatureCard(
        title: '60 Saniye Challenge',
        desc: "Bugünkü ücretsiz hakkını kullandın. Yarın tekrar oyna ya da Premium'a geçip sınırsız oyna.",
      );
    }
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_noQuestions) {
      return const Scaffold(body: Center(child: Text('Yeterli soru bulunamadı.')));
    }
    if (_finished) {
      return QuickModeResultCard(
        title: '⏱️ 60 Saniye Challenge',
        emoji: _score >= 15 ? '🎉' : '📚',
        message: '$_attempts denemede $_score doğru cevap verdin!',
        onRetry: _retry,
      );
    }
    return _buildBoard(context);
  }

  Widget _buildBoard(BuildContext context) {
    final colors = context.watch<ThemeProvider>().colors;
    final totalSeconds = context.watch<StorageService>().getGameTimeSpent(kHiz60GameId);
    final q = _current!;
    return Scaffold(
      appBar: AppBar(
        title: const Text('⏱️ 60 Saniye Challenge'),
        actions: const [
          HowToPlayButton(
            title: '⏱️ Nasıl Oynanır?',
            body: '60 saniye boyunca art arda gelen karışık sorulara olabildiğince '
                'hızlı ve doğru cevap vermeye çalış. Her doğru cevap skoruna eklenir, '
                'yanlışlar seni durdurmaz ama skorunu artırmaz. Süre dolduğunda kaç '
                'doğru yaptığını görürsün — kendi rekorunu kırmaya çalış!',
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('⏳ $_secondsLeft sn',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _secondsLeft <= 10 ? colors.danger : colors.text)),
                  Text('Skor: $_score / $_attempts', style: const TextStyle(fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Toplam: ${formatPlayDuration(totalSeconds)} oynadın',
                style: TextStyle(fontSize: 11, color: colors.textFaint),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: colors.glass2,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: colors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(q.soru, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 14),
                        for (var i = 0; i < q.secenekler.length; i++) _buildOption(q, i, colors),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOption(Question q, int i, KpssColors colors) {
    Color? borderColor;
    Color? bgColor;
    if (_flash) {
      if (i == q.dogruIndex) {
        borderColor = colors.success;
        bgColor = colors.success.withValues(alpha: 0.14);
      } else if (i == _given) {
        borderColor = colors.danger;
        bgColor = colors.danger.withValues(alpha: 0.14);
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: !_flash ? () => _select(i) : null,
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor ?? colors.border),
            color: bgColor,
          ),
          child: Row(
            children: [
              CircleAvatar(radius: 13, child: Text(kQuickModeOptionLetters[i], style: const TextStyle(fontSize: 12))),
              const SizedBox(width: 12),
              Expanded(child: Text(q.secenekler[i])),
            ],
          ),
        ),
      ),
    );
  }
}
