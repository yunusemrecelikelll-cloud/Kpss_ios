# İllüstrasyonlar

Tasarımdaki 3B görseller (kum saati, roket, kupa, taç, klasör) buraya konur.

Kod tarafı **zaten hazır**: `DsIllustration` bileşeni (bkz.
`lib/theme/design_system.dart`) bir `asset` yolu verildiğinde onu çizer,
verilmediğinde ya da dosya bulunamadığında sessizce büyük emojiye düşer.
Yani bu klasör boşken de uygulama sorunsuz çalışır.

## Görsel eklemek

1. PNG dosyasını (şeffaf zemin, kare, en az 512×512 önerilir) buraya koy.
2. İlgili ekranda `DsIllustration`/`DsHeroCard` çağrısına asset yolunu ver:

   ```dart
   DsHeroCard(
     illustrationEmoji: '🚀',
     illustrationAsset: 'assets/images/roket.png',
     ...
   )
   ```

`pubspec.yaml` içinde `assets/images/` klasörü zaten kayıtlı — yeni dosya
eklerken pubspec'e dokunmana gerek yok, sadece `flutter pub get` çalıştır.

## Beklenen dosyalar

Ekranlardaki emoji karşılıkları (istediğini eklersin, hepsi zorunlu değil):

| Nerede | Emoji | Önerilen dosya adı |
|---|---|---|
| Anasayfa — sınav geri sayımı | ⏳ | `kumsaati.png` |
| Anasayfa — Tam Deneme Sınavı | 🚀 | `roket.png` |
| Anasayfa — KPSS Düello | 🏆 | `kupa.png` |
| Premium ekranı | 👑 | `tac.png` |
| Ders sınavı kartı | 🗂️ | `klasor.png` |
