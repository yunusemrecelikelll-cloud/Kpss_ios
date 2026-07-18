/// KPSS konu anlatım hocaları — derse göre gruplanmış. Her hocanın adı ve
/// mizaç (anlatım tarzı) açıklaması bulunur. Bir konu ekranında ilgili dersin
/// hocaları gösterilir; seçilen hocanın o konuyla ilgili YouTube araması açılır.
class Teacher {
  final String name;
  final String mizac;
  const Teacher(this.name, this.mizac);
}

const Map<String, List<Teacher>> kTeachersBySubject = {
  'turkce': [
    Teacher('Aker Kartal',
        "Tam bir motivasyon ve disiplin kaynağıdır. Videolarında 'Bunalıyorsan daha da bunalacaksın, bu iş çalışarak olur' gibi gerçekçi, sert ama babacan bir motivasyon mizacı vardır. Dersleri çok esprili geçer ve akılda kalıcı, eğlenceli kodlamalarla doludur."),
    Teacher('Rüştü Bayındır',
        "'Taktiklerin babası' olarak bilinir. Videoları genellikle daha kısa, doğrudan sınav odaklı ve stratejik adımlardan oluşur. Sakin, net, odaklanmış ve öğrenciye gereksiz detay yüklemeyen, öz güven aşılayan bir tarzı vardır."),
    Teacher('Öznur Saat Yıldırım',
        "Son derece düzenli, planlı ve anaç bir mizaçla ders anlatır. Yazı tahtasını veya slaytları kusursuz kullanır. Videoları baştan sona sistematik ilerler, kafa karıştırmayan, sakinleştirici ve güven veren bir ses tonuna sahiptir."),
    Teacher('Kadir Gümüş',
        "Edebiyat ve Türkçe alanında tam bir kültür insanı modundadır. Bilgili, entelektüel, ders aralarında konunun kökenine dair hikayeler ve şiirler paylaşan, dinlendirici ve derinlikli bir anlatım tarzı vardır."),
    Teacher('Gizem Ural',
        "Oldukça enerjik, güler yüzlü ve pozitiftir. Konuları basitleştirerek anlatmayı sever. Akıcı dil bilgisi kampları ve pratik şemalar içeren akıcı videolar hazırlar."),
    Teacher('Önder Hoca',
        "Kısa, nokta atışı, tamamen 'ÖSYM ne sorar?' mantığına odaklanan soru çözüm ve taktik videoları hazırlar. Zaman kazandıran, net ve pratik bir mizacı vardır."),
  ],
  'tarih': [
    Teacher('Ramazan Yetgin',
        "KPSS tarihinin efsanesidir. Klasik tahta düzenini mükemmel kullanır. Tarihi adeta bir dizi veya film gibi hikayeleştirerek, karakterleri yaşatarak anlatır. Ağırbaşlı, samimi, disiplinli ve her videoda ders çalışma bilinci aşılayan bir mizacı vardır."),
    Teacher('Aydın Yüce',
        "İnanılmaz enerjik, hareketli ve coşkuludur. Ders anlatırken adeta yaşar. Videoları bolca kahkaha, taklit ve akılda kalıcı hikayeler barındırır. Sıkılmaya asla vakit bırakmayan, dinamik bir sahne duruşu vardır."),
    Teacher('Mehmet Celal Özyıldız',
        "İnce esprileri, ironik yaklaşımı ve kendine has 'Öğretmenim...' hitaplarıyla çok sevilir. Tarihsel olaylar arasında kurduğu mantıksal ve esprili bağlar sayesinde en sıkıcı konuları bile eğlenceli sohbet havasındaki videolara dönüştürür."),
    Teacher('Selami Yalçın',
        "Özellikle sınav öncesi çektiği 'Genel Tekrar' videolarıyla bilinir. Kelime oyunları ve harf kodlamaları üzerinden giden, daha düz, sakin ama ezber bozan pratik bir anlatım tarzı benimser."),
    Teacher('Sadettin Akyayla',
        "Tam bir akademik birikim ve ciddiyet abidesidir. Kronolojik sırayı ve sebep-sonuç ilişkilerini çok derin işler. Ağırbaşlı, net ve akademik derinliği seven öğrencilere hitap eden videolar çeker."),
    Teacher('Hakan Dede',
        "Samimi, mahalle abisi tadında, sıcak bir anlatımı vardır. Konuları çok kasmadan, en sade haliyle öğrenciye aktarır. Soru çözüm videolarında şıkları tek tek eritmeyi çok iyi öğretir."),
    Teacher('Birol Yetimoğlu',
        "Akıcı, doğrudan hedefe giden ve gereksiz ayrıntılardan arındırılmış nokta atışı videolar hazırlar. Net ve kararlı bir mizaçla sınav formatını tam kalbinden vurmayı hedefler."),
  ],
  'cografya': [
    Teacher('Engin Eraydın',
        "Görsel hafızanın coğrafyadaki karşılığıdır. Renkli haritalar, esprili ve günlük hayattan örnekler, unutulması imkansız yerel kodlamalar kullanır. Doğal, samimi ve öğrenciyi ekran başında uyanık tutan canlı bir mizacı vardır."),
    Teacher('Mehmet Eğit',
        "'Hafıza Teknikleri' konseptinin öncüsüdür. Videolarında soyut bilgileri tamamen resimlerle ve hikayelerle somutlaştırır (örneğin turunçgil bölgesine bizzat portakal resmi koyarak anlatır). Sakin, zeki, analitik ve stratejik bir anlatım dili vardır."),
    Teacher('Ali Özgün',
        "Bölge bölge, dağ dağ harita çizmeyi ve harita okumayı öğretir. Net, akademik ama karmaşadan uzak, tane tane konuşan, öğretme odaklı sabırlı bir mizaç taşır."),
    Teacher('Bayram Meral',
        "Çok tecrübeli ve babacan bir tarza sahiptir. Türkiye coğrafyasını kendi gezdiği, gördüğü yerlerden anılar katarak samimi bir gezi programı tadında anlatır. Dinlendirici ve güven veren bir üslubu vardır."),
    Teacher('Hakan Bileyen',
        "Haritalar üzerinde nokta atışı kamplar yapar. Sınavda çıkma ihtimali en yüksek yerleri defalarca vurgulayan, dinamik ve tekrar odaklı videolar üretir."),
    Teacher('Erhan Altunok',
        "Efsanevi, derin ve etkileyici ses tonuyla şiir gibi ders anlatır. Coğrafyayı adeta edebi bir hikayeye dönüştürür. Estetik, sakin ve dinlemesi aşırı keyifli bir üslubu vardır."),
  ],
  'matematik': [
    Teacher('İlyas Güneş',
        "Matematikten korkanların sığınağıdır. En temelden, 'x nedir'den başlayarak adım adım zirveye taşır. 'Güzel insan', 'canım benim' gibi samimi hitapları, sabırlı anlatımı, bol soru çözümlü ve her seviyeye hitap eden kucaklayıcı bir mizacı vardır."),
    Teacher('Mehmet Bilge Yıldız',
        "Sorulara yaklaşım mantığını ve pratik kısayolları öğretmeye odaklanır. Formül ezberletmek yerine işin mantığını anlatırken esprili, uyanık ve öğrenciyi ters köşe yapmayı seven enerjik bir tarz kullanır."),
    Teacher('Rehber Matematik (Mehmet Hoca)',
        "'Gülümse' mottosuyla tamamen pozitif enerji üzerine kuruludur. Dijital ekranı çok iyi kullanır, renkli grafikler ve 'parçala alıştır' taktiğiyle matematiği kağıt üzerinde çok eğlenceli ve modern bir sunumla anlatır."),
    Teacher('Mert Hoca',
        "'Matematik bir sanattır' felsefesiyle yaklaşır. Yoğun kamp videoları çeker. Ciddi, disiplinli, işini çok sıkı tutan ama öğrenciyle doğrudan empati kurabilen, samimi ve karizmatik bir anlatım dili vardır."),
    Teacher('Şenol Hoca',
        "Matematiğin temelini sıfırdan atmak isteyenler için tam bir kılavuzdur. Çok basit, yalın, ilkokul seviyesinden alıp lise/KPSS seviyesine getiren, sakin ve aşırı net bir tarzı vardır."),
    Teacher('Deniz Atalay',
        "Geometri ve matematikte zor soruların pratik çözümlerini gösterir. Analitik düşündüren, işlem kalabalığından kurtaran, zeki ve teknik odaklı bir mizacı vardır."),
    Teacher('Ömer Karaman',
        "Klasik tarzın dışına çıkıp yeni nesil mantık sorularına yoğunlaşır. Matematiksel akıl yürütmeyi sevdiren, hırslı ve başarı odaklı videolar hazırlar."),
  ],
  'vatandaslik': [
    Teacher('Esra Özkan Karaoğlu',
        "Hukuk ve anayasa gibi ağır konuları günlük hayattaki dedikodularla, akraba ilişkileriyle ve şemalarla harmanlar. Çok güler yüzlü, enerjik, samimi ve ezberi tamamen ortadan kaldıran şeffaf bir anlatımı vardır."),
    Teacher('Erdal Kesekler',
        "Çok akıcı ve seri konuşur, derslerinde zaman su gibi akar. Sıkıcı hukuki terimleri en popüler güncel olaylarla bağdaştırarak anlatır. Esprili, uyanık ve sınav tüyolarını havada uçuşturan bir üslubu vardır."),
    Teacher('Ali Koç',
        "Kavram haritalarını ve tabloları tahtaya mükemmel işler. Düzenli, disiplinli, ders esnasında konudan sapmayan, bilgiyi en duru ve yasal netliğiyle aktaran ağırbaşlı bir hocadır."),
    Teacher('Emrah Vahap Özkaraca',
        "Hukuk mantığını oturtmaya çalışır. Maddeleri ezberletmek yerine 'Bu kanun neden çıktı?' mantığını sorgulatır. Entelektüel, ciddi ama öğrenciyi sürekli uyanık tutan etkileyici bir hitabeti vardır."),
    Teacher('Sait Zaman',
        "Kısa, akılda kalıcı kodlamalarla ve nokta atışı güncel bilgilerle nokta atışı videolar çeker. Pratik, sonuç odaklı ve sınav öncesi hayat kurtaran bir mizaca sahiptir."),
    Teacher('Özgür Özkınık',
        "Hukukun temel kavramlarını çok eğlenceli skeç tadındaki örneklerle anlatır. Tane tane konuşan, sabırlı, öğrencinin gözünü korkutmadan anayasayı sevdiren sakin bir tarzı vardır."),
  ],
};

/// Seçilen hoca + ders + konu için YouTube arama bağlantısı üretir. Belirli bir
/// video kimliği uydurmak yerine arama linki kullanılır — böylece link her zaman
/// geçerli olur ve hocanın o konudaki güncel videolarını gösterir.
String youtubeSearchUrlFor(String teacherName, String subjectAd, String topicBaslik) {
  final q = Uri.encodeQueryComponent('$teacherName KPSS $subjectAd $topicBaslik konu anlatımı');
  return 'https://www.youtube.com/results?search_query=$q';
}
