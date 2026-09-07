# KPSS Hazırlık — Playable Ads (Oynanabilir Reklamlar)

Reklamlarda gösterilecek, başka uygulamaları kullanan kişilerin **reklam içinde
oynayabileceği** kendi kendine yeten (self-contained) HTML5 mini oyunlar.
Tasarımları uygulamanın içindeki oyunlarla **birebir aynıdır** (aynı renkler,
kart stilleri, yerleşim). Sadece **Apple (App Store)** hedefi içindir; Android sonra.

Tasarım, boyut, kart sayısı, sayaçlar ve içerik uygulamadaki oyunlarla **birebir aynıdır**.

## Dosyalar
- `kpss_solitaire_reklam.html` — **Eşleştirme Solitaire** (Kolay) reklamı.
  Yeşil keçe masa (#0F6B3E), krem + altın kenarlı kartlar (#FAF3E4/#F5B942),
  mavi kart sırtı destesi. **5 gerçek Türkçe kategori** (Sözcük Türleri, Ses
  Olayları, Zamir Çeşitleri, Cümlenin Ögeleri, Fiil Çatısı) = **30 kart**,
  **75 hamle** bütçesi. Üstte gerçek sayaçlar: 🎯 Karışık, 🪙 coin, Kalan Hamle,
  🎴 Kalan kart. 5 hedef slot + 5 tableau sütunu + "Çek" destesi + alt araç
  çubuğu (İpucu/Geri Al/Market). Kartı tutup sürükle ya da dokun-seç.
- `kpss_kartoyunu_v2_reklam.html` — **Kart Oyunu V2** reklamı.
  Pembe Rüya teması (#FFF0F6), iki sütun **8'er kart**, **3 zor bölüm**
  (Tarih / Coğrafya / İnkılap), bölüm bitince sıradaki gelir. Doğru eşleşme
  **renkli okla** birleşir. Sınırsız (yanlış/bitiş yok).
- `kpss_dogru_yanlis_reklam.html` — **Doğru mu Yanlış mı?** reklamı.
  Tinder tarzı kaydırmalı: kartı **sağa = DOĞRU** (teal), **sola = YANLIŞ**
  (kırmızı); eğilme + damga + son-cevap şeridi + alt DOĞRU/YANLIŞ butonları.
  İlk açılışta kartın sağa/sola hareket ettiği **ipucu animasyonu** oynar.
  16 gerçek önerme (8 doğru + 8 yanlış). Üstte ve altta CTA yazıları.
- `kpss_yazim_yanlislari_reklam.html` — **Yazım Yanlışları** reklamı.
  8 sn **geri sayım halkası**, "Doğru yazımı seç", 2 seçenek (doğru ↔ yaygın
  yanlış). Yanlış/süre dolunca doğrusu kırmızı panelde. 16 gerçek TDK çifti
  (yalnız/yanlız, herkes/herkez, Türkiye'de/Türkiyede…).

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
