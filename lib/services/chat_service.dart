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

/// 'Mesajlarım' gelen kutusunda gösterilen bir DM thread'inin özeti.
class DmThreadSummary {
  final String threadId;
  final String peerUid;
  final DateTime? updatedAt;
  const DmThreadSummary({required this.threadId, required this.peerUid, required this.updatedAt});
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
  Stream<List<ChatMessage>> streamMessages({int limit = 200}) {
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

  Future<void> sendDirectMessage({
    required String fromUid,
    required String toUid,
    required String message,
  }) async {
    _requireConfigured();
    final trimmed = message.trim();
    if (trimmed.isEmpty) return;
    final bad = findProfanity(trimmed);
    if (bad != null) throw ProfanityDetectedException(bad);

    final threadId = threadIdFor(fromUid, toUid);
    final threadRef = _db.collection(dmCollection).doc(threadId);
    await threadRef.set({
      'participants': [fromUid, toUid]..sort(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await threadRef.collection('messages').add({
      'senderUid': fromUid,
      'message': trimmed,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Kullanıcının katıldığı tüm DM thread'lerini (en son güncellenen önce)
  /// dinler — 'Mesajlarım' gelen kutusu listesi için. Karşı tarafın uid'ini
  /// taşır; görünen ismi çözmek çağıran tarafın işidir (bkz.
  /// StorageService.getDmPeerNames — yerel önbellek).
  Stream<List<DmThreadSummary>> streamMyThreads(String myUid) {
    if (!isConfigured) return Stream<List<DmThreadSummary>>.value(const []);
    return _db
        .collection(dmCollection)
        .where('participants', arrayContains: myUid)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) {
              final participants = List<String>.from(d.data()['participants'] as List? ?? const []);
              final peer = participants.firstWhere((p) => p != myUid, orElse: () => '');
              final ts = d.data()['updatedAt'];
              return DmThreadSummary(
                threadId: d.id,
                peerUid: peer,
                updatedAt: ts is Timestamp ? ts.toDate() : null,
              );
            }).toList());
  }

  Stream<List<DirectMessage>> streamDirectMessages({
    required String uidA,
    required String uidB,
    int limit = 200,
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
