import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/ad_service.dart';
import '../services/purchase_service.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../theme/design_system.dart';
import '../theme/theme_provider.dart';

/// "Hak Satın Al" ekranı — Ayarlar'dan açılır.
///
/// Kullanıcı burada:
///  • Cüzdanındaki mevcut hakkı görür,
///  • [kHakPaketiMiktar] haklık tüketilebilir paketi satın alır (tekrar tekrar),
///  • ya da ödüllü reklam izleyip +[AdService.odulKrediSayisi] hak kazanır.
///
/// Hak = evrensel kredi: oyunlarda ekstra oynama ve tam deneme sınavı tekrarı
/// için istenen yerde harcanır (sohbet/DM HARİÇ). Premium kullanıcıda bu ekran
/// ve tüm hak/reklam sistemi GİZLİDİR (sınırsız) — çağıran taraf premium'u
/// kontrol eder; burada da bir güvenlik notu gösterilir.
class HakSatinAlScreen extends StatefulWidget {
  const HakSatinAlScreen({super.key});

  @override
  State<HakSatinAlScreen> createState() => _HakSatinAlScreenState();
}

class _HakSatinAlScreenState extends State<HakSatinAlScreen> {
  late final PurchaseService _purchases;
  bool _reklamOynatiliyor = false;

  @override
  void initState() {
    super.initState();
    _purchases = PurchaseService(context.read<StorageService>());
    _purchases.addListener(_degisti);
    _purchases.init();
  }

  void _degisti() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _purchases.removeListener(_degisti);
    _purchases.dispose();
    super.dispose();
  }

  Future<void> _satinAl() async {
    context.read<SoundService>().click();
    if (_purchases.status == PurchaseServiceStatus.unavailable) {
      _mesaj('Mağaza şu an kullanılamıyor. Daha sonra tekrar dene.');
      return;
    }
    await _purchases.buy(kHakPaketiId);
    if (!mounted) return;
    if (_purchases.status == PurchaseServiceStatus.error) {
      _mesaj(_purchases.lastError ?? 'Satın alma başarısız oldu.');
    }
  }

  Future<void> _reklamIzle() async {
    final storage = context.read<StorageService>();
    context.read<SoundService>().click();
    setState(() => _reklamOynatiliyor = true);
    final kazandi = await AdService.instance.odulluReklamGoster();
    if (kazandi) {
      await storage.hakEkle(AdService.odulKrediSayisi);
    }
    if (!mounted) return;
    setState(() => _reklamOynatiliyor = false);
    _mesaj(kazandi
        ? '+${AdService.odulKrediSayisi} hak kazandın! 🎉'
        : 'Reklam şu an gösterilemedi. Birazdan tekrar dene.');
  }

  void _mesaj(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final storage = context.watch<StorageService>();
    final premium = storage.isPremiumUser();
    final haklar = storage.getHaklar();
    final urun = _purchases.productFor(kHakPaketiId);
    final fiyat = urun?.price ?? '9,99 ₺';

    return Scaffold(
      appBar: AppBar(title: const Text('🎟️ Hak Satın Al')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Cüzdan.
            DsCard(
              accent: c.gold,
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  DsIconBadge(emoji: '🎟️', color: c.gold, size: 48, glow: false),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Mevcut hakkın',
                            style: TextStyle(fontSize: 12, color: c.textFaint)),
                        const SizedBox(height: 2),
                        Text('$haklar hak',
                            style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: c.text)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '1 hak = 1 ekstra oyun hakkı ya da 1 deneme sınavı tekrarı. '
              'İstediğin yerde kullanabilirsin.',
              style: TextStyle(fontSize: 12, height: 1.4, color: c.textFaint),
            ),
            const SizedBox(height: 16),

            if (premium)
              DsCard(
                accent: c.gold,
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Text('👑', style: const TextStyle(fontSize: 22)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Premium üyesin — her şey zaten sınırsız ve reklamsız. '
                        'Hak satın almana gerek yok.',
                        style: TextStyle(fontSize: 13, height: 1.4, color: c.text),
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              // Satın alınabilir paket.
              DsCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        DsIconBadge(emoji: '🎁', color: c.violet, size: 44, glow: false),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('$kHakPaketiMiktar Hak Paketi',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16,
                                      color: c.text)),
                              const SizedBox(height: 2),
                              Text('Tek seferlik — istediğin kadar alabilirsin',
                                  style: TextStyle(fontSize: 11.5, color: c.textFaint)),
                            ],
                          ),
                        ),
                        Text(fiyat,
                            style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                                color: c.gold)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    DsPillButton(
                      label: _purchases.status == PurchaseServiceStatus.purchasing
                          ? 'İşleniyor…'
                          : '$kHakPaketiMiktar Hak Satın Al',
                      color: c.gold,
                      leadingIcon: Icons.shopping_cart_checkout_rounded,
                      onPressed:
                          _purchases.status == PurchaseServiceStatus.purchasing
                              ? null
                              : _satinAl,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Reklamla ücretsiz hak.
              DsCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ücretsiz hak',
                        style: TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 14, color: c.text)),
                    const SizedBox(height: 4),
                    Text(
                      'Reklam izleyerek +${AdService.odulKrediSayisi} hak kazan. '
                      'Reklam yalnızca butona bastığında çıkar.',
                      style: TextStyle(fontSize: 12, height: 1.4, color: c.textFaint),
                    ),
                    const SizedBox(height: 12),
                    DsPillButton(
                      label: _reklamOynatiliyor
                          ? 'Reklam yükleniyor…'
                          : 'Reklam İzle (+${AdService.odulKrediSayisi} Hak)',
                      color: c.violet,
                      filled: false,
                      leadingIcon: Icons.slideshow_rounded,
                      onPressed: _reklamOynatiliyor ? null : _reklamIzle,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
