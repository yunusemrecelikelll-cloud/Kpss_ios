# KPSS Hazırlık — iOS

Bu klasör, KPSS Hazırlık uygulamasının **sadece iOS** için hazırlanmış sürümüdür.
`Kpss_Telefon` klasöründeki ortak Flutter kod tabanından türetildi; `android/`,
`web/` ve `windows/` platform klasörleri kasıtlı olarak kaldırıldı — bu klasör
App Store'a yüklenecek iOS derlemesi için tek kaynaktır.

Android sürümü için `Kpss_Android` klasörüne bakın.

**Bu klasör bir Mac + Xcode gerektirir** (bkz. daha önce anlatılan Mac kurulum
rehberi). Widget extension (`DailyCodeWidget`) hâlâ Xcode'da elle tamamlanması
gereken bir target — bkz. `WIDGET_SETUP.md`.

## Derleme (Mac'te)

```
flutter pub get
cd ios && pod install && cd ..
flutter build ipa --release   # App Store Connect yüklemesi için
```

## Notlar

- `lib/`, `assets/` ve `pubspec.yaml` içeriği Kpss_Android ile birebir aynı
  tutulmalı — bundan sonraki özellik/hata düzeltme istekleri hem bu klasöre hem
  Kpss_Android'e aynı şekilde uygulanacak.
- Firebase/Ödeme/Widget kurulumu için kök dizindeki `FIREBASE_SETUP.md`,
  `IAP_SETUP.md`, `WIDGET_SETUP.md` dosyalarına bakın.
