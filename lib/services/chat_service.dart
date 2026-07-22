import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../firebase_bootstrap.dart';

/// Genel sohbet / DM özellikleri Firebase yapılandırılmadan kullanılmaya
/// çalışılırsa fırlatılan istisna.
class ChatNotConfiguredException implements Exception {
  const ChatNotConfiguredException();
  @override
  String toString() =>
      'Sohbet özelliği için Firebase henüz yapılandırılmadı. '
      'google-services.json / GoogleService-Info.plist eklenip '
      'initFirebaseIfConfigured() çağrıldıktan sonra aktif olacak.';
}

/// Bir mesaj gönderilmeden önce basit kötü-söz filtresine takıldığında
/// fırlatılan istisna. Ekran bunu yakalayıp kullanıcıya "mesajın uygunsuz
/// içerik barındırıyor" gibi bir uyarı gösterebilir.
class ProfanityDetectedException implements Exception {
  final String matchedWord;
  const ProfanityDetectedException(this.matchedWord);
  @override
  String toString() => 'Mesaj uygunsuz bir kelime içeriyor: $matchedWord';
}

/// Genel sohbet mesajı — 'chat_messages' koleksiyonundaki bir doküman.
class ChatMessage {
  final String id;
  final String senderUid;
  final String senderName;
  final String character;
  final String message;
  final DateTime? createdAt;

  const ChatMessage({
    required this.id,
    required this.senderUid,
    required this.senderName,
    required this.character,
    required this.message,
    required this.createdAt,
  });

  factory ChatMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final ts = data['createdAt'];
    return ChatMessage(
      id: doc.id,
      senderUid: data['senderUid'] as String? ?? '',
      senderName: data['senderName'] as String? ?? 'Bilinmeyen',
      character: data['character'] as String? ?? '',
      message: data['message'] as String? ?? '',
      createdAt: ts is Timestamp ? ts.toDate() : null,
    );
  }
}

/// İki kullanıcı arasındaki özel mesaj — 'dm_threads/{threadId}/messages'
/// altındaki bir doküman.
class DirectMessage {
  final String id;
  final String senderUid;
  final String message;
  final DateTime? createdAt;

  const DirectMessage({
    required this.id,
    required this.senderUid,
    required this.message,
    required this.createdAt,
  });

  factory DirectMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final ts = data['createdAt'];
    return DirectMessage(
      id: doc.id,
      senderUid: data['senderUid'] as String? ?? '',
      message: data['message'] as String? ?? '',
      createdAt: ts is Timestamp ? ts.toDate() : null,
    );
  }
}

/// Gelen/giden bir arkadaşlık isteği.
class FriendRequest {
  final String id;
  final String fromUid;
  final String fromName;
  final String toUid;
  final DateTime? createdAt;

  const FriendRequest({
    required this.id,
    required this.fromUid,
    required this.fromName,
    required this.toUid,
    required this.createdAt,
  });

  factory FriendRequest.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final ts = data['createdAt'];
    return FriendRequest(
      id: doc.id,
      fromUid: data['fromUid'] as String? ?? '',
      fromName: data['fromName'] as String? ?? 'Kullanıcı',
      toUid: data['toUid'] as String? ?? '',
      createdAt: ts is Timestamp ? ts.toDate() : null,
    );
  }
}

/// Arkadaş listesindeki bir kişi.
class Friend {
  final String uid;
  final String name;
  final DateTime? since;
  const Friend({required this.uid, required this.name, required this.since});

  factory Friend.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final ts = data['since'];
    return Friend(
      uid: doc.id,
      name: data['name'] as String? ?? 'Kullanıcı',
      since: ts is Timestamp ? ts.toDate() : null,
    );
  }
}

/// 'Mesajlarım' gelen kutusunda gösterilen bir DM thread'inin özeti.
class DmThreadSummary {
  final String threadId;
  final String peerUid;
  final DateTime? updatedAt;

  /// Karşı tarafın adı — thread dokümanındaki `names` haritasından gelir.
  /// Böylece arkadaş OLMAYAN biri yazdığında da isim görünür (eskiden yalnızca
  /// yerel önbellekteki adlar biliniyordu ve yabancılar "Kullanıcı" çıkıyordu).
  final String peerName;

  /// Son mesajın metni — gelen kutusunda ismin altında önizleme olarak gösterilir.
  final String lastMessage;

  /// Son mesajı kimin yazdığı (önizlemeye "Sen: " öneki koymak için).
  final String lastSenderUid;

  /// BENİM okumadığım mesaj sayısı. Karşı taraf her mesaj gönderdiğinde
  /// sunucuda artar, ben sohbeti açınca sıfırlanır (bkz. markThreadRead).
  final int unreadCount;

  const DmThreadSummary({
    required this.threadId,
    required this.peerUid,
    required this.updatedAt,
    this.peerName = '',
    this.lastMessage = '',
    this.lastSenderUid = '',
    this.unreadCount = 0,
  });
}

/// Arkadaş olmayan birine, karşı taraf yanıt verene (isteği kabul edene) kadar
/// en fazla [ChatService.kMesajIstegiSiniri] mesaj gönderilebilir. Sınır
/// aşılırsa bu istisna fırlatılır; ekran mesajı kullanıcıya gösterir.
class MesajIstegiSiniriException implements Exception {
  const MesajIstegiSiniriException();
  @override
  String toString() =>
      'Karşı taraf sana yanıt verene kadar en fazla '
      '${ChatService.kMesajIstegiSiniri} mesaj gönderebilirsin. '
      'Yanıt gelince sınır kalkar.';
}

/// Genel sohbet + DM + basit moderasyon (kötü-söz filtresi, rapor, engelleme)
/// servis katmanı.
///
/// Firebase yapılandırılmamışsa (bkz. [isFirebaseConfigured]) yazma
/// metodları [ChatNotConfiguredException] fırlatır, dinleme (stream)
/// metodları ise boş bir liste yayınlayan bir stream döner — hiçbir zaman
/// uygulamayı çökertmez.
class ChatService {
  static const String chatCollection = 'chat_messages';
  static const String reportsCollection = 'chat_reports';
  static const String dmCollection = 'dm_threads';
  static const String blockedCollection = 'blocked_users';
  /// Hafif, kişi-başı bildirim kutusu (ör. "mesajın rapor edildi" bildirimi).
  /// Tam bir bildirim merkezi DEĞİLDİR — bkz. fetchAndClearNotifications.
  /// NOT: Bu koleksiyon için Firestore güvenlik kuralı EKLENMESİ gerekir
  /// (bkz. firestore_user_notifications_rules_ADD.txt) — rapor eden kullanıcı
  /// KENDİ uid'i olmayan bir belgeye (rapor edilen kişinin bildirim kutusuna)
  /// yazmak zorunda olduğu için mevcut "isOwner" deseni yetmez. Bu kural insan
  /// onayı olmadan YAYINLANMAMALIDIR.
  static const String notificationsCollection = 'user_notifications';

  /// Çok kısa, temel bir uygunsuz kelime listesi. Gerçek bir moderasyon
  /// ekibi/servisi (ör. Cloud Functions + üçüncü parti bir moderasyon API'si)
  /// devreye alınana kadar en azından bariz küfürleri engelleyen bir güvenlik
  /// ağı. Liste kolayca genişletilebilir.
  static const List<String> _bannedWords = [
    'aptal',
    'gerizekalı',
    'salak',
    'mal',
    'yavşak',
    'piç',
    'orospu',
    'ibne',
    'amk',
    'aq',
    'siktir',
    'kahpe',
    'göt',
  ];

  bool get isConfigured => isFirebaseConfigured;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// Yasaklı kelimeler için KELİME SINIRI ile eşleşen düzenli ifadeler.
  ///
  /// ÖNEMLİ: Eskiden burada düz `lower.contains(w)` kullanılıyordu ve bu,
  /// yasaklı kelimeyi İÇİNDE barındıran masum kelimeleri de engelliyordu:
  ///   • 'mal'  →  "normal", "malzeme", "maliyet", "kamera"...
  ///   • 'göt'  →  "götür", "götüren", "götürmek"
  /// Bir KPSS uygulamasında "normal" yazamamak gerçek bir hataydı.
  ///
  /// Dart'ın `\b` sınırı ASCII tabanlı olduğu ve Türkçe harfleri (ç, ğ, ı, ö,
  /// ş, ü) kelime karakteri saymadığı için `\b` yerine ELLE bir sınır sınıfı
  /// kullanıyoruz: kelimenin önünde ve arkasında harf/rakam OLMAMALI.
  static final List<RegExp> _bannedPatterns = _bannedWords.map((w) {
    const harf = r'a-zA-Z0-9çğıöşüÇĞIİÖŞÜ';
    return RegExp('(?<![$harf])${RegExp.escape(w)}(?![$harf])',
        caseSensitive: false);
  }).toList();

  /// Verilen metnin basit kötü-söz listesine göre uygunsuz olup olmadığını
  /// döner. Yalnızca TAM KELİME eşleşmelerini yakalar.
  bool containsProfanity(String text) {
    return _bannedPatterns.any((r) => r.hasMatch(text));
  }

  /// [text] içinde geçen ilk yasaklı kelimeyi döner, yoksa null.
  String? findProfanity(String text) {
    // containsProfanity ile AYNI kuralı kullanmalı — biri alt-dize, diğeri tam
    // kelime eşleşseydi "engellendi ama sebebi bulunamadı" durumu oluşurdu.
    for (var i = 0; i < _bannedPatterns.length; i++) {
      if (_bannedPatterns[i].hasMatch(text)) return _bannedWords[i];
    }
    return null;
  }

  void _requireConfigured() {
    if (!isConfigured) throw const ChatNotConfiguredException();
  }

  // ── Genel sohbet ──

  /// Mesajı, gönderilmeden önce kötü-söz filtresinden geçirerek
  /// 'chat_messages' koleksiyonuna yazar. Filtreye takılırsa
  /// [ProfanityDetectedException] fırlatır ve mesaj GÖNDERİLMEZ.
  Future<void> sendMessage({
    required String senderUid,
    required String senderName,
    required String character,
    required String message,
  }) async {
    _requireConfigured();
    final trimmed = message.trim();
    if (trimmed.isEmpty) return;
    final bad = findProfanity(trimmed);
    if (bad != null) throw ProfanityDetectedException(bad);

    await _db.collection(chatCollection).add({
      'senderUid': senderUid,
      'senderName': senderName,
      'character': character,
      'message': trimmed,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Genel sohbet akışını en yeniden en eskiye dinler. Firebase
  /// yapılandırılmamışsa boş bir liste yayınlayan sabit bir stream döner.
  // OKUMA MALİYETİ: Ekran her açıldığında en fazla [limit] mesaj çekilir.
  // Eskiden 200'dü; her açılışta 200 okuma demekti. En son 30 mesaj çoğu
  // kullanıcı için yeterli; daha eskiyi görmek gerekirse ileride "daha fazla
  // yükle" ile artırılabilir (Firestore startAfter ile sayfalama).
  Stream<List<ChatMessage>> streamMessages({int limit = 30}) {
    if (!isConfigured) return Stream<List<ChatMessage>>.value(const []);
    return _db
        .collection(chatCollection)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(ChatMessage.fromDoc).toList());
  }

  /// Bir mesajı 'chat_reports' koleksiyonuna rapor eder (moderatörlerin
  /// incelemesi için). Mesajın kendisini silmez.
  ///
  /// [reportedUid] verildiğinde, rapor edilen kullanıcıya hafif bir uygulama
  /// içi bildirim ("Bir mesajınız incelenmek üzere bildirildi.") bırakmayı
  /// dener — bkz. [_notifyUser]. Bu adım BEST-EFFORT'tur: ilgili Firestore
  /// kuralı henüz yayınlanmadıysa (bkz. notificationsCollection yorumu)
  /// sessizce başarısız olur, raporun kendisi yine de kaydedilir.
  Future<void> reportMessage({
    required String messageId,
    required String reporterUid,
    required String reason,
    String? reportedUid,
  }) async {
    _requireConfigured();
    await _db.collection(reportsCollection).add({
      'messageId': messageId,
      'collection': chatCollection,
      'reporterUid': reporterUid,
      'reason': reason,
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'open',
    });
    if (reportedUid != null && reportedUid.isNotEmpty) {
      await _notifyUser(reportedUid, 'Bir mesajınız incelenmek üzere bildirildi.');
    }
  }

  /// [uid] kullanıcısının hafif bildirim kutusuna tek satırlık bir bildirim
  /// yazar. HİÇBİR ZAMAN istisna fırlatmaz — Firestore kuralı henüz izin
  /// vermiyorsa (yeni koleksiyon, insan onayı bekleniyor) sessizce yutar.
  Future<void> _notifyUser(String uid, String message, {String type = 'info'}) async {
    if (!isConfigured) return;
    try {
      await _db.collection(notificationsCollection).doc(uid).collection('items').add({
        'type': type,
        'message': message,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('ChatService._notifyUser başarısız (Firestore kuralı henüz yayınlanmamış olabilir): $e');
    }
  }

  /// [uid] kullanıcısının bekleyen tüm hafif bildirimlerini okur, HEPSİNİ SİLER
  /// (tam bir bildirim merkezi değil — tek seferlik "son ziyaretten beri neler
  /// oldu" gösterimi) ve mesaj metinlerini döner. Hata/izin sorunu olursa
  /// sessizce boş liste döner.
  Future<List<String>> fetchAndClearNotifications(String uid) async {
    if (!isConfigured) return const [];
    try {
      final snap = await _db.collection(notificationsCollection).doc(uid).collection('items').get();
      final messages = snap.docs
          .map((d) => d.data()['message'] as String? ?? '')
          .where((m) => m.isNotEmpty)
          .toList();
      for (final doc in snap.docs) {
        // ignore: unawaited_futures
        doc.reference.delete();
      }
      return messages;
    } catch (e) {
      debugPrint('ChatService.fetchAndClearNotifications başarısız: $e');
      return const [];
    }
  }

  /// Bir kullanıcıyı yerel/bulut engelli listesine ekler — engellenen
  /// kullanıcının mesajları istemci tarafında filtrelenebilir. Basit bir
  /// tamamlayıcı; tam bir engelleme motoru değildir.
  Future<void> blockUser({required String myUid, required String blockedUid}) async {
    _requireConfigured();
    await _db
        .collection(blockedCollection)
        .doc(myUid)
        .collection('users')
        .doc(blockedUid)
        .set({'blockedAt': FieldValue.serverTimestamp()});
  }

  Future<void> unblockUser({required String myUid, required String blockedUid}) async {
    _requireConfigured();
    await _db
        .collection(blockedCollection)
        .doc(myUid)
        .collection('users')
        .doc(blockedUid)
        .delete();
  }

  Stream<Set<String>> streamBlockedUids(String myUid) {
    if (!isConfigured) return Stream<Set<String>>.value(const {});
    return _db
        .collection(blockedCollection)
        .doc(myUid)
        .collection('users')
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.id).toSet());
  }

  // ── Kullanıcıdan kullanıcıya özel mesaj (DM) ──

  /// İki kullanıcı arasındaki DM thread kimliğini belirlenimli (deterministic)
  /// biçimde üretir: uid'ler sıralanıp birleştirilir, böylece hangi kullanıcı
  /// başlatırsa başlatsın her zaman aynı doküman yoluna yazılır/okunur.
  String threadIdFor(String uidA, String uidB) {
    final sorted = [uidA, uidB]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }

  /// Arkadaş olmayan birine, o yanıt verene kadar gönderilebilecek en fazla
  /// mesaj sayısı ("mesaj isteği" sınırı). Karşı taraf tek bir yanıt verdiği
  /// anda istek kabul edilmiş sayılır ve sınır kalkar. Arkadaşlar için sınır
  /// hiç uygulanmaz.
  static const int kMesajIstegiSiniri = 3;

  /// Özel mesaj gönderir ve thread META verisini günceller.
  ///
  /// THREAD DOKÜMANI ARTIK ŞUNLARI DA TAŞIYOR:
  ///  • names.{uid}      → görünen adlar. Karşı taraf beni hiç kaydetmemiş
  ///                       olsa da gelen kutusunda adım görünsün diye.
  ///  • lastMessage      → gelen kutusundaki son mesaj önizlemesi.
  ///  • lastSenderUid    → önizlemeye "Sen:" öneki için.
  ///  • unread.{uid}     → alıcının okunmamış sayacı (ben gönderince karşı
  ///                       tarafınki artar; o açınca sıfırlar).
  ///  • requestFrom      → sohbeti başlatan (ilk mesajı atan) kişi.
  ///  • accepted         → mesaj isteği kabul edildi mi? Alıcı YANIT VERDİĞİ
  ///                       anda true olur; taraflar arkadaşsa baştan true.
  ///
  /// MESAJ İSTEĞİ SINIRI: Taraflar arkadaş değilse ve accepted=false ise,
  /// sohbeti başlatan kişi en fazla [kMesajIstegiSiniri] mesaj gönderebilir —
  /// aşarsa [MesajIstegiSiniriException] fırlatılır. Bu, tanımadık kişilere
  /// mesaj spam'ini engeller (kullanıcı isteği).
  Future<void> sendDirectMessage({
    required String fromUid,
    required String toUid,
    required String message,
    String fromName = '',
  }) async {
    _requireConfigured();
    final trimmed = message.trim();
    if (trimmed.isEmpty) return;
    final bad = findProfanity(trimmed);
    if (bad != null) throw ProfanityDetectedException(bad);

    final threadId = threadIdFor(fromUid, toUid);
    final threadRef = _db.collection(dmCollection).doc(threadId);

    // Mevcut thread durumunu oku (yoksa null alanlarla devam edilir).
    final threadDoc = await threadRef.get();
    final data = threadDoc.data() ?? const <String, dynamic>{};
    final accepted = data['accepted'] == true;
    final requestFrom = data['requestFrom'] as String?;

    var yeniAccepted = accepted;
    var yeniRequestFrom = requestFrom;

    if (!accepted) {
      // Arkadaşlarsa istek/sınır hiç işlemez.
      final arkadasMi = await _db
          .collection(friendsCollection)
          .doc(fromUid)
          .collection('list')
          .doc(toUid)
          .get()
          .then((d) => d.exists)
          .catchError((_) => false);

      if (arkadasMi) {
        yeniAccepted = true;
      } else if (!threadDoc.exists || requestFrom == null) {
        // İlk mesaj: sohbeti ben başlatıyorum.
        yeniRequestFrom = fromUid;
      } else if (requestFrom != fromUid) {
        // Alıcı yanıt veriyor → istek KABUL edilmiş sayılır, sınır kalkar.
        yeniAccepted = true;
      } else {
        // Başlatan, kabul gelmeden mesaj atmaya devam ediyor → sınırı uygula.
        final benimkiler = (data['requestCount'] as num?)?.toInt() ?? 0;
        if (benimkiler >= kMesajIstegiSiniri) {
          throw const MesajIstegiSiniriException();
        }
      }
    }

    await threadRef.set({
      'participants': [fromUid, toUid]..sort(),
      'updatedAt': FieldValue.serverTimestamp(),
      if (fromName.isNotEmpty) 'names': {fromUid: fromName},
      'lastMessage': trimmed.length > 80 ? trimmed.substring(0, 80) : trimmed,
      'lastSenderUid': fromUid,
      // Alıcının okunmamış sayacını artır (kendi sayacıma dokunma).
      'unread': {toUid: FieldValue.increment(1)},
      'accepted': yeniAccepted,
      'requestFrom': ?yeniRequestFrom,
      // Kabul edilmemiş istekte başlatanın mesaj adedini say.
      if (!yeniAccepted && yeniRequestFrom == fromUid)
        'requestCount': FieldValue.increment(1),
    }, SetOptions(merge: true));

    await threadRef.collection('messages').add({
      'senderUid': fromUid,
      'message': trimmed,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Sohbet açıldığında BENİM okunmamış sayacımı sıfırlar (rozet ve kalın
  /// yazı kalksın). Best-effort: hata olursa sessizce geçer.
  Future<void> markThreadRead({required String myUid, required String peerUid}) async {
    if (!isConfigured) return;
    try {
      await _db.collection(dmCollection).doc(threadIdFor(myUid, peerUid)).set({
        'unread': {myUid: 0},
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('ChatService.markThreadRead başarısız: $e');
    }
  }

  /// Kullanıcının katıldığı tüm DM thread'lerini (en son güncellenen önce)
  /// dinler — 'Mesajlarım' gelen kutusu listesi için. Karşı tarafın uid'ini
  /// taşır; görünen ismi çözmek çağıran tarafın işidir (bkz.
  /// StorageService.getDmPeerNames — yerel önbellek).
  ///
  /// DÜZELTİLEN HATA — "Mesajlarım hiç açılmıyordu":
  /// Bu sorgu eskiden `.orderBy('updatedAt', descending: true)` de içeriyordu.
  /// Firestore'da `arrayContains` filtresi ile BAŞKA bir alana göre `orderBy`
  /// birleştirildiğinde BİLEŞİK İNDEKS (composite index) zorunludur. İndeks
  /// oluşturulmadığı için sorgu her seferinde `failed-precondition` ile
  /// düşüyor, stream veri yayınlamıyor ve ekran sonsuza dek dönen halkada
  /// kalıyordu.
  ///
  /// Çözüm olarak sıralamayı İSTEMCİYE aldık: bir kullanıcının DM thread'i
  /// sayısı küçüktür (onlarca), bellekte sıralamak bedava sayılır ve
  /// kurulumda unutulabilecek bir indekse bağımlılık ortadan kalkar.
  Stream<List<DmThreadSummary>> streamMyThreads(String myUid) {
    if (!isConfigured) return Stream<List<DmThreadSummary>>.value(const []);
    return _db
        .collection(dmCollection)
        .where('participants', arrayContains: myUid)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map((d) {
        final data = d.data();
        final participants = List<String>.from(data['participants'] as List? ?? const []);
        final peer = participants.firstWhere((p) => p != myUid, orElse: () => '');
        final ts = data['updatedAt'];
        final names = Map<String, dynamic>.from(data['names'] as Map? ?? const {});
        final unread = Map<String, dynamic>.from(data['unread'] as Map? ?? const {});
        return DmThreadSummary(
          threadId: d.id,
          peerUid: peer,
          updatedAt: ts is Timestamp ? ts.toDate() : null,
          peerName: (names[peer] as String?) ?? '',
          lastMessage: (data['lastMessage'] as String?) ?? '',
          lastSenderUid: (data['lastSenderUid'] as String?) ?? '',
          unreadCount: (unread[myUid] as num?)?.toInt() ?? 0,
        );
      }).toList();
      // En son güncellenen üstte. Zamanı olmayan (henüz sunucu damgası
      // işlenmemiş) thread'ler en sona düşer.
      list.sort((a, b) {
        final ax = a.updatedAt?.millisecondsSinceEpoch ?? 0;
        final bx = b.updatedAt?.millisecondsSinceEpoch ?? 0;
        return bx.compareTo(ax);
      });
      return list;
    });
  }

  // Okuma maliyeti: DM açılışında en fazla [limit] mesaj çekilir (bkz.
  // streamMessages'taki aynı gerekçe). 200 → 30.
  Stream<List<DirectMessage>> streamDirectMessages({
    required String uidA,
    required String uidB,
    int limit = 30,
  }) {
    if (!isConfigured) return Stream<List<DirectMessage>>.value(const []);
    final threadId = threadIdFor(uidA, uidB);
    return _db
        .collection(dmCollection)
        .doc(threadId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(DirectMessage.fromDoc).toList());
  }

  // ── Arkadaşlık ─────────────────────────────────────────────────────────
  //
  // VERİ MODELİ
  //   friend_requests/{gonderenUid_alanUid}
  //       fromUid, fromName, toUid, createdAt
  //       Doküman kimliği İKİ uid'den türetilir; böylece aynı kişiye ikinci bir
  //       istek göndermek yeni kayıt OLUŞTURMAZ, mevcudun üzerine yazar. İstek
  //       spam'i bu sayede veri modelinin kendisiyle engellenmiş olur.
  //
  //   friends/{uid}/list/{arkadasUid}
  //       name, since
  //       Arkadaşlık ÇİFT YÖNLÜ saklanır: kabul edildiğinde HER İKİ kullanıcının
  //       listesine de birer kayıt yazılır. Tek yönlü saklayıp "beni arkadaş
  //       ekleyenler" diye sorgulamak, koleksiyon-grubu sorgusu ve ek indeks
  //       gerektirirdi; iki küçük doküman yazmak çok daha basit.

  static const String friendRequestsCollection = 'friend_requests';
  static const String friendsCollection = 'friends';

  /// Kullanıcı ID'si (6 haneli) → uid eşlemesi. Doküman kimliği = 6 haneli kod.
  /// Alanlar: uid, name. Kullanıcılar birbirini bu kodla arayıp ekleyebilir.
  static const String userIdsCollection = 'user_ids';

  final Random _rnd = Random();

  /// İki kullanıcı için istek dokümanının kimliği. Yön ÖNEMLİDİR:
  /// "A'dan B'ye" ile "B'den A'ya" farklı kayıtlardır (ikisi de aynı anda
  /// varsa iki taraf da birbirine istek atmış demektir).
  String friendRequestId(String fromUid, String toUid) => '${fromUid}_$toUid';

  // ── 6 haneli kullanıcı ID'si ───────────────────────────────────────────
  //
  // Her kullanıcının paylaşabileceği, arkadaş eklemede kullanılan 6 haneli
  // benzersiz bir kodu vardır. Kod İKİ yerde tutulur:
  //   • user_ids/{kod}          → { uid, name }  (koddan kullanıcıya arama için)
  //   • league_scores/{uid}.kod → kod            (kullanıcının kendi kodunu
  //                                                okuyup gösterebilmesi için)
  // Kod bir kez üretilir ve league_scores'ta saklandığı için cihaz değişse de
  // aynı kalır (yeniden üretilip eski user_ids dokümanı yetim kalmaz).

  /// Kullanıcının 6 haneli kodunu döndürür; yoksa benzersiz bir tane üretip
  /// kaydeder. Hata durumunda null döner (özellik bozulmaz, sadece kod görünmez).
  Future<String?> ensureMyKod({required String uid, required String name}) async {
    if (!isConfigured) return null;
    try {
      // 1) league_scores'ta kayıtlı kod var mı?
      final profil = await _db.collection('league_scores').doc(uid).get();
      final mevcut = profil.data()?['kod'];
      if (mevcut is String && mevcut.length == 6) {
        // user_ids kaydını (ad değişmiş olabilir) tazele, best-effort.
        // ignore: unawaited_futures
        _db.collection(userIdsCollection).doc(mevcut).set(
            {'uid': uid, 'name': name}, SetOptions(merge: true));
        return mevcut;
      }

      // 2) Benzersiz 6 haneli kod üret (birkaç deneme).
      for (var deneme = 0; deneme < 8; deneme++) {
        final kod = (100000 + _rnd.nextInt(900000)).toString(); // 100000-999999
        final varMi = await _db.collection(userIdsCollection).doc(kod).get();
        if (varMi.exists) continue;
        await _db.collection(userIdsCollection).doc(kod).set({'uid': uid, 'name': name});
        await _db
            .collection('league_scores')
            .doc(uid)
            .set({'kod': kod, 'displayName': name}, SetOptions(merge: true));
        return kod;
      }
      return null;
    } catch (e) {
      debugPrint('ChatService.ensureMyKod başarısız: $e');
      return null;
    }
  }

  /// 6 haneli koda sahip kullanıcıyı bulur. Bulamazsa null döner.
  Future<({String uid, String name})?> findUserByKod(String kod) async {
    if (!isConfigured) return null;
    final temiz = kod.trim();
    if (temiz.length != 6) return null;
    try {
      final doc = await _db.collection(userIdsCollection).doc(temiz).get();
      if (!doc.exists) return null;
      final data = doc.data()!;
      final uid = data['uid'] as String?;
      if (uid == null || uid.isEmpty) return null;
      return (uid: uid, name: (data['name'] as String?) ?? 'Kullanıcı');
    } catch (e) {
      debugPrint('ChatService.findUserByKod başarısız: $e');
      return null;
    }
  }

  /// 6 haneli kodla arkadaşlık isteği gönderir. Kullanıcıya gösterilecek
  /// Türkçe sonucu döndürür. Kod bulunamazsa uyarır.
  Future<String> sendFriendRequestByKod({
    required String myUid,
    required String myName,
    required String kod,
  }) async {
    _requireConfigured();
    final hedef = await findUserByKod(kod);
    if (hedef == null) {
      return 'Bu ID\'ye sahip bir kullanıcı bulunamadı. Kodu kontrol et.';
    }
    return sendFriendRequest(
      fromUid: myUid,
      fromName: myName,
      toUid: hedef.uid,
      toName: hedef.name,
    );
  }

  /// Bir KULLANICIYI (belirli bir mesajı değil) rapor eder — arkadaş/sohbet
  /// menüsündeki "Şikayet Et" için. chat_reports koleksiyonuna yazar.
  Future<void> reportUser({
    required String reporterUid,
    required String reportedUid,
    String reason = 'kullanici_sikayet',
  }) async {
    _requireConfigured();
    await _db.collection(reportsCollection).add({
      'reportedUid': reportedUid,
      'reporterUid': reporterUid,
      'reason': reason,
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'open',
    });
  }

  /// Arkadaşlık isteği gönderir.
  ///
  /// Kendine istek göndermeyi ve ZATEN arkadaş olunan kişiye tekrar istek
  /// göndermeyi engeller. Karşı taraf bize daha önce istek göndermişse istek
  /// oluşturmak yerine arkadaşlığı DOĞRUDAN KURAR — "iki kişi aynı anda
  /// birbirine istek attı ama ikisi de bekliyor" gibi bir çıkmaz oluşmasın.
  ///
  /// Dönen değer kullanıcıya gösterilecek Türkçe sonuç mesajıdır.
  Future<String> sendFriendRequest({
    required String fromUid,
    required String fromName,
    required String toUid,
    required String toName,
  }) async {
    _requireConfigured();
    if (fromUid == toUid) return 'Kendine arkadaşlık isteği gönderemezsin.';

    // Zaten arkadaş mıyız?
    final mevcut = await _db
        .collection(friendsCollection)
        .doc(fromUid)
        .collection('list')
        .doc(toUid)
        .get();
    if (mevcut.exists) return '$toName zaten arkadaşın.';

    // Karşı taraf bana istek göndermiş mi? Göndermişse bu "kabul" demektir.
    final tersIstek = await _db
        .collection(friendRequestsCollection)
        .doc(friendRequestId(toUid, fromUid))
        .get();
    if (tersIstek.exists) {
      await acceptFriendRequest(
        myUid: fromUid,
        myName: fromName,
        fromUid: toUid,
        fromName: toName,
      );
      return '$toName ile artık arkadaşsınız!';
    }

    await _db
        .collection(friendRequestsCollection)
        .doc(friendRequestId(fromUid, toUid))
        .set({
      'fromUid': fromUid,
      'fromName': fromName,
      'toUid': toUid,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Karşı tarafa hafif bildirim bırak (best-effort, hata yutulur).
    await _notifyUser(toUid, '$fromName sana arkadaşlık isteği gönderdi.');
    return '$toName kişisine arkadaşlık isteği gönderildi.';
  }

  /// Gelen bir isteği kabul eder: iki tarafın listesine de kayıt yazar, sonra
  /// isteği siler.
  ///
  /// SIRALAMA ÖNEMLİ — istek dokümanı EN SONDA silinir. Güvenlik kuralı,
  /// "karşı tarafın listesine kendimi ekleme" iznini tam olarak o isteğin
  /// VARLIĞINA bakarak veriyor; önce silseydik ikinci yazma reddedilir ve
  /// arkadaşlık tek taraflı kalırdı.
  Future<void> acceptFriendRequest({
    required String myUid,
    required String myName,
    required String fromUid,
    required String fromName,
  }) async {
    _requireConfigured();
    final now = FieldValue.serverTimestamp();

    // 1) Kendi listeme karşı tarafı ekle.
    await _db
        .collection(friendsCollection)
        .doc(myUid)
        .collection('list')
        .doc(fromUid)
        .set({'name': fromName, 'since': now});

    // 2) Karşı tarafın listesine KENDİMİ ekle.
    await _db
        .collection(friendsCollection)
        .doc(fromUid)
        .collection('list')
        .doc(myUid)
        .set({'name': myName, 'since': now});

    // 3) İsteği kaldır.
    await _db
        .collection(friendRequestsCollection)
        .doc(friendRequestId(fromUid, myUid))
        .delete();

    await _notifyUser(fromUid, '$myName arkadaşlık isteğini kabul etti.');
  }

  /// Gelen bir isteği reddeder (yalnızca istek dokümanını siler; karşı tarafa
  /// bildirim GÖNDERİLMEZ — reddedildiğini bildirmek gereksiz bir kırgınlık
  /// kaynağı ve tekrar istek göndermeye davet olurdu).
  Future<void> rejectFriendRequest({required String myUid, required String fromUid}) async {
    _requireConfigured();
    await _db
        .collection(friendRequestsCollection)
        .doc(friendRequestId(fromUid, myUid))
        .delete();
  }

  /// Arkadaşlıktan çıkarır — İKİ taraftaki kaydı da siler, yoksa karşı tarafta
  /// "arkadaş" görünmeye devam ederdi.
  Future<void> removeFriend({required String myUid, required String friendUid}) async {
    _requireConfigured();
    await _db.collection(friendsCollection).doc(myUid).collection('list').doc(friendUid).delete();
    await _db.collection(friendsCollection).doc(friendUid).collection('list').doc(myUid).delete();
  }

  /// Bana gelen bekleyen istekler.
  ///
  /// `orderBy` BİLEREK KULLANILMADI: eşitlik filtresi + farklı alana göre
  /// sıralama bileşik indeks ister (bkz. streamMyThreads'teki aynı tuzak).
  /// Sıralamayı istemcide yapıyoruz.
  Stream<List<FriendRequest>> streamIncomingRequests(String myUid) {
    if (!isConfigured) return Stream<List<FriendRequest>>.value(const []);
    return _db
        .collection(friendRequestsCollection)
        .where('toUid', isEqualTo: myUid)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map(FriendRequest.fromDoc).toList();
      list.sort((a, b) {
        final ax = a.createdAt?.millisecondsSinceEpoch ?? 0;
        final bx = b.createdAt?.millisecondsSinceEpoch ?? 0;
        return bx.compareTo(ax);
      });
      return list;
    });
  }

  /// Arkadaş listem (ada göre sıralı).
  Stream<List<Friend>> streamFriends(String myUid) {
    if (!isConfigured) return Stream<List<Friend>>.value(const []);
    return _db
        .collection(friendsCollection)
        .doc(myUid)
        .collection('list')
        .snapshots()
        .map((snap) {
      final list = snap.docs.map(Friend.fromDoc).toList();
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return list;
    });
  }

  /// Bir DM mesajını rapor eder — genel sohbet raporlarıyla aynı
  /// 'chat_reports' koleksiyonuna, hangi thread'e ait olduğu bilgisiyle yazar.
  Future<void> reportDirectMessage({
    required String uidA,
    required String uidB,
    required String messageId,
    required String reporterUid,
    required String reason,
  }) async {
    _requireConfigured();
    await _db.collection(reportsCollection).add({
      'messageId': messageId,
      'collection': '$dmCollection/${threadIdFor(uidA, uidB)}/messages',
      'reporterUid': reporterUid,
      'reason': reason,
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'open',
    });
  }
}
