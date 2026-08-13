import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../firebase_bootstrap.dart';
import 'chat_service.dart';
import 'cloud_sync_service.dart';
import 'storage_service.dart';

/// Davet ödülü sonuçları (UI mesajı için).
enum DavetSonuc {
  basari, // ödül talebi başarıyla kaydedildi (iki tarafa da 1 gün premium)
  koddYok, // ortada bekleyen kod yok
  gecersizKod, // kod bir kullanıcıya ait değil
  kendiKodun, // kendi kodunu kullanmaya çalıştı
  cihazKullanildi, // bu cihazda davet kodu zaten kullanılmış
  hesapKullanildi, // bu hesap zaten bir davet kullanmış
  hesapEski, // hesap YENİ değil (daha önce oluşturulmuş) — davet geçersiz
  hata, // ağ/başka hata
}

/// ───────────────────────────────────────────────────────────────────────────
/// Davet (referans) sistemi — kullanıcı isteği
/// ───────────────────────────────────────────────────────────────────────────
///
/// ÖDÜL: Davet EDEN ve davet EDİLEN kişiye **1'er gün premium** verilir. Davet
/// eden için süre BİRİKİR (3 kişi kayıt olduysa +3 gün). Ödül YALNIZCA davet
/// edilen kişi UYGULAMAYI YENİ HESAPLA kurup giriş yaptığında verilir; daha önce
/// hesabı olan kullanıcılar için geçerli değildir.
///
/// SAHTECİLİK KORUMASI (Cloud Functions olmadan, en güçlü istemci-tarafı):
///   1. CİHAZ TEKİLLİĞİ: Her fiziksel cihaz (iOS identifierForVendor / Android
///      ID) bir davet kodunu YALNIZCA 1 KEZ kullanabilir. `invite_claims/{cihaz}`
///      dokümanı bir kez yazılır; ikinci deneme reddedilir. Böylece "aynı
///      cihazda farklı hesapla tekrar tekrar davet" kapatılır.
///   2. HESAP TEKİLLİĞİ: Bir hesap yalnızca 1 davet kullanabilir (yerel bayrak +
///      cihaz kaydı).
///   3. KENDİ KODUN yasak; geçersiz kod yasak.
///   4. Ödül, davet EDENİN gelen-kutusuna (`invite_rewards/{eden}/items`)
///      yazılır ve eden kişinin uygulaması açılışta uygular. Firestore kuralı
///      `fromUid == auth.uid && fromUid != owner` şartıyla KENDİNE ödül yazmayı
///      engeller.
///
/// SINIR (dürüst not): Modifiye edilmiş bir istemci sahte cihaz kimliği
/// üretebilir; TAM koruma sunucu (Cloud Functions + cihaz attestation) ister.
/// Yukarıdaki kombinasyon normal kullanıcı için tüm bariz açıkları kapatır.
class InviteService {
  InviteService();

  static const int kOdulPremiumGun = 1; // davet başına +1 gün premium (iki tarafa)

  static const String _claimsCollection = 'invite_claims';
  static const String _rewardsCollection = 'invite_rewards';

  final ChatService _chat = ChatService();

  bool get _configured => isFirebaseConfigured;
  FirebaseFirestore get _db => FirebaseFirestore.instance;
  String? get _uid => _configured ? FirebaseAuth.instance.currentUser?.uid : null;

  /// Kararlı cihaz kimliği (iOS IDFV / Android ID). Alınamazsa null.
  Future<String?> cihazKimligi() async {
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isIOS) {
        final ios = await info.iosInfo;
        return ios.identifierForVendor;
      } else if (Platform.isAndroid) {
        final and = await info.androidInfo;
        return and.id; // ANDROID_ID
      }
    } catch (e) {
      debugPrint('InviteService.cihazKimligi hatası: $e');
    }
    return null;
  }

  /// Kullanıcının PAYLAŞACAĞI kendi davet kodu (6 haneli — mevcut kullanıcı
  /// kodu). Giriş yapmış olmayı gerektirir.
  Future<String?> kendiDavetKodum({required String ad}) async {
    final uid = _uid;
    if (uid == null) return null;
    return _chat.ensureMyKod(uid: uid, name: ad);
  }

  /// Girilen kodun geçerli (bir kullanıcıya ait) olup olmadığını kontrol eder;
  /// geçerliyse o kişinin adını döndürür (giriş EKRANINDA "kontrol et" için).
  Future<({String uid, String name})?> koduDogrula(String kod) =>
      _chat.findUserByKod(kod);

  /// Bekleyen davet kodunu (giriş öncesi girilen) giriş SONRASI uygular:
  /// yeni-hesap + cihaz/hesap tekilliğini kontrol eder, davet EDİLENE 1 gün
  /// premium verir ve davet EDENİN kutusuna 1 günlük ödül yazar.
  ///
  /// [yeniHesap]: bu giriş YENİ bir hesap mı (daha önce oluşturulmamış). false
  /// ise davet geçersizdir (kullanıcı isteği: eski hesaplar davet kullanamaz;
  /// hesabı silip tekrar giriş yaparak premium farm'lanamaz — ayrıca cihaz
  /// tekilliği de bunu engeller).
  Future<DavetSonuc> bekleyenDavetiUygula(
    StorageService storage, {
    required bool yeniHesap,
  }) async {
    final kod = storage.getPendingInviteCode().trim();
    if (kod.isEmpty) return DavetSonuc.koddYok;
    if (!_configured) return DavetSonuc.hata;
    final uid = _uid;
    if (uid == null) return DavetSonuc.hata;

    // YENİ HESAP DEĞİLSE (daha önce oluşturulmuş): davet geçersiz.
    if (!yeniHesap) {
      await storage.clearPendingInviteCode();
      return DavetSonuc.hesapEski;
    }

    // Hesap zaten bir davet kullanmışsa (yerel hızlı kontrol).
    if (storage.getInviteRedeemed()) {
      await storage.clearPendingInviteCode();
      return DavetSonuc.hesapKullanildi;
    }

    try {
      final eden = await _chat.findUserByKod(kod);
      if (eden == null) {
        await storage.clearPendingInviteCode();
        return DavetSonuc.gecersizKod;
      }
      if (eden.uid == uid) {
        await storage.clearPendingInviteCode();
        return DavetSonuc.kendiKodun;
      }

      final cihaz = await cihazKimligi();
      if (cihaz == null || cihaz.isEmpty) {
        // Cihaz kimliği alınamadıysa sahtecilik koruması uygulanamaz → güvenli
        // tarafta kal, ödül verme (kod beklemede kalmasın diye temizle).
        await storage.clearPendingInviteCode();
        return DavetSonuc.hata;
      }

      // CİHAZ TEKİLLİĞİ: invite_claims/{cihaz} transaction ile 1 kez yazılır.
      final claimRef = _db.collection(_claimsCollection).doc(cihaz);
      final cihazMusait = await _db.runTransaction<bool>((tx) async {
        final snap = await tx.get(claimRef);
        if (snap.exists) return false; // bu cihaz zaten kullanmış
        tx.set(claimRef, {
          'inviterUid': eden.uid,
          'claimerUid': uid,
          'kod': kod,
          'at': FieldValue.serverTimestamp(),
        });
        return true;
      });

      if (!cihazMusait) {
        await storage.clearPendingInviteCode();
        await storage.setInviteRedeemed(true); // bu cihazda bir daha denemesin
        return DavetSonuc.cihazKullanildi;
      }

      // Ödülü davet EDENİN gelen kutusuna yaz (eden açılışta uygular; her öğe
      // +1 gün → süre birikir).
      await _db
          .collection(_rewardsCollection)
          .doc(eden.uid)
          .collection('items')
          .add({
        'fromUid': uid,
        'deviceId': cihaz,
        'premiumGun': kOdulPremiumGun,
        'at': FieldValue.serverTimestamp(),
      });

      // Davet EDİLENE (bu kullanıcıya) de HEMEN 1 gün premium ver.
      await storage.addBonusPremiumDays(kOdulPremiumGun);
      await storage.setInviteRedeemed(true);
      await storage.clearPendingInviteCode();
      // ignore: unawaited_futures
      CloudSyncService().syncUp(storage);
      return DavetSonuc.basari;
    } catch (e) {
      debugPrint('InviteService.bekleyenDavetiUygula hatası: $e');
      return DavetSonuc.hata;
    }
  }

  /// Davet EDEN için: kendi ödül gelen-kutusundaki (`invite_rewards/{ben}/items`)
  /// tüm ödülleri uygular (her biri +1 gün premium → süre BİRİKİR), öğeleri
  /// siler ve UYGULANAN ödül sayısını (kaç kişinin kayıt olduğunu) döndürür.
  /// Açılışta çağrılır.
  Future<int> gelenOdulleriUygula(StorageService storage) async {
    final uid = _uid;
    if (uid == null || !_configured) return 0;
    try {
      final col =
          _db.collection(_rewardsCollection).doc(uid).collection('items');
      final snap = await col.get();
      if (snap.docs.isEmpty) return 0;
      var uygulanan = 0;
      for (final doc in snap.docs) {
        final data = doc.data();
        final gun = ((data['premiumGun'] as num?) ?? kOdulPremiumGun).toInt();
        await storage.addBonusPremiumDays(gun);
        await storage.addInviteEarned();
        try {
          await doc.reference.delete();
        } catch (_) {/* silme başarısızsa çift ödül olmasın diye yut */}
        uygulanan++;
      }
      // Kazanılan hak/premium buluta da yansısın.
      // ignore: unawaited_futures
      CloudSyncService().syncUp(storage);
      return uygulanan;
    } catch (e) {
      debugPrint('InviteService.gelenOdulleriUygula hatası: $e');
      return 0;
    }
  }
}
