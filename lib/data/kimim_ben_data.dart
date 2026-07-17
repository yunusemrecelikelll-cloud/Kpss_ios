/// "Kimim Ben" mini oyunu için veri modeli ve GERÇEK, KPSS'de sık geçen
/// tarihi/edebi şahsiyetler.
///
/// Her [KimimBenKisi] için 3 ipucu genelden özele doğru sıralanmıştır:
/// ilk ipucu en genel/belirsiz, son ipucu ise kişiyi neredeyse kesin olarak
/// belirleyen ama İSMİ DOĞRUDAN VERMEYEN en spesifik bilgidir. Tüm bilgiler
/// gerçek ve doğrulanmıştır — kurgu/uydurma bilgi YOKTUR.
class KimimBenKisi {
  final String isim;
  final List<String> ipuclari; // genelden özele, 3 adet

  const KimimBenKisi({required this.isim, required this.ipuclari});
}

const List<KimimBenKisi> kKimimBenKisiler = [
  KimimBenKisi(
    isim: 'Fatih Sultan Mehmet',
    ipuclari: [
      'Bir Osmanlı padişahıyım, tahta iki kez çıktım.',
      'Babam II. Murad, oğlum II. Bayezid\'dir.',
      '1453 yılında İstanbul\'u fethederek bin yıllık Bizans İmparatorluğu\'nu sona erdirdim.',
    ],
  ),
  KimimBenKisi(
    isim: 'Yavuz Sultan Selim',
    ipuclari: [
      'Bir Osmanlı padişahıyım; saltanatım kısa ama fetihlerle doludur.',
      'Mısır Seferi ile Memlük Devleti\'ne son verdim ve halifeliği Osmanlı\'ya taşıdım.',
      'Çaldıran Savaşı\'nda Safevi hükümdarı Şah İsmail\'i yenilgiye uğrattım.',
    ],
  ),
  KimimBenKisi(
    isim: 'Kanuni Sultan Süleyman',
    ipuclari: [
      'Osmanlı padişahlarının en uzun süre tahtta kalanlarından biriyim.',
      'Dönemimde Osmanlı sınırları Avrupa\'nın içlerine, Viyana kapılarına kadar ulaştı.',
      'Hazırlattığım kanunname nedeniyle Batı\'da "Muhteşem", kendi halkım arasında adaletli kanunlarımla anılırım.',
    ],
  ),
  KimimBenKisi(
    isim: 'II. Abdülhamit',
    ipuclari: [
      '19. yüzyılın sonlarında uzun süre tahtta kalmış bir Osmanlı padişahıyım.',
      'Kanun-i Esasi\'yi 1878\'de askıya alarak otuz yılı aşkın süre tek başıma yönettim.',
      '1908\'de İttihat ve Terakki Cemiyeti\'nin baskısıyla meşrutiyeti yeniden ilan etmek zorunda kaldım.',
    ],
  ),
  KimimBenKisi(
    isim: 'Mustafa Kemal Atatürk',
    ipuclari: [
      '20. yüzyılın başında bir orduda subay olarak göreve başladım.',
      '19 Mayıs 1919\'da Samsun\'a çıkarak bağımsızlık mücadelesini başlattım.',
      'Yeni kurulan cumhuriyetin ilk cumhurbaşkanı oldum ve TBMM tarafından bana özel, herkese verilmeyen bir soyadı çıkarıldı.',
    ],
  ),
  KimimBenKisi(
    isim: 'İsmet İnönü',
    ipuclari: [
      'Kurtuluş Savaşı\'nda önemli bir cephede komuta ettim.',
      'Lozan Antlaşması görüşmelerinde Türk heyetine başkanlık ettim.',
      'Türkiye\'nin ikinci cumhurbaşkanı oldum ve "Milli Şef" unvanıyla anıldım.',
    ],
  ),
  KimimBenKisi(
    isim: 'Enver Paşa',
    ipuclari: [
      'İttihat ve Terakki Cemiyeti\'nin önde gelen isimlerinden biriyim.',
      'I. Dünya Savaşı\'nda Osmanlı ordularının Harbiye Nazırı ve Başkumandan Vekili oldum.',
      'Sarıkamış Harekâtı\'nın felaketle sonuçlanmasından sorumlu tutulan komutanım.',
    ],
  ),
  KimimBenKisi(
    isim: 'Mimar Sinan',
    ipuclari: [
      'Osmanlı döneminde yaşadım, önce yeniçeri ocağında askerlik yaptım.',
      'Kanuni, II. Selim ve III. Murad dönemlerinde baş mimarlık görevinde bulundum.',
      'Selimiye Camii\'ni kendi "ustalık eserim" olarak nitelendirdim.',
    ],
  ),
  KimimBenKisi(
    isim: 'Fuzuli',
    ipuclari: [
      '16. yüzyılda yaşamış bir divan şairiyim.',
      'Eserlerimi Türkçe, Arapça ve Farsça olmak üzere üç dilde yazdım.',
      '"Leyla ile Mecnun" mesnevisiyle tanınırım.',
    ],
  ),
  KimimBenKisi(
    isim: 'Yunus Emre',
    ipuclari: [
      'Anadolu\'da 13. yüzyılda yaşamış bir tasavvuf şairiyim.',
      'Şiirlerimi sade bir Türkçeyle, halkın anlayacağı dilde yazdım.',
      '"Risaletü\'n-Nushiyye" adlı mesnevim ve Divan\'ımla Anadolu\'da Türkçenin öncülerinden sayılırım.',
    ],
  ),
  KimimBenKisi(
    isim: 'Namık Kemal',
    ipuclari: [
      'Tanzimat dönemi Yeni Osmanlılar hareketinin önde gelen isimlerindenim.',
      'Vatan sevgisini işlediğim oyunum yüzünden sürgüne gönderildim.',
      '"Vatan yahut Silistre" adlı oyunumla tanınırım.',
    ],
  ),
  KimimBenKisi(
    isim: 'Ziya Gökalp',
    ipuclari: [
      'II. Meşrutiyet döneminde etkili olmuş bir düşünür ve sosyologum.',
      'Türkçülük akımının fikir babası sayılırım.',
      '"Türkleşmek, İslamlaşmak, Muasırlaşmak" adlı eserimle tanınırım.',
    ],
  ),
  KimimBenKisi(
    isim: 'I. Ahmed',
    ipuclari: [
      '17. yüzyıl başında genç yaşta tahta çıkmış bir Osmanlı padişahıyım.',
      'Kardeş katlini kaldırıp yerine "ekber ve erşed" veraset sistemini getirdim.',
      'İstanbul\'da adımı taşıyan, altı minareli meşhur camiyi yaptırdım.',
    ],
  ),
  KimimBenKisi(
    isim: 'IV. Murad',
    ipuclari: [
      '17. yüzyılda genç yaşta tahta çıkmış bir Osmanlı padişahıyım.',
      'Bağdat\'ı yeniden fethederek Safevilerden geri aldım.',
      'Tütün ve kahve yasakları gibi sert disiplin politikalarımla tanınırım.',
    ],
  ),
  KimimBenKisi(
    isim: 'III. Selim',
    ipuclari: [
      '18. yüzyıl sonunda tahta çıkmış bir Osmanlı padişahıyım.',
      '"Nizam-ı Cedid" adını verdiğim yeni bir ordu kurmaya çalıştım.',
      'Kabakçı Mustafa İsyanı sonucunda tahttan indirildim.',
    ],
  ),
  KimimBenKisi(
    isim: 'II. Mahmud',
    ipuclari: [
      '19. yüzyıl başında tahta çıkmış bir Osmanlı padişahıyım.',
      '1826\'da Yeniçeri Ocağı\'nı kaldırdım; bu olay "Vaka-i Hayriye" olarak anılır.',
      'Modernleşme adımlarımla Tanzimat\'a giden yolu açtım.',
    ],
  ),
  KimimBenKisi(
    isim: 'Halide Edip Adıvar',
    ipuclari: [
      '20. yüzyıl başında yazar ve fikir kadınıyım.',
      'Kurtuluş Savaşı sırasında cephede görev aldım, Sivas Kongresi\'nde de bulundum.',
      '"Ateşten Gömlek" ve "Sinekli Bakkal" gibi romanlarımla tanınırım.',
    ],
  ),
  KimimBenKisi(
    isim: 'Kazım Karabekir',
    ipuclari: [
      'Kurtuluş Savaşı\'nda cephe komutanlarından biriyim.',
      'Doğu Cephesi\'nde Ermeni kuvvetlerine karşı savaştım ve Gümrü Antlaşması\'nı imzalattım.',
      'Cumhuriyet\'in ilk yıllarında Terakkiperver Cumhuriyet Fırkası\'nın kurucularındanım.',
    ],
  ),
  KimimBenKisi(
    isim: 'Talat Paşa',
    ipuclari: [
      'İttihat ve Terakki\'nin önde gelen üç paşasından biriyim.',
      'I. Dünya Savaşı sırasında sadrazamlık (başbakanlık) görevinde bulundum.',
      '1921\'de Berlin\'de bir suikast sonucu hayatımı kaybettim.',
    ],
  ),
  KimimBenKisi(
    isim: 'Piri Reis',
    ipuclari: [
      '16. yüzyılda yaşamış bir Osmanlı denizciyim.',
      'Akdeniz ve dünya haritalarını çizdiğim eserlerimle tanınırım.',
      'Amerika kıtasını da gösteren ünlü dünya haritamı 1513\'te çizdim.',
    ],
  ),
];
