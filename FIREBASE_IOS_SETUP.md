# iOS'ta Giriş / Oda Açma / Soru İndirme — Kök Neden ve Kurulum

## Sorun neydi?

TestFlight'ta şu hatayı alıyordun:

> Firebase henüz yapılandırılmadı. google-services.json / GoogleService-Info.plist
> eklenip initFirebaseIfConfigured() çağrıldıktan sonra bu özellik aktif olacak.

Ayrıca oda açarken / soru indirirken "internet bağlantısı yok" diyordu.

**Hepsinin tek bir kök nedeni vardı:**
`ios/Runner/GoogleService-Info.plist` dosyası diskte duruyordu ama
**Xcode projesine (`project.pbxproj`) hiç eklenmemişti.** Yani dosya IPA'nın
içine kopyalanmıyordu. `Firebase.initializeApp()` config bulamayınca hata
fırlatıyor, `initFirebaseIfConfigured()` bunu yakalayıp `false` dönüyordu ve
buna bağlı **her şey** (giriş, düello odaları, soru indirme, sohbet, lig,
bulut yedekleme) kapalı kalıyordu.

`main.dart` zaten `initFirebaseIfConfigured()`'ı doğru şekilde çağırıyordu —
sorun Dart tarafında değildi.

## Kodda yapılan düzeltmeler (tamamlandı)

1. `GoogleService-Info.plist` Xcode projesine eklendi — `PBXFileReference`,
   `PBXBuildFile`, Runner grubu ve **Copy Bundle Resources** fazı olmak üzere
   4 yere kaydedildi. Artık IPA'ya paketleniyor.
2. `Runner.entitlements` dosyası Runner target'ına bağlandı
   (`CODE_SIGN_ENTITLEMENTS`, üç konfigürasyon: Debug / Release / Profile).
   Daha önce diskte duruyor ama hiçbir target'a bağlı değildi.
3. Entitlements içine **`com.apple.developer.applesignin`** eklendi. Bu
   olmadan "Apple ile Giriş" iOS'ta her zaman hata döner.
4. Entitlements'tan **App Groups kaldırıldı**. Sebep: `DailyCodeWidget`
   extension'ı Xcode projesine bir target olarak hiç eklenmemiş
   (`project.pbxproj` içinde 0 referans). Provisioning profile'da karşılığı
   olmayan bir App Group entitlement'ı imzalamayı bozar. Widget target'ı
   gerçekten eklendiğinde geri konmalı (dosyada yorum olarak duruyor).
5. Yanıltıcı "internet bağlantısı yok" mesajları gerçek sebebi söyleyecek
   şekilde yeniden yazıldı.

## Senin yapman gerekenler

### 1. Xcode'da capability'leri onayla (ZORUNLU)

Otomatik imzalama açık, ama Xcode'un App ID'yi güncellemesi gerekiyor:

- `ios/Runner.xcworkspace` dosyasını Xcode'da aç
- **Runner target > Signing & Capabilities**
- **"Sign in with Apple"** capability'sinin listede göründüğünü doğrula
  (entitlements dosyasından otomatik gelmeli; gelmezse `+ Capability` ile ekle)
- Signing bölümünde kırmızı hata olmadığından emin ol

### 2. Firebase Console'da sağlayıcıları aç — ✅ TAMAMLANDI

`kpss-52eb6` projesinde **Authentication > Sign-in method** altında:

- **Apple** → ✅ etkin
- **Anonymous** → ✅ etkin
  (Düello odaları `signInAnonymously()` kullanıyor — bu kapalıysa **oda
  açma/katılma çalışmaz**, giriş yapmış olsan bile)
- **Google** → ✅ etkin

### 3. Google ile Giriş — ✅ TAMAMLANDI

Firebase Console'da Google sağlayıcısı açık ve `GoogleService-Info.plist`
yeniden indirilip projeye kuruldu. Dosya artık `CLIENT_ID` ve
`REVERSED_CLIENT_ID` anahtarlarını içeriyor.

`ios/Runner/Info.plist` içindeki `CFBundleURLSchemes` değeri de plist'teki
`REVERSED_CLIENT_ID` ile birebir eşleşecek şekilde güncellendi:

```
com.googleusercontent.apps.993008276386-78k2ralk6pk3adsr2uut0lhlc7g0m4kj
```

> Firebase projesi ileride değişirse bu iki değer BİRLİKTE güncellenmelidir.
> Ayrışırlarsa Google girişi, kullanıcı hesabını seçtikten sonra uygulamaya
> geri dönemez.

### 4. Firestore kuralları — ✅ YAYINLANDI

Kuralların tam ve güncel hali repo kökündeki **`firestore.rules`** dosyasında
duruyor ve Firebase Console'a yayınlandı (21 Temmuz 2026).

Kurallar değiştirilecekse `firestore.rules` düzenlenip Console'a yeniden
yapıştırılmalı ya da şu komutla dağıtılmalı:

```bash
firebase deploy --only firestore:rules
```

Kritik nokta: kullanıcının KENDİ dokümanlarını silme izni, "Hesabımı Sil"
akışının çalışması için şarttır. Bu izin olmadan silme adımları sessizce
başarısız olur; kullanıcı "hesabım silindi" görür ama veriler sunucuda kalır
(App Store 5.1.1(v) ve Google Play veri silme şartının ihlali).

**Yayınlanan kural setinin kapsadıkları:** `question_banks`, `app_meta`,
`duel_rooms`, `league_scores`, `cloud_backups`, `user_notifications`,
`blocked_users`, `chat_messages`, `dm_threads`, `chat_reports` + sonda
varsayılan-kapalı (default deny) bloğu.

> **Kaldırılan koleksiyonlar:** Önceki kural setinde `support_tickets`,
> `live_exams` ve `scores` için de bloklar vardı. Kod tabanı tarandı; bu üç
> koleksiyon uygulamada **hiç kullanılmıyor** (eski bir tasarımdan kalma).
> Varsayılan-kapalı bloğu bu yüzden hiçbir özelliği bozmuyor. İleride bu
> koleksiyonlar gerçekten kullanılacaksa kuralları geri eklemek gerekir.

> `question_banks` koleksiyonunun dolu olduğu doğrulandı (50+ konu dokümanı).

### 5. Yeni build al

```bash
flutter clean
flutter pub get
cd ios && pod install && cd ..
flutter build ipa
```

## Doğrulama

Uygulama açılışında Xcode konsolunda şunu görmelisin:

```
[firebase_bootstrap] Firebase başarıyla başlatıldı.
```

Bu satır çıkmıyorsa plist hâlâ bundle'a girmiyor demektir — Xcode'da
**Runner target > Build Phases > Copy Bundle Resources** listesinde
`GoogleService-Info.plist` olduğunu kontrol et.
