import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/study_plan_screen.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../services/study_plan_service.dart';
import '../theme/design_system.dart';
import '../theme/theme_provider.dart';

/// ─────────────────────────────────────────────────────────────────────────
/// Anasayfa: Günlük Çalışma Planı kartı
/// ─────────────────────────────────────────────────────────────────────────
///
/// Parametresizdir (`const StudyPlanCard()`) — anasayfadaki listeye olduğu gibi
/// bırakılabilir. Gerekli her şeyi Provider'dan okur:
///   • Plan varsa → bir sonraki seans ("Bugün 19:00–20:30" + kalan süre)
///   • Plan yoksa → "Çalışma planı oluştur" daveti
///   • Her iki durumda da tek satırlık ders önerisi
///
/// [StorageService] `watch` edildiği için plan ekranından dönüldüğünde kart
/// kendiliğinden tazelenir.
class StudyPlanCard extends StatelessWidget {
  const StudyPlanCard({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final storage = context.watch<StorageService>();
    final servis = StudyPlanService(storage);

    final sonraki = servis.nextSession();
    final planVar = servis.getPlan().isNotEmpty;

    // Vurgu rengi: seans şu an devam ediyorsa dikkat çeken yeşil, aksi hâlde
    // uygulamanın birincil mor tonu.
    final vurgu = sonraki?.suAnDevamEdiyor == true ? c.success : c.violet;

    final baslik = sonraki != null
        ? servis.nextSessionLabel()
        : (planVar ? 'Planın kapalı' : 'Çalışma planı oluştur');

    final altSatir = sonraki != null
        ? servis.nextSessionCountdown()
        : (planVar
            ? 'Günlerini tekrar açmak için dokun'
            : 'Gününü ve saatini seç, tam o saatte hatırlatayım');

    return DsCard(
      accent: vurgu,
      onTap: () {
        try {
          context.read<SoundService>().click();
        } catch (_) {
          // Ses servisi yoksa sessizce geç.
        }
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const StudyPlanScreen()),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              DsIconBadge(
                emoji: sonraki != null ? '⏰' : '🗓️',
                color: vurgu,
                size: 48,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            baslik,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: c.text,
                            ),
                          ),
                        ),
                        if (sonraki?.suAnDevamEdiyor == true) ...[
                          const SizedBox(width: 8),
                          DsChip(label: 'ŞİMDİ', color: c.success),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      altSatir,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, height: 1.35, color: c.textFaint),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, size: 20, color: c.textDim),
            ],
          ),
          const SizedBox(height: 10),
          // Ders önerisi — tek satır, taşmaya karşı kırpılır.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(kDsRadiusSm),
              color: c.glass2,
              border: Border.all(color: c.border),
            ),
            child: Text(
              servis.shortSuggestionText(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: c.textDim,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
