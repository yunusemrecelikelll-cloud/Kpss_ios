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
  /// davet koduyla gelince ne olduğu yazsın). Görsel ekran DIŞINDA (off-screen)
  /// çizilip PNG olarak yakalanır, geçici dosyaya yazılıp paylaşılır.
  Future<void> _gorselPaylas() async {
    if (_kod == null) return;
    context.read<SoundService>().click();
    final c = context.read<ThemeProvider>().colors;
    // Her paylaşımda FARKLI motivasyon (kullanıcı isteği) — görsel ve metinde aynı.
    final motivasyon = _rastgeleMotivasyon();
    final boundaryKey = GlobalKey();
    final overlay = Overlay.of(context);
    final entry = OverlayEntry(
      builder: (_) => Positioned(
        left: -3000, // ekran dışı ama boyanır
        top: 0,
        child: Material(
          type: MaterialType.transparency,
          child: RepaintBoundary(
            key: boundaryKey,
            child: _PaylasGorseli(kod: _kod!, c: c, motivasyon: motivasyon),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    try {
      // Bir-iki kare bekle ki off-screen widget boyanmış olsun.
      await Future.delayed(const Duration(milliseconds: 350));
      final boundary = boundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        entry.remove();
        return;
      }
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      entry.remove();
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/kpss_davet_$_kod.png');
      await file.writeAsBytes(bytes.buffer.asUint8List());
      await Share.shareXFiles([XFile(file.path)], text: _davetMetni(motivasyon));
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

/// Paylaşılacak davet GÖRSELİ (off-screen çizilip PNG'e dönüştürülür): gradyanlı
/// kart, uygulama adı, büyük davet kodu, "davet koduyla gelince ne olur" ve
/// uygulama içeriği. Sabit boyutlu (paylaşımda net görünsün).
class _PaylasGorseli extends StatelessWidget {
  final String kod;
  final dynamic c;
  final String motivasyon;
  const _PaylasGorseli({required this.kod, required this.c, required this.motivasyon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 420,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(c.violet.withValues(alpha: 0.35), const Color(0xFF120A22)),
            Color.alphaBlend(c.violetL.withValues(alpha: 0.20), const Color(0xFF0B0715)),
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text('📚 KPSS Hazırlık',
              style: TextStyle(
                  fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white)),
          const SizedBox(height: 6),
          const Text('Soru Bankası · Konu Anlatımı · Deneme · Düello · Oyunlar',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Color(0xFFCFC6E6))),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
            ),
            child: Column(
              children: [
                const Text('DAVET KODUM',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                        color: Color(0xFFCFC6E6))),
                const SizedBox(height: 6),
                Text(kod,
                    style: const TextStyle(
                        fontSize: 44,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 8,
                        color: Colors.white)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // ── Sınavlara kalan süre (motivasyon) ──
          Builder(builder: (_) {
            final now = DateTime.now();
            // En yakın sınava kalan gün — başlık motivasyonu için.
            int? enYakinGun;
            for (final e in kExamTypes) {
              final g = nextExamDate(e, now: now).difference(
                  DateTime(now.year, now.month, now.day)).inDays;
              if (enYakinGun == null || g < enYakinGun) enYakinGun = g;
            }
            return Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE11D48).withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE11D48).withValues(alpha: 0.5)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        enYakinGun != null
                            ? '⏳ İlk KPSS sınavına yalnızca $enYakinGun gün kaldı!'
                            : '⏳ KPSS yaklaşıyor!',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        motivasyon,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12.5, height: 1.35, color: Color(0xFFF3D6DE)),
                      ),
                      const SizedBox(height: 10),
                      for (final e in kExamTypes)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('KPSS ${e.label}',
                                  style: const TextStyle(
                                      fontSize: 12.5, fontWeight: FontWeight.w700,
                                      color: Colors.white)),
                              Text(
                                  formatCountdown(nextExamDate(e, now: now), now: now),
                                  style: const TextStyle(
                                      fontSize: 12.5, fontWeight: FontWeight.w900,
                                      color: Color(0xFFFFD9A6))),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
            );
          }),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFD97706).withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFD97706).withValues(alpha: 0.5)),
            ),
            child: const Text(
              '🎁 Bu kodla uygulamayı indirip YENİ hesapla giriş yapana da, '
              'beni davet edene de 1’er GÜN PREMIUM!',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14, height: 1.4, fontWeight: FontWeight.w700, color: Colors.white),
            ),
          ),
          const SizedBox(height: 16),
          const Text('20.000+ soru • konu anlatımı • deneme • düello • ücretsiz',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Color(0xFFB7ADCE))),
        ],
      ),
    );
  }
}
