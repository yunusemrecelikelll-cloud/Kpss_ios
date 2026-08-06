# KPSS Hazırlık — Playable Ads (Oynanabilir Reklamlar)

Reklamlarda gösterilecek, başka uygulamaları kullanan kişilerin **reklam içinde
oynayabileceği** kendi kendine yeten (self-contained) HTML5 mini oyunlar.
Tasarımları uygulamanın içindeki oyunlarla **birebir aynıdır** (aynı renkler,
kart stilleri, yerleşim). Sadece **Apple (App Store)** hedefi içindir; Android sonra.

## Dosyalar
- `kpss_solitaire_reklam.html` — **Eşleştirme Solitaire** reklamı.
  Uygulamadaki gibi yeşil keçe masa (#0F6B3E), krem + altın kenarlı kartlar
  (#FAF3E4 / #F5B942), 🎯 hedef kategori slotları ve mavi kart sırtı destesi.
  Oyna: bir terim kartını seç, doğru kategoriye dokun → hepsi yerleşince CTA.
- `kpss_kartoyunu_v2_reklam.html` — **Kart Oyunu V2** reklamı.
  Uygulamadaki gibi Pembe Rüya teması (#FFF0F6), iki sütun (terim ↔ tanım);
  doğru eşleşen çiftler **renkli bir okla** birleşir, yanlış = kırmızı sarsıntı.
  İçerik: Güncel Bilgiler eşleştirmeleri.

Her ikisi de tek HTML dosyasıdır: tüm CSS/JS gömülü, **dış ağ isteği yok**
(playable ad kuralı). Dikey (portrait), mobil dokunmatik. Üzerlerinde uygulamaya
çeken yazılar ve "Ücretsiz İndir" CTA'sı vardır.

## Yayınlamadan ÖNCE yapılacak (tek zorunlu adım)
Her iki dosyanın içindeki şu satırı **gerçek App Store linkinle** değiştir:
```js
var STORE_URL = 'https://apps.apple.com/app/id0000000000'; /* TODO */
```
`id0000000000` yerine uygulamanın App Store kimliği (App Store Connect → uygulaman
→ App Store bilgisi → "Apple ID" ya da paylaşım linkindeki `id##########`).

> Not: Google Ads / AdMob playable akışında CTA'ya basınca mağaza kampanya
> tarafından açılır; `STORE_URL` yalnızca **yedek** (fallback) içindir. CTA köprüsü
> AdMob (`mraid.open`), Google Ads (`ExitApi.exit`), Meta (`FbPlayableAd.onCTAClick`)
> ve düz `window.open` — hepsini sırayla dener, ağ farkı için ek düzenleme gerekmez.

## Nereye yüklenir
- **Google Ads** (App kampanyası → Öğeler → HTML5 / "Reklam öğesi ekle" → HTML5 yükle) VEYA
- **Meta / Unity / ironSource** gibi playable destekleyen ağlar.
- AdMob doğrudan playable almaz; playable'lar genelde Google Ads App kampanyası
  ya da yukarıdaki ağlar üzerinden yayınlanır.
- Dosyayı `.html` olarak (gerekirse `.zip` içinde tek index.html) yükle. Boyut
  sınırı genelde ≤ 5 MB (bu dosyalar birkaç KB).

## Test
Herhangi bir tarayıcıda dosyayı aç, telefon boyutunda oyna. CTA masaüstünde
`window.open` ile mağaza linkini açar.
