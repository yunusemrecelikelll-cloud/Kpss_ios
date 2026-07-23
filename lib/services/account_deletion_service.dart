import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../firebase_bootstrap.dart';
import 'auth_service.dart';
import 'chat_service.dart';
import 'cloud_sync_service.dart';
import 'duel_service.dart';
import 'league_service.dart';
import 'storage_service.dart';

/// Hesabın Firebase Auth kaydını silmek için kullanıcının YAKIN ZAMANDA giriş
/// yapmış olması gerekir (Firebase güvenlik kuralı). Oturum eskiyse
/// `firebase_auth` `requires-recent-login` hatası döndürür; bu istisna UI'a
/// "önce tekrar giriş yaptır, sonra tekrar dene" demek için fırlatılır.
class ReauthRequiredException implements Exception {
  const ReauthRequiredException();
  @override
  String toString() =>
      'Güvenliğin için hesabını silmeden önce tekrar giriş yapman gerekiyor.';
}

/// Silme sırasında oluşan, kullanıcıya gösterilebilir hata.
class AccountDeletionException implements Exception {
  final String message;
  const AccountDeletionException(this.message);
  @override
  String toString() => message;
}

/// "Hesabımı Sil" akışını yürüten servis.
///
/// App Store İnceleme Kuralı 5.1.1(v): hesap oluşturmayı destekleyen
/// uygulamalar, hesabın UYGULAMA İÇİNDEN silinmesini de sunmak zorundadır.
///
/// SIRALAMA ÖNEMLİ: Önce Firestore verisi, EN SON Auth kaydı silinir. Çünkü
/// Auth kaydı silinince kullanıcı oturumu kapanır ve güvenlik kuralları
/// gereği artık kendi dokümanlarına yazamaz/silemez — sıra ters olsaydı
/// veriler yetim kalırdı.
///
/// Her adım kendi try/catch'i içindedir: bir koleksiyon silinemezse (izin,
/// ağ, kural) süreç durmaz, kalanlar silinmeye devam eder. Amaç, kullanıcının
/// "sil" dedikten sonra yarı yolda takılıp hesabının durmaya devam etmesini
/// önlemek.
class AccountDeletionService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Firestore tek seferde en fazla 500 işlem alır; güvenli bir paylaşımla
  /// parça parça siliyoruz.
  static const int _batchLimit = 400;

  /// Verilen dokümanları parçalara bölerek siler.
  Future<void> _deleteDocs(List<DocumentReference<Object?>> refs) async {
    for (var i = 0; i < refs.length; i += _batchLimit) {
      final dilim = refs.sublist(
        i,
        (i + _batchLimit) > refs.length ? refs.length : i + _batchLimit,
      );
      final batch = _db.batch();
      for (final ref in dilim) {
        batch.delete(ref);
      }
      await batch.commit();
    }
  }

  /// Bir adımı çalıştırır; hata olursa yutar ve loglar (süreç devam etsin).
  Future<void> _adim(String ad, Future<void> Function() islem) async {
    try {
      await islem();
    } catch (e) {
      debugPrint('[AccountDeletion] "$ad" adımı atlandı: $e');
    }
  }

  /// Kullanıcının buluttaki TÜM kişisel verisini siler.
  ///
  /// Auth kaydına DOKUNMAZ — onu [deleteAccount] en sonda siler.
  Future<void> deleteCloudData(String uid) async {
    // 1) Herkese açık profil/lig özeti — 'league_scores/{uid}'
    await _adim('league_scores', () async {
      await _db.collection(LeagueService.scoresCollection).doc(uid).delete();
    });

    // 2) Bulut yedeği — 'cloud_backups/{uid}'
    await _adim('cloud_backups', () async {
      await _db.collection(CloudSyncService.backupCollection).doc(uid).delete();
    });

    // 3) Bildirimler — 'user_notifications/{uid}/items/*' + üst doküman
    await _adim('user_notifications', () async {
      final items = await _db
          .collection(ChatService.notificationsCollection)
          .doc(uid)
          .collection('items')
          .get();
      await _deleteDocs(items.docs.map((d) => d.reference).toList());
      await _db.collection(ChatService.notificationsCollection).doc(uid).delete();
    });

    // 4) Engellenen kullanıcı listesi — 'blocked_users/{uid}/users/*'
    await _adim('blocked_users', () async {
      final users = await _db
          .collection(ChatService.blockedCollection)
          .doc(uid)
          .collection('users')
          .get();
      await _deleteDocs(users.docs.map((d) => d.reference).toList());
      await _db.collection(ChatService.blockedCollection).doc(uid).delete();
    });

    // 5) Genel sohbette yazdığı mesajlar
    await _adim('chat_messages', () async {
      final snap = await _db
          .collection(ChatService.chatCollection)
          .where('senderUid', isEqualTo: uid)
          .get();
      await _deleteDocs(snap.docs.map((d) => d.reference).toList());
    });

    // 6) Özel mesaj (DM) konuşmaları — içindeki mesajlarla birlikte.
    //    Thread iki kişiliktir; kullanıcı hesabını silince konuşmanın tamamı
    //    kaldırılır (karşı tarafta da yarım bir sohbet kalmasın).
    await _adim('dm_threads', () async {
      final threads = await _db
          .collection(ChatService.dmCollection)
          .where('participants', arrayContains: uid)
          .get();
      for (final t in threads.docs) {
        final msgs = await t.reference.collection('messages').get();
        await _deleteDocs(msgs.docs.map((d) => d.reference).toList());
      }
      await _deleteDocs(threads.docs.map((d) => d.reference).toList());
    });

    // 7) Kendi gönderdiği moderasyon raporları
    await _adim('chat_reports', () async {
      final snap = await _db
          .collection(ChatService.reportsCollection)
          .where('reporterUid', isEqualTo: uid)
          .get();
      await _deleteDocs(snap.docs.map((d) => d.reference).toList());
    });

    // 8) Düello odaları — iki ayrı durum var:
    //    a) KENDİ AÇTIĞI odalar: oda tamamen silinir (host gidince oda zaten
    //       anlamsız kalır).
    //    b) BAŞKASININ odasına katıldığı kayıtlar: odanın kendisi başkasına
    //       ait olduğu için silinmez, sadece kullanıcının `players` girdisi ve
    //       `playerUids` dizisindeki uid'i kaldırılır.
    //
    //    (b) ancak odalarda sorgulanabilir bir `playerUids` DİZİSİ olduğu için
    //    mümkün — `players` bir harita alanı olduğundan tek başına
    //    "beni içeren odalar" diye sorgulanamıyordu (bkz. DuelService).
    await _adim('duel_rooms (host)', () async {
      final rooms = await _db
          .collection(DuelService.roomsCollection)
          .where('hostUid', isEqualTo: uid)
          .get();
      await _deleteDocs(rooms.docs.map((d) => d.reference).toList());
    });

    await _adim('duel_rooms (katılımcı)', () async {
      final rooms = await _db
          .collection(DuelService.roomsCollection)
          .where('playerUids', arrayContains: uid)
          .get();
      // Host olduklarını yukarıda zaten sildik; kalanlardan sadece kendi
      // girdimizi çıkarıyoruz.
      final guncellenecek = rooms.docs
          .where((d) => (d.data()['hostUid'] as String?) != uid)
          .toList();
      for (var i = 0; i < guncellenecek.length; i += _batchLimit) {
        final dilim = guncellenecek.sublist(
          i,
          (i + _batchLimit) > guncellenecek.length
              ? guncellenecek.length
              : i + _batchLimit,
        );
        final batch = _db.batch();
        for (final d in dilim) {
          batch.update(d.reference, {
            'players.$uid': FieldValue.delete(),
            'playerUids': FieldValue.arrayRemove([uid]),
          });
        }
        await batch.commit();
      }
    });

    // 9) Arkadaşlıklar — ÇİFT YÖNLÜ temizlik.
    //    Arkadaşlık iki dokümanda birden saklanır (bkz. ChatService). Yalnızca
    //    kendi listemizi silmek yetmez: karşı tarafın listesinde silinmiş
    //    hesabın adı "arkadaşın" olarak durmaya devam ederdi.
    await _adim('friends', () async {
      final benim = await _db
          .collection(ChatService.friendsCollection)
          .doc(uid)
          .collection('list')
          .get();
      // Önce karşı tarafların listesinden KENDİMİZİ sil (kural buna izin
      // veriyor: friendUid == kendi uid'im).
      final karsiTaraf = benim.docs
          .map((d) => _db
              .collection(ChatService.friendsCollection)
              .doc(d.id)
              .collection('list')
              .doc(uid))
          .toList();
      await _deleteDocs(karsiTaraf);
      // Sonra kendi listemizi tamamen kaldır.
      await _deleteDocs(benim.docs.map((d) => d.reference).toList());
    });

    // 10) Bekleyen arkadaşlık istekleri — hem gönderdiklerimiz hem aldıklarımız.
    //     Silinmezse karşı tarafın "İstekler" bölümünde artık var olmayan bir
    //     hesaptan gelen istek asılı kalırdı.
    await _adim('friend_requests (giden)', () async {
      final snap = await _db
          .collection(ChatService.friendRequestsCollection)
          .where('fromUid', isEqualTo: uid)
          .get();
      await _deleteDocs(snap.docs.map((d) => d.reference).toList());
    });

    await _adim('friend_requests (gelen)', () async {
      final snap = await _db
          .collection(ChatService.friendRequestsCollection)
          .where('toUid', isEqualTo: uid)
          .get();
      await _deleteDocs(snap.docs.map((d) => d.reference).toList());
    });

    // 10.3) Canlılık kaydı — 'user_status/{uid}' (yönetici paneli verisi).
    await _adim('user_status', () async {
      await _db.collection('user_status').doc(uid).delete();
    });

    // 10.4) Panelden verilmiş premium kaydı — 'premium_grants/{uid}'.
    await _adim('premium_grants', () async {
      await _db.collection('premium_grants').doc(uid).delete();
    });

    // 10.5) 6 haneli kullanıcı ID kaydı — 'user_ids/{kod}'
    //       Silinmezse kod kalıcı olarak rezerve kalır ve başka biri o kodu
    //       arayınca artık var olmayan bir hesaba istek göndermeye çalışır.
    await _adim('user_ids', () async {
      final snap = await _db
          .collection(ChatService.userIdsCollection)
          .where('uid', isEqualTo: uid)
          .get();
      await _deleteDocs(snap.docs.map((d) => d.reference).toList());
    });

    // 11) Kullanıcı adı rezervasyonu — 'usernames/{kullaniciAdiKucukHarf}'
    //
    //    Bu adım ATLANIRSA kullanıcı adı SONSUZA DEK rezerve kalır: hesap
    //    silinmiş olmasına rağmen o adı bir daha kimse alamaz ve kullanıcının
    //    kendisi bile aynı adla tekrar kayıt olamaz.
    //
    //    Doküman kimliğini `displayName`'den TÜRETMİYORUZ. Kullanıcı görünen
    //    adını sonradan değiştirmiş olabilir; o durumda türetilen anahtar
    //    yanlış (ya da var olmayan) bir dokümanı hedefler ve silme sessizce
    //    boşa giderdi. Bunun yerine sahipliğin TEK doğru kaynağı olan `uid`
    //    alanı üzerinden sorguluyoruz — kurallar da silmeyi tam olarak buna
    //    (resource.data.uid == request.auth.uid) göre veriyor.
    await _adim('usernames', () async {
      final snap = await _db
          .collection(kUsernamesCollection)
          .where('uid', isEqualTo: uid)
          .get();
      await _deleteDocs(snap.docs.map((d) => d.reference).toList());
    });
  }

  /// Hesabı tamamen siler: önce buluttaki veri, sonra Auth kaydı, en son
  /// cihazdaki yerel veri.
  ///
  /// Firebase yapılandırılmamışsa ya da kullanıcı giriş yapmamışsa yalnızca
  /// yerel veri temizlenir (çevrimdışı kullanıcı için "hesabı sil" pratikte
  /// budur).
  ///
  /// [ReauthRequiredException] fırlatırsa: UI kullanıcıyı yeniden giriş
  /// yaptırıp bu metodu TEKRAR çağırmalıdır. Bu durumda bulut verisi zaten
  /// silinmiş olur, ikinci çağrıda kalan Auth kaydı silinir.
  Future<void> deleteAccount(StorageService storage) async {
    final user = isFirebaseConfigured ? FirebaseAuth.instance.currentUser : null;

    if (user != null) {
      await deleteCloudData(user.uid);

      try {
        await user.delete();
      } on FirebaseAuthException catch (e) {
        if (e.code == 'requires-recent-login') {
          // Bulut verisi silindi ama Auth kaydı duruyor — çağıran tarafın
          // yeniden giriş yaptırıp tekrar denemesi gerekiyor.
          throw const ReauthRequiredException();
        }
        throw AccountDeletionException(
          'Hesap silinemedi: ${e.message ?? e.code}',
        );
      }
    }

    await _clearLocal(storage);
  }

  /// Cihazdaki TÜM veriyi sıfırlar — profiller, istatistikler, rozetler,
  /// ayarlar ve PREMIUM dahil (kullanıcı isteği: "hesabı sil yapınca bütün
  /// premium ve istatistikler sıfırlansın").
  ///
  /// ESKİDEN yalnızca aktif profilin anahtarları siliniyordu; profil adı
  /// boşsa ya da premium başka bir kapsamda kalmışsa artıklar kalabiliyordu.
  /// Artık uygulama ilk kurulmuş gibi tertemiz başlar.
  Future<void> _clearLocal(StorageService storage) async {
    await storage.tumVerileriSil();
  }
}
