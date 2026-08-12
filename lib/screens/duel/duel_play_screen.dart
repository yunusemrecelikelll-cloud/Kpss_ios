import 'dart:async';
import 'dart:math';

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
import '../quiz_screen.dart' show sikMetni;
import '../tools_hub_screen.dart' show HowToPlayButton;
import 'duel_lobby_screen.dart' show kDuelloGameId;
import 'duel_notepad.dart';
import 'duel_result_screen.dart';
import '../../utils/ust_bildirim.dart';

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
  // Solo yapılandırması (kullanıcı isteği: solo'da da süre + konu seçimi).
  // null => karışık; belirtilmişse yalnızca o ders/konudan sorular gelir.
  final String? soloSubjectId;
  final String? soloTopicId;
  final int soloSeconds;
  final int soloCount;

  const DuelPlayScreen.online({super.key, required String this.roomId})
      : soloSubjects = const [],
        soloSubjectId = null,
        soloTopicId = null,
        soloSeconds = 30,
        soloCount = 10;

  const DuelPlayScreen.solo({
    super.key,
    required List<Subject> subjects,
    this.soloSubjectId,
    this.soloTopicId,
    this.soloSeconds = 30,
    this.soloCount = 10,
  })  : roomId = null,
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

  // Oda 2 saatlik ömrünü doldurduğunda uyarı+silme bir kez tetiklensin.
  bool _suresiDolduIslendi = false;

  // Son 5 saniyede tik-tak sesi için: en son tik çalınan (soru, saniye) çifti.
  // Aynı saniye içinde ticker birden çok kez çalıştığından tekrar çalmayı
  // önler; soru değişince de sıfırlanır.
  int _tickLastIndex = -1;
  int _tickLastSec = -1;

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
  final Map<int, int> _mySelections = {}; // soruIndex -> seçilen şık (ORİJİNAL index)

  // Kullanıcı isteği: her oyuncu AYNI soruyu görür ama ŞIKLARIN YERİ FARKLI
  // olur. Bu, her soru için bu OYUNCUYA özel bir şık sıralaması (permütasyon):
  // gösterim pozisyonu -> orijinal şık indeksi. Oyuncunun uid'i + soru indeksi
  // ile deterministik üretilir (yeniden çizimlerde şıklar yerinden oynamaz).
  final Map<int, List<int>> _optionPerm = {};

  List<int> _permFor(int idx, int n) {
    final cached = _optionPerm[idx];
    if (cached != null && cached.length == n) return cached;
    final kim = widget.isSolo ? 'solo' : (_duel.currentUid ?? 'anon');
    final perm = List<int>.generate(n, (i) => i)
      ..shuffle(Random(Object.hash(kim, idx)));
    _optionPerm[idx] = perm;
    return perm;
  }
  // Her rakip kullanıcıya özel, sabit renk paleti (uid'den türer).
  static const List<Color> _rakipRenkleri = [
    Color(0xFF2E9E5B), Color(0xFF1E88E5), Color(0xFFF57C00),
    Color(0xFF8E24AA), Color(0xFF00897B), Color(0xFFD81B60),
    Color(0xFF5E35B1), Color(0xFF3949AB),
  ];
  Color _uidRenk(String uid) =>
      _rakipRenkleri[uid.hashCode.abs() % _rakipRenkleri.length];

  /// [qIdx] sorusunda [orig] şıkkını seçen RAKİP oyuncuların rozetleri.
  /// Kendi cevabımız gösterilmez; çağıran yalnızca biz cevaplayınca çağırır.
  List<_RakipRozet> _rakipRozetleri(int qIdx, int orig) {
    if (widget.isSolo) return const [];
    final myUid = _duel.currentUid;
    final list = <_RakipRozet>[];
    _players.forEach((uid, p) {
      if (uid == myUid) return;
      final a = p.answers[qIdx];
      if (a != null && a.idx == orig) {
        list.add(_RakipRozet(
          harf: p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
          renk: _uidRenk(uid),
        ));
      }
    });
    return list;
  }

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
      if (widget.soloTopicId != null || widget.soloSubjectId != null) {
        // KONU/DERS SEÇİLDİ (kullanıcı isteği): havuz doğrudan seçili ders/konu
        // sorularından kurulur; gömülü karışık solo havuzu (buildSoloQuestions)
        // KULLANILMAZ ki sorular konu dışına çıkmasın.
        final secilenler = <Question>[];
        for (final s in widget.soloSubjects) {
          if (widget.soloSubjectId != null && s.id != widget.soloSubjectId) {
            continue;
          }
          for (final t in s.konular) {
            if (widget.soloTopicId != null && t.id != widget.soloTopicId) {
              continue;
            }
            secilenler.addAll(t.sorular.where((q) => q.secenekler.length >= 2));
          }
        }
        secilenler.shuffle();
        pool = secilenler.take(widget.soloCount).toList();
      } else {
        // KARIŞIK: JSON bankasını gömülü solo havuzuyla birleştiren varsayılan
        // akış (çevrimdışı da dolu çalışır).
        pool = await _duel.buildSoloQuestions(
          subjects: widget.soloSubjects,
          remote: remote,
          count: widget.soloCount,
        );
      }
    } catch (_) {
      pool = const [];
    }
    if (!mounted) return;
    setState(() {
      _questions = pool;
      _total = _questions.length;
      _perQ = widget.soloSeconds;
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

  /// Son 5 saniyede her tam saniyede bir tik-tak sesi çalar (kullanıcı isteği).
  /// Aynı saniyede tekrar çalmayı ve soru değişince kalıntı çalmayı engeller.
  void _maybePlayTick(int idx) {
    if (idx < 0 || idx >= _total) return;
    final remainingSec = (_remainingMs(idx).clamp(0, _perQ * 1000) / 1000).ceil();
    if (idx != _tickLastIndex) {
      // Yeni soruya geçildi: faz ve sayaç sıfırlanır.
      _tickLastIndex = idx;
      _tickLastSec = -1;
      context.read<SoundService>().resetTickPhase();
    }
    if (remainingSec >= 1 && remainingSec <= 5 && remainingSec != _tickLastSec) {
      _tickLastSec = remainingSec;
      context.read<SoundService>().tick();
    }
  }

  void _onTick() {
    if (!mounted) return;
    _now = DateTime.now();

    if (widget.isSolo) {
      _maybePlayTick(_soloIndex);
      _soloTick();
      return;
    }

    final idx = _currentIndex;
    _maybePlayTick(idx);

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

    // Oyun istatistiği kaydı (kullanıcı isteği: oyunlardaki doğru/yanlışlar
    // istatistiklere işlensin). Solo'da seçili ders varsa o derse, yoksa
    // "genel"e yazılır; online'da karışık geldiği için "genel".
    _storage.addGameAnswer(
        'duello', widget.soloSubjectId ?? 'genel', correct);

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

        // Oda 2 saatlik ömrünü doldurduysa (kullanıcı isteği): yarış sürüyor
        // olsa bile uyar, odayı sil ve ekrandan çık. Bir kez tetiklenir.
        if (room.suresiDoldu && !_suresiDolduIslendi) {
          _suresiDolduIslendi = true;
          _duel.closeIfExpired(widget.roomId!);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ustBildirim('Odanın süresi (2 saat) doldu, oda kapatıldı.',
                tur: UstBildirimTuru.hata);
            Navigator.of(context).popUntil((r) => r.isFirst);
          });
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

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
            DuelNotepadButton(),
            HowToPlayButton(
              title: '⚔️ Nasıl Oynanır?',
              body: "Düello'da bir rakiple, Royale'de birden çok oyuncuyla aynı "
                  'soruları eş zamanlı çözersün; hızlı ve doğru cevap veren daha çok '
                  'puan kazanır. Süre dolmadan cevap ver — cevap veremezsen o soruyu '
                  'kaçırmış olursun.',
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(8),
            child: _CountdownBand(
              progress: progress,
              urgent: remainingSec <= 5,
              base: widget.isSolo ? c.mint : (_isRoyale ? c.gold : c.violetL),
              danger: c.danger,
              track: c.border,
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
              // Kullanıcı isteği: puanlar ÜST TARAFTA animasyonlu BAR YARIŞI
              // olarak; isim + puan; öne geçen bar diğerinin üstüne kayar.
              if (!widget.isSolo)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: _TopScoreBars(
                    players: _players,
                    myUid: _duel.currentUid,
                    colors: c,
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
                    // Şıklar bu oyuncuya özel karışık sırada gösterilir; tıklanan
                    // gösterim pozisyonu, ORİJİNAL şık indeksine (perm[p]) çevrilir.
                    for (var p = 0; p < q.secenekler.length; p++)
                      Builder(builder: (_) {
                        final orig = _permFor(idx, q.secenekler.length)[p];
                        return _OptionTile(
                          letter: p < kQuickModeOptionLetters.length ? kQuickModeOptionLetters[p] : '${p + 1}',
                          // Metindeki gömülü "A) / B)" önekini at — rozet harfi
                          // konumdan geliyor; düelloda şıklar karışık geldiği için
                          // gömülü harf uyuşmuyor ve çift harf/kayma görünüyordu.
                          text: sikMetni(q.secenekler[orig]),
                          state: _optionState(answered, mySel, orig, q.dogruIndex),
                          // Rakip cevap rozetleri: SADECE sen cevap verdiysen
                          // görünür (kullanıcı isteği). Her rakip, seçtiği şıkkın
                          // üzerinde baş harfi + kendine özel renkte yuvarlak rozet.
                          rozetler: answered ? _rakipRozetleri(idx, orig) : const [],
                          onTap: (answered || eliminated || (widget.isSolo && _soloAdvancing))
                              ? null
                              : () => _answer(orig),
                        );
                      }),
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
                      // Cevap verince rakiplerin bu sorudaki cevabını göster
                      // (kullanıcı isteği): baş harfli avatar + seçtiği şık +
                      // doğru/yanlış. Henüz cevaplamayan "düşünüyor".
                      const SizedBox(height: 8),
                      _RakipCevaplari(
                        players: _players,
                        myUid: _duel.currentUid,
                        questionIdx: idx,
                        correctIdx: q.dogruIndex,
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
                    // Online skorlar artık ÜST TARAFTA bar yarışı olarak
                    // gösteriliyor (bkz. _TopScoreBars); alttaki sıralama kaldırıldı.
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

/// Bir rakibin bir şıkka verdiği cevabı temsil eden rozet (baş harf + renk).
class _RakipRozet {
  final String harf;
  final Color renk;
  const _RakipRozet({required this.harf, required this.renk});
}

class _OptionTile extends StatelessWidget {
  final String letter;
  final String text;
  final _OptState state;
  final VoidCallback? onTap;
  final List<_RakipRozet> rozetler;
  const _OptionTile(
      {required this.letter,
      required this.text,
      required this.state,
      required this.onTap,
      this.rozetler = const []});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    // Şık zemin + yazı renkleri (kullanıcı isteği): VARSAYILAN altın zemin +
    // siyah okunur yazı. Cevap verilince doğru=yeşil, yanlış=kırmızı, elenen
    // diğer şıklar soluk.
    Color zemin;
    Color yazi;
    Color kenar;
    switch (state) {
      case _OptState.correct:
        zemin = c.success;
        yazi = Colors.white;
        kenar = c.success;
        break;
      case _OptState.wrong:
        zemin = c.danger;
        yazi = Colors.white;
        kenar = c.danger;
        break;
      case _OptState.dim:
        zemin = c.glass2;
        yazi = c.textFaint;
        kenar = c.border;
        break;
      case _OptState.idle:
        zemin = c.gold;
        yazi = Colors.black;
        kenar = c.gold;
        break;
    }
    final tile = Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: zemin,
        borderRadius: BorderRadius.circular(kDsRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(kDsRadius),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(kDsRadius),
              border: Border.all(color: kenar, width: 1.3),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: yazi.withValues(alpha: 0.14),
                    border: Border.all(color: yazi.withValues(alpha: 0.55)),
                  ),
                  child: Text(letter,
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w900, color: yazi)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(fontSize: 14, height: 1.3, color: yazi),
                  ),
                ),
                // Rakip rozetleri varsa ✓/✗ ikonuna yer bırakmak için küçük boşluk.
                if (rozetler.isNotEmpty) const SizedBox(width: 4),
                if (state == _OptState.correct)
                  const Icon(Icons.check_circle, color: Colors.white, size: 20),
                if (state == _OptState.wrong)
                  const Icon(Icons.cancel, color: Colors.white, size: 20),
              ],
            ),
          ),
        ),
      ),
    );

    if (rozetler.isEmpty) return tile;
    // Rakiplerin bu şıkka verdiği cevaplar: sağ üstte, baş harf + kişiye özel
    // renkte yuvarlak rozetler. Şıkkın ÜSTÜNDE durur, cevap metnini kapatmaz.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        tile,
        Positioned(
          top: -5,
          right: 10,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final r in rozetler)
                Container(
                  margin: const EdgeInsets.only(left: 3),
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: r.renk,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                    boxShadow: const [
                      BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 1)),
                    ],
                  ),
                  child: Text(r.harf,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
                ),
            ],
          ),
        ),
      ],
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

/// Kullanıcı isteği: puanlar ÜST TARAFTA animasyonlu BAR YARIŞI. Her oyuncu bir
/// bar; genişlik puanla orantılı, ÖNE GEÇEN barın satırı diğerinin ÜSTÜNE
/// yumuşakça kayar (AnimatedPositioned) — bir yarışma hissi. İsim + puan bar
/// üstünde yazar.
class _TopScoreBars extends StatelessWidget {
  final Map<String, DuelPlayer> players;
  final String? myUid;
  final KpssColors colors;
  const _TopScoreBars(
      {required this.players, required this.myUid, required this.colors});

  static const List<Color> _palet = [
    Color(0xFF8B5CF6), Color(0xFFF43F5E), Color(0xFFF59E0B),
    Color(0xFF22C55E), Color(0xFF3B82F6), Color(0xFFEC4899),
    Color(0xFF06B6D4), Color(0xFFD4AF37),
  ];
  Color _renk(String uid) => _palet[uid.hashCode.abs() % _palet.length];

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final tumu = players.values.toList();
    if (tumu.isEmpty) return const SizedBox.shrink();
    final sirali = [...tumu]..sort((a, b) => b.score.compareTo(a.score));
    final rankOf = <String, int>{
      for (var i = 0; i < sirali.length; i++) sirali[i].uid: i,
    };
    final maxScore = sirali.first.score;
    // Çizim sırası SABİT (uid) → children yeniden sıralanmaz; yalnızca her barın
    // `top`'u değişir ve AnimatedPositioned bunu kaydırır (öne geçme animasyonu).
    final stabil = [...tumu]..sort((a, b) => a.uid.compareTo(b.uid));

    const rowH = 34.0;
    const gap = 8.0;
    final yukseklik = stabil.length * rowH + (stabil.length - 1) * gap;

    return DsCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('🏁 Yarış',
                  style: TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 12.5, color: c.textDim)),
              const Spacer(),
              Text('öne geç!',
                  style: TextStyle(fontSize: 10.5, color: c.textFaint)),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: yukseklik,
            child: Stack(
              children: [
                for (final p in stabil)
                  AnimatedPositioned(
                    key: ValueKey(p.uid),
                    duration: const Duration(milliseconds: 550),
                    curve: Curves.easeOutCubic,
                    top: rankOf[p.uid]! * (rowH + gap),
                    left: 0,
                    right: 0,
                    height: rowH,
                    child: _BarRow(
                      player: p,
                      rank: rankOf[p.uid]!,
                      maxScore: maxScore,
                      isMe: p.uid == myUid,
                      barColor: _renk(p.uid),
                      colors: c,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BarRow extends StatelessWidget {
  final DuelPlayer player;
  final int rank;
  final int maxScore;
  final bool isMe;
  final Color barColor;
  final KpssColors colors;
  const _BarRow({
    required this.player,
    required this.rank,
    required this.maxScore,
    required this.isMe,
    required this.barColor,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final elendi = player.eliminated;
    final frac = maxScore > 0 ? (player.score / maxScore).clamp(0.08, 1.0) : 0.08;
    final madalya = rank == 0
        ? '🥇'
        : rank == 1
            ? '🥈'
            : rank == 2
                ? '🥉'
                : '${rank + 1}.';
    // Metin, hem dolu bar hem boş ray üstünde okunur olsun diye tema metin
    // rengi + zemin renginden bir kontrast halesi (shadow) kullanır.
    final yaziGolge = [Shadow(color: c.bg.withValues(alpha: 0.75), blurRadius: 3)];

    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: c.glass2,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                  color: isMe ? barColor : c.border, width: isMe ? 1.8 : 1),
            ),
          ),
        ),
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Align(
              alignment: Alignment.centerLeft,
              child: AnimatedFractionallySizedBox(
                duration: const Duration(milliseconds: 550),
                curve: Curves.easeOutCubic,
                widthFactor: elendi ? 0.0 : frac,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      barColor.withValues(alpha: 0.9),
                      barColor.withValues(alpha: 0.45),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Text(madalya, style: const TextStyle(fontSize: 13)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    isMe ? '${player.name} (sen)' : player.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12.5,
                      color: elendi ? c.textFaint : c.text,
                      decoration: elendi ? TextDecoration.lineThrough : null,
                      shadows: yaziGolge,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text('${player.score}',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      color: c.text,
                      shadows: yaziGolge,
                    )),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Cevap verildikten sonra RAKİPLERİN bu sorudaki cevabını gösteren panel
/// (kullanıcı isteği). Her rakip için: baş harfli daire avatar + adı + seçtiği
/// şık (doğruysa yeşil, yanlışsa kırmızı) ya da henüz cevaplamadıysa "düşünüyor".
class _RakipCevaplari extends StatelessWidget {
  final Map<String, DuelPlayer> players;
  final String? myUid;
  final int questionIdx;
  final int correctIdx;
  final KpssColors colors;
  const _RakipCevaplari({
    required this.players,
    required this.myUid,
    required this.questionIdx,
    required this.correctIdx,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final rakipler = players.values.where((p) => p.uid != myUid).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (rakipler.isEmpty) return const SizedBox.shrink();

    return DsCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('🎭 Rakiplerin cevabı',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: c.textDim)),
          const SizedBox(height: 10),
          for (var i = 0; i < rakipler.length; i++) ...[
            if (i > 0) Divider(color: c.border, height: 16),
            _satir(rakipler[i], c),
          ],
        ],
      ),
    );
  }

  Widget _satir(DuelPlayer p, KpssColors c) {
    final bas = p.name.trim().isNotEmpty ? p.name.trim()[0].toUpperCase() : '?';
    final ans = p.answers[questionIdx];
    final cevapladi = ans != null;
    final dogru = cevapladi && ans.idx == correctIdx;
    final renk = !cevapladi ? c.textFaint : (dogru ? c.success : c.danger);
    // NOT: Şıkların yeri her oyuncuda FARKLI olduğu için rakibin "hangi harfi"
    // seçtiğini göstermek anlamsızdır; bu yüzden yalnızca DOĞRU/YANLIŞ gösterilir.

    return Row(
      children: [
        // Baş harfli daire avatar
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [c.violet, c.rose]),
            border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
          ),
          child: Text(bas,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w900, color: Colors.white)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            p.eliminated ? '${p.name} (elendi)' : p.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: p.eliminated ? c.textFaint : c.text),
          ),
        ),
        const SizedBox(width: 8),
        if (!cevapladi)
          Text('düşünüyor…',
              style: TextStyle(
                  fontSize: 11.5, fontStyle: FontStyle.italic, color: c.textFaint))
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: renk.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: renk.withValues(alpha: 0.5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(dogru ? Icons.check_circle : Icons.cancel, size: 15, color: renk),
                const SizedBox(width: 5),
                Text(dogru ? 'Doğru' : 'Yanlış',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w900, color: renk)),
              ],
            ),
          ),
      ],
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

/// Soru başına geri sayım bandı — AppBar'ın altında, temaya uygun gradyanlı
/// ilerleme çubuğu. Süre azaldıkça çubuk kısalır; son 5 saniyede kırmızı
/// gradyana döner ve hafifçe parlar (kullanıcı isteği: "temaya uygun yeniden
/// tasarla"). Genişlik animasyonlu (250 ms) olduğundan ticker adımları arasında
/// akıcı ilerler.
class _CountdownBand extends StatelessWidget {
  final double progress; // 1.0 (dolu/başlangıç) → 0.0 (süre bitti)
  final bool urgent; // son 5 saniye
  final Color base;
  final Color danger;
  final Color track;
  const _CountdownBand({
    required this.progress,
    required this.urgent,
    required this.base,
    required this.danger,
    required this.track,
  });

  @override
  Widget build(BuildContext context) {
    final Color c1 = urgent ? danger : base;
    final Color c2 = urgent ? danger.withValues(alpha: 0.65) : base.withValues(alpha: 0.55);
    return Container(
      height: 8,
      color: track.withValues(alpha: 0.35),
      child: Align(
        alignment: Alignment.centerLeft,
        child: LayoutBuilder(
          builder: (context, box) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.linear,
              width: box.maxWidth * progress.clamp(0.0, 1.0),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [c1, c2]),
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(6),
                  bottomRight: Radius.circular(6),
                ),
                boxShadow: urgent
                    ? [BoxShadow(color: danger.withValues(alpha: 0.6), blurRadius: 8)]
                    : null,
              ),
            );
          },
        ),
      ),
    );
  }
}
