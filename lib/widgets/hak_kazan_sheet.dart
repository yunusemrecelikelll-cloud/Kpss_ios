import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/ad_service.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../screens/premium_screen.dart';
import '../theme/design_system.dart';
import '../theme/theme_provider.dart';

/// "Hakkın doldu" alt sayfası — ücretsiz limit bittiğinde gösterilir.
///
/// Kullanıcı BUTONA BASMADAN reklam çıkmaz (istek): burada iki yol var —
///  1. Ödüllü reklam izle → +[AdService.odulKrediSayisi] hak,
///  2. Elindeki haktan [maliyet] kadar harcayıp devam et.
/// Ayrıca "Premium'a Geç" (sınırsız + reklamsız).
///
/// DÖNÜŞ: kullanıcı [maliyet] kadar hakkı BAŞARIYLA harcadıysa `true` —
/// çağıran taraf ekstra hakkı kendi bağlamına ekleyip (oyun/deneme) devam
/// eder. Aksi halde `false`.
///
/// ÖNEMLİ: Bu sayfa yalnızca ÜCRETSİZ kullanıcıya gösterilmelidir; çağıran
/// taraf premium'u önceden kontrol eder (premium = sınırsız, hiç reklam yok).
Future<bool> hakKazanSheet(
  BuildContext context, {
  required String baslik,
  required String aciklama,
  int maliyet = 1,
}) async {
  final sonuc = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _HakKazanSheet(
      baslik: baslik,
      aciklama: aciklama,
      maliyet: maliyet,
    ),
  );
  return sonuc ?? false;
}

class _HakKazanSheet extends StatefulWidget {
  final String baslik;
  final String aciklama;
  final int maliyet;
  const _HakKazanSheet({
    required this.baslik,
    required this.aciklama,
    required this.maliyet,
  });

  @override
  State<_HakKazanSheet> createState() => _HakKazanSheetState();
}

class _HakKazanSheetState extends State<_HakKazanSheet> {
  bool _reklamOynatiliyor = false;

  Future<void> _reklamIzle() async {
    final storage = context.read<StorageService>();
    final messenger = ScaffoldMessenger.of(context);
    context.read<SoundService>().click();
    setState(() => _reklamOynatiliyor = true);
    final kazandi = await AdService.instance.odulluReklamGoster();
    if (kazandi) {
      await storage.hakEkle(AdService.odulKrediSayisi);
    }
    if (!mounted) return;
    setState(() => _reklamOynatiliyor = false);
    if (!kazandi) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Reklam şu an gösterilemedi. Birazdan tekrar dene.'),
      ));
    } else {
      messenger.showSnackBar(SnackBar(
        content: Text('+${AdService.odulKrediSayisi} hak kazandın! 🎉'),
      ));
    }
  }

  Future<void> _hakHarcaVeDevam() async {
    final storage = context.read<StorageService>();
    context.read<SoundService>().click();
    final oldu = await storage.hakHarca(widget.maliyet);
    if (!mounted) return;
    Navigator.of(context).pop(oldu);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final haklar = context.watch<StorageService>().getHaklar();
    final yeterli = haklar >= widget.maliyet;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: DsIconBadge(emoji: '🎟️', color: c.gold, size: 52, glow: false)),
            const SizedBox(height: 12),
            Text(widget.baslik,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w900, color: c.text)),
            const SizedBox(height: 6),
            Text(widget.aciklama,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, height: 1.4, color: c.textFaint)),
            const SizedBox(height: 14),

            // Cüzdan durumu.
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
              decoration: BoxDecoration(
                color: c.gold.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(kDsRadiusSm),
                border: Border.all(color: c.gold.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('🎟️', style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                  Text('Hakların: $haklar',
                      style: TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 14, color: c.text)),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 1) Reklam izle (+2 hak).
            DsPillButton(
              label: _reklamOynatiliyor
                  ? 'Reklam yükleniyor…'
                  : 'Reklam İzle (+${AdService.odulKrediSayisi} Hak)',
              color: c.violet,
              leadingIcon: Icons.slideshow_rounded,
              onPressed: _reklamOynatiliyor ? null : _reklamIzle,
            ),
            const SizedBox(height: 10),

            // 2) Hakla devam et.
            DsPillButton(
              label: yeterli
                  ? '${widget.maliyet} Hak Kullan ve Devam Et'
                  : 'Yeterli hakkın yok',
              color: c.mint,
              filled: false,
              leadingIcon: Icons.play_arrow_rounded,
              onPressed: yeterli ? _hakHarcaVeDevam : null,
            ),
            const SizedBox(height: 10),

            // 3) Premium.
            DsPillButton(
              label: 'Premium\'a Geç (Sınırsız + Reklamsız)',
              color: c.gold,
              filled: false,
              leadingIcon: Icons.workspace_premium_rounded,
              onPressed: () {
                context.read<SoundService>().click();
                Navigator.of(context).pop(false);
                Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PremiumScreen()));
              },
            ),
          ],
        ),
      ),
    );
  }
}
