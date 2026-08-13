import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../screens/account_login_screen.dart';
import '../services/auth_service.dart';
import '../services/invite_service.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../theme/design_system.dart';
import '../theme/theme_provider.dart';
import '../utils/ust_bildirim.dart';

/// Anasayfa "Davet Et & Kazan" kartı (kullanıcı isteği):
/// - Kullanıcının kendi davet kodu + kopyala/paylaş.
/// - "Nasıl yapılır" adımları.
/// - Her davetten kazanılanlar: **+50 hak** ve **1 gün premium**.
/// - Şu ana kadar davetlerden kazanılan toplam (kişi + hak).
/// - Bonus premium KALAN süresi (saat:dakika, canlı sayar).
///
/// Yalnızca GİRİŞ YAPMIŞ kullanıcıda anlamlıdır (kod hesaba bağlı); giriş yoksa
/// kısa bir "giriş yap" yönlendirmesi gösterir.
class DavetKazanKarti extends StatefulWidget {
  const DavetKazanKarti({super.key});

  @override
  State<DavetKazanKarti> createState() => _DavetKazanKartiState();
}

class _DavetKazanKartiState extends State<DavetKazanKarti> {
  final _invite = InviteService();
  String? _kod;
  bool _yukleniyor = true;
  Timer? _saat; // kalan premium süreyi dakikada bir tazeler

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
    Clipboard.setData(ClipboardData(
        text: 'KPSS Hazırlık uygulamasına davet kodum: $_kod\n'
            'Uygulamayı indir, girişte bu kodu gir; ikimiz de kazanalım!'));
    ustBildirim('Davet mesajı kopyalandı — arkadaşlarına gönder!',
        tur: UstBildirimTuru.basari);
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
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                DsIconBadge(
                    icon: Icons.card_giftcard_rounded, color: c.gold, size: 40, glow: false),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Davet Et & Kazan',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w900, color: c.text)),
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

    return DsCard(
      accent: c.gold,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DsIconBadge(icon: Icons.card_giftcard_rounded, color: c.gold, size: 40, glow: false),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Davet Et & Kazan',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w900, color: c.text)),
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
          const SizedBox(height: 12),
          // Davet kodu
          if (_yukleniyor)
            Center(child: Padding(
              padding: const EdgeInsets.all(8),
              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: c.gold)),
            ))
          else if (_kod != null)
            InkWell(
              onTap: _kopyala,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: c.glass2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.border),
                ),
                child: Row(
                  children: [
                    Text('Kodun:', style: TextStyle(fontSize: 12.5, color: c.textDim)),
                    const SizedBox(width: 8),
                    Text(_kod!,
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w900,
                            letterSpacing: 4, color: c.text)),
                    const Spacer(),
                    Icon(Icons.copy_rounded, size: 18, color: c.violetL),
                    const SizedBox(width: 4),
                    Text('Paylaş', style: TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w800, color: c.violetL)),
                  ],
                ),
              ),
            )
          else
            Text('Davet kodu yüklenemedi, internetini kontrol et.',
                style: TextStyle(fontSize: 12, color: c.textFaint)),
          const SizedBox(height: 12),
          // Kazanımlar + kalan premium
          Row(
            children: [
              Expanded(
                child: _ozet(c, '👥', '$kazananSayi kişi',
                    '$kazananSayi gün premium kazandın'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: premiumKalan > Duration.zero
                    ? _ozet(c, '💎', 'Premium aktif', 'Kalan: ${_kalanSure(premiumKalan)}')
                    : _ozet(c, '💎', 'Premium yok', 'Davet et, 1 gün kazan'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _ozet(dynamic c, String emoji, String ust, String alt) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: c.glass,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$emoji $ust',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: c.text)),
          const SizedBox(height: 2),
          Text(alt,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: c.textDim)),
        ],
      ),
    );
  }
}
