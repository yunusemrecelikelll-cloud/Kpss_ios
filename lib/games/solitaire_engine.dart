/// Kategori Eşleştirme Solitaire — motor.
///
/// Bu, klasik iskambil solitaire'i DEĞİL; KPSS terim/kavram kartlarını doğru
/// KATEGORİYE eşleştirme oyununu yönetir. Ancak yerleşim ve etkileşim klasik
/// solitaire'den ödünç alınır: tableau sütunları, yığma (stack), çekme destesi
/// ve "çevrilen kart" (waste).
///
/// Akış:
///  * [startLevel] ile seviyedeki TÜM kategoriler verilir (Kolay 5 / Orta 10 /
///    Zor 20). Zorluk ne olursa olsun tahtada AYNI ANDA en fazla
///    [kHedefSlotSayisi] hedef kategori durur; oyun hep 5 hedefle BAŞLAR.
///    Kalan kategoriler çekme destesine "hedef kategori kartı" olarak konur ve
///    oyuncu bunları çekip tahtadaki BOŞ slota yerleştirerek oyunu büyütür.
///  * Bir hedef kategori tamamlanınca tahtadan KALKAR ([_slotTemizle]) ve yeri
///    boşalır; o boş slota yalnızca yeni bir HEDEF KATEGORİ kartı konabilir.
///  * Tableau'da kartlar KATEGORİSİNE göre üst üste yığılabilir ([tasi]).
///    Bir yığının herhangi bir açık kartından itibaren ÜSTÜNDEKİ TÜM kartlar
///    birlikte taşınır (klasik solitaire davranışı).
///  * Boşalan bir tableau sütununa (kategori şartı olmadan) herhangi bir açık
///    kart/yığın taşınabilir.
///  * Çekme destesinden HEM terim kartı HEM hedef kategori kartı çıkar
///    ([cekDeste]); çekilen kartlar gerçek solitaire'deki gibi bir AÇILAN YIĞIN
///    ([acilanlar]) üzerinde birikir. Yığının EN ÜSTTEKİ kartı ([cekilen])
///    oynanabilir; o kart oynanınca altındaki kart yeni üst kart olur.
///  * Deste tükenince açılan yığının tamamı desteye geri döner ve KARIŞTIRILIR
///    ([cekDeste] içindeki geri dönüşüm). Bu sayede o an oynanamayan kartlar
///    ilerideki turlarda tekrar önüne gelir; kilitlenme olmaz.
///  * TÜM terimler eşleşince ([seviyeTamamlandi]) seviye biter.
library;

import 'dart:math';
import '../data/kategori_eslestirme_data.dart';

/// Session başına sabit ipucu hakkı.
const int kBaslangicIpucuHakki = 3;

/// Session başına sabit geri alma hakkı.
const int kBaslangicGeriAlHakki = 5;

/// Tableau sütun sayısı (referans görseldeki gibi 5).
const int kSutunSayisi = 5;

/// Tahtada AYNI ANDA duran hedef kategori slotu sayısı. Her zorluk bu kadar
/// hedefle başlar; fark, desteden çekilen EK hedeflerle toplam kategori
/// sayısının artmasıdır.
const int kHedefSlotSayisi = 5;

/// Seviye kurulurken her sütuna başlangıçta dağıtılan MAKSİMUM kart sayısı.
const int kBaslangicSutunDerinlik = 4;

/// Kategori başına üretilecek terim (kart) sayısı aralığı — AZ kategorili
/// seviyeler için.
const int kKartAltSinir = 4;
const int kKartUstSinir = 8;

/// ÇOK kategorili seviyelerde (bkz. [kCokKategoriEsigi]) kategori başına daha
/// az kart üretilir; aksi hâlde toplam kart sayısı oynanamayacak kadar şişer.
const int kCokKategoriEsigi = 10;
const int kCokKategoriAltSinir = 3;
const int kCokKategoriUstSinir = 5;

/// Hamle bütçesi = toplam terim (kart) sayısı × bu çarpan (yukarı yuvarlanır).
const double kHamleButceCarpani = 2.5;

/// Tek bir terim kartı (bir sütunda / destede yer alır).
class TerimKart {
  final String terim;

  /// Bu terimin ait olduğu DOĞRU kategori adı.
  final String kategoriAdi;

  /// Kart açık (oynanabilir) mı yoksa kapalı (mavi sırt) mı?
  bool faceUp;

  TerimKart({required this.terim, required this.kategoriAdi, this.faceUp = false});
}

/// Bir hedef kategori slotu (başlık + ilerleme sayacı).
class KategoriHedef {
  final String kategoriAdi;
  final String ders;

  /// Bu kategoriye ulaşılması gereken toplam eşleşme (Y — "X/Y").
  final int hedef;

  /// Şu ana kadar doğru eşleşen kart sayısı (X).
  int eslesen;

  KategoriHedef({
    required this.kategoriAdi,
    required this.ders,
    required this.hedef,
    this.eslesen = 0,
  });

  bool get tamamlandi => eslesen >= hedef;

  /// Daha kaç kart kabul edebilir.
  int get kalan => hedef - eslesen;
}

/// Çekme destesindeki bir öğe: ya bir TERİM kartı ya da yeni bir HEDEF
/// KATEGORİ kartı.
enum DesteTuru { terim, hedef }

class DesteKarti {
  final DesteTuru tur;
  final TerimKart? terim;
  final KategoriHedef? hedef;

  DesteKarti.terimKarti(TerimKart k)
      : tur = DesteTuru.terim,
        terim = k,
        hedef = null;

  DesteKarti.hedefKarti(KategoriHedef h)
      : tur = DesteTuru.hedef,
        hedef = h,
        terim = null;

  bool get hedefMi => tur == DesteTuru.hedef;

  /// Kartın üstünde yazan metin (önizleme ve sürükleme için).
  String get baslik => hedefMi ? hedef!.kategoriAdi : terim!.terim;
}

/// Geri alma için tek bir doğru eşleştirmenin kaydı.
class _UndoKayit {
  /// Kaynak tableau sütunu — null ise kart DESTEDEN (çekilen yuvasından) geldi.
  final int? sutunIndex;

  /// Bu eşleştirmede birlikte düşen açık grup (yığma sayesinde 1'den fazla).
  final List<TerimKart> grup;

  /// Bu eşleştirme sırasında bir alttaki kart açıldı mı?
  final bool altKartAcildi;

  /// Kartların gittiği hedef (sayacı geri almak için).
  final KategoriHedef hedef;

  /// Bu eşleştirme hedefi TAMAMLAYIP tahtadan kaldırdı mı?
  final bool hedefKalkti;

  /// Hedefin kalktığı slot indeksi (geri alırken aynı yere dönsün).
  final int slotIndex;

  _UndoKayit({
    required this.sutunIndex,
    required this.grup,
    required this.altKartAcildi,
    required this.hedef,
    required this.hedefKalkti,
    required this.slotIndex,
  });
}

class KategoriEslestirmeEngine {
  final Random _rnd;

  /// Tahtadaki hedef slotları — null olan slot BOŞTUR ve yalnızca desteden
  /// çekilen yeni bir HEDEF KATEGORİ kartını kabul eder.
  List<KategoriHedef?> slotlar = List<KategoriHedef?>.filled(kHedefSlotSayisi, null);

  /// Seviyedeki TÜM kategoriler (tahtada olan + destede bekleyen + tamamlanan).
  List<KategoriHedef> tumHedefler = [];

  /// Tamamlanıp tahtadan kalkan kategoriler (sonuç ekranı için).
  List<KategoriHedef> tamamlananlar = [];

  List<List<TerimKart>> sutunlar = [];

  /// Çekme destesi — terim ve hedef kartları karışık.
  List<DesteKarti> deste = [];

  /// AÇILAN YIĞIN ("waste pile"): desteden çekilmiş ama henüz oynanmamış
  /// kartlar. Listenin SONU ([last]) yığının en üstteki, tek oynanabilir
  /// kartıdır. Yeni çekilen kart bu yığının üstüne biner; eldeki kart artık
  /// kaybolmaz, altta bekler. Deste tükenince bu yığının tamamı karıştırılıp
  /// desteye geri döner.
  List<DesteKarti> acilanlar = [];

  /// Açılan yığının en üstteki (oynanabilir) kartı — yığın boşsa null.
  /// Geriye dönük uyumluluk: ekran kodu tek kartlık "çekilen" kavramını bu
  /// getter üzerinden kullanmaya devam eder.
  DesteKarti? get cekilen => acilanlar.isEmpty ? null : acilanlar.last;

  /// Seviyedeki toplam terim kartı sayısı.
  int toplamKart = 0;

  /// Şimdiye kadar doğru eşleşen toplam kart sayısı.
  int eslesenKart = 0;

  /// Toplam eşleştirme/taşıma DENEMESİ sayacı (doğru + yanlış).
  int hamle = 0;

  /// Bu seviye için verilen toplam hamle bütçesi.
  int hamleButcesi = 0;

  /// Son BAŞARILI eşleştirmede kaç kartın birlikte düştüğü.
  int sonEslesenAdet = 0;

  int ipucuHakki = kBaslangicIpucuHakki;
  int geriAlHakki = kBaslangicGeriAlHakki;

  final List<_UndoKayit> _undoStack = [];

  KategoriEslestirmeEngine([Random? rnd]) : _rnd = rnd ?? Random();

  // ── Seviye kurulumu ────────────────────────────────────────────────────

  /// Seçilen kategori gruplarından bir seviye kurar. Zorluk ne olursa olsun
  /// tahta [kHedefSlotSayisi] hedefle başlar; kalan kategoriler desteye
  /// "hedef kartı" olarak eklenir.
  void startLevel(List<KategoriGrubu> gruplar) {
    tumHedefler = [];
    tamamlananlar = [];
    slotlar = List<KategoriHedef?>.filled(kHedefSlotSayisi, null);
    deste = [];
    acilanlar = [];

    final cokKategori = gruplar.length >= kCokKategoriEsigi;
    final altSinir = cokKategori ? kCokKategoriAltSinir : kKartAltSinir;
    final ustSinir = cokKategori ? kCokKategoriUstSinir : kKartUstSinir;

    // Her kategori için hedef sayacı + o kadar terim kartı üret.
    final kategoriKartlari = <List<TerimKart>>[];
    for (final g in gruplar) {
      final terimler = List<String>.from(g.terimler)..shuffle(_rnd);
      final maxHedef = min(terimler.length, ustSinir);
      final hedefAdet =
          maxHedef <= altSinir ? maxHedef : altSinir + _rnd.nextInt(maxHedef - altSinir + 1);
      final h = KategoriHedef(kategoriAdi: g.kategoriAdi, ders: g.ders, hedef: hedefAdet);
      tumHedefler.add(h);
      kategoriKartlari.add([
        for (final t in terimler.take(hedefAdet))
          TerimKart(terim: t, kategoriAdi: g.kategoriAdi),
      ]);
    }
    toplamKart = kategoriKartlari.fold(0, (a, l) => a + l.length);
    eslesenKart = 0;

    // İlk [kHedefSlotSayisi] kategori tahtaya; kartları tableau'ya dağıtılır.
    final aktifAdet = min(kHedefSlotSayisi, tumHedefler.length);
    final acilisKartlar = <TerimKart>[];
    for (var i = 0; i < aktifAdet; i++) {
      slotlar[i] = tumHedefler[i];
      acilisKartlar.addAll(kategoriKartlari[i]);
    }
    acilisKartlar.shuffle(_rnd);

    sutunlar = List.generate(kSutunSayisi, (_) => <TerimKart>[]);
    final tableauKapasite = kSutunSayisi * kBaslangicSutunDerinlik;
    for (var i = 0; i < acilisKartlar.length; i++) {
      if (i < tableauKapasite) {
        sutunlar[i % kSutunSayisi].add(acilisKartlar[i]);
      } else {
        deste.add(DesteKarti.terimKarti(acilisKartlar[i]));
      }
    }
    for (final c in sutunlar) {
      if (c.isNotEmpty) c.last.faceUp = true;
    }

    // Bekleyen kategorilerin HEDEF kartı ve terimleri desteye eklenir.
    for (var i = aktifAdet; i < tumHedefler.length; i++) {
      deste.add(DesteKarti.hedefKarti(tumHedefler[i]));
      deste.addAll(kategoriKartlari[i].map(DesteKarti.terimKarti));
    }

    // Deste TAMAMEN karıştırılır: hedef kartları ve terim kartları ayrı ayrı
    // değil, hepsi birlikte. Eskiden "önce hedef, hemen ardından o kategorinin
    // terimleri" sırası korunuyordu; bu deste'yi tahmin edilebilir kılıyordu.
    // Artık karıştırmak GÜVENLİ: karşılığı henüz tahtada olmayan bir terim
    // kartı açılan yığında bekler ve deste tükenip geri dönüşüm olunca tekrar
    // önüne gelir. Yani hedefinden önce çıkan terim kaybolmaz, kilitlenme
    // yaratmaz — sadece bir tur sonra tekrar denenir.
    deste.shuffle(_rnd);

    hamle = 0;
    hamleButcesi = (toplamKart * kHamleButceCarpani).ceil();
    sonEslesenAdet = 0;
    ipucuHakki = kBaslangicIpucuHakki;
    geriAlHakki = kBaslangicGeriAlHakki;
    _undoStack.clear();
  }

  // ── Tahta sorguları ────────────────────────────────────────────────────

  /// Tahtadaki (dolu) hedef kategoriler.
  List<KategoriHedef> get hedefler => slotlar.whereType<KategoriHedef>().toList();

  /// Boş hedef slotu var mı? (Desteden çekilen hedef kartı konabilir mi?)
  bool get bosSlotVar => slotlar.any((s) => s == null);

  /// O sütunun EN ÜSTTEKİ (son) açık kartı — yoksa null.
  TerimKart? topKart(int sutunIndex) {
    final c = sutunlar[sutunIndex];
    if (c.isEmpty) return null;
    return c.last.faceUp ? c.last : null;
  }

  /// Sütundaki ilk AÇIK kartın indeksi (açık kart yoksa -1). Açık kartlar her
  /// zaman sütunun sonunda, kesintisiz ve TEK kategoriden oluşur.
  int acikBaslangic(int sutunIndex) {
    final c = sutunlar[sutunIndex];
    var i = c.length - 1;
    if (i < 0 || !c[i].faceUp) return -1;
    while (i - 1 >= 0 && c[i - 1].faceUp) {
      i--;
    }
    return i;
  }

  /// Sütunun açık (oynanabilir) kart listesi.
  List<TerimKart> acikGrup(int sutunIndex) {
    final bas = acikBaslangic(sutunIndex);
    if (bas < 0) return const [];
    return sutunlar[sutunIndex].sublist(bas);
  }

  /// [index] kartından İTİBAREN üstündeki tüm kartlar — bir yığının ortasına
  /// dokunulduğunda birlikte taşınacak grup. Kart açık değilse boş liste.
  List<TerimKart> altGrup(int sutunIndex, int index) {
    final c = sutunlar[sutunIndex];
    if (index < 0 || index >= c.length || !c[index].faceUp) return const [];
    return c.sublist(index);
  }

  /// Verilen kategori için tahtada AÇIK (tamamlanmamış) bir slot var mı?
  KategoriHedef? _slotHedef(String kategoriAdi) {
    for (final s in slotlar) {
      if (s != null && s.kategoriAdi == kategoriAdi && !s.tamamlandi) return s;
    }
    return null;
  }

  /// Tamamlanan hedefleri tahtadan kaldırır (yerleri boşalır).
  void _slotTemizle() {
    for (var i = 0; i < slotlar.length; i++) {
      final s = slotlar[i];
      if (s != null && s.tamamlandi) {
        tamamlananlar.add(s);
        slotlar[i] = null;
      }
    }
  }

  int _slotIndexOf(KategoriHedef h) {
    for (var i = 0; i < slotlar.length; i++) {
      if (identical(slotlar[i], h)) return i;
    }
    return -1;
  }

  // ── Eşleştirme (tableau → hedef) ───────────────────────────────────────

  /// [sutunIndex] sütununun [index] kartından itibaren yukarısındaki tüm grubu
  /// [kategoriAdi] hedefine yerleştirmeyi dener. Doğruysa grup düşer, sayaç
  /// artar, alttaki kart açılır ve hedef tamamlandıysa tahtadan kalkar.
  /// Yanlışsa hiçbir şey değişmez. Her iki durumda da [hamle] artar.
  bool eslestir(int sutunIndex, int index, String kategoriAdi) {
    final grup = altGrup(sutunIndex, index);
    hamle++;
    if (grup.isEmpty) return false;
    final hedef = _slotHedef(kategoriAdi);
    if (hedef == null) return false;
    if (grup.any((k) => k.kategoriAdi != kategoriAdi)) return false;
    if (grup.length > hedef.kalan) return false;
    _yerlestir(sutunIndex, index, hedef);
    return true;
  }

  /// Doğruluğu ÖNCEDEN garanti edilmiş bir grubu hedefe yerleştirir.
  void _yerlestir(int sutunIndex, int index, KategoriHedef hedef) {
    final c = sutunlar[sutunIndex];
    final grup = c.sublist(index);
    c.removeRange(index, c.length);
    hedef.eslesen += grup.length;
    eslesenKart += grup.length;
    sonEslesenAdet = grup.length;

    var altKartAcildi = false;
    if (c.isNotEmpty && !c.last.faceUp) {
      c.last.faceUp = true;
      altKartAcildi = true;
    }

    final slotIndex = _slotIndexOf(hedef);
    final kalkti = hedef.tamamlandi;
    _undoStack.add(_UndoKayit(
      sutunIndex: sutunIndex,
      grup: grup,
      altKartAcildi: altKartAcildi,
      hedef: hedef,
      hedefKalkti: kalkti,
      slotIndex: slotIndex,
    ));
    _slotTemizle();
  }

  // ── Taşıma (tableau → tableau) ─────────────────────────────────────────

  /// Kart-üstüne-kart YIĞMA: [kaynakSutun]'un [kaynakIndex] kartından itibaren
  /// üstündeki tüm grubu [hedefSutun]'a taşır.
  ///
  /// Kural: hedef sütun BOŞSA her grup kabul edilir (boşalan sütuna yanındaki
  /// açık kartlar taşınabilsin diye); doluysa hedefin üst kartı AÇIK ve
  /// grupla AYNI kategoride olmalıdır. Sayaç artmaz — bu bir düzenleme
  /// hamlesidir. Her iki durumda da [hamle] artar.
  bool tasi(int kaynakSutun, int kaynakIndex, int hedefSutun) {
    if (kaynakSutun == hedefSutun) return false;
    final grup = altGrup(kaynakSutun, kaynakIndex);
    hamle++;
    if (grup.isEmpty) return false;

    final hedefC = sutunlar[hedefSutun];
    if (hedefC.isNotEmpty) {
      final ust = hedefC.last;
      if (!ust.faceUp || ust.kategoriAdi != grup.first.kategoriAdi) return false;
    }

    final kaynak = sutunlar[kaynakSutun];
    kaynak.removeRange(kaynakIndex, kaynak.length);
    for (final k in grup) {
      k.faceUp = true;
      hedefC.add(k);
    }
    if (kaynak.isNotEmpty && !kaynak.last.faceUp) {
      kaynak.last.faceUp = true;
    }
    return true;
  }

  // ── Çekme destesi ve çekilen kart ──────────────────────────────────────

  /// Şu an desteden yeni bir kart çekilebilir mi? Deste boşsa bile açılan
  /// yığında kart varsa GERİ DÖNÜŞÜM yapılabileceği için true; ikisi de boşsa
  /// oynanacak deste kartı kalmamıştır (ekranda "Bitti").
  bool get cekilebilir => deste.isNotEmpty || acilanlar.isNotEmpty;

  /// Desteden bir sonraki kartı çekip AÇILAN YIĞININ ÜSTÜNE koyar.
  ///
  /// Eldeki (üstteki) kart artık hiçbir yere atılmaz — yığında, yeni kartın
  /// altında kalır ve üstündeki oynandığında tekrar görünür hâle gelir.
  ///
  /// Deste tükenmişse önce GERİ DÖNÜŞÜM yapılır: açılan yığının tamamı desteye
  /// döner ve KARIŞTIRILIR. Karıştırmak bilinçli — klasik solitaire sırayı
  /// korur, ama burada aynı oynanamaz kartların her turda aynı sırayla gelip
  /// oyuncuyu kilitlemesini engellemek daha önemli.
  bool cekDeste() {
    if (deste.isEmpty) {
      if (acilanlar.isEmpty) return false; // gerçekten çekilecek kart yok
      deste = acilanlar;
      acilanlar = [];
      deste.shuffle(_rnd);
    }
    acilanlar.add(deste.removeAt(0));
    return true;
  }

  /// Açılan yığının en üstteki kartını yığından çıkarır (oynandı).
  void _cekileniCikar() {
    if (acilanlar.isNotEmpty) acilanlar.removeLast();
  }

  /// Çekilen (yığının üstteki) TERİM kartını doğrudan bir hedef kategoriye
  /// eşleştirir. Kart yığından kalkar, altındaki kart yeni üst kart olur.
  bool cekilenEslestir(String kategoriAdi) {
    final ck = cekilen;
    hamle++;
    if (ck == null || ck.hedefMi) return false;
    final kart = ck.terim!;
    final hedef = _slotHedef(kategoriAdi);
    if (hedef == null || kart.kategoriAdi != kategoriAdi) return false;

    hedef.eslesen++;
    eslesenKart++;
    sonEslesenAdet = 1;
    _cekileniCikar();
    final slotIndex = _slotIndexOf(hedef);
    _undoStack.add(_UndoKayit(
      sutunIndex: null,
      grup: [kart],
      altKartAcildi: false,
      hedef: hedef,
      hedefKalkti: hedef.tamamlandi,
      slotIndex: slotIndex,
    ));
    _slotTemizle();
    return true;
  }

  /// Çekilen (yığının üstteki) TERİM kartını bir tableau sütununa koyar (boş
  /// sütun ya da aynı kategoriden açık kartın üstü). Kart yığından kalkar.
  bool cekilenSutunaKoy(int sutunIndex) {
    final ck = cekilen;
    hamle++;
    if (ck == null || ck.hedefMi) return false;
    final kart = ck.terim!;
    final c = sutunlar[sutunIndex];
    if (c.isNotEmpty) {
      final ust = c.last;
      if (!ust.faceUp || ust.kategoriAdi != kart.kategoriAdi) return false;
    }
    kart.faceUp = true;
    c.add(kart);
    _cekileniCikar();
    return true;
  }

  /// Çekilen (yığının üstteki) HEDEF KATEGORİ kartını tahtadaki BOŞ slota
  /// yerleştirir; kart yığından kalkar, altındaki kart görünür olur. Bu bir
  /// eşleştirme denemesi olmadığı için hamle HARCAMAZ.
  bool cekilenHedefiYerlestir(int slotIndex) {
    final ck = cekilen;
    if (ck == null || !ck.hedefMi) return false;
    if (slotIndex < 0 || slotIndex >= slotlar.length) return false;
    if (slotlar[slotIndex] != null) return false;
    slotlar[slotIndex] = ck.hedef;
    _cekileniCikar();
    return true;
  }

  // ── Yardımcılar (market) ───────────────────────────────────────────────

  /// Satın alınan JOKER: oynanabilir bir grubu DOĞRU kategorisine otomatik
  /// yerleştirir. Hamle harcamaz.
  bool joker() {
    for (var i = 0; i < sutunlar.length; i++) {
      final bas = acikBaslangic(i);
      if (bas < 0) continue;
      final kat = sutunlar[i][bas].kategoriAdi;
      final hedef = _slotHedef(kat);
      if (hedef == null) continue;
      final grup = sutunlar[i].sublist(bas);
      if (grup.any((k) => k.kategoriAdi != kat) || grup.length > hedef.kalan) continue;
      _yerlestir(i, bas, hedef);
      return true;
    }
    // Tableau'da uygun grup yoksa elde bekleyen kartı denemeyi dene.
    final ck = cekilen;
    if (ck != null && !ck.hedefMi && _slotHedef(ck.terim!.kategoriAdi) != null) {
      hamle--; // cekilenEslestir bir hamle sayar; joker hamle harcamaz
      return cekilenEslestir(ck.terim!.kategoriAdi);
    }
    return false;
  }

  /// Joker'in şu an yerleştirebileceği bir kart var mı?
  bool get jokerUygun {
    for (var i = 0; i < sutunlar.length; i++) {
      final bas = acikBaslangic(i);
      if (bas < 0) continue;
      final kat = sutunlar[i][bas].kategoriAdi;
      final hedef = _slotHedef(kat);
      if (hedef != null && sutunlar[i].length - bas <= hedef.kalan) return true;
    }
    final ck = cekilen;
    return ck != null && !ck.hedefMi && _slotHedef(ck.terim!.kategoriAdi) != null;
  }

  void satinAlinanIpucu() => ipucuHakki++;
  void satinAlinanGeriAl() => geriAlHakki++;

  /// Market'teki "Ek Hamle" ürünü ve kayıp ekranındaki kurtarma için bütçeyi
  /// büyütür.
  void hamleEkle(int adet) {
    if (adet > 0) hamleButcesi += adet;
  }

  // ── İpucu / geri al ────────────────────────────────────────────────────

  /// Seçim gerektirmeyen ipucu: tahtadaki bir hedefe uyan bir kart bulup
  /// terim + kategorisini döndürür ve ipucu hakkını düşürür.
  ({String terim, String kategori})? hintAny() {
    if (ipucuHakki <= 0) return null;
    // Önce gerçekten oynanabilir (hedefi tahtada olan) bir kart ara.
    for (var i = 0; i < sutunlar.length; i++) {
      final k = topKart(i);
      if (k != null && _slotHedef(k.kategoriAdi) != null) {
        ipucuHakki--;
        return (terim: k.terim, kategori: k.kategoriAdi);
      }
    }
    for (var i = 0; i < sutunlar.length; i++) {
      final k = topKart(i);
      if (k != null) {
        ipucuHakki--;
        return (terim: k.terim, kategori: k.kategoriAdi);
      }
    }
    final ck = cekilen;
    if (ck != null && !ck.hedefMi) {
      ipucuHakki--;
      return (terim: ck.terim!.terim, kategori: ck.terim!.kategoriAdi);
    }
    return null;
  }

  /// O sütunun üstteki kartının doğru kategorisini verir; ipucu hakkını düşürür.
  String? hint(int sutunIndex) {
    if (ipucuHakki <= 0) return null;
    final kart = topKart(sutunIndex);
    if (kart == null) return null;
    ipucuHakki--;
    return kart.kategoriAdi;
  }

  /// Son doğru eşleştirmeyi geri alır.
  bool undo() {
    if (geriAlHakki <= 0 || _undoStack.isEmpty) return false;
    final kayit = _undoStack.last;

    // Hedef tamamlanıp tahtadan kalktıysa geri dönebilmesi için boş slot gerek.
    var geriSlot = -1;
    if (kayit.hedefKalkti) {
      if (kayit.slotIndex >= 0 &&
          kayit.slotIndex < slotlar.length &&
          slotlar[kayit.slotIndex] == null) {
        geriSlot = kayit.slotIndex;
      } else {
        geriSlot = slotlar.indexWhere((s) => s == null);
      }
      if (geriSlot < 0) return false; // yer yok → geri alınamaz
    }

    _undoStack.removeLast();

    if (kayit.sutunIndex != null) {
      final c = sutunlar[kayit.sutunIndex!];
      if (kayit.altKartAcildi && c.isNotEmpty) {
        c.last.faceUp = false;
      }
      for (final k in kayit.grup) {
        k.faceUp = true;
        c.add(k);
      }
    } else {
      // Kart açılan yığından oynanmıştı: yığının ÜSTÜNE geri konur; böylece
      // geri alındığı anda yine oynanabilir üst kart olur ve altındakiler
      // olduğu gibi korunur.
      final kart = kayit.grup.first..faceUp = true;
      acilanlar.add(DesteKarti.terimKarti(kart));
    }

    kayit.hedef.eslesen =
        (kayit.hedef.eslesen - kayit.grup.length).clamp(0, kayit.hedef.hedef);
    eslesenKart = (eslesenKart - kayit.grup.length).clamp(0, toplamKart);
    if (kayit.hedefKalkti && geriSlot >= 0) {
      slotlar[geriSlot] = kayit.hedef;
      tamamlananlar.remove(kayit.hedef);
    }

    geriAlHakki--;
    return true;
  }

  // ── Durum özetleri ─────────────────────────────────────────────────────

  /// Bu seviyedeki kategorilerin ait olduğu ortak ders; karışıksa "Karışık".
  String get seviyeDers {
    if (tumHedefler.isEmpty) return 'Karışık';
    final ilk = tumHedefler.first.ders;
    return tumHedefler.every((h) => h.ders == ilk) ? ilk : 'Karışık';
  }

  /// Çekme destesinde ŞU AN bekleyen kart sayısı — her çekişte 1 azalır.
  int get bekleyenSayisi => deste.length;

  /// Açılan yığında bekleyen kart sayısı (yığın rozeti "×N" bunu gösterir).
  int get acilanSayisi => acilanlar.length;

  /// Deste + açılan yığın: henüz oynanmamış TÜM deste kartları. Deste sayacı
  /// sıfırlanınca "yeniden dağıtım" olacağını anlatmak için kullanılır.
  int get oynanmamisDesteKarti => deste.length + acilanlar.length;

  /// Henüz oynanmamış HEDEF KATEGORİ kartı sayısı (destede ya da açılan
  /// yığında). Boş slot metni bunu kullanır.
  int get bekleyenHedefSayisi =>
      deste.where((d) => d.hedefMi).length +
      acilanlar.where((d) => d.hedefMi).length;

  /// Seviyedeki toplam terim (kart) sayısı — hamle bütçesinin dayanağı.
  int get toplamTerim => toplamKart;

  /// Henüz eşleşmemiş kart sayısı.
  int get kalanTerim => toplamKart - eslesenKart;

  /// Seviyedeki toplam kategori sayısı (Kolay 5 / Orta 10 / Zor 20).
  int get toplamKategori => tumHedefler.length;

  bool get geriAlinabilir => geriAlHakki > 0 && _undoStack.isNotEmpty;

  bool get seviyeTamamlandi => eslesenKart >= toplamKart && toplamKart > 0;

  /// Kalan hamle hakkı (bütçe − yapılan deneme). Negatif olmaz.
  int get kalanHamle {
    final k = hamleButcesi - hamle;
    return k < 0 ? 0 : k;
  }

  /// KAYBETME koşulu: hamle bütçesi tükendi VE hâlâ tamamlanmamış kart var.
  bool get kaybedildi => hamle >= hamleButcesi && !seviyeTamamlandi;
}
