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

### 2. Firebase Console'da sağlayıcıları aç (ZORUNLU)

`kpss-52eb6` projesinde **Authentication > Sign-in method** altında:

- **Apple** → etkinleştir
- **Anonymous** → etkinleştir
  (Düello odaları `signInAnonymously()` kullanıyor — bu kapalıysa **oda
  açma/katılma çalışmaz**, giriş yapmış olsan bile)
- **Google** → etkinleştir (aşağıdaki 3. adım için gerekli)

### 3. Google ile Giriş için plist'i yenile (Google girişi istiyorsan)

Şu anki `GoogleService-Info.plist` içinde **`CLIENT_ID` ve
`REVERSED_CLIENT_ID` anahtarları yok**. Bu anahtarlar yalnızca Firebase
Console'da Google sağlayıcısı açıkken üretilir. Onlar olmadan
`GoogleSignIn.instance.initialize()` başarısız olur.

1. Firebase Console > Authentication > Sign-in method > **Google**'ı aç
2. Project Settings > Your apps > iOS uygulaması > **GoogleService-Info.plist**'i
   yeniden indir
3. `ios/Runner/GoogleService-Info.plist` üzerine yaz
   (Xcode kaydı zaten yapıldı, tekrar eklemene gerek yok)
4. Yeni plist'teki `REVERSED_CLIENT_ID` değerini kopyala. Şu formatta olur:
   `com.googleusercontent.apps.993008276386-XXXXXXXXXXXX`
5. `ios/Runner/Info.plist` içindeki `CFBundleURLSchemes` altında duran
   `REVERSED_CLIENT_ID_BURAYA_YAPISTIR` yer tutucusunu bu değerle **değiştir**

Bu adımı atlarsan: **Apple ile giriş sorunsuz çalışır**, sadece Google
butonu hata verir.

### 4. Firestore kurallarını kontrol et

Oda açma ve soru indirme Firestore'a yazar/okur. Kurallar test modundaysa ve
süresi dolduysa her istek reddedilir. Gereken minimum:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    function girisli() { return request.auth != null; }
    function sahip(uid) { return request.auth != null && request.auth.uid == uid; }

    // Soru bankaları: herkes okuyabilir, kimse yazamaz
    match /question_banks/{topicId} {
      allow read: if true;
      allow write: if false;
    }

    // Uygulama meta verisi (içerik sürümü)
    match /app_meta/{doc} {
      allow read: if true;
      allow write: if false;
    }

    // Düello odaları: giriş yapmış (anonim dahil) herkes
    match /duel_rooms/{roomId} {
      allow read, write: if girisli();
      match /{sub=**} {
        allow read, write: if girisli();
      }
    }

    // ── Hesap silme için ZORUNLU izinler ────────────────────────────
    // Kullanıcı KENDİ dokümanlarını silebilmeli; aksi halde "Hesabımı Sil"
    // sessizce yarım kalır ve veriler sunucuda durmaya devam eder.

    // Herkese açık profil / lig özeti: herkes okur, sadece sahibi yazar/siler
    match /league_scores/{uid} {
      allow read: if true;
      allow write, delete: if sahip(uid);
    }

    // Bulut yedeği: sadece sahibi
    match /cloud_backups/{uid} {
      allow read, write, delete: if sahip(uid);
    }

    // Bildirimler: sadece sahibi
    match /user_notifications/{uid} {
      allow read, write, delete: if sahip(uid);
      match /items/{itemId} {
        allow read, write, delete: if sahip(uid);
      }
    }

    // Engellenen kullanıcılar: sadece sahibi
    match /blocked_users/{uid} {
      allow read, write, delete: if sahip(uid);
      match /users/{blockedUid} {
        allow read, write, delete: if sahip(uid);
      }
    }

    // Genel sohbet: giriş yapan okur/yazar, mesajı SADECE yazarı silebilir
    match /chat_messages/{msgId} {
      allow read: if girisli();
      allow create: if girisli() && request.resource.data.senderUid == request.auth.uid;
      allow delete: if girisli() && resource.data.senderUid == request.auth.uid;
      allow update: if false;
    }

    // Özel mesajlar: sadece konuşmanın tarafları
    match /dm_threads/{threadId} {
      allow read, write, delete: if girisli() &&
        request.auth.uid in resource.data.participants;
      allow create: if girisli() &&
        request.auth.uid in request.resource.data.participants;
      match /messages/{msgId} {
        allow read, create: if girisli();
        allow delete: if girisli();
        allow update: if false;
      }
    }

    // Moderasyon raporları: kullanıcı kendi raporunu oluşturur ve silebilir,
    // başkasınınkini okuyamaz (moderasyon Console/Admin SDK üzerinden yapılır)
    match /chat_reports/{reportId} {
      allow create: if girisli() && request.resource.data.reporterUid == request.auth.uid;
      allow read, delete: if girisli() && resource.data.reporterUid == request.auth.uid;
      allow update: if false;
    }
  }
}
```

> **Not:** `duel_rooms` üzerindeki `playerUids` dizisi tek alanlı bir
> `arrayContains` sorgusuyla kullanılıyor — Firestore bunu otomatik indeksler,
> elle composite index oluşturman gerekmez.

> `question_banks` koleksiyonunun **dolu olduğundan** da emin ol. Boşsa soru
> indirme sessizce gömülü yedek soru setine düşer — hata vermez ama havuz
> küçük kalır.

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
