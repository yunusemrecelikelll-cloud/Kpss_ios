/// "Zincirleme Bilgi" mini oyunu için veri modeli ve GERÇEK, doğrulanmış
/// tarih/coğrafya/vatandaşlık zincirleri.
///
/// Her [BilgiZinciri] birbirine anlamlı biçimde bağlı [ZincirAdim]lardan
/// oluşur: bir adımın doğru cevabı bir sonraki adımın konusuna/ipucuna
/// bağlanır (ör. Samsun'a çıkış → Amasya Genelgesi → Erzurum Kongresi →
/// Sivas Kongresi ...). Tüm olay/tarih bilgileri KPSS müfredatına uygun,
/// gerçek ve doğrulanmış bilgilerdir — kurgu/uydurma bilgi YOKTUR.
class ZincirAdim {
  final String soru;
  final List<String> secenekler;
  final int dogruIndex;
  final String aciklama;
  /// Bu adım doğru cevaplandıktan sonra bir sonraki adıma geçişi anlatan
  /// bağlantı cümlesi. Zincirin SON adımında boş string ('') olur.
  final String ipucuSonraki;

  const ZincirAdim({
    required this.soru,
    required this.secenekler,
    required this.dogruIndex,
    required this.aciklama,
    this.ipucuSonraki = '',
  });
}

class BilgiZinciri {
  final String id;
  final String baslik;
  final List<ZincirAdim> adimlar;

  const BilgiZinciri({
    required this.id,
    required this.baslik,
    required this.adimlar,
  });
}

const List<BilgiZinciri> kBilgiZincirleri = [
  // ── 1. Kurtuluş Savaşı'nın hazırlık dönemi: Samsun'dan Misak-ı Milli'ye ──
  BilgiZinciri(
    id: 'zincir_samsun_misakimilli',
    baslik: 'Samsun\'dan Misak-ı Millî\'ye',
    adimlar: [
      ZincirAdim(
        soru: 'Mondros Ateşkes Antlaşması sonrasında Karadeniz bölgesindeki '
            'asayişi sağlamak görevi bahane edilerek 19 Mayıs 1919\'da '
            'Mustafa Kemal\'in Bandırma Vapuru ile çıktığı şehir neresidir?',
        secenekler: ['İzmir', 'Samsun', 'Trabzon', 'Erzurum'],
        dogruIndex: 1,
        aciklama: 'Mustafa Kemal, 19 Mayıs 1919\'da Samsun\'a çıkmıştır; bu tarih '
            'Kurtuluş Savaşı\'nın başlangıcı olarak kabul edilir.',
        ipucuSonraki: 'Samsun\'a çıktıktan kısa süre sonra, "Milletin bağımsızlığını '
            'yine milletin azim ve kararı kurtaracaktır" ilkesini ilk kez resmi '
            'olarak duyurduğu belge hangisidir?',
      ),
      ZincirAdim(
        soru: '22 Haziran 1919\'da yayımlanan, milli bağımsızlık ilkesinin ilk '
            'kez resmi olarak açıklandığı belge hangisidir?',
        secenekler: ['Amasya Genelgesi', 'Havza Genelgesi', 'Misak-ı Millî', 'Amasya Görüşmeleri'],
        dogruIndex: 0,
        aciklama: 'Amasya Genelgesi (22 Haziran 1919), Kurtuluş Savaşı\'nın "yol '
            'haritası" niteliğinde ilk resmi belgedir.',
        ipucuSonraki: 'Bu genelgenin ardından toplanan, sadece doğu illerini '
            'temsilen yapılan ilk bölgesel kongre hangisidir?',
      ),
      ZincirAdim(
        soru: '23 Temmuz - 7 Ağustos 1919 tarihleri arasında toplanan, doğu '
            'illerini temsil eden ve "Doğu illeri bir bütündür, bölünemez" '
            'ilkesini kabul eden kongre hangisidir?',
        secenekler: ['Sivas Kongresi', 'Erzurum Kongresi', 'Balıkesir Kongresi', 'Alaşehir Kongresi'],
        dogruIndex: 1,
        aciklama: 'Erzurum Kongresi, bölgesel nitelikte olmasına rağmen aldığı '
            'kararlarla (manda ve himayenin reddi, milli sınırlar) Sivas '
            'Kongresi\'ne zemin hazırlamıştır.',
        ipucuSonraki: 'Erzurum Kongresi kararlarının tüm yurt adına genişletildiği, '
            'tüm illerin temsilcileriyle toplanan kongre hangisidir?',
      ),
      ZincirAdim(
        soru: '4-11 Eylül 1919 tarihlerinde toplanan, manda ve himayenin '
            'kesin olarak reddedildiği, "Anadolu ve Rumeli Müdafaa-i Hukuk '
            'Cemiyeti"nin kurulduğu tüm yurdu temsil eden kongre hangisidir?',
        secenekler: ['Sivas Kongresi', 'Erzurum Kongresi', 'Amasya Görüşmeleri', 'TBMM\'nin açılışı'],
        dogruIndex: 0,
        aciklama: 'Sivas Kongresi, ülke genelinden gelen temsilcilerle toplanmış, '
            'ulusal bağımsızlık iradesini tüm yurt adına ortaya koymuştur.',
        ipucuSonraki: 'Sivas Kongresi\'nden sonra İstanbul Hükümeti ile Heyet-i '
            'Temsiliye arasında yapılan ve İstanbul Hükümeti\'nin Sivas Kongresi '
            'kararlarını tanımasıyla sonuçlanan görüşme hangisidir?',
      ),
      ZincirAdim(
        soru: '20-22 Ekim 1919 tarihlerinde İstanbul Hükümeti adına Bahriye '
            'Nazırı Salih Paşa ile Mustafa Kemal arasında yapılan, İstanbul '
            'Hükümeti\'nin Anadolu hareketini ilk kez tanıdığı görüşme hangisidir?',
        secenekler: ['Amasya Görüşmeleri', 'Amasya Genelgesi', 'Erzurum Kongresi', 'Londra Konferansı'],
        dogruIndex: 0,
        aciklama: 'Amasya Görüşmeleri sonucunda İstanbul Hükümeti, Anadolu ve '
            'Rumeli Müdafaa-i Hukuk Cemiyeti\'ni ve Sivas Kongresi kararlarını '
            'zımnen kabul etmiştir.',
        ipucuSonraki: 'Bu görüşmelerin ardından toplanan, Misak-ı Millî '
            'kararlarının kabul edildiği son Osmanlı Mebusan Meclisi oturumu '
            'hangi tarihte gerçekleşmiştir?',
      ),
      ZincirAdim(
        soru: 'Son Osmanlı Mebusan Meclisi\'nin, ülkenin bölünmezliğini ve '
            'bağımsızlığını esas alan Misak-ı Millî kararlarını kabul ettiği '
            'tarih hangisidir?',
        secenekler: ['28 Ocak 1920', '23 Nisan 1920', '10 Ağustos 1920', '11 Ekim 1922'],
        dogruIndex: 0,
        aciklama: 'Son Osmanlı Mebusan Meclisi, 28 Ocak 1920\'de Misak-ı Millî\'yi '
            'kabul etmiştir; meclis kısa süre sonra İstanbul\'un işgaliyle '
            'dağıtılmış, bu da TBMM\'nin açılışına giden süreci hızlandırmıştır.',
      ),
    ],
  ),

  // ── 2. TBMM'nin açılışından Lozan'a ──
  BilgiZinciri(
    id: 'zincir_tbmm_lozan',
    baslik: 'TBMM\'den Lozan\'a',
    adimlar: [
      ZincirAdim(
        soru: 'İstanbul\'un resmen işgal edilmesi ve Osmanlı Mebusan Meclisi\'nin '
            'dağıtılması üzerine, tüm yetkileri kendinde toplayan yeni meclis '
            '23 Nisan 1920\'de nerede açılmıştır?',
        secenekler: ['Ankara', 'Sivas', 'Erzurum', 'İstanbul'],
        dogruIndex: 0,
        aciklama: 'TBMM, 23 Nisan 1920\'de Ankara\'da açılmış, ilk başkanlığına '
            'Mustafa Kemal seçilmiştir.',
        ipucuSonraki: 'TBMM\'nin açılışından sonra Yunan ilerleyişinin durdurulduğu, '
            '"Hattı müdafaa yoktur, sathı müdafaa vardır" sözünün söylendiği '
            'büyük meydan muharebesi hangisidir?',
      ),
      ZincirAdim(
        soru: '23 Ağustos - 13 Eylül 1921 tarihleri arasında, Mustafa Kemal\'in '
            'Başkomutan sıfatıyla bizzat yönettiği, Yunan ilerleyişinin '
            'durdurulduğu meydan muharebesi hangisidir?',
        secenekler: ['Sakarya Meydan Muharebesi', 'I. İnönü Muharebesi', 'II. İnönü Muharebesi', 'Büyük Taarruz'],
        dogruIndex: 0,
        aciklama: 'Sakarya Meydan Muharebesi zaferinin ardından TBMM, Mustafa '
            'Kemal\'e Mareşal rütbesi ve Gazi unvanını vermiştir.',
        ipucuSonraki: 'Sakarya zaferinden sonra Yunan ordusunun Anadolu\'dan '
            'tamamen çıkarılmasını sağlayan kesin taarruz hangisidir?',
      ),
      ZincirAdim(
        soru: '26 Ağustos 1922\'de başlayıp "Başkomutanlık Meydan Muharebesi" '
            'ile süren, 9 Eylül 1922\'de İzmir\'in kurtuluşuyla sonuçlanan '
            'taarruz hangisidir?',
        secenekler: ['Büyük Taarruz', 'Sakarya Meydan Muharebesi', 'Çanakkale Savaşı', 'I. İnönü Muharebesi'],
        dogruIndex: 0,
        aciklama: 'Büyük Taarruz ile Yunan ordusu kesin olarak yenilgiye '
            'uğratılmış, Anadolu\'daki işgale son verilmiştir.',
        ipucuSonraki: 'Büyük Taarruz zaferinin ardından İtilaf Devletleri ile '
            'imzalanan, savaşı fiilen sona erdiren ateşkes anlaşması hangisidir?',
      ),
      ZincirAdim(
        soru: '11 Ekim 1922\'de imzalanan, Kurtuluş Savaşı\'nın fiilen sona '
            'erdiği ateşkes antlaşması hangisidir?',
        secenekler: ['Mudanya Ateşkes Antlaşması', 'Mondros Ateşkes Antlaşması', 'Lozan Antlaşması', 'Sevr Antlaşması'],
        dogruIndex: 0,
        aciklama: 'Mudanya Ateşkes Antlaşması ile İtilaf Devletleri, TBMM '
            'Hükümeti\'ni resmen muhatap almıştır.',
        ipucuSonraki: 'Mudanya\'dan kısa süre sonra, TBMM\'nin ikili yönetime son '
            'vermek için 1 Kasım 1922\'de aldığı önemli karar nedir?',
      ),
      ZincirAdim(
        soru: 'TBMM\'nin 1 Kasım 1922\'de aldığı, Osmanlı Devleti\'nin fiilen '
            'sona ermesini sağlayan karar hangisidir?',
        secenekler: ['Saltanatın kaldırılması', 'Halifeliğin kaldırılması', 'Cumhuriyetin ilanı', 'Şer\'iye ve Evkaf Vekaletinin kaldırılması'],
        dogruIndex: 0,
        aciklama: 'TBMM, 1 Kasım 1922\'de saltanatı kaldırmış, son padişah '
            'Vahdettin ülkeyi terk etmiştir. Halifelik ise bir süre daha devam '
            'etmiş, 3 Mart 1924\'te kaldırılmıştır.',
        ipucuSonraki: 'Saltanatın kaldırılmasından sonra imzalanan, yeni Türk '
            'devletinin bağımsızlığını uluslararası alanda tescil eden barış '
            'antlaşması hangisidir?',
      ),
      ZincirAdim(
        soru: '24 Temmuz 1923\'te imzalanan, Türkiye Cumhuriyeti\'nin '
            'uluslararası alanda tanındığı barış antlaşması hangisidir?',
        secenekler: ['Lozan Antlaşması', 'Sevr Antlaşması', 'Mudanya Ateşkesi', 'Ankara Antlaşması'],
        dogruIndex: 0,
        aciklama: 'Lozan Antlaşması, Misak-ı Millî\'ye en yakın sınırları kabul '
            'ettiren, yeni Türk devletinin bağımsızlığını tescil eden antlaşmadır.',
      ),
    ],
  ),

  // ── 3. Osmanlı Devleti'nin kuruluş ve yükseliş dönemi ──
  BilgiZinciri(
    id: 'zincir_osmanli_kurulus',
    baslik: 'Osmanlı\'nın Kuruluşu ve Yükselişi',
    adimlar: [
      ZincirAdim(
        soru: '1299\'da Söğüt ve Domaniç yöresinde, Bizans\'a karşı verdiği '
            'mücadelelerle Osmanlı Devleti\'nin temelini atan bey kimdir?',
        secenekler: ['Osman Bey', 'Ertuğrul Gazi', 'Orhan Bey', 'I. Murad'],
        dogruIndex: 0,
        aciklama: 'Osmanlı Devleti, 1299\'da Osman Bey tarafından kurulmuştur.',
        ipucuSonraki: 'Osman Bey\'in oğlu, Bursa\'yı fethedip başkent yapan ve '
            'ilk düzenli Osmanlı ordusunun temelini atan hükümdar kimdir?',
      ),
      ZincirAdim(
        soru: '1326\'da Bursa\'yı fethederek başkent yapan, "Yaya ve '
            'Müsellemler" adlı ilk düzenli Osmanlı ordusunu kuran ve Rumeli\'ye '
            'ilk geçişi (Çimpe Kalesi, 1353) sağlayan padişah kimdir?',
        secenekler: ['Orhan Bey', 'I. Murad', 'Osman Bey', 'Yıldırım Bayezid'],
        dogruIndex: 0,
        aciklama: 'Orhan Bey döneminde Bursa başkent yapılmış, ilk düzenli '
            'ordu kurulmuş ve Rumeli\'ye ilk adım atılmıştır.',
        ipucuSonraki: 'Orhan Bey\'den sonra tahta çıkan, Kosova Savaşı (1389) '
            'sırasında şehit düşen, Rumeli\'deki fetihleri genişleten padişah kimdir?',
      ),
      ZincirAdim(
        soru: '1389\'da Sırp ve müttefik kuvvetlerine karşı kazanılan I. Kosova '
            'Savaşı sırasında şehit düşen, Yeniçeri Ocağı\'nın kurumsallaştığı '
            'dönemin padişahı kimdir?',
        secenekler: ['I. Murad', 'Yıldırım Bayezid', 'II. Murad', 'Orhan Bey'],
        dogruIndex: 0,
        aciklama: 'I. Murad (Hüdavendigâr), Kosova Savaşı\'nda şehit düşmüş, '
            'kendisinden sonra oğlu Yıldırım Bayezid tahta geçmiştir.',
        ipucuSonraki: 'I. Murad\'ın şehadetinin ardından tahta çıkan, Niğbolu '
            'Savaşı\'nı (1396) kazanan ama Ankara Savaşı\'nda (1402) Timur\'a '
            'yenilerek Fetret Devri\'nin başlamasına neden olan padişah kimdir?',
      ),
      ZincirAdim(
        soru: '1396\'da Niğbolu Savaşı\'nı kazanan, ancak 1402\'de Ankara '
            'Savaşı\'nda Timur\'a yenilerek Osmanlı\'da "Fetret Devri"nin '
            'başlamasına neden olan padişah kimdir?',
        secenekler: ['Yıldırım Bayezid', 'I. Murad', 'Çelebi Mehmed', 'II. Murad'],
        dogruIndex: 0,
        aciklama: 'Yıldırım Bayezid\'in Ankara Savaşı\'nda esir düşmesiyle '
            '1402-1413 arasında Fetret Devri (şehzadeler arası taht '
            'kavgaları) yaşanmıştır.',
        ipucuSonraki: 'Fetret Devri\'ne son vererek Osmanlı birliğini yeniden '
            'sağlayan, "İkinci Kurucu" olarak da anılan padişah kimdir?',
      ),
      ZincirAdim(
        soru: '1413\'te kardeşleriyle giriştiği taht mücadelesini kazanarak '
            'Fetret Devri\'ne son veren ve Osmanlı birliğini yeniden sağlayan '
            'padişah kimdir?',
        secenekler: ['Çelebi Mehmed (I. Mehmed)', 'II. Murad', 'Yıldırım Bayezid', 'II. Mehmed'],
        dogruIndex: 0,
        aciklama: 'Çelebi Mehmed (I. Mehmed), Fetret Devri\'ni sona erdirdiği '
            'için "İkinci Kurucu" olarak anılır.',
        ipucuSonraki: 'Çelebi Mehmed\'in oğlu, 1444\'te Varna ve 1448\'de II. '
            'Kosova savaşlarını kazanan, tahttan geçici olarak çekilip tekrar '
            'dönen padişah kimdir?',
      ),
      ZincirAdim(
        soru: '1444\'te Varna, 1448\'de II. Kosova savaşlarını kazanan, oğlu '
            'lehine tahttan geçici olarak çekilip sonra tekrar tahta çıkan '
            'padişah kimdir?',
        secenekler: ['II. Murad', 'II. Mehmed', 'Yıldırım Bayezid', 'Çelebi Mehmed'],
        dogruIndex: 0,
        aciklama: 'II. Murad döneminde kazanılan Varna ve II. Kosova zaferleri, '
            'oğlu Fatih Sultan Mehmed\'in İstanbul\'u fethetmesinin zeminini '
            'hazırlamıştır.',
      ),
    ],
  ),

  // ── 4. Türkiye'nin coğrafi bölgeleri ve doğal ortam özellikleri ──
  BilgiZinciri(
    id: 'zincir_cografya_bolgeler',
    baslik: 'Türkiye\'nin Coğrafyası',
    adimlar: [
      ZincirAdim(
        soru: 'Türkiye\'nin yüzölçümü bakımından en büyük coğrafi bölgesi '
            'hangisidir?',
        secenekler: ['İç Anadolu Bölgesi', 'Doğu Anadolu Bölgesi', 'Karadeniz Bölgesi', 'Akdeniz Bölgesi'],
        dogruIndex: 1,
        aciklama: 'Yüzölçümüne göre en büyük bölge Doğu Anadolu, en küçüğü ise '
            'Marmara Bölgesi\'dir.',
        ipucuSonraki: 'Doğu Anadolu Bölgesi\'nde bulunan, Türkiye\'nin en yüksek '
            'zirvesi olan volkanik dağın adı nedir?',
      ),
      ZincirAdim(
        soru: 'Doğu Anadolu Bölgesi\'nde yer alan, 5137 metre ile Türkiye\'nin '
            'en yüksek zirvesi olan volkanik dağ hangisidir?',
        secenekler: ['Ağrı Dağı', 'Erciyes Dağı', 'Süphan Dağı', 'Kaçkar Dağları'],
        dogruIndex: 0,
        aciklama: 'Ağrı Dağı, 5137 m ile Türkiye\'nin en yüksek noktasıdır ve '
            'sönmüş bir volkanik dağdır.',
        ipucuSonraki: 'Doğu Anadolu Bölgesi\'nde, bir volkanik set gölü olan ve '
            'Türkiye\'nin en büyük gölü olan sodalı gölün adı nedir?',
      ),
      ZincirAdim(
        soru: 'Nemrut Dağı\'ndan çıkan lavların bir vadinin önünü kapatmasıyla '
            'oluşan, Türkiye\'nin yüzölçümü en büyük gölü olan sodalı '
            '(alkali) göl hangisidir?',
        secenekler: ['Van Gölü', 'Tuz Gölü', 'Beyşehir Gölü', 'Eğirdir Gölü'],
        dogruIndex: 0,
        aciklama: 'Van Gölü, volkanik set gölü olarak oluşmuş, Türkiye\'nin en '
            'büyük gölüdür; suyu sodalıdır.',
        ipucuSonraki: 'Van Gölü Türkiye\'nin en büyük gölüyken, İç Anadolu '
            'Bölgesi\'nde bulunan ve tuzluluk oranı çok yüksek olan ikinci '
            'büyük gölümüz hangisidir?',
      ),
      ZincirAdim(
        soru: 'İç Anadolu Bölgesi\'nde yer alan, Türkiye\'nin tuz üretiminin '
            'büyük bölümünü karşılayan, yüksek tuzluluğa sahip göl hangisidir?',
        secenekler: ['Tuz Gölü', 'Van Gölü', 'Manyas Gölü', 'Sapanca Gölü'],
        dogruIndex: 0,
        aciklama: 'Tuz Gölü, İç Anadolu\'da bulunur; yaz aylarında aşırı '
            'buharlaşma nedeniyle tuz oranı çok yükselir.',
        ipucuSonraki: 'Tuz Gölü çevresinde de görülen, yazları sıcak-kurak, '
            'kışları soğuk ve kar yağışlı geçen İç Anadolu\'ya özgü iklim tipi '
            'hangisidir?',
      ),
      ZincirAdim(
        soru: 'İç Anadolu Bölgesi\'nde görülen, yazları sıcak ve kurak, '
            'kışları soğuk ve kar yağışlı geçen iklim tipi hangisidir?',
        secenekler: ['Karasal (step) iklimi', 'Akdeniz iklimi', 'Karadeniz iklimi', 'Ege iklimi'],
        dogruIndex: 0,
        aciklama: 'İç Anadolu\'da karasal iklim görülür; yıllık yağış azdır, '
            'kış-yaz sıcaklık farkı fazladır.',
        ipucuSonraki: 'Bu karasal (step) ikliminin görüldüğü İç Anadolu\'nun, '
            'ilkbaharda yeşerip yazın sararan doğal bitki örtüsüne ne ad verilir?',
      ),
      ZincirAdim(
        soru: 'İç Anadolu\'nun doğal bitki örtüsü olan, kısa boylu otsu '
            'bitkilerden oluşan, ilkbaharda yeşerip yaz sıcaklarında sararan '
            'bitki formasyonuna ne ad verilir?',
        secenekler: ['Step (bozkır)', 'Maki', 'Tundra', 'Orman'],
        dogruIndex: 0,
        aciklama: 'Step (bozkır), İç Anadolu\'nun karasal iklimine uyum '
            'sağlamış, kısa ömürlü otsu bitkilerden oluşan doğal bitki '
            'örtüsüdür.',
      ),
    ],
  ),

  // ── 5. Anayasal düzen: yasama, yürütme, yargı ──
  BilgiZinciri(
    id: 'zincir_anayasal_duzen',
    baslik: 'Türkiye\'nin Anayasal Düzeni',
    adimlar: [
      ZincirAdim(
        soru: 'Devlet yetkilerinin yasama, yürütme ve yargı olarak farklı '
            'organlar arasında paylaştırılması ilkesine ne ad verilir?',
        secenekler: ['Kuvvetler ayrılığı ilkesi', 'Hukuk devleti ilkesi', 'Laiklik ilkesi', 'Sosyal devlet ilkesi'],
        dogruIndex: 0,
        aciklama: 'Kuvvetler ayrılığı, keyfi yönetimi önlemek amacıyla devlet '
            'yetkilerinin farklı organlara dağıtılmasıdır.',
        ipucuSonraki: 'Türkiye\'de yasama yetkisini kullanan, milletvekillerinden '
            'oluşan organ hangisidir?',
      ),
      ZincirAdim(
        soru: 'Türkiye\'de yasama yetkisini kullanan, 600 milletvekilinden '
            'oluşan ve 5 yılda bir seçilen organ hangisidir?',
        secenekler: ['TBMM', 'Cumhurbaşkanlığı', 'Danıştay', 'Yargıtay'],
        dogruIndex: 0,
        aciklama: 'TBMM, 2017 Anayasa değişikliğiyle görev süresi 4 yıldan 5 '
            'yıla çıkarılan, yasama yetkisini kullanan organdır.',
        ipucuSonraki: 'Türkiye\'de yürütme yetkisini kullanan, 2018\'den '
            'itibaren yürürlükte olan sistemle halk tarafından doğrudan '
            'seçilen makam hangisidir?',
      ),
      ZincirAdim(
        soru: '2017 Anayasa değişikliğiyle 2018\'den itibaren yürütme '
            'yetkisinin tek başına verildiği, halk tarafından doğrudan seçilen '
            'makam hangisidir?',
        secenekler: ['Cumhurbaşkanı', 'Başbakan', 'TBMM Başkanı', 'Anayasa Mahkemesi Başkanı'],
        dogruIndex: 0,
        aciklama: 'Cumhurbaşkanlığı Hükümet Sistemi ile Başbakanlık kaldırılmış, '
            'yürütme yetkisi Cumhurbaşkanına verilmiştir.',
        ipucuSonraki: 'Türkiye\'de yargı yetkisini kullanan, hakim ve savcıların '
            'atama ve disiplin işlerini yürüten üst kurul hangisidir?',
      ),
      ZincirAdim(
        soru: 'Hakim ve savcıların mesleğe kabul, atama, nakil ve disiplin '
            'işlerini yürüten, eski adı HSYK olan kurul hangisidir?',
        secenekler: ['Hakimler ve Savcılar Kurulu (HSK)', 'Anayasa Mahkemesi', 'Danıştay', 'Sayıştay'],
        dogruIndex: 0,
        aciklama: 'HSK (eski adıyla HSYK), yargı bağımsızlığını sağlamak '
            'amacıyla hakim ve savcıların özlük işlerini yürütür.',
        ipucuSonraki: 'Kanunların ve KHK\'ların Anayasa\'ya uygunluğunu '
            'denetleyen en üst mahkeme hangisidir?',
      ),
      ZincirAdim(
        soru: 'Kanunların, Cumhurbaşkanlığı kararnamelerinin ve TBMM '
            'İçtüzüğü\'nün Anayasa\'ya uygunluğunu denetleyen mahkeme hangisidir?',
        secenekler: ['Anayasa Mahkemesi', 'Yargıtay', 'Danıştay', 'Sayıştay'],
        dogruIndex: 0,
        aciklama: 'Anayasa Mahkemesi, Anayasa yargısını yürüten, kanunların '
            'Anayasa\'ya uygunluğunu denetleyen en üst mahkemedir.',
        ipucuSonraki: 'Bireylerin temel hak ve özgürlüklerinin kamu gücü '
            'tarafından ihlal edildiği iddiasıyla Anayasa Mahkemesi\'ne '
            'yapabildiği başvuru yoluna ne ad verilir?',
      ),
      ZincirAdim(
        soru: '2010 Anayasa değişikliğiyle getirilen, 23 Eylül 2012\'den '
            'itibaren fiilen kullanılmaya başlanan, diğer başvuru yolları '
            'tükendikten sonra Anayasa Mahkemesi\'ne yapılan başvuru yoluna '
            'ne ad verilir?',
        secenekler: ['Bireysel başvuru', 'İptal davası', 'İtiraz yolu', 'Uyuşmazlık davası'],
        dogruIndex: 0,
        aciklama: 'Bireysel başvuru yolu, kişilerin temel hak ihlallerini '
            'Anayasa Mahkemesi önüne taşımasını sağlayan bir hak arama '
            'yoludur.',
      ),
    ],
  ),

  // ── 6. Kurtuluş Savaşı Cepheleri ──
  BilgiZinciri(
    id: 'zincir_kurtulus_cepheleri',
    baslik: 'Kurtuluş Savaşı Cepheleri',
    adimlar: [
      ZincirAdim(
        soru: 'Kurtuluş Savaşı\'nda Ermeni birliklerine karşı Doğu Cephesi\'nde '
            'mücadeleyi yöneten, Gümrü Antlaşması\'nı (3 Aralık 1920) '
            'imzalatan komutan kimdir?',
        secenekler: ['Kazım Karabekir', 'İsmet İnönü', 'Fevzi Çakmak', 'Refet Bele'],
        dogruIndex: 0,
        aciklama: 'Gümrü Antlaşması, TBMM\'nin uluslararası alanda tanındığı '
            'ilk antlaşmadır.',
        ipucuSonraki: 'Doğu Cephesi\'ndeki bu başarıdan sonra, Güney Cephesi\'nde '
            'işgalci Fransız kuvvetlerine karşı büyük ölçüde halkın (düzenli '
            'ordu değil) direnişiyle geçen mücadele hangi cephede yaşanmıştır?',
      ),
      ZincirAdim(
        soru: 'Fransız işgaline karşı düzenli ordu yerine büyük ölçüde halkın '
            'kendiliğinden oluşturduğu Kuvâ-yı Millîye direnişiyle geçen, '
            'Antep-Maraş-Urfa\'nın "Gazi" unvanı aldığı cephe hangisidir?',
        secenekler: ['Güney Cephesi', 'Doğu Cephesi', 'Batı Cephesi', 'Trakya Cephesi'],
        dogruIndex: 0,
        aciklama: 'Güney Cephesi\'nde düzenli ordu yerine yerel halk direnişi '
            'ön plandadır; bu yüzden diğer cephelerden ayrılır.',
        ipucuSonraki: 'Kurtuluş Savaşı\'nın asıl kararının verildiği, Yunan '
            'işgaline karşı düzenli ordunun savaştığı, İnönü savaşlarının, '
            'Sakarya\'nın ve Büyük Taarruz\'un yaşandığı cephe hangisidir?',
      ),
      ZincirAdim(
        soru: 'Yunan işgaline karşı düzenli Türk ordusunun savaştığı, I. ve II. '
            'İnönü, Sakarya Meydan Muharebesi ve Büyük Taarruz\'un yaşandığı '
            'cephe hangisidir?',
        secenekler: ['Batı Cephesi', 'Doğu Cephesi', 'Güney Cephesi', 'Kafkas Cephesi'],
        dogruIndex: 0,
        aciklama: 'Batı Cephesi, Kurtuluş Savaşı\'nın kaderinin belirlendiği, '
            'düzenli ordunun Yunanlara karşı savaştığı ana cephedir.',
        ipucuSonraki: 'Batı Cephesi\'nde düzenli ordunun Yunanlara karşı '
            'kazandığı, aynı zamanda TBMM\'nin ilk askeri zaferi olan savaş '
            'hangisidir?',
      ),
      ZincirAdim(
        soru: '6-10 Ocak 1921\'de kazanılan, düzenli ordunun ilk zaferi olan '
            've bu zaferden sonra TBMM\'nin ilk anayasayı (1921 Teşkilat-ı '
            'Esasiye Kanunu) kabul ettiği savaş hangisidir?',
        secenekler: ['I. İnönü Muharebesi', 'II. İnönü Muharebesi', 'Sakarya Meydan Muharebesi', 'Büyük Taarruz'],
        dogruIndex: 0,
        aciklama: 'I. İnönü Muharebesi, düzenli ordunun kazandığı ilk '
            'zaferdir ve TBMM\'nin uluslararası itibarını artırmıştır.',
        ipucuSonraki: 'I. İnönü\'den kısa süre sonra Yunanlıların yeniden '
            'saldırıya geçmesiyle yaşanan, İsmet Paşa\'nın "milletin makûs '
            'talihini de yendiniz" sözleriyle kutlandığı ikinci savaş hangisidir?',
      ),
      ZincirAdim(
        soru: '23 Mart - 1 Nisan 1921 tarihlerinde kazanılan, Mustafa '
            'Kemal\'in İsmet Paşa\'ya "Siz orada yalnız düşmanı değil, '
            'milletin makûs talihini de yendiniz" dediği savaş hangisidir?',
        secenekler: ['II. İnönü Muharebesi', 'I. İnönü Muharebesi', 'Sakarya Meydan Muharebesi', 'Kütahya-Eskişehir Muharebeleri'],
        dogruIndex: 0,
        aciklama: 'II. İnönü zaferi, Yunan ordusunun ikinci büyük saldırısını '
            'da boşa çıkarmıştır.',
        ipucuSonraki: 'II. İnönü\'den sonra Yunan ordusunun büyük bir taarruzla '
            'Sakarya Nehri\'ne kadar ilerlemesi üzerine, Mustafa Kemal\'in '
            'Başkomutanlık yetkisiyle bizzat yönettiği meydan savaşının '
            'ardından TBMM\'nin kendisine verdiği iki unvan nedir?',
      ),
      ZincirAdim(
        soru: 'Sakarya Meydan Muharebesi zaferinin ardından, 19 Eylül '
            '1921\'de TBMM\'nin Mustafa Kemal\'e verdiği iki unvan/rütbe '
            'aşağıdakilerden hangisidir?',
        secenekler: ['Mareşallik ve Gazilik', 'Başkomutanlık yetkisi', 'Cumhurbaşkanlığı', 'Meclis Başkanlığı'],
        dogruIndex: 0,
        aciklama: 'TBMM, 19 Eylül 1921\'de Mustafa Kemal\'e Mareşal rütbesi ve '
            'Gazi unvanını vermiştir.',
      ),
    ],
  ),

  // ── 7. İki savaş arası dönem Türk dış politikası ──
  BilgiZinciri(
    id: 'zincir_dis_politika',
    baslik: 'Atatürk Dönemi Dış Politikası',
    adimlar: [
      ZincirAdim(
        soru: 'Türkiye\'nin kurucu üyesi olmadığı, ancak 18 Temmuz 1932\'de '
            'üye olarak katıldığı, I. Dünya Savaşı sonrası kurulan '
            'uluslararası barış ve güvenlik örgütü hangisidir?',
        secenekler: ['Milletler Cemiyeti', 'Birleşmiş Milletler', 'NATO', 'Avrupa Konseyi'],
        dogruIndex: 0,
        aciklama: 'Türkiye, Milletler Cemiyeti\'ne 1932\'de üye olmuştur.',
        ipucuSonraki: 'Türkiye\'nin 1934\'te Yugoslavya, Romanya ve '
            'Yunanistan ile birlikte imzaladığı, Balkanlar\'daki sınırların '
            'güvenliğini amaçlayan ittifak hangisidir?',
      ),
      ZincirAdim(
        soru: '9 Şubat 1934\'te Türkiye, Yunanistan, Yugoslavya ve Romanya '
            'arasında imzalanan, Balkanlar\'daki sınırların güvenliğini '
            'amaçlayan ittifak hangisidir?',
        secenekler: ['Balkan Antantı', 'Sadabat Paktı', 'Küçük Antant', 'Varşova Paktı'],
        dogruIndex: 0,
        aciklama: 'Balkan Antantı, Balkan ülkeleri arasındaki sınırların '
            'karşılıklı güvence altına alınmasını amaçlamıştır.',
        ipucuSonraki: 'Türkiye\'nin 1937\'de İran, Irak ve Afganistan ile '
            'imzaladığı, Ortadoğu\'daki güvenliği amaçlayan benzer bir '
            'ittifak hangisidir?',
      ),
      ZincirAdim(
        soru: '8 Temmuz 1937\'de Tahran yakınlarındaki Sadabat Sarayı\'nda '
            'Türkiye, İran, Irak ve Afganistan arasında imzalanan ittifak '
            'antlaşması hangisidir?',
        secenekler: ['Sadabat Paktı', 'Balkan Antantı', 'Bağdat Paktı', 'Lozan Antlaşması'],
        dogruIndex: 0,
        aciklama: 'Sadabat Paktı, Ortadoğu\'da bölgesel güvenliği ve iş '
            'birliğini amaçlayan bir antlaşmadır.',
        ipucuSonraki: '20 Temmuz 1936\'da Türkiye\'nin, Lozan\'da '
            'sınırlandırılmış olan Boğazlar üzerindeki tam egemenlik hakkını '
            'yeniden kazandığı sözleşme hangisidir?',
      ),
      ZincirAdim(
        soru: '20 Temmuz 1936\'da imzalanan, Türkiye\'nin Boğazlar '
            'üzerindeki tam egemenlik hakkını yeniden kazandığı sözleşme '
            'hangisidir?',
        secenekler: ['Montrö Boğazlar Sözleşmesi', 'Lozan Antlaşması', 'Sevr Antlaşması', 'Ankara Antlaşması'],
        dogruIndex: 0,
        aciklama: 'Montrö Boğazlar Sözleşmesi ile Türkiye, Lozan\'da '
            'sınırlandırılmış boğazlar egemenliğini tam olarak yeniden '
            'kazanmıştır.',
        ipucuSonraki: 'Montrö\'den sonra, 1938\'de bağımsız bir devlet olarak '
            'ilan edilip 1939\'da meclis kararıyla Türkiye\'ye katılan, '
            'Atatürk\'ün vefatından kısa süre sonra anavatana kavuşan bölge '
            'neresidir?',
      ),
      ZincirAdim(
        soru: '1938\'de bağımsız bir devlet olarak kurulmuş, 29 Haziran '
            '1939\'da meclis kararıyla Türkiye\'ye katılan bölge neresidir?',
        secenekler: ['Hatay', 'Musul', 'Kerkük', 'Batum'],
        dogruIndex: 0,
        aciklama: 'Hatay, 1939\'da Türkiye\'ye katılmıştır; Atatürk, Hatay\'ın '
            'anavatana katılışını görmeden 10 Kasım 1938\'de vefat etmiştir.',
      ),
    ],
  ),

  // ── 8. Tanzimat'tan II. Meşrutiyet'e ──
  BilgiZinciri(
    id: 'zincir_tanzimat_mesrutiyet',
    baslik: 'Tanzimat\'tan Meşrutiyet\'e',
    adimlar: [
      ZincirAdim(
        soru: 'Sultan Abdülmecid döneminde, Mustafa Reşit Paşa\'nın '
            'öncülüğünde 3 Kasım 1839\'da ilan edilen, padişahın da '
            'kanunlara uyacağını kabul ettiği ilk belge hangisidir?',
        secenekler: ['Tanzimat Fermanı', 'Islahat Fermanı', 'Kanun-i Esasi', 'Sened-i İttifak'],
        dogruIndex: 0,
        aciklama: 'Tanzimat Fermanı (Gülhane Hatt-ı Hümayunu), Osmanlı\'da '
            'hukuk devletine geçişin ilk adımı sayılır.',
        ipucuSonraki: 'Tanzimat\'tan sonra, Kırım Savaşı\'nın ardından '
            '1856\'da ilan edilen ve gayrimüslimlere Müslümanlarla eşit '
            'haklar tanıyan ferman hangisidir?',
      ),
      ZincirAdim(
        soru: '1856\'da, Kırım Savaşı sonrası Paris Antlaşması öncesinde '
            'ilan edilen, gayrimüslim tebaaya Müslümanlarla eşit haklar '
            'tanıyan ferman hangisidir?',
        secenekler: ['Islahat Fermanı', 'Tanzimat Fermanı', 'Kanun-i Esasi', 'Sened-i İttifak'],
        dogruIndex: 0,
        aciklama: 'Islahat Fermanı, büyük devletlerin baskısıyla ilan edilmiş, '
            'gayrimüslimlerin hak ve statüsünü genişletmiştir.',
        ipucuSonraki: 'Osmanlı\'da ilk kez anayasal düzene geçişi sağlayan, '
            'II. Abdülhamit döneminde 23 Aralık 1876\'da ilan edilen '
            'anayasanın adı nedir?',
      ),
      ZincirAdim(
        soru: '23 Aralık 1876\'da ilan edilen, Osmanlı\'nın ilk yazılı '
            'anayasası olan ve I. Meşrutiyet\'in başlangıcı sayılan belge '
            'hangisidir?',
        secenekler: ['Kanun-i Esasi', 'Tanzimat Fermanı', 'Islahat Fermanı', 'Sened-i İttifak'],
        dogruIndex: 0,
        aciklama: 'Kanun-i Esasi ile I. Meşrutiyet ilan edilmiş, ilk Osmanlı '
            'Mebusan Meclisi açılmıştır.',
        ipucuSonraki: 'I. Meşrutiyet, II. Abdülhamit tarafından meclisin '
            'kapatılmasıyla askıya alınmıştır. Meclisin yeniden açılıp '
            'Kanun-i Esasi\'nin tekrar yürürlüğe girdiği, 1908\'deki '
            'gelişme hangisidir?',
      ),
      ZincirAdim(
        soru: '23 Temmuz 1908\'de İttihat ve Terakki Cemiyeti\'nin '
            'baskısıyla II. Abdülhamit\'in Kanun-i Esasi\'yi yeniden '
            'yürürlüğe koyup meclisi açtığı gelişme hangisidir?',
        secenekler: ['II. Meşrutiyet\'in ilanı', 'I. Meşrutiyet\'in ilanı', '31 Mart Vakası', 'Balkan Savaşları'],
        dogruIndex: 0,
        aciklama: 'II. Meşrutiyet, İttihat ve Terakki\'nin siyasi baskısıyla '
            'ilan edilmiştir.',
        ipucuSonraki: 'II. Meşrutiyet\'in ilanından kısa süre sonra, '
            '1911\'de İtalya\'nın saldırısıyla başlayan ve Osmanlı\'nın '
            'Kuzey Afrika\'daki son toprağını kaybetmesiyle sonuçlanan '
            'savaş hangisidir?',
      ),
      ZincirAdim(
        soru: '1911-1912 yıllarında İtalya\'nın saldırısıyla yaşanan, '
            'Mustafa Kemal ve Enver Bey\'in gönüllü olarak görev aldığı, '
            'Uşi Antlaşması ile Osmanlı\'nın Kuzey Afrika\'daki son '
            'toprağını kaybettiği savaş hangisidir?',
        secenekler: ['Trablusgarp Savaşı', 'Balkan Savaşları', 'I. Dünya Savaşı', 'Kırım Savaşı'],
        dogruIndex: 0,
        aciklama: 'Trablusgarp Savaşı sonunda imzalanan Uşi Antlaşması ile '
            'Osmanlı, Kuzey Afrika\'daki son toprağı olan Trablusgarp\'ı '
            'İtalya\'ya bırakmıştır.',
      ),
    ],
  ),
];
