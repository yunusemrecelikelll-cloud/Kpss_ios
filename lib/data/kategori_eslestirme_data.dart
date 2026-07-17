/// "Kategori Eşleştirme Solitaire" mini oyunu için veri modeli ve GERÇEK,
/// KPSS müfredatında (Türkçe / Matematik / Tarih / Coğrafya / Vatandaşlık)
/// gerçekten sorulan sınıflandırma/gruplama konuları.
///
/// Her [KategoriGrubu], bir başlık ([kategoriAdi]), hangi derse ait olduğu
/// ([ders]) ve o kategoriye AİT olan üye terimlerin ([terimler]) listesinden
/// oluşur. Oyunda oyuncu bir terim kartını doğru kategoriye eşleştirir.
///
/// ÖNEMLİ: Buradaki tüm eşleşmeler GERÇEK ders bilgisiyle doğrulanmıştır;
/// uydurma/yanlış sınıflandırma yoktur. Bu bir eğitim uygulaması olduğundan
/// her terimin gerçekten ilgili kategoriye ait olması esastır.
class KategoriGrubu {
  /// Hedef kategori başlığı (ör. "Sözcük Türleri").
  final String kategoriAdi;

  /// Kategorinin ait olduğu ders (ör. "Türkçe").
  final String ders;

  /// Bu kategoriye ait GERÇEK üye terimler.
  final List<String> terimler;

  const KategoriGrubu({
    required this.kategoriAdi,
    required this.ders,
    required this.terimler,
  });
}

/// NOT (zorluk): Bazı kategorilerde üye terimler kategori başlığının kendi
/// kelimesini birebir içeriyordu (ör. "Ortalama Türleri" altında "Geometrik
/// Ortalama") — bu, oyuncunun anlamı bilmeden salt ortak kelimeyi görüp
/// kategoriyi tahmin etmesine ("ipucu sızıntısı") yol açıyordu. Bu yüzden bu
/// tür terimler bilinçli olarak KISALTILMIŞTIR (ör. sadece "Geometrik") —
/// eksik/yarım bırakılmış değildir. Kısaltırken başka bir kategoriyle metin
/// çakışması (iki farklı kategoride aynı görünen kart) oluşmaması için bazı
/// terimler bilerek TAM haliyle bırakılmıştır (ör. "Soru Zamiri", "İdare
/// Mahkemeleri") — bunlar da unutulmuş değildir.
///
/// KPSS gruplama/sınıflandırma setleri — 5 dersten toplam 76 kategori.
const List<KategoriGrubu> kKategoriGruplari = [
  // ─────────────────────────── TÜRKÇE ───────────────────────────
  KategoriGrubu(
    kategoriAdi: 'Sözcük Türleri',
    ders: 'Türkçe',
    terimler: ['İsim', 'Fiil', 'Sıfat', 'Zamir', 'Zarf', 'Edat', 'Bağlaç', 'Ünlem'],
  ),
  KategoriGrubu(
    kategoriAdi: 'Ses Olayları',
    ders: 'Türkçe',
    terimler: [
      'Ünlü Düşmesi',
      'Ünlü Daralması',
      'Ünsüz Yumuşaması',
      'Ünsüz Benzeşmesi',
      'Ünsüz Türemesi',
      'Ulama',
      'Kaynaştırma',
    ],
  ),
  KategoriGrubu(
    kategoriAdi: 'Zamir (Adıl) Çeşitleri',
    ders: 'Türkçe',
    terimler: [
      'Kişi',
      'İşaret',
      'Soru Zamiri',
      'Belgisiz',
      'İlgi',
      'Dönüşlülük',
    ],
  ),
  KategoriGrubu(
    kategoriAdi: 'Cümlenin Ögeleri',
    ders: 'Türkçe',
    terimler: ['Özne', 'Yüklem', 'Nesne', 'Dolaylı Tümleç', 'Zarf Tümleci'],
  ),
  KategoriGrubu(
    kategoriAdi: 'Fiil Çatısı (Özne-Yüklem İlişkisi)',
    ders: 'Türkçe',
    terimler: ['Etken', 'Edilgen', 'Dönüşlü', 'İşteş'],
  ),

  // ─────────────────────────── MATEMATİK ───────────────────────────
  KategoriGrubu(
    kategoriAdi: 'Açı Türleri',
    ders: 'Matematik',
    terimler: ['Dar', 'Dik', 'Geniş', 'Doğru', 'Tam'],
  ),
  KategoriGrubu(
    kategoriAdi: 'Üçgen Türleri (Kenarlarına Göre)',
    ders: 'Matematik',
    terimler: ['Eşkenar', 'İkizkenar', 'Çeşitkenar'],
  ),
  KategoriGrubu(
    kategoriAdi: 'Üçgen Türleri (Açılarına Göre)',
    ders: 'Matematik',
    terimler: ['Dar Açılı', 'Dik Açılı', 'Geniş Açılı'],
  ),
  KategoriGrubu(
    kategoriAdi: 'Sayı Kümeleri',
    ders: 'Matematik',
    terimler: [
      'Doğal Sayılar',
      'Tam Sayılar',
      'Rasyonel Sayılar',
      'İrrasyonel Sayılar',
      'Reel Sayılar',
    ],
  ),
  KategoriGrubu(
    kategoriAdi: 'Dörtgen Çeşitleri',
    ders: 'Matematik',
    terimler: [
      'Kare',
      'Dikdörtgen',
      'Paralelkenar',
      'Eşkenar Dörtgen',
      'Yamuk',
      'Deltoid',
    ],
  ),

  // ─────────────────────────── TARİH ───────────────────────────
  KategoriGrubu(
    kategoriAdi: 'İlk Türk Devletleri (İslamiyet Öncesi)',
    ders: 'Tarih',
    terimler: [
      'Asya Hun',
      'Avrupa Hun',
      'Göktürk',
      'Uygurlar',
      'Avarlar',
      'Hazarlar',
      'Kırgızlar',
      'Türgişler',
    ],
  ),
  KategoriGrubu(
    kategoriAdi: 'İlk Türk-İslam Devletleri',
    ders: 'Tarih',
    terimler: [
      'Karahanlılar',
      'Gazneliler',
      'Büyük Selçuklu',
      'Harzemşahlar',
      'Tolunoğulları',
      'İhşidiler',
    ],
  ),
  KategoriGrubu(
    kategoriAdi: 'Anadolu\'daki İlk Türk Beylikleri',
    ders: 'Tarih',
    terimler: [
      'Danişmentliler',
      'Saltuklular',
      'Mengücekliler',
      'Artuklular',
      'Çaka',
    ],
  ),
  KategoriGrubu(
    kategoriAdi: 'Milli Mücadele Dönemi Kongreleri',
    ders: 'Tarih',
    terimler: [
      'Erzurum',
      'Sivas',
      'Balıkesir',
      'Alaşehir',
    ],
  ),
  KategoriGrubu(
    kategoriAdi: 'Kurtuluş Savaşı Cepheleri',
    ders: 'Tarih',
    terimler: ['Doğu', 'Güney', 'Batı'],
  ),
  KategoriGrubu(
    kategoriAdi: 'Osmanlı Demokratikleşme (Anayasal Gelişme) Belgeleri',
    ders: 'Tarih',
    terimler: [
      'Sened-i İttifak',
      'Tanzimat Fermanı',
      'Islahat Fermanı',
      'Kanun-i Esasi',
    ],
  ),

  // ─────────────────────────── COĞRAFYA ───────────────────────────
  KategoriGrubu(
    kategoriAdi: 'Türkiye\'nin Coğrafi Bölgeleri',
    ders: 'Coğrafya',
    terimler: [
      'Marmara',
      'Ege',
      'Akdeniz',
      'İç Anadolu',
      'Karadeniz',
      'Doğu Anadolu',
      'Güneydoğu Anadolu',
    ],
  ),
  KategoriGrubu(
    kategoriAdi: 'Türkiye\'de Görülen İklim Tipleri',
    ders: 'Coğrafya',
    terimler: [
      'Akdeniz İklimi',
      'Karadeniz İklimi',
      'Karasal İklim',
      'Marmara (Geçiş) İklimi',
    ],
  ),
  KategoriGrubu(
    kategoriAdi: 'Atmosfer Katmanları',
    ders: 'Coğrafya',
    terimler: ['Troposfer', 'Stratosfer', 'Mezosfer', 'Termosfer', 'Ekzosfer'],
  ),
  KategoriGrubu(
    kategoriAdi: 'Kayaç (Taş) Türleri',
    ders: 'Coğrafya',
    terimler: [
      'Püskürük (Magmatik)',
      'Tortul (Sedimanter)',
      'Başkalaşım (Metamorfik)',
    ],
  ),
  KategoriGrubu(
    kategoriAdi: 'Dış Kuvvetler',
    ders: 'Coğrafya',
    terimler: [
      'Akarsular',
      'Rüzgârlar',
      'Buzullar',
      'Dalga ve Akıntılar',
      'Yer Altı Suları',
    ],
  ),
  KategoriGrubu(
    kategoriAdi: 'İç Kuvvetler',
    ders: 'Coğrafya',
    terimler: ['Depremler', 'Volkanizma', 'Epirojenez', 'Orojenez'],
  ),

  // ─────────────────────────── VATANDAŞLIK ───────────────────────────
  KategoriGrubu(
    kategoriAdi: 'Devletin Erkleri (Kuvvetler Ayrılığı)',
    ders: 'Vatandaşlık',
    terimler: ['Yasama', 'Yürütme', 'Yargı'],
  ),
  KategoriGrubu(
    kategoriAdi: 'Temel Hak ve Hürriyetlerin Türleri',
    ders: 'Vatandaşlık',
    terimler: [
      'Kişi Hakları',
      'Sosyal ve Ekonomik Haklar',
      'Siyasi Haklar',
    ],
  ),
  KategoriGrubu(
    kategoriAdi: 'Yüksek Mahkemeler',
    ders: 'Vatandaşlık',
    terimler: [
      'Anayasa',
      'Yargıtay',
      'Danıştay',
      'Uyuşmazlık',
    ],
  ),

  // ═══════════════════ GENİŞLETME — 2. TUR (26 yeni kategori) ═══════════════════
  // ─────────────────────────── TÜRKÇE (devam) ───────────────────────────
  KategoriGrubu(
    kategoriAdi: 'Anlatım Biçimleri',
    ders: 'Türkçe',
    terimler: [
      'Açıklayıcı',
      'Betimleyici',
      'Öyküleyici',
      'Tartışmacı',
      'Kanıtlayıcı',
    ],
  ),
  KategoriGrubu(
    kategoriAdi: 'Cümle Türleri (Anlamına Göre)',
    ders: 'Türkçe',
    terimler: ['Olumlu', 'Olumsuz', 'Soru Cümlesi', 'Ünlem Cümlesi', 'Şart'],
  ),
  KategoriGrubu(
    kategoriAdi: 'Söz Sanatları',
    ders: 'Türkçe',
    terimler: ['Teşbih (Benzetme)', 'İstiare (Eğretileme)', 'Mecaz-ı Mürsel (Ad Aktarması)', 'Kinaye', 'Teşhis (Kişileştirme)'],
  ),
  KategoriGrubu(
    kategoriAdi: 'Yazım (İmla) Kuralı Konuları',
    ders: 'Türkçe',
    terimler: [
      'Büyük Harflerin Kullanımı',
      'Bileşik Kelimelerin',
      'Sayıların',
      'Kısaltmaların',
    ],
  ),

  // ─────────────────────────── MATEMATİK (devam) ───────────────────────────
  KategoriGrubu(
    kategoriAdi: 'Sayma ve Olasılık Kavramları',
    ders: 'Matematik',
    terimler: ['Permütasyon', 'Kombinasyon', 'Olasılık', 'Faktöriyel'],
  ),
  KategoriGrubu(
    kategoriAdi: 'Ortalama Türleri',
    ders: 'Matematik',
    terimler: ['Aritmetik', 'Geometrik', 'Harmonik'],
  ),
  KategoriGrubu(
    kategoriAdi: 'Çokgen Türleri',
    ders: 'Matematik',
    terimler: ['Beşgen', 'Altıgen', 'Yedigen', 'Sekizgen', 'Ongen'],
  ),
  KategoriGrubu(
    kategoriAdi: 'Simetri Türleri',
    ders: 'Matematik',
    terimler: ['Eksen', 'Nokta', 'Kayma (Öteleme)'],
  ),

  // ─────────────────────────── TARİH (devam) ───────────────────────────
  KategoriGrubu(
    kategoriAdi: 'Balkan Savaşları Sonrası İmzalanan Antlaşmalar',
    ders: 'Tarih',
    terimler: ['Londra', 'Bükreş', 'İstanbul', 'Atina'],
  ),
  KategoriGrubu(
    kategoriAdi: 'I. Dünya Savaşı\'nı Sona Erdiren Antlaşmalar',
    ders: 'Tarih',
    terimler: ['Versay', 'Sen Jermen', 'Nöyyi', 'Trianon', 'Sevr'],
  ),
  KategoriGrubu(
    kategoriAdi: 'Kurtuluş Savaşı Sonrası İmzalanan Antlaşmalar',
    ders: 'Tarih',
    terimler: ['Gümrü', 'Moskova', 'Ankara', 'Kars', 'Lozan'],
  ),
  KategoriGrubu(
    kategoriAdi: 'Osmanlı Duraklama Dönemi Islahatçıları',
    ders: 'Tarih',
    terimler: ['Kuyucu Murad Paşa', 'IV. Murad', 'Tarhuncu Ahmed Paşa', 'Köprülü Mehmed Paşa'],
  ),
  KategoriGrubu(
    kategoriAdi: 'Kurtuluş Savaşı Düzenli Ordu Muharebeleri',
    ders: 'Tarih',
    terimler: ['I. İnönü Muharebesi', 'II. İnönü Muharebesi', 'Sakarya Meydan Muharebesi', 'Büyük Taarruz'],
  ),
  KategoriGrubu(
    kategoriAdi: 'Osmanlı Kuruluş Dönemi Padişahları',
    ders: 'Tarih',
    terimler: ['Osman Bey', 'Orhan Bey', 'I. Murad', 'Yıldırım Bayezid'],
  ),
  KategoriGrubu(
    kategoriAdi: 'Siyasi Alanda Yapılan İnkılaplar',
    ders: 'Tarih',
    terimler: ['Saltanatın Kaldırılması', 'Cumhuriyetin İlanı', 'Halifeliğin Kaldırılması'],
  ),
  KategoriGrubu(
    kategoriAdi: 'Milli Mücadele\'de Yararlı Cemiyetler',
    ders: 'Tarih',
    terimler: [
      'Trakya-Paşaeli',
      'Kilikyalılar',
      'Doğu Anadolu Müdafaa-i Hukuk',
      'İzmir Müdafaa-i Hukuk',
      'Trabzon Muhafaza-i Hukuk',
    ],
  ),

  // ─────────────────────────── COĞRAFYA (devam) ───────────────────────────
  KategoriGrubu(
    kategoriAdi: 'Zonal (Olgun) Toprak Tipleri',
    ders: 'Coğrafya',
    terimler: [
      'Laterit',
      'Kırmızı-Sarı Podzolik',
      'Kahverengi Orman',
      'Çernozyem (Kara)',
      'Kestane Rengi',
      'Çöl',
      'Tundra',
    ],
  ),
  KategoriGrubu(
    kategoriAdi: 'İntrazonal Topraklar',
    ders: 'Coğrafya',
    terimler: ['Karasal Bataklık', 'Boz (Halomorfik)', 'Kalsimorfik', 'Hidromorfik'],
  ),
  KategoriGrubu(
    kategoriAdi: 'Azonal (Taşınmış) Topraklar',
    ders: 'Coğrafya',
    terimler: ['Alüvyal', 'Kolüvyal', 'Regosol', 'Litosol'],
  ),
  KategoriGrubu(
    kategoriAdi: 'Türkiye\'nin Komşu Ülkeleri',
    ders: 'Coğrafya',
    terimler: ['Yunanistan', 'Bulgaristan', 'Gürcistan', 'Ermenistan', 'Azerbaycan (Nahçıvan)', 'İran', 'Irak', 'Suriye'],
  ),
  KategoriGrubu(
    kategoriAdi: 'Nüfus Piramidi Türleri',
    ders: 'Coğrafya',
    terimler: ['Genişleyen', 'Duraklayan (Daralan)', 'Yaşlı'],
  ),
  KategoriGrubu(
    kategoriAdi: 'Türkiye\'yi Çevreleyen Denizler',
    ders: 'Coğrafya',
    terimler: ['Karadeniz', 'Marmara Denizi', 'Ege Denizi', 'Akdeniz'],
  ),

  // ─────────────────────────── VATANDAŞLIK (devam) ───────────────────────────
  KategoriGrubu(
    kategoriAdi: 'Türk Anayasa Tarihi',
    ders: 'Vatandaşlık',
    terimler: ['1921', '1924', '1961', '1982'],
  ),
  KategoriGrubu(
    kategoriAdi: 'Seçim Sistemleri',
    ders: 'Vatandaşlık',
    terimler: ['Çoğunluk', 'Nispi Temsil', 'Karma Seçim'],
  ),
  KategoriGrubu(
    kategoriAdi: 'Mahalli İdare Birimleri',
    ders: 'Vatandaşlık',
    terimler: ['İl Özel', 'Belediye', 'Köy'],
  ),
  KategoriGrubu(
    kategoriAdi: 'İdari Yargı Organları',
    ders: 'Vatandaşlık',
    terimler: ['Danıştay', 'Bölge', 'İdare Mahkemeleri', 'Vergi'],
  ),

  // ═══════════════════ GENİŞLETME — 3. TUR (25 yeni kategori) ═══════════════════
  // ─────────────────────────── TÜRKÇE (3. tur) ───────────────────────────
  KategoriGrubu(
    kategoriAdi: 'Fiilimsi (Eylemsi) Türleri',
    ders: 'Türkçe',
    terimler: ['İsim-Fiil', 'Sıfat-Fiil', 'Bağ-Fiil (Zarf-Fiil)'],
  ),
  KategoriGrubu(
    kategoriAdi: 'Anlatım Bozukluğu Türleri',
    ders: 'Türkçe',
    terimler: [
      'Özne-Yüklem Uyumsuzluğu',
      'Anlam Belirsizliği',
      'Gereksiz Sözcük Kullanımı',
      'Ek Yanlışlığı',
      'Sözcükte Anlam Kayması',
    ],
  ),
  KategoriGrubu(
    kategoriAdi: 'Noktalama İşaretleri',
    ders: 'Türkçe',
    terimler: [
      'Nokta (.)',
      'Virgül (,)',
      'Noktalı Virgül (;)',
      'İki Nokta (:)',
      "Kesme İşareti (')",
      'Parantez ( )',
    ],
  ),
  KategoriGrubu(
    kategoriAdi: 'Paragraf Soru Tipleri',
    ders: 'Türkçe',
    terimler: [
      'Ana Düşünce Bulma',
      'Yardımcı Düşünce Bulma',
      'Başlık Bulma',
      'Parçanın Öncesini/Sonrasını Bulma',
      'Tamamlama',
    ],
  ),
  KategoriGrubu(
    kategoriAdi: 'Yapım Eki Türleri',
    ders: 'Türkçe',
    terimler: [
      'İsimden İsim Yapan',
      'İsimden Fiil Yapan',
      'Fiilden İsim Yapan',
      'Fiilden Fiil Yapan',
    ],
  ),

  // ─────────────────────────── MATEMATİK (3. tur) ───────────────────────────
  KategoriGrubu(
    kategoriAdi: 'Küme Çeşitleri',
    ders: 'Matematik',
    terimler: ['Evrensel', 'Alt', 'Eşit', 'Denk', 'Ayrık', 'Boş'],
  ),
  KategoriGrubu(
    kategoriAdi: 'Olay Türleri (Olasılıkta)',
    ders: 'Matematik',
    terimler: ['Bağımlı', 'Bağımsız', 'Kesin', 'İmkânsız', 'Zıt'],
  ),
  KategoriGrubu(
    kategoriAdi: 'Üçgenin Yardımcı Elemanları',
    ders: 'Matematik',
    terimler: ['Kenarortay', 'Açıortay', 'Yükseklik', 'Orta Dikme'],
  ),
  KategoriGrubu(
    kategoriAdi: 'İşlem Özellikleri',
    ders: 'Matematik',
    terimler: ['Değişme', 'Birleşme', 'Dağılma', 'Yutan Eleman', 'Etkisiz Eleman'],
  ),
  KategoriGrubu(
    kategoriAdi: 'Açı Çiftleri',
    ders: 'Matematik',
    terimler: ['Tümler', 'Bütünler', 'Ters', 'Komşu'],
  ),

  // ─────────────────────────── TARİH (3. tur) ───────────────────────────
  KategoriGrubu(
    kategoriAdi: 'Hukuk Alanında Yapılan İnkılaplar',
    ders: 'Tarih',
    terimler: ['Türk Medeni Kanunu', 'Türk Ceza Kanunu', 'Borçlar Kanunu', 'Ticaret Kanunu'],
  ),
  KategoriGrubu(
    kategoriAdi: 'Eğitim ve Kültür Alanında Yapılan İnkılaplar',
    ders: 'Tarih',
    terimler: [
      'Tevhid-i Tedrisat Kanunu',
      'Yeni Türk Harfleri',
      'Millet Mektepleri',
      'Türk Tarih Kurumu',
      'Türk Dil Kurumu',
    ],
  ),
  KategoriGrubu(
    kategoriAdi: 'Ekonomi Alanında Yapılan İnkılaplar',
    ders: 'Tarih',
    terimler: [
      'Aşarın Kaldırılması',
      'Kabotaj Kanunu',
      'İzmir İktisat Kongresi',
      'Teşvik-i Sanayi Kanunu',
      "Merkez Bankası'nın Kurulması",
    ],
  ),
  KategoriGrubu(
    kategoriAdi: 'Toplumsal Alanda Yapılan İnkılaplar',
    ders: 'Tarih',
    terimler: [
      'Şapka Kanunu',
      'Tekke ve Zaviyelerin Kapatılması',
      'Soyadı Kanunu',
      'Takvim ve Saatte Değişiklik',
      'Kadınlara Seçme-Seçilme Hakkı',
    ],
  ),
  KategoriGrubu(
    kategoriAdi: 'Osmanlı Yükselme Dönemi Padişahları',
    ders: 'Tarih',
    terimler: ['II. Murad', 'Fatih Sultan Mehmed', 'II. Bayezid', 'Yavuz Sultan Selim', 'Kanuni Sultan Süleyman'],
  ),

  // ─────────────────────────── COĞRAFYA (3. tur) ───────────────────────────
  KategoriGrubu(
    kategoriAdi: "Türkiye'nin Önemli Madenleri",
    ders: 'Coğrafya',
    terimler: ['Bor', 'Krom', 'Bakır', 'Demir', 'Manganez'],
  ),
  KategoriGrubu(
    kategoriAdi: 'Yenilenebilir Enerji Kaynakları',
    ders: 'Coğrafya',
    terimler: ['Güneş', 'Rüzgar', 'Jeotermal', 'Hidrolik', 'Biyokütle'],
  ),
  KategoriGrubu(
    kategoriAdi: 'Göç Çeşitleri',
    ders: 'Coğrafya',
    terimler: ['İç', 'Dış', 'Mevsimlik', 'Beyin', 'Zorunlu'],
  ),
  KategoriGrubu(
    kategoriAdi: "Türkiye'nin Başlıca Akarsuları",
    ders: 'Coğrafya',
    terimler: ['Kızılırmak', 'Fırat', 'Dicle', 'Sakarya', 'Yeşilırmak', 'Ceyhan'],
  ),
  KategoriGrubu(
    kategoriAdi: 'Göl Oluşum Türleri',
    ders: 'Coğrafya',
    terimler: ['Tektonik', 'Volkanik', 'Karstik', 'Buzul Gölü', 'Set Gölü'],
  ),

  // ─────────────────────────── VATANDAŞLIK (3. tur) ───────────────────────────
  KategoriGrubu(
    kategoriAdi: "TBMM'nin Görev ve Yetkileri",
    ders: 'Vatandaşlık',
    terimler: [
      'Kanun Koymak, Değiştirmek ve Kaldırmak',
      'Bütçe Kanununu Kabul Etmek',
      'Para Basılmasına Karar Vermek',
      'Savaş İlanına Karar Vermek',
      'Genel ve Özel Af İlanına Karar Vermek',
    ],
  ),
  KategoriGrubu(
    kategoriAdi: 'Yürütme Organının Unsurları',
    ders: 'Vatandaşlık',
    terimler: ['Cumhurbaşkanı', 'Cumhurbaşkanı Yardımcıları', 'Bakanlar'],
  ),
  KategoriGrubu(
    kategoriAdi: 'Kamu Hukuku Dalları',
    ders: 'Vatandaşlık',
    terimler: ['Anayasa Hukuku', 'İdare Hukuku', 'Ceza Hukuku', 'Vergi Hukuku', 'Uluslararası Hukuk'],
  ),
  KategoriGrubu(
    kategoriAdi: 'Özel Hukuk Dalları',
    ders: 'Vatandaşlık',
    terimler: ['Medeni Hukuk', 'Borçlar Hukuku', 'Ticaret Hukuku', 'Devletler Özel Hukuku'],
  ),
  KategoriGrubu(
    kategoriAdi: "Türkiye'nin Üye Olduğu Başlıca Uluslararası Kuruluşlar",
    ders: 'Vatandaşlık',
    terimler: ['Birleşmiş Milletler (BM)', 'NATO', 'AGİT', 'İslam İşbirliği Teşkilatı', 'D-8'],
  ),
];
