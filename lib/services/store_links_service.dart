import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../firebase_bootstrap.dart';

/// Uygulamanın mağaza bağlantıları + kimlikleri.
///
/// Varsayılanlar koda gömülüdür; ASIL değerler Firestore'daki
/// `app_meta/store_links` belgesinden çekilir. Amaç (kullanıcı isteği):
/// uygulama Google Play'e yüklenip linki hazır olunca, UYGULAMAYI YENİDEN
/// GÜNCELLEMEDEN yalnızca Firebase Console'dan bu belgeyi doldurmak yeterli
/// olsun — hem App Store hem Google Play linki oradan gelsin.
///
/// Firebase Console > Firestore > `app_meta` koleksiyonu > `store_links`
/// belgesi (alanlar hepsi opsiyonel; boş bırakılan alanlar varsayılanı kullanır):
///   iosUrl (string)      → App Store linki
///   androidUrl (string)  → Google Play linki (yayınlanınca doldur)
///   iosId (string)       → App Store sayısal ID (6792403982)
///   androidId (string)   → Android paket adı (Play'de "ID" olarak aranır)
///   appName (string)     → Uygulama adı
class StoreLinks {
  final String iosUrl;
  final String androidUrl; // Play'de yayınlanana kadar boş olabilir
  final String iosId;
  final String androidId; // Android applicationId
  final String appName;

  const StoreLinks({
    required this.iosUrl,
    required this.androidUrl,
    required this.iosId,
    required this.androidId,
    required this.appName,
  });

  /// Google Play linki hazır mı (Firestore'da androidUrl dolu mu)?
  bool get androidVar => androidUrl.trim().isNotEmpty;

  static const StoreLinks defaults = StoreLinks(
    iosUrl: 'https://apps.apple.com/app/id6792403982',
    androidUrl: '', // henüz Google Play'de yayınlanmadı
    iosId: '6792403982',
    androidId: 'com.kpsshazirlik.kpss_telefon',
    appName: 'KPSS Hazırlık',
  );

  /// Firestore verisini varsayılanların ÜZERİNE uygular (boş alan = varsayılan).
  StoreLinks _merge(Map<String, dynamic> d) {
    String pick(String key, String fallback) {
      final v = d[key];
      return (v is String && v.trim().isNotEmpty) ? v : fallback;
    }

    return StoreLinks(
      iosUrl: pick('iosUrl', iosUrl),
      // androidUrl'de boş DA anlamlı (henüz yok) — string ise olduğu gibi al.
      androidUrl: d['androidUrl'] is String ? d['androidUrl'] as String : androidUrl,
      iosId: pick('iosId', iosId),
      androidId: pick('androidId', androidId),
      appName: pick('appName', appName),
    );
  }
}

class StoreLinksService {
  static const String _col = 'app_meta';
  static const String _doc = 'store_links';
  static StoreLinks? _cache;

  /// Firestore'dan mağaza linklerini çeker (oturum boyunca bir kez cache'ler).
  /// Firebase yok / offline / belge yoksa varsayılanları döner — asla hata
  /// fırlatıp uygulamayı çökertmez.
  Future<StoreLinks> fetch() async {
    if (_cache != null) return _cache!;
    if (!isFirebaseConfigured) return StoreLinks.defaults;
    try {
      final snap =
          await FirebaseFirestore.instance.collection(_col).doc(_doc).get();
      final data = snap.data();
      final result =
          data == null ? StoreLinks.defaults : StoreLinks.defaults._merge(data);
      _cache = result;
      return result;
    } catch (e) {
      debugPrint('StoreLinksService.fetch başarısız: $e');
      return StoreLinks.defaults;
    }
  }
}
