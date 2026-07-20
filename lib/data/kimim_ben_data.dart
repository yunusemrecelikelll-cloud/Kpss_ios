/// "Kimim Ben" mini oyunu için veri modeli ve GERÇEK, KPSS'de sık geçen
/// tarihi/edebi şahsiyetler.
///
/// Her [KimimBenKisi] için ipuçları genelden özele doğru sıralanmıştır:
/// ilk ipucu en genel/belirsiz, son ipucu ise kişiyi neredeyse kesin olarak
/// belirleyen ama İSMİ DOĞRUDAN VERMEYEN en spesifik bilgidir. Tüm bilgiler
/// gerçek ve doğrulanmıştır — kurgu/uydurma bilgi YOKTUR.
///
/// İpucu sayısı kişiye göre değişebilir (en az 3, çoğunda 4); ekran ipucu
/// sayısını listenin uzunluğundan okur ve puanı buna göre azaltır
/// (bkz. kKimimBenClueScores / _clueScoreFor).
class KimimBenKisi {
  final String isim;
  final List<String> ipuclari; // genelden özele

  const KimimBenKisi({required this.isim, required this.ipuclari});
}

const List<KimimBenKisi> kKimimBenKisiler = [
  // ── Osmanlı padişahları ──
  KimimBenKisi(
    isim: 'Osman Bey',
    ipuclari: [
      'Batı Anadolu\'da küçük bir uç beyliğinin başına geçtim.',
      'Babam Ertuğrul Gazi, oğlum Orhan Bey\'dir.',
      'Bizans tekfurlarıyla mücadele ederek beyliğimin sınırlarını genişlettim.',
      'Kurduğum devlet altı yüzyıl boyunca benim adımla anıldı.',
    ],
  ),
  KimimBenKisi(
    isim: 'Orhan Gazi',
    ipuclari: [
      'Osmanlı Beyliği\'nin ikinci hükümdarıyım.',
      'Bursa\'yı fethedip başkent yaptım ve İznik\'te ilk Osmanlı medresesini açtım.',
      'İlk düzenli orduyu (yaya ve müsellemler) benim dönemimde kurduk.',
      'Oğlum Süleyman Paşa ile Rumeli\'ye geçerek Avrupa yakasında ilk toprakları aldık.',
    ],
  ),
  KimimBenKisi(
    isim: 'I. Murad',
    ipuclari: [
      'Bir Osmanlı padişahıyım; "Hüdavendigâr" unvanıyla anılırım.',
      'Devlet yönetiminde "ülke hükümdar ve oğullarınındır" anlayışını getirdim.',
      'Yeniçeri Ocağı ve Rumeli Beylerbeyliği benim dönemimde kuruldu.',
      'Savaş meydanında şehit düşen ilk ve tek Osmanlı padişahıyım.',
    ],
  ),
  KimimBenKisi(
    isim: 'Fatih Sultan Mehmet',
    ipuclari: [
      'Bir Osmanlı padişahıyım, tahta iki kez çıktım.',
      'Babam II. Murad, oğlum II. Bayezid\'dir.',
      'Devletin yönetim ve teşkilat düzenini belirleyen bir kanunname hazırlattım.',
      '1453 yılında İstanbul\'u fethederek bin yıllık Bizans İmparatorluğu\'nu sona erdirdim.',
    ],
  ),
  KimimBenKisi(
    isim: 'Yavuz Sultan Selim',
    ipuclari: [
      'Bir Osmanlı padişahıyım; saltanatım kısa ama fetihlerle doludur.',
      'Babam II. Bayezid\'in yerine tahta geçtim.',
      'Çaldıran Savaşı\'nda Safevi hükümdarı Şah İsmail\'i yenilgiye uğrattım.',
      'Mısır Seferi ile Memlük Devleti\'ne son verdim ve halifeliği Osmanlı\'ya taşıdım.',
    ],
  ),
  KimimBenKisi(
    isim: 'Kanuni Sultan Süleyman',
    ipuclari: [
      'Osmanlı padişahlarının en uzun süre tahtta kalanlarından biriyim.',
      '1526\'da Mohaç Ovası\'nda Macar ordusunu kısa sürede dağıttım.',
      'Dönemimde Osmanlı sınırları Avrupa\'nın içlerine, Viyana kapılarına kadar ulaştı.',
      'Hazırlattığım kanunname nedeniyle Batı\'da "Muhteşem", kendi halkım arasında adaletli kanunlarımla anılırım.',
    ],
  ),
  KimimBenKisi(
    isim: 'I. Ahmed',
    ipuclari: [
      '17. yüzyıl başında genç yaşta tahta çıkmış bir Osmanlı padişahıyım.',
      'Dönemimde Avusturya ile Zitvatorok Antlaşması imzalandı.',
      'Kardeş katlini kaldırıp yerine "ekber ve erşed" veraset sistemini getirdim.',
      'İstanbul\'da adımı taşıyan, altı minareli meşhur camiyi yaptırdım.',
    ],
  ),
  KimimBenKisi(
    isim: 'IV. Murad',
    ipuclari: [
      '17. yüzyılda genç yaşta tahta çıkmış bir Osmanlı padişahıyım.',
      'Tütün ve kahve yasakları gibi sert disiplin politikalarımla tanınırım.',
      'Revan Seferi\'nin ardından ikinci bir doğu seferine çıktım.',
      'Bağdat\'ı yeniden fethederek Safevilerden geri aldım.',
    ],
  ),
  KimimBenKisi(
    isim: 'III. Selim',
    ipuclari: [
      '18. yüzyıl sonunda tahta çıkmış bir Osmanlı padişahıyım.',
      'Avrupa başkentlerinde ilk daimî Osmanlı elçiliklerini açtım.',
      '"Nizam-ı Cedid" adını verdiğim yeni bir ordu kurmaya çalıştım.',
      'Kabakçı Mustafa İsyanı sonucunda tahttan indirildim.',
    ],
  ),
  KimimBenKisi(
    isim: 'II. Mahmud',
    ipuclari: [
      '19. yüzyıl başında tahta çıkmış bir Osmanlı padişahıyım.',
      'Divan teşkilatını kaldırıp yerine nazırlıkları (bakanlıkları) kurdum.',
      '1826\'da Yeniçeri Ocağı\'nı kaldırdım; bu olay "Vaka-i Hayriye" olarak anılır.',
      'Modernleşme adımlarımla Tanzimat\'a giden yolu açtım.',
    ],
  ),
  KimimBenKisi(
    isim: 'II. Abdülhamit',
    ipuclari: [
      '19. yüzyılın sonlarında uzun süre tahtta kalmış bir Osmanlı padişahıyım.',
      'Tahta çıkışımın hemen ardından ilk Osmanlı anayasası Kanun-i Esasi ilan edildi.',
      'Kanun-i Esasi\'yi 1878\'de askıya alarak otuz yılı aşkın süre tek başıma yönettim.',
      '1908\'de İttihat ve Terakki Cemiyeti\'nin baskısıyla meşrutiyeti yeniden ilan etmek zorunda kaldım.',
    ],
  ),

  // ── Cumhuriyet ve Millî Mücadele dönemi ──
  KimimBenKisi(
    isim: 'Mustafa Kemal Atatürk',
    ipuclari: [
      '20. yüzyılın başında bir orduda subay olarak göreve başladım.',
      'Çanakkale\'de Anafartalar Grubu komutanı olarak ün kazandım.',
      '19 Mayıs 1919\'da Samsun\'a çıkarak bağımsızlık mücadelesini başlattım.',
      'Yeni kurulan cumhuriyetin ilk cumhurbaşkanı oldum ve TBMM tarafından bana özel, herkese verilmeyen bir soyadı çıkarıldı.',
    ],
  ),
  KimimBenKisi(
    isim: 'İsmet İnönü',
    ipuclari: [
      'Kurtuluş Savaşı\'nda önemli bir cephede komuta ettim.',
      'Soyadımı, kazandığım iki muharebenin geçtiği yerden aldım.',
      'Lozan Antlaşması görüşmelerinde Türk heyetine başkanlık ettim.',
      'Türkiye\'nin ikinci cumhurbaşkanı oldum ve "Milli Şef" unvanıyla anıldım.',
    ],
  ),
  KimimBenKisi(
    isim: 'Kazım Karabekir',
    ipuclari: [
      'Kurtuluş Savaşı\'nda cephe komutanlarından biriyim.',
      'Erzurum Kongresi\'nin toplanmasına destek verdim.',
      'Doğu Cephesi\'nde Ermeni kuvvetlerine karşı savaştım ve Gümrü Antlaşması\'nı imzalattım.',
      'Cumhuriyet\'in ilk yıllarında Terakkiperver Cumhuriyet Fırkası\'nın kurucularındanım.',
    ],
  ),
  KimimBenKisi(
    isim: 'Ali Fuat Cebesoy',
    ipuclari: [
      'Mustafa Kemal\'in askerî okuldan yakın arkadaşıyım.',
      'Millî Mücadele\'nin başında Ankara\'daki 20. Kolordu\'nun komutanıydım.',
      'Batı Cephesi komutanlığı yaptıktan sonra Moskova büyükelçiliğine atandım.',
      'Terakkiperver Cumhuriyet Fırkası\'nın kurucuları arasında yer aldım.',
    ],
  ),
  KimimBenKisi(
    isim: 'Fevzi Çakmak',
    ipuclari: [
      'Osmanlı ordusunda yetişmiş bir komutanım.',
      'Millî Mücadele\'de TBMM hükümetinin Millî Savunma Bakanlığı ve Başbakanlık görevlerinde bulundum.',
      'Sakarya ve Büyük Taarruz\'da Genelkurmay Başkanı olarak görev yaptım.',
      'Mustafa Kemal ile birlikte mareşal rütbesi alan iki komutandan biriyim.',
    ],
  ),
  KimimBenKisi(
    isim: 'Rauf Orbay',
    ipuclari: [
      'Osmanlı donanmasında görev yapmış bir bahriye subayıyım.',
      'Balkan Savaşları\'nda Hamidiye kruvazörüyle yaptığım akınlarla tanındım.',
      'Bahriye Nazırı olarak Mondros Ateşkes Antlaşması\'nı imzaladım.',
      'Cumhuriyet\'in ilk yıllarında başbakanlık yaptım, sonra muhalefete geçtim.',
    ],
  ),
  KimimBenKisi(
    isim: 'Enver Paşa',
    ipuclari: [
      'İttihat ve Terakki Cemiyeti\'nin önde gelen isimlerinden biriyim.',
      'Trablusgarp\'ta yerel direnişi örgütleyen subaylar arasında yer aldım.',
      'I. Dünya Savaşı\'nda Osmanlı ordularının Harbiye Nazırı ve Başkumandan Vekili oldum.',
      'Sarıkamış Harekâtı\'nın felaketle sonuçlanmasından sorumlu tutulan komutanım.',
    ],
  ),
  KimimBenKisi(
    isim: 'Talat Paşa',
    ipuclari: [
      'Meslek hayatıma posta-telgraf memuru olarak başladım.',
      'İttihat ve Terakki\'nin önde gelen üç paşasından biriyim.',
      'I. Dünya Savaşı sırasında sadrazamlık (başbakanlık) görevinde bulundum.',
      '1921\'de Berlin\'de bir suikast sonucu hayatımı kaybettim.',
    ],
  ),
  KimimBenKisi(
    isim: 'Halide Edip Adıvar',
    ipuclari: [
      '20. yüzyıl başında yazar ve fikir kadınıyım.',
      'İzmir\'in işgalinden sonra Sultanahmet Mitingi\'nde halka seslendim.',
      'Kurtuluş Savaşı sırasında cephede görev aldım, Sivas Kongresi\'nde de bulundum.',
      '"Ateşten Gömlek" ve "Sinekli Bakkal" gibi romanlarımla tanınırım.',
    ],
  ),
  KimimBenKisi(
    isim: 'Celal Bayar',
    ipuclari: [
      'Cumhuriyet\'in ilk yıllarında iktisat alanında görev aldım.',
      'İş Bankası\'nın kuruluşunda öncü rol oynadım.',
      'Atatürk döneminin son başbakanı oldum.',
      '1950 seçimlerinin ardından Türkiye\'nin üçüncü cumhurbaşkanı seçildim.',
    ],
  ),
  KimimBenKisi(
    isim: 'Adnan Menderes',
    ipuclari: [
      'Çok partili hayata geçiş döneminde siyaset sahnesine çıktım.',
      'Demokrat Parti\'nin kurucuları arasındayım.',
      '1950-1960 arasında on yıl boyunca başbakanlık yaptım.',
      '27 Mayıs Darbesi sonrası Yassıada\'da yargılanıp idam edildim.',
    ],
  ),

  // ── Bilim, denizcilik, mimarlık ──
  KimimBenKisi(
    isim: 'Mimar Sinan',
    ipuclari: [
      'Osmanlı döneminde yaşadım, önce yeniçeri ocağında askerlik yaptım.',
      'Kanuni, II. Selim ve III. Murad dönemlerinde baş mimarlık görevinde bulundum.',
      'İstanbul\'daki Süleymaniye Camii\'ni "kalfalık eserim" olarak nitelendirdim.',
      'Edirne\'deki Selimiye Camii\'ni ise "ustalık eserim" saydım.',
    ],
  ),
  KimimBenKisi(
    isim: 'Piri Reis',
    ipuclari: [
      '16. yüzyılda yaşamış bir Osmanlı denizciyim.',
      'Akdeniz ve dünya haritalarını çizdiğim eserlerimle tanınırım.',
      '"Kitab-ı Bahriye" adlı denizcilik kılavuzunu yazdım.',
      'Amerika kıtasını da gösteren ünlü dünya haritamı 1513\'te çizdim.',
    ],
  ),
  KimimBenKisi(
    isim: 'Barbaros Hayreddin Paşa',
    ipuclari: [
      '16. yüzyılda Akdeniz\'de faaliyet gösteren bir denizciyim.',
      'Cezayir\'i Osmanlı Devleti\'ne bağladım ve kaptan-ı deryalığa getirildim.',
      'Kanuni döneminde Osmanlı donanmasının başına geçtim.',
      '1538\'de Preveze\'de Haçlı donanmasını yenerek Akdeniz\'de üstünlük sağladım.',
    ],
  ),
  KimimBenKisi(
    isim: 'Ali Kuşçu',
    ipuclari: [
      '15. yüzyılda yaşamış bir astronom ve matematikçiyim.',
      'Semerkant\'ta Uluğ Bey\'in yanında yetiştim.',
      'Fatih Sultan Mehmet\'in daveti üzerine İstanbul\'a geldim.',
      'Ayasofya Medresesi\'nde müderrislik yaparak Osmanlı\'da pozitif bilimlerin gelişmesine katkı sundum.',
    ],
  ),
  KimimBenKisi(
    isim: 'Katip Çelebi',
    ipuclari: [
      '17. yüzyılda yaşamış bir Osmanlı bilgini ve yazarıyım.',
      'Tarih, coğrafya ve bibliyografya alanlarında eserler verdim.',
      '"Keşfü\'z-Zünun" adlı büyük bibliyografya eserini hazırladım.',
      '"Cihannüma" adlı coğrafya kitabımla tanınırım.',
    ],
  ),
  KimimBenKisi(
    isim: 'Evliya Çelebi',
    ipuclari: [
      '17. yüzyılda yaşamış bir Osmanlı gezginiyim.',
      'Ömrümün büyük bölümünü Osmanlı ülkesini ve komşu diyarları gezerek geçirdim.',
      'Gezdiğim yerlerin coğrafyasını, halkını ve geleneklerini ayrıntılı biçimde yazdım.',
      'On ciltlik "Seyahatname" adlı eserimle tanınırım.',
    ],
  ),
  KimimBenKisi(
    isim: 'Aziz Sancar',
    ipuclari: [
      'Türkiye\'de doğup ABD\'de akademik kariyer yapmış bir bilim insanıyım.',
      'Mardin doğumluyum ve önce tıp eğitimi aldım.',
      'DNA onarım mekanizmaları üzerine yaptığım çalışmalarla tanınırım.',
      '2015 yılında Nobel Kimya Ödülü\'nü kazandım.',
    ],
  ),

  // ── Edebiyat ve düşünce ──
  KimimBenKisi(
    isim: 'Kaşgarlı Mahmud',
    ipuclari: [
      '11. yüzyılda yaşamış bir Türk dilbilimciyim.',
      'Türk boylarını dolaşarak ağız ve söz varlığını derledim.',
      'Eserimi Araplara Türkçeyi öğretmek amacıyla yazdım.',
      '"Divanü Lugati\'t-Türk" adlı ilk Türkçe sözlük bana aittir.',
    ],
  ),
  KimimBenKisi(
    isim: 'Yusuf Has Hacib',
    ipuclari: [
      '11. yüzyılda Karahanlılar döneminde yaşadım.',
      'Eserimi hükümdara sunduğum için saray görevi ile ödüllendirildim.',
      'Yapıtım siyasetname niteliğinde, dört sembolik kişi üzerine kuruludur.',
      '"Kutadgu Bilig" adlı ilk Türk-İslam eserinin yazarıyım.',
    ],
  ),
  KimimBenKisi(
    isim: 'Mevlana Celaleddin Rumi',
    ipuclari: [
      '13. yüzyılda Anadolu\'da yaşamış bir mutasavvıfım.',
      'Ömrümün büyük bölümünü Konya\'da geçirdim.',
      'Şems-i Tebrizi ile karşılaşmam hayatımın dönüm noktası oldu.',
      'Farsça yazdığım "Mesnevi" adlı eserimle tanınırım.',
    ],
  ),
  KimimBenKisi(
    isim: 'Yunus Emre',
    ipuclari: [
      'Anadolu\'da 13. yüzyılda yaşamış bir tasavvuf şairiyim.',
      'Şiirlerimi sade bir Türkçeyle, halkın anlayacağı dilde yazdım.',
      'Şiirlerimi çoğunlukla hece ölçüsüyle ve ilahi türünde söyledim.',
      '"Risaletü\'n-Nushiyye" adlı mesnevim ve Divan\'ımla Anadolu\'da Türkçenin öncülerinden sayılırım.',
    ],
  ),
  KimimBenKisi(
    isim: 'Fuzuli',
    ipuclari: [
      '16. yüzyılda yaşamış bir divan şairiyim.',
      'Eserlerimi Türkçe, Arapça ve Farsça olmak üzere üç dilde yazdım.',
      'Şiirlerimde ilahi aşkı ve ıstırabı işledim; "Su Kasidesi" de bana aittir.',
      '"Leyla ile Mecnun" mesnevisiyle tanınırım.',
    ],
  ),
  KimimBenKisi(
    isim: 'Şinasi',
    ipuclari: [
      'Tanzimat edebiyatının ilk kuşağındanım.',
      'Fransa\'da öğrenim gördükten sonra Batı edebiyatını Türkçeye tanıttım.',
      'Agâh Efendi ile birlikte ilk özel Türk gazetesi Tercüman-ı Ahval\'i çıkardım.',
      'İlk yerli tiyatro eseri sayılan "Şair Evlenmesi" bana aittir.',
    ],
  ),
  KimimBenKisi(
    isim: 'Namık Kemal',
    ipuclari: [
      'Tanzimat dönemi Yeni Osmanlılar hareketinin önde gelen isimlerindenim.',
      'Vatan sevgisini işlediğim oyunum yüzünden sürgüne gönderildim.',
      '"Hürriyet Kasidesi" ve "İntibah" adlı romanım bana aittir.',
      '"Vatan yahut Silistre" adlı oyunumla tanınırım.',
    ],
  ),
  KimimBenKisi(
    isim: 'Ziya Gökalp',
    ipuclari: [
      'II. Meşrutiyet döneminde etkili olmuş bir düşünür ve sosyologum.',
      'Türkçülük akımının fikir babası sayılırım.',
      '"Hars" (kültür) ile "medeniyet" arasında bir ayrım yaptım.',
      '"Türkleşmek, İslamlaşmak, Muasırlaşmak" adlı eserimle tanınırım.',
    ],
  ),
  KimimBenKisi(
    isim: 'Mehmet Akif Ersoy',
    ipuclari: [
      'II. Meşrutiyet ve Millî Mücadele dönemlerinde yaşamış bir şairim.',
      'Birinci TBMM\'de Burdur milletvekili olarak görev yaptım.',
      'Yazdığım şiirin ödülünü kabul etmeyerek bağışladım.',
      'TBMM\'nin 12 Mart 1921\'de kabul ettiği İstiklal Marşı\'nın şairiyim.',
    ],
  ),
  KimimBenKisi(
    isim: 'Reşat Nuri Güntekin',
    ipuclari: [
      'Cumhuriyet dönemi Türk romancılarındanım.',
      'Uzun yıllar öğretmenlik ve maarif müfettişliği yaptım.',
      'Romanlarımda Anadolu insanını ve taşra hayatını anlattım.',
      'Feride adlı genç bir öğretmenin hikâyesini anlatan "Çalıkuşu" romanıyla tanınırım.',
    ],
  ),
];
