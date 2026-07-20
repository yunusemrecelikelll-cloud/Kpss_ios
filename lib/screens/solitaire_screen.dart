import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/subject.dart';
import '../data/kategori_eslestirme_data.dart';
import '../games/solitaire_engine.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../theme/theme_provider.dart';
import 'tools_hub_screen.dart';
import 'map_game/map_shared.dart';

/// Günlük ücretsiz oynama hakkı (mevcut oyunlarla aynı desen).
const int kFreeSolitaireDaily = 10;
const String kSolitaireGameId = 'solitaire';

// ── Oyun-içi coin ekonomisi (kozmetik; gerçek para DEĞİL) ──
// Denge: her doğru kart +12 coin → ~15-20 kartlık bir seviye ~200-260 coin
// kazandırır; seviye bitince +60 taban ve kalan hamle başına +1 verimlilik
// bonusu eklenir. Market fiyatları (ipucu 50 / geri-al 80 / joker 150) bu
// kazançla dengeli: bir seviye kabaca 1 joker + birkaç ipucu finanse eder.
const int kCoinPerKart = 12; // doğru eşleşen kart başına
const int kCoinSeviyeBonus = 60; // seviye tamamlama tabanı
const int kFiyatIpucu = 50; // market: +1 ipucu
const int kFiyatGeriAl = 80; // market: +1 geri al
const int kFiyatJoker = 150; // market: joker (bir kartı otomatik yerleştir)
const int kFiyatKurtarma = 30; // kayıp ekranı: +10 hamle
const int kKurtarmaHamle = 10; // kayıp ekranında satın alınan hamle

// ── "Oyun masası" sabit paleti ──
// Bu ekran, uygulamanın genel light/dark temasından BAĞIMSIZ, kendine özgü bir
// kumar-masası kimliği taşır (referans görseldeki yeşil keçe). ThemeProvider
// renkleri yalnızca menüde/zorluk seçiminde kullanılır; oyun tahtası aşağıdaki
// sabitleri kullanır.
const Color _tableGreen = Color(0xFF0F6B3E); // ana keçe yeşili
const Color _tableGreenDark = Color(0xFF0A4E2C); // koyu ton (app bar / kilitli slot)
const Color _feltGreen = Color(0xFF148A4F); // açık keçe (vurgu)
const Color _cardCream = Color(0xFFFAF3E4); // terim/kategori kart zemini
const Color _cardInk = Color(0xFF2A1D10); // kart yazısı (koyu kahve/siyah)
const Color _goldTrim = Color(0xFFF5B942); // altın kenarlık
const Color _backBlue = Color(0xFF1E5FA8); // kapalı kart sırtı
const Color _backBlueDark = Color(0xFF16457A);

// ── Terim kartı boyut oranı ──
// Standart iskambil kartı en-boy oranı ~2.5:3.5 (genişlik:yükseklik ≈ 0.714).
// Kart yüksekliği SABİT bir sayı DEĞİL; her build'de tableau'nun o anki
// gerçek sütun genişliğinden (bkz. [_EslestirmePlayScreenState._cardHeight])
// türetilir — böylece ekran genişliği ne olursa olsun (dar/geniş telefon)
// kart iskambil oranını korur ve sütun taşması/kırpılması yaşanmaz.
const double kTerimKartOrani = 2.5 / 3.5; // genişlik / yükseklik

// ── Yerleşim sabitleri ──
/// Kartlar arası yatay/dikey boşluk.
const double kKartBosluk = 6.0;

/// Hedef kategori kartları TOPLAM 5 SIRA hâlinde ve her sırada yan yana
/// [kHedefSatirKapasite] kart olacak şekilde dizilir (5 × 5 = 25 slot; Zor
/// seviyedeki 20 hedef 4 sıraya sığar). Hedef kartları, tableau sütunlarıyla
/// AYNI genişlik biriminden türetildiği için normal terim kartlarıyla birebir
/// aynı boyuttadır.
const int kHedefSatirKapasite = kSutunSayisi; // sıra başına kart (yan yana)
const int kHedefMaxSatir = 5; // toplam sıra sayısı

/// Sürüklenen kart, parmağın dokunduğu noktanın BU KADAR üstünde durur —
/// böylece parmak kartı kapatmaz. Bırakma hedefi de (feedbackOffset ile) aynı
/// miktarda yukarı taşınır, yani "kartın gördüğü yer" ile "bırakılan yer" aynıdır.
const double kSuruklemeYukariPay = 66.0;

/// Dokunma (hit-test) alanı, görsel karttan bu kadar BÜYÜK tutulur — kartı
/// ilk dokunuşta yakalayabilmek için.
const double kDokunmaPayi = 14.0;

/// Kategori Eşleştirme Solitaire.
///
/// Klasik iskambil solitaire DEĞİL: KPSS terim kartlarını (İsim, Dik Açı,
/// Göktürkler, Marmara...) doğru KATEGORİYE (Sözcük Türleri, Açı Türleri, İlk
/// Türk Devletleri, Türkiye'nin Bölgeleri...) eşleştirme oyunu.
///
/// Etkileşim: açık terim kartını basılı tutup (long-press) doğru kategori
/// kartının üzerine SÜRÜKLE-BIRAK. Yanlış bırakınca kart yerinde kalır ve
/// kategori kırmızı yanıp söner. Sağ üstteki çekme destesinden yeni kartlar
/// tableau'ya dağıtılır.
///
/// Dış API KORUNUR: `SolitaireScreen(subjects: subjects)` — tools_hub_screen
/// bu şekilde çağırır.
class SolitaireScreen extends StatelessWidget {
  final List<Subject> subjects;
  const SolitaireScreen({super.key, required this.subjects});

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final colors = context.watch<ThemeProvider>().colors;
    final premium = storage.isPremiumUser();
    final gp = storage.getGamePlayState(kSolitaireGameId);
    final left = (kFreeSolitaireDaily - (gp['plays'] as int)).clamp(0, kFreeSolitaireDaily);

    return Scaffold(
      // Başlık, tema rengiyle aynı tona düşüp kaybolmasın diye AppBar rengi ve
      // yazı rengi BURADA sabitlenir (koyu keçe zemin + beyaz, yüksek kontrast).
      appBar: AppBar(
        backgroundColor: _tableGreenDark,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          '🃏 Eşleştirme Solitaire',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [colors.violet.withValues(alpha: 0.85), colors.rose.withValues(alpha: 0.85)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'Terim kartlarını doğru KATEGORİYE eşleştir!\n\n'
              'Açık bir terim kartını (ör. "Dik Açı") TUTUP üstteki doğru '
              'kategoriye (ör. "Açı Türleri") SÜRÜKLE — kart parmağının biraz '
              'üstünde durur, böylece nereye bıraktığını görürsün. Aynı kategoriden iki açık '
              'kartı üst üste sürükleyerek YIĞABİLİRSİN (sütun açılır). Her doğru '
              'eşleştirme 🪙 coin kazandırır — coinle marketten ipucu, geri al ya '
              'da joker al. Ama DİKKAT: hamle hakkın SINIRLI; biterse kaybedersin!',
              style: TextStyle(fontSize: 13.5, color: Colors.white, height: 1.5),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Text(
              premium ? 'Premium: sınırsız oynarsın.' : 'Bugün $left oyun hakkın kaldı.',
              style: TextStyle(fontSize: 12.5, color: colors.textFaint, fontWeight: FontWeight.w600),
            ),
          ),
          _ZorlukKarti(
            title: '🟢 Kolay',
            desc: '5 hedef kategori — ısınma turu.',
            kategoriSayisi: 5,
          ),
          _ZorlukKarti(
            title: '🟡 Orta',
            desc: '10 hedef kategori — dengeli bir seviye.',
            kategoriSayisi: 10,
          ),
          _ZorlukKarti(
            title: '🔴 Zor',
            desc: '20 hedef kategori — dolu bir tableau, uzun maraton.',
            kategoriSayisi: 20,
          ),
        ],
      ),
    );
  }
}

class _ZorlukKarti extends StatelessWidget {
  final String title;
  final String desc;
  final int kategoriSayisi;
  const _ZorlukKarti({required this.title, required this.desc, required this.kategoriSayisi});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(desc),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          context.read<SoundService>().click();
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => _EslestirmePlayScreen(kategoriSayisi: kategoriSayisi)),
          );
        },
      ),
    );
  }
}

/// Oyun tahtası — bir seviyeyi oynatan ekran.
class _EslestirmePlayScreen extends StatefulWidget {
  final int kategoriSayisi;
  const _EslestirmePlayScreen({required this.kategoriSayisi});

  @override
  State<_EslestirmePlayScreen> createState() => _EslestirmePlayScreenState();
}

class _EslestirmePlayScreenState extends State<_EslestirmePlayScreen>
    with SingleTickerProviderStateMixin {
  final _engine = KategoriEslestirmeEngine();
  bool _locked = false;
  bool _booted = false;
  bool _finished = false;
  bool _lost = false;

  /// Bu oyuncunun güncel coin/altın bakiyesi (StorageService ile senkron).
  int _coins = 0;

  /// Bu turda kazanılan toplam coin (sonuç ekranında göstermek için).
  int _kazanilanCoin = 0;

  /// Yanlış bırakılışta kısa süre kırmızı yakılan kategori adı.
  String? _flashKategori;

  /// Yanlış YIĞMA denemesinde kısa süre kırmızı yakılan sütun.
  int? _flashSutun;

  /// Sürüklenen kartın o an üzerinde olduğu (hover) kategori — kenarlık vurgusu.
  String? _hoverKategori;

  /// Sürüklenen kartın o an üzerinde olduğu (hover) hedef yığma sütunu.
  int? _hoverSutun;

  /// Kart ölçüleri — HEM hedef kategori kartları HEM tableau terim kartları bu
  /// aynı ölçüyü kullanır (aynı boyut şartı). [_buildBoard] içindeki
  /// [LayoutBuilder] her build'de kullanılabilir genişlik VE yüksekliği ölçüp
  /// bunları günceller; böylece kart iskambil oranını korur ve 5 sıralık hedef
  /// ızgarası + tableau ekrana taşmadan sığar.
  double _cardHeight = 82.0;
  double _cardWidth = 82.0 * kTerimKartOrani;

  /// Hedef kategori ızgarasının o anki toplam yüksekliği — dağıtım
  /// animasyonunda tableau kartlarının başlangıç konumunu hesaplamak için.
  double _hedefAlanYukseklik = 0;

  /// Seviye açılışındaki "kartlar sağ üstteki desteden dağıtılıyor" animasyonu.
  late final AnimationController _dagitimCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  /// Çekme destesinin, tahta alanı içindeki yaklaşık konumu (dağıtım
  /// animasyonunun başlangıç noktası). Deste sağ ÜSTTE olduğu için x = sağ
  /// kenar, y = tahtanın biraz üstü.
  Offset _destePozisyon(double tahtaGenisligi) =>
      Offset(tahtaGenisligi - _cardWidth, -(_cardHeight + 40));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  @override
  void dispose() {
    _dagitimCtrl.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    final storage = context.read<StorageService>();
    final premium = storage.isPremiumUser();
    if (!premium) {
      final gp = storage.getGamePlayState(kSolitaireGameId);
      if ((gp['plays'] as int) >= kFreeSolitaireDaily) {
        if (!mounted) return;
        setState(() => _locked = true);
        return;
      }
      await storage.useGamePlay(kSolitaireGameId);
    }
    if (!mounted) return;

    final pool = List<KategoriGrubu>.from(kKategoriGruplari)..shuffle(Random());
    // Hedef ızgarası en fazla [kHedefMaxSatir] × [kHedefSatirKapasite] slot
    // taşıyabildiği için kategori sayısı bu kapasiteyle de sınırlanır.
    const izgaraKapasite = kHedefMaxSatir * kHedefSatirKapasite;
    final int ustSinir =
        izgaraKapasite < kKategoriGruplari.length ? izgaraKapasite : kKategoriGruplari.length;
    final int adet = widget.kategoriSayisi < ustSinir ? widget.kategoriSayisi : ustSinir;
    final secilen = pool.take(adet).toList();
    _engine.startLevel(secilen);
    _dagitimCtrl.forward(from: 0); // kartlar sağ üstteki desteden dağıtılsın
    setState(() {
      _booted = true;
      _finished = false;
      _lost = false;
      _kazanilanCoin = 0;
      _coins = storage.getSolitaireCoins();
      _flashKategori = null;
      _flashSutun = null;
      _hoverKategori = null;
      _hoverSutun = null;
    });
  }

  void _retry() {
    setState(() {
      _booted = false;
      _locked = false;
      _finished = false;
      _lost = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  /// Coin ekler (ekranda + kalıcı depoda) ve tur kazancını günceller.
  Future<void> _coinEkle(int miktar) async {
    if (miktar <= 0) return;
    _coins += miktar;
    _kazanilanCoin += miktar;
    await context.read<StorageService>().addSolitaireCoins(miktar);
  }

  /// Sürükle-bırak eşleştirmesi (Draggable → kategori DragTarget onAccept).
  Future<void> _onDrop(int sutunIndex, KategoriHedef h) async {
    setState(() => _hoverKategori = null);
    final ok = _engine.matchCard(sutunIndex, h.kategoriAdi);
    if (ok) {
      context.read<SoundService>().click();
      // Doğru: düşen kart sayısı kadar coin.
      await _coinEkle(_engine.sonEslesenAdet * kCoinPerKart);
      if (!mounted) return;
      if (_engine.seviyeTamamlandi) {
        // Seviye bonusu: taban + kalan hamle (verimlilik ödülü).
        await _coinEkle(kCoinSeviyeBonus + _engine.kalanHamle);
        if (!mounted) return;
        setState(() => _finished = true);
      } else if (_engine.kaybedildi) {
        // Doğru hamleydi ama bütçe tam bu hamlede tükendiyse yine kayıp.
        setState(() => _lost = true);
      } else {
        setState(() {});
      }
    } else {
      // Yanlış: kart engine'de kaldığı için görsel olarak yerinde durur;
      // kategori kartı kırmızı yanıp söner. Bu yanlış deneme de hamle harcadı.
      _flashWrong(h.kategoriAdi);
      if (_engine.kaybedildi) {
        setState(() => _lost = true);
      } else {
        setState(() {});
      }
    }
  }

  /// Kart-üstüne-kart yığma (bir sütunun açık kartı → başka sütunun açık kartı).
  void _onStackDrop(int kaynakSutun, int hedefSutun) {
    setState(() => _hoverSutun = null);
    if (kaynakSutun == hedefSutun) return;
    final ok = _engine.stackCard(kaynakSutun, hedefSutun);
    if (ok) {
      context.read<SoundService>().click();
      setState(() {});
    } else {
      // Farklı kategori → yığılamaz; hedef sütun kırmızı yanıp söner.
      _flashWrongSutun(hedefSutun);
    }
    // Yığma da (doğru/yanlış) bir hamle harcadığından bütçe bitmiş olabilir.
    if (_engine.kaybedildi) setState(() => _lost = true);
  }

  void _flashWrong(String kategoriAdi) {
    setState(() => _flashKategori = kategoriAdi);
    Future.delayed(const Duration(milliseconds: 550), () {
      if (mounted && _flashKategori == kategoriAdi) setState(() => _flashKategori = null);
    });
  }

  void _flashWrongSutun(int sutun) {
    setState(() => _flashSutun = sutun);
    Future.delayed(const Duration(milliseconds: 550), () {
      if (mounted && _flashSutun == sutun) setState(() => _flashSutun = null);
    });
  }

  void _onCekDeste() {
    if (_engine.bekleyenSayisi == 0) return;
    context.read<SoundService>().click();
    setState(() => _engine.cekDeste());
  }

  void _onIpucu() {
    context.read<SoundService>().click();
    final ip = _engine.hintAny();
    if (ip == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('İpucu hakkın kalmadı.'),
        duration: Duration(milliseconds: 1400),
      ));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('💡 "${ip.terim}" → ${ip.kategori}'),
      duration: const Duration(milliseconds: 2200),
    ));
    setState(() {});
  }

  void _onGeriAl() {
    context.read<SoundService>().click();
    final ok = _engine.undo();
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Geri alınacak hamle yok ya da hakkın kalmadı.'),
        duration: Duration(milliseconds: 1400),
      ));
      return;
    }
    setState(() {});
  }

  /// Coin harcayarak ekstra ipucu / geri al / joker satın alınan market.
  void _openMarket() {
    context.read<SoundService>().click();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _tableGreenDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheet) {
            // Bir satın alma işler: coin düşer, etkiyi uygular, iki tarafı da tazeler.
            Future<void> satinAl(int fiyat, String basari, void Function() etki) async {
              final sheetNav = Navigator.of(sheetCtx); // async gap öncesi yakala
              final ok = await context.read<StorageService>().spendSolitaireCoins(fiyat);
              if (!ok) return; // yetersiz (buton zaten pasif olmalı)
              etki();
              if (!mounted) return;
              _coins = context.read<StorageService>().getSolitaireCoins();
              context.read<SoundService>().click();
              // Joker seviyeyi bitirmiş olabilir → bonus ver, sheet'i kapat, sonuç.
              if (_engine.seviyeTamamlandi && !_finished) {
                await _coinEkle(kCoinSeviyeBonus + _engine.kalanHamle);
                if (!mounted) return;
                _coins = context.read<StorageService>().getSolitaireCoins();
                if (sheetNav.canPop()) sheetNav.pop();
                setState(() => _finished = true);
                return;
              }
              setSheet(() {});
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(basari),
                duration: const Duration(milliseconds: 1500),
              ));
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('🛒 Market',
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Colors.white)),
                        const Spacer(),
                        _coinRozet(_coins),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text('Coin harcayarak yardım al. Coinini doğru eşleştirmelerle kazanırsın.',
                        style: TextStyle(fontSize: 12, color: Colors.white70)),
                    const SizedBox(height: 14),
                    _marketSatir(
                      emoji: '💡',
                      baslik: '+1 İpucu Hakkı',
                      fiyat: kFiyatIpucu,
                      yeterli: _coins >= kFiyatIpucu,
                      onAl: () => satinAl(kFiyatIpucu, '💡 +1 ipucu hakkı eklendi.',
                          () => _engine.satinAlinanIpucu()),
                    ),
                    const SizedBox(height: 10),
                    _marketSatir(
                      emoji: '↩️',
                      baslik: '+1 Geri Al Hakkı',
                      fiyat: kFiyatGeriAl,
                      yeterli: _coins >= kFiyatGeriAl,
                      onAl: () => satinAl(kFiyatGeriAl, '↩️ +1 geri al hakkı eklendi.',
                          () => _engine.satinAlinanGeriAl()),
                    ),
                    const SizedBox(height: 10),
                    _marketSatir(
                      emoji: '🃏',
                      baslik: 'Joker — bir kartı otomatik yerleştir',
                      fiyat: kFiyatJoker,
                      yeterli: _coins >= kFiyatJoker && _engine.jokerUygun,
                      onAl: () => satinAl(kFiyatJoker, '🃏 Joker bir kartı doğru kategoriye yerleştirdi!',
                          () => _engine.joker()),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_locked) {
      return const LockedFeatureCard(
        title: 'Eşleştirme Solitaire',
        desc: "Bugünkü $kFreeSolitaireDaily ücretsiz oyun hakkını kullandın. Yarın tekrar oyna ya da Premium'a geçip sınırsız oyna.",
      );
    }
    if (!_booted) {
      return const Scaffold(
        backgroundColor: _tableGreen,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }
    if (_finished) {
      return MapSessionResult(
        title: '🃏 Eşleştirme Solitaire',
        emoji: '🎉',
        message: 'Seviye tamamlandı!\n'
            '${_engine.toplamTerim} terimin tamamını doğru kategorilere eşleştirdin.\n'
            '${_engine.hamle}/${_engine.hamleButcesi} hamle kullandın.\n'
            '🪙 Bu turda +$_kazanilanCoin coin kazandın (toplam: $_coins).',
        onRetry: _retry,
      );
    }
    if (_lost) {
      return _buildKayip(context);
    }
    return _buildBoard(context);
  }

  Widget _buildBoard(BuildContext context) {
    return Scaffold(
      backgroundColor: _tableGreen,
      appBar: AppBar(
        backgroundColor: _tableGreenDark,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        // Başlık arka planla aynı tona düşüp kaybolmasın: rengi açıkça beyaz.
        title: const Text(
          '🃏 Eşleştirme Solitaire',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17),
        ),
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── Üst çubuk: ders rozeti + coin · Kalan hamle · SAĞ ÜSTTE deste ──
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _dersRozeti(),
                      const SizedBox(height: 6),
                      _coinRozet(_coins),
                    ],
                  ),
                  const SizedBox(width: 8),
                  // Bayrak esner + gerekirse küçülür → dar telefonlarda taşma yok.
                  Expanded(
                    child: Center(
                      child: FittedBox(fit: BoxFit.scaleDown, child: _hamleBayragi()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Çekme destesi HER ZAMAN sağ üst köşede: hem hedef kategori
                  // kartları hem de terim kartları (dağıtım animasyonunda)
                  // buradan çıkar.
                  _buildCekDeste(),
                ],
              ),
            ),
            // Tahtanın TAMAMI tek bir LayoutBuilder ile ölçülür: kullanılabilir
            // genişlik VE yükseklikten kart boyutu türetilir; 5 sıralık hedef
            // ızgarası + tableau sığmıyorsa kart oranı korunarak küçültülür
            // (sabit piksel yok → taşma/overflow olmaz).
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final tahtaGenislik = constraints.maxWidth;
                    final tahtaYukseklik = constraints.maxHeight;

                    // Tableau: 5 sütun + aralarındaki boşluklar (0.5 px yuvarlama
                    // güvenlik payıyla — hairline taşma olmasın).
                    final sutunGenisligi =
                        (tahtaGenislik - 0.5 - kKartBosluk * (kSutunSayisi - 1)) / kSutunSayisi;
                    final idealYukseklik = sutunGenisligi / kTerimKartOrani;

                    // Hedef ızgarasının sıra sayısı (en fazla [kHedefMaxSatir]).
                    final hedefAdet = _engine.hedefler.length;
                    var satirSayisi = (hedefAdet / kHedefSatirKapasite).ceil();
                    if (satirSayisi < 1) satirSayisi = 1;
                    if (satirSayisi > kHedefMaxSatir) satirSayisi = kHedefMaxSatir;

                    // İki bölüm başlığı + aralarındaki boşluklar için dikey pay.
                    // Cihazın yazı ölçeği büyükse başlıklar da büyür → pay onunla
                    // birlikte artar (aksi hâlde Column taşardı).
                    final baslikOlcek =
                        (MediaQuery.textScalerOf(context).scale(12.5) / 12.5).clamp(1.0, 2.0);
                    final basliklarYukseklik = 20.0 + 36.0 * baslikOlcek;
                    // Tableau'nun en az bir kart + yığın "peek" payı kadar yeri olmalı.
                    const tableauPayCarpani = 1.5;
                    // ÖLÇEK yalnızca kartlara uygulanır; başlık/boşluk payları
                    // sabit olduğu için önce düşülür — aksi hâlde küçük ekranda
                    // sütun yine taşardı.
                    final kartlaraKalan = tahtaYukseklik -
                        basliklarYukseklik -
                        satirSayisi * kKartBosluk;
                    final gerekliKart = idealYukseklik * (satirSayisi + tableauPayCarpani);
                    final olcek = (kartlaraKalan <= 0 || gerekliKart <= kartlaraKalan)
                        ? 1.0
                        : (kartlaraKalan / gerekliKart);

                    _cardHeight = idealYukseklik * olcek;
                    _cardWidth = _cardHeight * kTerimKartOrani;
                    final hedefAlanYukseklik =
                        satirSayisi * _cardHeight + (satirSayisi - 1) * kKartBosluk;
                    _hedefAlanYukseklik = hedefAlanYukseklik;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Hedef kategori kartları (DragTarget) — 5 sıra, yan yana ──
                        const _BolumBasligi('🎯 Hedef Kategoriler'),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: hedefAlanYukseklik,
                          width: double.infinity,
                          child: _buildHedefIzgara(tahtaGenislik, satirSayisi),
                        ),
                        const SizedBox(height: 8),
                        // ── Tableau sütunları (Draggable açık kartlar) ──
                        const _BolumBasligi('🂠 Kartlar — kartı tutup kategoriye sürükle'),
                        const SizedBox(height: 6),
                        Expanded(
                          child: SingleChildScrollView(
                            child: _buildTableau(tahtaGenislik),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            // ── Alt araç çubuğu: İpucu · Geri Al ──
            Container(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
              decoration: const BoxDecoration(
                color: _tableGreenDark,
                border: Border(top: BorderSide(color: Colors.white24)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: _toolBtnStyle(),
                      onPressed: _engine.ipucuHakki > 0 ? _onIpucu : null,
                      icon: const Text('💡', style: TextStyle(fontSize: 15)),
                      label: Text('İpucu (${_engine.ipucuHakki})',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: _toolBtnStyle(),
                      onPressed: _engine.geriAlinabilir ? _onGeriAl : null,
                      icon: const Text('↩️', style: TextStyle(fontSize: 15)),
                      label: Text('Geri Al (${_engine.geriAlHakki})',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: _toolBtnStyle(),
                      onPressed: _openMarket,
                      icon: const Text('🛒', style: TextStyle(fontSize: 15)),
                      label: const Text('Market', maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  ButtonStyle _toolBtnStyle() => OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        disabledForegroundColor: Colors.white38,
        side: const BorderSide(color: Colors.white54),
        backgroundColor: Colors.white.withValues(alpha: 0.06),
      );

  // ── Üst çubuk parçaları ─────────────────────────────────────────────

  Widget _dersRozeti() {
    final ders = _engine.seviyeDers;
    const dersEmoji = {
      'Türkçe': '📘',
      'Matematik': '🔢',
      'Tarih': '🏛️',
      'Coğrafya': '🌍',
      'Vatandaşlık': '⚖️',
      'Karışık': '🎯',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: _cardCream,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _goldTrim, width: 1.4),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(dersEmoji[ders] ?? '🎯', style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Text(ders,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: _cardInk)),
        ],
      ),
    );
  }

  Widget _hamleBayragi() {
    // Basit flama/bayrak: sağ kenarı çentikli kutu. Kalan hamle azaldıkça (≤5)
    // kırmızıya döner — SINIRLI kaynak uyarısı.
    final kalan = _engine.kalanHamle;
    final azaldi = kalan <= 5;
    return ClipPath(
      clipper: _FlamaClipper(),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 7, 20, 7),
        color: azaldi ? const Color(0xFFC0392B) : _feltGreen,
        child: Text(
          'Kalan Hamle: $kalan',
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }

  /// Üstteki 🪙 coin göstergesi (krem rozet, altın kenarlık) — market sheet'inde
  /// de kullanılır.
  Widget _coinRozet(int coins) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _cardCream,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _goldTrim, width: 1.4),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🪙', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Text('$coins',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: _cardInk)),
        ],
      ),
    );
  }

  /// Market bottom sheet'inde tek bir satın alma satırı (emoji · başlık · fiyat ·
  /// "Satın Al"). Coin yetmezse (ya da joker için yerleştirilecek kart yoksa)
  /// buton pasif/gri görünür.
  Widget _marketSatir({
    required String emoji,
    required String baslik,
    required int fiyat,
    required bool yeterli,
    required VoidCallback onAl,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(baslik,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Colors.white)),
                const SizedBox(height: 2),
                Text('🪙 $fiyat coin',
                    style: const TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: yeterli ? onAl : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: _goldTrim,
              foregroundColor: _cardInk,
              disabledBackgroundColor: Colors.white24,
              disabledForegroundColor: Colors.white38,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5),
            ),
            child: const Text('Satın Al'),
          ),
        ],
      ),
    );
  }

  /// Hamle bütçesi tükenince gösterilen KAYBETME ekranı. "Tekrar Dene" +
  /// (coin yeterliyse) coin harcayarak "Hamle Hakkı Satın Al" kurtarma seçeneği.
  Widget _buildKayip(BuildContext context) {
    final kurtarilabilir = _coins >= kFiyatKurtarma;
    return Scaffold(
      backgroundColor: _tableGreen,
      appBar: AppBar(
        backgroundColor: _tableGreenDark,
        foregroundColor: Colors.white,
        title: const Text('🃏 Eşleştirme Solitaire'),
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: _cardCream,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _goldTrim, width: 2),
              boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 12, offset: Offset(0, 6))],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('💥', style: TextStyle(fontSize: 46)),
                const SizedBox(height: 10),
                const Text('Hamle hakkın bitti!',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: _cardInk)),
                const SizedBox(height: 8),
                Text(
                  '${_engine.hamleButcesi} hamlelik bütçen doldu ama hâlâ '
                  '${_engine.kalanTerim} kart tamamlanmadı.\n'
                  '🪙 Bakiyen: $_coins coin',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, height: 1.5, color: _cardInk.withValues(alpha: 0.8)),
                ),
                const SizedBox(height: 20),
                if (kurtarilabilir) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _onKurtar,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _goldTrim,
                        foregroundColor: _cardInk,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
                      ),
                      child: const Text('🪙 $kFiyatKurtarma coin → +$kKurtarmaHamle Hamle (Devam Et)'),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      context.read<SoundService>().click();
                      _retry();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _tableGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
                    ),
                    child: const Text('🔄 Tekrar Dene'),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    context.read<SoundService>().click();
                    Navigator.of(context).pop();
                  },
                  child: Text('Menüye Dön', style: TextStyle(color: _cardInk.withValues(alpha: 0.7))),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Kayıp ekranında coin harcayarak hamle satın alıp oyuna devam eder.
  Future<void> _onKurtar() async {
    context.read<SoundService>().click();
    final ok = await context.read<StorageService>().spendSolitaireCoins(kFiyatKurtarma);
    if (!ok || !mounted) return;
    _coins = context.read<StorageService>().getSolitaireCoins();
    _engine.hamleEkle(kKurtarmaHamle);
    setState(() => _lost = false); // bütçe arttı → oyuna geri dön
  }

  Widget _buildCekDeste() {
    final kalan = _engine.bekleyenSayisi;
    final onizleme = _engine.bekleyenKuyruk.take(2).toList();
    final aktif = kalan > 0;

    return GestureDetector(
      // Destenin TAMAMI (önizleme kartları + boşluklar dâhil) dokunulabilir.
      behavior: HitTestBehavior.opaque,
      onTap: aktif ? _onCekDeste : null,
      child: Opacity(
        opacity: aktif ? 1 : 0.55,
        child: SizedBox(
          width: 96,
          height: 60,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.centerRight,
            children: [
              // Önizleme kartları (sıradaki 2 terim), hafif yelpaze.
              if (onizleme.isNotEmpty)
                Positioned(
                  left: 0,
                  top: 6,
                  child: Transform.rotate(
                    angle: -0.18,
                    child: _miniOnizleme(onizleme.length > 1 ? onizleme[1].terim : onizleme[0].terim),
                  ),
                ),
              if (onizleme.isNotEmpty)
                Positioned(
                  left: 14,
                  top: 2,
                  child: Transform.rotate(
                    angle: -0.06,
                    child: _miniOnizleme(onizleme[0].terim),
                  ),
                ),
              // Kapalı çekme destesi + kalan sayı.
              Positioned(
                right: 0,
                top: 0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 42,
                      height: 46,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white70, width: 1.2),
                        boxShadow: const [
                          BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2))
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: CustomPaint(
                          painter: _CardBackPainter(),
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.45),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text('$kalan',
                                  style: const TextStyle(
                                      fontSize: 13, fontWeight: FontWeight.w900, color: Colors.white)),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(aktif ? 'Çek' : 'Bitti',
                        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniOnizleme(String terim) {
    return Container(
      width: 34,
      height: 44,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _cardCream,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _goldTrim.withValues(alpha: 0.8)),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 1))],
      ),
      child: Center(
        child: Text(
          terim,
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 6.5, height: 1.05, fontWeight: FontWeight.w800, color: _cardInk),
        ),
      ),
    );
  }

  // ── Dağıtım animasyonu ──────────────────────────────────────────────

  /// Kartı, sağ üstteki çekme destesinden yerine "uçurarak" gösterir.
  /// [sira]/[toplam] ile kartlar sırayla (stagger) dağıtılır; [yerelKonum]
  /// kartın tahta içindeki nihai konumudur.
  Widget _desteDagitim({
    required int sira,
    required int toplam,
    required Offset yerelKonum,
    required double tahtaGenislik,
    required Widget child,
  }) {
    return AnimatedBuilder(
      animation: _dagitimCtrl,
      child: child,
      builder: (context, icerik) {
        final basla = toplam <= 1 ? 0.0 : (sira / toplam) * 0.5;
        final ham = ((_dagitimCtrl.value - basla) / (1 - basla)).clamp(0.0, 1.0);
        if (ham >= 1.0) return icerik!;
        final t = Curves.easeOutCubic.transform(ham);
        final baslangic = _destePozisyon(tahtaGenislik) - yerelKonum;
        return Transform.translate(
          offset: baslangic * (1 - t),
          child: Opacity(opacity: 0.35 + 0.65 * t, child: icerik),
        );
      },
    );
  }

  // ── Hedef kategori ızgarası (5 sıra, yan yana) ──────────────────────

  Widget _buildHedefIzgara(double tahtaGenislik, int satirSayisi) {
    final hedefler = _engine.hedefler;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var s = 0; s < satirSayisi; s++) ...[
          if (s > 0) const SizedBox(height: kKartBosluk),
          SizedBox(
            height: _cardHeight,
            child: Row(
              children: [
                for (var k = 0; k < kHedefSatirKapasite; k++)
                  if (s * kHedefSatirKapasite + k < hedefler.length) ...[
                    if (k > 0) const SizedBox(width: kKartBosluk),
                    _buildKategori(
                      hedefler[s * kHedefSatirKapasite + k],
                      s * kHedefSatirKapasite + k,
                      Offset(k * (_cardWidth + kKartBosluk), s * (_cardHeight + kKartBosluk)),
                      tahtaGenislik,
                    ),
                  ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ── Kategori hedef kartı (DragTarget) ───────────────────────────────

  Widget _buildKategori(KategoriHedef h, int sira, Offset yerelKonum, double tahtaGenislik) {
    final flashing = _flashKategori == h.kategoriAdi;
    final hovering = _hoverKategori == h.kategoriAdi;
    final done = h.tamamlandi;

    Color borderColor = _goldTrim;
    double borderW = 1.4;
    Color bg = _cardCream;
    if (flashing) {
      borderColor = const Color(0xFFE23B3B);
      borderW = 2.4;
      bg = const Color(0xFFF6D9D5);
    } else if (hovering) {
      borderColor = const Color(0xFF2ECC71);
      borderW = 2.8;
    } else if (done) {
      borderColor = _goldTrim;
      borderW = 2.2;
    }

    // Yazı ölçüleri kart yüksekliğinden türetilir (sabit piksel yok) — kart
    // küçüldüğünde metin de küçülür, taşma olmaz.
    final sayacFont = (_cardHeight * 0.155).clamp(8.5, 15.0);
    final adFont = (_cardHeight * 0.115).clamp(7.0, 12.0);
    final dersFont = (_cardHeight * 0.095).clamp(6.0, 10.0);
    final ic = (_cardHeight * 0.06).clamp(3.0, 8.0);

    final kart = DragTarget<int>(
      // Kartın TAMAMI bırakma alanı olsun (şeffaf boşluklar dâhil).
      hitTestBehavior: HitTestBehavior.opaque,
      onWillAcceptWithDetails: (details) {
        // Tamamlanmış kategori yeni kart kabul etmez; onun dışında hover göster.
        if (done) return false;
        if (_hoverKategori != h.kategoriAdi) {
          setState(() => _hoverKategori = h.kategoriAdi);
        }
        return true;
      },
      onLeave: (_) {
        if (_hoverKategori == h.kategoriAdi) setState(() => _hoverKategori = null);
      },
      onAcceptWithDetails: (details) => _onDrop(details.data, h),
      builder: (context, candidate, rejected) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          // Hedef kartı, normal terim kartıyla BİREBİR aynı ölçüde.
          width: _cardWidth,
          height: _cardHeight,
          padding: EdgeInsets.symmetric(horizontal: ic, vertical: ic),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: borderColor, width: borderW),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(done ? '👑' : '🎯', style: TextStyle(fontSize: sayacFont)),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text('${h.eslesen}/${h.hedef}',
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: sayacFont,
                            color: done ? const Color(0xFFB8860B) : _cardInk)),
                  ),
                ],
              ),
              Expanded(
                child: Center(
                  child: Text(
                    h.kategoriAdi,
                    textAlign: TextAlign.center,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: adFont,
                        fontWeight: FontWeight.w800,
                        height: 1.12,
                        color: _cardInk),
                  ),
                ),
              ),
              Text(h.ders,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: dersFont, color: _cardInk.withValues(alpha: 0.6))),
            ],
          ),
        );
      },
    );

    // Hedef kartları da (terim kartları gibi) sağ üstteki desteden dağıtılır.
    return _desteDagitim(
      sira: sira,
      toplam: _engine.hedefler.length + kSutunSayisi,
      yerelKonum: yerelKonum,
      tahtaGenislik: tahtaGenislik,
      child: kart,
    );
  }

  // ── Tableau (5 sütun) ───────────────────────────────────────────────

  /// Tableau satırı. Sütun genişliği [_cardWidth] olarak SABİTLENİR (Expanded
  /// değil) — böylece terim kartları hedef kategori kartlarıyla birebir aynı
  /// boyutta olur; satır ortalanır.
  Widget _buildTableau(double tahtaGenislik) {
    final sutunlar = _engine.sutunlar;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < sutunlar.length; i++) ...[
          if (i > 0) const SizedBox(width: kKartBosluk),
          SizedBox(width: _cardWidth, child: _buildSutun(i, tahtaGenislik)),
        ],
      ],
    );
  }

  Widget _buildSutun(int i, double tahtaGenislik) {
    final c = _engine.sutunlar[i];
    // Dağıtım animasyonunda bu sütunun tahta içindeki yaklaşık konumu.
    final yerelKonum = Offset(
      i * (_cardWidth + kKartBosluk),
      _hedefAlanYukseklik + kKartBosluk * 5,
    );
    final dagitimToplam = _engine.hedefler.length + kSutunSayisi;

    if (c.isEmpty) {
      // Boş yuva — çekme destesi buraya kart koyabilir. Dolu sütunlarla hizalı
      // kalması için yükseklik terim kartıyla aynı ölçekten türetilir.
      return Container(
        height: _cardHeight,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: Colors.white38, width: 1.2),
          color: Colors.white.withValues(alpha: 0.05),
        ),
        child: Center(
          child: Icon(Icons.add_rounded,
              color: Colors.white38, size: (_cardHeight * 0.22).clamp(12.0, 22.0)),
        ),
      );
    }

    // Sondaki açık grup (yığma ile 1'den fazla olabilir); geri kalanı kapalı.
    final grup = _engine.acikGrup(i);
    final acikAdet = grup.isEmpty ? 0 : grup.length;
    final kapaliAdet = c.length - acikAdet;
    final kapaliGorunur = min(kapaliAdet, 4);

    // Kaydırma payları da kart yüksekliğinden türetilir (sabit piksel yok).
    final kapaliOffset = _cardHeight * 0.11;
    final kapaliKartY = _cardHeight * 0.26; // kapalı kart sırtının görünen payı
    final grupOffset = _cardHeight * 0.18; // yığındaki alt kartların "peek" payı
    final base = kapaliGorunur * kapaliOffset;
    final grupYuksek = acikAdet <= 1 ? 0.0 : (acikAdet - 1) * grupOffset;
    // Açık kartın dokunma alanı görsel karttan [kDokunmaPayi] kadar büyük.
    final toplamYukseklik = base + grupYuksek + _cardHeight + kDokunmaPayi;

    return _desteDagitim(
      sira: _engine.hedefler.length + i,
      toplam: dagitimToplam,
      yerelKonum: yerelKonum,
      tahtaGenislik: tahtaGenislik,
      child: SizedBox(
        height: toplamYukseklik,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Kapalı (mavi sırt) kartlar.
            for (var k = 0; k < kapaliGorunur; k++)
              Positioned(
                top: k * kapaliOffset,
                left: 2,
                right: 2,
                child: _kapaliKart(kapaliKartY),
              ),
            // Fazla gizli kapalı kart sayacı. IgnorePointer: bu rozet, altındaki
            // kartın dokunma alanını ASLA engellemesin.
            if (kapaliAdet > kapaliGorunur)
              Positioned(
                top: 0,
                right: 2,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: _backBlueDark,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white54, width: 0.8),
                    ),
                    child: Text('+$kapaliAdet',
                        style: const TextStyle(
                            fontSize: 9, color: Colors.white, fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
            // Yığındaki ALT açık kartlar (sadece görsel "peek") — dokunma
            // olaylarını yutmasınlar diye IgnorePointer ile sarılır.
            if (acikAdet > 1)
              for (var g = 0; g < acikAdet - 1; g++)
                Positioned(
                  top: base + g * grupOffset,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(child: _terimKarti(grup[g], faded: false)),
                ),
            // Açık grubun EN ÜST kartı — sürüklenebilir + yığma hedefi.
            // (Stack'te EN SON çizildiği için hit-test'te de en öndedir.)
            if (acikAdet > 0)
              Positioned(
                top: base + grupYuksek,
                left: 0,
                right: 0,
                child: _buildAcikKart(i, grup.last, acikAdet),
              ),
          ],
        ),
      ),
    );
  }

  Widget _kapaliKart(double yukseklik) {
    return Container(
      height: yukseklik,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: Colors.white54, width: 0.8),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2, offset: Offset(0, 1))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: CustomPaint(painter: _CardBackPainter(), child: const SizedBox.expand()),
      ),
    );
  }

  Widget _buildAcikKart(int sutunIndex, TerimKart kart, int grupAdet) {
    final flashing = _flashSutun == sutunIndex;
    final hovering = _hoverSutun == sutunIndex;

    // ── Dokunma hassasiyeti ──
    // 1) Gecikme minimuma indirildi: kart neredeyse dokunur dokunmaz yakalanır.
    // 2) [hitTestBehavior] = opaque: kartın TAMAMI (şeffaf dokunma payı dâhil)
    //    dokunulabilir; alttaki/üstteki widget'lar dokunuşu yutamaz.
    // 3) Kart, [kDokunmaPayi] kadar büyütülmüş şeffaf bir alanla sarılır —
    //    parmak kartın hemen kenarına düşse bile kart seçilir.
    // 4) Tableau artık başlıkla birlikte kaydırılan büyük bir listede değil;
    //    kendi bölmesinde durduğu için kaydırma jesti dokunuşu çalmaz.
    final draggable = LongPressDraggable<int>(
      data: sutunIndex,
      delay: const Duration(milliseconds: 25),
      hitTestBehavior: HitTestBehavior.opaque,
      // Sürüklenen kart parmağın BİRAZ ÜSTÜNDE dursun (parmak kartı kapatmasın):
      // tutma noktası kartın alt-orta noktasının [kSuruklemeYukariPay] altına alınır.
      dragAnchorStrategy: (draggable, ctx, position) =>
          Offset(_cardWidth / 2, _cardHeight + kSuruklemeYukariPay),
      // Bırakma hedefi parmağın değil, KARTIN göründüğü noktadan hesaplansın —
      // yoksa kart bir kategorinin üstündeyken parmak başka yerde olur.
      feedbackOffset: Offset(0, -(kSuruklemeYukariPay + _cardHeight / 2)),
      feedback: Material(
        color: Colors.transparent,
        child: Transform.scale(
          scale: 1.06,
          child: SizedBox(
            // Sürükleme "hayaleti" gerçek kartla aynı ölçüde.
            width: _cardWidth,
            child: _terimKarti(kart, faded: false, dragging: true, grupAdet: grupAdet),
          ),
        ),
      ),
      childWhenDragging: Padding(
        padding: const EdgeInsets.symmetric(vertical: kDokunmaPayi / 2),
        child: _terimKarti(kart, faded: true, grupAdet: grupAdet),
      ),
      onDragStarted: () => context.read<SoundService>().click(),
      child: GestureDetector(
        // Şeffaf dokunma payı da dâhil tüm alan hit-test'e dâhil olsun.
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: kDokunmaPayi / 2),
          child: _terimKarti(kart,
              faded: false, flash: flashing, hover: hovering, grupAdet: grupAdet),
        ),
      ),
    );

    return DragTarget<int>(
      hitTestBehavior: HitTestBehavior.opaque,
      onWillAcceptWithDetails: (details) {
        // Kendine bırakma yok; sadece başka sütunun açık kartını kabul et.
        if (details.data == sutunIndex) return false;
        if (_hoverSutun != sutunIndex) setState(() => _hoverSutun = sutunIndex);
        return true;
      },
      onLeave: (_) {
        if (_hoverSutun == sutunIndex) setState(() => _hoverSutun = null);
      },
      onAcceptWithDetails: (details) => _onStackDrop(details.data, sutunIndex),
      builder: (context, candidate, rejected) => draggable,
    );
  }

  Widget _terimKarti(
    TerimKart kart, {
    required bool faded,
    bool dragging = false,
    bool flash = false,
    bool hover = false,
    int grupAdet = 1,
  }) {
    // Kenarlık önceliği: yanlış yığma flaşı (kırmızı) > yığma hover (yeşil) >
    // sürükleme (yeşil) > varsayılan.
    Color borderColor = const Color(0xFFCBB07A);
    double borderW = 1;
    if (flash) {
      borderColor = const Color(0xFFE23B3B);
      borderW = 2.4;
    } else if (hover || dragging) {
      borderColor = const Color(0xFF2ECC71);
      borderW = dragging ? 2 : 2.6;
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          height: _cardHeight,
          padding: EdgeInsets.all((_cardHeight * 0.06).clamp(3.0, 8.0)),
          decoration: BoxDecoration(
            color: faded
                ? _cardCream.withValues(alpha: 0.3)
                : (flash ? const Color(0xFFF6D9D5) : _cardCream),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: borderColor, width: borderW),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dragging ? 0.35 : 0.22),
                blurRadius: dragging ? 10 : 5,
                offset: Offset(0, dragging ? 5 : 2),
              )
            ],
          ),
          child: Center(
            child: Text(
              kart.terim,
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                // Yazı boyu da kart yüksekliğinden türetilir (sabit piksel yok).
                fontSize: (_cardHeight * 0.115).clamp(7.0, 13.0),
                height: 1.12,
                fontWeight: FontWeight.w900,
                color: faded ? _cardInk.withValues(alpha: 0.4) : _cardInk,
              ),
            ),
          ),
        ),
        // Yığın rozeti: bu sütunda kaç açık kart üst üste (×N).
        // IgnorePointer — rozet, kartın dokunma alanını engellemesin.
        if (grupAdet > 1 && !faded)
          Positioned(
            top: -6,
            right: -4,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFF148A4F),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: Colors.white, width: 1),
                ),
                child: Text('×$grupAdet',
                    style: const TextStyle(
                        fontSize: 9, fontWeight: FontWeight.w900, color: Colors.white)),
              ),
            ),
          ),
      ],
    );
  }
}

/// Küçük yeşil bölüm başlığı.
class _BolumBasligi extends StatelessWidget {
  final String text;
  const _BolumBasligi(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w900,
        color: Colors.white.withValues(alpha: 0.92),
        letterSpacing: 0.2,
      ),
    );
  }
}

/// "Hamle N" bayrağı için sağ kenarı içe çentikli (flama) şekil.
class _FlamaClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    const notch = 9.0;
    final p = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width - notch, size.height / 2)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    return p;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// Kapalı kart sırtı — mavi zemin üzerine basit baklava (diamond) deseni.
class _CardBackPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = _backBlue;
    canvas.drawRect(Offset.zero & size, bg);

    // Diyagonal baklava dilimi ağı.
    final line = Paint()
      ..color = _backBlueDark
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    const step = 8.0;
    for (double x = -size.height; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), line);
      canvas.drawLine(Offset(x + size.height, 0), Offset(x, size.height), line);
    }
    // İnce açık kenar.
    final edge = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawRect(Offset.zero & size, edge);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
