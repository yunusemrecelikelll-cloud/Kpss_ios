import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/question.dart';
import '../services/storage_service.dart';
import '../services/quiz_engine.dart';
import '../services/timer_service.dart';
import '../services/sound_service.dart';
import '../services/tts_service.dart';
import '../services/auth_service.dart';
import '../services/cloud_sync_service.dart';
import '../services/in_app_notice_service.dart';
import '../theme/theme_provider.dart';
import '../theme/design_system.dart';
import '../widgets/karalama_katmani.dart';
import 'result_screen.dart';
import 'placement_result_screen.dart';

const int kAutoSecsPerQ = 65; // KPSS GY-GK oranı

/// Şık metninin BAŞINDAKİ eski harf önekini ("A) ", "B)", "C." gibi) temizler.
/// Bazı soru verilerinde şıklar "A) ...", "B) ..." biçiminde GÖMÜLÜ harfle
/// kaydedilmiş; şıklar karıştırılınca (shuffle) soldaki KONUM etiketi (A-E) ile
/// metindeki gömülü harf uyuşmuyordu ("A" etiketli şıkta metin "E)" ile
/// başlıyordu). Etiketi konumdan üretiyoruz, metindeki gömülü harfi atıyoruz.
final RegExp _kSikOnekRegex = RegExp(r'^\s*[A-Ea-e]\s*[\)\.]\s+');
String sikMetni(String s) => s.replaceFirst(_kSikOnekRegex, '').trimLeft();

// ── Test süresi ──
// Süre artık test öncesi sorulmaz; kullanıcının Ayarlar > "⏱️ Test Süresi"
// tercihinden hesaplanır (bkz. testSuresiHesapla). Preset'ler ayarlar
// ekranındaki hızlı seçim çipleri için kullanılır.
const List<int> kSureOnayarlariSn = [5, 10, 15, 20, 25, 30];
const int kMinTestDakika = 1;
const int kMaxTestDakika = 300; // 5 saat — absürt değerlere karşı üst sınır

/// Bir konunun "tamamlandı" sayılması için testinden alınması gereken en
/// düşük yüzde. Anasayfadaki ders kartlarında görünen "0/5 konu" sayacı ve
/// Profil'deki "Konu Tamamlanan" istatistiği bu eşiğe göre hesaplanır.
const int kTopicCompletionThreshold = 80;

/// Uygulama ilk kurulduğunda geçerli olan soru-cevap davranışı.
/// 'herZamanDur' = her cevaptan sonra açıklama gösterilir ve kullanıcı
/// "Sonraki" ile ilerler. Ayarlar > Soru Cevap bölümünden değiştirilebilir.
const String kVarsayilanSoruCevapModu = 'herZamanDur';

/// Ayarlardaki süre tercihine göre bir testin TOPLAM süresini (SANİYE) verir.
///
/// [settings] → StorageService.getSettings() çıktısı.
/// Dönüş değeri:
/// * `0`   → "Süresiz" (geri sayım yok)
/// * `> 0` → toplam test süresi (saniye)
int testSuresiHesapla(Map<String, dynamic> settings, int soruSayisi) {
  final mod = (settings['timerMode'] as String?) ?? 'auto';
  if (mod == 'off' || soruSayisi <= 0) return 0;
  final soruBasina = mod == 'perq'
      ? ((settings['secsPerQ'] as int?) ?? kAutoSecsPerQ)
      : kAutoSecsPerQ;
  final toplam = soruSayisi * soruBasina;
  // Absürt değerlere karşı makul aralıkta tut.
  return toplam.clamp(kMinTestDakika * 60, kMaxTestDakika * 60);
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
  /// Ayarlardaki tercihten hesaplanan TOPLAM süre (saniye) — bkz.
  /// [testSuresiHesapla]. `null` ya da `0` ise geri sayım yoktur
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
  // Karalama (scratchpad) katmanı açık mı? (kullanıcı isteği: testlerde çizim/
  // yazı yapılabilen, alta sabit, cevapların üzerinde açılan alan.)
  bool _karalamaAcik = false;
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

  /// Yanlış cevapta gösterilen "hangi şıkkı seçtin" notu.
  ///
  /// Yapay zeka YOK: sadece kullanıcının işaretlediği şıkkın ve doğru şıkkın
  /// METNİ kullanılarak kısa bir çerçeve cümlesi kurulur; sorunun kendi
  /// `aciklama` alanı panelde ayrıca gösterilir. Veri uydurulmaz.
  String? _secimNotu(List<String> secenekler, int? verilenIndex, int dogruIndex) {
    if (verilenIndex == null) return null;
    if (verilenIndex < 0 || verilenIndex >= secenekler.length) return null;
    if (dogruIndex < 0 || dogruIndex >= secenekler.length) return null;
    return '"${sikMetni(secenekler[verilenIndex])}" şıkkını işaretledin. '
        'Doğrusu "${sikMetni(secenekler[dogruIndex])}".';
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

    // Test sürerken uygulama içi bildirim afişleri (yeni mesaj / arkadaşlık
    // isteği) ERTELENİR; test bitince birikenler sırayla gösterilir
    // (kullanıcı isteği — dikkat dağılmasın). Bekletme sayaçlıdır, dispose'ta
    // mutlaka geri açılır.
    InAppNoticeService.instance.beklet();

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
    // Test bitti/terk edildi: ertelenen bildirim afişleri artık gösterilebilir.
    InAppNoticeService.instance.devamEt();
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
      // "Süresiz" denemede (durationSec == 0) geri sayım yeniden kurulmaz.
      if (quiz.durationSec <= 0) return;
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

    // SÜRE KURALI: geri sayım YALNIZCA deneme/tam sınavda (isFullTest) vardır
    // ve süresi Ayarlar > "⏱️ Deneme Sınavı Süresi" tercihinden hesaplanır
    // ("Süresiz" seçiliyse 0 döner → geri sayım kurulmaz). Konu testlerinde
    // süre sınırı yoktur; oradan durationSec de gelmez.
    final userDuration = widget.durationSec ?? 0;
    final duration = userDuration > 0
        ? userDuration
        : widget.isFullTest
            ? testSuresiHesapla(settings, widget.questions!.length)
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

    // "Süresiz" tercihinde (duration == 0) denemede de geri sayım kurulmaz.
    if (duration <= 0) return;

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
      // Bir konu "tamamlandı" sayılmak için testinden en az %80 alınmalı.
      // Anasayfadaki "0/5 konu" sayacı bu işarete bakar.
      //
      // Eşik ÖNCEDEN %60'tı; konuyu gerçekten öğrenmeden tamamlanmış
      // göstermemesi için %80'e çıkarıldı. (`skor == 100` kontrolü de
      // gereksizdi — 100 zaten eşiğin üstünde.)
      if (result.skor >= kTopicCompletionThreshold) {
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
    final c = context.watch<ThemeProvider>().colors;
    final settings = storage.getSettings();
    final timerMode = settings['timerMode'] as String? ?? 'auto';
    final secsPerQ = (settings['secsPerQ'] as int?) ?? 65;
    final q = quiz.questions[quiz.currentIndex];

    // Geri sayım SADECE deneme/tam sınavda ve orada da süre "Süresiz"
    // değilse (quiz.durationSec > 0) çalışır. Konu testlerinde geri sayım
    // yoktur; üstte İLERİ sayan çalışma süresi sayacı gösterilir (istatistik
    // amaçlı, bir sınır değil).
    final hasCountdown = _userCountdown || (isDeneme && quiz.durationSec > 0);
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
    final isDogru = answeredIdx != null && answeredIdx == q.dogruIndex;
    // Ayarlar > "❓ Soru Cevap" tercihi (konu testleri için):
    //   'testSonunda'  → şık seçilince anında sonraki soruya geç, açıklama yok
    //   'yanlistaDur'  → doğruysa geç, yanlışsa soruda kal ve açıklamayı göster
    //   'herZamanDur'  → her hâlükârda soruda kal ve açıklamayı göster
    // Deneme/tam sınavda mod ne olursa olsun anında geçilir, açıklama sınav
    // sonunda görünür.
    final soruCevapModu = (settings['soruCevapModu'] as String?) ?? kVarsayilanSoruCevapModu;
    final showFeedback = !isDeneme &&
        answeredIdx != null &&
        (soruCevapModu == 'herZamanDur' ||
            (soruCevapModu == 'yanlistaDur' && !isDogru));
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
        child: Stack(
          children: [
            Column(
          children: [
            // ── Sabit üst panel: solda toplam soru, ortada aktif soru
            // (otomatik ortalanır), animasyonlu geçiş (kullanıcı isteği) ──
            _SoruNavPaneli(
              total: quiz.questions.length,
              current: quiz.currentIndex,
              // Her soru için durum: null = cevaplanmadı, true = doğru, false = yanlış
              // (cevaplananların üzerinde yeşil/kırmızı gösterilir — kullanıcı isteği).
              dogruMu: [
                for (var i = 0; i < quiz.questions.length; i++)
                  quiz.answers[i] == null
                      ? null
                      : quiz.answers[i] == quiz.questions[i].dogruIndex,
              ],
              onTap: (i) {
                context.read<SoundService>().click();
                quiz.goTo(i);
              },
            ),
            // ── Soru içeriği: sorular arası geçiş animasyonlu (kayarak + solarak) ──
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween<Offset>(
                            begin: const Offset(0.06, 0), end: Offset.zero)
                        .animate(anim),
                    child: child,
                  ),
                ),
                child: ListView(
                  key: ValueKey(quiz.currentIndex),
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (isExpiredQuestion)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: c.warn.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(kDsRadiusSm),
                          border: Border.all(color: c.warn.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                            '⏱️ Bu sorunun süresi doldu — cevabını artık değiştiremezsin.',
                            style: TextStyle(fontWeight: FontWeight.w700, color: c.text)),
                      ),
                    DsCard(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(q.soru,
                              style: TextStyle(
                                  fontSize: 16.5,
                                  height: 1.4,
                                  fontWeight: FontWeight.w700,
                                  color: c.text)),
                          const SizedBox(height: 16),
                    for (var pos = 0; pos < order.length; pos++)
                      _OptionTile(
                        letter: String.fromCharCode(65 + pos),
                        text: sikMetni(q.secenekler[order[pos]]),
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
                            // Konu testi: bir kez cevaplanınca kilitlenir.
                            // Sonrasında ne olacağını "Soru Cevap" modu
                            // belirler — ya anında sonraki soruya geçilir ya
                            // da açıklama gösterilip Sonraki beklenir.
                            if (answeredIdx != null) return;
                            quiz.answer(realIdx);
                            final dogruMu = realIdx == q.dogruIndex;
                            final anindaGec = soruCevapModu == 'testSonunda' ||
                                (soruCevapModu == 'yanlistaDur' && dogruMu);
                            if (anindaGec &&
                                quiz.currentIndex < quiz.questions.length - 1) {
                              quiz.next();
                            }
                          }
                        },
                      ),
                    if (showFeedback) ...[
                      const SizedBox(height: 12),
                      _FeedbackPanel(
                        correct: isDogru,
                        motivation: _motivationFor(quiz.currentIndex, isDogru),
                        aciklama: q.aciklama,
                        distractorAciklama: q.distractorAciklama,
                        // Yanlış cevapta hangi şıkkı işaretlediğini ve
                        // doğrusunun ne olduğunu adıyla anan kısa not.
                        secimNotu: isDogru
                            ? null
                            : _secimNotu(q.secenekler, answeredIdx, q.dogruIndex),
                      ),
                    ],
                  ],
                ),
              ),
              // Alt butonlar bottomNavigationBar'da sabit; son kart altında kalmasın.
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
          ],
        ),
            // ── KARALAMA katmanı: alta SABİT, "sonraki soru" butonlarının
            // üzerinde; açıkken yukarı kayar, cevapların üzerini örter. Ağaçta
            // hep mounted kaldığı için (AnimatedSlide) not/çizim açılıp
            // kapanınca korunur.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: MediaQuery.sizeOf(context).height * 0.52,
              child: IgnorePointer(
                ignoring: !_karalamaAcik,
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  offset: _karalamaAcik ? Offset.zero : const Offset(0, 1.15),
                  child: KaralamaKatmani(
                    onKapat: () => setState(() => _karalamaAcik = false),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.small(
        heroTag: 'karalamaFab',
        backgroundColor: c.violet,
        foregroundColor: Colors.white,
        tooltip: _karalamaAcik ? 'Karalamayı kapat' : 'Karalama defteri',
        onPressed: () => setState(() => _karalamaAcik = !_karalamaAcik),
        child: Icon(_karalamaAcik ? Icons.close_rounded : Icons.edit_rounded),
      ),
      // Madde 5: Önceki / Sonraki / Testi Bitir butonları ekranın ALT KISMINDA
      // sabit — içerik kaydırılsa bile hep görünür, üçü eşit genişlikte.
      bottomNavigationBar: _QuizBottomBar(
        isFirst: quiz.currentIndex == 0,
        isLast: quiz.currentIndex >= quiz.questions.length - 1,
        // Açıklama gösterilirken ilerlemenin tek yolu "Sonraki" — vurgulanır.
        highlightNext: showFeedback,
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

/// Test ekranının üstünde SABİT duran soru-numarası paneli (kullanıcı isteği:
/// "üzerindeki soru sayıları animasyonlu olsun, aynı boyutta; solda toplam
/// soru sayısı; aktif soru panelde ortada").
///
/// • Solda toplam soru sayısı rozeti.
/// • Ortada yatay numara şeridi; aktif soru numarası her değiştiğinde şerit
///   otomatik olarak AKTİF numarayı ORTAYA getirecek şekilde animasyonlu kayar.
/// • Numaralar aynı boyutta; aktif olan renk/gölge ile animasyonlu vurgulanır,
///   cevaplananlar yeşil tonlanır.
class _SoruNavPaneli extends StatefulWidget {
  final int total;
  final int current;

  /// Her soru için: null = cevaplanmadı, true = doğru, false = yanlış.
  final List<bool?> dogruMu;
  final ValueChanged<int> onTap;
  const _SoruNavPaneli({
    required this.total,
    required this.current,
    required this.dogruMu,
    required this.onTap,
  });

  @override
  State<_SoruNavPaneli> createState() => _SoruNavPaneliState();
}

class _SoruNavPaneliState extends State<_SoruNavPaneli> {
  final ScrollController _ctrl = ScrollController();
  static const double _oge = 46; // her numara slotunun yatay genişliği

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ortala(false));
  }

  @override
  void didUpdateWidget(covariant _SoruNavPaneli old) {
    super.didUpdateWidget(old);
    if (old.current != widget.current) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _ortala(true));
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Aktif numarayı görünür alanın ORTASINA getirir (animasyonlu).
  void _ortala(bool animate) {
    if (!_ctrl.hasClients) return;
    final vp = _ctrl.position.viewportDimension;
    final hedef = (widget.current * _oge) - (vp / 2) + (_oge / 2);
    final k = hedef.clamp(0.0, _ctrl.position.maxScrollExtent);
    if (animate) {
      _ctrl.animateTo(k,
          duration: const Duration(milliseconds: 340), curve: Curves.easeOutCubic);
    } else {
      _ctrl.jumpTo(k);
    }
  }

  // Merkeze olan uzaklığa göre boyut/opaklık: aktif büyük ve net, iki yana
  // gittikçe küçük ve saydam (kullanıcı isteği: coverflow etkisi).
  static double _boyut(int d) => switch (d) { 0 => 42, 1 => 34, 2 => 29, 3 => 25, _ => 22 };
  static double _opak(int d) => switch (d) { 0 => 1.0, 1 => 0.7, 2 => 0.45, 3 => 0.28, _ => 0.16 };
  static double _yazi(int d) => switch (d) { 0 => 16, 1 => 13, 2 => 11.5, _ => 10.5 };

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: c.bg2,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          // Sol: toplam soru sayısı
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: c.violet.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.violet.withValues(alpha: 0.35)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${widget.total}',
                    style: TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 16, color: c.text)),
                Text('soru',
                    style: TextStyle(
                        fontSize: 9.5, fontWeight: FontWeight.w700, color: c.textFaint)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Orta/sağ: coverflow numara şeridi (aktif ortada, iki yan silik/küçük)
          Expanded(
            child: SizedBox(
              height: 46,
              child: ListView.builder(
                controller: _ctrl,
                scrollDirection: Axis.horizontal,
                itemExtent: _oge,
                itemCount: widget.total,
                itemBuilder: (context, i) {
                  final d = (i - widget.current).abs();
                  final current = d == 0;
                  final dogru = widget.dogruMu[i]; // null / true / false

                  // Renk: doğru → yeşil, yanlış → kırmızı, cevapsız → cam.
                  final Color dolgu;
                  final Color kenar;
                  final Color yaziRengi;
                  if (dogru == true) {
                    dolgu = c.success;
                    kenar = c.success;
                    yaziRengi = Colors.white;
                  } else if (dogru == false) {
                    dolgu = c.danger;
                    kenar = c.danger;
                    yaziRengi = Colors.white;
                  } else {
                    dolgu = c.glass2;
                    kenar = c.border;
                    yaziRengi = c.textDim;
                  }

                  final boyut = _boyut(d);

                  return Center(
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      opacity: _opak(d),
                      child: GestureDetector(
                        onTap: () => widget.onTap(i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutCubic,
                          width: boyut,
                          height: boyut,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: dolgu,
                            // Aktif soru: mor halka + gölge ile "buradasın" vurgusu.
                            border: Border.all(
                              color: current ? c.violet : kenar,
                              width: current ? 2.2 : 1,
                            ),
                            boxShadow: current
                                ? [
                                    BoxShadow(
                                        color: c.violet.withValues(alpha: 0.5),
                                        blurRadius: 10,
                                        offset: const Offset(0, 3))
                                  ]
                                : null,
                          ),
                          child: Text(
                            '${i + 1}',
                            style: TextStyle(
                              fontSize: _yazi(d),
                              fontWeight: FontWeight.w900,
                              color: dogru == null && current ? c.text : yaziRengi,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Madde 5: test ekranının altında SABİT duran gezinme çubuğu.
///
/// Üç buton (Önceki / Testi Bitir / Sonraki) eşit genişlikte dağıtılır, her
/// biri kendi rengiyle ayrışır ve devre dışı durumlar (ilk soruda "Önceki",
/// son soruda "Sonraki") soluk gri gösterilir. SafeArea alt çentiği korur.
class _QuizBottomBar extends StatelessWidget {
  final bool isFirst;
  final bool isLast;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onFinish;
  /// Açıklama panelinin açık olduğu (Soru Cevap modu 2/3) durumlarda
  /// "Sonraki" butonu vurgulanır — ilerlemenin tek yolu odur.
  final bool highlightNext;

  const _QuizBottomBar({
    required this.isFirst,
    required this.isLast,
    required this.onPrev,
    required this.onNext,
    required this.onFinish,
    this.highlightNext = false,
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
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
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
                  label: 'Testi Bitir',
                  icon: Icons.flag_rounded,
                  color: _bitirRenk,
                  onPressed: onFinish,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _BarButton(
                  label: 'Sonraki',
                  icon: Icons.chevron_right,
                  color: _sonrakiRenk,
                  iconAtEnd: true,
                  highlight: highlightNext,
                  onPressed: isLast ? null : onNext,
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
  /// Dikkat çekmesi gereken buton (açıklama açıkken "Sonraki") — daha kalın
  /// gölge ve beyaz kenarlıkla öne çıkar.
  final bool highlight;

  const _BarButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
    this.iconAtEnd = false,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    final ikon = Icon(icon, size: 21);
    final metin = Flexible(
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
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
        elevation: disabled ? 0 : (highlight ? 8 : 2),
        side: highlight && !disabled
            ? BorderSide(color: Colors.white.withValues(alpha: 0.85), width: 2)
            : null,
        // Dokunma alanı rahat olsun diye dikey padding ve minimum yükseklik
        // artırıldı; üç buton hâlâ eşit genişlikte kalır.
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 16),
        minimumSize: const Size(0, 56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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

  /// Her şıkkın (A/B/C/D/E) kendine ait ayırt edici rengi (kullanıcı isteği:
  /// "şıklar farklı renkli olsun"). Her iki temada da okunur, canlı sabit
  /// renkler (madalya renkleri gibi bilerek sabit).
  // Kullanıcı isteği: şık renkleri YEŞİL ve KIRMIZIYA yakın OLMASIN (bunlar
  // doğru/yanlış geri bildirimine ayrılmıştır); SOLUK/pastel tonlar tercih
  // edildi — birbirinden ayrışan ama nötr renkler.
  static const Map<String, Color> _sikRenkleri = {
    'A': Color(0xFFB0A8E0), // soluk lavanta
    'B': Color(0xFF9BB8D9), // soluk mavi
    'C': Color(0xFFD8C08A), // soluk kum/amber
    'D': Color(0xFFC4A4C9), // soluk erguvan
    'E': Color(0xFFA8B0CC), // soluk gece mavisi
  };

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final sikRenk = _sikRenkleri[letter] ?? c.violet;

    // Cevap sonrası: doğru şık YEŞİL, yanlış seçilen şık KIRMIZI vurgulanır.
    // Cevap öncesi/nötr: her şık KENDİ rengiyle görünür; seçilen daha belirgin.
    Color borderColor;
    Color? bgColor;
    if (showResult && isCorrectOption) {
      borderColor = c.success;
      bgColor = c.success.withValues(alpha: 0.14);
    } else if (showResult && selected && !isCorrectOption) {
      borderColor = c.danger;
      bgColor = c.danger.withValues(alpha: 0.14);
    } else {
      borderColor = sikRenk.withValues(alpha: selected ? 0.95 : 0.5);
      bgColor = sikRenk.withValues(alpha: selected ? 0.16 : 0.06);
    }

    // Rozet rengi: sonuç modunda doğru/yanlışa göre, aksi halde şık rengi.
    final Color rozetRenk = (showResult && isCorrectOption)
        ? c.success
        : (showResult && selected && !isCorrectOption)
            ? c.danger
            : sikRenk;
    // Harf rengi: normal şık rozetleri paletteki SOLUK tonlar olduğundan
    // beyaz harf kaybolur; bu yüzden onlarda DAİMA koyu mürekkep kullanılır.
    // Sadece sonuç rozetlerinde (doygun yeşil/kırmızı) parlaklığa göre koyu/
    // beyaz seçilir. Kullanıcı isteği: harfler her durumda tam görünsün.
    final bool sonucRozeti =
        showResult && (isCorrectOption || (selected && !isCorrectOption));
    final Color harfRenk = sonucRozeti
        ? (rozetRenk.computeLuminance() > 0.55
            ? const Color(0xFF1A1420)
            : Colors.white)
        : const Color(0xFF241C33);

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
              border: Border.all(color: borderColor, width: selected ? 1.6 : 1.2),
              color: bgColor,
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: rozetRenk,
                    boxShadow: [
                      BoxShadow(
                          color: rozetRenk.withValues(alpha: 0.4),
                          blurRadius: 6,
                          offset: const Offset(0, 2)),
                    ],
                  ),
                  child: Text(letter,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: harfRenk)),
                ),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(text,
                        style: TextStyle(
                            fontSize: 14.5, height: 1.3, color: c.text))),
                if (showResult && isCorrectOption)
                  Icon(Icons.check_circle, size: 18, color: c.success)
                else if (showResult && selected && !isCorrectOption)
                  Icon(Icons.cancel, size: 18, color: c.danger),
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
  /// Yanlış cevapta, seçilen şıkkı adıyla anan kısa çerçeve notu (bkz.
  /// _QuizScreenState._secimNotu). Doğru cevapta `null`.
  final String? secimNotu;
  const _FeedbackPanel({
    required this.correct,
    required this.motivation,
    required this.aciklama,
    this.distractorAciklama,
    this.secimNotu,
  });

  @override
  Widget build(BuildContext context) {
    // Sabit renk yok: doğru/yanlış vurgusu tema token'larından gelir.
    final c = context.watch<ThemeProvider>().colors;
    final color = correct ? c.success : c.danger;
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
          if (!correct && (secimNotu?.trim().isNotEmpty ?? false)) ...[
            const SizedBox(height: 8),
            Text(
              secimNotu!.trim(),
              style: TextStyle(height: 1.4, fontWeight: FontWeight.w600, color: c.text),
            ),
          ],
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
