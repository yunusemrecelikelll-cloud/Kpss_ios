import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/dogru_yanlis_data.dart';
import '../../services/sound_service.dart';
import '../../services/storage_service.dart';
import '../../theme/design_system.dart';
import '../../theme/theme_provider.dart';
import '../premium_screen.dart';
import '../tools_hub_screen.dart';

/// Mini oyun — "Doğru mu Yanlış mı?": Tinder benzeri bir kart destesi.
/// Ekrandaki kartta bir SORU değil bir İDDİA (önerme) yazar; oyuncu ya alttaki
/// DOĞRU / YANLIŞ butonlarına basar ya da kartı sağa (doğru) / sola (yanlış)
/// sürükler. İki yol da aynı [_cevapla] fonksiyonuna gider, dolayısıyla
/// sürükleme kapalı kalsa bile butonlar tek başına oyunu yürütür.
///
/// Önerme havuzu [kDogruYanlisOnermeler] içindedir
/// (lib/data/dogru_yanlis_data.dart) — 300'den fazla, yarısı doğru yarısı
/// yanlış, tamamı doğrulanmış bilgi.
const String kDogruYanlisGameId = 'dogru_yanlis';

/// Oyun başında seçilebilen soru sayıları.
const List<int> kDogruYanlisAdetSecenekleri = [10, 20, 50, 100];

/// Ücretsiz pakette oynanabilen TEK deste boyutu. Diğer seçenekler kilitli
/// görünür ve dokununca Premium ekranına yönlendirir.
const int kUcretsizAdet = 10;

/// Kartın cevaplanmış sayılması için gereken yatay sürükleme mesafesi (px).
const double _kSwipeEsigi = 92;

class DogruYanlisScreen extends StatefulWidget {
  const DogruYanlisScreen({super.key});

  @override
  State<DogruYanlisScreen> createState() => _DogruYanlisScreenState();
}

/// Oyunun içinde bulunduğu aşama.
enum _Asama { kurulum, oyun, bitis }

/// Cevaplanan bir kartın kaydı — sonuç şeridinde ve bitişte kullanılır.
class _Cevap {
  final DogruYanlisOnerme onerme;
  final bool kullaniciDedi; // oyuncunun "doğru" dediği mi?
  final bool isabet;
  const _Cevap(this.onerme, this.kullaniciDedi, this.isabet);
}

class _DogruYanlisScreenState extends State<DogruYanlisScreen> {
  final Random _rnd = Random();

  _Asama _asama = _Asama.kurulum;
  bool _locked = false;
  bool _booted = false;

  /// Seçili deste boyutu. Ücretsiz kullanıcıda [_boot] bunu
  /// [kUcretsizAdet]'e sabitler — varsayılanı 20 bırakmak, kilitli bir
  /// seçeneğin baştan seçili görünmesine yol açardı.
  int _adet = 20;
  final List<DogruYanlisOnerme> _deste = [];
  int _index = 0;
  int _dogruSayisi = 0;
  int _yanlisSayisi = 0;
  _Cevap? _sonCevap;
  bool _yeniRekor = false;

  /// Kartın parmakla sürüklenme mesafesi — sıfırdan farklıysa kart eğilir.
  Offset _kaydirma = Offset.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  /// Günlük hak kontrolü — hak kalmamışsa kilit ekranı gösterilir.
  /// (Hak TÜKETİMİ burada değil, oyun gerçekten başlarken [_basla] içindedir;
  /// böylece soru sayısı seçmeden geri çıkan kullanıcının hakkı yanmaz.)
  void _boot() {
    final storage = context.read<StorageService>();
    if (!storage.isPremiumUser()) {
      // Ücretsiz pakette yalnızca en küçük deste açık — seçimi ona sabitle.
      _adet = kUcretsizAdet;
      final gp = storage.getGamePlayState(kDogruYanlisGameId);
      if ((gp['plays'] as int) >= kFreeGameDailyLimit + storage.getExtraPlays(kDogruYanlisGameId)) {
        setState(() {
          _locked = true;
          _booted = true;
        });
        return;
      }
    }
    setState(() => _booted = true);
  }

  /// Seçilen soru sayısı kadar önerme çekip oyunu başlatır. Havuz karıştırılıp
  /// baştan alındığı için AYNI oyunda önerme tekrar etmez.
  Future<void> _basla() async {
    final storage = context.read<StorageService>();
    if (!storage.isPremiumUser()) {
      // Güvenlik ağı: ücretsiz kullanıcı hiçbir yoldan kilitli bir deste
      // boyutuyla oyuna başlayamasın.
      _adet = kUcretsizAdet;
      final gp = storage.getGamePlayState(kDogruYanlisGameId);
      if ((gp['plays'] as int) >= kFreeGameDailyLimit + storage.getExtraPlays(kDogruYanlisGameId)) {
        if (!mounted) return;
        setState(() => _locked = true);
        return;
      }
      await storage.useGamePlay(kDogruYanlisGameId);
    }
    if (!mounted) return;

    // Kullanıcının Ayarlar'da seçtiği eğitim seviyesine göre havuzu süz.
    // seviyeyeGoreOnermeler, seçilen seviyeye + tüm seviyelere uygun önermeleri
    // döndürür; o seviyede içerik azsa otomatik olarak tüm havuza genişler.
    final havuz = seviyeyeGoreOnermeler(storage.getExamType(), enAz: _adet);
    final karisik = List<DogruYanlisOnerme>.from(havuz)..shuffle(_rnd);
    final sayi = min(_adet, karisik.length);
    setState(() {
      _deste
        ..clear()
        ..addAll(karisik.take(sayi));
      _index = 0;
      _dogruSayisi = 0;
      _yanlisSayisi = 0;
      _sonCevap = null;
      _yeniRekor = false;
      _kaydirma = Offset.zero;
      _asama = _Asama.oyun;
    });
  }

  /// Tek cevap noktası: hem butonlar hem sürükleme buraya gelir.
  void _cevapla(bool kullaniciDogruDedi) {
    if (_asama != _Asama.oyun || _index >= _deste.length) return;
    context.read<SoundService>().click();
    final onerme = _deste[_index];
    final isabet = onerme.dogru == kullaniciDogruDedi;
    setState(() {
      _sonCevap = _Cevap(onerme, kullaniciDogruDedi, isabet);
      if (isabet) {
        _dogruSayisi += 1;
      } else {
        _yanlisSayisi += 1;
      }
      _kaydirma = Offset.zero;
      _index += 1;
    });
    if (_index >= _deste.length) _bitir();
  }

  /// Deste bitti: skoru ve tur istatistiğini ortak API üzerinden kaydeder.
  Future<void> _bitir() async {
    setState(() => _asama = _Asama.bitis);
    final storage = context.read<StorageService>();
    final yeni = await storage.submitHighScore(kDogruYanlisGameId, _dogruSayisi);
    await storage.setLastRoundStats(
      kDogruYanlisGameId,
      correct: _dogruSayisi,
      wrong: _yanlisSayisi,
    );
    if (!mounted) return;
    setState(() => _yeniRekor = yeni);
  }

  void _yenidenOyna() {
    setState(() {
      _asama = _Asama.kurulum;
      _sonCevap = null;
      _kaydirma = Offset.zero;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_locked) {
      return LockedFeatureCard(
        gameId: kDogruYanlisGameId,
        oyunAdi: 'Doğru mu Yanlış mı',
        onUnlocked: () => setState(() => _locked = false),

        title: 'Doğru mu Yanlış mı?',
        desc: "Bugünkü $kFreeGameDailyLimit ücretsiz Doğru mu Yanlış mı hakkını kullandın. "
            "Yarın tekrar oynayabilir ya da Premium'a geçip sınırsız oynayabilirsin.",
      );
    }
    if (!_booted) {
      return Scaffold(
        appBar: AppBar(title: const Text('🤔 Doğru mu Yanlış mı?')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    switch (_asama) {
      case _Asama.kurulum:
        return _kurulumEkrani(context);
      case _Asama.oyun:
        return _oyunEkrani(context);
      case _Asama.bitis:
        return _sonucEkrani(context);
    }
  }

  // ── Kurulum: soru sayısı seçimi ─────────────────────────────────────────

  Widget _kurulumEkrani(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final storage = context.watch<StorageService>();
    final premium = storage.isPremiumUser();
    final gp = storage.getGamePlayState(kDogruYanlisGameId);
    final kalan = (kFreeGameDailyLimit - (gp['plays'] as int)).clamp(0, kFreeGameDailyLimit);
    final rekor = storage.getHighScore(kDogruYanlisGameId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('🤔 Doğru mu Yanlış mı?'),
        actions: const [
          HowToPlayButton(
            title: 'Doğru mu Yanlış mı?',
            body: 'Ekrana bir önerme (iddia) gelir. İddia doğruysa DOĞRU, yanlışsa '
                'YANLIŞ de.\n\nKartı sağa sürüklemek DOĞRU, sola sürüklemek YANLIŞ '
                'demektir; istersen alttaki butonları da kullanabilirsin.\n\n'
                'Her cevaptan sonra kısa açıklamayı görürsün. Tur bitince isabet '
                'yüzden ve rekorun hesaplanır.',
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DsCard(
              accent: c.violet,
              padding: const EdgeInsets.all(18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'ÖNERME KARTLARI',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.9,
                            color: c.violet,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Doğru mu Yanlış mı?',
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w900, color: c.text),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Karttaki iddiayı oku; doğruysa sağa, yanlışsa sola kaydır. '
                          'Butonlarla da cevaplayabilirsin.',
                          style: TextStyle(fontSize: 12.5, height: 1.4, color: c.textDim),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            DsChip(
                              label: '${kDogruYanlisOnermeler.length} ÖNERME',
                              color: c.violet,
                            ),
                            DsChip(
                              label: premium ? 'SINIRSIZ' : 'BUGÜN $kalan HAK',
                              color: premium ? c.gold : c.success,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  DsIllustration(emoji: '🤔', glowColor: c.violet),
                ],
              ),
            ),
            const SizedBox(height: 22),
            const DsSectionHeader(title: 'Kaç kart çözelim?'),
            const SizedBox(height: 10),
            Wrap(
              spacing: kDsGap,
              runSpacing: kDsGap,
              children: [
                for (final adet in kDogruYanlisAdetSecenekleri)
                  _AdetSecenegi(
                    adet: adet,
                    // Ücretsiz pakette yalnızca en küçük deste (10 kart)
                    // oynanabilir; diğerleri premium'a özel.
                    kilitli: !premium && adet != kUcretsizAdet,
                    secili: _adet == adet,
                    onTap: () {
                      context.read<SoundService>().click();
                      if (!premium && adet != kUcretsizAdet) {
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const PremiumScreen()));
                        return;
                      }
                      setState(() => _adet = adet);
                    },
                  ),
              ],
            ),
            if (!premium) ...[
              const SizedBox(height: 10),
              Text(
                'Ücretsiz pakette $kUcretsizAdet kartlık deste açık. '
                'Daha uzun desteler için Premium\'a geç.',
                style: TextStyle(fontSize: 12, color: c.textFaint, height: 1.35),
              ),
            ],
            const SizedBox(height: 20),
            DsStatStrip(
              items: [
                DsStatItem(
                  visual: DsIconBadge(emoji: '🏆', color: c.gold, size: 44),
                  value: '$rekor',
                  label: 'En Yüksek Skor',
                ),
                DsStatItem(
                  visual: DsIconBadge(emoji: '🃏', color: c.violet, size: 44),
                  value: '$_adet',
                  label: 'Seçilen kart',
                ),
                DsStatItem(
                  visual: DsIconBadge(
                      emoji: premium ? '👑' : '🎟️',
                      color: premium ? c.gold : c.success,
                      size: 44),
                  value: premium ? '∞' : '$kalan',
                  label: premium ? 'Premium' : 'Kalan hak',
                ),
              ],
            ),
            const SizedBox(height: 20),
            Center(
              child: DsPillButton(
                label: '$_adet Kart ile Başla',
                color: c.violet,
                trailingIcon: Icons.play_arrow_rounded,
                onPressed: () {
                  context.read<SoundService>().click();
                  _basla();
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ── Oyun tahtası ────────────────────────────────────────────────────────

  Widget _oyunEkrani(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    if (_index >= _deste.length) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final onerme = _deste[_index];
    final ilerleme = _index / _deste.length;

    // Sürükleme yönüne göre 0..1 arası bir "niyet" değeri — kartın üstündeki
    // DOĞRU/YANLIŞ damgasının belirginliğini ve kenarlık rengini belirler.
    final yatay = _kaydirma.dx;
    final niyet = (yatay.abs() / _kSwipeEsigi).clamp(0.0, 1.0);
    final saga = yatay > 0;
    final niyetRengi = niyet < 0.05 ? null : (saga ? c.success : c.danger);

    return Scaffold(
      appBar: AppBar(
        title: const Text('🤔 Doğru mu Yanlış mı?'),
        actions: const [
          HowToPlayButton(
            title: 'Doğru mu Yanlış mı?',
            body: 'Kartı sağa sürüklersen DOĞRU, sola sürüklersen YANLIŞ demiş '
                'olursun. Alttaki butonlar da aynı işi yapar.',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Üst şerit: ilerleme + anlık doğru/yanlış sayacı.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text(
                        'Kart ${_index + 1}/${_deste.length}',
                        style: TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w800, color: c.textDim),
                      ),
                      const Spacer(),
                      DsChip(label: '✓ $_dogruSayisi', color: c.success),
                      const SizedBox(width: 6),
                      DsChip(label: '✗ $_yanlisSayisi', color: c.danger),
                    ],
                  ),
                  const SizedBox(height: 8),
                  DsProgressBar(value: ilerleme, color: c.violet),
                ],
              ),
            ),
            // Kart alanı — kalan tüm yüksekliği kaplar, taşma olmaz.
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: GestureDetector(
                  onPanUpdate: (d) => setState(() => _kaydirma += d.delta),
                  onPanEnd: (_) {
                    if (_kaydirma.dx > _kSwipeEsigi) {
                      _cevapla(true);
                    } else if (_kaydirma.dx < -_kSwipeEsigi) {
                      _cevapla(false);
                    } else {
                      setState(() => _kaydirma = Offset.zero);
                    }
                  },
                  onPanCancel: () => setState(() => _kaydirma = Offset.zero),
                  child: Transform.translate(
                    offset: Offset(_kaydirma.dx, _kaydirma.dy * 0.25),
                    child: Transform.rotate(
                      angle: _kaydirma.dx / 1600,
                      child: _OnermeKarti(
                        onerme: onerme,
                        vurgu: niyetRengi,
                        damgaOpakligi: niyet,
                        damgaSaga: saga,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Son cevabın kısa açıklaması — bir sonraki kart gelirken de
            // ekranda kalır, böylece oyuncu akışı bozmadan öğrenir.
            if (_sonCevap != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _SonCevapSeridi(cevap: _sonCevap!),
              ),
            // Butonlar — sürükleme kullanılmasa da oyun tamamen oynanabilir.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: _CevapButonu(
                      etiket: 'YANLIŞ',
                      emoji: '✗',
                      renk: c.danger,
                      onTap: () => _cevapla(false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _CevapButonu(
                      etiket: 'DOĞRU',
                      emoji: '✓',
                      renk: c.success,
                      onTap: () => _cevapla(true),
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

  // ── Sonuç ───────────────────────────────────────────────────────────────

  Widget _sonucEkrani(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final toplam = _deste.isEmpty ? 1 : _deste.length;
    final yuzde = (_dogruSayisi * 100 / toplam).round();
    final rekor = context.watch<StorageService>().getHighScore(kDogruYanlisGameId);

    final (String emoji, String degerlendirme) = switch (yuzde) {
      >= 90 => ('🏆', 'Muhteşem! Önermeleri neredeyse kusursuz ayırt ettin.'),
      >= 75 => ('🎯', 'Çok iyi! Bilgin sağlam, birkaç ince ayrıntıya dikkat.'),
      >= 60 => ('👍', 'Fena değil. Yanlış bildiklerini not al, tekrar dene.'),
      >= 40 => ('📚', 'Gelişime açık. Açıklamaları okuyarak tekrar oyna.'),
      _ => ('💪', 'Şimdilik zorlandın ama pes yok — tekrar dene!'),
    };

    return Scaffold(
      appBar: AppBar(title: const Text('🤔 Doğru mu Yanlış mı?')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DsCard(
              accent: _yeniRekor ? c.gold : c.violet,
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DsIllustration(
                    emoji: _yeniRekor ? '🏆' : emoji,
                    glowColor: _yeniRekor ? c.gold : c.violet,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _yeniRekor ? 'YENİ REKOR!' : 'Tur Bitti!',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: _yeniRekor ? c.gold : c.text,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    degerlendirme,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, height: 1.45, color: c.textDim),
                  ),
                ],
              ),
            ),
            const SizedBox(height: kDsGap),
            DsStatStrip(
              items: [
                DsStatItem(
                  visual: DsIconBadge(emoji: '✅', color: c.success, size: 44),
                  value: '$_dogruSayisi',
                  label: 'Doğru',
                ),
                DsStatItem(
                  visual: DsIconBadge(emoji: '❌', color: c.danger, size: 44),
                  value: '$_yanlisSayisi',
                  label: 'Yanlış',
                ),
                DsStatItem(
                  visual: DsIconBadge(emoji: '🎯', color: c.violet, size: 44),
                  value: '%$yuzde',
                  label: 'İsabet',
                ),
              ],
            ),
            const SizedBox(height: kDsGap),
            DsCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  DsIconBadge(emoji: '🏆', color: c.gold, size: 42),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('En Yüksek Skor',
                            style: TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w800, color: c.textDim)),
                        const SizedBox(height: 2),
                        Text('$rekor doğru',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w900, color: c.text)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                DsPillButton(
                  label: 'Tekrar Oyna',
                  color: c.violet,
                  leadingIcon: Icons.refresh,
                  onPressed: () {
                    context.read<SoundService>().click();
                    _yenidenOyna();
                  },
                ),
                DsPillButton(
                  label: 'Menüye Dön',
                  color: c.violet,
                  filled: false,
                  onPressed: () {
                    context.read<SoundService>().click();
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

/// Kurulum ekranındaki soru sayısı seçeneği (10 / 20 / 50 / 100).
class _AdetSecenegi extends StatelessWidget {
  final int adet;
  final bool secili;
  final VoidCallback onTap;

  /// Bu seçenek premium'a mı özel? Ücretsiz pakette yalnızca en küçük
  /// seçenek (10 kart) açık; diğerleri kilitli görünür ve dokununca
  /// Premium ekranına yönlendirir.
  final bool kilitli;

  const _AdetSecenegi({
    required this.adet,
    required this.secili,
    required this.onTap,
    this.kilitli = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    // Kilitli seçenek altın kenarlıkla "premium" hissi verir; seçili olan
    // menekşe. Kilitli olan asla "seçili" görünmez.
    final vurgu = kilitli
        ? c.gold.withValues(alpha: 0.55)
        : (secili ? c.violet : c.border);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(kDsRadiusSm),
        onTap: onTap,
        child: Container(
          width: 78,
          padding: const EdgeInsets.symmetric(vertical: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(kDsRadiusSm),
            color: kilitli
                ? c.gold.withValues(alpha: 0.07)
                : (secili ? c.violet.withValues(alpha: 0.14) : c.glass),
            border: Border.all(color: vurgu, width: secili && !kilitli ? 1.6 : 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (kilitli)
                Icon(Icons.lock_outline, size: 16, color: c.gold)
              else
                const SizedBox(height: 16),
              const SizedBox(height: 2),
              Text('$adet',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: kilitli
                          ? c.gold
                          : (secili ? c.violet : c.text))),
              const SizedBox(height: 2),
              Text('kart',
                  style: TextStyle(fontSize: 10.5, color: c.textFaint)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Üstünde önermenin yazdığı büyük kart. Uzun metinlerde yazı boyu küçülür ve
/// gerekirse kart içinde kaydırılır — hiçbir durumda taşma olmaz.
class _OnermeKarti extends StatelessWidget {
  final DogruYanlisOnerme onerme;

  /// Sürükleme yönüne göre kenarlık vurgusu (yoksa nötr kart).
  final Color? vurgu;
  final double damgaOpakligi;
  final bool damgaSaga;

  const _OnermeKarti({
    required this.onerme,
    required this.vurgu,
    required this.damgaOpakligi,
    required this.damgaSaga,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    // Uzun önermelerde yazı küçülsün diye kaba bir ölçek.
    final uzunluk = onerme.metin.length;
    final punto = uzunluk > 130
        ? 17.0
        : uzunluk > 90
            ? 19.0
            : uzunluk > 55
                ? 22.0
                : 25.0;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(kDsRadius),
        color: vurgu != null
            ? vurgu!.withValues(alpha: c.isLight ? 0.08 : 0.12)
            : c.glass,
        border: Border.all(
          color: vurgu ?? c.border,
          width: vurgu != null ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: (vurgu ?? c.violet).withValues(alpha: c.isLight ? 0.12 : 0.20),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    DsChip(label: onerme.ders.toUpperCase(), color: c.violet),
                    const Spacer(),
                    Text('🤔', style: TextStyle(fontSize: 20, color: c.text)),
                  ],
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      child: Text(
                        onerme.metin,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: punto,
                          height: 1.35,
                          fontWeight: FontWeight.w800,
                          color: c.text,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    '← YANLIŞ            DOĞRU →',
                    style: TextStyle(
                      fontSize: 10.5,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w800,
                      color: c.textFaint,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Sürüklerken beliren damga.
          if (damgaOpakligi > 0.05)
            Positioned(
              top: 54,
              left: damgaSaga ? 20 : null,
              right: damgaSaga ? null : 20,
              child: Opacity(
                opacity: damgaOpakligi,
                child: Transform.rotate(
                  angle: damgaSaga ? -0.28 : 0.28,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: damgaSaga ? c.success : c.danger, width: 3),
                    ),
                    child: Text(
                      damgaSaga ? 'DOĞRU' : 'YANLIŞ',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                        color: damgaSaga ? c.success : c.danger,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Bir önceki cevabın sonucu + kısa açıklaması.
class _SonCevapSeridi extends StatelessWidget {
  final _Cevap cevap;
  const _SonCevapSeridi({required this.cevap});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final renk = cevap.isabet ? c.success : c.danger;
    final dogrusu = cevap.onerme.dogru ? 'DOĞRU' : 'YANLIŞ';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(kDsRadiusSm),
        color: renk.withValues(alpha: 0.12),
        border: Border.all(color: renk.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(cevap.isabet ? '✅' : '❌', style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  cevap.isabet ? 'Bildin! Önerme $dogrusu' : 'Kaçırdın — önerme $dogrusu',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w900, color: renk),
                ),
                const SizedBox(height: 2),
                Text(
                  cevap.onerme.aciklama,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, height: 1.3, color: c.textDim),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Alttaki büyük DOĞRU / YANLIŞ butonu.
class _CevapButonu extends StatelessWidget {
  final String etiket;
  final String emoji;
  final Color renk;
  final VoidCallback onTap;
  const _CevapButonu({
    required this.etiket,
    required this.emoji,
    required this.renk,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: renk.withValues(alpha: c.isLight ? 0.12 : 0.18),
            border: Border.all(color: renk.withValues(alpha: 0.65), width: 1.6),
            boxShadow: [
              BoxShadow(color: renk.withValues(alpha: 0.22), blurRadius: 14),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 15),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(emoji, style: TextStyle(fontSize: 17, color: renk)),
                const SizedBox(width: 8),
                Text(
                  etiket,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                    color: renk,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
