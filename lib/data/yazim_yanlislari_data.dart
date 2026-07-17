/// "Yazım Yanlışları" mini oyunu için veri modeli ve GERÇEK, KPSS Türkçe
/// müfredatında sık çıkan yazım hataları.
///
/// Her [YazimYanlisi], TDK yazım kurallarına göre DOĞRU yazılmış biçim ile
/// günlük yazışmalarda SIKÇA karşılaşılan YANLIŞ biçimi bir arada tutar.
/// Kurgu/uydurma "yaygın hata" YOKTUR — tamamı gerçek Türkçe dilbilgisi
/// kurallarına dayanır: bitişik/ayrı yazım, "de/da" ve "ki" bağlaçlarının
/// ayrı yazımı, kesme işareti kullanımı, ünlü daralması (-yor eki), ünsüz
/// benzeşmesi (sertleşme) ve ünsüz yumuşaması, yabancı kökenli kelimelerin
/// yazımı.
class YazimYanlisi {
  final String dogru;
  final String yanlis;

  const YazimYanlisi({required this.dogru, required this.yanlis});
}

const List<YazimYanlisi> kYazimYanlislari = [
  // ── Bitişik / ayrı yazım ──
  YazimYanlisi(dogru: 'yalnız', yanlis: 'yanlız'),
  YazimYanlisi(dogru: 'yanlış', yanlis: 'yalnış'),
  YazimYanlisi(dogru: 'yanlışlıkla', yanlis: 'yalnışlıkla'),
  YazimYanlisi(dogru: 'yalnızca', yanlis: 'yanlızca'),
  YazimYanlisi(dogru: 'herkes', yanlis: 'herkez'),
  YazimYanlisi(dogru: 'herkese', yanlis: 'herkeze'),
  YazimYanlisi(dogru: 'birkaç', yanlis: 'bir kaç'),
  YazimYanlisi(dogru: 'birçok', yanlis: 'bir çok'),
  YazimYanlisi(dogru: 'biraz', yanlis: 'bir az'),
  YazimYanlisi(dogru: 'her şey', yanlis: 'herşey'),
  YazimYanlisi(dogru: 'hiçbir', yanlis: 'hiç bir'),
  YazimYanlisi(dogru: 'hiçbir şey', yanlis: 'hiçbirşey'),
  YazimYanlisi(dogru: 'herhangi', yanlis: 'her hangi'),
  YazimYanlisi(dogru: 'hiç kimse', yanlis: 'hiçkimse'),
  YazimYanlisi(dogru: 'şu an', yanlis: 'şuan'),
  YazimYanlisi(dogru: 'her zaman', yanlis: 'herzaman'),
  YazimYanlisi(dogru: 'her yer', yanlis: 'heryer'),
  YazimYanlisi(dogru: 'her an', yanlis: 'heran'),
  YazimYanlisi(dogru: 'her gün', yanlis: 'hergün'),
  YazimYanlisi(dogru: 'her türlü', yanlis: 'hertürlü'),
  YazimYanlisi(dogru: 'bir sürü', yanlis: 'birsürü'),
  YazimYanlisi(dogru: 'ne kadar', yanlis: 'nekadar'),
  YazimYanlisi(dogru: 'o kadar', yanlis: 'okadar'),
  YazimYanlisi(dogru: 'bu kadar', yanlis: 'bukadar'),
  YazimYanlisi(dogru: 'belki', yanlis: 'bel ki'),
  YazimYanlisi(dogru: 'çünkü', yanlis: 'çünki'),

  // ── "de/da" bağlacının ayrı yazımı ──
  YazimYanlisi(dogru: 'bir de', yanlis: 'birde'),
  YazimYanlisi(dogru: 'ben de', yanlis: 'bende'),
  YazimYanlisi(dogru: 'sen de', yanlis: 'sende'),
  YazimYanlisi(dogru: 'o da', yanlis: 'oda'),
  YazimYanlisi(dogru: 'bunu da', yanlis: 'bunuda'),
  YazimYanlisi(dogru: 'biz de', yanlis: 'bizde'),

  // ── Özel isimlere gelen eklerde kesme işareti ──
  YazimYanlisi(dogru: "Ahmet'in", yanlis: 'Ahmetin'),
  YazimYanlisi(dogru: "Türkiye'de", yanlis: 'Türkiyede'),
  YazimYanlisi(dogru: "İstanbul'a", yanlis: 'İstanbula'),
  YazimYanlisi(dogru: "Ankara'dan", yanlis: 'Ankaradan'),
  YazimYanlisi(dogru: "Atatürk'ün", yanlis: 'Atatürkün'),

  // ── Ünlü daralması (-yor eki: a/e > ı/i/u/ü) ──
  YazimYanlisi(dogru: 'başlıyor', yanlis: 'başlayor'),
  YazimYanlisi(dogru: 'bekliyor', yanlis: 'bekleyor'),
  YazimYanlisi(dogru: 'oynuyor', yanlis: 'oynayor'),
  YazimYanlisi(dogru: 'söylüyor', yanlis: 'söyleyor'),
  YazimYanlisi(dogru: 'ağlıyor', yanlis: 'ağlayor'),
  YazimYanlisi(dogru: 'izliyor', yanlis: 'izleyor'),
  YazimYanlisi(dogru: 'anlıyor', yanlis: 'anlayor'),
  YazimYanlisi(dogru: 'yaşıyor', yanlis: 'yaşayor'),

  // ── Ünsüz benzeşmesi (sert ünsüzden sonra ekin sertleşmesi: c/d/g > ç/t/k) ──
  YazimYanlisi(dogru: 'kitapçı', yanlis: 'kitapcı'),
  YazimYanlisi(dogru: 'uçaktan', yanlis: 'uçakdan'),
  YazimYanlisi(dogru: 'kaçta', yanlis: 'kaçda'),
  YazimYanlisi(dogru: 'sokakta', yanlis: 'sokakda'),
  YazimYanlisi(dogru: 'kitapta', yanlis: 'kitapda'),
  YazimYanlisi(dogru: 'çiçekçi', yanlis: 'çiçekci'),
  YazimYanlisi(dogru: 'gençtir', yanlis: 'gençdir'),
  YazimYanlisi(dogru: 'aşçı', yanlis: 'aşcı'),
  YazimYanlisi(dogru: 'simitçi', yanlis: 'simitci'),

  // ── Ünsüz yumuşaması (ünlüyle başlayan ek gelince p/ç/t/k > b/c/d/ğ) ──
  YazimYanlisi(dogru: 'kitabı', yanlis: 'kitapı'),
  YazimYanlisi(dogru: 'ağacı', yanlis: 'ağaçı'),
  YazimYanlisi(dogru: 'sokağa', yanlis: 'sokaka'),
  YazimYanlisi(dogru: 'kaydı', yanlis: 'kayıtı'),
  YazimYanlisi(dogru: 'rengi', yanlis: 'renki'),
  YazimYanlisi(dogru: 'kağıdı', yanlis: 'kağıtı'),
  YazimYanlisi(dogru: 'yurdu', yanlis: 'yurtu'),
  YazimYanlisi(dogru: 'çocuğu', yanlis: 'çocuku'),

  // ── Yabancı kökenli kelimelerin yazımı ──
  YazimYanlisi(dogru: 'orijinal', yanlis: 'orjinal'),
  YazimYanlisi(dogru: 'aynı', yanlis: 'ayni'),
  YazimYanlisi(dogru: 'maalesef', yanlis: 'malesef'),
  YazimYanlisi(dogru: 'şoför', yanlis: 'şöför'),
  YazimYanlisi(dogru: 'şarj', yanlis: 'şarz'),
  YazimYanlisi(dogru: 'kuaför', yanlis: 'kuafor'),
  YazimYanlisi(dogru: 'enteresan', yanlis: 'enterasan'),
  YazimYanlisi(dogru: 'restoran', yanlis: 'restorant'),
  YazimYanlisi(dogru: 'entelektüel', yanlis: 'entellektüel'),
  YazimYanlisi(dogru: 'profesyonel', yanlis: 'proffesyonel'),
  YazimYanlisi(dogru: 'sürpriz', yanlis: 'sürpiriz'),
  YazimYanlisi(dogru: 'egzoz', yanlis: 'eksoz'),
  YazimYanlisi(dogru: 'ambulans', yanlis: 'anbulans'),
  YazimYanlisi(dogru: 'pantolon', yanlis: 'pantalon'),
  YazimYanlisi(dogru: 'aktüel', yanlis: 'aktuel'),
  YazimYanlisi(dogru: 'hakkında', yanlis: 'hakkinda'),
];
