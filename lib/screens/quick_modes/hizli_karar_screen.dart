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

/// Hızlı Karar — GENEL oyun kimliği (günlük ücretsiz hak sayacı için).
const String kHizliKararGameId = 'hizli-karar';

/// Bir oturumdaki soru sayısı.
const int kHizliKararSoruSayisi = 15;

/// Her soru için verilen süre (saniye) — "3-5 saniye" isteğine göre 4 sn.
const int kHizliKararSureSn = 4;

/// Normal 5 şıklı [Question]'dan türetilmiş, 2 şıklı (A/B) hızlı karar
/// sorusu: doğru şık ile rastgele bir yanlış şık alınır, hangisinin A/B
/// olacağı rastgele karıştırılır.
class _HizliKararSoru {
  final String metin;
  final String secenekA;
  final String secenekB;
  final int correctIndex; // 0 = A, 1 = B

  const _HizliKararSoru({
    required this.metin,
    required this.secenekA,
    required this.secenekB,
    required this.correctIndex,
  });

  static _HizliKararSoru? fromQuestion(Question q, Random rnd) {
    if (q.secenekler.length < 2) return null;
    if (q.dogruIndex < 0 || q.dogruIndex >= q.secenekler.length) return null;
    final wrongIndices = List.generate(q.secenekler.length, (i) => i)..remove(q.dogruIndex);
    if (wrongIndices.isEmpty) return null;
    final wrongIdx = wrongIndices[rnd.nextInt(wrongIndices.length)];
    final correctText = q.secenekler[q.dogruIndex];
    final wrongText = q.secenekler[wrongIdx];
    final correctIsA = rnd.nextBool();
    return _HizliKararSoru(
      metin: q.soru,
      secenekA: correctIsA ? correctText : wrongText,
      secenekB: correctIsA ? wrongText : correctText,
      correctIndex: correctIsA ? 0 : 1,
    );
  }
}

/// Hızlı Karar — her soru için sadece [kHizliKararSureSn] saniye süre olan,
/// 2 şıklı (A/B) art arda soru modu. Süre dolmadan cevap verilmezse otomatik
/// yanlış sayılır. Refleks + bilgi birlikte ölçülür.
class HizliKararScreen extends StatefulWidget {
  final List<Subject> subjects;
  const HizliKararScreen({super.key, required this.subjects});

  @override
  State<HizliKararScreen> createState() => _HizliKararScreenState();
}

class _HizliKararScreenState extends State<HizliKararScreen> {
  final _rnd = Random();
  bool _locked = false;
  bool _loading = true;
  bool _noQuestions = false;
  bool _finished = false;

  final List<_HizliKararSoru> _queue = [];
  int _index = 0;
  int _correct = 0;
  int? _given; // 0/1 — kullanıcının seçtiği şık (timeout'ta null kalır)
  bool _showResult = false;
  bool _timedOut = false;
  int _secondsLeft = kHizliKararSureSn;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _boot() async {
    final storage = context.read<StorageService>();
    final premium = storage.isPremiumUser();
    if (!premium) {
      final gp = storage.getGamePlayState(kHizliKararGameId);
      if ((gp['plays'] as int) >= kFreeGameDailyLimit) {
        if (!mounted) return;
        setState(() => _locked = true);
        return;
      }
      await storage.useGamePlay(kHizliKararGameId);
    }
    if (!mounted) return;

    final remote = context.read<RemoteQuestionService>();
    final pool = await QuickModesShared.collectAll(widget.subjects, remote, rnd: _rnd);
    if (!mounted) return;

    final derived = <_HizliKararSoru>[];
    for (final q in pool) {
      final s = _HizliKararSoru.fromQuestion(q, _rnd);
      if (s != null) derived.add(s);
      if (derived.length >= kHizliKararSoruSayisi) break;
    }

    if (derived.isEmpty) {
      setState(() {
        _loading = false;
        _noQuestions = true;
      });
      return;
    }

    _queue
      ..clear()
      ..addAll(derived);
    context.read<SoundService>().resetTickPhase();
    setState(() {
      _loading = false;
      _finished = false;
      _index = 0;
      _correct = 0;
      _given = null;
      _showResult = false;
      _timedOut = false;
    });
    _startQuestionTimer();
  }

  void _startQuestionTimer() {
    _ticker?.cancel();
    _secondsLeft = kHizliKararSureSn;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (!mounted) return;
    setState(() => _secondsLeft--);
    if (_secondsLeft <= 0) {
      _ticker?.cancel();
      _handleTimeout();
    }
  }

  void _handleTimeout() {
    if (_showResult || _finished) return;
    setState(() {
      _given = null;
      _timedOut = true;
      _showResult = true;
    });
    Future.delayed(const Duration(milliseconds: 550), _advance);
  }

  void _select(int idx) {
    if (_showResult || _finished) return;
    _ticker?.cancel();
    context.read<SoundService>().click();
    final correct = idx == _queue[_index].correctIndex;
    setState(() {
      _given = idx;
      _timedOut = false;
      _showResult = true;
      if (correct) _correct++;
    });
    Future.delayed(const Duration(milliseconds: 450), _advance);
  }

  void _advance() {
    if (!mounted || _finished) return;
    if (_index + 1 >= _queue.length) {
      setState(() => _finished = true);
      return;
    }
    setState(() {
      _index++;
      _given = null;
      _showResult = false;
      _timedOut = false;
    });
    _startQuestionTimer();
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
        title: 'Hızlı Karar',
        desc: "Bugünkü ücretsiz hakkını kullandın. Yarın tekrar oyna ya da Premium'a geçip sınırsız oyna.",
      );
    }
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_noQuestions) {
      return const Scaffold(
        body: Center(child: Text('Yeterli soru bulunamadı.')),
      );
    }
    if (_finished) {
      final colors = context.watch<ThemeProvider>().colors;
      final toplam = _queue.length;
      final isabet = toplam == 0 ? 0 : (_correct * 100 / toplam).round();
      final basari = _correct >= (kHizliKararSoruSayisi * 0.7);
      return GameResultScreen(
        title: '⚡ Hızlı Karar',
        emoji: (toplam > 0 && _correct == toplam)
            ? '🏆'
            : (basari ? '🎉' : (isabet >= 40 ? '💪' : '📚')),
        headline: basari ? 'Refleksin çok iyi!' : 'Tur bitti',
        message: '$toplam sorudan $_correct tanesini doğru bildin.\n'
            'Refleks + bilgi bir arada ölçüldü — daha hızlı karar vermeyi dene!',
        stats: [
          GameResultStat(emoji: '✅', value: '$_correct', label: 'Doğru', color: colors.success),
          GameResultStat(
            emoji: '❌',
            value: '${(toplam - _correct).clamp(0, toplam)}',
            label: 'Yanlış',
            color: colors.danger,
          ),
          GameResultStat(emoji: '🎯', value: '%$isabet', label: 'İsabet'),
        ],
        onRetry: _retry,
      );
    }
    return _buildBoard(context);
  }

  Widget _buildBoard(BuildContext context) {
    final colors = context.watch<ThemeProvider>().colors;
    final soru = _queue[_index];
    return Scaffold(
      appBar: AppBar(title: const Text('⚡ Hızlı Karar')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Soru ${_index + 1} / ${_queue.length}', style: TextStyle(fontSize: 13, color: colors.textFaint)),
                  Text('Doğru: $_correct', style: const TextStyle(fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: (_secondsLeft <= 1 ? colors.danger : colors.violet).withValues(alpha: 0.16),
                    border: Border.all(color: _secondsLeft <= 1 ? colors.danger : colors.violet, width: 2),
                  ),
                  child: Text(
                    '$_secondsLeft',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: _secondsLeft <= 1 ? colors.danger : colors.violet,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: colors.glass2,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: colors.border),
                        ),
                        child: Text(
                          soru.metin,
                          style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(height: 18),
                      _buildOption(context, 0, 'A', soru.secenekA, colors),
                      const SizedBox(height: 12),
                      _buildOption(context, 1, 'B', soru.secenekB, colors),
                      if (_showResult && _timedOut) ...[
                        const SizedBox(height: 14),
                        Text('⏰ Süre doldu, otomatik yanlış sayıldı.', style: TextStyle(color: colors.danger, fontWeight: FontWeight.w700)),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOption(BuildContext context, int idx, String letter, String text, KpssColors colors) {
    final soru = _queue[_index];
    Color? borderColor;
    Color? bgColor;
    if (_showResult) {
      if (idx == soru.correctIndex) {
        borderColor = colors.success;
        bgColor = colors.success.withValues(alpha: 0.14);
      } else if (idx == _given) {
        borderColor = colors.danger;
        bgColor = colors.danger.withValues(alpha: 0.14);
      }
    }
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: !_showResult ? () => _select(idx) : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: bgColor ?? colors.glass,
          border: Border.all(color: borderColor ?? colors.border, width: borderColor != null ? 1.8 : 1),
        ),
        child: Row(
          children: [
            CircleAvatar(radius: 15, child: Text(letter, style: const TextStyle(fontWeight: FontWeight.w800))),
            const SizedBox(width: 14),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
          ],
        ),
      ),
    );
  }
}
