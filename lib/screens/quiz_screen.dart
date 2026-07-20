import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/question.dart';
import '../services/storage_service.dart';
import '../services/quiz_engine.dart';
import '../services/timer_service.dart';
import '../services/sound_service.dart';
import '../services/tts_service.dart';
import '../services/auth_service.dart';
import '../services/cloud_sync_service.dart';
import 'result_screen.dart';
import 'placement_result_screen.dart';

const int kAutoSecsPerQ = 65; // KPSS GY-GK oranı

// ── Test süresi seçimi ──
// Kullanıcı toplam süreyi ELLE (dakika olarak) yazar; hızlı seçim için
// "soru başına saniye" preset'leri de sunulur (bkz. showTestSuresiDialog).
const List<int> kSureOnayarlariSn = [5, 10, 15, 20, 25, 30];
const int kMinTestDakika = 1;
const int kMaxTestDakika = 300; // 5 saat — absürt değerlere karşı üst sınır

/// Test başlamadan önce toplam süreyi sorar.
///
/// Dönüş değeri:
/// * `null` → kullanıcı vazgeçti, test BAŞLATILMAMALI
/// * `0`    → "Süresiz" seçildi (sayaç geri sayım yapmaz)
/// * `> 0`  → toplam test süresi (SANİYE)
Future<int?> showTestSuresiDialog(BuildContext context, int soruSayisi) {
  return showDialog<int>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _TestSuresiDialog(soruSayisi: soruSayisi),
  );
}

class _TestSuresiDialog extends StatefulWidget {
  final int soruSayisi;
  const _TestSuresiDialog({required this.soruSayisi});

  @override
  State<_TestSuresiDialog> createState() => _TestSuresiDialogState();
}

class _TestSuresiDialogState extends State<_TestSuresiDialog> {
  late final TextEditingController _ctrl;
  int? _seciliOnayar; // seçili "soru başına saniye" preset'i (varsa)
  String? _hata;

  @override
  void initState() {
    super.initState();
    // Varsayılan: soru başına 60 saniye → soru sayısı kadar dakika.
    _ctrl = TextEditingController(text: '${widget.soruSayisi.clamp(kMinTestDakika, kMaxTestDakika)}');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Preset seçilince toplam süre = soru sayısı × saniye (dakikaya yuvarlanır).
  void _onayarSec(int saniye) {
    final dakika = (widget.soruSayisi * saniye / 60).ceil().clamp(kMinTestDakika, kMaxTestDakika);
    setState(() {
      _seciliOnayar = saniye;
      _hata = null;
      _ctrl.text = '$dakika';
    });
  }

  /// Girilen dakikayı doğrular; geçersizse `null` döner ve hatayı gösterir.
  int? _dogrula() {
    final ham = _ctrl.text.trim();
    if (ham.isEmpty) {
      setState(() => _hata = 'Lütfen bir süre gir.');
      return null;
    }
    final dakika = int.tryParse(ham);
    if (dakika == null) {
      setState(() => _hata = 'Sadece rakam gir.');
      return null;
    }
    if (dakika < kMinTestDakika) {
      setState(() => _hata = 'En az $kMinTestDakika dakika olmalı.');
      return null;
    }
    if (dakika > kMaxTestDakika) {
      setState(() => _hata = 'En fazla $kMaxTestDakika dakika girebilirsin.');
      return null;
    }
    return dakika;
  }

  @override
  Widget build(BuildContext context) {
    final dakika = int.tryParse(_ctrl.text.trim());
    final soruBasina = (dakika != null && widget.soruSayisi > 0)
        ? (dakika * 60 / widget.soruSayisi).round()
        : null;

    return AlertDialog(
      title: const Text('⏱️ Test Süresi'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.soruSayisi} soruluk test. Toplam süreyi kendin belirle:',
                style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 14),
            TextField(
              controller: _ctrl,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(3),
              ],
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Toplam süre (dakika)',
                border: const OutlineInputBorder(),
                errorText: _hata,
                suffixText: 'dk',
              ),
              onChanged: (_) => setState(() {
                _seciliOnayar = null;
                _hata = null;
              }),
            ),
            const SizedBox(height: 14),
            const Text('Hızlı seçim — soru başına süre',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final sn in kSureOnayarlariSn)
                  ChoiceChip(
                    label: Text('$sn sn'),
                    selected: _seciliOnayar == sn,
                    onSelected: (_) => _onayarSec(sn),
                  ),
              ],
            ),
            if (soruBasina != null) ...[
              const SizedBox(height: 10),
              Text('≈ soru başına $soruBasina saniye',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, 0),
          child: const Text('Süresiz'),
        ),
        ElevatedButton(
          onPressed: () {
            final d = _dogrula();
            if (d == null) return;
            Navigator.pop(context, d * 60);
          },
          child: const Text('Başla'),
        ),
      ],
    );
  }
}

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
  /// Kullanıcının test başlamadan seçtiği TOPLAM süre (saniye) — bkz.
  /// [showTestSuresiDialog]. `null` ya da `0` ise geri sayım yoktur
  /// (deneme/tam sınav modu kendi süresini Ayarlar'dan hesaplamaya devam eder).
  final int? durationSec;

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
    this.durationSec,
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
        durationSec = null,
        resume = true;

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> with WidgetsBindingObserver {
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
  // dispose()'ta context.read güvenli olmadığından (element defunct olabilir ve
  // exception atabilir → ses durmadan kalır), SoundService referansı initState'te
  // yakalanır ve ekrandan çıkışta bununla güvenle durdurulur.
  late final SoundService _soundService;
  // Aynı gerekçeyle (dispose'ta context.read güvenli değil) TTS ve depolama
  // referansları da initState'te yakalanır.
  late final TtsService _ttsService;
  late final StorageService _storageService;

  // ── Çalışma süresi sayacı (madde 4) ──
  // Testte geçirilen süre de mevcut istatistik altyapısına
  // (StorageService.addStudyTime — Çalışma Kronometresi ile aynı alan)
  // yazılır. Uygulama arka plana giderse sayaç duraklatılır ki çalışılmayan
  // süre kaydedilmesin.
  final Stopwatch _studySw = Stopwatch();
  Timer? _studyTicker;
  String? _studySubjectId;
  bool _studySaved = false;

  /// Kullanıcının seçtiği süreyle (madde 1) çalışan düz geri sayım aktif mi?
  /// (Deneme/tam sınav modunun kendi geri sayımından ayrıdır.)
  bool _userCountdown = false;

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
    _soundService = context.read<SoundService>();
    _ttsService = context.read<TtsService>();
    _storageService = context.read<StorageService>();
    WidgetsBinding.instance.addObserver(this);

    // Madde 2: teste girildiği anda konu anlatımının sesli okuması dursun —
    // testin üzerine konuşma devam etmesin.
    _ttsService.stopNow();
    // Madde 3: test boyunca buton tıklama sesleri bastırılır (kullanıcının
    // Ayarlar'daki kalıcı ses tercihi DEĞİŞMEZ, sadece geçici susturma).
    _soundService.setSuppressed(true);

    // Madde 4: testte geçen süre de çalışma süresi olarak kaydedilir.
    _studySw.start();
    _studyTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _studyTicker?.cancel();
    _saveStudyTime();
    // Madde 3: geçici bastırma kaldırılır — uygulamanın geri kalanında
    // tıklama sesleri kullanıcının ayarına göre yine çalar.
    _soundService.setSuppressed(false);
    // Madde 2: ekrandan çıkarken de sesli anlatım kesin olarak dursun.
    _ttsService.stopNow();
    // Ekrandan çıkılınca (test bitişi, geri tuşu, vb.) Adaptasyon Sesleri
    // çalıyorsa hemen durdurulur — arka planda çalmaya devam etmesin.
    // (initState'te yakalanan referans kullanılır; dispose'ta context.read
    // güvenli değildir.)
    // ignore: unawaited_futures
    _soundService.stopFocusAmbience();
    super.dispose();
  }

  /// Uygulama arka plana gidince sesli anlatım susar ve çalışma süresi sayacı
  /// duraklar; geri dönülünce sayaç kaldığı yerden devam eder.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final arkaPlanda = state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached;
    if (arkaPlanda) {
      _ttsService.stopNow();
      _studySw.stop();
    } else if (state == AppLifecycleState.resumed) {
      _studySw.start();
    }
  }

  /// Bu oturumda geçen süreyi mevcut istatistik altyapısına yazar
  /// (StorageService.addStudyTime — Çalışma Kronometresi ile aynı alan).
  /// Bir kereden fazla çağrılsa bile tek kez kaydeder.
  void _saveStudyTime() {
    if (_studySaved) return;
    _studySaved = true;
    _studySw.stop();
    final sn = _studySw.elapsed.inSeconds;
    final subjectId = _studySubjectId;
    if (sn <= 0 || subjectId == null || subjectId.isEmpty) return;
    // ignore: unawaited_futures
    _storageService.addStudyTime(subjectId, sn);
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
      _soundService.startFocusAmbience();
    }

    if (widget.resume) {
      // QuizEngine.restoreFromDraft() zaten çağrılmış olmalı (bkz.
      // home_screen.dart "yarıda kalan sınav" kartı) — burada sadece
      // zamanlayıcıyı, geçen süre düşülerek kaldığı yerden başlatıyoruz.
      _studySubjectId = quiz.subjectId;
      final elapsedSoFar0 = DateTime.now().difference(quiz.startedAt ?? DateTime.now()).inSeconds;
      // Fix 4: deneme dışı testlerde zamanlayıcı yoktu; artık kullanıcı süre
      // seçtiyse (madde 1) taslakta durationSec > 0 olur ve kaldığı yerden
      // geri sayım devam eder.
      if (!quiz.isFullTest) {
        if (quiz.durationSec > 0) {
          final kalan = (quiz.durationSec - elapsedSoFar0).clamp(0, quiz.durationSec);
          _userCountdown = true;
          context.read<TimerService>().start(kalan, onExpire: _finish);
          setState(() {});
        }
        return;
      }
      final elapsedSoFar = elapsedSoFar0;
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

    _studySubjectId = widget.subjectId;

    // Madde 1: kullanıcı test öncesi kendi süresini yazdıysa (ya da preset
    // seçtiyse) o süre esas alınır; yoksa eski davranış korunur — deneme/tam
    // sınavda Ayarlar'dan hesaplanan süre, normal testte ise süre yok (0).
    final userDuration = widget.durationSec ?? 0;
    final otoDuration = timerMode == 'perq'
        ? widget.questions!.length * secsPerQ
        : widget.questions!.length * kAutoSecsPerQ;
    final duration = userDuration > 0
        ? userDuration
        : widget.isFullTest
            ? otoDuration
            : 0;

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

    // Madde 1: kullanıcının kendi belirlediği süre seçildiyse (deneme olsun
    // olmasın) düz bir TOPLAM geri sayım çalışır; süre bitince test kapanır.
    if (userDuration > 0) {
      _userCountdown = true;
      context.read<TimerService>().start(userDuration, onExpire: _finish);
      setState(() {});
      return;
    }

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
    // Madde 4: testte geçen süreyi çalışma süresi istatistiğine yaz (dispose
    // da çağırır ama tek kez kaydedilir).
    _studySubjectId ??= quiz.subjectId;
    _saveStudyTime();
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

    // Madde 1 + 4: geri sayım ya deneme modundan ya da kullanıcının seçtiği
    // süreden gelir. Geri sayım yoksa üstte İLERİ sayan çalışma süresi
    // sayacı gösterilir (konu/test ekranlarında sayaç artık hep işler).
    final hasCountdown = _userCountdown || isDeneme;
    int displaySecs = 0;
    var isExpiredQuestion = false;
    // "Soru başına süre" modu SADECE deneme modunda ve kullanıcı kendi toplam
    // süresini belirlememişken geçerlidir.
    final isPerqMode = isDeneme && !_userCountdown && timerMode == 'perq';
    if (hasCountdown) {
      final timer = context.watch<TimerService>();
      var isNewPerqQuestion = false;
      if (isPerqMode) {
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

      isExpiredQuestion = isPerqMode && displaySecs <= 0;

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
        // Madde 4: sayaç artık her testte üstte görünür — geri sayım varsa
        // kalan süre, yoksa testte geçen (ileri sayan) süre gösterilir.
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(hasCountdown ? Icons.timer_outlined : Icons.schedule, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    TimerService.format(
                        hasCountdown ? displaySecs : _studySw.elapsed.inSeconds),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: hasCountdown && displaySecs <= 5 ? Colors.red : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
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
                separatorBuilder: (_, _) => const SizedBox(width: 6),
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
            // Alt butonlar artık bottomNavigationBar'da sabit duruyor; içeriğin
            // son kartı butonların altında kalmasın diye boşluk bırakılıyor.
            const SizedBox(height: 12),
          ],
        ),
      ),
      // Madde 5: Önceki / Sonraki / Testi Bitir butonları ekranın ALT KISMINDA
      // sabit — içerik kaydırılsa bile hep görünür, üçü eşit genişlikte.
      bottomNavigationBar: _QuizBottomBar(
        isFirst: quiz.currentIndex == 0,
        isLast: quiz.currentIndex >= quiz.questions.length - 1,
        onPrev: () {
          context.read<SoundService>().click();
          quiz.prev();
        },
        onNext: () {
          context.read<SoundService>().click();
          quiz.next();
        },
        onFinish: () async {
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

/// Madde 5: test ekranının altında SABİT duran gezinme çubuğu.
///
/// Üç buton (Önceki / Sonraki / Testi Bitir) eşit genişlikte dağıtılır, her
/// biri kendi rengiyle ayrışır ve devre dışı durumlar (ilk soruda "Önceki",
/// son soruda "Sonraki") soluk gri gösterilir. SafeArea alt çentiği korur.
class _QuizBottomBar extends StatelessWidget {
  final bool isFirst;
  final bool isLast;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onFinish;

  const _QuizBottomBar({
    required this.isFirst,
    required this.isLast,
    required this.onPrev,
    required this.onNext,
    required this.onFinish,
  });

  // Koyu ve açık temada da yeterli kontrast veren, birbirinden ayrışan tonlar.
  static const Color _oncekiRenk = Color(0xFF546E7A); // nötr gri-mavi
  static const Color _sonrakiRenk = Color(0xFF5B4BC4); // mavi-mor
  static const Color _bitirRenk = Color(0xFF2E7D32); // yeşil (vurgulu)

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Row(
            children: [
              Expanded(
                child: _BarButton(
                  label: 'Önceki',
                  icon: Icons.chevron_left,
                  color: _oncekiRenk,
                  onPressed: isFirst ? null : onPrev,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _BarButton(
                  label: 'Sonraki',
                  icon: Icons.chevron_right,
                  color: _sonrakiRenk,
                  iconAtEnd: true,
                  onPressed: isLast ? null : onNext,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _BarButton(
                  label: 'Testi Bitir',
                  icon: Icons.flag_rounded,
                  color: _bitirRenk,
                  onPressed: onFinish,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Alt çubuktaki tek bir renkli buton. Metin küçük ekranlarda taşmasın diye
/// tek satıra sıkıştırılır (ellipsis) ve ikon+metin ortalanır.
class _BarButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool iconAtEnd;
  final VoidCallback? onPressed;

  const _BarButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
    this.iconAtEnd = false,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    final ikon = Icon(icon, size: 18);
    final metin = Flexible(
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
      ),
    );

    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        // Devre dışı durum görsel olarak belirgin: soluk gri zemin + soluk yazı.
        disabledBackgroundColor: Colors.grey.withValues(alpha: 0.28),
        disabledForegroundColor: Colors.grey.withValues(alpha: 0.85),
        elevation: disabled ? 0 : 2,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: iconAtEnd
            ? [metin, const SizedBox(width: 2), ikon]
            : [ikon, const SizedBox(width: 2), metin],
      ),
    );
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
