import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../data/duel_solo_questions.dart';
import '../firebase_bootstrap.dart';
import '../models/question.dart';
import '../models/subject.dart';
import '../screens/quick_modes/quick_modes_shared.dart';
import 'remote_question_service.dart';

/// Düello/Royale özellikleri Firebase yapılandırılmadan kullanılmaya
/// çalışılırsa fırlatılan istisna. UI bunu yakalayıp kullanıcıya bilgilendirici
/// bir mesaj gösterir (çevrimdışıyken sadece "Tek Başına Yarış" çalışır).
class DuelNotConfiguredException implements Exception {
  const DuelNotConfiguredException();
  @override
  String toString() =>
      'Çok oyunculu Düello/Royale şu an kullanılamıyor: sunucu bağlantısı '
      'kurulamadı. İnternetini kontrol et; sorun sürerse uygulamayı yeniden '
      'başlat. Bu sırada "Tek Başına Yarış" çevrimdışı da çalışır.';
}

/// Oda dolu olduğunda katılmaya çalışılırsa fırlatılır.
class RoomFullException implements Exception {
  const RoomFullException();
  @override
  String toString() => 'Bu oda dolu, başka bir odaya katılabilirsin.';
}

/// Oda bulunamadı / kod hatalı / oda çoktan başlamış.
class RoomUnavailableException implements Exception {
  final String reason;
  const RoomUnavailableException(this.reason);
  @override
  String toString() => reason;
}

/// Bir oyuncunun tek bir soruya verdiği cevap.
class DuelAnswer {
  final int idx;
  final int correctMs;
  const DuelAnswer({required this.idx, required this.correctMs});

  factory DuelAnswer.fromMap(Map data) => DuelAnswer(
        idx: (data['idx'] as num?)?.toInt() ?? -1,
        correctMs: (data['correctMs'] as num?)?.toInt() ?? 0,
      );
}

/// Bir odadaki tek bir oyuncunun anlık durumu.
class DuelPlayer {
  final String uid;
  final String name;
  final int score;
  final Map<int, DuelAnswer> answers;
  final bool eliminated;
  final int? eliminatedAtRound;
  final DateTime? joinedAt;

  const DuelPlayer({
    required this.uid,
    required this.name,
    required this.score,
    required this.answers,
    required this.eliminated,
    required this.eliminatedAtRound,
    required this.joinedAt,
  });

  factory DuelPlayer.fromMap(String uid, Map data) {
    final rawAnswers = Map<String, dynamic>.from(data['answers'] as Map? ?? const {});
    final answers = <int, DuelAnswer>{};
    rawAnswers.forEach((k, v) {
      final qi = int.tryParse(k);
      if (qi != null && v is Map) answers[qi] = DuelAnswer.fromMap(v);
    });
    final ts = data['joinedAt'];
    return DuelPlayer(
      uid: uid,
      name: data['name'] as String? ?? 'Oyuncu',
      score: (data['score'] as num?)?.toInt() ?? 0,
      answers: answers,
      eliminated: data['eliminated'] == true,
      eliminatedAtRound: (data['eliminatedAtRound'] as num?)?.toInt(),
      joinedAt: ts is Timestamp ? ts.toDate() : null,
    );
  }
}

/// `duel_rooms/{roomId}` dokümanının tam, çözümlenmiş hali.
class DuelRoom {
  final String id;
  final String code;
  final String name;
  final String hostUid;
  final String hostName;
  final String mode; // 'duello' | 'royale'
  final List<String> subjectFilter;
  final String? topicId;
  final String? topicAd;
  final int maxPlayers;
  final bool isPublic;
  final String status; // 'waiting' | 'active' | 'finished'
  final DateTime? createdAt;
  final DateTime? autoStartAt;
  final DateTime? startedAt;
  final int perQuestionSeconds;
  final int totalQuestions;
  final List<Question> questions;
  final Map<String, DuelPlayer> players;
  final int lastElimRound;

  /// Erken geçişlerle "kazanılmış" toplam süre (ms).
  ///
  /// Oyun akışının TEK senkron kaynağı `startedAt`'tir: her istemci soruyu
  /// "başlangıçtan bu yana geçen süre / soru süresi" ile hesaplar. Tüm
  /// oyuncular bir soruyu cevapladığında kalan süreyi beklemek anlamsız
  /// olduğundan, o soruda kalan süre buraya EKLENİR. Böylece herkesin
  /// hesabındaki "geçen süre" aynı anda ileri sıçrar ve senkron BOZULMADAN
  /// sonraki soruya geçilir.
  ///
  /// Alternatif olarak odaya "şu an kaçıncı sorudayız" diye bir alan
  /// yazılabilirdi; ama o zaman geri sayım, Royale elemesi ve bitiş kontrolü
  /// ayrı bir zaman kaynağına bağlanır ve iki kaynak birbirinden kayabilirdi.
  /// Tek bir sayıyı kaydırmak bu riski tamamen ortadan kaldırıyor.
  final int timeShiftMs;

  /// Erken geçişin uygulandığı SON soru indeksi (-1: hiç geçilmedi).
  /// Aynı sorunun birden çok cihaz tarafından tekrar tekrar kaydırılmasını
  /// engeller — bkz. [DuelService.skipToNextIfAllAnswered].
  final int lastSkippedIndex;

  const DuelRoom({
    required this.id,
    required this.code,
    required this.name,
    required this.hostUid,
    required this.hostName,
    required this.mode,
    required this.subjectFilter,
    required this.topicId,
    required this.topicAd,
    required this.maxPlayers,
    required this.isPublic,
    required this.status,
    required this.createdAt,
    required this.autoStartAt,
    required this.startedAt,
    required this.perQuestionSeconds,
    required this.totalQuestions,
    required this.questions,
    required this.players,
    required this.lastElimRound,
    this.timeShiftMs = 0,
    this.lastSkippedIndex = -1,
  });

  bool get isRoyale => mode == 'royale';
  bool get isFull => players.length >= maxPlayers;

  /// subjectFilter id'lerini okunur ders adlarına çevirir ("Tüm dersler
  /// karışık" boşsa) — [RoomSummary.subjectsLabel] ile aynı mantık.
  String get subjectsLabel {
    if (subjectFilter.isEmpty) return 'Tüm dersler karışık';
    final names = subjectFilter.map((id) {
      for (final s in kSubjects) {
        if (s.id == id) return s.ad;
      }
      return id;
    }).toList();
    return names.join(', ');
  }

  /// Ders adı + (varsa) konu adı + soru sayısı + süre bilgisini tek satırda
  /// birleştirir — bekleme odasında/oda kartında host'un yapılandırmasını
  /// göstermek için.
  String get configLabel {
    final subj = topicAd != null && topicAd!.isNotEmpty ? '$subjectsLabel · $topicAd' : subjectsLabel;
    return '$subj · $totalQuestions soru · $perQuestionSeconds sn';
  }

  List<DuelPlayer> get playersByScore {
    final list = players.values.toList();
    list.sort((a, b) => b.score.compareTo(a.score));
    return list;
  }

  factory DuelRoom.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final rawQuestions = data['questions'] as List? ?? const [];
    final questions = rawQuestions
        .whereType<Map>()
        .map((m) => _questionFromMap(Map<String, dynamic>.from(m)))
        .toList();
    final rawPlayers = Map<String, dynamic>.from(data['players'] as Map? ?? const {});
    final players = <String, DuelPlayer>{};
    rawPlayers.forEach((uid, v) {
      if (v is Map) players[uid] = DuelPlayer.fromMap(uid, v);
    });
    DateTime? toDate(dynamic v) => v is Timestamp ? v.toDate() : null;
    return DuelRoom(
      id: doc.id,
      code: data['code'] as String? ?? '',
      name: data['name'] as String? ?? 'Düello Odası',
      hostUid: data['hostUid'] as String? ?? '',
      hostName: data['hostName'] as String? ?? '',
      mode: data['mode'] as String? ?? 'duello',
      subjectFilter: List<String>.from(data['subjectFilter'] as List? ?? const []),
      topicId: data['topicId'] as String?,
      topicAd: data['topicAd'] as String?,
      maxPlayers: (data['maxPlayers'] as num?)?.toInt() ?? 2,
      isPublic: data['isPublic'] == true,
      status: data['status'] as String? ?? 'waiting',
      createdAt: toDate(data['createdAt']),
      autoStartAt: toDate(data['autoStartAt']),
      startedAt: toDate(data['startedAt']),
      perQuestionSeconds: (data['perQuestionSeconds'] as num?)?.toInt() ?? 30,
      totalQuestions: (data['totalQuestions'] as num?)?.toInt() ?? 10,
      questions: questions,
      players: players,
      lastElimRound: (data['lastElimRound'] as num?)?.toInt() ?? 0,
      // Eski odalarda bu alanlar YOKTUR; varsayılanlar (0 / -1) o odaların
      // eskisi gibi, sadece süreyle ilerlemesini sağlar.
      timeShiftMs: (data['timeShiftMs'] as num?)?.toInt() ?? 0,
      lastSkippedIndex: (data['lastSkippedIndex'] as num?)?.toInt() ?? -1,
    );
  }
}

/// Açık odalar listesindeki hafif özet (tam soru listesini taşımaz).
class RoomSummary {
  final String id;
  final String code;
  final String name;
  final String mode;
  final List<String> subjectFilter;
  final String? topicId;
  final String? topicAd;
  final int maxPlayers;
  final int playerCount;
  final int perQuestionSeconds;
  final int totalQuestions;
  final DateTime? autoStartAt;

  const RoomSummary({
    required this.id,
    required this.code,
    required this.name,
    required this.mode,
    required this.subjectFilter,
    required this.topicId,
    required this.topicAd,
    required this.maxPlayers,
    required this.playerCount,
    required this.perQuestionSeconds,
    required this.totalQuestions,
    required this.autoStartAt,
  });

  /// subjectFilter id'lerini okunur ders adlarına çevirir ("Tüm dersler
  /// karışık" boşsa).
  String get subjectsLabel {
    if (subjectFilter.isEmpty) return 'Tüm dersler karışık';
    final names = subjectFilter.map((id) {
      for (final s in kSubjects) {
        if (s.id == id) return s.ad;
      }
      return id;
    }).toList();
    return names.join(', ');
  }

  /// Ders adı + (varsa) konu adını birleştirir — oda kartında/bekleme
  /// odasında host'un seçtiği içerik yapılandırmasını gösterir.
  String get configLabel {
    if (topicAd != null && topicAd!.isNotEmpty) return '$subjectsLabel · $topicAd';
    return subjectsLabel;
  }
}

// ── Question <-> Firestore map dönüşümü (Question modeli toJson içermediği
// için burada tanımlı; sadece Düello için gereken alanları taşır). ──
Map<String, dynamic> _questionToMap(Question q) => {
      'soru': q.soru,
      'secenekler': q.secenekler,
      'dogruIndex': q.dogruIndex,
      'aciklama': q.aciklama,
      if (q.distractorAciklama != null) 'distractorAciklama': q.distractorAciklama,
      if (q.subjectAd != null) 'subjectAd': q.subjectAd,
    };

Question _questionFromMap(Map<String, dynamic> m) => Question(
      soru: m['soru'] as String? ?? '',
      secenekler: List<String>.from(m['secenekler'] as List? ?? const []),
      dogruIndex: (m['dogruIndex'] as num?)?.toInt() ?? 0,
      aciklama: m['aciklama'] as String? ?? '',
      distractorAciklama: m['distractorAciklama'] as String?,
      subjectAd: m['subjectAd'] as String?,
    );

/// KPSS Düello / KPSS Royale için gerçek zamanlı (istemci-taraflı Firestore)
/// servis katmanı. Cloud Functions KULLANMAZ — tüm oyun akışı istemci
/// okuma/yazma + `snapshots()` dinleyicileriyle yürür (bkz. ChatService,
/// LeagueService aynı desen).
///
/// Firebase yapılandırılmamışsa yazma metodları [DuelNotConfiguredException]
/// fırlatır, stream metodları ise boş yayınlayan sabit stream döner.
class DuelService {
  static const String roomsCollection = 'duel_rooms';

  /// Oda dolmazsa otomatik başlama süresi (oda kurulduktan sonra).
  static const Duration autoStartAfter = Duration(minutes: 2);

  static const String modeDuello = 'duello';
  static const String modeRoyale = 'royale';

  bool get isConfigured => isFirebaseConfigured;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _rooms => _db.collection(roomsCollection);

  void _requireConfigured() {
    if (!isConfigured) throw const DuelNotConfiguredException();
  }

  /// Anonim (ya da mevcut) Firebase kullanıcısını garanti eder ve uid döner.
  /// Kullanıcı zaten Google/Apple ile giriş yapmışsa o hesabı kullanır.
  Future<String> ensureSignedIn() async {
    _requireConfigured();
    final auth = FirebaseAuth.instance;
    if (auth.currentUser != null) return auth.currentUser!.uid;
    final cred = await auth.signInAnonymously();
    final uid = cred.user?.uid;
    if (uid == null) throw const DuelNotConfiguredException();
    return uid;
  }

  String? get currentUid => isConfigured ? FirebaseAuth.instance.currentUser?.uid : null;

  // ── Rastgele isim üreticiler ──

  static const List<String> _adjectives = [
    'Hızlı', 'Keskin', 'Azimli', 'Cesur', 'Bilge', 'Çevik', 'Zeki', 'Atik',
    'Gözüpek', 'Sabırlı', 'Kartal', 'Yıldırım', 'Şimşek', 'Usta', 'Kararlı',
    'Neşeli', 'Sakin', 'Görkemli', 'Efsane', 'Gizemli',
  ];

  static const List<String> _animals = [
    'Kaplan', 'Baykuş', 'Kartal', 'Tilki', 'Kurt', 'Şahin', 'Aslan', 'Panter',
    'Kırlangıç', 'Doğan', 'Ceylan', 'Bufalo', 'Kunduz', 'Vaşak', 'Zümrüdüanka',
    'Delfin', 'Puma', 'Leopar', 'Karınca', 'Arı',
  ];

  static const List<String> _roomThemes = [
    'Zafer', 'Bilgi', 'Bilgelik', 'Şampiyon', 'Kartal', 'Yıldız', 'Fırtına',
    'Zirve', 'Usta', 'Kahraman', 'Efsane', 'Şimşek', 'Alev', 'Rüzgar', 'Zeka',
  ];

  final Random _rnd = Random();

  /// "Hızlı Kırlangıç", "Bilge Baykuş" gibi Türkçe sıfat+hayvan kombinasyonu.
  String generateRandomPlayerName() {
    final a = _adjectives[_rnd.nextInt(_adjectives.length)];
    final b = _animals[_rnd.nextInt(_animals.length)];
    return '$a $b';
  }

  /// "Keskin Kaplan Odası", "Zafer Odası" gibi Türkçe oda adı.
  String generateRandomRoomName() {
    // Yarısı sıfat+hayvan, yarısı tema bazlı.
    if (_rnd.nextBool()) {
      final a = _adjectives[_rnd.nextInt(_adjectives.length)];
      final b = _animals[_rnd.nextInt(_animals.length)];
      return '$a $b Odası';
    }
    final t = _roomThemes[_rnd.nextInt(_roomThemes.length)];
    return '$t Odası';
  }

  String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // I,O,0,1 karışmasın diye çıkarıldı
    return List.generate(6, (_) => chars[_rnd.nextInt(chars.length)]).join();
  }

  /// Çakışmayan 6 haneli bir oda kodu üretir (birkaç deneme yapar).
  Future<String> _generateUniqueCode() async {
    for (var attempt = 0; attempt < 6; attempt++) {
      final code = _generateCode();
      final snap = await _rooms.where('code', isEqualTo: code).limit(1).get();
      if (snap.docs.isEmpty) return code;
    }
    // Son çare: zamana dayalı benzersizlik.
    return _generateCode();
  }

  // ── Tek Başına Yarış (solo) — LOKAL soru havuzu ──
  //
  // Solo mod Firestore GEREKTİRMEZ; bu bölüm tamamen çevrimdışı çalışır ve
  // çok oyunculu (oda) akışını hiçbir şekilde etkilemez.

  /// Solo bir turda sorulacak varsayılan soru sayısı.
  static const int soloQuestionsPerRound = 10;

  /// Uygulama açık olduğu sürece solo turlarda KULLANILMIŞ soru anahtarları
  /// ([Question.key]). Turdan tura aynı soruların tekrar gelmesini engeller;
  /// havuz tükendiğinde [buildSoloQuestions] içinde temizlenip havuz yeniden
  /// karıştırılır (böylece sonsuz döngü yerine "bitince baştan" davranışı olur).
  static final Set<String> _soloUsedKeys = <String>{};

  /// Solo turda kullanılmış soru takibini sıfırlar (ör. kullanıcı "havuzu
  /// yenile" derse ya da testlerde).
  static void resetSoloProgress() => _soloUsedKeys.clear();

  /// Şu ana kadar bu oturumda solo modda görülen soru sayısı.
  static int get soloSeenCount => _soloUsedKeys.length;

  /// "Tek Başına Yarış" için bir turluk soru listesi hazırlar.
  ///
  /// Havuz İKİ yerel kaynağın birleşimidir — ikisi de internet gerektirmez:
  ///  1. `assets/data/*.json` ders bankası ([QuickModesShared.collectAll]).
  ///     [RemoteQuestionService] önbellek varsa tam havuzu, yoksa uygulamayla
  ///     gömülü yedek soruları ANINDA döndürdüğü için çevrimdışı da doludur.
  ///  2. [kDuelSoloQuestions] — düello temposuna göre seçilmiş, derleme
  ///     zamanında gömülü ek havuz. Ders listesi hiç yüklenememişse bile
  ///     solo modun soru bulmasını GARANTİ eder.
  ///
  /// Aynı soru iki kaynakta da varsa [Question.key] üzerinden teke indirilir.
  /// Daha önce sorulmamış sorular önceliklendirilir; havuz tükenince kullanılmış
  /// kaydı temizlenip liste yeniden karıştırılır.
  ///
  /// Hiçbir durumda istisna fırlatmaz — en kötü ihtimalle gömülü havuzdan döner.
  Future<List<Question>> buildSoloQuestions({
    required List<Subject> subjects,
    RemoteQuestionService? remote,
    int count = soloQuestionsPerRound,
  }) async {
    final pool = <Question>[];

    // 1) JSON ders bankası (varsa).
    if (subjects.isNotEmpty && remote != null) {
      try {
        pool.addAll(await QuickModesShared.collectAll(subjects, remote, rnd: _rnd));
      } catch (e) {
        debugPrint('DuelService.buildSoloQuestions: ders bankası okunamadı: $e');
      }
    }

    // 2) Gömülü düello havuzu — her zaman eklenir (çevrimdışı garantisi).
    pool.addAll(kDuelSoloQuestions);

    // Tekrarlayan soruları (aynı metinli) teke indir.
    final unique = <String, Question>{};
    for (final q in pool) {
      if (q.secenekler.length < 2) continue; // bozuk kayıtları ele
      unique.putIfAbsent(q.key, () => q);
    }
    if (unique.isEmpty) return const [];

    final all = unique.values.toList()..shuffle(_rnd);

    // Daha önce sorulmamışları öne al; yetmiyorsa havuzu baştan başlat.
    var fresh = all.where((q) => !_soloUsedKeys.contains(q.key)).toList();
    if (fresh.length < count) {
      _soloUsedKeys.clear();
      fresh = all;
    }

    final chosen = fresh.take(count).toList();
    _soloUsedKeys.addAll(chosen.map((q) => q.key));
    return chosen;
  }

  // ── Oda oluşturma ──

  /// Verilen mod için 10 (royale'de daha fazla) soruyu HEMEN seçer, çakışmayan
  /// bir kod üretir ve odayı Firestore'a yazar, roomId döner.
  ///
  /// Sorular [QuickModesShared.collectAll] ile (tüm derslerden ya da
  /// [subjectFilter] varsa sadece o derslerden; [topicId] de verilmişse
  /// SADECE o konudan) karışık olarak seçilir ve odaya TEK SEFERDE gömülür —
  /// böylece tüm oyuncular AYNI soruları görür. [perQuestionSeconds] ve
  /// [totalQuestions] host'un seçtiği süre/soru sayısı yapılandırmasıdır ve
  /// olduğu gibi oda dokümanına yazılır — [DuelPlayScreen] (online) bu
  /// alanları odadan okuyup zamanlayıcıyı/soru döngüsünü buna göre çalıştırır.
  Future<String> createRoom({
    required String mode,
    required String hostName,
    required List<String> subjectFilter,
    required int maxPlayers,
    required bool isPublic,
    required List<Subject> subjects,
    required RemoteQuestionService remote,
    String? roomName,
    String? topicId,
    int perQuestionSeconds = 30,
    int? totalQuestions,
  }) async {
    _requireConfigured();
    final uid = await ensureSignedIn();

    final total = totalQuestions ?? (mode == modeRoyale ? 15 : 10);

    // Ders filtresi uygula.
    final filtered = subjectFilter.isEmpty
        ? subjects
        : subjects.where((s) => subjectFilter.contains(s.id)).toList();
    final poolSubjects = filtered.isEmpty ? subjects : filtered;

    // Konu filtresi uygula: topicId verilmişse SADECE o konudan soru topla
    // (ders(ler) içinde o id'ye sahip konuyu bul); bulunamazsa (tutarsız/eski
    // veri) sessizce tüm derse geri dön.
    List<Subject> effectiveSubjects = poolSubjects;
    String? topicAd;
    if (topicId != null) {
      final narrowed = <Subject>[];
      for (final s in poolSubjects) {
        final matching = s.konular.where((t) => t.id == topicId).toList();
        if (matching.isNotEmpty) {
          narrowed.add(Subject(meta: s.meta, konular: matching));
          topicAd ??= matching.first.baslik;
        }
      }
      if (narrowed.isNotEmpty) effectiveSubjects = narrowed;
    }

    final pool = await QuickModesShared.collectAll(
      effectiveSubjects,
      remote,
      rnd: _rnd,
    );
    if (pool.length < total) {
      // Yeterli soru yoksa yine de eldeki kadarla devam et (en az 5 iste).
      if (pool.length < 5) {
        throw const RoomUnavailableException('Soru havuzu yüklenemedi, tekrar dene.');
      }
    }
    final chosen = pool.take(total).toList();
    final questionMaps = chosen.map(_questionToMap).toList();

    final code = await _generateUniqueCode();
    final now = DateTime.now();

    final docRef = _rooms.doc();
    await docRef.set({
      'code': code,
      'name': roomName ?? generateRandomRoomName(),
      'hostUid': uid,
      'hostName': hostName,
      'mode': mode,
      'subjectFilter': subjectFilter,
      'topicId': topicId,
      'topicAd': topicAd,
      'maxPlayers': maxPlayers,
      'isPublic': isPublic,
      'status': 'waiting',
      'createdAt': FieldValue.serverTimestamp(),
      'autoStartAt': Timestamp.fromDate(now.add(autoStartAfter)),
      'startedAt': null,
      'perQuestionSeconds': perQuestionSeconds,
      'totalQuestions': chosen.length,
      'lastElimRound': 0,
      // Erken geçiş durumu (bkz. skipToNextIfAllAnswered). Baştan yazılıyor ki
      // ilk kaydırma bir "alan oluşturma" değil, düz bir güncelleme olsun.
      'timeShiftMs': 0,
      'lastSkippedIndex': -1,
      'questions': questionMaps,
      'players': {
        uid: {
          'name': hostName,
          'joinedAt': FieldValue.serverTimestamp(),
          'score': 0,
          'answers': <String, dynamic>{},
          'eliminated': false,
        },
      },
      // `players` bir HARİTA alanı olduğu için Firestore'da "şu kullanıcıyı
      // içeren odalar" diye sorgulanamaz. Aynı uid listesini ayrıca bir DİZİ
      // olarak da tutuyoruz ki `arrayContains` ile sorgulanabilsin — hesap
      // silme (bkz. AccountDeletionService) bu alan sayesinde kullanıcının
      // katıldığı TÜM odaları bulup temizleyebiliyor.
      // İki alan birlikte güncellenmeli: players.<uid> yazan/silen her yer
      // playerUids'i de arrayUnion/arrayRemove ile güncellemek zorunda.
      'playerUids': [uid],
    });
    return docRef.id;
  }

  // ── Katılma ──

  Future<String> joinRoomByCode(String code, String playerName) async {
    _requireConfigured();
    final normalized = code.trim().toUpperCase();
    final snap = await _rooms.where('code', isEqualTo: normalized).limit(1).get();
    if (snap.docs.isEmpty) {
      throw const RoomUnavailableException('Bu koda sahip bir oda bulunamadı.');
    }
    final roomId = snap.docs.first.id;
    await joinRoomById(roomId, playerName);
    return roomId;
  }

  Future<void> joinRoomById(String roomId, String playerName) async {
    _requireConfigured();
    final uid = await ensureSignedIn();
    final ref = _rooms.doc(roomId);
    await _db.runTransaction((tx) async {
      final doc = await tx.get(ref);
      if (!doc.exists) throw const RoomUnavailableException('Oda artık mevcut değil.');
      final data = doc.data()!;
      final players = Map<String, dynamic>.from(data['players'] as Map? ?? const {});
      final alreadyIn = players.containsKey(uid);
      final status = data['status'] as String? ?? 'waiting';
      if (!alreadyIn) {
        if (status != 'waiting') {
          throw const RoomUnavailableException('Oda çoktan başladı, katılamazsın.');
        }
        final maxPlayers = (data['maxPlayers'] as num?)?.toInt() ?? 2;
        if (players.length >= maxPlayers) throw const RoomFullException();
      }
      tx.update(ref, {
        'players.$uid.name': playerName,
        if (!alreadyIn) 'players.$uid.joinedAt': FieldValue.serverTimestamp(),
        if (!alreadyIn) 'players.$uid.score': 0,
        if (!alreadyIn) 'players.$uid.answers': <String, dynamic>{},
        if (!alreadyIn) 'players.$uid.eliminated': false,
        // Sorgulanabilir uid dizisini de güncel tut (bkz. createRoom'daki
        // 'playerUids' açıklaması). arrayUnion tekrar eklemeye karşı güvenli,
        // ayrıca ESKİ odalarda (alan hiç yokken) diziyi oluşturur.
        'playerUids': FieldValue.arrayUnion([uid]),
      });
    });
  }

  // ── Dinleyiciler ──

  /// Açık odalar akışı.
  ///
  /// ÖNEMLİ (düzeltilen hata): Firestore güvenlik kuralı `duel_rooms` okuması
  /// için `isPublic == true` şartını da içerir. `isPublic` filtresi SADECE
  /// istemci tarafında (Dart `where`) uygulanırsa, Firestore bu sorgunun
  /// TÜM olası sonuçlarının güvenlik kuralını sağladığını kanıtlayamaz ve
  /// SORGUNUN TAMAMINI `permission-denied` ile reddeder (tek tek belge
  /// okuma kuralı sağlansa bile). Bu yüzden `isPublic` filtresi de GERÇEK
  /// Firestore sorgusuna dahil edilmelidir — iki eşitlik (`==`) filtresinin
  /// birlikte kullanılması composite index GEREKTİRMEZ, `mode` ve sıralama
  /// yine istemci tarafında kalabilir (oda hacmi düşük).
  Stream<List<RoomSummary>> listOpenRooms({String? mode}) {
    if (!isConfigured) return Stream<List<RoomSummary>>.value(const []);
    return _rooms
        .where('status', isEqualTo: 'waiting')
        .where('isPublic', isEqualTo: true)
        .limit(60)
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .where((d) => mode == null || (d.data()['mode'] as String?) == mode)
          .map((d) {
        final data = d.data();
        final players = Map<String, dynamic>.from(data['players'] as Map? ?? const {});
        final ts = data['autoStartAt'];
        return RoomSummary(
          id: d.id,
          code: data['code'] as String? ?? '',
          name: data['name'] as String? ?? 'Düello Odası',
          mode: data['mode'] as String? ?? 'duello',
          subjectFilter: List<String>.from(data['subjectFilter'] as List? ?? const []),
          topicId: data['topicId'] as String?,
          topicAd: data['topicAd'] as String?,
          maxPlayers: (data['maxPlayers'] as num?)?.toInt() ?? 2,
          playerCount: players.length,
          perQuestionSeconds: (data['perQuestionSeconds'] as num?)?.toInt() ?? 30,
          totalQuestions: (data['totalQuestions'] as num?)?.toInt() ?? 10,
          autoStartAt: ts is Timestamp ? ts.toDate() : null,
        );
      }).toList();
      // En yeni (autoStartAt en ileride olan) önce.
      list.sort((a, b) {
        final ax = a.autoStartAt?.millisecondsSinceEpoch ?? 0;
        final bx = b.autoStartAt?.millisecondsSinceEpoch ?? 0;
        return bx.compareTo(ax);
      });
      return list;
    });
  }

  Stream<DuelRoom?> watchRoom(String roomId) {
    if (!isConfigured) return Stream<DuelRoom?>.value(null);
    return _rooms.doc(roomId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return DuelRoom.fromDoc(doc);
    });
  }

  // ── Başlatma ──

  /// Odayı 'active' durumuna geçirir ve `startedAt`'i sunucu zamanıyla set eder.
  /// Transaction + `status == 'waiting'` koşuluyla EŞZAMANLI çift-başlatmayı
  /// engeller (host manuel bassa da, herhangi bir oyuncunun cihazı oda
  /// dolunca/autoStartAt geçince tetiklese de yalnızca İLK yazan kazanır).
  Future<void> startRoom(String roomId) async {
    _requireConfigured();
    final ref = _rooms.doc(roomId);
    await _db.runTransaction((tx) async {
      final doc = await tx.get(ref);
      if (!doc.exists) return;
      final status = doc.data()!['status'] as String? ?? 'waiting';
      if (status != 'waiting') return; // Zaten başlamış — sessizce çık.
      tx.update(ref, {
        'status': 'active',
        'startedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Odayı 'finished' olarak işaretler (tüm sorular bitince herhangi bir
  /// oyuncunun cihazı tetikler). status == 'active' koşuluyla korunur.
  Future<void> finishRoom(String roomId) async {
    if (!isConfigured) return;
    final ref = _rooms.doc(roomId);
    try {
      await _db.runTransaction((tx) async {
        final doc = await tx.get(ref);
        if (!doc.exists) return;
        final status = doc.data()!['status'] as String? ?? 'waiting';
        if (status != 'active') return;
        tx.update(ref, {'status': 'finished'});
      });
    } catch (e) {
      debugPrint('DuelService.finishRoom başarısız: $e');
    }
  }

  // ── Cevap gönderme ──

  /// Bir soruya verilen cevabı işler: puanı hesaplar ve SADECE ilgili oyuncunun
  /// `players.<uid>.score` (FieldValue.increment) + `players.<uid>.answers.<qi>`
  /// alanlarını nokta-yollu update ile günceller — tüm players map'ini yeniden
  /// yazmadan, eşzamanlı yazımlarda veri kaybını önleyerek.
  ///
  /// Puan = doğruysa 100 + kalan süre bonusu; yanlış/boşsa 0 (yine de kaydedilir).
  Future<void> submitAnswer(
    String roomId,
    int questionIndex,
    int answerIdx,
    int elapsedMs,
    int correctIndex,
    int perQuestionSeconds,
  ) async {
    _requireConfigured();
    final uid = currentUid;
    if (uid == null) return;
    final isCorrect = answerIdx == correctIndex;
    var points = 0;
    if (isCorrect) {
      final totalMs = perQuestionSeconds * 1000;
      final remaining = (totalMs - elapsedMs).clamp(0, totalMs);
      final bonus = (remaining / 1000 * 3).round();
      points = 100 + bonus;
    }
    final ref = _rooms.doc(roomId);
    await ref.update({
      'players.$uid.answers.$questionIndex': {'idx': answerIdx, 'correctMs': elapsedMs},
      'players.$uid.score': FieldValue.increment(points),
    });
  }

  /// Tüm oyuncular cevapladığında sonraki soruya geçmeden ÖNCE bırakılan süre.
  /// Sıfır olsaydı ekran, kullanıcı kendi cevabının doğru/yanlış olduğunu ve
  /// açıklamasını görmeye fırsat bulamadan anında değişirdi.
  static const int allAnsweredGraceMs = 1500;

  /// Bir sorudaki TÜM (elenmemiş) oyuncular cevap verdiyse, o soruda kalan
  /// süreyi `timeShiftMs`'e ekleyerek herkesi aynı anda sonraki soruya taşır.
  ///
  /// Neden oda dokümanına yazıyoruz: erken geçiş SADECE geçişi fark eden
  /// cihazda uygulanırsa oyuncular farklı sorularda kalır ve çok oyunculu
  /// senkron çöker. Kaydırma odaya yazıldığı için tüm istemciler aynı anda
  /// aynı sonucu hesaplar.
  ///
  /// GÜVENLİK: "herkes cevapladı" iddiası çağırana DEĞİL, transaction içinde
  /// okunan oda verisine bakılarak doğrulanır. Böylece tek bir oyuncunun
  /// cihazı, rakipleri henüz cevaplamamışken soruyu ileri saramaz.
  ///
  /// `lastSkippedIndex` koşulu sayesinde aynı soru için birden çok cihaz
  /// çağırsa bile kaydırma YALNIZCA BİR KEZ uygulanır.
  Future<void> skipToNextIfAllAnswered(String roomId, int questionIndex) async {
    if (!isConfigured) return;
    if (questionIndex < 0) return;
    final ref = _rooms.doc(roomId);
    try {
      await _db.runTransaction((tx) async {
        final doc = await tx.get(ref);
        if (!doc.exists) return;
        final data = doc.data()!;
        if ((data['status'] as String?) != 'active') return;

        final lastSkipped = (data['lastSkippedIndex'] as num?)?.toInt() ?? -1;
        if (lastSkipped >= questionIndex) return; // Bu soru zaten işlendi.

        final startedAt = data['startedAt'];
        if (startedAt is! Timestamp) return; // Maç henüz başlamamış.

        final perQ = (data['perQuestionSeconds'] as num?)?.toInt() ?? 30;
        final shift = (data['timeShiftMs'] as num?)?.toInt() ?? 0;

        // Elenen oyuncular cevap VEREMEZ; onları beklemek oyunu kilitlerdi.
        final rawPlayers = Map<String, dynamic>.from(data['players'] as Map? ?? const {});
        final aktif = rawPlayers.values
            .whereType<Map>()
            .where((p) => p['eliminated'] != true)
            .toList();
        if (aktif.isEmpty) return;

        final hepsiCevapladi = aktif.every((p) {
          final answers = p['answers'];
          return answers is Map && answers.containsKey('$questionIndex');
        });
        if (!hepsiCevapladi) return;

        final gecen = DateTime.now().difference(startedAt.toDate()).inMilliseconds + shift;
        final kalan = (questionIndex + 1) * perQ * 1000 - gecen;

        // Süre zaten dolmak üzereyse kaydırmaya gerek yok; yalnızca bu sorunun
        // tekrar tekrar denenmemesi için işaretliyoruz.
        if (kalan <= allAnsweredGraceMs) {
          tx.update(ref, {'lastSkippedIndex': questionIndex});
          return;
        }

        tx.update(ref, {
          'timeShiftMs': shift + (kalan - allAnsweredGraceMs),
          'lastSkippedIndex': questionIndex,
        });
      });
    } catch (e) {
      debugPrint('DuelService.skipToNextIfAllAnswered başarısız: $e');
    }
  }

  // ── Royale eleme ──

  /// Her 5 soruda bir (istemci tarafında ilk fark eden oyuncu tetikler)
  /// o ana kadarki skorlara göre en düşük performanslı oyuncuların bir kısmını
  /// eler. Transaction + `lastElimRound` koşuluyla aynı turun BİRDEN FAZLA
  /// cihaz tarafından tekrar işlenmesini engeller.
  ///
  /// Strateji (MVP): her turda hayatta kalan oyuncu sayısını yarıya indir,
  /// asla 2'nin altına düşürme — böylece finale doğru kademeli olarak 2 kişi
  /// kalır.
  Future<void> checkAndEliminate(String roomId, int afterQuestionIndex) async {
    if (!isConfigured) return;
    final roundNumber = (afterQuestionIndex + 1) ~/ 5;
    if (roundNumber <= 0) return;
    final ref = _rooms.doc(roomId);
    try {
      await _db.runTransaction((tx) async {
        final doc = await tx.get(ref);
        if (!doc.exists) return;
        final data = doc.data()!;
        if ((data['mode'] as String?) != modeRoyale) return;
        final lastRound = (data['lastElimRound'] as num?)?.toInt() ?? 0;
        if (lastRound >= roundNumber) return; // Bu tur zaten işlenmiş.

        final rawPlayers = Map<String, dynamic>.from(data['players'] as Map? ?? const {});
        // Hayatta kalanlar.
        final alive = rawPlayers.entries.where((e) {
          final p = e.value as Map;
          return p['eliminated'] != true;
        }).toList();
        if (alive.length <= 2) {
          tx.update(ref, {'lastElimRound': roundNumber});
          return;
        }
        // Skora göre artan sırala (en düşük başta).
        alive.sort((a, b) {
          final sa = ((a.value as Map)['score'] as num?)?.toInt() ?? 0;
          final sb = ((b.value as Map)['score'] as num?)?.toInt() ?? 0;
          return sa.compareTo(sb);
        });
        final targetRemaining = max(2, (alive.length / 2).ceil());
        final eliminateCount = alive.length - targetRemaining;
        final updates = <String, dynamic>{'lastElimRound': roundNumber};
        for (var i = 0; i < eliminateCount; i++) {
          final uid = alive[i].key;
          updates['players.$uid.eliminated'] = true;
          updates['players.$uid.eliminatedAtRound'] = roundNumber;
        }
        tx.update(ref, updates);
      });
    } catch (e) {
      debugPrint('DuelService.checkAndEliminate başarısız: $e');
    }
  }

  /// Bir oyuncu odadan ayrılırsa (waiting aşamasında) kendini players'tan siler.
  Future<void> leaveRoom(String roomId) async {
    if (!isConfigured) return;
    final uid = currentUid;
    if (uid == null) return;
    try {
      await _rooms.doc(roomId).update({
        'players.$uid': FieldValue.delete(),
        // Harita ve dizi ASLA ayrışmamalı — biri silinip diğeri kalırsa
        // kullanıcı odadan çıkmış görünmesine rağmen sorgularda çıkmaya
        // devam eder.
        'playerUids': FieldValue.arrayRemove([uid]),
      });
    } catch (e) {
      debugPrint('DuelService.leaveRoom başarısız: $e');
    }
  }
}
