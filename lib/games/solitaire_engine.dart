/// Kategori Eşleştirme Solitaire — motor.
///
/// Bu, klasik iskambil solitaire'i DEĞİL; KPSS terim/kavram kartlarını doğru
/// KATEGORİYE eşleştirme oyununu yönetir.
///
/// Akış:
///  * [startLevel] ile 5-20 [KategoriGrubu] verilir (Kolay 5 / Orta 10 / Zor
///    20). Her kategori için gerçek üye-terim sayısına göre bir hedef sayaç
///    (3-8; bkz. [kKartAltSinir]) belirlenir ve o kadar terim kartı üretilir.
///    Tüm kartlar karıştırılıp 5 sütuna (tableau)
///    dağıtılır; her sütunda üstte kapalı kartlar, en altta (oynanabilir) 1
///    açık kart bulunur.
///  * Oyuncu önce açık bir terim kartını seçer ([tapCard]), sonra ait olduğunu
///    düşündüğü kategoriye dokunur ([tapCategory]). Doğruysa kart düşer,
///    kategorinin sayacı artar ve alttaki kart açılır; yanlışsa [tapCategory]
///    false döner (UI kırmızı flaş gösterir).
///  * [undo] son doğru eşleştirmeyi geri alır (sınırlı hak). [hint] bir sütunun
///    üstteki kartının doğru kategorisini verir (sınırlı hak).
///  * TÜM kartlar eşleşince ([seviyeTamamlandi]) seviye biter.
library;

import 'dart:math';
import '../data/kategori_eslestirme_data.dart';

/// Session başına sabit ipucu hakkı (satın alınamaz — coin ekonomisi yoktur).
const int kBaslangicIpucuHakki = 3;

/// Session başına sabit geri alma hakkı.
const int kBaslangicGeriAlHakki = 5;

/// Tableau sütun sayısı (referans görseldeki gibi 5).
const int kSutunSayisi = 5;

/// Seviye kurulurken her sütuna başlangıçta dağıtılan MAKSİMUM kart sayısı.
/// Bunun üzerindeki terimler "çekme destesi" kuyruğunda ([bekleyenKuyruk])
/// bekletilir ve oyuncu desteye dokundukça tableau'ya dağıtılır.
const int kBaslangicSutunDerinlik = 4;

/// Kategori başına üretilecek terim (kart) sayısı aralığı — AZ kategorili
/// seviyeler için. Toplam kart sayısını artırmak amacıyla yükseltildi.
const int kKartAltSinir = 4;
const int kKartUstSinir = 8;

/// ÇOK kategorili seviyelerde (bkz. [kCokKategoriEsigi]) kategori başına daha
/// az kart üretilir; aksi hâlde toplam kart sayısı oynanamayacak kadar şişer.
const int kCokKategoriEsigi = 10;
const int kCokKategoriAltSinir = 3;
const int kCokKategoriUstSinir = 5;

/// Hamle bütçesi = toplam terim (kart) sayısı × bu çarpan (yukarı yuvarlanır).
/// 2.5 kat: her kartı doğru yere koymak en az 1 hamle olduğundan, dikkatli bir
/// oyuncu (birkaç yanlış deneme + birkaç yığma payıyla) rahat bitirir; çok fazla
/// yanlış deneme yapan oyuncu ise bütçeyi tüketip kaybeder. (Bkz. [kalanHamle].)
const double kHamleButceCarpani = 2.5;

/// Tek bir terim kartı (bir sütunda yer alır).
class TerimKart {
  final String terim;

  /// Bu terimin ait olduğu DOĞRU kategori adı.
  final String kategoriAdi;

  /// Kart açık (oynanabilir) mı yoksa kapalı (mavi sırt) mı?
  bool faceUp;

  TerimKart({required this.terim, required this.kategoriAdi, this.faceUp = false});
}

/// Üstteki hedef kategori slotu (başlık + ilerleme sayacı).
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
}

/// Geri alma için tek bir doğru eşleştirmenin kaydı.
class _UndoKayit {
  final int sutunIndex;

  /// Bu eşleştirmede birlikte düşen açık grup (yığma sayesinde 1'den fazla
  /// olabilir — hepsi aynı kategoriye aittir).
  final List<TerimKart> grup;

  /// Bu eşleştirme sırasında bir alttaki kart açıldı mı? (Geri alırken tekrar
  /// kapatmak için.)
  final bool altKartAcildi;

  _UndoKayit(this.sutunIndex, this.grup, this.altKartAcildi);
}

class KategoriEslestirmeEngine {
  final Random _rnd;

  List<KategoriHedef> hedefler = [];
  List<List<TerimKart>> sutunlar = [];

  /// Henüz tableau'ya DAĞITILMAMIŞ, "çekme destesinde" (draw pile) bekleyen
  /// terimler. Oyuncu desteye dokundukça ([cekDeste]) baştan alınıp boş bir
  /// sütuna ya da en az kartlı sütunun üstüne konur.
  List<TerimKart> bekleyenKuyruk = [];

  /// Toplam eşleştirme/yığma DENEMESİ sayacı (doğru + yanlış). Bu sayaç
  /// [hamleButcesi] ile karşılaştırılarak "Kalan Hamle" hesaplanır.
  int hamle = 0;

  /// Bu seviye için verilen toplam hamle bütçesi (SINIRLI kaynak). [hamle] bu
  /// değere ulaşınca ve seviye bitmemişse oyun KAYBEDİLİR ([kaybedildi]).
  int hamleButcesi = 0;

  /// Son BAŞARILI eşleştirmede kaç kartın birlikte düştüğü (yığın sayesinde
  /// 1'den fazla olabilir) — UI'ın coin ödülünü kart başına vermesi için.
  int sonEslesenAdet = 0;

  /// Seçili terim kartının bulunduğu sütun (null = seçili kart yok).
  int? seciliSutun;

  int ipucuHakki = kBaslangicIpucuHakki;
  int geriAlHakki = kBaslangicGeriAlHakki;

  final List<_UndoKayit> _undoStack = [];

  KategoriEslestirmeEngine([Random? rnd]) : _rnd = rnd ?? Random();

  /// Seçilen kategori gruplarından bir seviye kurar.
  void startLevel(List<KategoriGrubu> gruplar) {
    hedefler = [];
    final tumKartlar = <TerimKart>[];

    // Kategori sayısı arttıkça kategori başına kart sayısı düşürülür (bkz.
    // [kCokKategoriEsigi]) — böylece Zor seviyede 20 kategori olsa bile toplam
    // kart sayısı makul kalır.
    final cokKategori = gruplar.length >= kCokKategoriEsigi;
    final altSinir = cokKategori ? kCokKategoriAltSinir : kKartAltSinir;
    final ustSinir = cokKategori ? kCokKategoriUstSinir : kKartUstSinir;

    for (final g in gruplar) {
      final terimler = List<String>.from(g.terimler)..shuffle(_rnd);
      final maxHedef = min(terimler.length, ustSinir);
      // [altSinir] ile maxHedef arasında makul bir hedef.
      final hedef =
          maxHedef <= altSinir ? maxHedef : altSinir + _rnd.nextInt(maxHedef - altSinir + 1);
      final secilen = terimler.take(hedef).toList();
      hedefler.add(KategoriHedef(kategoriAdi: g.kategoriAdi, ders: g.ders, hedef: hedef));
      for (final t in secilen) {
        tumKartlar.add(TerimKart(terim: t, kategoriAdi: g.kategoriAdi));
      }
    }

    tumKartlar.shuffle(_rnd);
    sutunlar = List.generate(kSutunSayisi, (_) => <TerimKart>[]);
    bekleyenKuyruk = [];
    // Başlangıçta yalnızca sütun başına [kBaslangicSutunDerinlik] kart dağıtılır;
    // geri kalanlar çekme destesi kuyruğunda bekletilir.
    final tableauKapasite = kSutunSayisi * kBaslangicSutunDerinlik;
    for (var i = 0; i < tumKartlar.length; i++) {
      if (i < tableauKapasite) {
        sutunlar[i % kSutunSayisi].add(tumKartlar[i]);
      } else {
        bekleyenKuyruk.add(tumKartlar[i]);
      }
    }
    // Her sütunun EN ALTTAKİ (son) kartı açık/oynanabilir olur.
    for (final c in sutunlar) {
      if (c.isNotEmpty) c.last.faceUp = true;
    }

    hamle = 0;
    // Hamle bütçesi, toplam kart sayısına göre ölçeklenir (bkz. [kHamleButceCarpani]).
    hamleButcesi = (toplamTerim * kHamleButceCarpani).ceil();
    sonEslesenAdet = 0;
    seciliSutun = null;
    ipucuHakki = kBaslangicIpucuHakki;
    geriAlHakki = kBaslangicGeriAlHakki;
    _undoStack.clear();
  }

  /// O sütunun oynanabilir (açık, en alttaki) kartı — yoksa null.
  TerimKart? topKart(int sutunIndex) {
    final c = sutunlar[sutunIndex];
    if (c.isEmpty) return null;
    final k = c.last;
    return k.faceUp ? k : null;
  }

  /// Şu an seçili olan terim kartı (yoksa null).
  TerimKart? get seciliKart => seciliSutun == null ? null : topKart(seciliSutun!);

  /// Açık bir terim kartını seçer/seçimi kaldırır. Kart açık değilse yok sayılır.
  void tapCard(int sutunIndex) {
    if (topKart(sutunIndex) == null) return;
    if (seciliSutun == sutunIndex) {
      seciliSutun = null; // aynı karta tekrar dokununca seçimi kaldır
    } else {
      seciliSutun = sutunIndex;
    }
  }

  /// Bir sütunun sondaki (alttaki) ARDIŞIK açık kartlarından, EN ALTTAKİ kartla
  /// AYNI kategoriye ait olanların oluşturduğu "oynanabilir grup". Yığma
  /// ([stackCard]) sayesinde bir sütunun altında aynı kategoriden birden fazla
  /// açık kart üst üste durabilir; bunlar bir kategoriye birlikte eşleşir.
  /// Kategori sınırına ya da kapalı bir karta gelince durur (böylece grup her
  /// zaman TEK kategoriden oluşur — güvenli).
  List<TerimKart> _acikGrupKartlari(List<TerimKart> c) {
    if (c.isEmpty || !c.last.faceUp) return const [];
    final kat = c.last.kategoriAdi;
    final grup = <TerimKart>[];
    for (var i = c.length - 1; i >= 0; i--) {
      if (c[i].faceUp && c[i].kategoriAdi == kat) {
        grup.insert(0, c[i]);
      } else {
        break;
      }
    }
    return grup;
  }

  /// UI için: bir sütunun sondaki açık (oynanabilir) grubu — hepsi aynı kategori.
  List<TerimKart> acikGrup(int sutunIndex) => _acikGrupKartlari(sutunlar[sutunIndex]);

  /// Verilen kategori için henüz TAMAMLANMAMIŞ hedefi döndürür (yoksa null).
  KategoriHedef? _uygunHedef(String kategoriAdi) {
    for (final h in hedefler) {
      if (h.kategoriAdi == kategoriAdi && !h.tamamlandi) return h;
    }
    return null;
  }

  /// [sutunIndex]'in açık grubunu [hedef]e yerleştirir (doğruluk ÖNCEDEN garanti
  /// edilmiş olmalı). Grubu düşürür, sayacı grup boyutu kadar artırır, alttaki
  /// kartı açar, geri-al kaydı bırakır ve düşen kart sayısını döndürür.
  int _yerlestirGrup(int sutunIndex, KategoriHedef hedef) {
    final c = sutunlar[sutunIndex];
    final grup = _acikGrupKartlari(c);
    if (grup.isEmpty) return 0;
    c.removeRange(c.length - grup.length, c.length);
    hedef.eslesen += grup.length;

    var altKartAcildi = false;
    if (c.isNotEmpty && !c.last.faceUp) {
      c.last.faceUp = true;
      altKartAcildi = true;
    }

    _undoStack.add(_UndoKayit(sutunIndex, grup, altKartAcildi));
    return grup.length;
  }

  /// Seçili kartı (ve varsa üstündeki aynı kategoriden açık grubu) [kategoriAdi]
  /// ile eşleştirmeyi dener.
  ///
  /// Doğruysa: gruptaki TÜM kartları düşürür, kategorinin sayacını grup boyutu
  /// kadar artırır, alttaki kartı açar, true döner ([sonEslesenAdet] düşen kart
  /// sayısını tutar). Yanlışsa: durum değişmez, false döner (UI kırmızı flaş
  /// göstermeli). Her iki durumda da [hamle] artar.
  bool tapCategory(String kategoriAdi) {
    final kart = seciliKart;
    if (kart == null) return false; // önce kart seçilmeli

    final hedef = hedefler.firstWhere(
      (h) => h.kategoriAdi == kategoriAdi,
      orElse: () => KategoriHedef(kategoriAdi: '', ders: '', hedef: 0),
    );
    if (hedef.kategoriAdi.isEmpty) return false;

    hamle++;

    if (kart.kategoriAdi != kategoriAdi || hedef.tamamlandi) {
      return false; // yanlış eşleştirme
    }

    sonEslesenAdet = _yerlestirGrup(seciliSutun!, hedef);
    seciliSutun = null;
    return true;
  }

  /// Sürükle-bırak eşleştirmesi: [sutunIndex] sütununun açık kartını doğrudan
  /// [kategoriAdi] hedefine bırakmayı dener. Dokun-seç adımını atlar; içeride
  /// [tapCategory] mantığını kullanır (aynı doğru/yanlış kuralı, aynı [hamle]
  /// sayacı). Sürükleme sonrası seçim durumu her hâlükârda temizlenir.
  bool matchCard(int sutunIndex, String kategoriAdi) {
    if (topKart(sutunIndex) == null) return false;
    seciliSutun = sutunIndex;
    final ok = tapCategory(kategoriAdi);
    seciliSutun = null;
    return ok;
  }

  /// Kart-üstüne-kart ARA HAMLESİ: [kaynakSutun]'un açık grubunu, [hedefSutun]'un
  /// açık kartının üzerine YIĞAR — YALNIZCA iki üst kart AYNI kategoriye aitse.
  ///
  /// Başarılıysa: kaynağın açık grubu hedef sütunun üstüne taşınır (hedefte artık
  /// aynı kategoriden birden fazla açık kart üst üste durur), kaynak sütun boşalır
  /// / varsa alttaki kartı açılır, true döner. Bu bir TAMAMLAMA DEĞİLDİR — hiçbir
  /// kategori sayacı ARTMAZ; yalnızca sıkışık sütunları açmaya/organize etmeye
  /// yarayan bir hamledir. Kategoriler farklıysa hiçbir şey değişmez, false döner
  /// (UI kırmızı flaş göstermeli). Her iki durumda da [hamle] artar (bir deneme).
  bool stackCard(int kaynakSutun, int hedefSutun) {
    if (kaynakSutun == hedefSutun) return false;
    final kaynakTop = topKart(kaynakSutun);
    final hedefTop = topKart(hedefSutun);
    if (kaynakTop == null || hedefTop == null) return false;

    hamle++; // yığma da sürükle-bırak denemesidir → bir hamle harcar

    if (kaynakTop.kategoriAdi != hedefTop.kategoriAdi) {
      return false; // FARKLI kategori → yığılamaz (kırmızı flaş)
    }

    // Aynı kategori: kaynağın tüm açık grubunu hedefin üstüne taşı.
    final kaynak = sutunlar[kaynakSutun];
    final hedef = sutunlar[hedefSutun];
    final grup = _acikGrupKartlari(kaynak);
    kaynak.removeRange(kaynak.length - grup.length, kaynak.length);
    for (final k in grup) {
      k.faceUp = true;
      hedef.add(k);
    }
    // Kaynakta bir alt kart açılır.
    if (kaynak.isNotEmpty && !kaynak.last.faceUp) {
      kaynak.last.faceUp = true;
    }
    seciliSutun = null;
    return true;
  }

  /// Satın alınan JOKER: oynanabilir bir kartı (grubu) DOĞRU kategorisine
  /// otomatik yerleştirir. Yerleştirilecek uygun bir kart varsa true (ve
  /// [sonEslesenAdet] düşen kart sayısını tutar), yoksa false döner. Bir hamle
  /// HARCAMAZ (satın alınmış yardımcı). Coin/market kontrolü UI'da yapılır.
  bool joker() {
    for (var i = 0; i < sutunlar.length; i++) {
      final k = topKart(i);
      if (k == null) continue;
      final hedef = _uygunHedef(k.kategoriAdi);
      if (hedef == null) continue;
      sonEslesenAdet = _yerlestirGrup(i, hedef);
      seciliSutun = null;
      return true;
    }
    return false;
  }

  /// Joker'in şu an yerleştirebileceği bir kart var mı? (Market butonunu
  /// etkinleştirmek için.)
  bool get jokerUygun {
    for (var i = 0; i < sutunlar.length; i++) {
      final k = topKart(i);
      if (k != null && _uygunHedef(k.kategoriAdi) != null) return true;
    }
    return false;
  }

  // ── Market ile satın alınan yardımcılar (coin harcaması UI'da yapılır) ──
  void satinAlinanIpucu() => ipucuHakki++;
  void satinAlinanGeriAl() => geriAlHakki++;

  /// Kaybetme ekranındaki "Hamle Hakkı Satın Al" için bütçeyi büyütür.
  void hamleEkle(int adet) {
    if (adet > 0) hamleButcesi += adet;
  }

  /// Çekme destesinden (kuyruk) bir sonraki terimi tableau'ya dağıtır.
  ///
  /// BOŞ bir sütun varsa oraya konur; yoksa EN AZ kartlı sütunun üstüne
  /// (üst üste ekstra kart olarak) eklenir. Yeni kart açık/oynanabilir olur,
  /// üstüne konduğu önceki kart kapanır. Kuyruk boşsa false döner.
  bool cekDeste() {
    if (bekleyenKuyruk.isEmpty) return false;
    final kart = bekleyenKuyruk.removeAt(0);

    // Önce boş sütun ara.
    int hedefSutun = -1;
    for (var i = 0; i < sutunlar.length; i++) {
      if (sutunlar[i].isEmpty) {
        hedefSutun = i;
        break;
      }
    }
    // Boş sütun yoksa en az kartlı sütunu seç.
    if (hedefSutun < 0) {
      hedefSutun = 0;
      for (var i = 1; i < sutunlar.length; i++) {
        if (sutunlar[i].length < sutunlar[hedefSutun].length) hedefSutun = i;
      }
    }

    final c = sutunlar[hedefSutun];
    // Önceki açık grubun TAMAMI kapanır (yeni çekilen kart yeni bir açık grup
    // başlatır; böylece bir sütunun açık grubu her zaman tek kategoriden olur).
    for (var i = c.length - 1; i >= 0 && c[i].faceUp; i--) {
      c[i].faceUp = false;
    }
    kart.faceUp = true;
    c.add(kart);
    return true;
  }

  /// Bu seviyedeki kategorilerin ait olduğu ortak dersi verir; birden fazla
  /// dersten kategori varsa "Karışık" döner (üstteki ders rozeti için).
  String get seviyeDers {
    if (hedefler.isEmpty) return 'Karışık';
    final ilk = hedefler.first.ders;
    return hedefler.every((h) => h.ders == ilk) ? ilk : 'Karışık';
  }

  /// Çekme destesinde bekleyen kart sayısı (draw pile sayacı).
  int get bekleyenSayisi => bekleyenKuyruk.length;

  /// Seçim gerektirmeyen ipucu: oynanabilir bir kart bulup terim + doğru
  /// kategorisini döndürür ve ipucu hakkını düşürür. Hak yoksa null döner.
  ({String terim, String kategori})? hintAny() {
    if (ipucuHakki <= 0) return null;
    for (var i = 0; i < sutunlar.length; i++) {
      final k = topKart(i);
      if (k != null) {
        ipucuHakki--;
        return (terim: k.terim, kategori: k.kategoriAdi);
      }
    }
    return null;
  }

  /// Son doğru eşleştirmeyi geri alır. Hak yoksa ya da geri alınacak hamle
  /// yoksa false döner.
  bool undo() {
    if (geriAlHakki <= 0 || _undoStack.isEmpty) return false;
    final kayit = _undoStack.removeLast();
    final c = sutunlar[kayit.sutunIndex];

    // Bu eşleştirmeyle açılan alt kartı tekrar kapat.
    if (kayit.altKartAcildi && c.isNotEmpty) {
      c.last.faceUp = false;
    }
    // Grubun tamamını geri koy (tekrar açık ve oynanabilir).
    for (final k in kayit.grup) {
      k.faceUp = true;
      c.add(k);
    }

    // Kategori sayacını grup boyutu kadar düşür.
    final hedef = hedefler.firstWhere((h) => h.kategoriAdi == kayit.grup.first.kategoriAdi);
    hedef.eslesen = (hedef.eslesen - kayit.grup.length).clamp(0, hedef.hedef);

    geriAlHakki--;
    seciliSutun = null;
    return true;
  }

  /// O sütunun üstteki kartının doğru kategorisini verir; ipucu hakkını düşürür.
  /// Hak yoksa ya da açık kart yoksa null döner.
  String? hint(int sutunIndex) {
    if (ipucuHakki <= 0) return null;
    final kart = topKart(sutunIndex);
    if (kart == null) return null;
    ipucuHakki--;
    return kart.kategoriAdi;
  }

  /// Kalan (henüz eşleşmemiş) toplam terim sayısı — tableau + çekme destesi.
  int get kalanTerim =>
      sutunlar.fold(0, (a, c) => a + c.length) + bekleyenKuyruk.length;

  /// Seviyedeki toplam terim (kart) sayısı.
  int get toplamTerim => hedefler.fold(0, (a, h) => a + h.hedef);

  bool get geriAlinabilir => geriAlHakki > 0 && _undoStack.isNotEmpty;

  bool get seviyeTamamlandi => kalanTerim == 0;

  /// Kalan hamle hakkı (bütçe − yapılan deneme). Negatif olmaz.
  int get kalanHamle {
    final k = hamleButcesi - hamle;
    return k < 0 ? 0 : k;
  }

  /// KAYBETME koşulu: hamle bütçesi tükendi VE hâlâ tamamlanmamış kart var.
  bool get kaybedildi => hamle >= hamleButcesi && !seviyeTamamlandi;
}
