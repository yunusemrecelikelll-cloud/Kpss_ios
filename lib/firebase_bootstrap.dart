import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Gerçek bir Firebase projesi (google-services.json / GoogleService-Info.plist)
/// eklendiğinde, `main.dart`'ın `runApp` çağrısından ÖNCE tek satırla çağırması
/// gereken başlatma fonksiyonu.
///
/// DURUM: Proje ARTIK gerçek bir Firebase projesine (kpss-52eb6) bağlıdır ve
/// bu fonksiyon `lib/main.dart` içinden çağrılmaktadır. Config dosyaları
/// (android/app/google-services.json, ios/Runner/GoogleService-Info.plist)
/// yerinde ve iOS tarafında Xcode projesine kayıtlıdır.
///
/// Çağrı şekli (main.dart'ta hâlihazırda böyle):
///
/// ```dart
/// WidgetsFlutterBinding.ensureInitialized();
/// await initFirebaseIfConfigured();
/// ```
///
/// Config dosyaları henüz yoksa veya başlatma başarısız olursa bu fonksiyon
/// İSTİSNA FIRLATMAZ — sessizce `false` döner ve konsola log basar. Böylece
/// Firebase paketleri pubspec.yaml'da kurulu olsa da, gerçek proje bağlanana
/// kadar uygulama tamamen "offline" modda, çökmeden çalışmaya devam eder.
Future<bool> initFirebaseIfConfigured() async {
  if (Firebase.apps.isNotEmpty) {
    // Zaten başlatılmış (ör. hot-restart sırasında tekrar çağrıldıysa).
    return true;
  }
  try {
    await Firebase.initializeApp();
    debugPrint('[firebase_bootstrap] Firebase başarıyla başlatıldı.');
    return true;
  } catch (e, st) {
    debugPrint(
      '[firebase_bootstrap] Firebase yapılandırılmamış ya da başlatılamadı '
      '(google-services.json / GoogleService-Info.plist eksik olabilir): $e',
    );
    debugPrint('$st');
    return false;
  }
}

/// Firebase'in şu an gerçekten kullanılabilir olup olmadığını (initializeApp
/// başarıyla çağrılmış mı) kontrol etmek için tüm servislerin kullandığı ortak
/// yardımcı. `initFirebaseIfConfigured()` hiç çağrılmadıysa ya da başarısız
/// olduysa `false` döner.
bool get isFirebaseConfigured => Firebase.apps.isNotEmpty;
