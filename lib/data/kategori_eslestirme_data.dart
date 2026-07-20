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

// ════════════════════════════════════════════════════════════════════════════
//  KART OYUNLARI (v1 + V2) İÇİN KISA EŞLEŞTİRME ÇİFTLERİ
// ════════════════════════════════════════════════════════════════════════════

/// Kart oyunlarında kullanılan tek bir eşleştirme çifti.
///
/// [sol] terim/olay, [sag] ise onun karşılığıdır (tarih, kişi, sonuç...).
/// Kartlara sığması ve AKILDA KALICI olması için her iki taraf da bilinçli
/// olarak 1-3 kelime tutulmuştur; uzun cümle kullanılmaz.
class EslestirmeCifti {
  final String sol;
  final String sag;
  const EslestirmeCifti(this.sol, this.sag);
}

/// Konu id'sine göre ELLE HAZIRLANMIŞ kısa eşleştirmeler.
///
/// Neden var: konu JSON'larındaki `anahtarNoktalar` alanı bazı konularda
/// "Terim: Tanım" biçiminde olmadığından (özellikle TÜM Tarih konularında)
/// kart oyunu için çift üretilemiyordu. Burası o eksik konuları tamamlar ve
/// aynı zamanda v1 (kapalı kart) oyununun kısa-kelime havuzunu besler.
///
/// ÖNEMLİ: Buradaki tüm bilgiler tarihsel/ders bilgisi olarak DOĞRUDUR.
/// Aynı konu içinde iki kartın metni asla aynı olmamalıdır (oyun aksi hâlde
/// belirsizleşir), bu yüzden tarihler/karşılıklar bilinçli olarak ayrıştırıldı.
const Map<String, List<EslestirmeCifti>> kKonuEslestirmeleri = {
  // ─────────────────────────── TARİH ───────────────────────────
  'tarih-ilk-turk-devletleri': [
    EslestirmeCifti('Asya Hun', 'Mete Han'),
    EslestirmeCifti('Avrupa Hun', 'Attila'),
    EslestirmeCifti('Kavimler Göçü', '375'),
    EslestirmeCifti('"Türk" Adı', 'Göktürk Devleti'),
    EslestirmeCifti('Orhun Yazıtları', 'II. Göktürk'),
    EslestirmeCifti('Uygurlar', 'Yerleşik Hayat'),
    EslestirmeCifti('Talas Savaşı', '751'),
  ],
  'tarih-ilk-turk-islam': [
    EslestirmeCifti('Karahanlılar', 'İlk Müslüman Türk Devleti'),
    EslestirmeCifti('Gazneliler', 'Gazneli Mahmud'),
    EslestirmeCifti('Büyük Selçuklu', 'Tuğrul Bey'),
    EslestirmeCifti('Dandanakan', '1040'),
    EslestirmeCifti('Malazgirt', '1071'),
    EslestirmeCifti('Nizamiye Medresesi', 'Nizamülmülk'),
    EslestirmeCifti('Katvan Savaşı', '1141'),
  ],
  'tarih-anadolu-selcuklu': [
    EslestirmeCifti('Anadolu Selçuklu Kurucusu', 'Süleyman Şah'),
    EslestirmeCifti('Başkent', 'Konya'),
    EslestirmeCifti('Miryokefalon', '1176'),
    EslestirmeCifti('Kösedağ', '1243'),
    EslestirmeCifti('Yassıçemen', 'Harzemşahlar'),
    EslestirmeCifti('En Parlak Dönem', 'I. Alaeddin Keykubad'),
    EslestirmeCifti('Kervansaray', 'Ticaret Konaklaması'),
  ],
  'tarih-osmanli-kurulus': [
    EslestirmeCifti('Osmanlı Kurucusu', 'Osman Bey'),
    EslestirmeCifti('Koyunhisar', 'İlk Bizans Zaferi'),
    EslestirmeCifti("Bursa'nın Fethi", 'Orhan Bey'),
    EslestirmeCifti('Çimpe Kalesi', "Rumeli'ye Geçiş"),
    EslestirmeCifti('I. Kosova', '1389'),
    EslestirmeCifti('Ankara Savaşı', '1402'),
    EslestirmeCifti("İstanbul'un Fethi", '1453'),
    EslestirmeCifti('Otlukbeli', 'Akkoyunlular'),
    EslestirmeCifti('Çaldıran', 'Safeviler'),
    EslestirmeCifti('Ridaniye', 'Memlükler'),
    EslestirmeCifti('Mohaç', '1526'),
    EslestirmeCifti('Preveze', '1538'),
  ],
  'tarih-osmanli-gerileme': [
    EslestirmeCifti('II. Viyana Kuşatması', '1683'),
    EslestirmeCifti('Karlofça', '1699'),
    EslestirmeCifti('Pasarofça', 'Lale Devri'),
    EslestirmeCifti('Küçük Kaynarca', '1774'),
    EslestirmeCifti('Yaş Antlaşması', '1792'),
    EslestirmeCifti('Nizam-ı Cedid', 'III. Selim'),
    EslestirmeCifti('Sened-i İttifak', '1808'),
    EslestirmeCifti('Tanzimat Fermanı', '1839'),
    EslestirmeCifti('Islahat Fermanı', '1856'),
    EslestirmeCifti('I. Meşrutiyet', '1876'),
  ],
  'tarih-20yy-osmanli': [
    EslestirmeCifti('II. Meşrutiyet', '1908'),
    EslestirmeCifti('31 Mart Olayı', '1909'),
    EslestirmeCifti('Trablusgarp', 'İtalya'),
    EslestirmeCifti('Uşi Antlaşması', '1912'),
    EslestirmeCifti('Londra Antlaşması', 'I. Balkan Sonu'),
    EslestirmeCifti('Bükreş Antlaşması', 'II. Balkan Sonu'),
    EslestirmeCifti('Çanakkale', '1915'),
    EslestirmeCifti('Mondros', '1918'),
    EslestirmeCifti('Sevr', '1920'),
  ],
  'tarih-kurtulus-savasi': [
    EslestirmeCifti('Amasya Genelgesi', '22 Haziran 1919'),
    EslestirmeCifti('Erzurum Kongresi', '23 Temmuz 1919'),
    EslestirmeCifti('Sivas Kongresi', '4 Eylül 1919'),
    EslestirmeCifti('TBMM Açılışı', '23 Nisan 1920'),
    EslestirmeCifti('Gümrü', 'Ermenistan'),
    EslestirmeCifti('Sakarya', '1921'),
    EslestirmeCifti('Büyük Taarruz', '30 Ağustos 1922'),
    EslestirmeCifti('Mudanya Ateşkesi', '11 Ekim 1922'),
    EslestirmeCifti('Lozan', '1923'),
  ],
  'tarih-ataturk': [
    EslestirmeCifti('Saltanatın Kaldırılması', '1922'),
    EslestirmeCifti('Cumhuriyetin İlanı', '1923'),
    EslestirmeCifti('Halifeliğin Kaldırılması', '1924'),
    EslestirmeCifti('Şapka Kanunu', '1925'),
    EslestirmeCifti('Medeni Kanun', '1926'),
    EslestirmeCifti('Harf İnkılabı', '1928'),
    EslestirmeCifti('Türk Dil Kurumu', '1932'),
    EslestirmeCifti('Soyadı Kanunu', '1934'),
    EslestirmeCifti('Tevhid-i Tedrisat', 'Eğitim Birliği'),
  ],
  'tarih-cumhuriyet-donemi': [
    EslestirmeCifti('Terakkiperver Fırka', '1924'),
    EslestirmeCifti('Serbest Cumhuriyet Fırkası', '1930'),
    EslestirmeCifti('Montrö Boğazlar', '1936'),
    EslestirmeCifti("Hatay'ın Katılımı", '1939'),
    EslestirmeCifti('Çok Partili Seçim', '1946'),
    EslestirmeCifti('Marshall Yardımı', '1948'),
    EslestirmeCifti('Kore Savaşı', '1950'),
    EslestirmeCifti('NATO Üyeliği', '1952'),
    EslestirmeCifti('Kıbrıs Barış Harekâtı', '1974'),
  ],
  'tarih-turk-kulturu': [
    EslestirmeCifti('Kutadgu Bilig', 'Yusuf Has Hacib'),
    EslestirmeCifti("Divanü Lugati't-Türk", 'Kaşgarlı Mahmud'),
    EslestirmeCifti("Atabetü'l-Hakayık", 'Edip Ahmet'),
    EslestirmeCifti('Divan-ı Hikmet', 'Ahmet Yesevi'),
    EslestirmeCifti('Şehname', 'Firdevsi'),
    EslestirmeCifti('Ahilik', 'Esnaf Teşkilatı'),
    EslestirmeCifti('Selimiye Camii', 'Mimar Sinan'),
    EslestirmeCifti('Vakıf', 'Hayır Kurumu'),
  ],
  'tarih-dunya-tarihi': [
    EslestirmeCifti('Magna Carta', '1215'),
    EslestirmeCifti("Amerika'nın Keşfi", '1492'),
    EslestirmeCifti('Fransız İhtilali', '1789'),
    EslestirmeCifti('Matbaanın İcadı', 'Gutenberg'),
    EslestirmeCifti('Sanayi Devrimi', 'İngiltere'),
    EslestirmeCifti('I. Dünya Savaşı', '1914-1918'),
    EslestirmeCifti('II. Dünya Savaşı', '1939-1945'),
    EslestirmeCifti("Berlin Duvarı'nın Yıkılışı", '1989'),
    EslestirmeCifti("Sovyetler'in Dağılması", '1991'),
  ],

  // ─────────────────────────── COĞRAFYA ───────────────────────────
  'cografya-yer-sekilleri': [
    EslestirmeCifti('Orojenez', 'Dağ Oluşumu'),
    EslestirmeCifti('Epirojenez', 'Kıta Hareketi'),
    EslestirmeCifti('Volkanizma', 'Magma Yükselmesi'),
    EslestirmeCifti('En Yüksek Dağ', 'Ağrı Dağı'),
    EslestirmeCifti('Karstik Şekil', 'Kireç Taşı'),
    EslestirmeCifti('Delta Ovası', 'Akarsu Birikimi'),
    EslestirmeCifti('Falez', 'Kıyı Şekli'),
    EslestirmeCifti('Peribacası', 'Ürgüp-Göreme'),
  ],
  'cografya-dogal-afetler': [
    EslestirmeCifti('Deprem', 'Fay Hattı'),
    EslestirmeCifti('Heyelan', 'Karadeniz'),
    EslestirmeCifti('Erozyon', 'Toprak Kaybı'),
    EslestirmeCifti('Çığ', 'Doğu Anadolu'),
    EslestirmeCifti('Tsunami', 'Deniz Depremi'),
    EslestirmeCifti('Sera Etkisi', 'Küresel Isınma'),
    EslestirmeCifti('Asit Yağmuru', 'Hava Kirliliği'),
  ],
  'cografya-su-kaynaklari': [
    EslestirmeCifti('En Uzun Akarsu', 'Kızılırmak'),
    EslestirmeCifti('En Büyük Göl', 'Van Gölü'),
    EslestirmeCifti('En Büyük Tatlı Su Gölü', 'Beyşehir'),
    EslestirmeCifti('Atatürk Barajı', 'Fırat'),
    EslestirmeCifti('Tuz Gölü', 'İç Anadolu'),
    EslestirmeCifti('Sapanca Gölü', 'Tektonik'),
    EslestirmeCifti('Manavgat Çayı', 'Düzenli Rejim'),
  ],
  'cografya-ticaret': [
    EslestirmeCifti('İthalat', 'Dışarıdan Alım'),
    EslestirmeCifti('İhracat', 'Dışarıya Satım'),
    EslestirmeCifti('Dış Ticaret Açığı', 'İthalat Fazlası'),
    EslestirmeCifti('Serbest Bölge', 'Gümrüksüz Alan'),
    EslestirmeCifti('Transit Ticaret', 'Aktarma'),
    EslestirmeCifti('Gümrük Birliği', '1996'),
    EslestirmeCifti('Borsa İstanbul', 'Menkul Kıymet'),
  ],

  // ─────────────────────────── GÜNCEL BİLGİLER ───────────────────────────
  'guncel-teknoloji': [
    EslestirmeCifti('Yapay Zekâ', 'Makine Öğrenmesi'),
    EslestirmeCifti('Blok Zinciri', 'Dağıtık Kayıt'),
    EslestirmeCifti('Nesnelerin İnterneti', 'IoT'),
    EslestirmeCifti('Büyük Veri', 'Big Data'),
    EslestirmeCifti('Bulut Bilişim', 'Uzak Sunucu'),
    EslestirmeCifti('5G', 'Mobil İletişim'),
    EslestirmeCifti('e-Devlet', 'Kamu Hizmeti'),
    EslestirmeCifti('TÜBİTAK', 'Bilimsel Araştırma'),
    EslestirmeCifti('Siber Güvenlik', 'Veri Koruma'),
  ],

  // ─────────────────────────── MATEMATİK ───────────────────────────
  'matematik-temel-kavramlar': [
    EslestirmeCifti('Rakam', "0'dan 9'a"),
    EslestirmeCifti('Doğal Sayılar', 'N'),
    EslestirmeCifti('Tam Sayılar', 'Z'),
    EslestirmeCifti('En Küçük Asal', '2'),
    EslestirmeCifti('Çift Sayı', '2n'),
    EslestirmeCifti('Tek Sayı', '2n+1'),
    EslestirmeCifti('Ardışık Sayılar', 'Birer Artan'),
    EslestirmeCifti('Basamak Değeri', 'Rakam × Basamak'),
  ],
  'matematik-problemler': [
    EslestirmeCifti('Kâr', 'Satış - Maliyet'),
    EslestirmeCifti('Zarar', 'Maliyet - Satış'),
    EslestirmeCifti('Maliyet', 'Alış Fiyatı'),
    EslestirmeCifti('Basit Faiz', 'A·n·t/100'),
    EslestirmeCifti('Yaş Farkı', 'Hep Aynı'),
    EslestirmeCifti('%20 Artış', '1,2 Katı'),
    EslestirmeCifti('%25 İndirim', '0,75 Katı'),
  ],
  'matematik-geometri-temelleri': [
    EslestirmeCifti('Üçgenin İç Açıları', '180°'),
    EslestirmeCifti('Dörtgenin İç Açıları', '360°'),
    EslestirmeCifti('Pisagor', 'a² + b² = c²'),
    EslestirmeCifti('Dairenin Çevresi', '2πr'),
    EslestirmeCifti('Dairenin Alanı', 'πr²'),
    EslestirmeCifti('Üçgenin Alanı', 'Taban × Yükseklik / 2'),
    EslestirmeCifti('Karenin Alanı', 'a²'),
    EslestirmeCifti('Küpün Hacmi', 'a³'),
  ],
  'matematik-istatistik': [
    EslestirmeCifti('Aritmetik Ortalama', 'Toplam / Adet'),
    EslestirmeCifti('Medyan', 'Ortanca Değer'),
    EslestirmeCifti('Mod', 'En Çok Tekrar Eden'),
    EslestirmeCifti('Açıklık', 'En Büyük - En Küçük'),
    EslestirmeCifti('Daire Grafiği', 'Yüzde Dağılım'),
    EslestirmeCifti('Sütun Grafiği', 'Karşılaştırma'),
    EslestirmeCifti('Standart Sapma', 'Yayılma Ölçüsü'),
  ],
  'matematik-uslu-sayilar': [
    EslestirmeCifti('a⁰', '1'),
    EslestirmeCifti('a⁻ⁿ', '1/aⁿ'),
    EslestirmeCifti('aᵐ · aⁿ', 'aᵐ⁺ⁿ'),
    EslestirmeCifti('aᵐ / aⁿ', 'aᵐ⁻ⁿ'),
    EslestirmeCifti('(aᵐ)ⁿ', 'aᵐ·ⁿ'),
    EslestirmeCifti('2³', '8'),
    EslestirmeCifti('(-2)²', '4'),
    EslestirmeCifti('10⁻²', '0,01'),
  ],
  'matematik-koklu-sayilar': [
    EslestirmeCifti('√a · √b', '√(a·b)'),
    EslestirmeCifti('√a / √b', '√(a/b)'),
    EslestirmeCifti('√(a²)', '|a|'),
    EslestirmeCifti('√4', '2'),
    EslestirmeCifti('√9', '3'),
    EslestirmeCifti('∛8', '2 (küp kök)'),
    EslestirmeCifti('√2', 'İrrasyonel'),
    EslestirmeCifti('2√3 + 3√3', '5√3'),
  ],

  // ─────────────────────────── TÜRKÇE ───────────────────────────
  'turkce-cumle-turleri': [
    EslestirmeCifti('Kurallı Cümle', 'Yüklem Sonda'),
    EslestirmeCifti('Devrik Cümle', 'Yüklem Sonda Değil'),
    EslestirmeCifti('Fiil Cümlesi', 'Yüklemi Fiil'),
    EslestirmeCifti('İsim Cümlesi', 'Yüklemi İsim'),
    EslestirmeCifti('Basit Cümle', 'Tek Yargı'),
    EslestirmeCifti('Birleşik Cümle', 'Birden Çok Yargı'),
    EslestirmeCifti('Sıralı Cümle', 'Virgülle Bağlanır'),
    EslestirmeCifti('Bağlı Cümle', 'Bağlaçla Bağlanır'),
    EslestirmeCifti('Eksiltili Cümle', 'Yüklemi Söylenmemiş'),
  ],
  'turkce-cumlenin-ogeleri': [
    EslestirmeCifti('Özne', 'İşi Yapan'),
    EslestirmeCifti('Yüklem', 'Yargı Bildiren'),
    EslestirmeCifti('Belirtili Nesne', '-i Hâli'),
    EslestirmeCifti('Belirtisiz Nesne', 'Yalın Hâl'),
    EslestirmeCifti('Dolaylı Tümleç', '-e, -de, -den'),
    EslestirmeCifti('Zarf Tümleci', 'Nasıl, Ne Zaman'),
    EslestirmeCifti('Gizli Özne', 'Yüklemden Bulunur'),
    EslestirmeCifti('Cümle Dışı Unsur', 'Ünlem, Hitap'),
  ],
  'turkce-sozel-mantik': [
    EslestirmeCifti('Tümdengelim', 'Genelden Özele'),
    EslestirmeCifti('Tümevarım', 'Özelden Genele'),
    EslestirmeCifti('Öncül', 'Verilen Bilgi'),
    EslestirmeCifti('Çıkarım', 'Sonuca Ulaşma'),
    EslestirmeCifti('Analoji', 'Benzerlik Kurma'),
    EslestirmeCifti('Çelişki', 'Aynı Anda Doğru Olamaz'),
    EslestirmeCifti('Sıralama Sorusu', 'Kim Nerede'),
    EslestirmeCifti('Tablo Kurma', 'Bilgi Yerleştirme'),
  ],
  'turkce-paragrafta-anlatim-bicimi': [
    EslestirmeCifti('Açıklayıcı Anlatım', 'Bilgi Verme'),
    EslestirmeCifti('Tartışmacı Anlatım', 'Görüş Çürütme'),
    EslestirmeCifti('Betimleyici Anlatım', 'Görüntü Çizme'),
    EslestirmeCifti('Öyküleyici Anlatım', 'Olay Anlatma'),
    EslestirmeCifti('Tanımlama', 'Nedir Sorusu'),
    EslestirmeCifti('Örneklendirme', 'Somutlaştırma'),
    EslestirmeCifti('Karşılaştırma', 'Benzerlik-Farklılık'),
    EslestirmeCifti('Tanık Gösterme', 'Uzman Sözü'),
    EslestirmeCifti('Sayısal Veri', 'İstatistik Kullanma'),
  ],
  'turkce-paragraf-sorulari': [
    EslestirmeCifti('Ana Düşünce', 'Metnin Özü'),
    EslestirmeCifti('Yardımcı Düşünce', 'Destekleyici Bilgi'),
    EslestirmeCifti('Başlık', 'En Kapsayıcı İfade'),
    EslestirmeCifti('Konu', 'Neden Söz Ediliyor'),
    EslestirmeCifti('Anahtar Cümle', 'Giriş Cümlesi'),
    EslestirmeCifti('Akışı Bozan Cümle', 'Konu Dışı'),
    EslestirmeCifti('Paragrafın Sonu', 'Sonuç Cümlesi'),
    EslestirmeCifti('Yazarın Amacı', 'Yazma Nedeni'),
  ],

  // ─────────────────────────── VATANDAŞLIK ───────────────────────────
  'vatandaslik-hukukun-temelleri': [
    EslestirmeCifti('Hukuk', 'Toplumsal Kurallar'),
    EslestirmeCifti('Yaptırım', 'Kurala Uymama Sonucu'),
    EslestirmeCifti('Kamu Hukuku', 'Devlet - Birey'),
    EslestirmeCifti('Özel Hukuk', 'Birey - Birey'),
    EslestirmeCifti('Hak Ehliyeti', 'Sağ Doğmak'),
    EslestirmeCifti('Fiil Ehliyeti', 'Ergin ve Ayırt Eden'),
    EslestirmeCifti('Örf ve Âdet', 'Yazısız Kaynak'),
    EslestirmeCifti('Erginlik Yaşı', '18'),
  ],
  'vatandaslik-anayasa': [
    EslestirmeCifti('Kanun-i Esasi', '1876'),
    EslestirmeCifti('Teşkilat-ı Esasiye', '1921'),
    EslestirmeCifti('Yürürlükteki Anayasa', '1982'),
    EslestirmeCifti('Devletin Şekli', 'Cumhuriyet'),
    EslestirmeCifti('Değiştirilemez Maddeler', 'İlk Üç Madde'),
    EslestirmeCifti('Anayasa Değişikliği', '3/5 Çoğunluk'),
    EslestirmeCifti('Anayasa Mahkemesi', 'Norm Denetimi'),
    EslestirmeCifti('Başlangıç Hükümleri', 'Anayasaya Dâhil'),
  ],
  'vatandaslik-yasama': [
    EslestirmeCifti('Milletvekili Sayısı', '600'),
    EslestirmeCifti('Seçilme Yaşı', '18'),
    EslestirmeCifti('Seçim Dönemi', '5 Yıl'),
    EslestirmeCifti('Toplantı Yeter Sayısı', '1/3'),
    EslestirmeCifti('Genel Af', '3/5 Çoğunluk'),
    EslestirmeCifti('Bütçe Kanunu', 'TBMM Onayı'),
    EslestirmeCifti('Yasama Dokunulmazlığı', 'Milletvekili Güvencesi'),
  ],
  'vatandaslik-yargi': [
    EslestirmeCifti('Yargıtay', 'Adli Yargı'),
    EslestirmeCifti('Danıştay', 'İdari Yargı'),
    EslestirmeCifti('Sayıştay', 'Mali Denetim'),
    EslestirmeCifti('Anayasa Mahkemesi', 'Bireysel Başvuru'),
    EslestirmeCifti('Uyuşmazlık Mahkemesi', 'Görev Uyuşmazlığı'),
    EslestirmeCifti('HSK', 'Hâkim Atamaları'),
    EslestirmeCifti('Muhtar', 'Köy ve Mahalle'),
    EslestirmeCifti('İl Özel İdaresi', 'Vali Başkanlığı'),
  ],
  'vatandaslik-temel-haklar': [
    EslestirmeCifti('Koruyucu Haklar', 'Negatif Statü'),
    EslestirmeCifti('İsteme Hakları', 'Pozitif Statü'),
    EslestirmeCifti('Katılma Hakları', 'Aktif Statü'),
    EslestirmeCifti('Seçme ve Seçilme', 'Siyasi Hak'),
    EslestirmeCifti('Eğitim Hakkı', 'Sosyal Hak'),
    EslestirmeCifti('Konut Dokunulmazlığı', 'Kişi Hakkı'),
    EslestirmeCifti('Dilekçe Hakkı', 'Başvuru Hakkı'),
    EslestirmeCifti('Hakların Sınırlanması', 'Kanunla'),
  ],
  'vatandaslik-idare-hukuku': [
    EslestirmeCifti('Merkezi İdare', 'Bakanlıklar'),
    EslestirmeCifti('Taşra Teşkilatı', 'İl ve İlçe'),
    EslestirmeCifti('Vali', 'İlin Başı'),
    EslestirmeCifti('Kaymakam', 'İlçenin Başı'),
    EslestirmeCifti('Yerinden Yönetim', 'Mahalli İdare'),
    EslestirmeCifti('Hizmet Yerinden Yönetim', 'Üniversite, TRT'),
    EslestirmeCifti('İdari İşlem', 'Tek Yanlı Karar'),
    EslestirmeCifti('Büyükşehir Belediyesi', '30 İl'),
  ],
};

/// Tüm konulardaki kısa eşleştirmelerin düz listesi — v1 (kapalı kart)
/// oyununun kart havuzu bunu temel alır.
List<EslestirmeCifti> get kTumKisaEslestirmeler =>
    [for (final liste in kKonuEslestirmeleri.values) ...liste];
