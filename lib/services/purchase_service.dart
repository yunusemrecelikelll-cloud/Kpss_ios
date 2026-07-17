import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'cloud_sync_service.dart';
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

/// Sorgulanacak / satın alınabilecek tüm ürün ID'lerinin kümesi.
const Set<String> kPremiumProductIds = {kOgrenciPremiumId, kTamPremiumId};

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

  bool get isReady => status == PurchaseServiceStatus.ready;
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

    try {
      final available = await _iap.isAvailable();
      if (!available) {
        status = PurchaseServiceStatus.unavailable;
        lastError = 'Mağaza şu an kullanılamıyor (isAvailable=false).';
        notifyListeners();
        return;
      }

      // Satın alma güncellemelerini dinlemeye başla (isAvailable true olsa da
      // olmasa da güvenli — ama pratikte sadece mağaza varsa anlamlı).
      _subscription = _iap.purchaseStream.listen(
        _onPurchaseUpdate,
        onDone: () => _subscription?.cancel(),
        onError: (Object e) {
          status = PurchaseServiceStatus.error;
          lastError = e.toString();
          notifyListeners();
        },
      );

      final response = await _iap.queryProductDetails(kPremiumProductIds);

      if (response.error != null) {
        status = PurchaseServiceStatus.unavailable;
        lastError = response.error!.message;
        notifyListeners();
        return;
      }

      if (response.productDetails.isEmpty) {
        // TODO: App Store Connect / Play Console'da ürünler henüz
        // tanımlanmadıysa ya da onay bekliyorsa buraya düşülür.
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
      // Abonelik = non-consumable akış (yukarıdaki nota bakın).
      await _iap.buyNonConsumable(purchaseParam: purchaseParam);
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
          if (purchase.productID == kOgrenciPremiumId ||
              purchase.productID == kTamPremiumId) {
            await _storage.setUserPlan('premium');
            // Satın alma anında girişliyse buluta hemen yansıt — böylece
            // başka bir cihazda/kurulumda tekrar giriş yapınca premium
            // durumu kaybolmuş görünmez (bkz. CloudSyncService.syncDown).
            // ignore: unawaited_futures
            CloudSyncService().syncUp(_storage);
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

/// iOS'ta App Store'un satın alma kuyruğunu StoreKit 2 ile uyumlu şekilde
/// başlatmak için bazı kurulumlarda gerekli olabilecek yardımcı — bu proje
/// varsayılan in_app_purchase davranışını kullanıyor, burada sadece
/// platformun iOS olup olmadığını basitçe kontrol etmek için tutuluyor
/// (ör. ileride StoreKit'e özgü bir ayar eklenmek istenirse).
bool get isApplePlatform => Platform.isIOS || Platform.isMacOS;
