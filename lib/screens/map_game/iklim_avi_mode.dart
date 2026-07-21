import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/turkey_map_data.dart';
import '../../services/sound_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_provider.dart';
import '../tools_hub_screen.dart';
import 'map_shared.dart';

/// Bir oturumda sorulan soru sayısı — kullanıcı isteğiyle 8'den 5'e çekildi.
const int kIklimRounds = 5;

const String _kHowToPlay =
    'Ekranda iklimle ilgili bir ipucu yazar (yağış rejimi, sıcaklık farkı, don '
    'olayı, kar süresi, doğal bitki örtüsü, nem, yaz kuraklığı, iklime bağlı '
    'tarım ürünü...). Bu tarife UYAN illerden birine haritada dokun. Soruda '
    'iklimin ADI verilmez — tarife bakıp hangi ilin uyduğunu SEN çıkarırsın. '
    'Yanlış dokunursan 3 hakkın vardır; üçünü de kullanırsan doğru iller '
    'haritada yeşil gösterilir ve sıradaki soruya geçilir.';

/// Tek bir "İklim Avı" sorusu.
///
/// ÖNEMLİ (kullanıcı isteğiyle yapılan köklü değişiklik): Eski sürümde soru
/// yalnızca bir iklim ADI ("Karadeniz iklimi görülen bir il seç") söylüyor,
/// cevap da o adı taşıyan bölgenin illeri oluyordu — yani oyun "Bölgeyi Bul"
/// modunun neredeyse aynısıydı ve HİÇBİR iklim bilgisi ölçmüyordu. Bu tip
/// birebir eşleşen sorular TAMAMEN KALDIRILDI. Artık her soru bir iklim
/// ÖZELLİĞİNİ tarif eder (yağış rejimi, karasallık/sıcaklık farkı, don, kar
/// örtüsü süresi, doğal bitki örtüsü, nem, yaz kuraklığı, iklim-tarım
/// ilişkisi) ve kullanıcının bu tariften ile ULAŞMASINI ister.
class IklimSorusu {
  /// Kullanıcıya gösterilen ipucu/soru metni. İklim tipinin ADINI VERMEZ.
  final String soru;

  /// Bu tarife uyan il id'leri (bkz. lib/data/turkey_map_data.dart). Bunlardan
  /// HERHANGİ birine dokunmak doğru kabul edilir.
  final Set<String> dogruIller;

  /// Cevap sonrası gösterilen, bilgiyi pekiştiren kısa açıklama.
  final String aciklama;

  const IklimSorusu({
    required this.soru,
    required this.dogruIller,
    required this.aciklama,
  });
}

/// İklim Avı soru havuzu — her oyunda buradan RASTGELE [kIklimRounds] soru
/// seçilir (bkz. [_soruSec]), böylece her oturum farklı olur.
///
/// İçerik notu: Tüm sorular ortaöğretim/KPSS coğrafya müfredatındaki yerleşik
/// iklim bilgilerine dayanır (yağış rejimi ve miktarı, karasallık derecesi,
/// don ve kar örtüsü süresi, doğal bitki örtüsü kuşakları, nem/güneşlenme,
/// iklimin tarım ürünü desenine etkisi). Doğru cevap kümeleri, tarifin
/// TARTIŞMASIZ geçerli olduğu illerle sınırlı tutulmuştur.
const List<IklimSorusu> kIklimSorulari = [
  // ── Yağış rejimi ve miktarı ──────────────────────────────────────────
  IklimSorusu(
    soru: 'Her mevsimi yağışlı geçen, yıllık yağışın 1000 mm\'yi aştığı bir ile dokun.',
    dogruIller: {'rize', 'artvin', 'trabzon', 'giresun', 'ordu', 'zonguldak', 'bartin', 'duzce', 'sinop'},
    aciklama: 'Kuzey Anadolu Dağları\'nın denize bakan yamaçlarında nemli hava yükselerek yıl boyu yağış '
        'bırakır. Bu kıyı kuşağında yağış her mevsime dağılır; kurak mevsim yoktur.',
  ),
  IklimSorusu(
    soru: 'Türkiye\'nin en çok yağış alan, yıllık yağışı 2000 mm\'yi geçen ilini bul.',
    dogruIller: {'rize'},
    aciklama: 'Rize, yılda yaklaşık 2200-2400 mm yağışla Türkiye\'nin en yağışlı ilidir. Dağların denize '
        'çok yakın ve dik olması yağışı artırır.',
  ),
  IklimSorusu(
    soru: 'Yıllık yağışın 400 mm\'nin altında kaldığı, kuraklığın en şiddetli hissedildiği bir ile dokun.',
    dogruIller: {'konya', 'karaman', 'aksaray', 'igdir', 'nevsehir'},
    aciklama: 'Türkiye\'nin en az yağış alan yerleri Tuz Gölü çevresi (Konya-Karaman-Aksaray) ve Iğdır '
        'Ovası\'dır; buralarda yıllık yağış 250-400 mm arasında kalır. Çevredeki dağlar nemli havayı keser.',
  ),
  IklimSorusu(
    soru: 'Yağışın büyük bölümünü kış aylarında alan, yaz yağışı toplam yağışın %10\'unun altında kalan bir ile dokun.',
    dogruIller: {'antalya', 'mugla', 'mersin', 'izmir', 'aydin', 'hatay', 'adana', 'osmaniye'},
    aciklama: 'Güney ve batı kıyılarımızda yazın kuru ve sıcak hava kütleleri etkilidir; yağışların neredeyse '
        'tamamı kış yarıyılında düşer. Yaz kuraklığı bu kıyıların temel özelliğidir.',
  ),
  IklimSorusu(
    soru: 'En yağışlı mevsimin İLKBAHAR olduğu, yağış rejiminin düzensiz olduğu bir ile dokun.',
    dogruIller: {'konya', 'ankara', 'kirsehir', 'yozgat', 'sivas', 'nevsehir', 'nigde', 'aksaray', 'karaman', 'kayseri', 'cankiri', 'kirikkale', 'eskisehir'},
    aciklama: 'Denizden uzak, etrafı dağlarla çevrili yüksek düzlüklerde yağış en çok ilkbaharda düşer; '
        'yaz ise kuraktır. Bu düzensiz rejim tarımda sulamayı zorunlu kılar.',
  ),
  IklimSorusu(
    soru: 'Yaz aylarında da yağış aldığı için tarlanın dinlendirilmesine (nadasa) gerek kalmayan bir ile dokun.',
    dogruIller: {'rize', 'trabzon', 'giresun', 'ordu', 'artvin', 'samsun', 'sinop', 'zonguldak', 'bartin', 'duzce', 'sakarya'},
    aciklama: 'Nadas, yağışın yetersiz olduğu yerlerde toprakta nem biriktirmek için uygulanır. Yaz dâhil '
        'her mevsim yağış alan kıyı kuşağında toprak nemi yeterli olduğundan nadasa ihtiyaç duyulmaz.',
  ),
  IklimSorusu(
    soru: 'Yağış yetersizliği yüzünden nadas uygulamasının en yaygın olduğu bir ile dokun.',
    dogruIller: {'konya', 'karaman', 'aksaray', 'ankara', 'yozgat', 'sivas', 'cankiri', 'kirsehir', 'nigde', 'nevsehir', 'kirikkale', 'eskisehir'},
    aciklama: 'Yağışın az ve düzensiz olduğu iç kesimlerde toprak bir yıl ekilmeyip nem biriktirmesi için '
        'dinlendirilir. Nadas alanlarının en geniş olduğu yerler bu kurak düzlüklerdir.',
  ),

  // ── Sıcaklık farkı / karasallık ──────────────────────────────────────
  IklimSorusu(
    soru: 'Yaz ile kış arasındaki sıcaklık farkının en yüksek olduğu, kışın -30 °C\'ye kadar düşebilen bir ile dokun.',
    dogruIller: {'agri', 'kars', 'ardahan', 'erzurum', 'mus', 'bitlis', 'hakkari', 'van', 'bingol', 'sivas'},
    aciklama: 'Denizden uzaklık ve yüksek rakım karasallığı artırır: yazlar sıcak, kışlar çok soğuk geçer. '
        'Yıllık sıcaklık farkının 30 °C\'yi aştığı yerler bu yüksek doğu kesimidir.',
  ),
  IklimSorusu(
    soru: 'Türkiye\'nin en düşük kış sıcaklıklarının ölçüldüğü ilimize dokun.',
    dogruIller: {'agri', 'kars', 'ardahan', 'erzurum', 'van'},
    aciklama: 'Türkiye\'nin en düşük sıcaklık kayıtları Ağrı ve Van (Çaldıran) çevresinde, -40 °C\'nin '
        'altında ölçülmüştür. Yükselti, karasallık ve çanak biçimli araziler soğuk havanın göllenmesine yol açar.',
  ),
  IklimSorusu(
    soru: 'Ortalama yükseltisi Türkiye\'nin en fazla olan kesimde yer aldığı için aynı enlemdeki illere göre çok daha soğuk geçen bir ile dokun.',
    dogruIller: {'hakkari', 'van', 'agri', 'kars', 'ardahan', 'erzurum', 'bitlis', 'mus', 'bingol', 'tunceli', 'erzincan'},
    aciklama: 'Sıcaklık her 200 metre yükseltide yaklaşık 1 °C düşer. Ortalama yükseltisi 2000 metreye '
        'yaklaşan bu kesimde, enlem aynı olsa bile sıcaklıklar belirgin biçimde düşüktür.',
  ),
  IklimSorusu(
    soru: 'Yıllık ortalama sıcaklığı Türkiye\'de en yüksek olan illerden birine dokun.',
    dogruIller: {'hatay', 'mersin', 'adana', 'antalya', 'osmaniye'},
    aciklama: 'Güney kıyılarımız hem enlem olarak güneyde hem de deniz etkisi altındadır; yıllık ortalama '
        'sıcaklık 18-20 °C civarındadır. Kışın bile ortalama sıcaklık 9-10 °C\'nin altına inmez.',
  ),
  IklimSorusu(
    soru: 'Ocak ayı ortalama sıcaklığı bile 0 °C\'nin çok üzerinde kalan, kışları serin ve yağışlı geçen bir kıyı iline dokun.',
    dogruIller: {'izmir', 'aydin', 'mugla', 'antalya', 'mersin', 'adana', 'hatay', 'osmaniye'},
    aciklama: 'Deniz, kışın yavaş soğuduğu için kıyıları ılıtır. Bu kıyılarda ocak ortalaması 8-10 °C '
        'dolayındadır; bu yüzden kışın bitki örtüsü yeşil kalabilir.',
  ),

  // ── Don olayı ve kar örtüsü ──────────────────────────────────────────
  IklimSorusu(
    soru: 'Kar örtüsünün yerde 4 aydan uzun süre kaldığı bir ile dokun.',
    dogruIller: {'agri', 'kars', 'ardahan', 'erzurum', 'hakkari', 'bitlis', 'mus', 'van', 'bingol'},
    aciklama: 'Yüksek ve karasal kesimlerde kar erken yağar, geç erir. Kar örtüsünün yerde kalma süresi '
        'burada 120 günü aşar; bu da tarım mevsimini kısaltıp yol/ulaşım sorunları doğurur.',
  ),
  IklimSorusu(
    soru: 'Don olaylı gün sayısının en fazla olduğu, bu yüzden tarım mevsiminin en kısa sürdüğü bir ile dokun.',
    dogruIller: {'agri', 'kars', 'ardahan', 'erzurum', 'hakkari', 'bitlis', 'mus', 'van', 'bingol'},
    aciklama: 'Donlu gün sayısının 150 günü aştığı bu kesimde ekim-hasat arası çok kısalır; bu nedenle '
        'yalnızca yazlık ve kısa sürede olgunlaşan ürünler yetiştirilebilir.',
  ),
  IklimSorusu(
    soru: 'Kışın donun neredeyse hiç görülmemesi sayesinde muz yetiştirilebilen bir ile dokun.',
    dogruIller: {'mersin', 'antalya'},
    aciklama: 'Muz, don olayına dayanamayan tropikal kökenli bir bitkidir. Türkiye\'de ancak Anamur '
        '(Mersin) ve Alanya (Antalya) çevresinde, Toroslar\'ın soğuğu kestiği dar kıyı şeridinde yetişir.',
  ),
  IklimSorusu(
    soru: 'İlkbahar geç donlarının meyve bahçelerine sık sık zarar verdiği, karasal koşulların hüküm sürdüğü bir ile dokun.',
    dogruIller: {'malatya', 'elazig', 'nigde', 'konya', 'kayseri', 'isparta', 'karaman', 'nevsehir'},
    aciklama: 'Karasal iç kesimlerde ilkbaharda hava aniden ısınıp ağaçlar çiçek açtıktan sonra gelen '
        'geç donlar ürünü vurur. Kayısı ve elma üretiminde yıllık rekolte bu yüzden çok değişkendir.',
  ),
  IklimSorusu(
    soru: 'Kar yağışının kıyı kesimde çok nadir görüldüğü, kışın yağışın yağmur biçiminde düştüğü bir ile dokun.',
    dogruIller: {'antalya', 'mersin', 'hatay', 'mugla', 'izmir', 'adana', 'osmaniye', 'aydin'},
    aciklama: 'Kış sıcaklıkları donma noktasının belirgin biçimde üzerinde seyrettiği için yağış yağmur '
        'olarak düşer. Aynı illerin Toroslar üzerindeki yüksek kesimlerinde ise kar aylarca kalabilir.',
  ),

  // ── Doğal bitki örtüsü ───────────────────────────────────────────────
  IklimSorusu(
    soru: 'Doğal bitki örtüsü MAKİ olan, kızılçam ormanlarının yaygın görüldüğü bir ile dokun.',
    dogruIller: {'antalya', 'mugla', 'mersin', 'izmir', 'aydin', 'adana', 'hatay', 'canakkale', 'balikesir', 'osmaniye'},
    aciklama: 'Maki, yazın kurak geçen ılıman kıyılara uyum sağlamış, kışın yaprağını dökmeyen sert '
        'yapraklı çalı topluluğudur. Bu kıyılarda makinin üstünde kızılçam ormanları yer alır.',
  ),
  IklimSorusu(
    soru: 'Doğal bitki örtüsü BOZKIR (step) olan, yetersiz yağış yüzünden doğal orman yetişemeyen bir ile dokun.',
    dogruIller: {'konya', 'karaman', 'aksaray', 'ankara', 'kirsehir', 'nevsehir', 'nigde', 'yozgat', 'sivas', 'cankiri', 'kirikkale', 'eskisehir'},
    aciklama: 'Yağışın az, yaz kuraklığının uzun olduğu iç düzlüklerde ağaç yetişemez; ilkbaharda yeşerip '
        'yazın kuruyan otsu bitkilerden oluşan bozkır örtüsü hâkimdir.',
  ),
  IklimSorusu(
    soru: 'Bol yağış ve yüksek nem sayesinde yamaçların deniz seviyesinden itibaren gür ormanlarla kaplandığı bir ile dokun.',
    dogruIller: {'rize', 'artvin', 'trabzon', 'giresun', 'ordu', 'sinop', 'kastamonu', 'bartin', 'zonguldak', 'duzce', 'bolu'},
    aciklama: 'Yıl boyu yağış ve yüksek nem, orman için en elverişli koşulları oluşturur. Türkiye\'nin '
        'orman varlığı bakımından en zengin kuşağı bu nemli yamaçlardır.',
  ),
  IklimSorusu(
    soru: 'Yaz yağışlarıyla gelişen gür ÇAYIR örtüsü sayesinde büyükbaş hayvancılığın öne çıktığı bir ile dokun.',
    dogruIller: {'erzurum', 'kars', 'ardahan', 'agri', 'mus'},
    aciklama: 'Yüksek platolarda yaz yağışları otları yeşertir ve geniş çayır-mera alanları oluşur. Bu '
        'doğal yem kaynağı, bölgede büyükbaş hayvancılığın ve mandıracılığın gelişmesini sağlamıştır.',
  ),

  // ── Nem, güneşlenme, sis ─────────────────────────────────────────────
  IklimSorusu(
    soru: 'Bağıl nem oranının Türkiye\'de en yüksek olduğu bir ile dokun.',
    dogruIller: {'rize', 'artvin', 'trabzon', 'giresun', 'ordu', 'sinop'},
    aciklama: 'Denizden gelen sürekli nemli hava ve bol yağış, kuzey kıyı kuşağında bağıl nemi yıl boyu '
        'yüksek tutar. Yüksek nem, günlük sıcaklık farkını da azaltır.',
  ),
  IklimSorusu(
    soru: 'Bulutluluk ve sisin fazla olması nedeniyle yıllık güneşlenme süresinin Türkiye\'de en az olduğu bir ile dokun.',
    dogruIller: {'rize', 'artvin', 'trabzon', 'giresun', 'ordu', 'sinop', 'zonguldak', 'bartin'},
    aciklama: 'Sürekli bulutlu ve yağışlı hava, kuzey kıyılarında güneşlenme süresini kısaltır. Bu yüzden '
        'güneş enerjisi potansiyeli Türkiye\'nin en düşük olduğu kesim burasıdır.',
  ),
  IklimSorusu(
    soru: 'Yaz sıcaklıklarının 45 °C\'yi aştığı, Türkiye\'nin en sıcak yazlarının yaşandığı bir ile dokun.',
    dogruIller: {'sanliurfa', 'diyarbakir', 'sirnak', 'mardin', 'batman', 'siirt', 'adiyaman'},
    aciklama: 'Güneydoğudaki alçak platolarda yazın çöl kökenli sıcak hava kütleleri etkili olur; '
        'sıcaklık rekorları (Cizre/Şırnak, Şanlıurfa) 48-49 °C\'ye ulaşmıştır.',
  ),
  IklimSorusu(
    soru: 'Yaz kuraklığının en uzun sürdüğü, yaz aylarında aylarca ölçülebilir yağış düşmeyen bir ile dokun.',
    dogruIller: {'antalya', 'mersin', 'mugla', 'adana', 'hatay', 'izmir', 'aydin', 'osmaniye'},
    aciklama: 'Bu kıyılarda haziran-eylül arası neredeyse tamamen kurak geçer. Uzun yaz kuraklığı hem '
        'orman yangını riskini artırır hem de tarımda sulamayı zorunlu kılar.',
  ),

  // ── Geçiş özellikleri ve yerel (mikro) iklimler ──────────────────────
  IklimSorusu(
    soru: 'Kuzeydeki nemli ile güneydeki yaz kurak iklim arasında GEÇİŞ özelliği gösteren, iki iklimin de yumuşamış hâlinin görüldüğü bir ile dokun.',
    dogruIller: {'istanbul', 'kocaeli', 'sakarya', 'bursa', 'balikesir', 'canakkale', 'tekirdag', 'edirne', 'kirklareli', 'yalova', 'bilecik'},
    aciklama: 'Bu kesimde kışlar Akdeniz kıyılarına göre soğuk, iç kesimlere göre ılıktır; yaz kuraklığı '
        'vardır ama Akdeniz kıyıları kadar şiddetli değildir. Bu nedenle "geçiş iklimi" denir.',
  ),
  IklimSorusu(
    soru: 'Doğu Anadolu\'da yer aldığı hâlde çukur ova özelliği ve yerel iklimi sayesinde pamuk, çeltik ve kayısı yetiştirilebilen ilimize dokun.',
    dogruIller: {'igdir'},
    aciklama: 'Iğdır Ovası yaklaşık 850 metre yükseltiyle çevresindeki 2000 metrelik platolardan çok '
        'alçaktır. Bu çukurluk sıcaklığı yükselttiğinden bölgenin genel iklimine aykırı ürünler yetişir; '
        'Iğdır aynı zamanda Türkiye\'nin en az yağış alan yerlerindendir.',
  ),
  IklimSorusu(
    soru: 'Çevresi yüksek dağlarla kuşatılmış çukur bir ovada yer aldığı için çevresine göre daha ılıman geçen, kuru kayısısıyla ünlü ilimize dokun.',
    dogruIller: {'malatya'},
    aciklama: 'Malatya Ovası, çevresindeki yüksek kesimlere göre alçakta kaldığı için daha ılıman bir '
        'yerel iklime sahiptir. Bu koşullar Türkiye kuru kayısı üretiminin büyük bölümünü karşılamasını sağlar.',
  ),
  IklimSorusu(
    soru: 'Akdeniz\'e yakın olmasına rağmen yüksekliği ve Toroslar\'ın gerisinde kalması yüzünden karasal koşulların görüldüğü bir ile dokun.',
    dogruIller: {'isparta', 'burdur', 'karaman'},
    aciklama: 'Toroslar denizin ılıtıcı etkisini iç kesimlere geçirmez. Dağların gerisinde kalan ve '
        'yükseltisi 1000 metreyi aşan bu yörede kışlar soğuk, yağış rejimi karasaldır.',
  ),
  IklimSorusu(
    soru: 'Kıyıdaki komşusuyla arasında dağlar bulunduğu için deniz etkisinden yoksun kalan, kışları çok daha soğuk geçen iç kesimdeki bir ile dokun.',
    dogruIller: {'gumushane', 'bayburt', 'erzincan'},
    aciklama: 'Kuzey Anadolu Dağları\'nın güneyinde kalan bu iller, nemli deniz havasının gerisinde '
        'kaldığından hem çok daha az yağış alır hem de kışları sert geçer. Buna "yağış gölgesi" denir.',
  ),
  IklimSorusu(
    soru: 'Yazları serin ve nemli geçtiği için yaylacılığın çok geliştiği bir ile dokun.',
    dogruIller: {'rize', 'trabzon', 'giresun', 'artvin', 'ordu', 'gumushane', 'bayburt'},
    aciklama: 'Yaz yağışlarının sürdüğü serin yüksek yaylalarda otlaklar yaz boyunca yeşil kalır. Bu '
        'nedenle yaz aylarında hayvanlarla birlikte yaylaya çıkma geleneği bu kuşakta çok yaygındır.',
  ),
  IklimSorusu(
    soru: 'Kısa bir yatay mesafede deniz kıyısından yüksek dağlara çıkıldığı için ovasıyla yaylası arasında iklimin tamamen değiştiği bir ile dokun.',
    dogruIller: {'adana', 'mersin', 'antalya', 'hatay', 'kahramanmaras'},
    aciklama: 'Toroslar kıyıya çok yakın ve yüksektir. Ovada narenciye ve pamuk yetişirken, birkaç on '
        'kilometre içeride yükselti nedeniyle serin iklim koşulları ve kar örtüsü görülür.',
  ),

  // ── İklim - tarım ürünü ilişkisi ─────────────────────────────────────
  IklimSorusu(
    soru: 'Yıl boyu yağış ve asitli toprak istediği için çay tarımının yapılabildiği bir ile dokun.',
    dogruIller: {'rize', 'trabzon', 'artvin', 'giresun', 'ordu'},
    aciklama: 'Çay; yaz kuraklığına dayanamayan, yıl boyu nem ve bol yağış isteyen bir bitkidir. '
        'Türkiye\'de yalnızca Doğu Karadeniz kıyı kuşağında bu koşullar bir arada bulunur.',
  ),
  IklimSorusu(
    soru: 'Her mevsim yağışlı iklim sayesinde fındığın en çok yetiştirildiği illerden birine dokun.',
    dogruIller: {'ordu', 'giresun', 'samsun', 'trabzon', 'sakarya', 'duzce', 'zonguldak'},
    aciklama: 'Fındık, yaz kuraklığı istemeyen ve don riskine duyarlı bir bitkidir. Kuzey kıyı kuşağının '
        'nemli, ılıman ve her mevsim yağışlı koşulları fındık için idealdir.',
  ),
  IklimSorusu(
    soru: 'Kışların ılık geçmesi ve don olmaması sayesinde zeytin yetiştiriciliğinin yapıldığı bir ile dokun.',
    dogruIller: {'izmir', 'aydin', 'mugla', 'manisa', 'balikesir', 'canakkale', 'bursa', 'hatay', 'mersin', 'antalya'},
    aciklama: 'Zeytin, kışın -7 °C\'nin altındaki sıcaklıklara dayanamaz; bu yüzden yayılışı ılıman kıyı '
        'kuşağıyla sınırlıdır. Zeytinin sınırı, aynı zamanda ılıman kıyı ikliminin de doğal sınırı sayılır.',
  ),
  IklimSorusu(
    soru: 'Kış sıcaklıklarının yeterince yüksek olması sayesinde turunçgil (narenciye) üretiminin yapıldığı bir ile dokun.',
    dogruIller: {'adana', 'mersin', 'antalya', 'hatay', 'osmaniye'},
    aciklama: 'Turunçgiller don olayına çok duyarlıdır ve kışın ılık geçmesini ister. Türkiye üretiminin '
        'neredeyse tamamı bu güney kıyı ovalarından karşılanır.',
  ),
  IklimSorusu(
    soru: 'Yazları sıcak, kışları soğuk ve yağışın az olduğu koşullarda yetişen şeker pancarının en çok üretildiği bir ile dokun.',
    dogruIller: {'konya', 'yozgat', 'eskisehir', 'afyonkarahisar', 'kayseri', 'sivas', 'aksaray', 'ankara'},
    aciklama: 'Şeker pancarı karasal iklimin ürünüdür: yazın sıcak ve uzun bir büyüme dönemi ister, '
        'sulama ile yetiştirilir. Üretimin ağırlık merkezi iç kesimlerdeki karasal düzlüklerdir.',
  ),
  IklimSorusu(
    soru: 'Yazları sıcak-kurak, kışları soğukça geçen koşullarda yetişen Antep fıstığının öne çıktığı bir ile dokun.',
    dogruIller: {'gaziantep', 'sanliurfa', 'siirt', 'adiyaman', 'kahramanmaras', 'kilis', 'mardin'},
    aciklama: 'Antep fıstığı kuraklığa çok dayanıklıdır ve yazın uzun süren sıcaklık ister; kışın ise '
        'belirli bir soğuklama süresine ihtiyaç duyar. Bu ikili istek güneydoğudaki koşullarla karşılanır.',
  ),
  IklimSorusu(
    soru: 'Bol su ve yüksek yaz sıcaklığı isteyen çeltik (pirinç) tarımının delta ovalarında yapıldığı bir ile dokun.',
    dogruIller: {'samsun', 'edirne', 'corum', 'balikesir'},
    aciklama: 'Çeltik, tarlanın su altında tutulmasını ve sıcak bir yetişme dönemini gerektirir. Bafra-'
        'Çarşamba (Samsun) ve Meriç (Edirne) ovaları Türkiye çeltik üretiminin merkezleridir.',
  ),
  IklimSorusu(
    soru: 'Yüksek nem ve bol yağış yüzünden buğdayın iyi sonuç vermediği, bunun yerine mısır tarımının öne çıktığı bir ile dokun.',
    dogruIller: {'rize', 'trabzon', 'giresun', 'ordu', 'artvin', 'sinop', 'bartin', 'zonguldak', 'duzce'},
    aciklama: 'Buğday hasat döneminde kuru hava ister; sürekli yağışlı kıyı kuşağında tanede çürüme ve '
        'verim düşüklüğü olur. Neme daha dayanıklı olan mısır bu yüzden geleneksel ürün hâline gelmiştir.',
  ),
  IklimSorusu(
    soru: 'Örtü altı (sera) tarımının Türkiye\'de en yoğun yapıldığı, kışın ısıtma ihtiyacının en az olduğu bir ile dokun.',
    dogruIller: {'antalya', 'mersin'},
    aciklama: 'Seracılık kışın ılık geçen yerlerde ekonomik olur; ısıtma masrafı düşük olduğu için '
        'Antalya ve Mersin kıyıları örtü altı üretimde başı çeker.',
  ),
  IklimSorusu(
    soru: 'Kışları soğuk geçtiği için tarımın yerini büyük ölçüde hayvancılığın aldığı, otlak ve çayırların geniş yer kapladığı bir ile dokun.',
    dogruIller: {'kars', 'ardahan', 'agri', 'erzurum', 'mus', 'bitlis', 'van', 'hakkari'},
    aciklama: 'Uzun ve sert kışlar tarım mevsimini kısaltır; buna karşılık yaz yağışlarıyla gelişen geniş '
        'meralar hayvancılığı öne çıkarır. Bölgenin temel geçim kaynağı bu yüzden hayvancılıktır.',
  ),
  IklimSorusu(
    soru: 'Yükselti ve karasallık nedeniyle tahıl hasadının Türkiye\'de en geç yapıldığı bir ile dokun.',
    dogruIller: {'erzurum', 'kars', 'ardahan', 'agri', 'van', 'mus', 'bitlis'},
    aciklama: 'Yükseltinin artmasıyla sıcaklık düştüğü için bitkiler geç gelişir. Kıyılarda mayısta '
        'başlayan hasat, bu yüksek kesimlerde ağustos-eylüle sarkar.',
  ),
  IklimSorusu(
    soru: 'Yazları kurak ama geceleri serin geçen, göller yöresindeki koşullar sayesinde gül yetiştiriciliğinin merkezi olan ilimize dokun.',
    dogruIller: {'isparta'},
    aciklama: 'Yağ gülü, gündüz sıcak-kurak gece serin geçen ve yükseltisi 1000 metre dolayında olan '
        'yerlerde en iyi kokuyu verir. Isparta çevresi Türkiye gülyağı üretiminin merkezidir.',
  ),
  IklimSorusu(
    soru: 'Kuraklığa dayanıklı olduğu için yağışın az olduğu iç kesimlerde geniş alan kaplayan arpa-buğday tarımının hâkim olduğu bir ile dokun.',
    dogruIller: {'konya', 'karaman', 'aksaray', 'ankara', 'yozgat', 'kirsehir', 'sivas', 'cankiri', 'kirikkale', 'eskisehir', 'nigde'},
    aciklama: 'Tahıllar ilkbahar yağışlarıyla gelişip yaz kuraklığı başlamadan olgunlaşabildiği için '
        'bozkır kuşağının temel ürünüdür. Türkiye buğday üretiminin en büyük payı buradan gelir.',
  ),
  IklimSorusu(
    soru: 'Yaz kuraklığına dayanıklı olan ve kışın don istemeyen incirin en çok yetiştirildiği bir ile dokun.',
    dogruIller: {'aydin', 'izmir', 'mugla'},
    aciklama: 'İncir, yazın sıcak-kurak kışın ılık geçen kıyı koşullarını sever. Büyük Menderes Ovası '
        've çevresi (Aydın) kuru incir üretiminde Türkiye\'nin merkezidir.',
  ),
  IklimSorusu(
    soru: 'Yağışın azlığı yüzünden tarımın büyük ölçüde sulamaya bağlı olduğu, sulama projeleriyle pamuk üretiminin arttığı bir ile dokun.',
    dogruIller: {'sanliurfa', 'diyarbakir', 'mardin', 'batman', 'siirt', 'adiyaman'},
    aciklama: 'Yazın uzun ve çok sıcak geçmesi pamuk için elverişlidir, ancak yağış yetersizdir. GAP '
        'sulama yatırımları bu illerde pamuk ve mısır üretimini büyük ölçüde artırmıştır.',
  ),
  IklimSorusu(
    soru: 'Serin ve nemli iklim isteyen, yüksek kesimlerde yetiştirilen çayır bitkilerine dayalı arıcılığın (bal üretiminin) öne çıktığı bir ile dokun.',
    dogruIller: {'ordu', 'mugla', 'adana', 'sivas', 'bingol', 'erzurum'},
    aciklama: 'Bal üretimi zengin çiçek örtüsüne bağlıdır: Ordu\'da yayla çiçekleri, Muğla\'da çam '
        'ormanları, doğuda ise yüksek çayırlar farklı iklim koşullarında farklı bal türleri sağlar.',
  ),

  // ── Karşılaştırmalı/çıkarımsal sorular ───────────────────────────────
  IklimSorusu(
    soru: 'Aynı enlemde bulunmasına rağmen deniz etkisinden yoksun olduğu için kışları çok daha sert geçen, iç kesimdeki bir ile dokun.',
    dogruIller: {'sivas', 'yozgat', 'kayseri', 'ankara', 'cankiri', 'kirsehir', 'corum', 'erzincan', 'tokat'},
    aciklama: 'Deniz, yazın serinletici kışın ılıtıcı etki yapar. Kıyıdan uzaklaşıp yükseltinin arttığı iç '
        'kesimlerde bu etki kaybolur ve kışlar aynı enlemdeki kıyılara göre çok daha soğuk geçer.',
  ),
  IklimSorusu(
    soru: 'Günlük sıcaklık farkının (gece-gündüz farkının) en fazla olduğu, havanın kuru ve açık olduğu bir ile dokun.',
    dogruIller: {'konya', 'karaman', 'aksaray', 'nevsehir', 'nigde', 'sanliurfa', 'igdir', 'kirsehir'},
    aciklama: 'Nem ve bulutluluk azaldıkça gündüz ısınma, gece ise ısı kaybı artar. Kuru ve açık havanın '
        'hâkim olduğu bu yerlerde gece-gündüz sıcaklık farkı 20 °C\'yi bulabilir.',
  ),
  IklimSorusu(
    soru: 'Orman üst sınırının yükseltiye bağlı olarak Türkiye\'nin en yükseklerine çıktığı, ağaçsız yüksek çayır kuşağının geniş yer kapladığı bir ile dokun.',
    dogruIller: {'hakkari', 'van', 'agri', 'kars', 'ardahan', 'erzurum', 'bitlis'},
    aciklama: 'Sıcaklık yükseltiyle düştüğü için belli bir seviyeden sonra ağaç yetişemez. Bu yüksek '
        'kesimlerde orman sınırının üstünde geniş alpin çayır kuşağı yer alır ve yaylacılığa elverişlidir.',
  ),
];

/// Havuzda ARDIŞIK oyunlarda aynı soruların tekrar gelmemesi için, uygulama
/// oturumu boyunca kullanılmış soruların indeksleri tutulur. Havuzda yeni soru
/// kalmadığında liste sıfırlanıp havuz baştan dolaşılır.
final Set<int> _kullanilanSoruIndeksleri = <int>{};

/// Havuzdan [adet] kadar, mümkün olduğunca DAHA ÖNCE ÇIKMAMIŞ soru seçer.
List<IklimSorusu> _soruSec(int adet) {
  final rnd = Random();
  final tumIndeksler = List<int>.generate(kIklimSorulari.length, (i) => i);
  var uygun = tumIndeksler.where((i) => !_kullanilanSoruIndeksleri.contains(i)).toList();
  if (uygun.length < adet) {
    // Havuz tükendi — baştan başla ki oyun hiçbir zaman soru bulamamış olmasın.
    _kullanilanSoruIndeksleri.clear();
    uygun = tumIndeksler;
  }
  uygun.shuffle(rnd);
  final secilen = uygun.take(adet).toList();
  _kullanilanSoruIndeksleri.addAll(secilen);
  return [for (final i in secilen) kIklimSorulari[i]];
}

/// Mod 7 — "İklim Avı": iklime dair bir ÖZELLİK tarif edilir, kullanıcı bu
/// tarife uyan illerden birini haritada işaretler.
class IklimAviScreen extends StatefulWidget {
  const IklimAviScreen({super.key});

  @override
  State<IklimAviScreen> createState() => _IklimAviScreenState();
}

class _IklimAviScreenState extends State<IklimAviScreen> {
  bool _locked = false;
  bool _booted = false;
  bool _finished = false;
  int _round = 0;
  int _score = 0;
  int _attempts = 0;
  late List<IklimSorusu> _queue;
  TurkeyProvince? _tapped;
  bool _showResult = false;
  String? _flashWrongId;
  DateTime? _sessionStart;

  @override
  void initState() {
    super.initState();
    _sessionStart = DateTime.now();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  @override
  void dispose() {
    final start = _sessionStart;
    if (start != null) {
      context.read<StorageService>().addGameTimeSpent(kIklimAviGameId, DateTime.now().difference(start));
    }
    super.dispose();
  }

  Future<void> _boot() async {
    final ok = await consumeMapGameDailyPlay(context);
    if (!mounted) return;
    if (!ok) {
      setState(() => _locked = true);
      return;
    }
    setState(() {
      _queue = _soruSec(kIklimRounds);
      _booted = true;
      _round = 0;
      _score = 0;
      _attempts = 0;
      _finished = false;
      // bkz. bolge_bul_mode.dart — retry sonrası bir önceki oyunun son
      // sonuç durumunun sızmaması için tur-bazlı alanlar burada da sıfırlanır.
      _showResult = false;
      _tapped = null;
      _flashWrongId = null;
    });
  }

  IklimSorusu get _soru => _queue[_round];

  bool _uyar(TurkeyProvince p) => _soru.dogruIller.contains(p.id);

  void _onTapProvince(TurkeyProvince p) {
    if (_showResult) return;
    context.read<SoundService>().click();
    if (_uyar(p)) {
      setState(() {
        _tapped = p;
        _showResult = true;
        _score++;
      });
      return;
    }
    _attempts++;
    if (_attempts >= kMapMaxAttempts) {
      setState(() {
        _tapped = p;
        _showResult = true;
      });
    } else {
      _flashWrong(p.id);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('❌ Yanlış, tekrar dene! (${kMapMaxAttempts - _attempts} hakkın kaldı)'),
        duration: const Duration(milliseconds: 1400),
      ));
    }
  }

  /// Yanlış dokunulan ili kısa süreliğine kırmızı yakıp söndürür.
  void _flashWrong(String id) {
    setState(() => _flashWrongId = id);
    Future.delayed(const Duration(milliseconds: 550), () {
      if (mounted && _flashWrongId == id) setState(() => _flashWrongId = null);
    });
  }

  void _next() {
    context.read<SoundService>().click();
    if (_round + 1 >= _queue.length) {
      setState(() => _finished = true);
      return;
    }
    setState(() {
      _round++;
      _tapped = null;
      _showResult = false;
      _attempts = 0;
      _flashWrongId = null;
    });
  }

  void _retry() {
    setState(() {
      _booted = false;
      _locked = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  @override
  Widget build(BuildContext context) {
    if (_locked) {
      return const LockedFeatureCard(
        title: 'İklim Avı',
        desc: "Bugünkü $kFreeGameDailyLimit ücretsiz harita oyunu hakkını kullandın. Yarın tekrar oyna ya da Premium'a geçip sınırsız oyna.",
      );
    }
    if (!_booted) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_finished) {
      return MapQuizResult(
        title: '☀️ İklim Avı',
        modeId: kIklimAviGameId,
        score: _score,
        total: _queue.length,
        onRetry: _retry,
      );
    }
    return _buildRound(context);
  }

  Widget _buildRound(BuildContext context) {
    final colors = context.watch<ThemeProvider>().colors;
    return MapQuizScaffold(
      title: '☀️ İklim Avı',
      promptText: _soru.soru,
      statusText: 'Soru ${_round + 1}/${_queue.length} • Skor: $_score'
          '${_showResult ? "" : " • Hak: ${kMapMaxAttempts - _attempts}/$kMapMaxAttempts"}',
      palette: mapModePaletteFor(kIklimAviGameId),
      howToPlay: _kHowToPlay,
      map: TurkeyMapCanvas(
        provinces: kTurkeyProvinces,
        colorFor: (p) {
          if (!_showResult) {
            if (p.id == _flashWrongId) return colors.danger;
            return colors.violet.withValues(alpha: 0.32);
          }
          // Cevap verildikten sonra tarife UYAN tüm iller yeşil gösterilir —
          // kullanıcı doğru cevabın tek bir il değil bir KÜME olduğunu görür.
          if (_uyar(p)) return colors.success;
          if (p.id == _tapped?.id) return colors.danger;
          return colors.violet.withValues(alpha: 0.12);
        },
        onTap: _onTapProvince,
      ),
      feedback: _showResult ? _buildFeedback(colors) : null,
    );
  }

  Widget _buildFeedback(KpssColors colors) {
    final tapped = _tapped;
    final correct = tapped != null && _uyar(tapped);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: (correct ? colors.success : colors.danger).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: correct ? colors.success : colors.danger),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            correct
                ? '✅ Doğru! ${tapped.ad} bu tarife uyuyor.'
                : '❌ $kMapMaxAttempts hakkını da kullandın. ${tapped?.ad} bu tarife uymuyor; '
                    'haritada yeşil gösterilen iller doğru cevaplardır.',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Text('💡 ${_soru.aciklama}', style: const TextStyle(fontSize: 12.5, height: 1.45)),
          if (tapped != null) ...[
            const SizedBox(height: 6),
            Text(
              '${tapped.ad}: ${tapped.iklim}',
              style: TextStyle(fontSize: 11.5, color: colors.textFaint),
            ),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton(
              onPressed: _next,
              child: Text(_round + 1 < _queue.length ? 'Sonraki Soru →' : 'Bitir'),
            ),
          ),
        ],
      ),
    );
  }
}
