import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/badge.dart';
import '../services/storage_service.dart';
import '../theme/theme_provider.dart';

/// JS karşılığı: renderBadges() (src/js/app.js) + rozet tanımları src/js/badges.js.
class BadgesScreen extends StatelessWidget {
  const BadgesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final c = context.watch<ThemeProvider>().colors;
    final unlocked = storage.getUnlockedBadges().toSet();

    return Scaffold(
      appBar: AppBar(title: const Text('🎖 Rozetler')),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                '${unlocked.length} / ${kBadgeDefs.length} kazanıldı',
                style: TextStyle(fontSize: 13.5, color: c.textFaint),
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.82,
                ),
                itemCount: kBadgeDefs.length,
                itemBuilder: (context, i) {
                  final b = kBadgeDefs[i];
                  final isUnlocked = unlocked.contains(b.id);
                  return _BadgeCard(badge: b, unlocked: isUnlocked);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kazanılmış rozetler altın/parıltılı bir "madalya" hissi versin diye
/// gradyanlı çerçeve + köşede küçük bir altın rozet rüzgarı kullanılır;
/// kilitliler sade/gri kalır. Kart boyutu (3 sütunlu daha sık grid, 30x30
/// daire, 13px emoji, küçültülmüş padding/font) önceki 2 sütunlu tasarıma
/// göre ~%25-30 küçültüldü — ekranda daha fazla rozet aynı anda görünsün diye.
class _BadgeCard extends StatelessWidget {
  final BadgeDef badge;
  final bool unlocked;
  const _BadgeCard({required this.badge, required this.unlocked});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    // Kilitli rozet "sönük" görünsün ama zemine göre sönük olsun: sabit gri
    // açık temada da koyu temada da aynı kalıyordu.
    final medalColor = unlocked ? badge.color : c.textFaint;
    // Madalya çerçevesinin altın parıltısı artık temanın kendi altın tonundan.
    final gold = c.gold;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        gradient: unlocked
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [badge.color.withValues(alpha: 0.16), gold.withValues(alpha: 0.08)],
              )
            : null,
        color: unlocked ? null : Theme.of(context).cardColor.withValues(alpha: 0.5),
        border: Border.all(
          color: unlocked ? gold.withValues(alpha: 0.55) : Colors.transparent,
          width: 1,
        ),
        boxShadow: unlocked
            ? [BoxShadow(color: badge.color.withValues(alpha: 0.18), blurRadius: 8, offset: const Offset(0, 2))]
            : null,
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: medalColor.withValues(alpha: unlocked ? 0.2 : 0.12),
                    border: Border.all(color: medalColor.withValues(alpha: unlocked ? 0.6 : 0.3), width: 1.3),
                  ),
                  child: Center(
                    child: Opacity(
                      opacity: unlocked ? 1.0 : 0.35,
                      child: Text(badge.icon, style: const TextStyle(fontSize: 13)),
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  badge.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 9,
                    color: unlocked ? null : c.textFaint,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  badge.desc,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 7.5),
                ),
              ],
            ),
          ),
          if (unlocked)
            Positioned(
              top: 4,
              right: 4,
              child: Icon(Icons.workspace_premium, size: 11, color: gold.withValues(alpha: 0.9)),
            )
          else
            Positioned(
              top: 4,
              right: 4,
              child: Icon(Icons.lock, size: 10, color: c.textFaint),
            ),
        ],
      ),
    );
  }
}
