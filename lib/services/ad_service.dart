import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Ödüllü reklam servisi.
///
/// TASARIM İLKELERİ (kullanıcı istekleri):
///  • YALNIZCA ödüllü (rewarded) reklam. Banner, geçiş (interstitial) ya da
///    açılış reklamı YOKTUR — kullanıcı bir butona basıp "reklam izle"
///    demeden EKRANDA HİÇBİR reklam çıkmaz.
///  • Premium kullanıcıya HİÇ reklam gösterilmez (çağıran taraf premium'u
///    kontrol edip bu servisi hiç çağırmaz; ayrıca burada da savunma yok —
///    çağrılırsa gösterir, o yüzden çağrı yerlerinde premium kontrolü ŞART).
///  • Ödül: kullanıcı reklamı SONUNA KADAR izlerse [odulKrediSayisi] kredi.
///
/// REKLAM KİMLİKLERİ GERÇEK AdMob birim kimlikleridir. NOT: AdMob uygulaması
/// henüz mağazaya bağlanıp incelenmediği için "sınırlı reklam sunumu"
/// durumunda olabilir; geliştirme sırasında geçersiz trafik riskine karşı
/// AdMob konsolundan cihazını "test cihazı" olarak eklemen önerilir.
class AdService {
  AdService._();
  static final AdService instance = AdService._();

  /// Bir ödüllü reklam izleme başına verilen kredi.
  static const int odulKrediSayisi = 2;

  // GERÇEK AdMob ödüllü reklam birim kimlikleri (birim adı: kpss_rewarded).
  // Native App ID'ler: AndroidManifest.xml + ios/Runner/Info.plist.
  static const String _androidRewarded = 'ca-app-pub-2208830315848722/6997660328';
  static const String _iosRewarded = 'ca-app-pub-2208830315848722/3832561079';

  bool _baslatildi = false;
  RewardedAd? _reklam;
  bool _yukleniyor = false;

  String get _birimId {
    if (kIsWeb) return _androidRewarded;
    return Platform.isIOS ? _iosRewarded : _androidRewarded;
  }

  /// main.dart'ta bir kez çağrılır. Reklam SDK'sını başlatır ve ilk reklamı
  /// arka planda ön yükler. Desteklenmeyen platformda sessizce no-op.
  Future<void> baslat() async {
    if (_baslatildi || kIsWeb) return;
    if (!(Platform.isAndroid || Platform.isIOS)) return;
    try {
      await MobileAds.instance.initialize();
      _baslatildi = true;
      _onYukle();
    } catch (e) {
      debugPrint('AdService.baslat hatası: $e');
    }
  }

  /// Bir sonraki reklamı hazırda tutmak için ön yükler.
  void _onYukle() {
    if (!_baslatildi || _yukleniyor || _reklam != null) return;
    _yukleniyor = true;
    RewardedAd.load(
      adUnitId: _birimId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _reklam = ad;
          _yukleniyor = false;
        },
        onAdFailedToLoad: (err) {
          _reklam = null;
          _yukleniyor = false;
          debugPrint('AdService: reklam yüklenemedi: ${err.code} ${err.message}');
        },
      ),
    );
  }

  /// Reklam GÖSTERİLMEYE hazır mı? (Buton, hazır değilken "yükleniyor"
  /// gösterebilsin diye.)
  bool get hazir => _reklam != null;

  /// Ödüllü reklamı gösterir. Kullanıcı ödülü HAK ETTİYSE (reklamı yeterince
  /// izlediyse) `true` döner; reklam yoksa/başarısızsa ya da kullanıcı erken
  /// kapattıysa `false`.
  ///
  /// ÇAĞIRAN TARAF: dönüş true ise krediyi EKLEMELİDİR (StorageService.hakEkle).
  /// Bu servis depolamaya dokunmaz — test edilebilir ve premium'dan bağımsız
  /// kalsın diye.
  Future<bool> odulluReklamGoster() async {
    if (!_baslatildi) await baslat();
    // Hazır değilse kısa bir yükleme şansı ver.
    if (_reklam == null) {
      _onYukle();
      for (var i = 0; i < 20 && _reklam == null; i++) {
        await Future.delayed(const Duration(milliseconds: 150));
      }
    }
    final ad = _reklam;
    if (ad == null) return false;
    _reklam = null; // tek kullanımlık

    var odulKazanildi = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _onYukle(); // sonraki için hazırla
      },
      onAdFailedToShowFullScreenContent: (ad, err) {
        ad.dispose();
        _onYukle();
      },
    );

    await ad.show(onUserEarnedReward: (ad, reward) => odulKazanildi = true);
    return odulKazanildi;
  }
}
