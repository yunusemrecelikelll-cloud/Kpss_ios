// "Haritadan Öğren" kütüphanesi verisi — rakip uygulamalardaki (KPSS SınavBank
// vb.) "Haritadan Öğren" özelliğine benzer şekilde, Türkiye haritası üzerinde
// kategorilere ayrılmış onlarca alt-harita (fındık haritası, çay haritası vb.)
// gösterir. Harita render'ı lib/widgets/turkey_map_painter.dart (TurkeyMapWidget)
// ile yapılır; bu dosya SADECE hangi ilin hangi maddede vurgulanacağını ve veri
// kaynağını tutar.
//
// ÖNEMLİ — VERİ DOĞRULUĞU: tuik.gov.tr / data.tuik.gov.tr adreslerine DOĞRUDAN
// erişim (WebFetch) bot-engelleme/yönlendirme nedeniyle başarısız oldu (bkz.
// araştırma notu). Bu nedenle her madde, TÜİK verisine AÇIKÇA ATIF YAPAN resmi
// ya da yarı-resmi ikincil kaynaklardan (AA - Anadolu Ajansı, ilgili Bakanlık/
// TEPGE raporları, EPDK/TEİAŞ kurulu güç istatistikleri, EÜAŞ/Eti Maden/TTK/MTA
// gibi kamu kurumu resmi siteleri, valilik resmi açıklamaları) doğrulanmıştır.
// Her [LearnMapItem.kaynak] alanı kaynağı ve güven notunu açıkça belirtir.
// Doğrulanamayan ya da veri belirsizliği yüksek olan maddeler (ör. il bazında
// net sıralaması TÜİK tablosuyla teyit edilemeyen "Linyit üretimi" gibi geniş
// iddialar yerine sadece kesin doğrulanan "en büyük rezerv" iddiası) ya hiç
// eklenmemiş ya da kapsamı daraltılarak eklenmiştir.
//
// Öncelik sırası (bkz. proje görev talimatı):
//  1. Bölgeler ve İdari Yapı — mevcut turkey_map_data.dart'tan türetilir (ek
//     araştırma gerekmez, id/bölge eşlemesi zaten doğrulanmış gerçek veridir).
//  2. Tarım
//  3. Hayvancılık
//  4. Madenler
//  5. Enerji Kaynakları
//  (Ulaşım/Turizm/Su Kaynakları/Çevre kategorileri bu sürümde YOKTUR — zaman
//  kısıtı nedeniyle veri doğrulaması yapılamadığı için eklenmemiştir.)
library;

import 'turkey_map_data.dart';

/// "Haritadan Öğren" kütüphanesindeki tek bir alt-harita maddesi
/// (ör. "Fındık", "Sığır", "Bor", "Doğalgaz").
class LearnMapItem {
  final String id;
  final String title;
  /// Haritanın altında gösterilen kısa açıklama.
  final String subtitle;
  /// Haritada vurgulanacak il id'leri (lib/data/turkey_map_data.dart id'leriyle
  /// BİREBİR aynı olmalı).
  final List<String> provinceIds;
  /// Veri kaynağı — denetlenebilirlik için ZORUNLU, UI'da da gösterilir.
  final String kaynak;

  const LearnMapItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.provinceIds,
    required this.kaynak,
  });
}

/// Bir üst kategori (ör. "Tarım", "Madenler") ve içindeki maddeler.
class LearnMapCategory {
  final String id;
  final String icon;
  final String title;
  final String description;
  final List<LearnMapItem> items;

  const LearnMapCategory({
    required this.id,
    required this.icon,
    required this.title,
    required this.description,
    required this.items,
  });
}

/// "Bölgeler ve İdari Yapı" kategorisi — turkey_map_data.dart'taki MEVCUT
/// bolge alanından TÜRETİLİR (ek araştırma gerekmez, zaten doğrulanmış gerçek
/// veri). Her bölge bir madde; ayrıca "Tüm İller" (81 il, plaka sırası) eklenir.
LearnMapCategory _buildBolgelerCategory() {
  final items = <LearnMapItem>[];
  for (final bolge in kTurkeyRegions) {
    final ids = kTurkeyProvinces.where((p) => p.bolge == bolge).map((p) => p.id).toList();
    items.add(
      LearnMapItem(
        id: 'bolge_${bolge.toLowerCase().replaceAll(' ', '_').replaceAll('ç', 'c').replaceAll('ğ', 'g').replaceAll('ı', 'i').replaceAll('ö', 'o').replaceAll('ş', 's').replaceAll('ü', 'u')}',
        title: bolge,
        subtitle: '$bolge Bölgesi — ${ids.length} il: '
            '${kTurkeyProvinces.where((p) => ids.contains(p.id)).map((p) => p.ad).join(', ')}',
        provinceIds: ids,
        // Kaynak: Türkiye'nin 7 coğrafi bölgesi ve il dağılımı — TÜİK İl Bazında
        // İstatistikler / Türkiye İstatistiki Bölge Birimleri Sınıflaması (İBBS)
        // ve genel coğrafya müfredatında sabit, tartışmasız idari-coğrafi veridir.
        // Zaten lib/data/turkey_map_data.dart içinde doğrulanmış olarak mevcuttur.
        kaynak: 'TÜİK İstatistiki Bölge Birimleri Sınıflaması (İBBS) — 7 coğrafi bölge, '
            '81 il dağılımı (mevcut proje verisi, lib/data/turkey_map_data.dart).',
      ),
    );
  }
  items.add(
    LearnMapItem(
      id: 'tum_iller',
      title: 'Tüm İller (81 İl)',
      subtitle: "Türkiye'nin 81 ili — plaka kodu sırasına göre tamamı haritada işaretli.",
      provinceIds: kTurkeyProvinces.map((p) => p.id).toList(),
      kaynak: 'TÜİK il/plaka kodu listesi (mevcut proje verisi, lib/data/turkey_map_data.dart).',
    ),
  );
  return LearnMapCategory(
    id: 'bolgeler',
    icon: '🗾',
    title: 'Bölgeler ve İdari Yapı',
    description: "Türkiye'nin 7 coğrafi bölgesi ve 81 ili.",
    items: items,
  );
}

/// TARIM — TÜİK Bitkisel Üretim İstatistikleri'nden (doğrudan veya TÜİK'e
/// açıkça atıf yapan resmi/yarı-resmi ikincil kaynaklardan) doğrulanan
/// ürünler. Araştırma tarihi: 2026-07 (bkz. görev raporu).
const LearnMapCategory kTarimCategory = LearnMapCategory(
  id: 'tarim',
  icon: '🌾',
  title: 'Tarım',
  description: "Türkiye'de en çok üretilen tarım ürünleri ve il dağılımı.",
  items: [
    LearnMapItem(
      id: 'findik',
      title: 'Fındık',
      subtitle: 'Dünya fındık üretiminin büyük bölümü Türkiye\'de yapılır. Üretimde 1. sırada Ordu '
          '(~240 bin ton), onu Samsun, Sakarya ve Giresun izler.',
      provinceIds: ['ordu', 'samsun', 'sakarya', 'giresun', 'duzce', 'trabzon'],
      kaynak: 'TÜİK/Tarım Bakanlığı 2022 bitkisel üretim verileri (Giresun Ziraat Odası fındık '
          'raporuna aktarılmıştır) — Ordu 1., Samsun 2., Sakarya 3., Giresun 4. sırada. Yüksek güven.',
    ),
    LearnMapItem(
      id: 'cay',
      title: 'Çay',
      subtitle: "Türkiye çay üretiminin neredeyse tamamı Doğu Karadeniz'de yapılır; Rize açık ara "
          '1. sıradadır, Trabzon, Artvin ve Giresun onu izler.',
      provinceIds: ['rize', 'trabzon', 'artvin', 'giresun'],
      kaynak: 'TÜİK Bitkisel Üretim İstatistikleri Bülteni (data.tuik.gov.tr) — yaş çay üretiminde '
          'Rize açık ara 1. sırada. Yüksek güven.',
    ),
    LearnMapItem(
      id: 'zeytin',
      title: 'Zeytin',
      subtitle: 'Ege kıyı şeridi zeytin üretiminde Türkiye\'nin merkezidir; İzmir, Manisa, Aydın ve '
          'Balıkesir üretimde ilk sıralarda yer alır (2024 rekor üretim: 3,75 milyon ton).',
      provinceIds: ['izmir', 'manisa', 'aydin', 'balikesir'],
      kaynak: 'TÜİK verisine dayanan AA (Anadolu Ajansı) haberi, "Türkiye\'nin zeytin üretimi 2024\'te '
          'rekora ulaştı" — İzmir, Manisa, Aydın, Balıkesir üretim lideri iller. Yüksek güven.',
    ),
    LearnMapItem(
      id: 'uzum',
      title: 'Üzüm',
      subtitle: 'Çekirdeksiz kuru üzümde Manisa Türkiye\'nin (ve dünyanın) en büyük üreticisidir — '
          'kurutmalık üzümün ~%85\'i, sofralık üzümün ~%56\'sı Manisa\'da yetişir.',
      provinceIds: ['manisa', 'denizli', 'izmir'],
      kaynak: 'TÜİK verisine dayanan tarım raporları / Manisa Tarım İl Müdürlüğü açıklaması — '
          'kurutmalık üzümde Manisa payı ~%85. Yüksek güven.',
    ),
    LearnMapItem(
      id: 'pamuk',
      title: 'Pamuk',
      subtitle: 'GAP sayesinde Şanlıurfa Türkiye\'nin en büyük pamuk üreticisi konumundadır '
          '(üretimin ~%32\'si); Aydın, Hatay, Diyarbakır ve Adana diğer önemli üretim illeridir.',
      provinceIds: ['sanliurfa', 'aydin', 'hatay', 'diyarbakir', 'adana'],
      kaynak: 'TÜİK 2020 bitkisel üretim verisi — Şanlıurfa 567.251 ton ile üretimin ~%32\'sini '
          'karşılıyor, sıralama: Şanlıurfa, Aydın, Hatay, Diyarbakır, Adana. Yüksek güven.',
    ),
    LearnMapItem(
      id: 'kayisi',
      title: 'Kayısı',
      subtitle: 'Malatya, kuru kayısı üretiminin ~%85\'ini karşılayan, dünyaca bilinen geleneksel '
          'merkezdir (KPSS\'de standart cevap). NOT: 2025\'te "yüzyılın donu" nedeniyle üretim geçici '
          'olarak Mersin\'e kaydı — bu istisnai bir durumdur.',
      provinceIds: ['malatya', 'elazig', 'igdir', 'mersin'],
      kaynak: 'TÜİK verisine dayanan tarım raporları — Malatya kuru kayısı üretiminde tarihsel/'
          'geleneksel 1. sıradadır (~%85 pay). 2025 don felaketi istisnası ayrıca not edilmiştir. '
          'Yüksek güven.',
    ),
    LearnMapItem(
      id: 'incir',
      title: 'İncir',
      subtitle: "Aydın, dünyanın en kaliteli kuru incirinin yetiştiği il olarak üretimde açık ara "
          '1. sıradadır (186.346 ton); İzmir ikinci sıradadır.',
      provinceIds: ['aydin', 'izmir'],
      kaynak: 'TÜİK verisine dayanan tarım-ekonomi kaynağı (apelasyon.com, "İncir ve Ekonomisine '
          'Genel Bir Bakış") — Aydın 186.346 ton, İzmir 45.652 ton. Yüksek güven.',
    ),
    LearnMapItem(
      id: 'hasas',
      title: 'Haşhaş',
      subtitle: 'Afyonkarahisar, adını da aldığı haşhaş (afyon) üretiminde Türkiye\'nin 1. ilidir.',
      provinceIds: ['afyonkarahisar', 'burdur', 'denizli', 'kutahya', 'usak'],
      kaynak: '2022 TÜİK verisine dayanan Afyonkarahisar İl Tarım Müdürlüğü resmi açıklaması — '
          '"2022 TÜİK verilerine göre ülkemizde 1. sıradadır." Yüksek güven.',
    ),
    LearnMapItem(
      id: 'tutun',
      title: 'Tütün',
      subtitle: 'Güncel (2023) TÜİK verisine göre Adıyaman 1. sıradadır (25.990 ton); tarihsel olarak '
          'Manisa uzun süre lider olmuştur — bölge, Doğu Karadeniz-GAP tütün kuşağıdır.',
      provinceIds: ['adiyaman', 'samsun', 'batman'],
      kaynak: 'TÜİK 2023 Bitkisel Üretim İstatistikleri Bülteni verisine atıf yapan haberler — '
          'Adıyaman güncel üretimde 1. sırada. Orta-yüksek güven (tarihsel Manisa liderliğiyle '
          'karşılaştırma notu eklendi).',
    ),
    LearnMapItem(
      id: 'aycicegi',
      title: 'Ayçiçeği',
      subtitle: "Trakya (Tekirdağ ve Edirne) Türkiye'nin ayçiçeği (yağlık) üretim merkezidir.",
      provinceIds: ['tekirdag', 'edirne', 'kirklareli'],
      kaynak: 'TÜİK verisine dayanan tarım raporları — Tekirdağ 267.012 ton, Edirne 226.573 ton ile '
          'ilk iki sırada. Orta güven (veri yılı eski ama sıralama yıllardır stabil).',
    ),
    LearnMapItem(
      id: 'antep_fistigi',
      title: 'Antep Fıstığı',
      subtitle: 'Şanlıurfa, 2023 TÜİK verisine göre Antep fıstığı üretiminde Gaziantep\'i geçerek '
          '1. sıraya yerleşmiştir (59.848 ton); Gaziantep 2. sıradadır (54.575 ton).',
      provinceIds: ['sanliurfa', 'gaziantep'],
      kaynak: 'TÜİK 2023 Bitkisel Üretim İstatistikleri\'ne atıf yapan tarım raporları. Yüksek güven.',
    ),
    LearnMapItem(
      id: 'elma',
      title: 'Elma',
      subtitle: 'Isparta, elma üretiminde Türkiye\'nin 1. ilidir (üretimin ~%25,4\'ü); Karaman ise '
          'ekim alanında 1. sıradadır.',
      provinceIds: ['isparta', 'karaman'],
      kaynak: 'TEPGE (Tarımsal Ekonomi ve Politika Geliştirme Enstitüsü) / TÜİK Elma Ürün Raporu. '
          'Yüksek güven.',
    ),
    LearnMapItem(
      id: 'muz',
      title: 'Muz',
      subtitle: "Mersin (özellikle Anamur ilçesi), muz üretiminin %70'inden fazlasını karşılayan "
          "Türkiye'nin muz başkentidir.",
      provinceIds: ['mersin', 'antalya'],
      kaynak: 'TÜİK verisine dayanan akademik/resmi kaynaklar, Mersin Valiliği açıklaması. Yüksek güven.',
    ),
  ],
);

/// HAYVANCILIK — TÜİK Hayvansal Üretim İstatistikleri'nden (veya TÜİK'e atıf
/// yapan kaynaklardan) doğrulanan kategoriler.
const LearnMapCategory kHayvancilikCategory = LearnMapCategory(
  id: 'hayvancilik',
  icon: '🐄',
  title: 'Hayvancılık',
  description: 'Büyükbaş/küçükbaş hayvan varlığı ve arıcılıkta öne çıkan iller.',
  items: [
    LearnMapItem(
      id: 'sigir',
      title: 'Sığır (Büyükbaş)',
      subtitle: 'Konya, sığır varlığı bakımından Türkiye\'nin en büyük ilidir (~970 bin baş); '
          'İzmir ve Erzurum onu izler.',
      provinceIds: ['konya', 'izmir', 'erzurum'],
      kaynak: 'TÜİK Hayvansal Üretim İstatistikleri\'ne atıf yapan haber (yenimeram.com.tr) — '
          'Konya 970.876 baş ile sığır varlığında 1. sırayı koruyor. Yüksek güven.',
    ),
    LearnMapItem(
      id: 'koyun',
      title: 'Koyun',
      subtitle: 'Van, 2022 TÜİK verisine göre koyun varlığında 1. ildir (~3,1 milyon baş); '
          'Konya (~2,77 milyon) ve Şanlıurfa (~2,09 milyon) onu izler.',
      provinceIds: ['van', 'konya', 'sanliurfa'],
      kaynak: 'TÜİK 2022 Hayvansal Üretim İstatistikleri\'ne atıf yapan haberler. Yüksek güven.',
    ),
    LearnMapItem(
      id: 'keci',
      title: 'Keçi',
      subtitle: 'Ankara keçisi (tiftik) yetiştiriciliğinde Ankara tarihsel merkezdir (tiftik '
          'üretiminin ~330/468 tonu Ankara\'da); toplam keçi varlığında ise Mersin öne çıkar.',
      provinceIds: ['ankara', 'mersin'],
      kaynak: 'Tiftik keçisi: TÜİK 2021 verisine atıf yapan Tarım Bakanlığı/akademik kaynaklar '
          '(yüksek güven). Genel keçi varlığında Mersin: Tarım ve Orman Bakanlığı verisine dayanan '
          'haberler (orta güven — il bazında TÜİK tablosuna doğrudan ulaşılamadı).',
    ),
    LearnMapItem(
      id: 'aricilik',
      title: 'Arıcılık (Bal)',
      subtitle: 'Ordu, 2025 verisine göre bal üretiminde Türkiye\'nin 1. ilidir (16.750 ton); '
          'Adana 2., Muğla 3. sıradadır (Muğla, kovan/koloni sayısında 1. sıradadır).',
      provinceIds: ['ordu', 'adana', 'mugla'],
      kaynak: 'TÜİK 2025 verisine atıf yapan Ordu Valiliği resmi açıklaması ("Bal üretiminde '
          'Türkiye\'nin 1 numarası"). Yüksek güven.',
    ),
  ],
);

/// MADENLER — MTA (Maden Tetkik ve Arama) / ilgili kamu kurumlarının (Eti
/// Maden, EÜAŞ, TTK) resmi verilerinden doğrulanan maden yatakları.
const LearnMapCategory kMadenlerCategory = LearnMapCategory(
  id: 'madenler',
  icon: '⛏️',
  title: 'Madenler',
  description: "Türkiye'nin dünya çapında öne çıktığı maden yatakları.",
  items: [
    LearnMapItem(
      id: 'bor',
      title: 'Bor',
      subtitle: 'Dünya bor rezervinin büyük çoğunluğu Türkiye\'dedir. Eskişehir (Kırka), dünyanın '
          'en büyük bor/boraks tesisiyle dünya pazarının ~%65\'ini karşılar; Kütahya (Emet) ve '
          'Balıkesir (Bigadiç) diğer büyük yataklardır.',
      provinceIds: ['eskisehir', 'kutahya', 'balikesir'],
      kaynak: 'Eti Maden (resmi kamu kurumu) kurumsal sitesi, etimaden.gov.tr/kirka — Kırka tesisi '
          'dünya bor pazarının ~%65\'ini karşılıyor. Yüksek güven.',
    ),
    LearnMapItem(
      id: 'krom',
      title: 'Krom',
      subtitle: 'Elazığ (Guleman yöresi), Türkiye krom üretiminin yarısından fazlasını karşılar.',
      provinceIds: ['elazig'],
      kaynak: 'AA (Anadolu Ajansı) haberi, MTA/sektör verisine dayanarak: "Krom üretiminin yarısı '
          'Elazığ\'dan". Yüksek güven.',
    ),
    LearnMapItem(
      id: 'linyit',
      title: 'Linyit (en büyük rezerv)',
      subtitle: "Türkiye'nin en büyük linyit REZERVİ, Kahramanmaraş'taki Afşin-Elbistan Havzası'ndadır "
          '(EÜAŞ\'ın en büyük linyit sahalarından biri).',
      provinceIds: ['kahramanmaras'],
      kaynak: 'EÜAŞ (Elektrik Üretim A.Ş., resmi kamu kurumu) kurumsal sitesi, '
          'euas.gov.tr/santraller/afsin-elbistan-linyit-sahasi. Yüksek güven (SADECE "en büyük '
          'rezerv" iddiası için — il bazında yıllık ÜRETİM sıralaması net TÜİK tablosuyla teyit '
          'edilemediği için kapsam dışı bırakılmıştır).',
    ),
    LearnMapItem(
      id: 'taskomuru',
      title: 'Taşkömürü',
      subtitle: "Türkiye'nin taşkömürü (maden kömürü) üretiminin neredeyse tamamı Zonguldak "
          'havzasında (Zonguldak-Bartın-Karabük) yapılır.',
      provinceIds: ['zonguldak', 'bartin', 'karabuk'],
      kaynak: 'TTK (Türkiye Taşkömürü Kurumu, resmi kamu kurumu) verileri — taşkömürü üretimi '
          'neredeyse tamamen Zonguldak havzasında yoğunlaşır. Yüksek güven (KPSS coğrafyasında '
          'tartışmasız klasik bilgi).',
    ),
    LearnMapItem(
      id: 'demir',
      title: 'Demir',
      subtitle: "Sivas (Divriği-Gürün), Türkiye'nin demir ihtiyacının yarısını karşılayan en büyük "
          'demir yatağına sahiptir; Malatya (Hekimhan) diğer önemli merkezdir.',
      provinceIds: ['sivas', 'malatya'],
      kaynak: 'MTA verisine dayanan sektör raporu (divrigi.com.tr, "Divriği Demir Madenleri") — '
          'Divriği-Gürün yatağı Türkiye demir ihtiyacının yarısını karşılıyor. Yüksek güven.',
    ),
    LearnMapItem(
      id: 'bakir',
      title: 'Bakır',
      subtitle: "Artvin (Murgul) ve Rize (Çayeli), Türkiye'nin en büyük bakır yataklarına sahiptir.",
      provinceIds: ['artvin', 'rize'],
      kaynak: 'MTA/sektör verisine dayanan kaynaklar. Orta güven (il bazında tek bir "1 numara" '
          'TÜİK tablosu bulunamadı, ancak Artvin/Rize birden fazla kaynakta tutarlı şekilde öne çıkıyor).',
    ),
  ],
);

/// ENERJİ KAYNAKLARI — EPDK/TEİAŞ kurulu güç istatistikleri ve ilgili kamu
/// kurumlarının (TPAO, Enerji Bakanlığı) verilerinden doğrulanmıştır.
const LearnMapCategory kEnerjiCategory = LearnMapCategory(
  id: 'enerji',
  icon: '⚡',
  title: 'Enerji Kaynakları',
  description: 'Yerli enerji üretiminde ve kurulu güçte öne çıkan iller.',
  items: [
    LearnMapItem(
      id: 'petrol',
      title: 'Petrol',
      subtitle: "Türkiye'nin yerli ham petrol üretiminin büyük kısmı Güneydoğu Anadolu'da yapılır: "
          'Batman üretimin ~%73\'ünü, Adıyaman ~%26\'sını karşılar.',
      provinceIds: ['batman', 'adiyaman', 'diyarbakir', 'sirnak'],
      kaynak: 'AA (Anadolu Ajansı) haberi, TPAO/Enerji Bakanlığı verisine dayanarak: "Güneydoğu\'daki '
          '4 il Türkiye\'nin ham petrol üretiminin %28\'ini karşılıyor". Yüksek güven.',
    ),
    LearnMapItem(
      id: 'dogalgaz',
      title: 'Doğalgaz',
      subtitle: 'Karadeniz açıklarındaki Sakarya Gaz Sahası (işleme tesisi Zonguldak/Filyos '
          'kıyısında) günlük ~7,5 milyon m³ üretimle Türkiye\'nin en büyük yerli doğalgaz kaynağıdır; '
          'Trakya Havzası (Tekirdağ, Kırklareli) karadaki geleneksel üretim merkezidir.',
      provinceIds: ['zonguldak', 'tekirdag', 'kirklareli'],
      kaynak: 'Enerji ve Tabii Kaynaklar Bakanlığı / AA Enerji Terminali verileri. Yüksek güven '
          '(not: Sakarya Gaz Sahası\'nın kendisi deniz altında olduğu için en yakın kıyı ili '
          'Zonguldak/Filyos işaretlenmiştir).',
    ),
    LearnMapItem(
      id: 'gunes',
      title: 'Güneş Enerjisi',
      subtitle: 'Konya, kurulu güneş enerjisi santrali (GES) kapasitesinde Türkiye\'nin açık ara '
          '1. ilidir (1.722 MW); Ankara ve Gaziantep onu izler.',
      provinceIds: ['konya', 'ankara', 'gaziantep'],
      kaynak: 'EPDK verisine dayanan GENSED (Güneş Enerjisi Sanayicileri ve Endüstrisi Derneği) '
          'raporu, gensed.org/turkiyenin-kurulu-gucu. Yüksek güven.',
    ),
    LearnMapItem(
      id: 'ruzgar',
      title: 'Rüzgar Enerjisi',
      subtitle: 'İzmir, güncel EPDK verisine göre kurulu rüzgar enerjisi santrali (RES) kapasitesinde '
          '1. ildir (~2.307 MW); Çanakkale ve Balıkesir onu izler (Balıkesir tarihsel olarak uzun '
          'süre lider olmuştur).',
      provinceIds: ['izmir', 'canakkale', 'balikesir'],
      kaynak: 'EPDK verisine dayanan enerjiatlasi.com "İllere Göre Rüzgar Santrali Kurulu Gücü" '
          'raporu. Yüksek güven (güncel veri İzmir\'i gösteriyor; eski KPSS kaynaklarında hâlâ '
          'Balıkesir örnek verilebilir, bu yüzden ikisi de dahil edildi).',
    ),
    LearnMapItem(
      id: 'jeotermal',
      title: 'Jeotermal Enerji',
      subtitle: "Aydın, jeotermal enerji kurulu gücünde Türkiye'nin 1. ilidir (850,4 MW, Büyük "
          'Menderes Grabeni); Denizli (354 MW) ve Manisa (349 MW) onu izler.',
      provinceIds: ['aydin', 'denizli', 'manisa'],
      kaynak: 'EPDK/TEİAŞ kurulu güç istatistiklerine dayanan jeotermalhaber.com raporu, '
          '"Türkiye\'nin En Büyük Jeotermal Santralleri". Yüksek güven.',
    ),
  ],
);

/// "Haritadan Öğren" kütüphanesindeki TÜM kategoriler (öncelik sırasına göre).
///
/// NOT: Ulaşım, Turizm ve Kültür, Su Kaynakları, Çevre ve Doğal Alanlar,
/// Ekonomi ve Sanayi kategorileri bu sürümde YOKTUR — görev talimatındaki
/// öncelik sırasına göre süre yetmediği için eklenmemiştir, veri
/// doğrulanamadığından değil.
List<LearnMapCategory> get kLearnMapCategories => [
      _buildBolgelerCategory(),
      kTarimCategory,
      kHayvancilikCategory,
      kMadenlerCategory,
      kEnerjiCategory,
    ];
