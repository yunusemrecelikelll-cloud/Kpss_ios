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

/// Bilgi Maratonu — GENEL oyun kimliği (günlük ücretsiz hak sayacı için).
const String kBilgiMaratonuGameId = 'bilgi-maratonu';

/// Bilgi Maratonu — tüm derslerden karışık, sonsuz soru akışı. İlk yanlış
/// cevapta seri (streak) biter ve oturum sona erer. En uzun seri
/// StorageService.getBestMarathonStreak/setBestMarathonStreak ile yerel
/// olarak kaydedilir.
class BilgiMaratonuScreen extends StatefulWidget {
  final List<Subject> subjects;
  const BilgiMaratonuScreen({super.key, required this.subjects});

  @override
  State<BilgiMaratonuScreen> createState() => _BilgiMaratonuScreenState();
}

class _BilgiMaratonuScreenState extends State<BilgiMaratonuScreen> {
  final _rnd = Random();
  bool _locked = false;
  bool _loading = true;
  bool _noQuestions = false;
  bool _finished = false;

  List<Question> _pool = [];
  int _ptr = 0;
  Question? _current;
  int? _given;
  bool _showResult = false;
  bool _lastCorrect = false;
  int _streak = 0;
  int _best = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _boot() async {
    final storage = context.read<StorageService>();
    final premium = storage.isPremiumUser();
    if (!premium) {
      final gp = storage.getGamePlayState(kBilgiMaratonuGameId);
      if ((gp['plays'] as int) >= kFreeGameDailyLimit) {
        if (!mounted) return;
        setState(() => _locked = true);
        return;
      }
      await storage.useGamePlay(kBilgiMaratonuGameId);
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

    setState(() {
      _pool = pool;
      _ptr = 0;
      _best = storage.getBestMarathonStreak();
      _streak = 0;
      _given = null;
      _showResult = false;
      _finished = false;
      _current = _popNext();
      _loading = false;
    });
  }

  Question _popNext() {
    if (_ptr >= _pool.length) {
      _pool = List<Question>.from(_pool)..shuffle(_rnd);
      _ptr = 0;
    }
    return _pool[_ptr++];
  }

  void _select(int idx) {
    if (_showResult || _current == null) return;
    context.read<SoundService>().click();
    final correct = idx == _current!.dogruIndex;
    setState(() {
      _given = idx;
      _showResult = true;
      _lastCorrect = correct;
      if (correct) _streak++;
    });
  }

  Future<void> _next() async {
    context.read<SoundService>().click();
    if (_lastCorrect) {
      setState(() {
        _given = null;
        _showResult = false;
        _current = _popNext();
      });
      return;
    }
    final storage = context.read<StorageService>();
    if (_streak > _best) {
      await storage.setBestMarathonStreak(_streak);
      _best = _streak;
    }
    if (!mounted) return;
    setState(() => _finished = true);
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
        title: 'Bilgi Maratonu',
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
      final beatBest = _streak >= _best && _streak > 0;
      return QuickModeResultCard(
        title: '🏃 Bilgi Maratonu',
        emoji: beatBest ? '🏆' : '📚',
        message: 'Serin: $_streak doğru',
        subMessage: 'En uzun serin: $_best${beatBest ? ' — yeni rekor! 🎉' : ''}',
        onRetry: _retry,
      );
    }
    return _buildBoard(context);
  }

  Widget _buildBoard(BuildContext context) {
    final colors = context.watch<ThemeProvider>().colors;
    final q = _current!;
    return Scaffold(
      appBar: AppBar(title: const Text('🏃 Bilgi Maratonu')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Seri: $_streak', style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text('En uzun serin: $_best', style: TextStyle(fontSize: 12.5, color: colors.textFaint)),
                ],
              ),
              if (q.subjectAd != null) ...[
                const SizedBox(height: 4),
                Text(q.subjectAd!, style: TextStyle(fontSize: 11.5, color: colors.textFaint, fontWeight: FontWeight.w700)),
              ],
              const SizedBox(height: 10),
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
                        if (_showResult) ...[
                          const Divider(height: 24),
                          Text('💡 ${q.aciklama}', style: const TextStyle(fontSize: 13)),
                          const SizedBox(height: 14),
                          Align(
                            alignment: Alignment.centerRight,
                            child: ElevatedButton(
                              onPressed: _next,
                              child: Text(_lastCorrect ? 'Sonraki Soru →' : 'Serini Bitir'),
                            ),
                          ),
                        ],
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
    if (_showResult) {
      if (i == q.dogruIndex) {
        borderColor = colors.success;
        bgColor = colors.success.withValues(alpha: 0.12);
      } else if (i == _given) {
        borderColor = colors.danger;
        bgColor = colors.danger.withValues(alpha: 0.12);
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: !_showResult ? () => _select(i) : null,
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
