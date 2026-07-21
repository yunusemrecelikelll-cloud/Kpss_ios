import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/question.dart';
import '../../models/subject.dart';
import '../../services/duel_service.dart';
import '../../services/remote_question_service.dart';
import '../../services/sound_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/design_system.dart';
import '../../theme/theme_provider.dart';
import '../quick_modes/quick_modes_shared.dart' show kQuickModeOptionLetters;
import '../tools_hub_screen.dart' show HowToPlayButton;
import 'duel_lobby_screen.dart' show kDuelloGameId;
import 'duel_result_screen.dart';

/// Senkronize oyun ekranı. TÜM oyuncular `startedAt` + `soruIndex *
/// perQuestionSeconds` hesabıyla (istemci tarafında Timer ile) AYNI anda AYNI
/// soruyu görür. Cevaplar Firestore'a yazılır; diğer oyuncuların o anki cevabı
/// GÖSTERİLMEZ (adil olsun) — sadece kendi sonucun + canlı sıralama görünür.
///
/// İki mod:
///  - [DuelPlayScreen.online]  → Firestore odası (Düello/Royale, çok oyunculu).
///  - [DuelPlayScreen.solo]    → tamamen yerel pratik (Firestore gerektirmez).
class DuelPlayScreen extends StatefulWidget {
  final String? roomId; // null => solo
  final List<Subject> soloSubjects;

  const DuelPlayScreen.online({super.key, required String this.roomId}) : soloSubjects = const [];

  const DuelPlayScreen.solo({super.key, required List<Subject> subjects})
      : roomId = null,
        soloSubjects = subjects;

  bool get isSolo => roomId == null;

  @override
  State<DuelPlayScreen> createState() => _DuelPlayScreenState();
}

class _DuelPlayScreenState extends State<DuelPlayScreen> {
  final DuelService _duel = DuelService();
  Timer? _ticker;
  DateTime _now = DateTime.now();

  // Oyun parametreleri (online: room'dan; solo: yerel).
  List<Question> _questions = const [];
  DateTime? _startedAt;
  int _perQ = 30;
  int _total = 10;
  bool _isRoyale = false;
  Map<String, DuelPlayer> _players = const {};

  // Tüm oyuncular cevapladığında kalan sürenin atlanmasıyla "kazanılan" toplam
  // süre; odadan okunur, tüm cihazlarda aynıdır (bkz. DuelRoom.timeShiftMs).
  int _timeShiftMs = 0;
  // Bu cihazın erken geçiş isteği gönderdiği son soru. Aynı soru için ağa
  // saniyede dört kez (ticker hızında) istek gitmesini engeller; asıl
  // tekrar koruması yine sunucudaki `lastSkippedIndex` koşuludur.
  int _skipRequestedForIndex = -1;

  bool _soloLoading = true;

  // ── SOLO akışı ────────────────────────────────────────────────────────────
  // Solo'da rakip YOKTUR; bu yüzden soru indeksi zamandan DEĞİL, kendi
  // sayacından ilerler — kullanıcı bir şık seçer seçmez sonraki soruya geçilir.
  // Online'da ise senkron şart olduğu için indeks hâlâ `startedAt` üzerinden
  // hesaplanır (herkes aynı anda aynı soruyu görmeli).
  int _soloIndex = 0;
  // İçinde bulunulan solo sorusunun başlangıç anı: süre HER SORU İÇİN baştan
  // işlesin ve hız bonusu bu ana göre hesaplansın diye ayrı tutulur.
  DateTime? _soloQuestionStart;
  Timer? _soloAdvanceTimer; // doğru/yanlış geri bildirimi sonrası otomatik geçiş
  bool _soloAdvancing = false; // geri bildirim sürerken yeni dokunuşlar yok sayılır

  // NOT — "Önceki soru" butonu bilerek EKLENMEDİ: cevap verildiği anda puan
  // işleniyor (solo'da hız bonusu, online'da Firestore'a `submitAnswer`), geri
  // dönüp cevabı değiştirmek hem puanı hem de çok oyunculu senkronu bozardı.
  // Cevaplanan soruların özeti zaten sonuç ekranında gösteriliyor.

  // Kendi cevap durumu.
  final Map<int, int> _mySelections = {}; // soruIndex -> seçilen şık
  int _soloScore = 0;
  int _soloCorrect = 0;

  int _lastIndexSeen = -1;
  bool _finishNavigated = false;
  DateTime? _activeSinceNoStart;

  // Toplam Düello oynama süresi takibi: bu ekran, bir maç/pratik EFEKTİF
  // olarak başladığında (hem solo hem online için) push edildiğinden, oturum
  // initState'te başlar ve dispose'da (erken çıkış — maçtan çık — dahil) her
  // zaman kapatılıp kaydedilir.
  final DateTime _sessionStart = DateTime.now();
  late final StorageService _storage;

  @override
  void initState() {
    super.initState();
    _storage = context.read<StorageService>();
    if (widget.isSolo) {
      _bootstrapSolo();
    }
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => _onTick());
  }

  Future<void> _bootstrapSolo() async {
    // Herhangi bir beklenmeyen hata (ör. sağlayıcı henüz hazır değil) burada
    // yakalanmazsa _soloLoading hiç false olmaz ve ekran sonsuza dek
    // "yükleniyor" durumunda kalır — bu yüzden tüm gövde try/catch içinde.
    List<Question> pool = const [];
    try {
      final remote = context.read<RemoteQuestionService>();
      // ÖNCEDEN doğrudan QuickModesShared.collectAll kullanılıyordu; bu, soru
      // havuzunu tamamen indirilmiş/JSON banka verisine bağlıyor ve turdan
      // tura aynı soruların gelmesini engellemiyordu. buildSoloQuestions ise
      // JSON bankasını gömülü 90 soruluk solo havuzuyla birleştirir, tekrarı
      // eler ve daha önce sorulanları atlar — böylece "Tek Başına Yarış"
      // çevrimdışıyken de dolu bir havuzla çalışır.
      pool = await _duel.buildSoloQuestions(
        subjects: widget.soloSubjects,
        remote: remote,
      );
    } catch (_) {
      pool = const [];
    }
    if (!mounted) return;
    setState(() {
      _questions = pool;
      _total = _questions.length;
      _perQ = 30;
      _startedAt = DateTime.now();
      _soloIndex = 0;
      _soloQuestionStart = DateTime.now();
      _soloLoading = false;
    });
  }

  @override
  void dispose() {
    _storage.addGameTimeSpent(kDuelloGameId, DateTime.now().difference(_sessionStart));
    _ticker?.cancel();
    _soloAdvanceTimer?.cancel();
    super.dispose();
  }

  int get _currentIndex {
    // Solo: kendi sayacı (cevap verince / süre dolunca ilerler).
    if (widget.isSolo) return _soloIndex;
    // Online: senkron için indeks TAMAMEN zamandan hesaplanır — DOKUNMA.
    // Erken geçiş de buraya `_timeShiftMs` olarak dahildir: odaya yazılan tek
    // bir kaydırma değeri sayesinde tüm cihazlar aynı indeksi bulur.
    if (_startedAt == null) return 0;
    final elapsedMs = _effectiveElapsedMs;
    if (elapsedMs < 0) return 0;
    return elapsedMs ~/ (_perQ * 1000);
  }

  /// Maçın başından bu yana geçmiş SAYILAN süre (gerçek süre + erken geçişler).
  int get _effectiveElapsedMs {
    if (_startedAt == null) return 0;
    final gercek = _now.difference(_startedAt!).inMilliseconds;
    if (gercek < 0) return _timeShiftMs;
    return gercek + _timeShiftMs;
  }

  int _remainingMs(int index) {
    if (widget.isSolo) {
      // Solo'da geri sayım, o sorunun kendi başlangıcından itibaren işler.
      final start = _soloQuestionStart;
      if (start == null) return _perQ * 1000;
      return start.add(Duration(seconds: _perQ)).difference(_now).inMilliseconds;
    }
    if (_startedAt == null) return _perQ * 1000;
    return (index + 1) * _perQ * 1000 - _effectiveElapsedMs;
  }

  bool get _amEliminated {
    final uid = _duel.currentUid;
    if (uid == null) return false;
    return _players[uid]?.eliminated == true;
  }

  void _onTick() {
    if (!mounted) return;
    _now = DateTime.now();

    if (widget.isSolo) {
      _soloTick();
      return;
    }

    final idx = _currentIndex;

    // Oyun bitti mi?
    if (_startedAt != null && idx >= _total && _total > 0) {
      _handleFinish();
      setState(() {});
      return;
    }

    // Soru değişti mi?
    if (idx != _lastIndexSeen && _startedAt != null && idx < _total) {
      _lastIndexSeen = idx;
      // Royale: her 5 soruda bir, biten tur için eleme kontrolü (online).
      if (!widget.isSolo && _isRoyale && idx > 0 && idx % 5 == 0) {
        _duel.checkAndEliminate(widget.roomId!, idx - 1);
      }
    }

    // Herkes cevapladıysa kalan süreyi bekleme.
    _maybeSkipAhead(idx);

    setState(() {});
  }

  /// İçinde bulunulan soruyu TÜM (elenmemiş) oyuncular cevapladıysa, kalan
  /// sürenin atlanmasını ister.
  ///
  /// Kaydırmayı burada YEREL olarak uygulamıyoruz: öyle yapılsaydı isteği ilk
  /// fark eden cihaz sonraki soruya geçer, diğerleri geçmez ve oyuncular farklı
  /// sorularda kalırdı. Bunun yerine odaya yazdırıyoruz; kaydırma oda akışıyla
  /// (`watchRoom`) herkese aynı anda dönüyor.
  void _maybeSkipAhead(int idx) {
    if (widget.isSolo) return; // Solo'da geçiş zaten anında.
    if (_startedAt == null || idx >= _total) return;
    if (_skipRequestedForIndex >= idx) return; // Bu soru için zaten istendi.
    if (_players.isEmpty) return;

    // Elenen oyuncular cevap veremez; onları beklemek oyunu kilitlerdi.
    final aktif = _players.values.where((p) => !p.eliminated);
    if (aktif.isEmpty) return;
    if (!aktif.every((p) => p.answers.containsKey(idx))) return;

    _skipRequestedForIndex = idx;
    _duel.skipToNextIfAllAnswered(widget.roomId!, idx);
  }

  /// Solo tick: indeks zamandan ilerlemez, ama SÜRE SINIRI aynen geçerlidir —
  /// 30 saniye dolduğunda soru cevapsız sayılıp otomatik geçilir.
  void _soloTick() {
    if (_soloLoading || _total <= 0) {
      setState(() {});
      return;
    }
    if (_soloIndex >= _total) {
      _handleFinish();
      setState(() {});
      return;
    }
    // Geri bildirim gösterilirken zaman aşımı devreye girmesin; zaten
    // _soloAdvanceTimer birazdan geçişi yapacak.
    if (!_soloAdvancing && _remainingMs(_soloIndex) <= 0) {
      _goToNextSolo();
      return;
    }
    setState(() {});
  }

  /// Solo'da sonraki soruya geçer. Hem cevap sonrası geri bildirim timer'ından,
  /// hem süre dolduğunda, hem de "Sonraki" butonundan çağrılır. Cevap
  /// verilmemişse o soru cevapsız sayılır (_mySelections'a hiçbir şey yazılmaz).
  void _goToNextSolo() {
    _soloAdvanceTimer?.cancel();
    _soloAdvanceTimer = null;
    _soloAdvancing = false;
    if (!mounted) return;
    final next = _soloIndex + 1;
    if (next >= _total) {
      setState(() => _soloIndex = next);
      _handleFinish();
      return;
    }
    setState(() {
      _soloIndex = next;
      // Yeni sorunun 30 saniyesi SIFIRDAN başlar.
      _soloQuestionStart = DateTime.now();
    });
  }

  void _handleFinish() {
    if (_finishNavigated) return;
    _finishNavigated = true;
    if (!widget.isSolo) {
      _duel.finishRoom(widget.roomId!);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => widget.isSolo
            ? DuelResultScreen.solo(
                score: _soloScore,
                correct: _soloCorrect,
                total: _total,
              )
            : DuelResultScreen.online(roomId: widget.roomId!),
      ));
    });
  }

  void _answer(int optionIdx) {
    final idx = _currentIndex;
    if (idx >= _total || idx >= _questions.length) return;
    if (_mySelections.containsKey(idx)) return; // zaten cevaplandı
    if (widget.isSolo && _soloAdvancing) return; // geri bildirim sürerken dokunma yok
    if (!widget.isSolo && _amEliminated) return; // izleyici cevap veremez

    final q = _questions[idx];
    final correct = optionIdx == q.dogruIndex;
    // Geçen süre: solo'da o sorunun KENDİ başlangıcına göre, online'da
    // `startedAt + idx * perQ` senkron başlangıcına göre hesaplanır.
    final DateTime questionStart = widget.isSolo
        ? (_soloQuestionStart ?? _now)
        : _startedAt!.add(Duration(milliseconds: idx * _perQ * 1000));
    final elapsedMs = _now.difference(questionStart).inMilliseconds.clamp(0, _perQ * 1000);

    setState(() => _mySelections[idx] = optionIdx);

    context.read<SoundService>().click();

    if (widget.isSolo) {
      if (correct) {
        // Hız bonusu KORUNDU: 100 puan + kalan saniye başına 3 puan.
        final bonus = ((_perQ * 1000 - elapsedMs) / 1000 * 3).round();
        _soloScore += 100 + bonus;
        _soloCorrect += 1;
      }
      // Kısa doğru/yanlış geri bildirimi, ardından ANINDA sonraki soru.
      _soloAdvancing = true;
      _soloAdvanceTimer?.cancel();
      _soloAdvanceTimer = Timer(const Duration(milliseconds: 700), _goToNextSolo);
    } else {
      _duel.submitAnswer(widget.roomId!, idx, optionIdx, elapsedMs, q.dogruIndex, _perQ);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isSolo) {
      if (_soloLoading) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (_questions.isEmpty) {
        return const Scaffold(
          body: Center(
            child: Padding(padding: EdgeInsets.all(24), child: _EmptyNote(emoji: '📭', text: 'Soru yüklenemedi.')),
          ),
        );
      }
      return _buildScaffold(context);
    }

    // Online: room stream.
    return StreamBuilder<DuelRoom?>(
      stream: _duel.watchRoom(widget.roomId!),
      builder: (context, snap) {
        final room = snap.data;
        if (room == null) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          return const Scaffold(
            body: Center(
              child: Padding(padding: EdgeInsets.all(24), child: _EmptyNote(emoji: '🚪', text: 'Oda bulunamadı.')),
            ),
          );
        }
        // Room verilerini state alanlarına aktar (ticker bunları kullanır).
        _questions = room.questions;
        _startedAt = room.startedAt;
        _perQ = room.perQuestionSeconds;
        _total = room.totalQuestions;
        _isRoyale = room.isRoyale;
        _players = room.players;
        // Erken geçiş kaydırması: soru indeksi ve geri sayım BUNU da hesaba
        // katar, yoksa "herkes cevapladı" atlaması bu cihazda görünmezdi.
        _timeShiftMs = room.timeShiftMs;

        if (room.status == 'finished') {
          _handleFinish();
        }
        if (_startedAt == null) {
          // Normalde `status: 'active'` ile `startedAt` AYNI transaction'da
          // yazılır, ama sunucu gecikmesi/ağ sorunu olursa buradaki ekran
          // sonsuza dek "yükleniyor" görünürdü — bu yüzden bir eşik sonrası
          // "çık" seçeneği sunulur, asla kalıcı bir donma yaşanmaz.
          _activeSinceNoStart ??= DateTime.now();
          final waitedTooLong = DateTime.now().difference(_activeSinceNoStart!) > const Duration(seconds: 8);
          if (waitedTooLong) {
            return Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _EmptyNote(
                        emoji: '📡',
                        text: 'Maç başlatılamadı. Bağlantını kontrol edip tekrar dene.',
                      ),
                      const SizedBox(height: 16),
                      DsPillButton(
                        label: 'Çık',
                        color: context.watch<ThemeProvider>().colors.danger,
                        filled: false,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        _activeSinceNoStart = null;
        return _buildScaffold(context);
      },
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final idx = _currentIndex.clamp(0, _total - 1);
    if (idx >= _questions.length) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final q = _questions[idx];
    final remainingMs = _remainingMs(idx).clamp(0, _perQ * 1000);
    final remainingSec = (remainingMs / 1000).ceil();
    final progress = (remainingMs / (_perQ * 1000)).clamp(0.0, 1.0);
    final answered = _mySelections.containsKey(idx);
    final mySel = _mySelections[idx];
    final eliminated = !widget.isSolo && _amEliminated;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmQuit();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.isSolo
              ? 'Tek Başına Yarış'
              : (_isRoyale ? '👑 KPSS Royale' : '⚔️ KPSS Düello')),
          leading: IconButton(icon: const Icon(Icons.close), onPressed: _confirmQuit),
          actions: const [
            HowToPlayButton(
              title: '⚔️ Nasıl Oynanır?',
              body: "Düello'da bir rakiple, Royale'de birden çok oyuncuyla aynı "
                  'soruları aynı anda çözersün; hızlı ve doğru cevap veren daha çok '
                  'puan kazanır. Süre dolmadan cevap ver — cevap veremezsen o soruyu '
                  'kaçırmış olursun.',
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              color: progress < 0.3 ? c.danger : null,
            ),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (eliminated) _SpectatorBanner(color: c.danger),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    DsChip(
                      label: 'SORU ${idx + 1}/$_total',
                      color: widget.isSolo ? c.mint : (_isRoyale ? c.gold : c.violetL),
                    ),
                    const Spacer(),
                    Icon(Icons.timer_outlined, size: 16, color: remainingSec <= 5 ? c.danger : c.textFaint),
                    const SizedBox(width: 4),
                    Text('$remainingSec sn',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13.5,
                          color: remainingSec <= 5 ? c.danger : c.text,
                        )),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                  children: [
                    DsCard(
                      padding: const EdgeInsets.all(18),
                      child: Text(q.soru,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              height: 1.4,
                              color: c.text)),
                    ),
                    const SizedBox(height: kDsGap),
                    for (var i = 0; i < q.secenekler.length; i++)
                      _OptionTile(
                        letter: i < kQuickModeOptionLetters.length ? kQuickModeOptionLetters[i] : '${i + 1}',
                        text: q.secenekler[i],
                        state: _optionState(answered, mySel, i, q.dogruIndex),
                        onTap: (answered || eliminated || (widget.isSolo && _soloAdvancing))
                            ? null
                            : () => _answer(i),
                      ),
                    if (answered) ...[
                      const SizedBox(height: 12),
                      _AnswerFeedback(
                        question: q,
                        mySelection: mySel!,
                        colors: c,
                        // "Sonraki soru bekleniyor" notu SADECE online'da anlamlı;
                        // solo'da zaten anında geçiliyor.
                        showWaitingNote: !widget.isSolo,
                      ),
                    ],
                    // Online: cevap verildikten sonra ekran "donmuş" görünmesin —
                    // cevabın kaydedildiği + rakipler için beklendiği net yazılır.
                    if (answered && !widget.isSolo) ...[
                      const SizedBox(height: 8),
                      _WaitingForNextPanel(
                        remainingSec: remainingSec,
                        progress: progress,
                        colors: c,
                      ),
                    ],
                    // Solo: geri bildirimi beklemeden ilerleyebilmek için manuel
                    // geçiş. Cevap verilmemişse soru cevapsız sayılarak geçilir.
                    if (widget.isSolo) ...[
                      const SizedBox(height: 12),
                      DsPillButton(
                        label: answered ? 'Sonraki' : 'Soruyu Geç',
                        color: answered ? c.mint : c.textDim,
                        filled: answered,
                        trailingIcon: Icons.arrow_forward_rounded,
                        onPressed: _goToNextSolo,
                      ),
                    ],
                    const SizedBox(height: 16),
                    if (!widget.isSolo) _LiveLeaderboard(players: _players, myUid: _duel.currentUid, colors: c),
                    if (widget.isSolo) _SoloScoreStrip(score: _soloScore, correct: _soloCorrect, answered: idx, colors: c),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  _OptState _optionState(bool answered, int? mySel, int i, int correctIdx) {
    if (!answered) return _OptState.idle;
    if (i == correctIdx) return _OptState.correct;
    if (i == mySel) return _OptState.wrong;
    return _OptState.dim;
  }

  Future<void> _confirmQuit() async {
    // ÖNEMLİ: butonlar dialogContext'i kullanmalı, dışarıdaki ekranın
    // context'ini DEĞİL — aksi halde Navigator.pop yanlış navigator'ı
    // hedefleyip diyalog ekranda açık kalabiliyordu (bu ekran kök
    // navigator'a push edildiği için showDialog'un kendi context'i farklı
    // bir Navigator'a denk gelebiliyor).
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Maçtan çık?'),
        content: const Text('Çıkarsan bu maçtaki ilerlemen kaybolur.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Devam Et')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Çık')),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.of(context).pop();
  }
}

enum _OptState { idle, correct, wrong, dim }

class _OptionTile extends StatelessWidget {
  final String letter;
  final String text;
  final _OptState state;
  final VoidCallback? onTap;
  const _OptionTile({required this.letter, required this.text, required this.state, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    // Şık durumuna göre vurgu rengi — sabit renk YOK, hepsi tema token'ı.
    Color? vurgu;
    switch (state) {
      case _OptState.correct:
        vurgu = c.success;
        break;
      case _OptState.wrong:
        vurgu = c.danger;
        break;
      case _OptState.dim:
      case _OptState.idle:
        vurgu = null;
        break;
    }
    final harfRengi = vurgu ?? c.textDim;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DsCard(
        accent: vurgu,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        onTap: onTap,
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (vurgu ?? c.glass2).withValues(alpha: vurgu == null ? 1 : 0.18),
                border: Border.all(color: vurgu?.withValues(alpha: 0.6) ?? c.border),
              ),
              child: Text(letter,
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w900, color: harfRengi)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.3,
                  color: state == _OptState.dim ? c.textFaint : c.text,
                ),
              ),
            ),
            if (state == _OptState.correct) Icon(Icons.check_circle, color: c.success, size: 20),
            if (state == _OptState.wrong) Icon(Icons.cancel, color: c.danger, size: 20),
          ],
        ),
      ),
    );
  }
}

/// Boş/hata durumlarında gösterilen küçük illüstrasyonlu not.
class _EmptyNote extends StatelessWidget {
  final String emoji;
  final String text;
  const _EmptyNote({required this.emoji, required this.text});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DsIllustration(emoji: emoji, glowColor: c.violetL),
        const SizedBox(height: 8),
        Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: c.text)),
      ],
    );
  }
}

class _AnswerFeedback extends StatelessWidget {
  final Question question;
  final int mySelection;
  final KpssColors colors;
  final bool showWaitingNote;
  const _AnswerFeedback({
    required this.question,
    required this.mySelection,
    required this.colors,
    this.showWaitingNote = true,
  });

  @override
  Widget build(BuildContext context) {
    final correct = mySelection == question.dogruIndex;
    final c = colors;
    final aciklama = correct
        ? question.aciklama
        : (question.distractorAciklama ?? question.aciklama);
    final vurgu = correct ? c.success : c.danger;
    return DsCard(
      accent: vurgu,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(correct ? '✅ Doğru!' : '❌ Yanlış',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: vurgu)),
          if (aciklama.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(aciklama,
                style: TextStyle(fontSize: 12.5, height: 1.5, color: c.textDim)),
          ],
          if (showWaitingNote) ...[
            const SizedBox(height: 6),
            Text('Sonraki soru bekleniyor...',
                style: TextStyle(fontSize: 11, color: c.textFaint)),
          ],
        ],
      ),
    );
  }
}

/// ÇOK OYUNCULU bekleme paneli: cevap verildikten sonra tüm oyuncular aynı
/// anda ilerlediği için soru hemen değişmez. Bu panel, "ekran takıldı" hissini
/// önlemek için cevabın kaydedildiğini ve sonraki soruya kaç saniye kaldığını
/// açıkça gösterir. Cevap VERİLMEDİYSE gösterilmez — normal soru ekranı durur.
class _WaitingForNextPanel extends StatelessWidget {
  final int remainingSec;
  final double progress; // 1 → süre yeni başladı, 0 → süre bitti
  final KpssColors colors;
  const _WaitingForNextPanel({
    required this.remainingSec,
    required this.progress,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return DsCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cloud_done_outlined, size: 16, color: c.success),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Cevabın kaydedildi',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 13, color: c.success)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Sonraki soru: $remainingSec sn',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 12.5, color: c.text)),
          const SizedBox(height: 6),
          DsProgressBar(
            value: progress,
            color: progress < 0.3 ? c.danger : c.violetL,
          ),
          const SizedBox(height: 6),
          Text('Herkes cevaplayınca sonraki soruya hemen geçilir.',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, height: 1.4, color: c.textFaint)),
        ],
      ),
    );
  }
}

/// Canlı sıralama: top 3 + kendi sıran. Diğer oyuncuların O ANKİ cevabını
/// GÖSTERMEZ, sadece toplam skorları/sıralamayı gösterir.
class _LiveLeaderboard extends StatelessWidget {
  final Map<String, DuelPlayer> players;
  final String? myUid;
  final KpssColors colors;
  const _LiveLeaderboard({required this.players, required this.myUid, required this.colors});

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final list = players.values.toList()..sort((a, b) => b.score.compareTo(a.score));
    if (list.isEmpty) return const SizedBox.shrink();
    final top = list.take(3).toList();
    final myRank = myUid == null ? -1 : list.indexWhere((p) => p.uid == myUid);

    return DsCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('📊 Canlı Sıralama',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: c.textDim)),
          const SizedBox(height: 8),
          for (var i = 0; i < top.length; i++)
            _rankRow(i + 1, top[i], top[i].uid == myUid, c),
          if (myRank >= 3 && myUid != null) ...[
            Divider(color: c.border, height: 16),
            _rankRow(myRank + 1, list[myRank], true, c),
          ],
        ],
      ),
    );
  }

  Widget _rankRow(int rank, DuelPlayer p, bool isMe, KpssColors c) {
    final medal = rank == 1 ? '🥇' : rank == 2 ? '🥈' : rank == 3 ? '🥉' : '$rank.';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 26, child: Text(medal, style: const TextStyle(fontSize: 13))),
          Expanded(
            child: Text(
              isMe ? '${p.name} (sen)' : p.name,
              style: TextStyle(
                fontWeight: isMe ? FontWeight.w900 : FontWeight.w600,
                fontSize: 12.5,
                color: p.eliminated ? c.textFaint : c.text,
                decoration: p.eliminated ? TextDecoration.lineThrough : null,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text('${p.score}',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5, color: c.text)),
        ],
      ),
    );
  }
}

class _SoloScoreStrip extends StatelessWidget {
  final int score;
  final int correct;
  final int answered;
  final KpssColors colors;
  const _SoloScoreStrip({required this.score, required this.correct, required this.answered, required this.colors});

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return DsStatStrip(
      items: [
        DsStatItem(
          visual: DsIconBadge(emoji: '⭐', color: c.gold, size: 38, glow: false),
          value: '$score',
          label: 'Puan',
        ),
        DsStatItem(
          visual: DsIconBadge(emoji: '✅', color: c.success, size: 38, glow: false),
          value: '$correct',
          label: 'Doğru',
        ),
        DsStatItem(
          visual: DsIconBadge(emoji: '📝', color: c.violetL, size: 38, glow: false),
          value: '$answered',
          label: 'Geçilen soru',
        ),
      ],
    );
  }
}

class _SpectatorBanner extends StatelessWidget {
  final Color color;
  const _SpectatorBanner({required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: color.withValues(alpha: 0.15),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Text('👀 Elendin — kalan oyuncuları izleyici olarak izliyorsun.',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: color)),
    );
  }
}
