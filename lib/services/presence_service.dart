import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../firebase_bootstrap.dart';
import 'storage_service.dart';

/// Yönetici paneli için "canlılık" kaydı + uzaktan premium kontrolü.
///
/// İKİ iş yapar:
///  1. [bildir] — giriş yapmış kullanıcının `user_status/{uid}` dokümanına
///     lastSeen (sunucu saati), ad, e-posta ve premium bilgisini yazar.
///     Yönetici paneli bu koleksiyondan toplam/günlük/haftalık/aylık ve
///     "şu an online" sayılarını, kullanıcı listesini üretir. Yazma en fazla
///     2 dakikada bir yapılır (okuma/yazma maliyeti şişmesin).
///  2. [premiumKontrol] — yöneticinin panelden verdiği premium'u uygular:
///     `premium_grants/{uid}` dokümanı premium:true ise yerel plan premium
///     yapılır. Panelden geri alınırsa (premium:false) yalnızca PANEL
///     ÜZERİNDEN verilmiş premium geri alınır — mağazadan SATIN ALINMIŞ
///     premium'a dokunulmaz (yerel 'premiumKaynak' işaretiyle ayrılır).
class PresenceService {
  PresenceService._();
  static final PresenceService instance = PresenceService._();

  static const String statusCollection = 'user_status';
  static const String grantsCollection = 'premium_grants';

  DateTime? _sonBildirim;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// Kullanıcının canlılık kaydını yazar (en fazla 2 dakikada bir).
  /// Anonim oturumlar YAZILMAZ — panelde gerçek hesaplar görünsün.
  Future<void> bildir(StorageService storage) async {
    if (!isFirebaseConfigured) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return;

    final simdi = DateTime.now();
    if (_sonBildirim != null &&
        simdi.difference(_sonBildirim!) < const Duration(minutes: 2)) {
      return;
    }
    _sonBildirim = simdi;

    try {
      final ad = (user.displayName?.trim().isNotEmpty ?? false)
          ? user.displayName!.trim()
          : (storage.getUserName().isNotEmpty
              ? storage.getUserName()
              : (user.email?.split('@').first ?? 'Kullanıcı'));
      await _db.collection(statusCollection).doc(user.uid).set({
        'name': ad,
        'email': user.email ?? '',
        'premium': storage.isPremiumUser(),
        'lastSeen': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('PresenceService.bildir başarısız: $e');
    }
  }

  /// Panelden verilen/geri alınan premium'u uygular. Best-effort.
  Future<void> premiumKontrol(StorageService storage) async {
    if (!isFirebaseConfigured) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return;
    try {
      final doc = await _db.collection(grantsCollection).doc(user.uid).get();
      final grantPremium = doc.data()?['premium'] == true;
      final ayarlar = storage.getSettings();
      final kaynakGrant = ayarlar['premiumKaynak'] == 'grant';

      if (grantPremium && !storage.isPremiumUser()) {
        // Yönetici premium vermiş — uygula ve kaynağını işaretle.
        await storage.saveSettings({'premiumKaynak': 'grant'});
        await storage.setUserPlan('premium');
        debugPrint('PresenceService: panel üzerinden premium uygulandı.');
      } else if (!grantPremium && storage.isPremiumUser() && kaynakGrant) {
        // Yalnızca PANELDEN verilmiş premium geri alınır; satın alınmışa
        // dokunulmaz (kaynak işareti 'grant' değilse buraya girilmez).
        await storage.saveSettings({'premiumKaynak': ''});
        await storage.setUserPlan('free');
        debugPrint('PresenceService: panel premium\'u geri alındı.');
      }
    } catch (e) {
      debugPrint('PresenceService.premiumKontrol başarısız: $e');
    }
  }
}
