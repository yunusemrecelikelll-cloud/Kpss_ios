# KPSS Hazırlık — Playable Ads (Oynanabilir Reklamlar)

Reklamlarda gösterilecek, başka uygulamaları kullanan kişilerin **reklam içinde oynayabileceği**
kendi kendine yeten (self-contained) HTML5 mini oyunlar. Sadece **Apple (App Store)** hedefi
içindir; Android sonra.

## Dosyalar
- `kpss_guncel_reklam.html` — **Kart Oyunu V2 / Güncel Bilgiler** temalı hızlı quiz (5 soru →
  skor → "Ücretsiz İndir" CTA).
- `kpss_solitaire_reklam.html` — **Eşleştirme Solitaire (Kolay)** temalı dokun-eşleştir
  (terimleri doğru kategoriye yerleştir → bitince CTA).

Her ikisi de tek HTML dosyasıdır: tüm CSS/JS gömülü, **dış ağ isteği yok** (playable ad kuralı).
Dikey (portrait), mobil dokunmatik.

## Yayınlamadan ÖNCE yapılacak (tek zorunlu adım)
Her iki dosyanın içindeki şu satırı **gerçek App Store linkinle** değiştir:
```js
var STORE_URL = 'https://apps.apple.com/app/id0000000000'; /* TODO */
```
`id0000000000` yerine uygulamanın App Store kimliği (App Store Connect → uygulaman → App
Store bilgisi → "Apple ID" veya paylaşım linkindeki `id##########`).

> Not: Google Ads / AdMob playable akışında CTA'ya basınca mağaza kampanya tarafından açılır;
> `STORE_URL` yalnızca **yedek** (fallback) içindir. CTA köprüsü AdMob (`mraid.open`),
> Google Ads (`ExitApi.exit`), Meta (`FbPlayableAd.onCTAClick`) ve düz `window.open` — hepsini
> sırayla dener, ağ farkı için ek düzenleme gerekmez.

## Nereye yüklenir
- **Google Ads** (App kampanyası → Öğeler → HTML5 / "Reklam öğesi ekle" → HTML5 yükle) VEYA
- **AdMob** doğrudan playable desteklemez; playable'lar genelde **Google Ads App kampanyası**
  ya da **Meta Audience Network / Unity / ironSource** üzerinden yayınlanır.
- Dosyayı `.html` olarak (gerekiyorsa `.zip` içinde tek index.html) yükle. Boyut sınırı
  genelde ≤ 5 MB (bu dosyalar birkaç KB).

## Test
Herhangi bir tarayıcıda dosyayı aç, telefon boyutunda oyna. CTA masaüstünde `window.open`
ile mağaza linkini açar.
