import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/question.dart';
import '../services/storage_service.dart';
import '../services/quiz_engine.dart';
import '../services/timer_service.dart';
import '../services/sound_service.dart';
import '../services/auth_service.dart';
import '../services/cloud_sync_service.dart';
import 'result_screen.dart';
import 'placement_result_screen.dart';

const int kAutoSecsPerQ = 65; // KPSS GY-GK oranı

class QuizScreen extends StatefulWidget {
  final String? subjectId, subjectAd, topicId, topicBaslik;
  final List<Question>? questions;
  final bool isFullTest;
  final bool resume;
  /// Bu oturum Yanlışlarım ("Yanlışlar Testi") pratik oturumu mu? — bkz.
  /// wrong_bank_screen.dart. Genel istatistiklere (attempts/solved) dahil
  /// edilmez; sadece yanlış bankasının kendi durumunu etkiler (Fix 1).
  final bool isWrongBankMode;
  /// Bu oturum "Beni Sına" teşhis (yerleştirme) sınavı mı? — bkz.
  /// placement_exam_screen.dart. Bitince normal ResultScreen yerine
  /// ders bazlı zayıf/güçlü analiz ekranı (PlacementResultScreen) açılır
  /// (bkz. _finish()).
  final bool isPlacementExam;

  const QuizScreen({
    super.key,
    required String this.subjectId,
    required String this.subjectAd,
    required String this.topicId,
    required String this.topicBaslik,
    required List<Question> this.questions,
    required this.isFullTest,
    this.isWrongBankMode = false,
    this.isPlacementExam = false,
  }) : resume = false;

  /// QuizEngine'de restoreFromDraft() ile önceden yüklenmiş, yarıda kalmış
  /// bir testi devam ettirmek için — bkz. home_screen.dart "yarıda kalan
  /// sınav" kartı.
  const QuizScreen.resume({super.key})
      : subjectId = null,
        subjectAd = null,
        topicId = null,
        topicBaslik = null,
        questions = null,
        isFullTest = false,
        isWrongBankMode = false,
        isPlacementExam = false,
        resume = true;

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  int _perqTimerIndex = -1;
  List<int> _perqRemaining = [];

  // Fix 2: her sorunun şıkları bu OTURUM (bu QuizScreen örneği) boyunca bir
  // kez karıştırılıp soru index'ine göre önbelleğe alınır — aynı soru bu
  // oturumda tekrar gösterildiğinde (ör. Önceki/Sonraki ile geri dönülünce)
  // sıra SABİT kalır, ama testi yeniden başlatınca (yeni QuizScreen örneği,
  // dolayısıyla yeni bir cache) sıra yeniden karışır.
  final Map<int, List<int>> _optionOrderCache = {};
  // Fix 4: normal testte cevap verilince gösterilecek motivasyon cümlesi —
  // aynı soru görüntülemesi boyunca sabit kalsın diye (her rebuild'de
  // değişmesin diye) bir kez seçilip önbelleğe alınıyor.
  final Map<int, String> _motivationCache = {};
  final Random _rng = Random();

  static const List<String> _kCorrectMsgs = [
    'Harika, devam et! 🎉',
    'Süpersin, bu tempoyu koru! 💪',
    'Tam isabet, çok iyi gidiyorsun!',
    'Bravo! Bir doğru daha cebe kondu.',
    'Mükemmel, aynen böyle devam et!',
  ];
  static const List<String> _kWrongMsgs = [
    'Yanlış oldu ama bak neden:',
    'Olsun, hatalardan öğreniyoruz — işte doğrusu:',
    'Bu sefer olmadı, ama pes yok! Açıklamaya bir göz at:',
    'Herkes yanlış yapar, önemli olan öğrenmek:',
    'Tam olmadı, ama şimdi öğreneceğin şey kalıcı olacak:',
  ];

  /// Fix 2: bu soru index'i için karıştırılmış şık sırası — önbellekte yoksa
  /// (ilk gösterim ya da yeni bir oturum) yeni bir karışım üretir.
  List<int> _orderFor(int qIndex, int len) {
    final cached = _optionOrderCache[qIndex];
    if (cached != null && cached.length == len) return cached;
    final order = List<int>.generate(len, (i) => i)..shuffle(_rng);
    _optionOrderCache[qIndex] = order;
    return order;
  }

  String _motivationFor(int qIndex, bool correct) {
    return _motivationCache.putIfAbsent(qIndex, () {
      final pool = correct ? _kCorrectMsgs : _kWrongMsgs;
      return pool[_rng.nextInt(pool.length)];
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  @override
  void dispose() {
    // Ekrandan çıkılınca (test bitişi, geri tuşu, vb.) Adaptasyon Sesleri
    // çalıyorsa hemen durdurulur — arka planda çalmaya devam etmesin.
    // ignore: unawaited_futures
    context.read<SoundService>().stopFocusAmbience();
    super.dispose();
  }

  void _boot() {
    final quiz = context.read<QuizEngine>();
    final storage = context.read<StorageService>();
    final settings = storage.getSettings();
    final timerMode = settings['timerMode'] as String? ?? 'auto';
    final secsPerQ = (settings['secsPerQ'] as int?) ?? 65;

    // "Adaptasyon Sesleri" ayarı açıksa, bu test oturumu aktif kaldığı sürece
    // arka planda düşük sesle sınav salonu atmosferi çalınır (bkz.
    // SoundService.startFocusAmbience) — dispose()'da durdurulur.
    if (settings['adaptationSoundsEnabled'] == true) {
      context.read<SoundService>().startFocusAmbience();
    }

    if (widget.resume) {
      // QuizEngine.restoreFromDraft() zaten çağrılmış olmalı (bkz.
      // home_screen.dart "yarıda kalan sınav" kartı) — burada sadece
      // zamanlayıcıyı, geçen süre düşülerek kaldığı yerden başlatıyoruz.
      // Fix 4: zamanlayıcı SADECE deneme/tam sınav modunda var — normal
      // testlerde (ve Yanlışlarım'da) zamanlayıcı tamamen kaldırıldı.
      if (!quiz.isFullTest) return;
      final elapsedSoFar = DateTime.now().difference(quiz.startedAt ?? DateTime.now()).inSeconds;
      final remaining = (quiz.durationSec - elapsedSoFar).clamp(0, quiz.durationSec);
      if (timerMode != 'perq') {
        context.read<TimerService>().start(remaining, onExpire: _finish);
      } else {
        _perqTimerIndex = -1;
        _perqRemaining = List<int>.filled(quiz.questions.length, secsPerQ);
        setState(() {});
      }
      return;
    }

    final duration = timerMode == 'perq'
        ? widget.questions!.length * secsPerQ
        : widget.questions!.length * kAutoSecsPerQ;

    quiz.start(
      subjectId: widget.subjectId!,
      subjectAd: widget.subjectAd!,
      topicId: widget.topicId!,
      topicBaslik: widget.topicBaslik!,
      questions: widget.questions!,
      durationSec: duration,
      isFullTest: widget.isFullTest,
      isWrongBankMode: widget.isWrongBankMode,
      isPlacementExam: widget.isPlacementExam,
    );

    // Fix 4: normal testlerde (deneme dışı) zamanlayıcı tamamen kaldırıldı —
    // sadece deneme/tam sınav (isFullTest) modunda zamanlayıcı çalışır.
    if (!widget.isFullTest) return;

    if (timerMode != 'perq') {
      context.read<TimerService>().start(duration, onExpire: _finish);
    } else {
      _perqTimerIndex = -1;
      _perqRemaining = List<int>.filled(widget.questions!.length, secsPerQ);
      setState(() {});
    }
  }

  Future<void> _finish() async {
    final quiz = context.read<QuizEngine>();
    // Fix 1: Yanlışlarım oturumları genel "attempts/solved" istatistiklerine
    // dahil edilmez — bu bayrak quiz.finish() state'i sıfırlamadan ÖNCE
    // yakalanıyor.
    final wrongBankMode = quiz.isWrongBankMode;
    context.read<TimerService>().stop();
    final startedAt = quiz.startedAt ?? DateTime.now();
    final elapsed = DateTime.now().difference(startedAt).inSeconds;
    // PlacementResultScreen'in ders bazlı kırılım hesaplayabilmesi için —
    // quiz.finish() bitince quiz.questions'ı boşaltıyor, bu yüzden orijinal
    // (subjectId etiketli) soru listesinin bir kopyasını ÖNCEDEN alıyoruz.
    final isPlacementExam = quiz.isPlacementExam;
    final originalQuestions = List<Question>.of(quiz.questions);
    final result = await quiz.finish(elapsed);
    final storage = context.read<StorageService>();
    if (!wrongBankMode) {
      await storage.addAttempt(result);
      if (result.skor == 100 || result.skor >= 60) {
        await storage.markTopicCompleted(result.topicId);
      }
      if (!widget.isFullTest && !result.topicId.endsWith('-sinav')) {
        final usedKeys = result.review.map((r) => r.soru.length > 50 ? r.soru.substring(0, 50) : r.soru).toList();
        await storage.addUsedQuestions(result.topicId, usedKeys);
      }
    }
    await storage.touchStreak();
    // Girişli kullanıcı için her test bitişi doğal bir "kaydet" anı — buluta
    // yaz (giriş yapılmamışsa CloudSyncService sessizce hiçbir şey yapmaz).
    if (mounted && context.read<AuthService>().isSignedIn) {
      // ignore: unawaited_futures
      CloudSyncService().syncUp(storage);
    }
    if (!mounted) return;
    if (isPlacementExam) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => PlacementResultScreen(result: result, questions: originalQuestions),
      ));
      return;
    }
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ResultScreen(result: result)));
  }

  @override
  Widget build(BuildContext context) {
    final quiz = context.watch<QuizEngine>();
    final storage = context.watch<StorageService>();
    if (!quiz.isActive) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    // Fix 3/4: "deneme" = tam deneme sınavı modu (bkz. home_screen.dart
    // _startFullTest → QuizScreen(isFullTest: true)). Sadece bu modda
    // zamanlayıcı vardır VE şık seçince otomatik sonraki soruya geçilir;
    // normal testler (konu/ders sınavı, Yanlışlarım) bu ikisinden muaf.
    final isDeneme = quiz.isFullTest;
    final settings = storage.getSettings();
    final timerMode = settings['timerMode'] as String? ?? 'auto';
    final secsPerQ = (settings['secsPerQ'] as int?) ?? 65;
    final q = quiz.questions[quiz.currentIndex];

    int displaySecs = 0;
    var isExpiredQuestion = false;
    if (isDeneme) {
      final timer = context.watch<TimerService>();
      var isNewPerqQuestion = false;
      if (timerMode == 'perq') {
        if (_perqRemaining.length != quiz.questions.length) {
          _perqRemaining = List<int>.filled(quiz.questions.length, secsPerQ);
        }
        isNewPerqQuestion = _perqTimerIndex != quiz.currentIndex;
        displaySecs = isNewPerqQuestion ? _perqRemaining[quiz.currentIndex] : timer.remaining;
        if (isNewPerqQuestion) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _switchPerqQuestion(quiz.currentIndex, secsPerQ));
        }
      } else {
        displaySecs = timer.remaining;
      }

      isExpiredQuestion = timerMode == 'perq' && displaySecs <= 0;

      // JS updateTimer(): son 5 saniye tik-tak sesi (Timer her saniye bir kez
      // notifyListeners() çağırıyor, bu build de saniyede bir kez tetikleniyor).
      if (displaySecs <= 5 && displaySecs > 0) {
        context.read<SoundService>().tick();
      }
    }

    final answeredIdx = quiz.answers[quiz.currentIndex];
    // Fix 4: normal testte (deneme dışı) cevap verilince açıklama + motivasyon
    // mesajı gösterilir; deneme modunda hiç durmadan sonraki soruya geçildiği
    // için burada bir geri bildirim paneli yok.
    final showFeedback = !isDeneme && answeredIdx != null;
    final order = _orderFor(quiz.currentIndex, q.secenekler.length);

    return Scaffold(
      appBar: AppBar(
        title: Text('${quiz.subjectAd} • ${quiz.topicBaslik}', style: const TextStyle(fontSize: 14)),
        actions: isDeneme
            ? [
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Center(
                    child: Text(
                      TimerService.format(displaySecs),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: displaySecs <= 5 ? Colors.red : null,
                      ),
                    ),
                  ),
                ),
              ]
            : null,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Soru ${quiz.currentIndex + 1} / ${quiz.questions.length}',
                style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 8),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: quiz.questions.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (context, i) {
                  final answered = quiz.answers[i] != null;
                  final current = i == quiz.currentIndex;
                  return InkWell(
                    onTap: () {
                      context.read<SoundService>().click();
                      quiz.goTo(i);
                    },
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: current
                          ? Theme.of(context).colorScheme.primary
                          : answered
                              ? Colors.green.withValues(alpha: 0.3)
                              : null,
                      child: Text('${i + 1}', style: const TextStyle(fontSize: 12)),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            if (isExpiredQuestion)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                ),
                child: const Text('⏱️ Bu sorunun süresi doldu — cevabını artık değiştiremezsin.',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(q.soru, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 16),
                    for (var pos = 0; pos < order.length; pos++)
                      _OptionTile(
                        letter: String.fromCharCode(65 + pos),
                        text: q.secenekler[order[pos]],
                        selected: answeredIdx == order[pos],
                        // Deneme: sadece süre dolunca kilitlenir. Normal test:
                        // cevap verilince (açıklama gösterilirken) kilitlenir.
                        locked: isExpiredQuestion || (!isDeneme && answeredIdx != null),
                        showResult: showFeedback,
                        isCorrectOption: order[pos] == q.dogruIndex,
                        onTap: () {
                          final realIdx = order[pos];
                          if (isDeneme) {
                            // Fix 3: deneme modunda şıkka dokununca cevap
                            // kaydedilir ve HEMEN sonraki soruya geçilir —
                            // ayrı bir "Sonraki" butonuna gerek yok.
                            if (isExpiredQuestion) return;
                            quiz.answer(realIdx);
                            if (quiz.currentIndex < quiz.questions.length - 1) {
                              quiz.next();
                            }
                          } else {
                            // Normal test: bir kez cevaplanınca kilitlenir,
                            // açıklama gösterilir; ilerlemek için Sonraki/
                            // Önceki butonları kullanılır.
                            if (answeredIdx != null) return;
                            quiz.answer(realIdx);
                          }
                        },
                      ),
                    if (showFeedback) ...[
                      const SizedBox(height: 12),
                      _FeedbackPanel(
                        correct: answeredIdx == q.dogruIndex,
                        motivation: _motivationFor(quiz.currentIndex, answeredIdx == q.dogruIndex),
                        aciklama: q.aciklama,
                        distractorAciklama: q.distractorAciklama,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [
                  OutlinedButton(
                    onPressed: quiz.currentIndex == 0
                        ? null
                        : () {
                            context.read<SoundService>().click();
                            quiz.prev();
                          },
                    child: const Text('← Önceki'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () async {
                      context.read<SoundService>().click();
                      final unanswered = quiz.answers.where((a) => a == null).length;
                      if (unanswered > 0) {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            content: Text('$unanswered soru boş. Yine de bitirmek istiyor musun?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
                              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Bitir')),
                            ],
                          ),
                        );
                        if (ok != true) return;
                      }
                      _finish();
                    },
                    child: const Text('Testi Bitir'),
                  ),
                ]),
                // Fix 3: deneme modunda ilerleme otomatik olduğu için ayrı bir
                // "Sonraki" butonuna gerek yok — sadece normal testte gösterilir.
                if (!isDeneme && quiz.currentIndex < quiz.questions.length - 1)
                  ElevatedButton(
                    onPressed: () {
                      context.read<SoundService>().click();
                      quiz.next();
                    },
                    child: const Text('Sonraki →'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Soru başına süre modu: sadece gerçekten yeni bir soruya geçildiğinde
  // zamanlayıcıyı yeniden başlat; önceki sorunun kalan süresini kaydet,
  // geri dönülünce kaldığı yerden devam etsin.
  void _switchPerqQuestion(int newIndex, int secsPerQ) {
    if (_perqTimerIndex == newIndex) return;
    final timer = context.read<TimerService>();
    if (_perqTimerIndex != -1 && _perqTimerIndex < _perqRemaining.length) {
      _perqRemaining[_perqTimerIndex] = timer.remaining;
    }
    _perqTimerIndex = newIndex;
    timer.start(_perqRemaining[newIndex], onExpire: () {
      final quiz = context.read<QuizEngine>();
      if (quiz.currentIndex < quiz.questions.length - 1) {
        quiz.next();
      } else {
        _finish();
      }
    });
  }
}

class _OptionTile extends StatelessWidget {
  final String letter, text;
  final bool selected, locked;
  final bool showResult;
  final bool isCorrectOption;
  final VoidCallback onTap;
  const _OptionTile({
    required this.letter,
    required this.text,
    required this.selected,
    required this.locked,
    required this.onTap,
    this.showResult = false,
    this.isCorrectOption = false,
  });

  @override
  Widget build(BuildContext context) {
    // Fix 4: cevap verildikten sonra (normal testte) doğru şık yeşil, yanlış
    // seçilen şık kırmızı vurgulanır — açıklama panelinden önce görsel geri
    // bildirim.
    Color borderColor;
    Color? bgColor;
    if (showResult && isCorrectOption) {
      borderColor = Colors.green;
      bgColor = Colors.green.withValues(alpha: 0.14);
    } else if (showResult && selected && !isCorrectOption) {
      borderColor = Colors.red;
      bgColor = Colors.red.withValues(alpha: 0.14);
    } else {
      borderColor = selected ? Theme.of(context).colorScheme.primary : Colors.grey.withValues(alpha: 0.3);
      bgColor = selected ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12) : null;
    }
    return Opacity(
      opacity: locked && !showResult ? 0.55 : 1,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: InkWell(
          onTap: locked ? null : onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
              color: bgColor,
            ),
            child: Row(
              children: [
                CircleAvatar(radius: 13, child: Text(letter, style: const TextStyle(fontSize: 12))),
                const SizedBox(width: 12),
                Expanded(child: Text(text)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Fix 4: normal testte (deneme dışı) cevap verildikten sonra gösterilen
/// panel — ÖNCE kısa bir motivasyon cümlesi (doğru/yanlışa göre değişir),
/// SONRA sorunun gerçek açıklaması (aciklama).
class _FeedbackPanel extends StatelessWidget {
  final bool correct;
  final String motivation;
  final String aciklama;
  final String? distractorAciklama;
  const _FeedbackPanel({
    required this.correct,
    required this.motivation,
    required this.aciklama,
    this.distractorAciklama,
  });

  @override
  Widget build(BuildContext context) {
    final color = correct ? Colors.green : Colors.orange;
    // Yanlış cevaplandığında, varsa "muhtemelen bunu neden seçtin" açıklamasını
    // (distractorAciklama) da göster — doğru cevaplandığında sadece aciklama.
    final showDistractor = !correct && (distractorAciklama?.trim().isNotEmpty ?? false);
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(motivation, style: TextStyle(fontWeight: FontWeight.w800, color: color)),
          if (showDistractor) ...[
            const SizedBox(height: 8),
            Text('🤔 Muhtemelen bunu düşündün:', style: TextStyle(fontWeight: FontWeight.w700, color: color.withValues(alpha: 0.9), fontSize: 12.5)),
            const SizedBox(height: 3),
            Text(distractorAciklama!.trim(), style: const TextStyle(height: 1.4, fontStyle: FontStyle.italic)),
          ],
          if (aciklama.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            if (showDistractor)
              Text('✅ Doğrusu:', style: TextStyle(fontWeight: FontWeight.w700, color: color.withValues(alpha: 0.9), fontSize: 12.5)),
            if (showDistractor) const SizedBox(height: 3),
            Text(aciklama, style: const TextStyle(height: 1.4)),
          ],
        ],
      ),
    );
  }
}
