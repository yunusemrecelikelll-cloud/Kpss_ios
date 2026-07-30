import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../firebase_bootstrap.dart';
import 'in_app_notice_service.dart';
import 'storage_service.dart';

/// SUNUCUSUZ (Spark) yönetici duyurusu.
///
/// Yönetici paneli (ayrı web uygulaması) `duyurular/aktif` dokümanını yazar;
/// uygulama HER AÇILIŞTA bu tek dokümanı okur (1 okuma — Spark dostu) ve yeni
/// bir duyuru varsa ekranın üstünden kayan afişle bir kez gösterir. Cloud
/// Functions / FCM push GEREKMEZ: teslimat, kullanıcı uygulamayı açtığında
/// olur (premium_grants deseninin aynısı, bkz. PresenceService).
///
/// DOKÜMAN ŞEMASI (`duyurular/aktif`):
///   { aktif: bool, baslik: string, govde: string, id: string }
/// - [aktif] false ise hiçbir şey gösterilmez (duyuruyu "kapatmak" için).
/// - [id] her YENİ duyuru için değiştirilir (ör. tarih/sürüm). Cihaz en son
///   gösterdiği [id]'yi saklar; aynı id tekrar gösterilmez. id boşsa başlık
///   kimlik olarak kullanılır (yine de tekrar göstermez).
///
/// DAYANIKLILIK: Hiçbir metod istisna fırlatmaz; Firebase yoksa / okuma
/// başarısızsa sessizce no-op.
class DuyuruService {
  DuyuruService._();
  static final DuyuruService instance = DuyuruService._();

  static const String _collection = 'duyurular';
  static const String _docId = 'aktif';

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// Aktif duyuruyu okur ve daha önce gösterilmediyse üstten afişle gösterir.
  /// Açılışta (uygulama öndeyken) çağrılmalıdır.
  Future<void> kontrolVeGoster(StorageService storage) async {
    if (!isFirebaseConfigured) return;
    try {
      final doc = await _db.collection(_collection).doc(_docId).get();
      final data = doc.data();
      if (data == null) return;
      if (data['aktif'] != true) return;

      final baslik = (data['baslik'] ?? '').toString().trim();
      final govde = (data['govde'] ?? '').toString().trim();
      if (baslik.isEmpty && govde.isEmpty) return;

      // Kimlik: panelden verilen id birincil; yoksa başlık+gövde içeriğinden
      // türet (içerik değişince yeniden gösterilsin).
      final id = (data['id'] ?? '').toString().trim().isNotEmpty
          ? data['id'].toString().trim()
          : '$baslik|$govde';

      if (storage.getSonGorulenDuyuruId() == id) return; // zaten gösterildi
      await storage.setSonGorulenDuyuruId(id);

      InAppNoticeService.instance.goster(InAppNotice(
        baslik: baslik.isNotEmpty ? baslik : 'Duyuru',
        govde: govde,
        emoji: '📢',
        etiket: 'duyuru',
      ));
    } catch (e) {
      debugPrint('DuyuruService.kontrolVeGoster başarısız: $e');
    }
  }
}
