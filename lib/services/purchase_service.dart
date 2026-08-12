import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'auth_service.dart';
import 'cloud_sync_service.dart';
import 'presence_service.dart';
import 'storage_service.dart';

/// ============================================================================
/// ÜRÜN ID'LERİ — TODO: MAĞAZA KURULUMUNU BEKLİYOR
/// ============================================================================
/// Bu ID'ler App Store Connect / Play Console'da tanımlanan GERÇEK ürün
/// ID'leriyle BİREBİR EŞLEŞMELİDİR. Şu an bu proje gerçek bir Apple Developer /
/// Google Play Console hesabına bağlı değil; bu yüzden aşağıdaki değerler
/// PLACEHOLDER'dır. Kullanıcı kendi mağaza hesaplarında bu ID'lerle ürün/
/// abonelik tanımladığında kodda BAŞKA HİÇBİR DEĞİŞİKLİK GEREKMEZ — sadece
/// mağazadaki tanım bu string'lerle eşleşmelidir (bkz. IAP_SETUP.md).
const String kOgrenciPremiumId = 'premium_ogrenci_aylik';
const String kTamPremiumId = 'premium_tam_aylik';

/// TÜKETİLEBİLİR (consumable) "hak paketi": 10 hak, ~9,99 TL. Aboneliklerden
/// farklı olarak tekrar tekrar satın alınabilir; her satın almada cüzdana
/// [kHakPaketiMiktar] hak eklenir ve mağazada TÜKETİLİR (completePurchase +
/// consume) ki kullanıcı yeniden alabilsin. Mağazada bu ID ile "consumable"
/// ürün tanımlanmalı (Play: uygulama içi ürün / App Store: tüketilebilir).
const String kHakPaketiId = 'hak_paketi_10';
const int kHakPaketiMiktar = 10;

/// Sorgulanacak / satın alınabilecek tüm ürün ID'lerinin kümesi.
const Set<String> kPremiumProductIds = {
  kOgrenciPremiumId,
  kTamPremiumId,
  kHakPaketiId,
};

/// Mağaza / satın alma akışının o anki durumu. UI bu duruma göre buton
/// metnini, yükleniyor göstergesini ve hata mesajını belirler.
enum PurchaseServiceStatus {
  /// Henüz başlatılmadı (init() çağrılmadı ya da hâlâ sürüyor).
  idle,

  /// Mağaza kullanılabilir, ürünler yüklendi, satın almaya hazır.
  ready,

  /// isAvailable() false döndü ya da ürünler mağazada bulunamadı — gerçek
  /// mağaza şu an kullanılamıyor (ör. emülatör, mağaza hesabı bağlı değil,
  /// ürünler henüz App Store Connect/Play Console'da onaylanmadı).
  unavailable,

  /// Bir satın alma isteği devam ediyor.
  purchasing,

  /// Son işlemde hata oluştu (bkz. lastError).
  error,
}

/// in_app_purchase (StoreKit / Google Play Billing) tabanlı gerçek satın alma
/// servisi. `lib/screens/premium_screen.dart` bu servis üzerinden abonelik
/// satın alır / geri yükler.
///
/// NOT (güvenlik): Bu sınıf satın alma tamamlandığında (`PurchaseStatus.purchased`)
/// premium'u SADECE CLIENT TARAFINDA, mağazanın döndürdüğü işlem durumuna
/// güvenerek açar. Gerçek bir üründe bu YETERLİ DEĞİLDİR — kötü niyetli bir
/// kullanıcı cihazda oynayarak ya da sahte bir istemci ile bu client-side
/// kontrolü atlatabilir. Prodüksiyonda mutlaka:
///   1) `purchaseDetails.verificationData.serverVerificationData` (App Store
///      receipt / Play Store purchase token) bir backend'e (Cloud Function,
///      kendi sunucunuz vb.) gönderilmeli,
///   2) Backend, Apple App Store Server API / Google Play Developer API ile
///      makbuzu doğrulamalı,
///   3) Yalnızca backend "geçerli" derse premium açılmalı (ör. Firestore'da
///      bir custom claim / kullanıcı dokümanı güncellenerek).
/// Bkz. IAP_SETUP.md → "Sunucu Taraflı Makbuz Doğrulaması" bölümü.
class PurchaseService extends ChangeNotifier {
  PurchaseService(this._storage);

  final StorageService _storage;
  final InAppPurchase _iap = InAppPurchase.instance;

  StreamSubscription<List<PurchaseDetails>>? _subscription;

  PurchaseServiceStatus status = PurchaseServiceStatus.idle;
  List<ProductDetails> products = [];
  String? lastError;
  bool _initialized = false;

  bool get isPurchasing => status == PurchaseServiceStatus.purchasing;

  ProductDetails? productFor(String id) {
    for (final p in products) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Mağazayı başlatır: kullanılabilirlik kontrolü + ürün bilgisi çekme.
  /// Mağaza kullanılamazsa (emülatör, hesap bağlı değil, ürünler tanımsız)
  /// sessizce [PurchaseServiceStatus.unavailable]'a düşer — asla exception
  /// fırlatıp uygulamayı çökertmez.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await _yukle();
  }

  /// Kullanıcı "Tekrar Dene"ye bastığında (ya da mağaza geç hazır olduğunda)
  /// ürünleri yeniden yükler. init()'ten farkı: `_initialized` bayrağına
  /// bakmaz, her çağrıda yeniden sorgular.
  Future<void> yenidenDene() => _yukle();

  /// Mağazayı hazırlar ve ürünleri çeker. Ürün sorgusu, iOS'ta App Review
  /// ortamında sık görülen GEÇİCİ "StoreKit: Failed to get response from
  /// platform" hatasına karşı BİRKAÇ KEZ denenir — tek seferlik geçici bir
  /// hata artık kalıcı "kullanılamıyor" durumuna düşürmez (red sebebi buydu).
  Future<void> _yukle() async {
    status = PurchaseServiceStatus.idle;
    lastError = null;
    notifyListeners();
    try {
      final available = await _iap.isAvailable();
      if (!available) {
        status = PurchaseServiceStatus.unavailable;
        lastError = 'Mağaza şu an kullanılamıyor (isAvailable=false).';
        notifyListeners();
        return;
      }

      // Satın alma güncellemelerini dinle — yalnızca BİR KEZ abone ol
      // (yenidenDene defalarca çağrılabilir; çift abonelik olmasın).
      _subscription ??= _iap.purchaseStream.listen(
        _onPurchaseUpdate,
        onDone: () => _subscription?.cancel(),
        onError: (Object e) {
          status = PurchaseServiceStatus.error;
          lastError = e.toString();
          notifyListeners();
        },
      );

      // ÜRÜN SORGUSU — en fazla 3 deneme, artan bekleme ile. StoreKit ilk
      // açılışta / zayıf ağda ilk sorguya bazen yanıt vermez; tekrar deneyince
      // döner. (App Store denetçisinin gördüğü "Failed to get response from
      // platform" tam olarak bu geçici durumdu.)
      ProductDetailsResponse? response;
      for (var deneme = 1; deneme <= 3; deneme++) {
        response = await _iap.queryProductDetails(kPremiumProductIds);
        final basarili =
            response.error == null && response.productDetails.isNotEmpty;
        if (basarili || deneme == 3) break;
        await Future.delayed(Duration(milliseconds: 700 * deneme));
      }

      if (response == null || response.error != null) {
        status = PurchaseServiceStatus.unavailable;
        lastError = response?.error?.message ?? 'Mağaza yanıt vermedi.';
        notifyListeners();
        return;
      }

      if (response.productDetails.isEmpty) {
        // App Store Connect / Play Console'da ürünler henüz onaylı/eklenmemişse
        // ya da Paid Apps sözleşmesi aktif değilse buraya düşülür.
        status = PurchaseServiceStatus.unavailable;
        lastError = 'Ürünler mağazada bulunamadı (henüz tanımlanmamış olabilir).';
        notifyListeners();
        return;
      }

      products = response.productDetails;
      status = PurchaseServiceStatus.ready;
      lastError = null;
      notifyListeners();
    } catch (e) {
      // Ağ hatası, platform kanalı hatası vb. — uygulamayı çökertme, sadece
      // "kullanılamıyor" durumuna düş.
      status = PurchaseServiceStatus.unavailable;
      lastError = e.toString();
      notifyListeners();
    }
  }

  /// Verilen ürün ID'si için satın alma akışını başlatır. Abonelik ürünleri
  /// (App Store'da "Auto-Renewable Subscription", Play Console'da
  /// "Subscription") in_app_purchase paketinde de non-consumable akışıyla
  /// (`buyNonConsumable`) satın alınır — pakette ayrı bir "buySubscription"
  /// metodu yoktur, tip mağaza tarafında ürünün kendisinde tanımlanır.
  Future<void> buy(String productId) async {
    final product = productFor(productId);
    if (product == null) {
      lastError = 'Ürün bulunamadı: $productId (mağaza/ürün tanımını kontrol edin).';
      status = PurchaseServiceStatus.error;
      notifyListeners();
      return;
    }

    try {
      status = PurchaseServiceStatus.purchasing;
      notifyListeners();

      final purchaseParam = PurchaseParam(productDetails: product);
      if (productId == kHakPaketiId) {
        // Hak paketi TÜKETİLEBİLİR: tekrar tekrar alınabilsin diye consumable
        // akışıyla satın alınır.
        await _iap.buyConsumable(purchaseParam: purchaseParam);
      } else {
        // Abonelik = non-consumable akış (yukarıdaki nota bakın).
        await _iap.buyNonConsumable(purchaseParam: purchaseParam);
      }
      // Sonuç purchaseStream üzerinden _onPurchaseUpdate'e gelecek.
    } catch (e) {
      status = PurchaseServiceStatus.error;
      lastError = e.toString();
      notifyListeners();
    }
  }

  /// Kullanıcı telefon değiştirdiğinde / uygulamayı yeniden kurduğunda daha
  /// önce satın aldığı (henüz süresi dolmamış) aboneliği geri yükler.
  /// iOS'ta App Store, satın alma geçmişini `purchaseStream` üzerinden
  /// "restored" durumuyla tekrar yayınlar; Android'de Play Billing benzer
  /// şekilde davranır.
  Future<void> restorePurchases() async {
    try {
      await _iap.restorePurchases();
    } catch (e) {
      status = PurchaseServiceStatus.error;
      lastError = e.toString();
      notifyListeners();
    }
  }

  Future<void> _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.pending:
          status = PurchaseServiceStatus.purchasing;
          notifyListeners();
          break;

        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          // ------------------------------------------------------------
          // TODO (SUNUCU TARAFLI MAKBUZ DOĞRULAMASI — PRODÜKSİYONDA ŞART):
          // Şu an burada `purchase.verificationData.serverVerificationData`
          // değerini DOĞRULAMADAN, mağazanın client'a döndürdüğü duruma
          // güvenerek premium açıyoruz. Gerçek/canlı sürümde bu veri bir
          // backend'e gönderilip Apple/Google API'leriyle doğrulanmalı ve
          // premium SADECE doğrulama başarılıysa açılmalı. Bkz. IAP_SETUP.md.
          // ------------------------------------------------------------
          // KRİTİK (kullanıcı isteği): Premium yalnızca GERÇEKTEN GİRİŞ YAPMIŞ
          // (anonim değil) hesaba tanımlanır. iOS'ta StoreKit, uygulama silinip
          // yeniden kurulunca Apple ID'ye bağlı aboneliği "restored" olarak
          // tekrar yayınlar; bu olayı MİSAFİR profiline yazarsak giriş yapmamış
          // kullanıcı premium görünürdü. Bu yüzden girişli değilse premium AÇMA
          // — kullanıcı giriş yapınca zaten buluttan (syncDown) geri gelir.
          final girisli = AuthService().isRealSignedIn;
          if (purchase.productID == kOgrenciPremiumId ||
              purchase.productID == kTamPremiumId) {
            if (girisli) {
              await _storage.setUserPlan('premium');
              // ignore: unawaited_futures
              CloudSyncService().syncUp(_storage);
              // ignore: unawaited_futures
              PresenceService.instance.bildir(_storage, zorla: true);
            }
            // Girişli değilse: premium yazma. (Restore edilen abonelik, kullanıcı
            // giriş yapınca premium_screen'deki "Satın alımları geri yükle" ya da
            // buluttan senkron ile hesaba bağlanır.)
          } else if (purchase.productID == kHakPaketiId &&
              purchase.status == PurchaseStatus.purchased) {
            // TÜKETİLEBİLİR hak paketi: cüzdana ekle (yalnızca yeni 'purchased';
            // "restored"da tüketilebilir eklenmez). Premium aboneliğin aksine
            // hak paketi HERKESE açık (misafir de satın alabilir) — tüketilebilir
            // olduğu için StoreKit'in reinstall'da yeniden yayınlama/premium
            // sızıntısı sorunu burada YOKTUR. Paranın karşılığı kesin verilsin.
            await _storage.hakEkle(kHakPaketiMiktar);
            // Yalnızca girişliyse buluta yaz (misafirin hakkı yerelde kalır,
            // reklamla kazanılan hak gibi).
            if (girisli) {
              // ignore: unawaited_futures
              CloudSyncService().syncUp(_storage);
            }
          }
          if (purchase.pendingCompletePurchase) {
            await _iap.completePurchase(purchase);
          }
          status = PurchaseServiceStatus.ready;
          lastError = null;
          notifyListeners();
          break;

        case PurchaseStatus.error:
          status = PurchaseServiceStatus.error;
          lastError = purchase.error?.message ?? 'Bilinmeyen satın alma hatası.';
          if (purchase.pendingCompletePurchase) {
            await _iap.completePurchase(purchase);
          }
          notifyListeners();
          break;

        case PurchaseStatus.canceled:
          status = PurchaseServiceStatus.ready;
          notifyListeners();
          break;
      }
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
