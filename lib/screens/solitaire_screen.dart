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
      appBar: AppBar(title: const Text('🃏 Eşleştirme Solitaire')),
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
              'Açık bir terim kartını (ör. "Dik Açı") BASILI TUTUP üstteki doğru '
              'kategoriye (ör. "Açı Türleri") SÜRÜKLE. Aynı kategoriden iki açık '
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
            desc: '3 hedef kategori — daha az kart, ısınma turu.',
            kategoriSayisi: 3,
          ),
          _ZorlukKarti(
            title: '🟡 Orta',
            desc: '4 hedef kategori — dengeli bir seviye.',
            kategoriSayisi: 4,
          ),
          _ZorlukKarti(
            title: '🔴 Zor',
            desc: '5 hedef kategori — dolu bir tableau.',
            kategoriSayisi: 5,
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

class _EslestirmePlayScreenState extends State<_EslestirmePlayScreen> {
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

  /// Açık terim kartının o anki (ölçülen sütun genişliğinden türetilmiş)
  /// yüksekliği — bkz. [kTerimKartOrani]. [_buildBoard] içindeki
  /// [LayoutBuilder] her build'de gerçek sütun genişliğini ölçüp bunu
  /// günceller; böylece kart her zaman iskambil oranını korur.
  double _cardHeight = 82.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
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
    final secilen = pool.take(widget.kategoriSayisi.clamp(3, kKategoriGruplari.length)).toList();
    _engine.startLevel(secilen);
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
        title: const Text('🃏 Eşleştirme Solitaire'),
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── Üst çubuk: ders rozeti + coin · Kalan hamle · çekme destesi ──
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
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
                  const Spacer(),
                  _hamleBayragi(),
                  const Spacer(),
                  _buildCekDeste(),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Hedef kategori kartları (DragTarget) ──
                    const _BolumBasligi('🎯 Hedef Kategoriler'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final h in _engine.hedefler) _buildKategori(h),
                        // Kilitli/dekoratif boş slotlar (referans görsel).
                        for (var k = 0; k < (kSutunSayisi - _engine.hedefler.length).clamp(0, kSutunSayisi); k++)
                          _kilitliSlot(),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // ── Tableau sütunları (Draggable açık kartlar) ──
                    const _BolumBasligi('🂠 Kartlar — açık kartı tutup kategoriye sürükle'),
                    const SizedBox(height: 10),
                    // Sütunların GERÇEK genişliğini ölçüp kart yüksekliğini buna göre
                    // türetiyoruz (bkz. [kTerimKartOrani]) — sabit bir yükseklik
                    // yerine, dar telefonlarda kart küçülür/geniş telefonlarda
                    // büyür, ama iskambil oranı ve 5 sütunluk yerleşim HER ZAMAN
                    // korunur (taşma/kırpılma olmaz).
                    LayoutBuilder(
                      builder: (context, constraints) {
                        const gapToplam = 6.0 * (kSutunSayisi - 1);
                        final sutunGenisligi = (constraints.maxWidth - gapToplam) / kSutunSayisi;
                        _cardHeight = sutunGenisligi / kTerimKartOrani;
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var i = 0; i < _engine.sutunlar.length; i++)
                              Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(right: i == _engine.sutunlar.length - 1 ? 0 : 6),
                                  child: _buildSutun(i),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ],
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

  // ── Kategori hedef kartı (DragTarget) ───────────────────────────────

  Widget _buildKategori(KategoriHedef h) {
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

    return DragTarget<int>(
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
          width: 150,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: borderW),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(done ? '👑' : '🎯', style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 6),
                  Text('${h.eslesen}/${h.hedef}',
                      style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          color: done ? const Color(0xFFB8860B) : _cardInk)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                h.kategoriAdi,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w800, height: 1.15, color: _cardInk),
              ),
              const SizedBox(height: 2),
              Text(h.ders,
                  style: TextStyle(fontSize: 9.5, color: _cardInk.withValues(alpha: 0.6))),
            ],
          ),
        );
      },
    );
  }

  /// Kilitli/dekoratif kategori slotu — koyu yeşil, yarı saydam, taç ikonlu.
  Widget _kilitliSlot() {
    return Container(
      width: 150,
      height: 64,
      decoration: BoxDecoration(
        color: _tableGreenDark.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: const Center(
        child: Text('👑', style: TextStyle(fontSize: 20, color: Colors.white38)),
      ),
    );
  }

  // ── Tableau sütunu ──────────────────────────────────────────────────

  Widget _buildSutun(int i) {
    final c = _engine.sutunlar[i];
    if (c.isEmpty) {
      // Boş yuva — çekme destesi buraya kart koyabilir. Dolu sütunlarla hizalı
      // kalması için yükseklik terim kartıyla aynı ölçekten türetilir.
      return Container(
        height: _cardHeight + 10,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white38, width: 1.2),
          color: Colors.white.withValues(alpha: 0.05),
        ),
        child: const Center(child: Icon(Icons.add_rounded, color: Colors.white38, size: 20)),
      );
    }

    // Sondaki açık grup (yığma ile 1'den fazla olabilir); geri kalanı kapalı.
    final grup = _engine.acikGrup(i);
    final acikAdet = grup.isEmpty ? 0 : grup.length;
    final kapaliAdet = c.length - acikAdet;
    final kapaliGorunur = min(kapaliAdet, 4);

    const kapaliOffset = 10.0;
    const grupOffset = 16.0; // yığındaki alt kartların görünen "peek" payı
    final acikYukseklik = _cardHeight; // iskambil oranından türetilmiş (bkz. LayoutBuilder)
    final base = kapaliGorunur * kapaliOffset;
    final grupYuksek = acikAdet <= 1 ? 0.0 : (acikAdet - 1) * grupOffset;
    final toplamYukseklik = base + grupYuksek + acikYukseklik;

    return SizedBox(
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
              child: _kapaliKart(),
            ),
          // Fazla gizli kapalı kart sayacı.
          if (kapaliAdet > kapaliGorunur)
            Positioned(
              top: 0,
              right: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: _backBlueDark,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white54, width: 0.8),
                ),
                child: Text('+$kapaliAdet',
                    style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w800)),
              ),
            ),
          // Yığındaki ALT açık kartlar (sadece görsel "peek").
          if (acikAdet > 1)
            for (var g = 0; g < acikAdet - 1; g++)
              Positioned(
                top: base + g * grupOffset,
                left: 0,
                right: 0,
                child: _terimKarti(grup[g], faded: false),
              ),
          // Açık grubun EN ÜST kartı — sürüklenebilir + yığma hedefi.
          if (acikAdet > 0)
            Positioned(
              top: base + grupYuksek,
              left: 0,
              right: 0,
              child: _buildAcikKart(i, grup.last, acikAdet),
            ),
        ],
      ),
    );
  }

  Widget _kapaliKart() {
    return Container(
      height: 22,
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
    // Basılı tutup sürükle: liste kaydırmasıyla çakışmayan LongPressDraggable
    // — ama gecikmeyi (varsayılan ~500ms) neredeyse sıfıra indirdik ki
    // dokunur dokunmaz sürükleme başlasın (uzun basmaya gerek kalmasın),
    // yine de hızlı bir dikey kaydırma (scroll) hâlâ kaydırma olarak
    // algılanır (parmak eşik mesafesinden fazla hareket ederse long-press
    // iptal olur ve ScrollView jesti kazanır).
    final draggable = LongPressDraggable<int>(
      data: sutunIndex,
      delay: const Duration(milliseconds: 60),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        color: Colors.transparent,
        child: Transform.scale(
          scale: 1.06,
          child: SizedBox(
            // Sürükleme "hayaleti" de gerçek kart oranıyla (kTerimKartOrani)
            // eşleşsin diye genişlik, o anki kart yüksekliğinden türetilir.
            width: _cardHeight * kTerimKartOrani,
            child: _terimKarti(kart, faded: false, dragging: true, grupAdet: grupAdet),
          ),
        ),
      ),
      childWhenDragging: _terimKarti(kart, faded: true, grupAdet: grupAdet),
      onDragStarted: () => context.read<SoundService>().click(),
      child: _terimKarti(kart, faded: false, flash: flashing, hover: hovering, grupAdet: grupAdet),
    );

    return DragTarget<int>(
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
          padding: const EdgeInsets.all(6),
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
                fontSize: 9.5,
                height: 1.12,
                fontWeight: FontWeight.w900,
                color: faded ? _cardInk.withValues(alpha: 0.4) : _cardInk,
              ),
            ),
          ),
        ),
        // Yığın rozeti: bu sütunda kaç açık kart üst üste (×N).
        if (grupAdet > 1 && !faded)
          Positioned(
            top: -6,
            right: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFF148A4F),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: Colors.white, width: 1),
              ),
              child: Text('×$grupAdet',
                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.white)),
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
