import 'dart:async';
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

  /// Bir ödüllü reklam izleme başına verilen kredi (kullanıcı isteği: ücretsiz
  /// genişletildi — her reklam 2 hak versin).
  static const int odulKrediSayisi = 2;

  // GERÇEK AdMob ödüllü reklam birim kimlikleri (birim adı: kpss_rewarded).
  // Native App ID'ler: AndroidManifest.xml + ios/Runner/Info.plist.
  static const String _androidRewarded = 'ca-app-pub-2208830315848722/6997660328';
  static const String _iosRewarded = 'ca-app-pub-2208830315848722/3832561079';

  // GERÇEK AdMob GEÇİŞ (interstitial) reklam birim kimlikleri (birim adı:
  // kpss_interstitial) — kısa reklam, oyun/düello/quiz sonunda. Test birimleri
  // GERÇEK birimlerle değiştirildi (2026-08-24). Yeni birimler ilk ~1 saat boş
  // dönebilir; sonra dolar.
  static const String _androidInterstitial =
      'ca-app-pub-2208830315848722/3723649785';
  static const String _iosInterstitial =
      'ca-app-pub-2208830315848722/1117772942';

  bool _baslatildi = false;
  RewardedAd? _reklam;
  bool _yukleniyor = false;

  // Geçiş reklamı durumu.
  InterstitialAd? _gecis;
  bool _gecisYukleniyor = false;

  String get _birimId {
    if (kIsWeb) return _androidRewarded;
    return Platform.isIOS ? _iosRewarded : _androidRewarded;
  }

  String get _gecisBirimId {
    if (kIsWeb) return _androidInterstitial;
    return Platform.isIOS ? _iosInterstitial : _androidInterstitial;
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
      _gecisOnYukle();
    } catch (e) {
      debugPrint('AdService.baslat hatası: $e');
    }
  }

  /// Bir sonraki GEÇİŞ (interstitial) reklamını ön yükler.
  void _gecisOnYukle() {
    if (!_baslatildi || _gecisYukleniyor || _gecis != null) return;
    _gecisYukleniyor = true;
    InterstitialAd.load(
      adUnitId: _gecisBirimId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _gecis = ad;
          _gecisYukleniyor = false;
        },
        onAdFailedToLoad: (err) {
          _gecis = null;
          _gecisYukleniyor = false;
          debugPrint('AdService: geçiş reklamı yüklenemedi: ${err.code} ${err.message}');
        },
      ),
    );
  }

  /// KISA GEÇİŞ REKLAMI (kullanıcı isteği: test/oyun/düello sonunda kısa reklam;
  /// hak sayfasındaki uzun ödüllü reklam gibi olmasın). [premium] true ise HİÇ
  /// gösterilmez (premium'da hiçbir yerde reklam yok). Ödül yoktur; sadece
  /// gösterilir ve kapanır. Reklam hazır değilse sessizce geçer (akışı bloklamaz).
  Future<void> gecisReklamiGoster({required bool premium}) async {
    if (premium) return; // premium: kesinlikle reklam yok
    if (kIsWeb || kDebugMode) return; // web/debug: reklam yok, akış bozulmasın
    if (!(Platform.isAndroid || Platform.isIOS)) return;
    if (!_baslatildi) await baslat();
    if (_gecis == null) {
      _gecisOnYukle();
      // Kısa bir yükleme şansı; gelmezse sessizce vazgeç (akışı bekletme).
      for (var i = 0; i < 8 && _gecis == null; i++) {
        await Future.delayed(const Duration(milliseconds: 150));
      }
    }
    final ad = _gecis;
    if (ad == null) return;
    _gecis = null;
    final tamam = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _gecisOnYukle();
        if (!tamam.isCompleted) tamam.complete();
      },
      onAdFailedToShowFullScreenContent: (ad, err) {
        ad.dispose();
        _gecisOnYukle();
        if (!tamam.isCompleted) tamam.complete();
      },
    );
    try {
      await ad.show();
    } catch (e) {
      debugPrint('AdService: geçiş reklamı gösterilemedi: $e');
      if (!tamam.isCompleted) tamam.complete();
    }
    return tamam.future;
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
    // GELİŞTİRME/TEST KOLAYLIĞI: Gerçek reklam SDK'sı web'de çalışmaz, debug
    // derlemelerde de test reklamı her zaman gelmeyebilir. Bu yüzden YALNIZCA
    // kDebugMode'da (web dahil) ödül akışı, gerçek reklam olmadan başarılı
    // sayılır ki "reklam izle → +hak" akışı test edilebilsin.
    // RELEASE derlemede (kDebugMode == false) bu blok ÇALIŞMAZ; gerçek reklam
    // izlenmeden hak verilmez.
    if (kDebugMode) {
      await Future.delayed(const Duration(milliseconds: 500));
      return true;
    }
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

    // ÖNEMLİ (düzeltilen hata): `ad.show(...)` reklam KAPANMADAN, sadece
    // gösterilir gösterilmez geri döner. Ödül callback'i (onUserEarnedReward)
    // ise reklamın sonuna doğru tetiklenir. Eskiden `show`'dan hemen sonra
    // `odulKazanildi` okunduğu için değer HÂLÂ false oluyordu → kullanıcı
    // reklamı izlese de HAK VERİLMİYORDU. Artık reklam KAPANANA (dismiss)
    // kadar bir Completer ile beklenir ve ödül bayrağı o an okunur.
    final tamamlandi = Completer<bool>();
    var odulKazanildi = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _onYukle(); // sonraki için hazırla
        if (!tamamlandi.isCompleted) tamamlandi.complete(odulKazanildi);
      },
      onAdFailedToShowFullScreenContent: (ad, err) {
        ad.dispose();
        _onYukle();
        if (!tamamlandi.isCompleted) tamamlandi.complete(false);
      },
    );

    try {
      await ad.show(onUserEarnedReward: (ad, reward) => odulKazanildi = true);
    } catch (e) {
      debugPrint('AdService: reklam gösterilemedi: $e');
      if (!tamamlandi.isCompleted) tamamlandi.complete(false);
    }
    // Reklam kapanınca (dismiss/fail) tetiklenen sonucu bekle.
    return tamamlandi.future;
  }
}
