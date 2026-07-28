import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/sound_service.dart';
import '../theme/design_system.dart';
import '../theme/theme_provider.dart';

/// ÖSYM'nin resmî sitesi — sınav takvimi/başvuru/duyurular için.
const String kOsymUrl = 'https://www.osym.gov.tr';

/// Resmî kurum FERAGATI metni.
///
/// AMAÇ: Play Console / App Store, KPSS gibi devlet sınavlarıyla ilgili
/// uygulamaların "resmî bir devlet uygulaması" izlenimi vermesini istemiyor
/// (aksi hâlde yalnızca kurumsal/doğrulanmış hesaplar dağıtabiliyor). Bu açık
/// beyan, uygulamanın BAĞIMSIZ olduğunu net söyler; görünür bir yere
/// (Ayarlar > Hakkında) ve ilk açılışa konur, yanında tıklanabilir ÖSYM linki
/// bulunur.
const String kResmiKurumFeragati =
    'Bu uygulama bağımsız olarak geliştirilmiştir; ÖSYM veya herhangi bir resmî '
    'devlet kurumuyla bağlantılı, onlar tarafından desteklenen ya da onaylanan '
    'bir uygulama değildir. "KPSS" adı yalnızca ilgili sınavın tanımlanması '
    'amacıyla kullanılmaktadır. Sınav takvimi, başvuru ve resmî duyurular için '
    'ÖSYM\'nin resmî web sitesini ziyaret et.';

/// Resmî kurum feragatı + tıklanabilir "ÖSYM resmî sitesini aç" butonu.
///
/// [kompakt] true iken başlıksız, kartsız (ör. ilk açılış tanıtımında)
/// gösterilir; false iken (varsayılan) başlıklı bir [DsCard] içinde.
class ResmiKurumFeragati extends StatelessWidget {
  final bool kompakt;
  const ResmiKurumFeragati({super.key, this.kompakt = false});

  Future<void> _osymAc(BuildContext context) async {
    context.read<SoundService>().click();
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final acildi = await launchUrl(
        Uri.parse(kOsymUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!acildi) {
        messenger?.showSnackBar(
          const SnackBar(content: Text('Bağlantı açılamadı: $kOsymUrl')),
        );
      }
    } catch (_) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('Bağlantı açılamadı: $kOsymUrl')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;

    final metin = Text(
      kResmiKurumFeragati,
      style: TextStyle(fontSize: 12.5, height: 1.5, color: c.textDim),
    );
    final buton = DsPillButton(
      label: 'ÖSYM resmî sitesini aç',
      color: c.violet,
      leadingIcon: Icons.open_in_new,
      onPressed: () => _osymAc(context),
    );

    if (kompakt) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          metin,
          const SizedBox(height: 12),
          Align(alignment: Alignment.centerLeft, child: buton),
        ],
      );
    }

    return DsCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              DsIconBadge(emoji: '⚠️', color: c.warn, size: 34, circle: false, glow: false),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Resmî kurum bağlantısı yoktur',
                  style: TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 13.5, color: c.text),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          metin,
          const SizedBox(height: 12),
          Align(alignment: Alignment.centerLeft, child: buton),
        ],
      ),
    );
  }
}
