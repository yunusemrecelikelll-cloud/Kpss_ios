import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/subject.dart';
import '../../services/sound_service.dart';
import '../../services/storage_service.dart';
import '../../theme/subject_colors.dart';
import '../../theme/theme_provider.dart';
import '../learn_map/learn_map_hub_screen.dart';
import '../tools_hub_screen.dart' show formatPlayDuration;
import 'bolge_bul_mode.dart';
import 'hiz_modu.dart';
import 'iklim_avi_mode.dart';
import 'il_bul_mode.dart';
import 'il_fethi_mode.dart';
import 'komsu_il_mode.dart';
import 'map_shared.dart';
import 'tarih_haritasi_mode.dart';
import 'urun_haritasi_mode.dart';

/// Harita Oyunu — Türkiye haritası tabanlı TEK giriş noktalı hub: hem "Harita
/// Oyunu" (skorlu mini oyun modları) hem de "Haritadan Öğren" (puansız,
/// bilgi-amaçlı harita kütüphanesi, bkz. lib/screens/learn_map/) burada bir
/// arada listelenir — kullanıcı için ayrı bir "Haritadan Öğren" giriş noktası
/// YOKTUR (bkz. tools_hub_screen.dart, o karttan kaldırıldı).
/// "81 İl Fethi" bayrak mod olarak en üstte, ayrı ve daha büyük bir kartla
/// vurgulanır; diğer mini oyunlar günlük ortak hakka tabidir (bkz.
/// map_shared.dart — kMapGameId, kFreeGameDailyLimit).
class MapGameScreen extends StatelessWidget {
  final List<Subject> subjects;
  const MapGameScreen({super.key, required this.subjects});

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final colors = context.watch<ThemeProvider>().colors;
    final premium = storage.isPremiumUser();
    final left = mapGameDailyLeft(storage);
    final conquered = storage.getGamePassedTopics(kMapGameId).length;
    final totalSeconds = kAllMapModeIds.fold(0, (a, id) => a + storage.getGameTimeSpent(id));
    final totalLabel = totalSeconds > 0 ? formatPlayDuration(totalSeconds) : null;

    return Scaffold(
      appBar: AppBar(title: const Text('🗺️ Harita Oyunu')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            "Türkiye haritası üzerinde illeri, bölgeleri ve daha fazlasını keşfet, "
            'ya da "Haritadan Öğren" ile puansız çalış. '
            '${premium ? "Diğer mini oyunları sınırsız oynarsın." : "Diğer mini oyunlarda bugün $left hakkın kaldı."}',
            style: TextStyle(fontSize: 13.5, color: colors.textFaint),
          ),
          if (totalLabel != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.timer_outlined, size: 14, color: colors.textFaint),
                const SizedBox(width: 4),
                Text(
                  'Harita oyunlarında toplam $totalLabel oynadın',
                  style: TextStyle(fontSize: 12, color: colors.textFaint, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          _FlagshipCard(conquered: conquered, subjects: subjects, storage: storage),
          const SizedBox(height: 20),
          const _SectionTitle('📚 Haritadan Öğren'),
          const SizedBox(height: 10),
          _ModeTile(
            gameId: kHaritadanOgrenGameId,
            icon: '📚',
            title: 'Haritadan Öğren',
            desc: 'Tarım, hayvancılık, maden ve enerji haritalarıyla Türkiye coğrafyasını puansız öğren.',
            storage: storage,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LearnMapHubScreen())),
          ),
          const SizedBox(height: 20),
          const _SectionTitle('🎮 Mini Oyunlar'),
          const SizedBox(height: 10),
          _ModeTile(
            gameId: kIliBulGameId,
            icon: '🔎',
            title: 'İli Bul',
            desc: 'Söylenen ili haritada bul. Kolay/Orta/Zor seviyeleri.',
            storage: storage,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const IliBulScreen())),
          ),
          _ModeTile(
            gameId: kBolgeBulGameId,
            icon: '🧭',
            title: 'Bölgeyi Bul',
            desc: '7 coğrafi bölgeden istenen bölgeye ait bir il seç.',
            storage: storage,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BolgeyiBulScreen())),
          ),
          _ModeTile(
            gameId: kKomsuIlGameId,
            icon: '🤝',
            title: 'Komşu İl Oyunu',
            desc: 'Gösterilen ilin gerçek komşularından birini seç.',
            storage: storage,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const KomsuIlScreen())),
          ),
          _ModeTile(
            gameId: kUrunHaritasiGameId,
            icon: '🌾',
            title: 'Ürün Haritası',
            desc: 'Fındık, çay, pamuk gibi ürünlerin ilini bul.',
            storage: storage,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UrunHaritasiScreen())),
          ),
          _ModeTile(
            gameId: kTarihHaritasiGameId,
            icon: '🕰️',
            title: 'Tarih Haritası',
            desc: 'Millî Mücadele olaylarının yaşandığı ili işaretle.',
            storage: storage,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TarihHaritasiScreen())),
          ),
          _ModeTile(
            gameId: kIklimAviGameId,
            icon: '☀️',
            title: 'İklim Avı',
            desc: 'Yağış, sıcaklık, bitki örtüsü ipuçlarından ili bul.',
            storage: storage,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const IklimAviScreen())),
          ),
          _ModeTile(
            gameId: kHizliTurkiyeGameId,
            icon: '⏱️',
            title: '60 Saniyede Türkiye',
            desc: 'Karışık sorularla 60 saniyede skorunu katla.',
            storage: storage,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HizliTurkiyeScreen())),
          ),
        ],
      ),
    );
  }
}

class _FlagshipCard extends StatelessWidget {
  final int conquered;
  final List<Subject> subjects;
  final StorageService storage;
  const _FlagshipCard({required this.conquered, required this.subjects, required this.storage});

  @override
  Widget build(BuildContext context) {
    final colors = context.watch<ThemeProvider>().colors;
    final playedSeconds = storage.getGameTimeSpent(kIlFethiTimeGameId);
    final playedLabel = playedSeconds > 0 ? formatPlayDuration(playedSeconds) : null;
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: () {
        context.read<SoundService>().click();
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => IlFethiScreen(subjects: subjects)),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [colors.gold.withValues(alpha: 0.9), colors.rose.withValues(alpha: 0.85)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 16, offset: const Offset(0, 8))],
        ),
        child: Row(
          children: [
            const Text('👑', style: TextStyle(fontSize: 34)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '81 İl Fethi',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$conquered/81 il fethedildi • Günlük hak sınırı yok!'
                    '${playedLabel != null ? " • $playedLabel oynadın" : ""}',
                    style: const TextStyle(fontSize: 12.5, color: Colors.white70),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800));
}

class _ModeTile extends StatelessWidget {
  final String gameId;
  final String icon;
  final String title;
  final String desc;
  final StorageService storage;
  final VoidCallback onTap;
  const _ModeTile({
    required this.gameId,
    required this.icon,
    required this.title,
    required this.desc,
    required this.storage,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.watch<ThemeProvider>().colors;
    final palette = mapModePaletteFor(gameId);
    final playedSeconds = storage.getGameTimeSpent(gameId);
    final playedLabel = playedSeconds > 0 ? formatPlayDuration(playedSeconds) : null;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: subjectCardDecoration(palette: palette, isLight: colors.isLight),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            context.read<SoundService>().click();
            onTap();
          },
          child: ListTile(
            leading: Text(icon, style: const TextStyle(fontSize: 22)),
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(playedLabel != null ? '$desc\n🕒 $playedLabel oynadın' : desc),
            isThreeLine: playedLabel != null,
            trailing: const Icon(Icons.chevron_right),
          ),
        ),
      ),
    );
  }
}
