import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/badge.dart';
import '../../models/subject.dart';
import '../../models/question.dart';
import '../../services/remote_question_service.dart';
import '../../services/sound_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_provider.dart';
import 'quick_modes_shared.dart';

/// Günün Patronu — günde 20 özel soru, günde SADECE 1 kez oynanabilir
/// (premium/ücretsiz ayrımı YOK — tarihe göre herkes için kilitlenir, bkz.
/// StorageService.hasPlayedGununPatronuToday). Tamamlayan kullanıcı 7. kez
/// tamamladığında 'gunun-patronu' rozetini kazanır (bkz. models/badge.dart).
const int kGununPatronuSoruSayisi = 20;

class GununPatronuScreen extends StatefulWidget {
  final List<Subject> subjects;
  const GununPatronuScreen({super.key, required this.subjects});

  @override
  State<GununPatronuScreen> createState() => _GununPatronuScreenState();
}

class _GununPatronuScreenState extends State<GununPatronuScreen> {
  final _rnd = Random();
  bool _locked = false;
  bool _loading = true;
  bool _noQuestions = false;
  bool _finished = false;

  List<Question> _questions = [];
  int _index = 0;
  int _correct = 0;
  int? _given;
  bool _showResult = false;
  List<BadgeDef> _newlyUnlocked = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _boot() async {
    final storage = context.read<StorageService>();
    if (storage.hasPlayedGununPatronuToday()) {
      if (!mounted) return;
      setState(() {
        _locked = true;
        _loading = false;
      });
      return;
    }

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

    final selected = pool.take(kGununPatronuSoruSayisi).toList();
    setState(() {
      _questions = selected;
      _index = 0;
      _correct = 0;
      _given = null;
      _showResult = false;
      _finished = false;
      _loading = false;
    });
  }

  void _select(int idx) {
    if (_showResult || _index >= _questions.length) return;
    context.read<SoundService>().click();
    final correct = idx == _questions[_index].dogruIndex;
    setState(() {
      _given = idx;
      _showResult = true;
      if (correct) _correct++;
    });
  }

  Future<void> _next() async {
    context.read<SoundService>().click();
    if (_index + 1 < _questions.length) {
      setState(() {
        _index++;
        _given = null;
        _showResult = false;
      });
      return;
    }
    // Tur tamamlandı (skordan bağımsız) — bugünü kilitle ve sayaç artır.
    final storage = context.read<StorageService>();
    await storage.markGununPatronuCompleted();
    final unlocked = await checkAndUnlockBadges(storage, widget.subjects);
    if (!mounted) return;
    setState(() {
      _newlyUnlocked = unlocked;
      _finished = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_locked) {
      return Scaffold(
        appBar: AppBar(title: const Text('👑 Günün Patronu')),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('👑', style: TextStyle(fontSize: 44)),
                  const SizedBox(height: 12),
                  const Text(
                    "Bugünün Patronu'nu zaten yendin!",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Yarın tekrar gel, yeni 20 özel soru seni bekliyor.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.watch<ThemeProvider>().colors.textFaint, height: 1.5),
                  ),
                  const SizedBox(height: 20),
                  OutlinedButton(
                    onPressed: () {
                      context.read<SoundService>().click();
                      Navigator.of(context).pop();
                    },
                    child: const Text('Menüye Dön'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    if (_noQuestions) {
      return const Scaffold(body: Center(child: Text('Yeterli soru bulunamadı.')));
    }
    if (_finished) {
      final storage = context.read<StorageService>();
      final count = storage.getGununPatronuCompletedCount();
      return QuickModeResultCard(
        title: '👑 Günün Patronu',
        emoji: _correct >= (kGununPatronuSoruSayisi * 0.7) ? '🎉' : '👑',
        message: '$_correct / ${_questions.length} doğru yaptın!',
        subMessage: 'Günün Patronu\'nu $count kez tamamladın (rozet için 7 gerekli).'
            '${_newlyUnlocked.isNotEmpty ? ' 🏅 Yeni rozet: ${_newlyUnlocked.map((b) => b.name).join(', ')}!' : ''}',
      );
    }
    return _buildBoard(context);
  }

  Widget _buildBoard(BuildContext context) {
    final colors = context.watch<ThemeProvider>().colors;
    final q = _questions[_index];
    return Scaffold(
      appBar: AppBar(title: const Text('👑 Günün Patronu')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Soru ${_index + 1} / ${_questions.length}', style: TextStyle(fontSize: 13, color: colors.textFaint)),
                  Text('Doğru: $_correct', style: const TextStyle(fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(value: _index / _questions.length, minHeight: 6),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: SingleChildScrollView(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: colors.glass2,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: colors.gold, width: 1.2),
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
                              child: Text(_index + 1 < _questions.length ? 'Sonraki Soru →' : 'Turu Bitir'),
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
