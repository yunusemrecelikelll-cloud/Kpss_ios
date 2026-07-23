import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/subject.dart';
import '../data/kategori_eslestirme_data.dart';
import '../games/solitaire_engine.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../theme/design_system.dart';
import '../theme/theme_provider.dart';
import 'tools_hub_screen.dart';

/// Günlük ücretsiz oynama hakkı, DİĞER TÜM OYUNLARLA ORTAK sabitten gelir
/// ([kFreeGameDailyLimit], bkz. tools_hub_screen.dart). Solitaire'e özel ayrı
/// bir sabit YOKTUR — aksi hâlde oyunlar listesindeki "Bugün N hak" ile oyun
/// içindeki "Bugünkü hak" birbirini tutmuyordu.
const String kSolitaireGameId = 'solitaire';

// ── Oyun-içi coin ekonomisi (kozmetik; gerçek para DEĞİL) ──
// Denge SADE tutuldu: her DOĞRU EŞLEŞTİRME 1 coin. Zorluk çarpanı YOK — Kolay,
// Orta ve Zor modda kart başına kazanç aynıdır (Zor modda daha çok kart olduğu
// için toplam kazanç doğal olarak artar). Market'teki HER ürün 10 coin, yani
// 10 doğru eşleştirme = 1 ürün.
const int kCoinPerKart = 1; // doğru eşleşen kart başına
const int kMarketFiyat = 10; // market'teki TÜM ürünlerin ortak fiyatı
const int kEkHamleAdet = 5; // "5 Ek Hamle" ürününün verdiği hamle

// ── "Oyun masası" sabit paleti ──
// Oyun TAHTASI, uygulamanın genel light/dark temasından BAĞIMSIZ, kendine özgü
// bir kumar-masası kimliği taşır (referans görseldeki yeşil keçe) ve öyle
// KALIR. Menü, market, diyaloglar ve oyun sonu ekranları ise tasarım sistemine
// (design_system.dart) ve ThemeProvider token'larına bağlıdır.
const Color _tableGreen = Color(0xFF0F6B3E); // ana keçe yeşili
const Color _tableGreenDark = Color(0xFF0A4E2C); // koyu ton (app bar / kilitli slot)
const Color _feltGreen = Color(0xFF148A4F); // açık keçe (vurgu)
const Color _cardCream = Color(0xFFFAF3E4); // terim/kategori kart zemini
const Color _cardInk = Color(0xFF2A1D10); // kart yazısı (koyu kahve/siyah)
const Color _goldTrim = Color(0xFFF5B942); // altın kenarlık
const Color _backBlue = Color(0xFF1E5FA8); // kapalı kart sırtı
const Color _backBlueDark = Color(0xFF16457A);
const Color _hedefKartMor = Color(0xFF6C4AB6); // desteden çıkan HEDEF kartı vurgusu

// ── Terim kartı boyut oranı ──
// Standart iskambil kartı en-boy oranı ~2.5:3.5 (genişlik:yükseklik ≈ 0.714).
// Kart yüksekliği SABİT bir sayı DEĞİL; her build'de tahtanın o anki gerçek
// sütun genişliğinden türetilir — böylece ekran ne olursa olsun kart iskambil
// oranını korur ve taşma/kırpılma yaşanmaz.
const double kTerimKartOrani = 2.5 / 3.5; // genişlik / yükseklik

// ── Yerleşim sabitleri ──
/// Kartlar arası yatay/dikey boşluk.
const double kKartBosluk = 6.0;

/// Hedef kategori slotları tek sırada, tableau sütunlarıyla AYNI genişlik
/// biriminden dizilir → hedef kartları normal kartlarla birebir aynı boyutta.
const int kHedefSatirKapasite = kHedefSlotSayisi;

/// Üst çubuk (rozetler + deste) bu yüksekliğin altına inmez.
const double kUstCubukMinYukseklik = 58.0;

/// Sürüklenen kart, parmağın dokunduğu noktanın BU KADAR üstünde durur —
/// böylece parmak kartı kapatmaz. Bırakma hedefi de (feedbackOffset ile) aynı
/// miktarda yukarı taşınır, yani "kartın gördüğü yer" ile "bırakılan yer" aynıdır.
const double kSuruklemeYukariPay = 66.0;

/// Dokunma (hit-test) alanı, görsel karttan bu kadar BÜYÜK tutulur — kartı
/// ilk dokunuşta yakalayabilmek için.
const double kDokunmaPayi = 14.0;

/// Sürükleme yükü: bir tableau kartı/yığını ya da desteden çekilen kart.
class _Suruklenen {
  /// Kaynak tableau sütunu — negatifse kart DESTEDEN (çekilen yuvasından) gelir.
  final int sutun;

  /// Sütundaki başlangıç indeksi; bu karttan İTİBAREN üstündekiler taşınır.
  final int index;

  /// Desteden çekilen kart bir HEDEF KATEGORİ kartı mı?
  final bool hedefKarti;

  const _Suruklenen.tableau(this.sutun, this.index) : hedefKarti = false;
  const _Suruklenen.deste({required this.hedefKarti})
      : sutun = -1,
        index = 0;

  bool get destedenMi => sutun < 0;
}

/// Kategori Eşleştirme Solitaire.
///
/// Klasik iskambil solitaire DEĞİL: KPSS terim kartlarını (İsim, Dik Açı,
/// Göktürkler, Marmara...) doğru KATEGORİYE (Sözcük Türleri, Açı Türleri, İlk
/// Türk Devletleri, Türkiye'nin Bölgeleri...) eşleştirme oyunu.
///
/// Dış API KORUNUR: `SolitaireScreen(subjects: subjects)` — tools_hub_screen
/// bu şekilde çağırır.
class SolitaireScreen extends StatelessWidget {
  final List<Subject> subjects;
  const SolitaireScreen({super.key, required this.subjects});

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final c = context.watch<ThemeProvider>().colors;
    final premium = storage.isPremiumUser();
    final gp = storage.getGamePlayState(kSolitaireGameId);
    final left = (kFreeGameDailyLimit - (gp['plays'] as int)).clamp(0, kFreeGameDailyLimit);
    final coins = storage.getSolitaireCoins();

    return Scaffold(
      appBar: AppBar(title: const Text('🃏 Eşleştirme Solitaire')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Tanıtım kartı — tasarım sistemi yüzeyi (tema token'larıyla).
            DsCard(
              accent: c.violet,
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      DsIconBadge(emoji: '🃏', color: c.violet),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Terim kartlarını doğru kategoriye eşleştir',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w900, color: c.text),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Açık bir terim kartını TUTUP doğru hedef kategorinin üstüne '
                    'SÜRÜKLE. Aynı kategoriden kartları tableau\'da üst üste '
                    'YIĞABİLİR, bir yığının ortasındaki karta basıp üstündeki tüm '
                    'kartları birlikte taşıyabilirsin. Sağ üstteki desteden hem '
                    'terim hem de YENİ HEDEF KATEGORİ kartı çıkar; tamamlanan '
                    'kategori tahtadan kalkar, boşalan slota yeni hedef koyarsın. '
                    'Her doğru eşleştirme 🪙 1 coin kazandırır — ama hamle hakkın '
                    'SINIRLI!',
                    style: TextStyle(fontSize: 12.5, height: 1.5, color: c.textDim),
                  ),
                ],
              ),
            ),
            const SizedBox(height: kDsGap),
            DsStatStrip(
              items: [
                DsStatItem(
                  visual: DsIconBadge(emoji: '🪙', color: c.gold, size: 44),
                  value: '$coins',
                  label: 'Coin',
                ),
                DsStatItem(
                  visual: DsIconBadge(emoji: '🎟️', color: c.mint, size: 44),
                  value: premium ? '∞' : '$left',
                  label: 'Bugünkü hak',
                  sublabel: premium ? 'Premium' : 'Günlük $kFreeGameDailyLimit',
                ),
                DsStatItem(
                  visual: DsIconBadge(emoji: '🛒', color: c.rose, size: 44),
                  value: '$kMarketFiyat',
                  label: 'Market fiyatı',
                  sublabel: 'Her ürün',
                ),
              ],
            ),
            const SizedBox(height: kDsGap),
            const DsSectionHeader(title: 'Zorluk Seç'),
            const SizedBox(height: 4),
            _ZorlukKarti(
              emoji: '🟢',
              title: 'Kolay',
              desc: '5 hedef kategori — ısınma turu.',
              accent: c.mint,
              kategoriSayisi: 5,
            ),
            const SizedBox(height: kDsGap),
            _ZorlukKarti(
              emoji: '🟡',
              title: 'Orta',
              desc: '5 hedefle başlar, desteden gelen yeni hedeflerle 10 kategoriye çıkar.',
              accent: c.gold,
              kategoriSayisi: 10,
            ),
            const SizedBox(height: kDsGap),
            _ZorlukKarti(
              emoji: '🔴',
              title: 'Zor',
              desc: '5 hedefle başlar, toplam 20 kategoriye uzanan maraton.',
              accent: c.rose,
              kategoriSayisi: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _ZorlukKarti extends StatelessWidget {
  final String emoji;
  final String title;
  final String desc;
  final Color accent;
  final int kategoriSayisi;
  const _ZorlukKarti({
    required this.emoji,
    required this.title,
    required this.desc,
    required this.accent,
    required this.kategoriSayisi,
  });

  @override
  Widget build(BuildContext context) {
    return DsListRow(
      title: title,
      status: desc,
      emoji: emoji,
      accent: accent,
      onTap: () {
        context.read<SoundService>().click();
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => _EslestirmePlayScreen(kategoriSayisi: kategoriSayisi)),
        );
      },
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

  /// Yanlış taşıma denemesinde kısa süre kırmızı yakılan sütun.
  int? _flashSutun;

  /// Yanlış bırakılan BOŞ hedef slotu.
  int? _flashSlot;

  /// Sürüklenen kartın o an üzerinde olduğu (hover) kategori — kenarlık vurgusu.
  String? _hoverKategori;

  /// Sürüklenen kartın o an üzerinde olduğu (hover) tableau sütunu.
  int? _hoverSutun;

  /// Sürüklenen HEDEF kartının üzerinde olduğu boş slot.
  int? _hoverSlot;

  /// ŞU AN sürüklenen tableau yığınının kaynağı. Sürükleme TEK bir kartın
  /// değil, o karttan itibaren ÜSTÜNDEKİ TÜM kartların işidir; bu yüzden
  /// durum kartın kendi widget'ında değil, EKRAN düzeyinde tutulur — yoksa
  /// yalnızca basılan kart soluklaşır, üstündekiler yerinde durur ve yığın
  /// taşınmıyormuş gibi görünür.
  int? _dragSutun;
  int? _dragIndex;

  /// [sutun]/[index] kartı, o an sürüklenen yığının parçası mı?
  bool _surukleniyor(int sutun, int index) =>
      _dragSutun == sutun && _dragIndex != null && index >= _dragIndex!;

  /// Yığındaki alt kartların görünen şerit yüksekliği. Hem tableau yerleşimi
  /// hem de sürükleme feedback'i AYNI adımı kullanır.
  double get _grupAdim => _cardHeight * 0.24;

  /// Kart ölçüleri — hedef kategori kartları, tableau terim kartları VE sağ
  /// üstteki deste/çekilen kart bu AYNI ölçüyü kullanır. [_buildBoard]
  /// içindeki [LayoutBuilder] her build'de kullanılabilir genişlik VE
  /// yüksekliği ölçüp bunları günceller.
  double _cardHeight = 82.0;
  double _cardWidth = 82.0 * kTerimKartOrani;

  /// Hedef slot sırasının o anki toplam yüksekliği — dağıtım animasyonunda
  /// tableau kartlarının başlangıç konumunu hesaplamak için.
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
      if ((gp['plays'] as int) >= kFreeGameDailyLimit + storage.getExtraPlays(kSolitaireGameId)) {
        if (!mounted) return;
        setState(() => _locked = true);
        return;
      }
      await storage.useGamePlay(kSolitaireGameId);
    }
    if (!mounted) return;

    final pool = List<KategoriGrubu>.from(kKategoriGruplari)..shuffle(Random());
    // Kategori sayısı artık ızgara kapasitesiyle SINIRLI DEĞİL: tahtada aynı
    // anda [kHedefSlotSayisi] hedef durur, kalanlar desteden gelir.
    final int adet =
        widget.kategoriSayisi < pool.length ? widget.kategoriSayisi : pool.length;
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
      _flashSlot = null;
      _hoverKategori = null;
      _hoverSutun = null;
      _hoverSlot = null;
      _dragSutun = null;
      _dragIndex = null;
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

  /// Başarılı bir eşleştirme sonrası ortak akış: coin ver, bitiş/kayıp kontrolü.
  Future<void> _eslesmeSonrasi() async {
    context.read<SoundService>().click();
    await _coinEkle(_engine.sonEslesenAdet * kCoinPerKart);
    if (!mounted) return;
    if (_engine.seviyeTamamlandi) {
      setState(() => _finished = true);
    } else if (_engine.kaybedildi) {
      setState(() => _lost = true);
    } else {
      setState(() {});
    }
  }

  // ── Bırakma (drop) işleyicileri ─────────────────────────────────────

  /// Bir kartın/yığının HEDEF KATEGORİ kartına bırakılması.
  Future<void> _onKategoriDrop(_Suruklenen d, KategoriHedef h) async {
    // Sürükleme durumu HEMEN temizlenir: tahta değiştiği an eski sütun/indeks
    // bilgisiyle yanlış kartlar soluk görünmesin.
    setState(() {
      _hoverKategori = null;
      _dragSutun = null;
      _dragIndex = null;
    });
    if (d.destedenMi && d.hedefKarti) {
      // Hedef kategori kartı bir kategoriye bırakılamaz.
      _flashWrong(h.kategoriAdi);
      return;
    }
    final ok = d.destedenMi
        ? _engine.cekilenEslestir(h.kategoriAdi)
        : _engine.eslestir(d.sutun, d.index, h.kategoriAdi);
    if (ok) {
      await _eslesmeSonrasi();
    } else {
      _flashWrong(h.kategoriAdi);
      if (_engine.kaybedildi) {
        setState(() => _lost = true);
      } else {
        setState(() {});
      }
    }
  }

  /// Bir kartın/yığının TABLEAU sütununa bırakılması (yığma ya da boş sütuna
  /// taşıma).
  void _onSutunDrop(_Suruklenen d, int hedefSutun) {
    setState(() {
      _hoverSutun = null;
      _dragSutun = null;
      _dragIndex = null;
    });
    if (d.destedenMi && d.hedefKarti) {
      _flashWrongSutun(hedefSutun);
      return;
    }
    if (!d.destedenMi && d.sutun == hedefSutun) return;
    final ok = d.destedenMi
        ? _engine.cekilenSutunaKoy(hedefSutun)
        : _engine.tasi(d.sutun, d.index, hedefSutun);
    if (ok) {
      context.read<SoundService>().click();
      setState(() {});
    } else {
      _flashWrongSutun(hedefSutun);
    }
    // Taşıma da (doğru/yanlış) bir hamle harcadığından bütçe bitmiş olabilir.
    if (_engine.kaybedildi) setState(() => _lost = true);
  }

  /// Desteden çekilen HEDEF KATEGORİ kartının BOŞ slota bırakılması.
  void _onSlotDrop(_Suruklenen d, int slotIndex) {
    setState(() {
      _hoverSlot = null;
      _dragSutun = null;
      _dragIndex = null;
    });
    if (!d.destedenMi || !d.hedefKarti) {
      // Boş slota normal kart konamaz — yalnızca yeni hedef kategori.
      _flashWrongSlot(slotIndex);
      return;
    }
    final ok = _engine.cekilenHedefiYerlestir(slotIndex);
    if (ok) {
      context.read<SoundService>().click();
      setState(() {});
    } else {
      _flashWrongSlot(slotIndex);
    }
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

  void _flashWrongSlot(int slot) {
    setState(() => _flashSlot = slot);
    Future.delayed(const Duration(milliseconds: 550), () {
      if (mounted && _flashSlot == slot) setState(() => _flashSlot = null);
    });
  }

  void _onCekDeste() {
    if (!_engine.cekilebilir) return;
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

  /// Coin harcayarak yardımcı satın alınan MARKET. Yüzey tasarım sistemine ve
  /// tema token'larına bağlıdır (oyun tahtasının sabit yeşili DEĞİL).
  void _openMarket() {
    context.read<SoundService>().click();
    final c = context.read<ThemeProvider>().colors;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.bg2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(kDsRadius)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheet) {
            final sc = sheetCtx.watch<ThemeProvider>().colors;

            // Bir satın alma işler: coin düşer, etkiyi uygular, iki tarafı da tazeler.
            Future<void> satinAl(String basari, void Function() etki) async {
              final sheetNav = Navigator.of(sheetCtx); // async gap öncesi yakala
              final ok = await context.read<StorageService>().spendSolitaireCoins(kMarketFiyat);
              if (!ok) return; // yetersiz (buton zaten pasif olmalı)
              etki();
              if (!mounted) return;
              _coins = context.read<StorageService>().getSolitaireCoins();
              context.read<SoundService>().click();
              // Joker seviyeyi bitirmiş olabilir → sheet'i kapat, sonucu göster.
              if (_engine.seviyeTamamlandi && !_finished) {
                await _coinEkle(_engine.sonEslesenAdet * kCoinPerKart);
                if (!mounted) return;
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

            final yeterli = _coins >= kMarketFiyat;

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('🛒 Market',
                              style: TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w900, color: sc.text)),
                        ),
                        DsChip(label: '🪙 $_coins', color: sc.gold),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Her ürün $kMarketFiyat coin. Coinini doğru eşleştirmelerle kazanırsın '
                      '(her doğru eşleştirme 1 coin).',
                      style: TextStyle(fontSize: 12, color: sc.textFaint),
                    ),
                    const SizedBox(height: 14),
                    _marketSatir(
                      emoji: '💡',
                      baslik: '+1 İpucu Hakkı',
                      accent: sc.gold,
                      yeterli: yeterli,
                      onAl: () => satinAl('💡 +1 ipucu hakkı eklendi.',
                          () => _engine.satinAlinanIpucu()),
                    ),
                    const SizedBox(height: kDsGap),
                    _marketSatir(
                      emoji: '↩️',
                      baslik: '+1 Geri Al Hakkı',
                      accent: sc.violetL,
                      yeterli: yeterli,
                      onAl: () => satinAl('↩️ +1 geri al hakkı eklendi.',
                          () => _engine.satinAlinanGeriAl()),
                    ),
                    const SizedBox(height: kDsGap),
                    _marketSatir(
                      emoji: '⏱️',
                      baslik: '$kEkHamleAdet Ek Hamle',
                      accent: sc.mint,
                      yeterli: yeterli,
                      onAl: () => satinAl('⏱️ +$kEkHamleAdet hamle eklendi.',
                          () => _engine.hamleEkle(kEkHamleAdet)),
                    ),
                    const SizedBox(height: kDsGap),
                    _marketSatir(
                      emoji: '🃏',
                      baslik: 'Joker — bir kartı otomatik yerleştir',
                      accent: sc.rose,
                      yeterli: yeterli && _engine.jokerUygun,
                      onAl: () => satinAl('🃏 Joker bir kartı doğru kategoriye yerleştirdi!',
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
      return LockedFeatureCard(
        gameId: kSolitaireGameId,
        oyunAdi: 'Eşleştirme Solitaire',
        onUnlocked: () => setState(() => _locked = false),

        title: 'Eşleştirme Solitaire',
        desc: "Bugünkü $kFreeGameDailyLimit ücretsiz oyun hakkını kullandın. "
            "Yarın tekrar oyna ya da Premium'a geçip sınırsız oyna.",
      );
    }
    if (!_booted) {
      return const Scaffold(
        backgroundColor: _tableGreen,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }
    if (_finished) return _buildSonuc(context, kazandi: true);
    if (_lost) return _buildSonuc(context, kazandi: false);
    return _buildBoard(context);
  }

  // ── Oyun sonu ekranı (tasarım sistemi + tema token'ları) ────────────

  /// Kazanma ve kaybetme ekranı — uygulamanın geri kalanıyla AYNI tasarım
  /// dilinde: [DsCard], [DsIllustration], [DsStatStrip], [DsChip],
  /// [DsPillButton] ve ThemeProvider renkleri.
  Widget _buildSonuc(BuildContext context, {required bool kazandi}) {
    final c = context.watch<ThemeProvider>().colors;
    final vurgu = kazandi ? c.mint : c.rose;
    final kurtarilabilir = !kazandi && _coins >= kMarketFiyat;

    return Scaffold(
      appBar: AppBar(title: const Text('🃏 Eşleştirme Solitaire')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DsCard(
              accent: vurgu,
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  DsIllustration(
                    emoji: kazandi ? '🏆' : '💥',
                    size: 92,
                    glowColor: kazandi ? c.gold : vurgu,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    kazandi ? 'Seviye tamamlandı!' : 'Hamle hakkın bitti!',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: c.text),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    kazandi
                        ? '${_engine.toplamKategori} kategorinin ${_engine.toplamTerim} teriminin '
                            'tamamını doğru yere yerleştirdin.'
                        : '${_engine.hamleButcesi} hamlelik bütçen doldu ama hâlâ '
                            '${_engine.kalanTerim} kart tamamlanmadı.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, height: 1.5, color: c.textDim),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    alignment: WrapAlignment.center,
                    children: [
                      DsChip(label: '🪙 BAKİYE $_coins', color: c.gold),
                      DsChip(label: '🎯 ${_engine.tamamlananlar.length} KATEGORİ', color: vurgu),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: kDsGap),
            const DsSectionHeader(title: 'Tur Özeti'),
            const SizedBox(height: 4),
            DsStatStrip(
              items: [
                DsStatItem(
                  visual: DsIconBadge(emoji: '🪙', color: c.gold, size: 44),
                  value: '+$_kazanilanCoin',
                  label: 'Kazanılan coin',
                  sublabel: 'Eşleştirme başına 1',
                ),
                DsStatItem(
                  visual: DsIconBadge(emoji: '🎴', color: c.violetL, size: 44),
                  value: '${_engine.toplamTerim - _engine.kalanTerim}/${_engine.toplamTerim}',
                  label: 'Eşleşen kart',
                ),
                DsStatItem(
                  visual: DsIconBadge(emoji: '♟️', color: c.mint, size: 44),
                  value: '${_engine.hamle}/${_engine.hamleButcesi}',
                  label: 'Hamle',
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (kurtarilabilir) ...[
              Align(
                alignment: Alignment.center,
                child: DsPillButton(
                  label: '🪙 $kMarketFiyat coin → +$kEkHamleAdet Hamle',
                  onPressed: _onKurtar,
                  color: c.gold,
                  leadingIcon: Icons.play_arrow_rounded,
                ),
              ),
              const SizedBox(height: 10),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                DsPillButton(
                  label: 'Tekrar Oyna',
                  onPressed: () {
                    context.read<SoundService>().click();
                    _retry();
                  },
                  color: vurgu,
                  leadingIcon: Icons.refresh_rounded,
                ),
                const SizedBox(width: 10),
                DsPillButton(
                  label: 'Menüye Dön',
                  onPressed: () {
                    context.read<SoundService>().click();
                    Navigator.of(context).pop();
                  },
                  color: c.violetL,
                  filled: false,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Kayıp ekranında coin harcayarak hamle satın alıp oyuna devam eder.
  Future<void> _onKurtar() async {
    context.read<SoundService>().click();
    final ok = await context.read<StorageService>().spendSolitaireCoins(kMarketFiyat);
    if (!ok || !mounted) return;
    _coins = context.read<StorageService>().getSolitaireCoins();
    _engine.hamleEkle(kEkHamleAdet);
    setState(() => _lost = false); // bütçe arttı → oyuna geri dön
  }

  // ── Oyun tahtası ────────────────────────────────────────────────────

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
            // Üst çubuk + tahta TEK bir LayoutBuilder ile ölçülür: kullanılabilir
            // genişlik VE yükseklikten kart boyutu türetilir. Böylece sağ üstteki
            // deste/çekilen kart da tam olarak diğer kartlarla AYNI boyutta olur
            // ve hiçbir yerde taşma oluşmaz (sabit piksel yok).
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const yatayPad = 12.0;
                  final W = constraints.maxWidth;
                  final H = constraints.maxHeight;
                  final tahtaGenislik = W - yatayPad * 2;

                  // Tableau: 5 sütun + aralarındaki boşluklar (0.5 px yuvarlama
                  // güvenlik payıyla — hairline taşma olmasın).
                  final sutunGenisligi =
                      (tahtaGenislik - 0.5 - kKartBosluk * (kSutunSayisi - 1)) / kSutunSayisi;
                  final idealYukseklik = sutunGenisligi / kTerimKartOrani;

                  // Hedef slotları tek sıra (5 slot) — kapasiteye göre hesaplanır.
                  var satirSayisi = (kHedefSlotSayisi / kHedefSatirKapasite).ceil();
                  if (satirSayisi < 1) satirSayisi = 1;

                  // Cihazın yazı ölçeği büyükse başlıklar da büyür → pay onunla
                  // birlikte artar (aksi hâlde Column taşardı).
                  final baslikOlcek =
                      (MediaQuery.textScalerOf(context).scale(12.5) / 12.5).clamp(1.0, 2.0);
                  final basliklarYukseklik = 20.0 + 36.0 * baslikOlcek;
                  const ustCubukPay = 12.0; // üst çubuğun dikey iç boşluğu
                  const tahtaDikeyPay = 12.0; // tahta alanının dikey iç boşluğu
                  const bolumlerArasi = 8.0;
                  // Tableau'nun en az bu kadar kart yüksekliğine yeri olmalı.
                  const tableauPayCarpani = 2.2;

                  final sabitPay = ustCubukPay +
                      tahtaDikeyPay +
                      basliklarYukseklik +
                      bolumlerArasi +
                      (satirSayisi - 1) * kKartBosluk;
                  final kartlaraKalan = H - sabitPay;
                  // Dikey kart bütçesi: üst çubuk destesi (1) + hedef sıraları +
                  // tableau payı.
                  final gerekliKart = idealYukseklik * (satirSayisi + tableauPayCarpani + 1.0);
                  var olcek = (kartlaraKalan <= 0 || gerekliKart <= kartlaraKalan)
                      ? 1.0
                      : (kartlaraKalan / gerekliKart);
                  olcek = olcek.clamp(0.30, 1.0);

                  _cardHeight = idealYukseklik * olcek;
                  _cardWidth = _cardHeight * kTerimKartOrani;
                  _hedefAlanYukseklik =
                      satirSayisi * _cardHeight + (satirSayisi - 1) * kKartBosluk;
                  final ustCubukYuk = max(_cardHeight, kUstCubukMinYukseklik);

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Üst çubuk: ders rozeti + coin · Kalan hamle · deste ──
                      Padding(
                        padding: const EdgeInsets.fromLTRB(yatayPad, 8, yatayPad, 4),
                        child: SizedBox(
                          height: ustCubukYuk,
                          child: Row(
                            children: [
                              // Rozetler dar/alçak çubukta otomatik küçülür.
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _dersRozeti(),
                                    const SizedBox(height: 5),
                                    _coinRozet(_coins),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Center(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _hamleBayragi(),
                                        const SizedBox(height: 4),
                                        // ANA KART SAYACI: her doğru eşleştirmede
                                        // düşen "kalan toplam kart".
                                        _kalanKartRozet(),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Çekme destesi HER ZAMAN sağ üst köşede; yanında
                              // çekilen kartın KENDİ yuvası vardır (hiçbir kartın
                              // üstüne binmez).
                              _buildDesteAlani(),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(yatayPad, 4, yatayPad, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // ── Hedef kategori slotları (DragTarget) ──
                              const _BolumBasligi('🎯 Hedef Kategoriler'),
                              const SizedBox(height: 6),
                              SizedBox(
                                height: _hedefAlanYukseklik,
                                width: double.infinity,
                                child: _buildHedefIzgara(tahtaGenislik, satirSayisi),
                              ),
                              const SizedBox(height: bolumlerArasi),
                              // ── Tableau sütunları (Draggable açık kartlar) ──
                              const _BolumBasligi('🂠 Kartlar — kartı tutup sürükle'),
                              const SizedBox(height: 6),
                              Expanded(
                                child: SingleChildScrollView(
                                  child: _buildTableau(tahtaGenislik),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            // ── Alt araç çubuğu: İpucu · Geri Al · Market ──
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
          Text(dersEmoji[ders] ?? '🎯', style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 6),
          Text(ders,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: _cardInk)),
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

  /// ANA KART SAYACI — henüz eşleşmemiş toplam kart. Her DOĞRU eşleştirmede
  /// (tek kart ya da yığın) anında düşer; sıfırlandığında seviye biter.
  Widget _kalanKartRozet() {
    final kalan = _engine.kalanTerim;
    final toplam = _engine.toplamTerim;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Colors.white38, width: 1),
      ),
      child: Text(
        '🎴 Kalan kart: $kalan/$toplam',
        maxLines: 1,
        overflow: TextOverflow.clip,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }

  /// Üstteki 🪙 coin göstergesi (krem rozet, altın kenarlık).
  Widget _coinRozet(int coins) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _cardCream,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _goldTrim, width: 1.4),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🪙', style: TextStyle(fontSize: 13)),
          const SizedBox(width: 6),
          Text('$coins',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: _cardInk)),
        ],
      ),
    );
  }

  /// Market satırı — tasarım sistemi kartı + hap buton (tema renkleriyle).
  Widget _marketSatir({
    required String emoji,
    required String baslik,
    required Color accent,
    required bool yeterli,
    required VoidCallback onAl,
  }) {
    return Builder(builder: (ctx) {
      final c = ctx.watch<ThemeProvider>().colors;
      return DsCard(
        accent: accent,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            DsIconBadge(emoji: emoji, color: accent, size: 42, circle: false, glow: false),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(baslik,
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w800, color: c.text)),
                  const SizedBox(height: 3),
                  Text('🪙 $kMarketFiyat coin',
                      style: TextStyle(
                          fontSize: 11.5, fontWeight: FontWeight.w700, color: c.textFaint)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            DsPillButton(
              label: 'Satın Al',
              onPressed: yeterli ? onAl : null,
              color: yeterli ? accent : c.textFaint,
            ),
          ],
        ),
      );
    });
  }

  // ── Çekme destesi + çekilen kart yuvası (sağ üst) ───────────────────

  /// Sağ üst köşe: kapalı çekme destesi ve HEMEN YANINDA çekilen kartın kendi
  /// yuvası. Çekilen kart bu yuvada durur — hiçbir zaman başka kartların
  /// üzerine binmez ve diğer oyun kartlarıyla AYNI boyuttadır. Terim kartı
  /// çıkarsa kategoriye/sütuna, hedef kartı çıkarsa BOŞ slota sürüklenir.
  Widget _buildDesteAlani() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildCekilenYuva(),
        const SizedBox(width: kKartBosluk),
        _buildCekDeste(),
      ],
    );
  }

  Widget _buildCekDeste() {
    // Destede DURAN kart sayısı — her çekişte 1 azalır. Sıfırlandığında, henüz
    // oynanmamış kartlar varsa deste yeniden dağıtılabilir ("Yeniden").
    final kalan = _engine.bekleyenSayisi;
    final aktif = _engine.cekilebilir;
    final etiket = kalan > 0 ? 'Çek' : (aktif ? 'Yeniden' : 'Bitti');

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: aktif ? _onCekDeste : null,
      child: Opacity(
        opacity: aktif ? 1 : 0.55,
        child: SizedBox(
          width: _cardWidth,
          height: _cardHeight,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: Colors.white70, width: 1.2),
              boxShadow: const [
                BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2))
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CustomPaint(
                painter: _CardBackPainter(),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('$kalan',
                            style: TextStyle(
                                fontSize: (_cardHeight * 0.17).clamp(10.0, 15.0),
                                fontWeight: FontWeight.w900,
                                color: Colors.white)),
                        // "Yeniden" gibi uzun etiket dar kartta taşmasın.
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(etiket,
                              maxLines: 1,
                              style: TextStyle(
                                  fontSize: (_cardHeight * 0.11).clamp(7.0, 10.0),
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Açılan yığının yuvası — boşsa soluk bir çerçeve, doluysa yığının EN
  /// ÜSTTEKİ kartı SÜRÜKLENEBİLİR olarak çizilir. Altındaki 1-2 kart birkaç
  /// piksel kaydırılmış kenarlarıyla görünür (yığın olduğu anlaşılsın) ama
  /// dokunmayı yakalamaz — sürükleme yalnızca üstteki karttan başlar.
  Widget _buildCekilenYuva() {
    final ck = _engine.cekilen;
    final yiginAdet = _engine.acilanSayisi;
    // Altta gösterilecek dekoratif kart sayısı (en fazla 2).
    final altAdet = (yiginAdet - 1).clamp(0, 2);
    // Kaydırma payı: kart yüksekliğine göre küçük bir offset.
    final kaydirma = (_cardHeight * 0.035).clamp(2.0, 5.0);

    if (ck == null) {
      return Container(
        width: _cardWidth,
        height: _cardHeight,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: Colors.white38, width: 1.2),
          color: Colors.white.withValues(alpha: 0.05),
        ),
        child: Center(
          child: Icon(Icons.touch_app_rounded,
              color: Colors.white38, size: (_cardHeight * 0.24).clamp(12.0, 22.0)),
        ),
      );
    }

    final hedefMi = ck.hedefMi;
    final gorsel = hedefMi
        ? _yeniHedefKarti(ck.hedef!)
        : _terimKarti(ck.terim!, faded: false);

    final ustKart = LongPressDraggable<_Suruklenen>(
      data: _Suruklenen.deste(hedefKarti: hedefMi),
      delay: const Duration(milliseconds: 25),
      hitTestBehavior: HitTestBehavior.opaque,
      dragAnchorStrategy: (draggable, ctx, position) =>
          Offset(_cardWidth / 2, _cardHeight + kSuruklemeYukariPay),
      feedbackOffset: Offset(0, -(kSuruklemeYukariPay + _cardHeight / 2)),
      feedback: Material(
        color: Colors.transparent,
        child: Transform.scale(
          scale: 1.06,
          child: SizedBox(
            width: _cardWidth,
            child: hedefMi
                ? _yeniHedefKarti(ck.hedef!, dragging: true)
                : _terimKarti(ck.terim!, faded: false, dragging: true),
          ),
        ),
      ),
      childWhenDragging: SizedBox(
        width: _cardWidth,
        child: hedefMi
            ? _yeniHedefKarti(ck.hedef!, faded: true)
            : _terimKarti(ck.terim!, faded: true),
      ),
      onDragStarted: () => context.read<SoundService>().click(),
      child: SizedBox(width: _cardWidth, child: gorsel),
    );

    // Yığında tek kart varsa eski görünüm aynen korunur.
    if (altAdet == 0) {
      return SizedBox(width: _cardWidth, height: _cardHeight, child: ustKart);
    }

    // Yığın görünümü: alttaki kartlar sola-yukarı doğru birkaç piksel kaydırılmış
    // sırtlarıyla görünür, üstteki kart tam boyutta ve yuvanın TAM yerinde durur.
    // Yuvanın ölçüsü (_cardWidth × _cardHeight) DEĞİŞMEZ; kaydırılan sırtlar
    // Clip.none ile dışarı taşar ama yer kaplamaz, böylece üst çubuk kaymaz.
    return SizedBox(
      width: _cardWidth,
      height: _cardHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Dekoratif alt kartlar — en alttaki en çok kaydırılmış olsun.
          for (var i = altAdet; i >= 1; i--)
            Positioned(
              left: -kaydirma * i,
              top: -kaydirma * i,
              child: IgnorePointer(
                child: Opacity(
                  opacity: 0.85,
                  child: SizedBox(
                    width: _cardWidth,
                    height: _cardHeight,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: Colors.white54, width: 1),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CustomPaint(painter: _CardBackPainter()),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          // Oynanabilir ÜST kart.
          Positioned.fill(child: ustKart),
          // Yığındaki kart sayısı rozeti ("×3").
          Positioned(
            right: 2,
            top: 2,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.62),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '×$yiginAdet',
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: (_cardHeight * 0.11).clamp(7.0, 11.0),
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Desteden çıkan YENİ HEDEF KATEGORİ kartı (mor vurgulu) — boş slota
  /// sürüklenerek tahtaya eklenir.
  Widget _yeniHedefKarti(KategoriHedef h, {bool dragging = false, bool faded = false}) {
    final adFont = (_cardHeight * 0.115).clamp(7.0, 12.0);
    final ustFont = (_cardHeight * 0.10).clamp(6.0, 10.0);
    final ic = (_cardHeight * 0.06).clamp(3.0, 8.0);
    return Container(
      height: _cardHeight,
      padding: EdgeInsets.all(ic),
      decoration: BoxDecoration(
        color: faded ? _cardCream.withValues(alpha: 0.3) : _cardCream,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: _hedefKartMor, width: dragging ? 2.6 : 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dragging ? 0.35 : 0.22),
            blurRadius: dragging ? 10 : 5,
            offset: Offset(0, dragging ? 5 : 2),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('🎯 YENİ HEDEF',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(
                  fontSize: ustFont,
                  fontWeight: FontWeight.w900,
                  color: _hedefKartMor)),
          Expanded(
            child: _KayanMetin(
              metin: h.kategoriAdi,
              hizalama: TextAlign.center,
              stil: TextStyle(
                fontSize: adFont,
                fontWeight: FontWeight.w900,
                height: 1.12,
                color: faded ? _cardInk.withValues(alpha: 0.4) : _cardInk,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Dağıtım animasyonu ──────────────────────────────────────────────

  /// Kartı, sağ üstteki çekme destesinden yerine "uçurarak" gösterir.
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

  // ── Hedef slot ızgarası ─────────────────────────────────────────────

  Widget _buildHedefIzgara(double tahtaGenislik, int satirSayisi) {
    final slotlar = _engine.slotlar;
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
                  if (s * kHedefSatirKapasite + k < slotlar.length) ...[
                    if (k > 0) const SizedBox(width: kKartBosluk),
                    Builder(builder: (_) {
                      final idx = s * kHedefSatirKapasite + k;
                      final konum = Offset(
                          k * (_cardWidth + kKartBosluk), s * (_cardHeight + kKartBosluk));
                      final h = slotlar[idx];
                      return h == null
                          ? _buildBosSlot(idx)
                          : _buildKategori(h, idx, konum, tahtaGenislik);
                    }),
                  ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// Tamamlanan kategori kalkınca boşalan slot. YALNIZCA desteden çekilen yeni
  /// bir HEDEF KATEGORİ kartını kabul eder — normal kart konamaz.
  Widget _buildBosSlot(int slotIndex) {
    final flashing = _flashSlot == slotIndex;
    final hovering = _hoverSlot == slotIndex;
    return DragTarget<_Suruklenen>(
      hitTestBehavior: HitTestBehavior.opaque,
      onWillAcceptWithDetails: (details) {
        if (_hoverSlot != slotIndex) setState(() => _hoverSlot = slotIndex);
        return true; // yanlış kart bırakılırsa kırmızı flaşla uyarılır
      },
      onLeave: (_) {
        if (_hoverSlot == slotIndex) setState(() => _hoverSlot = null);
      },
      onAcceptWithDetails: (details) => _onSlotDrop(details.data, slotIndex),
      builder: (context, candidate, rejected) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: _cardWidth,
          height: _cardHeight,
          padding: EdgeInsets.all((_cardHeight * 0.06).clamp(3.0, 8.0)),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: flashing
                  ? const Color(0xFFE23B3B)
                  : (hovering ? const Color(0xFF2ECC71) : Colors.white38),
              width: flashing || hovering ? 2.4 : 1.2,
            ),
          ),
          child: Center(
            child: Text(
              // Destede hâlâ hedef kartı varsa buraya yeni bir hedef konabilir;
              // yoksa slot kalıcı olarak tamamlanmış demektir.
              _engine.bekleyenHedefSayisi > 0 ? 'Boş slot\nyeni hedef' : '👑\ntamamlandı',
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: (_cardHeight * 0.10).clamp(6.0, 10.5),
                height: 1.2,
                fontWeight: FontWeight.w800,
                color: Colors.white70,
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Kategori hedef kartı (DragTarget) ───────────────────────────────

  Widget _buildKategori(KategoriHedef h, int sira, Offset yerelKonum, double tahtaGenislik) {
    final flashing = _flashKategori == h.kategoriAdi;
    final hovering = _hoverKategori == h.kategoriAdi;

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
    }

    // Yazı ölçüleri kart yüksekliğinden türetilir (sabit piksel yok).
    final sayacFont = (_cardHeight * 0.155).clamp(8.5, 15.0);
    final adFont = (_cardHeight * 0.115).clamp(7.0, 12.0);
    final dersFont = (_cardHeight * 0.095).clamp(6.0, 10.0);
    final ic = (_cardHeight * 0.06).clamp(3.0, 8.0);

    final kart = DragTarget<_Suruklenen>(
      // Kartın TAMAMI bırakma alanı olsun (şeffaf boşluklar dâhil).
      hitTestBehavior: HitTestBehavior.opaque,
      onWillAcceptWithDetails: (details) {
        if (_hoverKategori != h.kategoriAdi) {
          setState(() => _hoverKategori = h.kategoriAdi);
        }
        return true;
      },
      onLeave: (_) {
        if (_hoverKategori == h.kategoriAdi) setState(() => _hoverKategori = null);
      },
      onAcceptWithDetails: (details) => _onKategoriDrop(details.data, h),
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
                  Text('🎯', style: TextStyle(fontSize: sayacFont)),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text('${h.eslesen}/${h.hedef}',
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: sayacFont,
                            color: _cardInk)),
                  ),
                ],
              ),
              Expanded(
                // Uzun kategori adı karta sığmazsa dikey olarak kayar.
                child: _KayanMetin(
                  metin: h.kategoriAdi,
                  hizalama: TextAlign.center,
                  stil: TextStyle(
                      fontSize: adFont,
                      fontWeight: FontWeight.w800,
                      height: 1.12,
                      color: _cardInk),
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
      toplam: kHedefSlotSayisi + kSutunSayisi,
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

  /// Bir tableau sütunu. Sütunun TAMAMI bir [DragTarget]'tır: boş sütuna da
  /// (kategori şartı olmadan) kart taşınabilir, dolu sütunda ise yalnızca aynı
  /// kategoriden kartlar yığılabilir.
  Widget _buildSutun(int i, double tahtaGenislik) {
    final c = _engine.sutunlar[i];
    final yerelKonum = Offset(
      i * (_cardWidth + kKartBosluk),
      _hedefAlanYukseklik + kKartBosluk * 5,
    );
    final flashing = _flashSutun == i;
    final hovering = _hoverSutun == i;

    // Sondaki açık grup (yığma ile 1'den fazla olabilir); geri kalanı kapalı.
    final acikBas = _engine.acikBaslangic(i);
    final acikAdet = acikBas < 0 ? 0 : c.length - acikBas;
    final kapaliAdet = acikBas < 0 ? c.length : acikBas;
    final kapaliGorunur = min(kapaliAdet, 4);

    // Kaydırma payları da kart yüksekliğinden türetilir (sabit piksel yok).
    final kapaliOffset = _cardHeight * 0.11;
    final kapaliKartY = _cardHeight * 0.26; // kapalı kart sırtının görünen payı
    // Açık yığındaki alt kartların görünen payı — bu şerit, o karta (ve
    // üstündekilere) dokunup birlikte taşımak için kullanılır.
    final grupOffset = _grupAdim;
    final base = kapaliGorunur * kapaliOffset;
    final grupYuksek = acikAdet <= 1 ? 0.0 : (acikAdet - 1) * grupOffset;
    final toplamYukseklik =
        (c.isEmpty ? _cardHeight : base + grupYuksek + _cardHeight + kDokunmaPayi);

    final govde = DragTarget<_Suruklenen>(
      hitTestBehavior: HitTestBehavior.opaque,
      onWillAcceptWithDetails: (details) {
        if (!details.data.destedenMi && details.data.sutun == i) return false;
        if (_hoverSutun != i) setState(() => _hoverSutun = i);
        return true;
      },
      onLeave: (_) {
        if (_hoverSutun == i) setState(() => _hoverSutun = null);
      },
      onAcceptWithDetails: (details) => _onSutunDrop(details.data, i),
      builder: (context, candidate, rejected) {
        if (c.isEmpty) {
          // Boş yuva — yanındaki açık kartlar/yığınlar buraya taşınabilir.
          return AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: _cardHeight,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: flashing
                    ? const Color(0xFFE23B3B)
                    : (hovering ? const Color(0xFF2ECC71) : Colors.white38),
                width: flashing || hovering ? 2.4 : 1.2,
              ),
              color: Colors.white.withValues(alpha: 0.05),
            ),
            child: Center(
              child: Icon(Icons.add_rounded,
                  color: Colors.white38, size: (_cardHeight * 0.22).clamp(12.0, 22.0)),
            ),
          );
        }

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
                  child: _kapaliKart(kapaliKartY),
                ),
              // Fazla gizli kapalı kart sayacı. IgnorePointer: bu rozet,
              // altındaki kartın dokunma alanını ASLA engellemesin.
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
              // Açık kartların HEPSİ ayrı ayrı sürüklenebilir: bir yığının
              // ortasındaki karta basılınca o kart VE üstündeki tüm kartlar
              // birlikte taşınır (klasik solitaire davranışı).
              //
              // DOKUNMA KUTULARI ÖRTÜŞMEZ: en üstteki kart tam kart yüksekliği
              // (+ dokunma payı) kadar, alttakiler ise YALNIZCA görünen şeritleri
              // kadar yer kaplar. Kart görseli [OverflowBox] ile şeridin dışına
              // taşarak çizilir. Böylece hangi karta basıldığı Stack'in çizim/
              // hit-test sırasından bağımsız olarak KESİNDİR.
              for (var g = 0; g < acikAdet; g++)
                Positioned(
                  top: base + g * grupOffset,
                  left: 0,
                  right: 0,
                  height: g == acikAdet - 1
                      ? _cardHeight + kDokunmaPayi
                      : grupOffset,
                  child: _buildAcikKart(
                    sutunIndex: i,
                    kartIndex: acikBas + g,
                    kart: c[acikBas + g],
                    grupAdet: acikAdet - g,
                    enUstte: g == acikAdet - 1,
                    flashing: flashing,
                    hovering: hovering,
                  ),
                ),
            ],
          ),
        );
      },
    );

    return _desteDagitim(
      sira: kHedefSlotSayisi + i,
      toplam: kHedefSlotSayisi + kSutunSayisi,
      yerelKonum: yerelKonum,
      tahtaGenislik: tahtaGenislik,
      child: govde,
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

  /// Tek bir AÇIK tableau kartı — kendisinden itibaren üstündeki tüm kartları
  /// (grupAdet) birlikte taşıyan sürükleyici.
  ///
  /// ── Dokunma hassasiyeti (korunan davranış) ──
  /// 1) Gecikme 25 ms: kart neredeyse dokunur dokunmaz yakalanır.
  /// 2) [hitTestBehavior] = opaque: kartın dokunma kutusunun TAMAMI aktiftir.
  /// 3) EN ÜSTTEKİ kart [kDokunmaPayi] kadar büyütülmüş şeffaf alanla sarılır.
  /// 4) Tableau kendi kaydırma bölmesinde durduğu için kaydırma jesti dokunuşu
  ///    çalmaz.
  ///
  /// ── Yığın taşıma ──
  /// Sürükleme başlayınca ([onDragStarted]) kaynak sütun/indeks EKRAN durumuna
  /// yazılır; böylece üstteki tüm kartlar da solar ve feedback'te grubun
  /// TAMAMI görünür.
  Widget _buildAcikKart({
    required int sutunIndex,
    required int kartIndex,
    required TerimKart kart,
    required int grupAdet,
    required bool enUstte,
    required bool flashing,
    required bool hovering,
  }) {
    // Bu kart, hâlihazırda sürüklenen yığının bir parçası mı?
    final grupta = _surukleniyor(sutunIndex, kartIndex);
    // Sürüklenecek grubun kartları (sıralama korunur: alttan üste).
    final grup = _engine.altGrup(sutunIndex, kartIndex);

    // Kart görselini, kendisine ayrılan (dar) dokunma şeridinin dışına taşarak
    // çizmesi için sarmalar.
    Widget kutu(Widget icerik) => OverflowBox(
          alignment: Alignment.topCenter,
          minHeight: 0,
          maxHeight: _cardHeight + (enUstte ? kDokunmaPayi : 0),
          child: Padding(
            // Şeffaf dokunma payı yalnızca en üstteki karta uygulanır; alttaki
            // kartlarda pay verilirse üsttekinin şeridini kapatırdı.
            padding: EdgeInsets.symmetric(vertical: enUstte ? kDokunmaPayi / 2 : 0),
            child: icerik,
          ),
        );

    final gorsel = _terimKarti(
      kart,
      faded: grupta,
      flash: flashing && enUstte,
      hover: hovering && enUstte,
      grupAdet: grupAdet,
    );

    return LongPressDraggable<_Suruklenen>(
      data: _Suruklenen.tableau(sutunIndex, kartIndex),
      delay: const Duration(milliseconds: 25),
      hitTestBehavior: HitTestBehavior.opaque,
      // Sürüklenen kart parmağın BİRAZ ÜSTÜNDE dursun (parmak kartı kapatmasın).
      dragAnchorStrategy: (draggable, ctx, position) =>
          Offset(_cardWidth / 2, _cardHeight + kSuruklemeYukariPay),
      // Bırakma hedefi parmağın değil, KARTIN göründüğü noktadan hesaplansın.
      feedbackOffset: Offset(0, -(kSuruklemeYukariPay + _cardHeight / 2)),
      feedback: Material(
        color: Colors.transparent,
        child: Transform.scale(
          scale: 1.06,
          alignment: Alignment.topCenter,
          child: _grupFeedback(grup.isEmpty ? [kart] : grup),
        ),
      ),
      childWhenDragging: kutu(_terimKarti(kart, faded: true, grupAdet: grupAdet)),
      onDragStarted: () {
        context.read<SoundService>().click();
        setState(() {
          _dragSutun = sutunIndex;
          _dragIndex = kartIndex;
        });
      },
      onDragEnd: (_) => _dragBitti(),
      onDraggableCanceled: (hiz, konum) => _dragBitti(),
      child: kutu(gorsel),
    );
  }

  void _dragBitti() {
    if (!mounted) return;
    if (_dragSutun == null && _dragIndex == null) return;
    setState(() {
      _dragSutun = null;
      _dragIndex = null;
    });
  }

  /// Sürükleme feedback'i: grubun TAMAMI, tableau'daki ile aynı basamaklı
  /// dizilişte. En alttaki (tutulan) kart ×N rozetini taşır.
  Widget _grupFeedback(List<TerimKart> grup) {
    final adet = grup.length;
    final adim = _grupAdim;
    return SizedBox(
      width: _cardWidth,
      height: _cardHeight + (adet - 1) * adim,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < adet; i++)
            Positioned(
              top: i * adim,
              left: 0,
              right: 0,
              child: _terimKarti(
                grup[i],
                faded: false,
                dragging: true,
                grupAdet: i == 0 ? adet : 1,
              ),
            ),
        ],
      ),
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
    // Kenarlık önceliği: yanlış hamle flaşı (kırmızı) > hover (yeşil) >
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
          // Terim karta sığmıyorsa kart içinde yavaşça aşağı-yukarı kayar.
          child: _KayanMetin(
            metin: kart.terim,
            hizalama: TextAlign.center,
            stil: TextStyle(
              // Yazı boyu da kart yüksekliğinden türetilir (sabit piksel yok).
              fontSize: (_cardHeight * 0.115).clamp(7.0, 13.0),
              height: 1.12,
              fontWeight: FontWeight.w900,
              color: faded ? _cardInk.withValues(alpha: 0.4) : _cardInk,
            ),
          ),
        ),
        // Yığın rozeti: bu karttan itibaren kaç kart birlikte taşınacak (×N).
        // IgnorePointer — rozet, kartın dokunma alanını engellemesin.
        if (grupAdet > 1 && !faded)
          Positioned(
            top: -6,
            right: -4,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: _feltGreen,
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

/// Karta SIĞMAYAN metni kart içinde sürekli aşağı-yukarı kaydıran (dikey
/// marquee) yazı.
///
/// Davranış:
///  * Metin verilen kutuya SIĞIYORSA hiç animasyon başlatılmaz; yazı dikeyde
///    ortalanmış ve SABİT durur (çok sayıda kart olduğu için bu performans
///    açısından kritiktir).
///  * Sığmıyorsa yazı yavaşça yukarı kayar, sonda kısa duraklar, geri iner ve
///    başta yine kısa durur; döngü kesintisiz sürer.
///  * Sığıp sığmadığı her yerleşimde [TextPainter] ile GERÇEKTEN ölçülür
///    (tahmin yok); ölçüm sonucu önbelleğe alınır.
///  * [AnimationController] [dispose] içinde MUTLAKA kapatılır.
class _KayanMetin extends StatefulWidget {
  final String metin;
  final TextStyle stil;
  final TextAlign hizalama;

  const _KayanMetin({
    required this.metin,
    required this.stil,
    this.hizalama = TextAlign.center,
  });

  @override
  State<_KayanMetin> createState() => _KayanMetinState();
}

class _KayanMetinState extends State<_KayanMetin> with SingleTickerProviderStateMixin {
  /// Sığma/taşma kararında kullanılan tolerans (yuvarlama hatalarına karşı).
  static const double _esik = 0.5;

  late final AnimationController _ctrl = AnimationController(vsync: this);

  // Ölçüm önbelleği — aynı metin/genişlik/punto için tekrar layout yapılmaz.
  String? _olcumMetin;
  double? _olcumGenislik;
  double? _olcumPunto;
  double _metinYukseklik = 0;

  @override
  void dispose() {
    // Kart sayısı fazla olduğundan sızıntı kritik: controller HER durumda kapanır.
    _ctrl.dispose();
    super.dispose();
  }

  double _olc(BuildContext context, double maxGenislik) {
    final punto = widget.stil.fontSize ?? 12.0;
    if (_olcumMetin == widget.metin &&
        _olcumGenislik == maxGenislik &&
        _olcumPunto == punto) {
      return _metinYukseklik;
    }
    final tp = TextPainter(
      text: TextSpan(text: widget.metin, style: widget.stil),
      textAlign: widget.hizalama,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: maxGenislik);
    _metinYukseklik = tp.height;
    tp.dispose();
    _olcumMetin = widget.metin;
    _olcumGenislik = maxGenislik;
    _olcumPunto = punto;
    return _metinYukseklik;
  }

  /// Animasyonu build DIŞINDA (kare sonunda) kurar/durdurur — build sırasında
  /// controller'a dokunmak "setState during build" hatasına yol açardı.
  double? _sonAyarTasma;

  void _animasyonAyarla(double tasma) {
    // Tahta çok sık yeniden çizilir (hover/flash); taşma değişmediyse yeni bir
    // kare-sonu işi kuyruğa alma.
    if (_sonAyarTasma != null && (_sonAyarTasma! - tasma).abs() < 0.01) return;
    _sonAyarTasma = tasma;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (tasma <= _esik) {
        if (_ctrl.isAnimating) _ctrl.stop();
        if (_ctrl.value != 0) _ctrl.value = 0;
        return;
      }
      // Taşma ne kadar büyükse kayma o kadar uzun sürer → hız sabit ve YAVAŞ.
      final sure = Duration(
        milliseconds: (3400 + tasma * 90).clamp(3400.0, 14000.0).round(),
      );
      if (_ctrl.duration != sure) {
        _ctrl.duration = sure;
        _ctrl.repeat();
      } else if (!_ctrl.isAnimating) {
        _ctrl.repeat();
      }
    });
  }

  /// 0→1 ilerlemeyi kayma oranına çevirir: başta bekle, yavaşça in, sonda
  /// bekle, yavaşça geri dön.
  double _kaymaOrani(double t) {
    const bekle = 0.18; // uçlardaki duraklama payı
    const orta = 0.5; // gidişin bittiği nokta
    if (t <= bekle) return 0;
    if (t < orta) return Curves.easeInOut.transform((t - bekle) / (orta - bekle));
    if (t <= orta + bekle) return 1;
    return 1 - Curves.easeInOut.transform((t - orta - bekle) / (1 - orta - bekle));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, cons) {
        final yazi = Text(
          widget.metin,
          textAlign: widget.hizalama,
          style: widget.stil,
        );
        if (!cons.hasBoundedHeight || cons.maxWidth <= 0 || cons.maxHeight <= 0) {
          return yazi;
        }

        final yukseklik = _olc(context, cons.maxWidth);
        final tasma = yukseklik - cons.maxHeight;
        _animasyonAyarla(tasma);

        // Sığıyor → sabit, ortalanmış yazı (animasyon YOK).
        if (tasma <= _esik) return Center(child: yazi);

        // Sığmıyor → kutu içinde dikey marquee.
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.topCenter,
            minHeight: 0,
            maxHeight: yukseklik,
            child: AnimatedBuilder(
              animation: _ctrl,
              child: yazi,
              builder: (context, icerik) => Transform.translate(
                offset: Offset(0, -tasma * _kaymaOrani(_ctrl.value)),
                child: icerik,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Küçük beyaz bölüm başlığı (oyun tahtası üzerinde).
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

/// "Kalan Hamle" bayrağı için sağ kenarı içe çentikli (flama) şekil.
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
