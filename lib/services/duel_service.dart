import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

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
      'Çok oyunculu Düello/Royale için internet bağlantısı ve Firebase '
      'gereklidir. Çevrimdışıyken "Tek Başına Yarış"ı deneyebilirsin.';
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

  /// startedAt + geçen süreye göre "şu an kaçıncı soruda olmamız gerektiğini"
  /// (0 tabanlı) hesaplar — sunucudan gelen zamana göre TAMAMEN istemci
  /// tarafında. Süre bittiyse totalQuestions döner (oyun bitmiş demektir).
  int currentQuestionIndex(DateTime now) {
    if (startedAt == null) return 0;
    final elapsedMs = now.difference(startedAt!).inMilliseconds;
    if (elapsedMs < 0) return 0;
    final idx = elapsedMs ~/ (perQuestionSeconds * 1000);
    return idx;
  }

  /// startedAt'e göre içinde bulunulan sorunun bitişine kalan milisaniye.
  int remainingMsForQuestion(int questionIndex, DateTime now) {
    if (startedAt == null) return perQuestionSeconds * 1000;
    final deadline = startedAt!.add(Duration(milliseconds: (questionIndex + 1) * perQuestionSeconds * 1000));
    return deadline.difference(now).inMilliseconds;
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

  Future<DuelRoom?> getRoomOnce(String roomId) async {
    if (!isConfigured) return null;
    final doc = await _rooms.doc(roomId).get();
    if (!doc.exists) return null;
    return DuelRoom.fromDoc(doc);
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
      await _rooms.doc(roomId).update({'players.$uid': FieldValue.delete()});
    } catch (e) {
      debugPrint('DuelService.leaveRoom başarısız: $e');
    }
  }
}
