import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../screens/account_login_screen.dart';
import '../services/auth_service.dart';
import '../services/invite_service.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../theme/design_system.dart';
import '../theme/theme_provider.dart';
import '../utils/exam_dates.dart';
import '../utils/ust_bildirim.dart';

/// Anasayfa "Davet Et & Kazan" kartı (kullanıcı isteği):
/// - Kullanıcının kendi davet kodu + kopyala/görsel paylaş.
/// - "Nasıl yapılır" adımları.
/// - Her yeni davette HEM davet edene HEM de kod ile giren yeni hesaba
///   **1 gün premium** (davet edende BİRİKİR: 3 kişi = 3 gün).
/// - Şu ana kadar davetlerden kazanılan toplam (kişi + kazanılan gün).
/// - Bonus premium KALAN süresi (saat:dakika, canlı sayar).
///
/// Yalnızca GİRİŞ YAPMIŞ kullanıcıda anlamlıdır (kod hesaba bağlı); giriş yoksa
/// kısa bir "giriş yap" yönlendirmesi gösterir.
/// Paylaşımlarda DÖNÜŞÜMLÜ kullanılan motivasyon/çekici cümleler (kullanıcı
/// isteği: her paylaşımda farklı olsun). Görsel ve metin paylaşımında rastgele
/// biri seçilir.
const List<String> kDavetMotivasyonlar = [
  'Hemen ücretsiz topluluğa katıl, 20.000’i aşkın soru ile çalış!',
  'Atama hayalin bir davet uzağında — birlikte çalışalım, birlikte kazanalım!',
  'Boş vaktini net’e çevir: her gün birkaç soru, sınavda büyük fark!',
  'Yalnız çalışma! KPSS Düello’da yarış, eğlenerek öğren, hızlan!',
  'Bugün başlayan yarın kazanır. Sen de bu kervana katıl!',
  '20.000+ soru, konu anlatımı ve denemeler cebinde — hemen indir!',
  'Sınav yaklaşıyor; kaybedecek günün yok. Şimdi başla, farkı gör!',
  'Doğru kaynak + düzenli tekrar = atama. Gerisini uygulama halleder!',
  'Arkadaşınla yarış, birlikte çalış; motivasyonun hiç düşmesin!',
  'Küçük adımlar büyük atamalar getirir. İlk adımı bugün at!',
];

class DavetKazanKarti extends StatefulWidget {
  const DavetKazanKarti({super.key});

  @override
  State<DavetKazanKarti> createState() => _DavetKazanKartiState();
}

class _DavetKazanKartiState extends State<DavetKazanKarti> {
  final _invite = InviteService();
  final _rnd = Random();
  String? _kod;
  bool _yukleniyor = true;
  Timer? _saat; // kalan premium süreyi dakikada bir tazeler

  String _rastgeleMotivasyon() =>
      kDavetMotivasyonlar[_rnd.nextInt(kDavetMotivasyonlar.length)];

  @override
  void initState() {
    super.initState();
    _kodYukle();
    _saat = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _saat?.cancel();
    super.dispose();
  }

  Future<void> _kodYukle() async {
    final auth = context.read<AuthService>();
    if (!auth.isRealSignedIn) {
      if (mounted) setState(() => _yukleniyor = false);
      return;
    }
    final ad = context.read<StorageService>().getUserName();
    final kod = await _invite.kendiDavetKodum(ad: ad.isEmpty ? 'Kullanıcı' : ad);
    if (!mounted) return;
    setState(() {
      _kod = kod;
      _yukleniyor = false;
    });
  }

  String _kalanSure(Duration d) {
    if (d <= Duration.zero) return '';
    final saat = d.inHours;
    final dk = d.inMinutes % 60;
    if (saat >= 24) {
      final gun = d.inDays;
      final kalanSaat = d.inHours % 24;
      return '$gun gün $kalanSaat saat';
    }
    return '$saat saat $dk dakika';
  }

  void _kopyala() {
    if (_kod == null) return;
    context.read<SoundService>().click();
    Clipboard.setData(ClipboardData(text: _davetMetni()));
    ustBildirim('Davet mesajı kopyalandı — arkadaşlarına gönder!',
        tur: UstBildirimTuru.basari);
  }

  String _davetMetni([String? motivasyon]) =>
      'KPSS Hazırlık uygulamasına davet kodum: ${_kod ?? ""}\n\n'
      '${motivasyon ?? _rastgeleMotivasyon()}\n\n'
      'Uygulamayı indir, giriş ekranındaki "Davet kodum var" bölümüne bu kodu gir; '
      'ikimiz de 1 gün premium kazanalım. 🎁';

  /// Davet GÖRSELİ oluşturup sistem paylaş menüsüyle paylaşır (kullanıcı isteği:
  /// paylaş butonu YENİ bir fotoğraf oluştursun; davet kodu + uygulama içeriği +
  /// davet koduyla gelince ne olduğu yazsın).
  ///
  /// TESTFLIGHT/iOS DÜZELTMESİ: Görsel eskiden ekran DIŞINDA (left:-3000)
  /// çiziliyordu; gerçek iOS'ta (Impeller) ekran dışı katman çoğu zaman
  /// BOYANMIYOR ve `toImage` boş/başarısız dönüyordu → "çalışmıyor". Artık
  /// görsel ekranın İÇİNDE (sol üst) çizilir — böylece kesinlikle layout edilip
  /// boyanır — ve üstüne konan OPAK bir katmanla kullanıcıdan gizlenir.
  /// RepaintBoundary kendi katmanını yakaladığı için üstteki kapak görüntüyü
  /// etkilemez. Ayrıca sabit gecikme yerine GERÇEK kare beklenir ve iPad'de
  /// paylaş popover'ı için `sharePositionOrigin` verilir (yoksa iOS hata verir).
  Future<void> _gorselPaylas() async {
    if (_kod == null) return;
    context.read<SoundService>().click();
    final c = context.read<ThemeProvider>().colors;
    // Her paylaşımda FARKLI motivasyon (kullanıcı isteği) — görsel ve metinde aynı.
    final motivasyon = _rastgeleMotivasyon();
    // iPad paylaş popover'ının çıkacağı konum (bu kartın ekrandaki dikdörtgeni).
    final kutu = context.findRenderObject() as RenderBox?;
    final Rect paylasKonumu = (kutu != null && kutu.hasSize)
        ? (kutu.localToGlobal(Offset.zero) & kutu.size)
        : (Offset.zero & const Size(120, 120));
    final boundaryKey = GlobalKey();
    final overlay = Overlay.of(context);
    final entry = OverlayEntry(
      builder: (_) => Stack(
        children: [
          // Görsel SABİT 540×960 (9:16) çizilir. Telefon ekranından geniş
          // olabileceği için FittedBox ile ekrana sığacak şekilde ölçeklenir —
          // böylece TAMAMI ekran içinde kalır ve kesinlikle boyanır. RepaintBoundary
          // kendi katmanını 540×960 doğal boyutunda yakaladığı için ekrandaki
          // küçültme çıktının çözünürlüğünü DÜŞÜRMEZ (toImage tam boyuttan alır).
          Positioned.fill(
            child: FittedBox(
              fit: BoxFit.contain,
              child: Material(
                type: MaterialType.transparency,
                child: RepaintBoundary(
                  key: boundaryKey,
                  child: _PaylasGorseli(kod: _kod!),
                ),
              ),
            ),
          ),
          // Tüm ekranı kaplayan OPAK katman — görseli kullanıcıdan gizler
          // (yakalama RepaintBoundary'nin kendi katmanından yapıldığı için bu
          // kapak görüntüye dahil olmaz).
          Positioned.fill(child: ColoredBox(color: c.bg)),
        ],
      ),
    );
    overlay.insert(entry);
    try {
      // Sabit gecikme yerine GERÇEK kare(ler)i bekle — böylece widget layout
      // edilip boyanmış olur (yavaş cihazda 350ms yetmeyebiliyordu).
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;
      final boundary = boundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        entry.remove();
        return;
      }
      // 540×960 mantıksal boyut × pixelRatio 2 = 1080×1920 fiziksel (Instagram
      // Story 9:16, tam hedef çözünürlük).
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      entry.remove();
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/kpss_davet_$_kod.png');
      await file.writeAsBytes(bytes.buffer.asUint8List());
      await Share.shareXFiles(
        [XFile(file.path)],
        text: _davetMetni(motivasyon),
        sharePositionOrigin: paylasKonumu,
      );
    } catch (e) {
      if (entry.mounted) entry.remove();
      if (mounted) {
        ustBildirim('Görsel paylaşılamadı, bunun yerine metin kopyalandı.',
            tur: UstBildirimTuru.hata);
        Clipboard.setData(ClipboardData(text: _davetMetni()));
      }
    }
  }

  void _nasilYapilir(BuildContext context) {
    final c = context.read<ThemeProvider>().colors;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.bg2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                    color: c.border, borderRadius: BorderRadius.circular(999)),
              ),
            ),
            Text('🎁 Davet Et & Kazan — Nasıl Yapılır?',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: c.text)),
            const SizedBox(height: 12),
            _adim(c, '1', 'Davet kodunu paylaş',
                'Yukarıdaki 6 haneli kodunu arkadaşına gönder (kopyala butonu hazır mesaj oluşturur).'),
            _adim(c, '2', 'Arkadaşın uygulamayı indirsin',
                'App Store / Google Play’den KPSS Hazırlık’ı kursun.'),
            _adim(c, '3', 'Girişte kodu girsin',
                'Arkadaşın giriş ekranındaki "Davet kodum var" bölümüne senin kodunu yazsın ve Google/Apple ile GİRİŞ YAPSIN.'),
            _adim(c, '4', 'Ödülünüzü alın 🎉',
                'Arkadaşın YENİ hesapla giriş yaptığı an HEM SANA hem de ona 1’er gün premium tanımlanır. Her yeni davetle senin premium süren BİRİKİR (3 kişi = 3 gün). Uygulamayı bir sonraki açışında otomatik yüklenir.'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.warn.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.warn.withValues(alpha: 0.4)),
              ),
              child: Text(
                'ℹ️ Güvenlik: Her cihaz davet kodunu yalnızca 1 kez kullanabilir. '
                'Aynı cihazda farklı hesaplarla tekrar tekrar davet kullanılamaz ve '
                'kendi kodunu kullanamazsın. Böylece sistem herkes için adil kalır.',
                style: TextStyle(fontSize: 11.5, height: 1.45, color: c.textDim),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _adim(dynamic c, String no, String baslik, String metin) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26, height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: c.violetL, shape: BoxShape.circle),
            child: Text(no,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(baslik,
                    style: TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w800, color: c.text)),
                const SizedBox(height: 2),
                Text(metin,
                    style: TextStyle(fontSize: 12, height: 1.4, color: c.textDim)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final storage = context.watch<StorageService>();
    final auth = context.watch<AuthService>();

    // Giriş yapılmamışsa: kartı yine göster ama dokununca GİRİŞ ekranına
    // yönlendir (davet kodu hesaba bağlı olduğu için giriş şart — kullanıcı
    // isteği: misafirde de görünsün, tıklayınca girişe gitsin).
    if (!auth.isRealSignedIn) {
      return DsCard(
        accent: c.gold,
        padding: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(kDsRadius),
          onTap: () {
            context.read<SoundService>().click();
            Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AccountLoginScreen()));
          },
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  c.violet.withValues(alpha: 0.28),
                  c.gold.withValues(alpha: 0.16),
                ],
              ),
              borderRadius: BorderRadius.circular(kDsRadius),
            ),
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                DsIconBadge(
                    icon: Icons.card_giftcard_rounded, color: c.gold, size: 42, glow: false),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Davet Et & Kazan',
                          style: TextStyle(
                              fontSize: 15.5, fontWeight: FontWeight.w900, color: c.text)),
                      const SizedBox(height: 2),
                      Text(
                        'Arkadaşını davet et, her ikiniz de 1 gün premium kazanın! '
                        'Davet kodunu görmek için giriş yap.',
                        style: TextStyle(fontSize: 12, height: 1.35, color: c.textDim),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: c.violetL),
              ],
            ),
          ),
        ),
      );
    }

    final kazananSayi = storage.getInviteEarnedCount();
    final premiumKalan = storage.getBonusPremiumRemaining();
    final premiumAktif = premiumKalan > Duration.zero;

    return DsCard(
      accent: c.gold,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Gradyanlı başlık şeridi (temaya uygun mor→altın geçiş) ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  c.violet.withValues(alpha: 0.32),
                  c.gold.withValues(alpha: 0.20),
                ],
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(kDsRadius)),
            ),
            child: Row(
              children: [
                DsIconBadge(
                    icon: Icons.card_giftcard_rounded, color: c.gold, size: 42, glow: false),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Davet Et & Kazan',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w900, color: c.text)),
                      const SizedBox(height: 1),
                      Text('Her yeni davet: ikinize de 1 gün premium',
                          style: TextStyle(fontSize: 11.5, color: c.textDim)),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.help_outline_rounded, color: c.violetL),
                  tooltip: 'Nasıl yapılır?',
                  onPressed: () => _nasilYapilir(context),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Davet kodu (altın tonlu, öne çıkan kutu) ──
                if (_yukleniyor)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: c.gold)),
                    ),
                  )
                else if (_kod != null)
                  InkWell(
                    onTap: _kopyala,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            c.gold.withValues(alpha: 0.18),
                            c.violetL.withValues(alpha: 0.10),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: c.gold.withValues(alpha: 0.45)),
                      ),
                      child: Row(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('DAVET KODUN',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.5,
                                      color: c.textFaint)),
                              const SizedBox(height: 2),
                              Text(_kod!,
                                  style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 5,
                                      color: c.text)),
                            ],
                          ),
                          const Spacer(),
                          Icon(Icons.copy_rounded, size: 18, color: c.violetL),
                          const SizedBox(width: 4),
                          Text('Kopyala',
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: c.violetL)),
                        ],
                      ),
                    ),
                  )
                else
                  Text('Davet kodu yüklenemedi, internetini kontrol et.',
                      style: TextStyle(fontSize: 12, color: c.textFaint)),
                if (_kod != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DsPillButton(
                          label: 'Görsel Paylaş',
                          leadingIcon: Icons.ios_share_rounded,
                          color: c.gold,
                          onPressed: _gorselPaylas,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DsPillButton(
                          label: 'Kopyala',
                          leadingIcon: Icons.copy_rounded,
                          color: c.violetL,
                          filled: false,
                          onPressed: _kopyala,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                // ── Kazanımlar + kalan premium (temaya uygun tonlu rozetler) ──
                Row(
                  children: [
                    Expanded(
                      child: _ozet(c, '👥', '$kazananSayi kişi',
                          '$kazananSayi gün premium kazandın', c.violetL),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: premiumAktif
                          ? _ozet(c, '💎', 'Premium aktif',
                              'Kalan: ${_kalanSure(premiumKalan)}', c.gold)
                          : _ozet(c, '💎', 'Premium yok',
                              'Davet et, 1 gün kazan', c.gold),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _ozet(dynamic c, String emoji, String ust, String alt, Color renk) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: renk.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: renk.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$emoji $ust',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: c.text)),
          const SizedBox(height: 2),
          Text(alt,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: c.textDim)),
        ],
      ),
    );
  }
}

// ── Paylaşım görselindeki özellik sayıları (MERKEZÎ) ───────────────────────
// Statik metinler ama tek yerden gelsin ki ileride (ör. 20.000 → 25.000)
// güncellemek kolay olsun (kullanıcı isteği: AppConfig mantığı).
const int kOzellikDersSayisi = 7;
const int kOzellikKonuSayisi = 101;
const String kOzellikTestSayisi = '20.000+';
const int kOzellikOyunSayisi = 15;

/// Paylaşılacak davet GÖRSELİ — Instagram Story / WhatsApp için 9:16 (SABİT
/// 540×960 mantıksal; pixelRatio 2 ile 1080×1920 PNG). Koyu premium mor/lacivert
/// zemin, neon parıltılar, altın vurgular. TÜM dinamik alanlar (davet kodu +
/// sınavlara kalan günler) çizim ANINDA gerçek veriden hesaplanır; hiçbiri
/// sabit değildir. Statik alanlar (başlık, slogan, özellikler) yukarıdaki
/// sabitlerden/merkezî sınav takviminden gelir.
class _PaylasGorseli extends StatelessWidget {
  final String kod;
  const _PaylasGorseli({required this.kod});

  // Premium palet (görsel her zaman koyu premium; temadan bağımsız).
  static const _bgTop = Color(0xFF211452);
  static const _bgMid = Color(0xFF160E36);
  static const _bgBottom = Color(0xFF0A0820);
  static const _magenta = Color(0xFFE0219A);
  static const _violet = Color(0xFF8B5CF6);
  static const _gold = Color(0xFFFFD36E);
  static const _goldStrong = Color(0xFFFFC63D);
  static const _soft = Color(0xFFCBC2E8);

  Color get _cardBg => Colors.white.withValues(alpha: 0.055);
  Color get _cardBorder => Colors.white.withValues(alpha: 0.14);

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return SizedBox(
      width: 540,
      height: 960,
      child: Stack(
        children: [
          // ── Zemin: koyu mor→lacivert dikey gradyan ──
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [_bgTop, _bgMid, _bgBottom],
                  stops: [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
          // ── Neon parıltı blobları ──
          _glow(top: -70, right: -60, size: 260, color: _magenta, opacity: 0.30),
          _glow(top: 250, left: -80, size: 240, color: _violet, opacity: 0.28),
          _glow(bottom: 40, right: -70, size: 250, color: _magenta, opacity: 0.22),
          _glow(bottom: -60, left: -40, size: 220, color: _violet, opacity: 0.22),
          // ── İçerik ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 30),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 1) Başlık
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.asset('assets/images/logo.png',
                          width: 46, height: 46, fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                                width: 46, height: 46,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                    color: _violet.withValues(alpha: 0.30),
                                    borderRadius: BorderRadius.circular(12)),
                                child: const Icon(Icons.school_rounded,
                                    color: Colors.white, size: 26),
                              )),
                    ),
                    const SizedBox(width: 10),
                    const Text('KPSS Hazırlık',
                        style: TextStyle(
                            fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white)),
                  ],
                ),
                const SizedBox(height: 6),
                const Text('Soru Bankası • Konu Anlatımı • Deneme • Düello • Oyunlar',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11.5, color: _soft, letterSpacing: 0.2)),
                const SizedBox(height: 20),
                // 2) Slogan
                const Text('KPSS YOLCULUĞUNDA',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white,
                        letterSpacing: 0.4)),
                const Text('BİRLİKTE DAHA GÜÇLÜYÜZ!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 21, fontWeight: FontWeight.w900, color: _goldStrong,
                        letterSpacing: 0.3)),
                const SizedBox(height: 20),
                // 3) Davet kodu kartı (altın parıltılı)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        _gold.withValues(alpha: 0.20),
                        _magenta.withValues(alpha: 0.14),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: _gold.withValues(alpha: 0.55), width: 2),
                    boxShadow: [
                      BoxShadow(color: _gold.withValues(alpha: 0.22), blurRadius: 28, spreadRadius: 1),
                    ],
                  ),
                  child: Column(
                    children: [
                      const Text('DAVET KODUM',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w800,
                              letterSpacing: 3, color: _soft)),
                      const SizedBox(height: 6),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(kod,
                            style: const TextStyle(
                                fontSize: 50, fontWeight: FontWeight.w900,
                                letterSpacing: 8, color: Colors.white, height: 1.0)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // 4) Premium açıklaması (TAM METİN — kullanıcı isteği)
                Text.rich(
                  TextSpan(
                    style: const TextStyle(fontSize: 13.5, height: 1.35, color: Colors.white),
                    children: [
                      const TextSpan(
                          text:
                              'Bu kodla uygulamayı indirip yeni hesapla giriş yapana '),
                      TextSpan(
                          text: '1 gün premium hediye !',
                          style: const TextStyle(
                              color: _goldStrong, fontWeight: FontWeight.w900)),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                // 5) Özellik kartları
                Row(
                  children: [
                    Expanded(child: _statTile(Icons.menu_book_rounded, '$kOzellikDersSayisi', 'DERS', null)),
                    const SizedBox(width: 8),
                    Expanded(child: _statTile(Icons.auto_stories_rounded, '$kOzellikKonuSayisi', 'KONU', null)),
                    const SizedBox(width: 8),
                    Expanded(child: _statTile(Icons.fact_check_rounded, kOzellikTestSayisi, 'TEST', 'açıklamalı')),
                    const SizedBox(width: 8),
                    Expanded(child: _statTile(Icons.sports_esports_rounded, '$kOzellikOyunSayisi', 'OYUN', null)),
                  ],
                ),
                const SizedBox(height: 8),
                _wideTile(Icons.emoji_events_rounded, 'DENEME & DÜELLO',
                    'Kendini test et, rakiplerinle yarış!'),
                const SizedBox(height: 18),
                // 6) Sınavlara kalan süre
                const Text('SINAVLARA KALAN SÜRE',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800,
                        letterSpacing: 1.5, color: _gold)),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (int i = 0; i < kExamTypes.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(child: _examCard(kExamTypes[i], now)),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                // 7) Alt özellikler
                Row(
                  children: [
                    Expanded(child: _subFeature(Icons.insights_rounded, 'DETAYLI', 'İSTATİSTİK')),
                    Expanded(child: _subFeature(Icons.bookmark_added_rounded, 'KAYDET &', 'DEVAM ET')),
                    Expanded(child: _subFeature(Icons.record_voice_over_rounded, 'SESLİ ANLATIM', '(TTS)')),
                    Expanded(child: _subFeature(Icons.picture_as_pdf_rounded, 'PDF', 'ÇIKARIMI')),
                    Expanded(child: _subFeature(Icons.wifi_off_rounded, 'OFFLINE', 'ÇALIŞMA')),
                  ],
                ),
                const SizedBox(height: 18),
                // 8) CTA
                const Text('HEMEN İNDİR, KODU GİR',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white,
                        letterSpacing: 0.3)),
                const Text('KAZANMAYA BAŞLA!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 19, fontWeight: FontWeight.w900, color: _goldStrong)),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _storeBadge(Icons.apple, 'App Store'),
                    const SizedBox(width: 10),
                    _storeBadge(Icons.shop_rounded, 'Google Play'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Yumuşak radyal neon parıltı blobu.
  Widget _glow({
    double? top, double? left, double? right, double? bottom,
    required double size, required Color color, required double opacity,
  }) {
    return Positioned(
      top: top, left: left, right: right, bottom: bottom,
      child: IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [color.withValues(alpha: opacity), color.withValues(alpha: 0.0)],
            ),
          ),
        ),
      ),
    );
  }

  /// Özellik istatistik karesi: ikon + büyük sayı + etiket (+ küçük alt etiket).
  Widget _statTile(IconData icon, String number, String label, String? sub) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: _gold),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(number,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
          ),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  fontSize: 9.5, fontWeight: FontWeight.w800,
                  letterSpacing: 0.5, color: _soft)),
          if (sub != null)
            Text(sub,
                style: TextStyle(fontSize: 8, color: _soft.withValues(alpha: 0.7))),
        ],
      ),
    );
  }

  /// Geniş özellik kartı (Deneme & Düello).
  Widget _wideTile(IconData icon, String title, String subtitle) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          _violet.withValues(alpha: 0.22),
          _magenta.withValues(alpha: 0.16),
        ]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cardBorder),
      ),
      child: Row(
        children: [
          Icon(icon, size: 26, color: _gold),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w900, color: Colors.white)),
                const SizedBox(height: 1),
                Text(subtitle,
                    style: const TextStyle(fontSize: 10.5, color: _soft)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Sınav geri sayım kartı — gün sayısı ÇİZİM ANINDA hesaplanır (sabit değil).
  Widget _examCard(ExamInfo e, DateTime now) {
    final gun = daysUntilExam(e, now: now);
    final bugun = gun <= 0;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFE0219A).withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0219A).withValues(alpha: 0.45)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('KPSS ${e.label.toUpperCase()}',
                style: const TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w800,
                    letterSpacing: 0.3, color: _soft)),
          ),
          const SizedBox(height: 6),
          if (bugun)
            const Text('BUGÜN!',
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white))
          else ...[
            Text('$gun',
                style: const TextStyle(
                    fontSize: 32, fontWeight: FontWeight.w900,
                    color: Colors.white, height: 1.0)),
            const Text('GÜN KALDI',
                style: TextStyle(
                    fontSize: 9.5, fontWeight: FontWeight.w800,
                    letterSpacing: 0.5, color: _gold)),
          ],
        ],
      ),
    );
  }

  /// Alt küçük özellik: ikon + iki satır etiket.
  Widget _subFeature(IconData icon, String l1, String l2) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: _violet),
        const SizedBox(height: 4),
        Text(l1,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 8.5, fontWeight: FontWeight.w800, color: Colors.white)),
        Text(l2,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 8.5, color: _soft)),
      ],
    );
  }

  /// Mağaza rozeti (yalnızca etiket — sahte URL yok).
  Widget _storeBadge(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
        ],
      ),
    );
  }
}
