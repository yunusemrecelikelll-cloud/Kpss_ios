/// "Tarihleri Bil" mini oyunu için veri modeli ve GERÇEK, KPSS'de sık çıkan
/// Osmanlı/Cumhuriyet dönemi tarihi olayları.
///
/// Her [TarihOlay], olayın doğru yılını ([dogruYil]) ve bilinçli olarak
/// YAKIN ama GERÇEKTEN YANLIŞ bir çeldirici yılı ([celdiriciYil]) bir arada
/// tutar (ör. doğru yıl 1919 ise çeldirici 1918 ya da 1920 gibi makul bir
/// yakınlıktadır, alakasız bir yıl DEĞİLDİR). Tüm tarihler doğrulanmış gerçek
/// bilgilerdir — bu bir KPSS hazırlık uygulaması olduğundan yanlış tarih
/// bilgisi KESİNLİKLE yoktur.
class TarihOlay {
  final String olay;
  final int dogruYil;
  final int celdiriciYil;

  const TarihOlay({
    required this.olay,
    required this.dogruYil,
    required this.celdiriciYil,
  });
}

const List<TarihOlay> kTarihOlaylari = [
  TarihOlay(olay: 'Sivas Kongresi', dogruYil: 1919, celdiriciYil: 1920),
  TarihOlay(olay: 'Erzurum Kongresi', dogruYil: 1919, celdiriciYil: 1918),
  TarihOlay(olay: 'Amasya Genelgesi', dogruYil: 1919, celdiriciYil: 1920),
  TarihOlay(olay: 'Amasya Görüşmeleri (Osmanlı hükümetiyle)', dogruYil: 1919, celdiriciYil: 1920),
  TarihOlay(olay: "Misak-ı Millî'nin Son Osmanlı Mebusan Meclisi'nce kabulü", dogruYil: 1920, celdiriciYil: 1919),
  TarihOlay(olay: "TBMM'nin açılışı (23 Nisan)", dogruYil: 1920, celdiriciYil: 1921),
  TarihOlay(olay: "Sevr Antlaşması'nın imzalanması", dogruYil: 1920, celdiriciYil: 1919),
  TarihOlay(olay: 'Mondros Ateşkes Antlaşması', dogruYil: 1918, celdiriciYil: 1919),
  TarihOlay(olay: 'I. İnönü Muharebesi', dogruYil: 1921, celdiriciYil: 1920),
  TarihOlay(olay: "İstiklal Marşı'nın kabulü (12 Mart)", dogruYil: 1921, celdiriciYil: 1920),
  TarihOlay(olay: 'II. İnönü Muharebesi', dogruYil: 1921, celdiriciYil: 1920),
  TarihOlay(olay: 'Londra Konferansı', dogruYil: 1921, celdiriciYil: 1922),
  TarihOlay(olay: 'Moskova Antlaşması (Sovyet Rusya ile)', dogruYil: 1921, celdiriciYil: 1920),
  TarihOlay(olay: 'Kütahya-Eskişehir Muharebeleri', dogruYil: 1921, celdiriciYil: 1922),
  TarihOlay(olay: 'Sakarya Meydan Muharebesi', dogruYil: 1921, celdiriciYil: 1922),
  TarihOlay(olay: 'Kars Antlaşması', dogruYil: 1921, celdiriciYil: 1922),
  TarihOlay(olay: 'Ankara Antlaşması (Fransa ile)', dogruYil: 1921, celdiriciYil: 1920),
  TarihOlay(olay: 'Gümrü Antlaşması', dogruYil: 1920, celdiriciYil: 1921),
  TarihOlay(olay: 'Büyük Taarruz ve Başkomutanlık Meydan Muharebesi', dogruYil: 1922, celdiriciYil: 1921),
  TarihOlay(olay: 'Mudanya Ateşkes Antlaşması', dogruYil: 1922, celdiriciYil: 1923),
  TarihOlay(olay: 'Saltanatın kaldırılması', dogruYil: 1922, celdiriciYil: 1923),
  TarihOlay(olay: 'Lozan Barış Antlaşması', dogruYil: 1923, celdiriciYil: 1922),
  TarihOlay(olay: "Ankara'nın başkent oluşu", dogruYil: 1923, celdiriciYil: 1924),
  TarihOlay(olay: 'İzmir İktisat Kongresi', dogruYil: 1923, celdiriciYil: 1924),
  TarihOlay(olay: "Cumhuriyet Halk Fırkası'nın kuruluşu", dogruYil: 1923, celdiriciYil: 1924),
  TarihOlay(olay: 'Cumhuriyetin ilanı (29 Ekim)', dogruYil: 1923, celdiriciYil: 1922),
  TarihOlay(olay: 'Halifeliğin kaldırılması', dogruYil: 1924, celdiriciYil: 1925),
  TarihOlay(olay: 'Tevhid-i Tedrisat (Öğretim Birliği) Kanunu', dogruYil: 1924, celdiriciYil: 1925),
  TarihOlay(olay: "Terakkiperver Cumhuriyet Fırkası'nın kuruluşu", dogruYil: 1924, celdiriciYil: 1925),
  TarihOlay(olay: 'Şeyh Said İsyanı', dogruYil: 1925, celdiriciYil: 1924),
  TarihOlay(olay: 'Şapka Kanunu', dogruYil: 1925, celdiriciYil: 1926),
  TarihOlay(olay: 'Tekke, zaviye ve türbelerin kapatılması', dogruYil: 1925, celdiriciYil: 1926),
  TarihOlay(olay: "Türk Medeni Kanunu'nun kabulü", dogruYil: 1926, celdiriciYil: 1925),
  TarihOlay(olay: 'Kabotaj Kanunu', dogruYil: 1926, celdiriciYil: 1927),
  TarihOlay(olay: "Miladi Takvim'e geçilmesi", dogruYil: 1926, celdiriciYil: 1925),
  TarihOlay(olay: 'Musul sorununun Ankara Antlaşması ile çözülmesi', dogruYil: 1926, celdiriciYil: 1925),
  TarihOlay(olay: "Nutuk'un okunması", dogruYil: 1927, celdiriciYil: 1926),
  TarihOlay(olay: 'Harf İnkılabı (Yeni Türk harfleri)', dogruYil: 1928, celdiriciYil: 1927),
  TarihOlay(olay: "Serbest Cumhuriyet Fırkası'nın kuruluşu", dogruYil: 1930, celdiriciYil: 1931),
  TarihOlay(olay: 'Kadınlara belediye seçimlerinde seçme ve seçilme hakkı', dogruYil: 1930, celdiriciYil: 1933),
  TarihOlay(olay: 'Menemen Olayı', dogruYil: 1930, celdiriciYil: 1931),
  TarihOlay(olay: "Soyadı Kanunu'nun kabulü", dogruYil: 1934, celdiriciYil: 1935),
  TarihOlay(olay: 'Kadınlara milletvekili seçme ve seçilme hakkının tanınması', dogruYil: 1934, celdiriciYil: 1930),
  TarihOlay(olay: "İlk kadın milletvekillerinin TBMM'ye girmesi", dogruYil: 1935, celdiriciYil: 1934),
  TarihOlay(olay: "Atatürk'ün vefatı (10 Kasım)", dogruYil: 1938, celdiriciYil: 1937),
  TarihOlay(olay: "II. Dünya Savaşı'nın başlaması", dogruYil: 1939, celdiriciYil: 1938),
  TarihOlay(olay: "II. Dünya Savaşı'nın sona ermesi", dogruYil: 1945, celdiriciYil: 1944),
  TarihOlay(olay: "Türkiye'nin Birleşmiş Milletler'e üye olması", dogruYil: 1945, celdiriciYil: 1946),
  TarihOlay(olay: "Demokrat Parti'nin kurulması", dogruYil: 1946, celdiriciYil: 1945),
  TarihOlay(olay: "Türkiye'de ilk çok partili genel seçimler", dogruYil: 1946, celdiriciYil: 1950),
  TarihOlay(olay: "Truman Doktrini kapsamında Türkiye'ye yardım başlaması", dogruYil: 1947, celdiriciYil: 1948),
  TarihOlay(olay: "Marshall Planı kapsamında Türkiye'nin yardım almaya başlaması", dogruYil: 1948, celdiriciYil: 1947),
  TarihOlay(olay: "Türkiye'nin Kore Savaşı'na asker göndermesi", dogruYil: 1950, celdiriciYil: 1951),
  TarihOlay(olay: "Türkiye'nin NATO'ya girişi", dogruYil: 1952, celdiriciYil: 1951),
  TarihOlay(olay: '6-7 Eylül Olayları', dogruYil: 1955, celdiriciYil: 1956),
  TarihOlay(olay: '27 Mayıs Darbesi', dogruYil: 1960, celdiriciYil: 1961),
  TarihOlay(olay: 'Yassıada duruşmaları sonucu idamlar', dogruYil: 1961, celdiriciYil: 1960),
  TarihOlay(olay: '12 Mart Muhtırası', dogruYil: 1971, celdiriciYil: 1970),
  TarihOlay(olay: 'Kıbrıs Barış Harekâtı', dogruYil: 1974, celdiriciYil: 1973),
  TarihOlay(olay: '12 Eylül Darbesi', dogruYil: 1980, celdiriciYil: 1979),
  TarihOlay(olay: "Türkiye'nin AET'ye (Avrupa Ekonomik Topluluğu) tam üyelik başvurusu", dogruYil: 1987, celdiriciYil: 1986),
  TarihOlay(olay: "Tanzimat Fermanı'nın ilanı", dogruYil: 1839, celdiriciYil: 1840),
  TarihOlay(olay: "Islahat Fermanı'nın ilanı", dogruYil: 1856, celdiriciYil: 1858),
  TarihOlay(olay: "I. Meşrutiyet'in ilanı", dogruYil: 1876, celdiriciYil: 1878),
  TarihOlay(olay: "II. Meşrutiyet'in ilanı", dogruYil: 1908, celdiriciYil: 1909),
  TarihOlay(olay: '31 Mart Olayı (13 Nisan)', dogruYil: 1909, celdiriciYil: 1910),
  TarihOlay(olay: "Balkan Savaşları'nın başlaması", dogruYil: 1912, celdiriciYil: 1913),
  TarihOlay(olay: "I. Dünya Savaşı'nın başlaması", dogruYil: 1914, celdiriciYil: 1915),
  TarihOlay(olay: 'Çanakkale Savaşı', dogruYil: 1915, celdiriciYil: 1916),
  TarihOlay(olay: "Mustafa Kemal'in Samsun'a çıkışı (19 Mayıs)", dogruYil: 1919, celdiriciYil: 1918),
  TarihOlay(olay: "Yeniçeri Ocağı'nın kaldırılması (Vaka-i Hayriye)", dogruYil: 1826, celdiriciYil: 1827),
  TarihOlay(olay: 'Küçük Kaynarca Antlaşması', dogruYil: 1774, celdiriciYil: 1775),
  TarihOlay(olay: 'Karlofça Antlaşması', dogruYil: 1699, celdiriciYil: 1700),
  TarihOlay(
    olay: "Rusya'nın kışkırtmaları ve Panislavist faaliyetlerin artmasıyla çıkan 93 Harbi (Osmanlı-Rus Savaşı)",
    dogruYil: 1877,
    celdiriciYil: 1878,
  ),
  TarihOlay(olay: 'Ayastefanos (Yeşilköy) Antlaşması', dogruYil: 1878, celdiriciYil: 1877),
  TarihOlay(olay: 'Berlin Antlaşması', dogruYil: 1878, celdiriciYil: 1877),
];
